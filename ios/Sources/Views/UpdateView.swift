import SwiftUI

/// 更新页：宿主 DSH 版本 / 官方最新版 / 可更新标记，并解释「iOS 端只是加载远端 Web UI」。
struct UpdateView: View {

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var endpoints: EndpointStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var status: StatusCenter
    @Environment(\.openURL) private var openURL

    @State private var results: [String: UpdateInfo] = [:]
    @State private var errors: [String: String] = [:]
    @State private var loading: Set<String> = []
    @State private var isCheckingAll = false

    var body: some View {
        NavigationStack {
            List {
                explainerSection
                hostsSection
                appSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(t("update.title"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await checkAll() }
                    } label: {
                        if isCheckingAll {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isCheckingAll || endpoints.isEmpty)
                    .accessibilityLabel(t("update.checkAll"))
                }
            }
        }
    }

    private var explainerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(t("update.explainer.title"), systemImage: "lightbulb")
                    .font(.subheadline.weight(.semibold))
                Text(t("update.explainer.body"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(t("update.explainer.native"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var hostsSection: some View {
        Section {
            if endpoints.isEmpty {
                EmptyHint(icon: "arrow.down.circle",
                          title: t("update.noEndpoints"),
                          message: t("dashboard.empty.message"))
            } else {
                ForEach(endpoints.endpoints) { endpoint in
                    hostRow(endpoint)
                }
            }
        } header: {
            Text(t("update.section.hosts"))
        }
    }

    @ViewBuilder
    private func hostRow(_ endpoint: Endpoint) -> some View {
        let snapshot = status.snapshot(for: endpoint.id)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(endpoint.name)
                    .font(.headline)
                Spacer(minLength: 6)
                if loading.contains(endpoint.id) {
                    ProgressView()
                }
            }

            InfoRow(title: t("update.current"),
                    value: DSHFormat.text(snapshot.status?.update?.current ?? snapshot.status?.host?.dshVersion))
            InfoRow(title: t("update.gateway"),
                    value: DSHFormat.text(snapshot.status?.host?.gatewayVersion))

            if let result = results[endpoint.id] {
                InfoRow(title: t("update.latest"), value: DSHFormat.text(result.latest))
                InfoRow(title: t("update.channel"), value: DSHFormat.text(result.channel))
                if result.isUpdateAvailable {
                    StateBadge(text: t("update.available"), color: .orange)
                } else if result.failureMessage == nil {
                    StateBadge(text: t("update.upToDate"), color: .green)
                }
                if let failure = result.failureMessage {
                    ErrorBanner(message: String(format: t("update.error"), failure))
                }
                if let note = result.ios?.note, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let error = errors[endpoint.id] {
                ErrorBanner(message: error)
            }

            Button {
                Task { await check(endpoint) }
            } label: {
                Label(t("update.check"), systemImage: "arrow.down.circle")
            }
            .disabled(loading.contains(endpoint.id))
        }
        .padding(.vertical, 4)
    }

    private var appSection: some View {
        Section {
            InfoRow(title: t("update.app.version"), value: UpdateChecker.appVersionDisplay)
            InfoRow(title: t("settings.endpoints.count"), value: String(endpoints.count))

            if let url = UpdateChecker.appStoreURL(appStoreID: settings.appStoreID) {
                Button {
                    openURL(url)
                } label: {
                    Label(t("update.app.openStore"), systemImage: "arrow.up.right.square")
                }
            } else {
                Text(t("update.app.noStoreId"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text(t("update.section.app"))
        } footer: {
            Text(t("update.app.storeIdHint"))
        }
    }

    @MainActor
    private func check(_ endpoint: Endpoint) async {
        guard let baseURL = endpoint.baseURL else {
            errors[endpoint.id] = t("status.invalidURL")
            return
        }
        loading.insert(endpoint.id)
        errors.removeValue(forKey: endpoint.id)
        defer { loading.remove(endpoint.id) }

        do {
            let info = try await UpdateChecker.check(baseURL: baseURL,
                                                     token: app.deviceToken(for: endpoint.id))
            results[endpoint.id] = info
            if let failure = info.failureMessage {
                errors[endpoint.id] = String(format: t("update.error"), failure)
            }
        } catch {
            errors[endpoint.id] = String(format: t("update.error"), error.localizedDescription)
        }
    }

    @MainActor
    private func checkAll() async {
        guard !isCheckingAll else { return }
        isCheckingAll = true
        defer { isCheckingAll = false }
        for endpoint in endpoints.endpoints {
            await check(endpoint)
        }
    }
}
