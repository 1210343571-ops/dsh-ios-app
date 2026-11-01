import Combine
import Foundation

/// 所有端点的状态缓存 + 并发轮询（`Promise.allSettled` 语义：单点失败只标记离线，不影响别人）。
@MainActor
final class StatusCenter: ObservableObject {

    @Published private(set) var snapshots: [String: EndpointSnapshot] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshAt: Date?

    private let endpoints: EndpointStore
    private let tokens: TokenStore
    private var pollTask: Task<Void, Never>?

    init(endpoints: EndpointStore, tokens: TokenStore = TokenStore.shared) {
        self.endpoints = endpoints
        self.tokens = tokens
    }

    var totalCount: Int {
        endpoints.endpoints.count
    }

    var onlineCount: Int {
        endpoints.endpoints.reduce(0) { partial, endpoint in
            partial + (snapshot(for: endpoint.id).isOnline ? 1 : 0)
        }
    }

    func snapshot(for endpointID: String) -> EndpointSnapshot {
        snapshots[endpointID] ?? EndpointSnapshot.empty
    }

    func refreshAll() async {
        let list = endpoints.endpoints
        guard !list.isEmpty else {
            snapshots = [:]
            lastRefreshAt = Date()
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var tokenByEndpoint: [String: String] = [:]
        for endpoint in list {
            if let token = tokens.token(for: endpoint.id) {
                tokenByEndpoint[endpoint.id] = token
            }
        }

        var gathered: [String: EndpointSnapshot] = [:]
        await withTaskGroup(of: SnapshotResult.self) { group in
            for endpoint in list {
                let token = tokenByEndpoint[endpoint.id]
                group.addTask {
                    SnapshotResult(endpointID: endpoint.id,
                                   snapshot: await fetchEndpointSnapshot(endpoint: endpoint, token: token))
                }
            }
            for await item in group {
                gathered[item.endpointID] = item.snapshot
            }
        }

        snapshots = gathered
        lastRefreshAt = Date()

        for endpoint in list {
            guard let snapshot = gathered[endpoint.id], snapshot.isOnline else { continue }
            endpoints.touch(id: endpoint.id, at: snapshot.fetchedAt ?? Date())
        }
    }

    func startPolling(seconds: Int) {
        stopPolling()
        let interval = UInt64(max(5, seconds)) * 1_000_000_000
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshAll()
                if Task.isCancelled { return }
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func removeSnapshot(for endpointID: String) {
        snapshots.removeValue(forKey: endpointID)
    }

    func reset() {
        snapshots = [:]
        lastRefreshAt = nil
        isRefreshing = false
    }
}

/// 自由函数（非 actor 隔离），在 TaskGroup 的子任务里安全调用。
private func fetchEndpointSnapshot(endpoint: Endpoint, token: String?) async -> EndpointSnapshot {    var snapshot = EndpointSnapshot()
    snapshot.fetchedAt = Date()

    guard let baseURL = endpoint.baseURL else {
        snapshot.connection = .offline(t("status.invalidURL"))
        return snapshot
    }

    let started = Date()
    do {
        let status = try await StatusClient.status(baseURL: baseURL, token: token)
        snapshot.status = status
        snapshot.connection = .online
        snapshot.latencyMs = Date().timeIntervalSince(started) * 1000
    } catch {
        snapshot.connection = .offline(error.localizedDescription)
    }
    return snapshot
}

/// TaskGroup 的子任务返回值（用结构体而不是元组，保证 Sendable 诉求明确）。
private struct SnapshotResult: Sendable {
    let endpointID: String
    let snapshot: EndpointSnapshot
}
