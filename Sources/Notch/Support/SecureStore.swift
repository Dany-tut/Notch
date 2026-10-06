import CryptoKit
import Foundation
import Security

/// Хранилище, которое шифрует содержимое перед записью на диск.
///
/// История буфера — это токены, ссылки и переписка; лежать в открытом JSON
/// она не должна. Ключ живёт в Связке ключей, а не рядом с данными: иначе
/// шифрование было бы декорацией.
struct SecureStore<Element: Codable> {
    let fileURL: URL
    private let keyTag: String

    init(filename: String, keyTag: String) {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Notch", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent(filename)
        self.keyTag = keyTag
    }

    func load() -> [Element] {
        guard let blob = try? Data(contentsOf: fileURL), let key = loadKey() else { return [] }
        guard let box = try? AES.GCM.SealedBox(combined: blob),
              let plain = try? AES.GCM.open(box, using: key) else { return [] }
        return (try? JSONDecoder().decode([Element].self, from: plain)) ?? []
    }

    func save(_ elements: [Element]) {
        guard let plain = try? JSONEncoder().encode(elements),
              let key = loadKey() ?? createKey(),
              let sealed = try? AES.GCM.seal(plain, using: key).combined
        else { return }
        try? sealed.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func removeFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Ключ

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.dany.notch",
            kSecAttrAccount as String: keyTag
        ]
    }

    private func loadKey() -> SymmetricKey? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return SymmetricKey(data: data)
    }

    private func createKey() -> SymmetricKey? {
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }

        var item = query
        item[kSecValueData as String] = raw
        // Доступно только после первой разблокировки и не уезжает в iCloud.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        SecItemDelete(query as CFDictionary)
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { return nil }
        return key
    }
}
