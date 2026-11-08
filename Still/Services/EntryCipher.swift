import Foundation
import CryptoKit
import Security

/// Encrypts journal text with AES-256-GCM. The key is generated on first use and
/// kept in the iOS Keychain, bound to this device (it is never synced or backed up).
enum EntryCipher {
    enum CipherError: Error {
        case sealFailed
        case keychain(OSStatus)
    }

    private static let service = "com.guythatlives.still.vault"
    private static let account = "entry-key-v1"
    private static var cachedKey: SymmetricKey?

    static func seal(_ text: String) throws -> Data {
        let box = try AES.GCM.seal(Data(text.utf8), using: try key())
        guard let combined = box.combined else { throw CipherError.sealFailed }
        return combined
    }

    static func open(_ data: Data) throws -> String {
        let box = try AES.GCM.SealedBox(combined: data)
        let plain = try AES.GCM.open(box, using: try key())
        return String(decoding: plain, as: UTF8.self)
    }

    private static func key() throws -> SymmetricKey {
        if let cachedKey { return cachedKey }
        if let stored = try readKey() {
            let k = SymmetricKey(data: stored)
            cachedKey = k
            return k
        }
        let k = SymmetricKey(size: .bits256)
        let raw = k.withUnsafeBytes { Data($0) }
        try storeKey(raw)
        cachedKey = k
        return k
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func readKey() throws -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CipherError.keychain(status) }
        return item as? Data
    }

    private static func storeKey(_ data: Data) throws {
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw CipherError.keychain(status) }
    }
}
