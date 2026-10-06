import AppKit
import AVFoundation

/// Зеркало: камера, которую включают на минуту — посмотреть на себя
/// перед звонком.
///
/// Камера работает только пока модуль на экране. Зелёный огонёк у камеры
/// пользователь видит сразу, и гореть ему, когда панель закрыта, нельзя.
@MainActor
final class MirrorStore: ObservableObject {
    enum Access: Equatable {
        case unknown
        case granted
        case denied
        /// Камеры нет вовсе — ни встроенной, ни подключённой.
        case noCamera
        /// Запущено не бандлом: без `NSCameraUsageDescription` запрос
        /// доступа не откажет, а уронит процесс.
        case unavailable
    }

    @Published private(set) var access: Access = .unknown

    let camera = MirrorCamera()

    private static var isProperlyBundled: Bool {
        Bundle.main.bundleIdentifier != nil
            && Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil
    }

    /// Модуль на экране — включаем, если можно.
    func resume() {
        refreshAccess()
        if access == .granted { camera.start() }
    }

    /// Модуль ушёл: панель свернулась или выбрали другую вкладку.
    func suspend() {
        camera.stop()
    }

    func requestAccess() {
        guard access == .unknown else { return }
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            // Пока шёл диалог, панель могли закрыть — тогда `resume`
            // случится сам при следующем показе.
            refreshAccess()
            if access == .granted, camera.isWanted { camera.start() }
        }
    }

    /// Перечитывает разрешение: его могли выдать или отобрать в Системных
    /// настройках, пока панель была закрыта.
    func refreshAccess() {
        guard Self.isProperlyBundled else {
            access = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            access = MirrorCamera.preferredDevice == nil ? .noCamera : .granted
        case .denied, .restricted:
            access = .denied
        default:
            access = .unknown
        }
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Сессия захвата и слой превью к ней.
///
/// `startRunning` блокирует поток на сотни миллисекунд, поэтому всё, что
/// трогает сессию, идёт по своей последовательной очереди: включение и
/// выключение встают в неё в том же порядке, в каком их попросили, и
/// быстрое «открыл — закрыл» не оставит камеру включённой.
final class MirrorCamera: @unchecked Sendable {
    /// Слой заводится один раз и переезжает в каждое новое представление.
    let previewLayer: AVCaptureVideoPreviewLayer

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "notch.mirror.session")
    private var isConfigured = false
    /// Чего хочет панель — читается на главном потоке.
    @MainActor private(set) var isWanted = false

    /// Камера, которую система считает основной (её же возьмёт и звонок);
    /// если такой нет — любая видеокамера.
    static var preferredDevice: AVCaptureDevice? {
        AVCaptureDevice.systemPreferredCamera ?? AVCaptureDevice.default(for: .video)
    }

    init() {
        // Без автоматического соединения: его заводим сами, чтобы
        // отзеркалить картинку, — иначе система решает за нас.
        previewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        previewLayer.videoGravity = .resizeAspectFill
    }

    @MainActor func start() {
        isWanted = true
        queue.async { [self] in
            configureIfNeeded()
            guard isConfigured, !session.isRunning else { return }
            session.startRunning()
        }
    }

    @MainActor func stop() {
        isWanted = false
        queue.async { [self] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured,
              let device = Self.preferredDevice,
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
        guard session.canAddInput(input) else { return }
        session.addInputWithNoConnections(input)

        guard let port = input.ports.first(where: { $0.mediaType == .video }) else { return }
        let connection = AVCaptureConnection(inputPort: port, videoPreviewLayer: previewLayer)
        // Зеркало — значит, как в зеркале: поднял правую руку — справа.
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        guard session.canAddConnection(connection) else { return }
        session.addConnection(connection)
        isConfigured = true
    }
}
