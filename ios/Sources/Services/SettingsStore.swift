import Combine
import Foundation
import UIKit

/// 偏好设置：全部落 UserDefaults，改动即时生效（`didSet` 里 persist）。
@MainActor
final class SettingsStore: ObservableObject {

    /// 轮询间隔候选（秒）。默认 30 秒，见 docs/SPEC.md 第 6 节。
    static let pollOptions: [Int] = [10, 30, 60]

    @Published var language: String {
        didSet { persist() }
    }

    @Published var pollSeconds: Int {
        didSet { persist() }
    }

    @Published var biometricLockEnabled: Bool {
        didSet { persist() }
    }

    @Published var deviceName: String {
        didSet { persist() }
    }

    @Published var appStoreID: String {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let language = L10n.languageKey
        static let pollSeconds = "dsh.settings.pollSeconds"
        static let biometric = "dsh.settings.biometricLock"
        static let deviceName = "dsh.settings.deviceName"
        static let appStoreID = "dsh.settings.appStoreID"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedLanguage = defaults.string(forKey: Keys.language) ?? "system"
        language = L10n.supportedLanguages.contains(storedLanguage) ? storedLanguage : "system"

        let storedPoll = defaults.integer(forKey: Keys.pollSeconds)
        pollSeconds = SettingsStore.pollOptions.contains(storedPoll) ? storedPoll : 30

        biometricLockEnabled = defaults.bool(forKey: Keys.biometric)

        let storedName = (defaults.string(forKey: Keys.deviceName) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        deviceName = storedName.isEmpty ? UIDevice.current.name : storedName

        appStoreID = defaults.string(forKey: Keys.appStoreID) ?? ""
    }

    private func persist() {
        defaults.set(language, forKey: Keys.language)
        defaults.set(pollSeconds, forKey: Keys.pollSeconds)
        defaults.set(biometricLockEnabled, forKey: Keys.biometric)
        defaults.set(deviceName, forKey: Keys.deviceName)
        defaults.set(appStoreID, forKey: Keys.appStoreID)
    }
}
