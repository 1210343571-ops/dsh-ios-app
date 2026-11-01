import Foundation

/// 轻量本地化：默认跟随系统；用户在设置里显式选语言时，直接从对应 `.lproj` 取字符串。
/// 这样不需要 bundle swizzling，切换语言后重建视图即可立刻生效。
enum L10n {

    /// 与 `SettingsStore` 共用的 UserDefaults key（"system" / "zh-Hans" / "en"）。
    static let languageKey = "dsh.settings.language"

    static let supportedLanguages = ["system", "zh-Hans", "en"]

    static var selectedLanguage: String {
        UserDefaults.standard.string(forKey: languageKey) ?? "system"
    }

    static func bundle(for language: String) -> Bundle {
        guard language != "system", supportedLanguages.contains(language) else { return .main }
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let localized = Bundle(path: path) else {
            return .main
        }
        return localized
    }

    static func t(_ key: String) -> String {
        let bundle = bundle(for: selectedLanguage)
        let value = NSLocalizedString(key, tableName: "Localizable", bundle: bundle, value: key, comment: "")
        if value != key { return value }
        // 显式选中的语言缺少该 key 时，回退到同名的英文文案，最后再回退到 key 本身。
        if bundle !== Bundle.main {
            let fallback = NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: key, comment: "")
            if fallback != key { return fallback }
        }
        return key
    }
}

/// 视图层统一入口：`Text(t("dashboard.title"))`。
func t(_ key: String) -> String {
    L10n.t(key)
}
