import AVFoundation
import SwiftUI

/// Зеркало: превью камеры, чтобы глянуть на себя перед звонком.
struct MirrorModule: NotchModule {
    let id = "mirror"
    let titleKey: L10n.Key = .moduleMirror
    let symbol = "web.camera"

    let store: MirrorStore

    func makeContent() -> some View {
        MirrorContent(store: store)
    }
}

private struct MirrorContent: View {
    @ObservedObject var store: MirrorStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        content
            // Панель вынимает содержимое из дерева и при сворачивании, и при
            // смене вкладки, и при открытии настроек — так что видимость
            // модуля и есть его `onAppear`/`onDisappear`.
            .onAppear { store.resume() }
            .onDisappear { store.suspend() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.access {
        case .unknown:
            VStack(spacing: 8) {
                Image(systemName: "web.camera")
                    .font(.system(size: 20))
                    .foregroundStyle(NotchTheme.textTertiary)
                Text(settings.t(.mirrorAskTitle))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NotchTheme.textSecondary)
                PromptButton(title: settings.t(.mirrorAskButton)) { store.requestAccess() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .denied:
            VStack(spacing: 8) {
                EmptyState(
                    symbol: "video.slash",
                    title: settings.t(.mirrorDeniedTitle),
                    hint: settings.t(.mirrorDeniedHint)
                )
                PromptButton(title: settings.t(.mirrorOpenSettings)) {
                    store.openSystemSettings()
                }
                .padding(.bottom, 6)
            }
        case .noCamera:
            EmptyState(
                symbol: "video.slash",
                title: settings.t(.mirrorNoCameraTitle),
                hint: settings.t(.mirrorNoCameraHint)
            )
        case .unavailable:
            EmptyState(
                symbol: "video.slash",
                title: settings.t(.mirrorUnbundledTitle),
                hint: settings.t(.mirrorUnbundledHint)
            )
        case .granted:
            preview
        }
    }

    /// Кадр целиком, 16:9, как его увидит собеседник, — а не полоса во
    /// всю ширину панели, где от лица остались бы глаза.
    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return ZStack {
            // Видна, пока камера просыпается: первые кадры приходят не сразу.
            Image(systemName: "web.camera")
                .font(.system(size: 20))
                .foregroundStyle(NotchTheme.textTertiary)
            CameraPreview(layer: store.camera.previewLayer)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .background(Color.white.opacity(0.05), in: shape)
        .clipShape(shape)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Слой превью из `AVFoundation` внутри SwiftUI.
private struct CameraPreview: NSViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> PreviewHost {
        let view = PreviewHost()
        view.previewLayer = layer
        return view
    }

    func updateNSView(_ view: PreviewHost, context: Context) {}

    final class PreviewHost: NSView {
        var previewLayer: AVCaptureVideoPreviewLayer? {
            didSet {
                guard let previewLayer else { return }
                wantsLayer = true
                layer?.addSublayer(previewLayer)
                needsLayout = true
            }
        }

        override func layout() {
            super.layout()
            // Без неявной анимации: иначе слой догоняет рамку с опозданием.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer?.frame = bounds
            CATransaction.commit()
        }
    }
}

/// Кнопка под запросом разрешения — такая же, как у Календаря.
private struct PromptButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(NotchTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(NotchTheme.accentSelection))
    }
}
