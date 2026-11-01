import Foundation

/// 官方更新检查（`GET /__mobile/api/update`）+ 原生 App 版本信息。
/// 「Web 资源随宿主更新」：iOS 端只是加载远端 UI，所以这里不涉及 App Store 上架。
enum UpdateChecker {

    static func check(baseURL: URL, token: String?) async throws -> UpdateInfo {
        try await StatusClient.update(baseURL: baseURL, token: token)
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    static var appVersionDisplay: String {
        "\(appVersion) (\(buildNumber))"
    }

    /// App Store 数字 id 由用户在设置里自填（占位能力，见 docs/SPEC.md 第 8 节）。
    static func appStoreURL(appStoreID: String) -> URL? {
        let trimmed = appStoreID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let digits = trimmed.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(digits)")
    }
}
