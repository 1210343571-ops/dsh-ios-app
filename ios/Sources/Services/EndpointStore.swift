import Combine
import Foundation

/// 端点列表的持久化：UserDefaults 里存一份 JSON（令牌不在其中，见 `TokenStore`）。
@MainActor
final class EndpointStore: ObservableObject {

    @Published private(set) var endpoints: [Endpoint] = []

    private let defaults: UserDefaults
    private let storageKey = "dsh.endpoints.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    var isEmpty: Bool {
        endpoints.isEmpty
    }

    var count: Int {
        endpoints.count
    }

    func endpoint(withID id: String) -> Endpoint? {
        endpoints.first { $0.id == id }
    }

    func endpoint(withNormalizedURL url: String) -> Endpoint? {
        endpoints.first { $0.url == url }
    }

    func add(_ endpoint: Endpoint) {
        endpoints.append(endpoint)
        save()
    }

    func update(_ endpoint: Endpoint) {
        guard let index = endpoints.firstIndex(where: { $0.id == endpoint.id }) else { return }
        endpoints[index] = endpoint
        save()
    }

    func rename(id: String, name: String) {
        guard let index = endpoints.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        endpoints[index].name = trimmed
        save()
    }

    /// 节流写入：同一端点 2 分钟内不重复落盘，避免每 30 秒轮询都写 UserDefaults。
    func touch(id: String, at date: Date = Date()) {
        guard let index = endpoints.firstIndex(where: { $0.id == id }) else { return }
        if let last = endpoints[index].lastSeenAt, date.timeIntervalSince(last) < 120 { return }
        endpoints[index].lastSeenAt = date
        save()
    }

    func remove(id: String) {
        endpoints.removeAll { $0.id == id }
        save()
    }

    func removeAll() {
        endpoints.removeAll()
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else {
            endpoints = []
            return
        }
        do {
            endpoints = try JSONCoding.decoder.decode([Endpoint].self, from: data)
        } catch {
            DSHLog.error("endpoints decode failed: \(error.localizedDescription)")
            endpoints = []
        }
    }

    private func save() {
        do {
            let data = try JSONCoding.encoder.encode(endpoints)
            defaults.set(data, forKey: storageKey)
        } catch {
            DSHLog.error("endpoints encode failed: \(error.localizedDescription)")
        }
    }
}
