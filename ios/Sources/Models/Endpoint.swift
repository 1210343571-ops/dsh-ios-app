import Foundation

/// 一个已添加的 DSH 网关端点。
/// 令牌不进模型：它单独存在钥匙串（`TokenStore`），只按 `id` 关联。
struct Endpoint: Identifiable, Codable, Hashable, Sendable {

    let id: String
    var name: String
    /// 归一化后的网关地址，例如 "http://192.168.3.18:63421"（无结尾斜杠）。
    var url: String
    var platform: String
    /// 网关侧设备 id（`POST /__mobile/api/pair` 返回的 device.id）。
    var deviceId: String?
    var addedAt: Date
    var lastSeenAt: Date?

    init(id: String = UUID().uuidString,
         name: String,
         url: String,
         platform: String = "ios",
         deviceId: String? = nil,
         addedAt: Date = Date(),
         lastSeenAt: Date? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.platform = platform
        self.deviceId = deviceId
        self.addedAt = addedAt
        self.lastSeenAt = lastSeenAt
    }

    var baseURL: URL? {
        Endpoint.normalizedURL(url)
    }

    var host: String {
        baseURL?.host ?? url
    }

    /// 手机控制台 PWA 入口（由网关静态提供）。
    var consoleURL: URL? {
        guard let baseURL else { return nil }
        return URL(string: baseURL.absoluteString + "/__mobile/")
    }

    /// 完整工作台入口：网关根路径会被反向代理到桌面 Web UI，需要 `dshm_device` Cookie。
    var workspaceURL: URL? {
        guard let baseURL else { return nil }
        return URL(string: baseURL.absoluteString + "/")
    }

    var healthURL: URL? {
        guard let baseURL else { return nil }
        return HTTPClient.url(for: "__mobile/api/health", baseURL: baseURL)
    }

    /// 把用户输入（可省略 scheme、可带尾斜杠）归一化成可用的网关地址。
    static func normalizedURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lowercased = text.lowercased()
        if !lowercased.hasPrefix("http://") && !lowercased.hasPrefix("https://") {
            text = "http://" + text
        }
        guard var components = URLComponents(string: text) else { return nil }
        components.query = nil
        components.fragment = nil
        guard let host = components.host, !host.isEmpty else { return nil }
        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path
        return components.url
    }

    static func normalizedString(_ raw: String) -> String? {
        normalizedURL(raw)?.absoluteString
    }
}
