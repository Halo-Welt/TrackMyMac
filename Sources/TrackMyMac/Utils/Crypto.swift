import Foundation
import Security
import CryptoKit

/// Stores the SQLite encryption key in macOS Keychain.
enum KeychainKeyStore {
    private static let service = "com.trackmymac.app"
    private static let account = "db-key-v1"

    static func loadOrCreateKey() -> SymmetricKey {
        if let data = load() {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        save(raw)
        return key
    }

    private static func load() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    private static func save(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            Log.error("Keychain save failed: \(status)")
        }
    }
}

/// AES-GCM encryption helper for sensitive payload columns.
enum Crypto {
    private static let key: SymmetricKey = KeychainKeyStore.loadOrCreateKey()

    static func encrypt(_ plaintext: String) -> Data? {
        guard let data = plaintext.data(using: .utf8) else { return nil }
        do {
            let sealed = try AES.GCM.seal(data, using: key)
            return sealed.combined
        } catch {
            Log.error("Encrypt failed: \(error)")
            return nil
        }
    }

    static func decrypt(_ data: Data) -> String? {
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            let raw = try AES.GCM.open(box, using: key)
            return String(data: raw, encoding: .utf8)
        } catch {
            Log.error("Decrypt failed: \(error)")
            return nil
        }
    }
}
