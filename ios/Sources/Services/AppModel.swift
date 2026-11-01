import Combine
import Foundation

enum AppTab: Hashable {
    case dashboard
    case workspace
    case updates
    case settings
}

struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

/// 应用级协调器：组合三个 store、处理深链配对、Face ID 锁、前后台轮询生命周期。
@MainActor
final class AppModel: ObservableObject {

    let endpoints: EndpointStore
    let settings: SettingsStore
    let status: StatusCenter
    let tokens: TokenStore

    @Published var selectedTab: AppTab = .dashboard
    @Published var workspaceEndpointID: String?
    @Published var alert: AppAlert?
    @Published var isLocked: Bool = false
    @Published var isBusyPairing: Bool = false
    @Published var biometry: LockState = .unavailable

    /// 解锁过一次后，正常的前后台切换仍然会重新上锁（见 `appDidEnterBackground`）。
    private var hasUnlockedSinceLaunch = false

    init() {
        let endpoints = EndpointStore()
        let settings = SettingsStore()
        let tokens = TokenStore.shared

        self.endpoints = endpoints
        self.settings = settings
        self.tokens = tokens
        self.status = StatusCenter(endpoints: endpoints, tokens: tokens)

        let state = BiometricLock.state()
        self.biometry = state
        self.isLocked = settings.biometricLockEnabled && state.available
    }

    // MARK: - 生命周期

    func appDidBecomeActive() {
        biometry = BiometricLock.state()
        if settings.biometricLockEnabled {
            isLocked = biometry.available && !hasUnlockedSinceLaunch
        }
        status.startPolling(seconds: settings.pollSeconds)
        Task { await status.refreshAll() }
    }

    func appDidEnterBackground() {
        status.stopPolling()
        guard settings.biometricLockEnabled, biometry.available else { return }
        hasUnlockedSinceLaunch = false
        isLocked = true
    }

    func settingsDidChange() {
        biometry = BiometricLock.state()
        if !settings.biometricLockEnabled {
            isLocked = false
            hasUnlockedSinceLaunch = true
        }
        status.startPolling(seconds: settings.pollSeconds)
    }

    // MARK: - 锁屏

    func unlock() async {
        let result = await BiometricLock.unlock(reason: t("lock.reason"))
        switch result {
        case .success:
            hasUnlockedSinceLaunch = true
            isLocked = false
        case .cancelled:
            break
        case .unavailable(let message):
            // 设备上没有可用的生物识别/密码时不把用户锁死，只提示一次。
            hasUnlockedSinceLaunch = true
            isLocked = false
            alert = AppAlert(title: t("lock.unavailableTitle"), message: message)
        case .failed(let message):
            alert = AppAlert(title: t("lock.failedTitle"), message: message)
        }
    }

    func lockNow() {
        guard settings.biometricLockEnabled, biometry.available else { return }
        hasUnlockedSinceLaunch = false
        isLocked = true
    }

    // MARK: - 端点 & 配对

    func deviceToken(for endpointID: String) -> String? {
        tokens.token(for: endpointID)
    }

    func hasToken(for endpointID: String) -> Bool {
        tokens.token(for: endpointID) != nil
    }

    /// 配对并在本地登记端点；同一网关地址重复配对时只刷新令牌与设备 id。
    func pair(name: String, rawURL: String, code: String) async throws -> Endpoint {
        guard let baseURL = Endpoint.normalizedURL(rawURL),
              let normalized = Endpoint.normalizedString(rawURL) else {
            throw PairingError.invalidURL
        }

        let result = try await PairingClient.pair(baseURL: baseURL,
                                                  code: code,
                                                  name: resolvedDeviceName(name),
                                                  platform: "ios")

        if let existing = endpoints.endpoint(withNormalizedURL: normalized) {
            if !tokens.save(result.token, for: existing.id) {
                DSHLog.warning("token refresh failed for endpoint \(existing.id)")
            }
            var updated = existing
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { updated.name = trimmed }
            if let deviceID = result.device?.id { updated.deviceId = deviceID }
            endpoints.update(updated)
            return updated
        }

        let endpoint = Endpoint(name: resolvedDeviceName(name),
                                url: normalized,
                                platform: result.device?.platform ?? "ios",
                                deviceId: result.device?.id)
        guard tokens.save(result.token, for: endpoint.id) else {
            throw PairingError.tokenStorageFailed
        }
        endpoints.add(endpoint)
        return endpoint
    }

    func deleteEndpoint(id: String) {
        tokens.delete(for: id)
        endpoints.remove(id: id)
        status.removeSnapshot(for: id)
        if workspaceEndpointID == id {
            workspaceEndpointID = nil
        }
    }

    func clearAllData() {
        tokens.deleteAll()
        endpoints.removeAll()
        status.reset()
        workspaceEndpointID = nil
        alert = AppAlert(title: t("settings.clear.doneTitle"), message: t("settings.clear.doneMessage"))
    }

    func openWorkspace(for endpoint: Endpoint) {
        workspaceEndpointID = endpoint.id
        selectedTab = .workspace
    }

    // MARK: - 深链配对

    static func isValidPairCode(_ code: String) -> Bool {
        code.count == 6 && code.allSatisfy { $0.isNumber }
    }

    /// `dshmobile://pair?url=<encoded gateway>&code=<6 位>&name=<可选设备名>`
    func handleOpenURL(_ url: URL) {
        guard url.scheme?.lowercased() == "dshmobile" else {
            alert = AppAlert(title: t("pair.unsupported.title"), message: t("pair.unsupported.message"))
            return
        }
        guard url.host?.lowercased() == "pair" else {
            alert = AppAlert(title: t("pair.unsupported.title"), message: t("pair.unsupported.message"))
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        let rawURL = items.first { $0.name == "url" }?.value ?? ""
        let code = items.first { $0.name == "code" }?.value ?? ""
        let name = items.first { $0.name == "name" }?.value

        guard !rawURL.isEmpty, !code.isEmpty else {
            alert = AppAlert(title: t("pair.deeplink.title"), message: t("pair.deeplink.message"))
            return
        }

        Task { await pairFromDeepLink(rawURL: rawURL, code: code, name: name) }
    }

    func pairFromDeepLink(rawURL: String, code: String, name: String?) async {
        guard !isBusyPairing else { return }
        guard let normalized = Endpoint.normalizedString(rawURL) else {
            alert = AppAlert(title: t("pair.failedTitle"), message: PairingError.invalidURL.localizedDescription)
            return
        }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AppModel.isValidPairCode(trimmedCode) else {
            alert = AppAlert(title: t("pair.failedTitle"), message: t("add.error.codeInvalid"))
            return
        }

        isBusyPairing = true
        defer { isBusyPairing = false }

        do {
            let endpoint = try await pair(name: name ?? "", rawURL: normalized, code: trimmedCode)
            workspaceEndpointID = endpoint.id
            selectedTab = .dashboard
            alert = AppAlert(title: t("pair.successTitle"),
                             message: String(format: t("pair.successMessage"), endpoint.name))
            await status.refreshAll()
        } catch {
            alert = AppAlert(title: t("pair.failedTitle"), message: error.localizedDescription)
        }
    }

    private func resolvedDeviceName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? settings.deviceName : trimmed
    }
}
