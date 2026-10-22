import Foundation
import Security

/// Stores access keys, which contain server passwords or config URLs with tokens.
protocol SecretStore {
    func secret(for id: String) throws -> String?
    func setSecret(_ secret: String, for id: String) throws
    func deleteSecret(for id: String) throws
}

/// Keeps each access key as a generic password item in the user's data protection
/// Keychain, readable only by Keyline and only after the first unlock since boot.
struct KeychainSecretStore: SecretStore {
    var service = "\(KeylineIdentifiers.app).access-key"

    struct KeychainError: Error, CustomStringConvertible {
        let status: OSStatus
        var description: String {
            "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
        }
    }

    func secret(for id: String) throws -> String? {
        var query = baseQuery(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    func setSecret(_ secret: String, for id: String) throws {
        let data = Data(secret.utf8)
        let status = SecItemUpdate(baseQuery(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery(id)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            item[kSecAttrLabel as String] = "Keyline access key"
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func deleteSecret(for id: String) throws {
        let status = SecItemDelete(baseQuery(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private func baseQuery(_ id: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}

/// A `SecretStore` that lives in memory, for tests and previews.
final class InMemorySecretStore: SecretStore {
    private(set) var secrets: [String: String] = [:]

    init(_ secrets: [String: String] = [:]) {
        self.secrets = secrets
    }

    func secret(for id: String) throws -> String? { secrets[id] }
    func setSecret(_ secret: String, for id: String) throws { secrets[id] = secret }
    func deleteSecret(for id: String) throws { secrets[id] = nil }
}
