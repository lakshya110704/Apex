import Foundation
import Security

/// Minimal Keychain wrapper for the Gemini API key. Items stay on this device and are not backed up.
enum KeychainStore {
    private static let service = "com.lakshya.apex"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func get(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// An empty value deletes the item. Returns false if the Keychain write failed.
    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        SecItemDelete(query(account) as CFDictionary)
        guard !value.isEmpty else { return true }
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}
