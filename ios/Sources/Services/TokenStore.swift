import Foundation
import Security

/// 设备令牌只存钥匙串，不写 UserDefaults、不写日志。
/// account = `endpoint.<endpoint.id>`，一台设备可以配多个端点，互不覆盖。
final class TokenStore {

    static let shared = TokenStore()

    private let service = "com.deepseek.dshmobile.device-token"
    private let accountPrefix = "endpoint."

    private func account(for endpointID: String) -> String {
        accountPrefix + endpointID
    }

    @discardableResult
    func save(_ token: String, for endpointID: String) -> Bool {
        guard let data = token.data(using: .utf8) else {
            DSHLog.error("token encode failed for \(endpointID)")
            return false
        }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: endpointID)
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            DSHLog.error("keychain add failed (\(status)) for \(endpointID)")
            return false
        }
        return true
    }

    func token(for endpointID: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: endpointID),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func delete(for endpointID: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: endpointID)
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    @discardableResult
    func deleteAll() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
