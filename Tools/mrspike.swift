import Foundation

// Разведка MediaRemote: отличаем «нет сессии» от «доступ закрыт».
// Запускать во время воспроизведения.

let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
guard let handle = dlopen(path, RTLD_NOW) else {
    print("dlopen: НЕ ОТКРЫЛСЯ — \(String(cString: dlerror()))")
    exit(0)
}
print("dlopen: ок")

func symbol(_ name: String) -> UnsafeMutableRawPointer? { dlsym(handle, name) }

// 1. Играет ли что-нибудь по мнению системы.
if let sym = symbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
    typealias IsPlaying = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    let call = unsafeBitCast(sym, to: IsPlaying.self)
    let done = DispatchSemaphore(value: 0)
    var playing: Bool?
    call(DispatchQueue.global()) { playing = $0; done.signal() }
    if done.wait(timeout: .now() + 3) == .timedOut {
        print("isPlaying: ТАЙМАУТ")
    } else {
        print("isPlaying: \(playing == true ? "ДА" : "нет")")
    }
} else {
    print("isPlaying: символа нет")
}

// 2. Кто владелец сессии.
if let sym = symbol("MRMediaRemoteGetNowPlayingApplicationPID") {
    typealias GetPID = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void
    let call = unsafeBitCast(sym, to: GetPID.self)
    let done = DispatchSemaphore(value: 0)
    var pid: Int32 = -1
    call(DispatchQueue.global()) { pid = $0; done.signal() }
    if done.wait(timeout: .now() + 3) == .timedOut {
        print("владелец: ТАЙМАУТ")
    } else {
        let name = pid > 0
            ? (try? Process.run(URL(fileURLWithPath: "/bin/echo"), arguments: [])) .map { _ in "" } ?? ""
            : ""
        _ = name
        print("владелец: pid \(pid)")
    }
} else {
    print("владелец: символа нет")
}

// 3. Метаданные трека.
if let sym = symbol("MRMediaRemoteGetNowPlayingInfo") {
    typealias GetInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    let call = unsafeBitCast(sym, to: GetInfo.self)
    let done = DispatchSemaphore(value: 0)
    var info: [String: Any]?
    call(DispatchQueue.global()) { info = $0; done.signal() }
    if done.wait(timeout: .now() + 4) == .timedOut {
        print("метаданные: ТАЙМАУТ")
    } else if let info, !info.isEmpty {
        print("метаданные: ЕСТЬ, ключей \(info.count)")
        for key in info.keys.sorted() { print("   \(key)") }
    } else {
        print("метаданные: пусто")
    }
}

print("""

Как читать:
  isPlaying ДА + метаданные ЕСТЬ  -> доступ открыт, универсальный провайдер
  isPlaying ДА + метаданные пусто -> доступ к метаданным закрыт
  isPlaying нет                   -> система не видит сессии (источник её не публикует)
""")
exit(0)
