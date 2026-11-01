import Foundation

/// 网关 JSON API 客户端（全部 `async/await`，10 秒超时）。
/// - health：无需鉴权，用于「测试连接」。
/// - status：需要 `Authorization: Bearer <token>`。
/// - update：需要同一个 Bearer token。
enum StatusClient {

    static func health(baseURL: URL) async throws -> GatewayHealth {
        try await HTTPClient.getJSON("__mobile/api/health",
                                     baseURL: baseURL,
                                     token: nil,
                                     as: GatewayHealth.self)
    }

    static func status(baseURL: URL, token: String?) async throws -> HostStatus {
        try await HTTPClient.getJSON("__mobile/api/status",
                                     baseURL: baseURL,
                                     token: token,
                                     as: HostStatus.self)
    }

    static func update(baseURL: URL, token: String?) async throws -> UpdateInfo {
        try await HTTPClient.getJSON("__mobile/api/update",
                                     baseURL: baseURL,
                                     token: token,
                                     as: UpdateInfo.self)
    }
}
