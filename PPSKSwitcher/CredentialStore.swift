import Foundation
import Security

/// Profile-specific secrets are separate Keychain generic-password items.
/// We never write PPSK secrets to UserDefaults, log files, or process arguments.
enum CredentialStore {
    private static let service = "app.local.PPSKSwitcher.profile-credentials"

    private static func query(for id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }

    static func password(for id: UUID) throws -> String? {
        var request = query(for: id)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw CredentialError(status)
        }
        return value
    }

    static func setPassword(_ password: String, for id: UUID) throws {
        let data = Data(password.utf8)
        let status = SecItemUpdate(query(for: id) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query(for: id)
            attributes[kSecValueData as String] = data
            let added = SecItemAdd(attributes as CFDictionary, nil)
            guard added == errSecSuccess else { throw CredentialError(added) }
        } else if status != errSecSuccess {
            throw CredentialError(status)
        }
    }

    static func deletePassword(for id: UUID) throws {
        let status = SecItemDelete(query(for: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialError(status)
        }
    }

    struct CredentialError: LocalizedError {
        let status: OSStatus
        init(_ status: OSStatus) { self.status = status }
        var errorDescription: String? {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
            return "Keychain error: \(reason) (OSStatus \(status))"
        }
    }
}
