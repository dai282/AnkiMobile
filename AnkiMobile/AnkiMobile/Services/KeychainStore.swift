//
//  KeychainStore.swift
//  AnkiMobile
//
//  A tiny wrapper over the iOS Keychain for secrets — the AnkiWeb sync key and
//  host learned at login (V2.1). Secrets must never live in UserDefaults.
//

import Foundation
import Security

enum KeychainStore {
    /// Namespacing service for all items this app stores.
    private static let service = "com.dainguyen.AnkiMobile"

    /// Well-known keys.
    enum Key: String {
        case syncKey = "ankiweb.syncKey"
        case syncHost = "ankiweb.syncHost"
        case username = "ankiweb.username"
    }

    // MARK: - String convenience

    static func set(_ value: String, for key: Key) {
        setData(Data(value.utf8), for: key)
    }

    static func string(for key: Key) -> String? {
        guard let data = data(for: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Data primitives

    static func setData(_ value: Data, for key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        // Replace any existing value for this key.
        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = value
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func data(for key: Key) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func remove(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Clears every stored secret (used on Log Out).
    static func clearAll() {
        [Key.syncKey, .syncHost, .username].forEach(remove)
    }
}
