import Foundation

/// `GET /__mobile/api/update` 响应。契约见 docs/SPEC.md 2.5。
/// 网络/解析失败时网关返回 HTTP 200 + `ok:false, error:"..."`，所以这里不把失败当异常。
struct UpdateInfo: Codable, Equatable, Sendable {

    var ok: Bool?
    var channel: String?
    var current: String?
    var latest: String?
    var updateAvailable: Bool?
    var checkedAt: Date?
    var feedUrl: String?
    var releaseNotesUrl: String?
    var error: String?
    var ios: IOSUpdateNote?

    struct IOSUpdateNote: Codable, Equatable, Sendable {
        var mode: String?
        var note: String?
        var consoleVersion: String?
    }

    var isUpdateAvailable: Bool {
        updateAvailable ?? false
    }

    /// 网关侧检查失败时给用户看的文案。
    var failureMessage: String? {
        if let error = error, !error.isEmpty { return error }
        if ok == false { return t("common.unknown") }
        return nil
    }
}

/// `GET /__mobile/api/health`（无需鉴权），用于「测试连接」。
struct GatewayHealth: Codable, Equatable, Sendable {
    var ok: Bool?
    var service: String?
    var version: String?
    var gatewayUrl: String?
    var host: PairedHost?

    var summary: String {
        let name = service ?? "dsh-mobile-gateway"
        let version = version ?? t("common.unknown")
        return "\(name) \(version)"
    }
}
