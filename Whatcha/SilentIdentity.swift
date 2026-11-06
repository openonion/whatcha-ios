import Foundation
import Security
import WhatchaCore

extension Identity {
    static func loadFromKeychain() -> Identity {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ai.openonion.whatcha.identity",
            kSecAttrAccount as String: "ed25519-seed"
        ]
        var found: CFTypeRef?
        var lookup = query
        lookup[kSecReturnData as String] = true
        let status = SecItemCopyMatching(lookup as CFDictionary, &found)
        if status == errSecSuccess { return try! Identity(seed: found as! Data) }
        precondition(status == errSecItemNotFound, "Keychain read failed: \(status)")
        let identity = Identity()
        var entry = query
        entry[kSecValueData as String] = identity.seed
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(entry as CFDictionary, nil)
        precondition(added == errSecSuccess, "Keychain write failed: \(added)")
        return identity
    }
}
