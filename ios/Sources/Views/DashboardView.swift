import SwiftUI
import UIKit

/// 原生仪表盘：并发拉取全部端点 status，显示在线/版本/running agents；下拉刷新 + 前台轮询。
struct DashboardView: View {

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var endpoints: EndpointStore
    @EnvironmentObject private var status: StatusCenter

    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                summarySection

                if endpoints.isEmpty {
                    Section {
                        emptyRow
                    }
                } else {
                    Section {
                        ForEach(endpoints.endpoints) { endpoint in
                            NavigationLink {
                                EndpointDetailView(endpointID: endpoint.id)
                            } label: {
                                EndpointRow(endpoint: endpoint,
                                            snapshot: status.snapshot(for: endpoint.id))
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    app.openWorkspace(for: endpoint)
                                } label: {
                                    Label(t("dashboard.workspace"), systemImage: "macwindow")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    app.deleteEndpoint(id: endpoint.id)
                                } label: {
                                    Label(t("common.delete"), systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text(t("dashboard.endpoints"))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(t("dashboard.title"))
            .refreshable {
                await status.refreshAll()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task { await status.refreshAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel(t("common.refresh"))
                    .disabled(status.isRefreshing)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(t("dashboard.add"))
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddEndpointView()
            }
        }
    }

    private var summarySection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                MetricTile(title: t("dashboard.metric.online"),
                           value: "\(status.onlineCount)/\(status.totalCount)",
                           icon: "wifi",
                           tint: .green)
                MetricTile(title: t("dashboard.metric.agents"),
                           value: DSHFormat.number(totalRunningAgents),
                           icon: "person.2.fill",
                           tint: .blue)
                MetricTile(title: t("dashboard.metric.sessions"),
                           value: DSHFormat.number(totalSessions),
                           icon: "bubble.left.and.bubble.right.fill",
                           tint: .purple)
                MetricTile(title: t("dashboard.metric.jobs"),
                           value: DSHFormat.number(totalRunningJobs),
                           icon: "gearshape.2.fill",
                           tint: .orange)
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            .listRowBackground(Color.clear)

            InfoRow(title: t("dashboard.lastRefresh"),
                    value: DSHFormat.timestamp(status.lastRefreshAt))
        } header: {
            Text(t("dashboard.summary"))
        }
    }

    private var emptyRow: some View {
        VStack(spacing: 14) {
            EmptyHint(icon: "desktopcomputer",
                      title: t("dashboard.empty.title"),
                      message: t("dashboard.empty.message"))
            Button {
                showingAdd = true
            } label: {
                Label(t("dashboard.add"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
    }

    private var totalRunningAgents: Int {
        endpoints.endpoints.reduce(0) { partial, endpoint in
            partial + (status.snapshot(for: endpoint.id).status?.agents?.running ?? 0)
        }
    }

    private var totalSessions: Int {
        endpoints.endpoints.reduce(0) { partial, endpoint in
            partial + (status.snapshot(for: endpoint.id).status?.sessions?.total ?? 0)
        }
    }

    private var totalRunningJobs: Int {
        endpoints.endpoints.reduce(0) { partial, endpoint in
            partial + (status.snapshot(for: endpoint.id).status?.jobs?.running ?? 0)
        }
    }
}

private struct MetricTile: View {

    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(tint)
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        }
    }
}

private struct EndpointRow: View {

    let endpoint: Endpoint
    let snapshot: EndpointSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusDot(snapshot: snapshot)
                Text(endpoint.name)
                    .font(.headline)
                Spacer(minLength: 6)
                if let agents = snapshot.status?.agents?.running, agents > 0 {
                    StateBadge(text: String(format: t("dashboard.badge.agents"), agents), color: .blue)
                }
            }

            Text(endpoint.url)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 12) {
                Label(DSHFormat.text(snapshot.status?.host?.dshVersion), systemImage: "shippingbox")
                if let sessions = snapshot.status?.sessions?.total {
                    Label(String(sessions), systemImage: "bubble.left.and.bubble.right")
                }
                if let jobs = snapshot.status?.jobs?.running, jobs > 0 {
                    Label(String(jobs), systemImage: "gearshape.2")
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)

            if let reason = snapshot.offlineReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
            } else {
                Text(String(format: t("dashboard.lastSeen"), DSHFormat.relative(endpoint.lastSeenAt)))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
