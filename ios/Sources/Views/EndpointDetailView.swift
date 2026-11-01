import SwiftUI
import UIKit

/// 端点详情：完整状态、运行中的 agent、打开工作台/控制台、更新检查、重命名与删除。
struct EndpointDetailView: View {

    let endpointID: String

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var endpoints: EndpointStore
    @EnvironmentObject private var status: StatusCenter
    @Environment(\.openURL) private var openURL

    @State private var showingRename = false
    @State private var showingDelete = false
    @State private var renameText = ""
    @State private var updateInfo: UpdateInfo?
    @State private var updateError: String?
    @State private var isCheckingUpdate = false
    @State private var copied = false

    private var endpoint: Endpoint? {
        endpoints.endpoint(withID: endpointID)
    }

    var body: some View {
        List {
            if let endpoint = endpoint {
                sections(for: endpoint)
            } else {
                Section {
                    EmptyHint(icon: "trash",
                              title: t("endpoint.missing"),
                              message: t("endpoint.missing.message"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(endpoint?.name ?? t("endpoint.title"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await status.refreshAll()
        }
        .alert(t("endpoint.rename.title"), isPresented: $showingRename) {
            TextField(t("endpoint.rename.placeholder"), text: $renameText)
            Button(t("common.cancel"), role: .cancel) {}
            Button(t("common.save")) {
                endpoints.rename(id: endpointID, name: renameText)
            }
        } message: {
            Text(t("endpoint.rename.message"))
        }
        .confirmationDialog(t("endpoint.delete.confirm"),
                            isPresented: $showingDelete,
                            titleVisibility: .visible) {
            Button(t("endpoint.action.delete"), role: .destructive) {
                app.deleteEndpoint(id: endpointID)
            }
            Button(t("common.cancel"), role: .cancel) {}
        } message: {
            Text(t("endpoint.delete.message"))
        }
    }

    @ViewBuilder
    private func sections(for endpoint: Endpoint) -> some View {
        let snapshot = status.snapshot(for: endpoint.id)

        Section {
            InfoRow(title: t("endpoint.field.address"), value: endpoint.url)
            HStack(spacing: 8) {
                StatusDot(snapshot: snapshot)
                Text(t("endpoint.field.status"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer(minLength: 8)
                Text(StatusDot(snapshot: snapshot).text)
                    .font(.subheadline)
            }
            InfoRow(title: t("endpoint.field.paired"),
                    value: app.hasToken(for: endpoint.id) ? t("endpoint.field.paired.yes") : t("endpoint.field.paired.no"))
            if snapshot.isOnline {
                InfoRow(title: t("endpoint.field.latency"), value: DSHFormat.latency(snapshot.latencyMs))
            }
            InfoRow(title: t("endpoint.field.updatedAt"), value: DSHFormat.timestamp(snapshot.fetchedAt))
            if let reason = snapshot.offlineReason {
                ErrorBanner(message: reason)
            }
        } header: {
            Text(t("endpoint.section.connection"))
        }

        if let host = snapshot.status?.host {
            Section {
                InfoRow(title: t("endpoint.field.hostName"), value: DSHFormat.text(host.name))
                InfoRow(title: t("endpoint.field.platform"), value: DSHFormat.text(host.platform))
                InfoRow(title: t("endpoint.field.osRelease"), value: DSHFormat.text(host.release))
                InfoRow(title: t("endpoint.field.dshVersion"), value: DSHFormat.text(host.dshVersion))
                InfoRow(title: t("endpoint.field.gatewayVersion"), value: DSHFormat.text(host.gatewayVersion))
                InfoRow(title: t("endpoint.field.uptime"), value: DSHFormat.uptime(milliseconds: host.uptimeMs))
                InfoRow(title: t("endpoint.field.gatewayUrl"), value: DSHFormat.text(host.gatewayUrl))
                InfoRow(title: t("endpoint.field.upstreamUrl"), value: DSHFormat.text(host.upstreamUrl))
            } header: {
                Text(t("endpoint.section.host"))
            }
        }

        if let hostStatus = snapshot.status {
            Section {
                InfoRow(title: t("endpoint.field.sessions"),
                        value: "\(DSHFormat.number(hostStatus.sessions?.total)) / \(DSHFormat.number(hostStatus.sessions?.active))")
                InfoRow(title: t("endpoint.field.teams"),
                        value: DSHFormat.number(hostStatus.teams?.members))
                if let tasks = hostStatus.teams?.tasks {
                    InfoRow(title: t("endpoint.field.tasks"),
                            value: "\(DSHFormat.number(tasks.pending)) / \(DSHFormat.number(tasks.inProgress)) / \(DSHFormat.number(tasks.completed))")
                }
                InfoRow(title: t("endpoint.field.jobs"),
                        value: "\(DSHFormat.number(hostStatus.jobs?.running)) / \(DSHFormat.number(hostStatus.jobs?.total))")
                InfoRow(title: t("endpoint.field.schedules"),
                        value: DSHFormat.number(hostStatus.schedules?.active))
                InfoRow(title: t("endpoint.field.approvals"),
                        value: DSHFormat.number(hostStatus.approvals?.pending))
                InfoRow(title: t("endpoint.field.devices"),
                        value: DSHFormat.number(hostStatus.devices?.count))
            } header: {
                Text(t("endpoint.section.runtime"))
            }
        }

        if let items = snapshot.status?.agents?.items, !items.isEmpty {
            Section {
                ForEach(items.prefix(20), id: \.stableID) { item in
                    AgentRow(item: item)
                }
            } header: {
                Text(t("endpoint.section.agents"))
            }
        }

        Section {
            if let info = updateInfo {
                InfoRow(title: t("update.channel"), value: DSHFormat.text(info.channel))
                InfoRow(title: t("update.current"), value: DSHFormat.text(info.current))
                InfoRow(title: t("update.latest"), value: DSHFormat.text(info.latest))
                InfoRow(title: t("update.checkedAt"), value: DSHFormat.timestamp(info.checkedAt))
                if info.isUpdateAvailable {
                    StateBadge(text: t("update.available"), color: .orange)
                } else if info.failureMessage == nil {
                    StateBadge(text: t("update.upToDate"), color: .green)
                }
                if let failure = info.failureMessage {
                    ErrorBanner(message: String(format: t("update.error"), failure))
                }
            }
            if let updateError = updateError {
                ErrorBanner(message: updateError)
            }
            Button {
                Task { await checkUpdate(for: endpoint) }
            } label: {
                HStack(spacing: 8) {
                    if isCheckingUpdate {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                    Text(t("update.check"))
                }
            }
            .disabled(isCheckingUpdate)
        } header: {
            Text(t("update.section.hosts"))
        }

        Section {
            Button {
                app.openWorkspace(for: endpoint)
            } label: {
                Label(t("endpoint.action.workspace"), systemImage: "macwindow")
            }

            Button {
                if let url = endpoint.consoleURL { openURL(url) }
            } label: {
                Label(t("endpoint.action.console"), systemImage: "safari")
            }

            Button {
                if let url = endpoint.workspaceURL { openURL(url) }
            } label: {
                Label(t("endpoint.action.safari"), systemImage: "arrow.up.right.square")
            }

            Button {
                UIPasteboard.general.string = endpoint.url
                copied = true
            } label: {
                Label(copied ? t("endpoint.action.copied") : t("endpoint.action.copy"), systemImage: "doc.on.doc")
            }

            Button {
                renameText = endpoint.name
                showingRename = true
            } label: {
                Label(t("endpoint.action.rename"), systemImage: "pencil")
            }
        } header: {
            Text(t("endpoint.section.actions"))
        }

        Section {
            Button(role: .destructive) {
                showingDelete = true
            } label: {
                Label(t("endpoint.action.delete"), systemImage: "trash")
            }
        }
    }

    private func checkUpdate(for endpoint: Endpoint) async {
        guard !isCheckingUpdate else { return }
        isCheckingUpdate = true
        updateError = nil
        defer { isCheckingUpdate = false }
        guard let baseURL = endpoint.baseURL else {
            updateInfo = nil
            updateError = t("status.invalidURL")
            return
        }
        do {
            updateInfo = try await UpdateChecker.check(baseURL: baseURL,
                                                       token: app.deviceToken(for: endpoint.id))
        } catch {
            updateInfo = nil
            updateError = error.localizedDescription
        }
    }
}

private struct AgentRow: View {

    let item: AgentItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(DSHFormat.text(item.title))
                    .font(.subheadline)
                Spacer(minLength: 6)
                if let status = item.status {
                    StateBadge(text: status, color: status == "running" ? .green : .gray)
                }
            }
            if let cwd = item.cwd, !cwd.isEmpty {
                Text(cwd)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(String(format: t("endpoint.field.lastActivity"), DSHFormat.relative(item.lastActivityAt)))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}
