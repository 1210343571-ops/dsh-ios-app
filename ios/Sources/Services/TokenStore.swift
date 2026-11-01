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

    private func defaultsKey(for endpointID: String) -> String {
        "dshmobile.device-token." + endpointID
    }

    /// 侧载（Sideloadly 重签名）后 App 的钥匙串访问组可能变化，
    /// SecItemAdd 会返回 errSecMissingEntitlement(-34018) 导致配对令牌丢失。
    /// 因此 Keychain 之外再加一层 UserDefaults 备份：任一写入成功就算保存成功。
    @discardableResult
    func save(_ token: String, for endpointID: String) -> Bool {
        var keychainSaved = false
        if let data = token.data(using: .utf8) {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account(for: endpointID)
            ]
            SecItemDelete(query as CFDictionary)
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let status = SecItemAdd(query as CFDictionary, nil)
            if status == errSecSuccess {
                keychainSaved = true
            } else {
                DSHLog.error("keychain add failed (\(status)) for \(endpointID), falling back to UserDefaults")
            }
        } else {
            DSHLog.error("token encode failed for \(endpointID)")
        }
        UserDefaults.standard.set(token, forKey: defaultsKey(for: endpointID))
        return keychainSaved || UserDefaults.standard.string(forKey: defaultsKey(for: endpointID)) == token
    }

    func token(for endpointID: String) -> String? {
        if let token = keychainToken(for: endpointID) {
            return token
        }
        if let fallback = UserDefaults.standard.string(forKey: defaultsKey(for: endpointID)), !fallback.isEmpty {
            return fallback
        }
        return nil
    }

    private func keychainToken(for endpointID: String) -> String? {
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
        UserDefaults.standard.removeObject(forKey: defaultsKey(for: endpointID))
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
