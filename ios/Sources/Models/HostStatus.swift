import Foundation

/// `GET /__mobile/api/status` 响应（schemaVersion 1）。
/// 契约见 docs/SPEC.md 2.4；所有字段可选，任何一项采集失败都不能让整个页面空白。
struct HostStatus: Codable, Equatable, Sendable {

    var schemaVersion: Int?
    var generatedAt: Date?
    var host: HostInfo?
    var sessions: SessionsInfo?
    var agents: AgentsInfo?
    var teams: TeamsInfo?
    var jobs: JobsInfo?
    var schedules: SchedulesInfo?
    var approvals: ApprovalsInfo?
    var devices: DevicesInfo?
    var update: UpdateSummary?

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case host
        case sessions
        case agents
        case teams
        case jobs
        case schedules
        case approvals
        case devices
        case update
    }
}

struct HostInfo: Codable, Equatable, Sendable {
    var id: String?
    var name: String?
    var platform: String?
    var release: String?
    var gatewayUrl: String?
    var gatewayUrls: [String]?
    var upstreamUrl: String?
    var dshVersion: String?
    var gatewayVersion: String?
    var startedAt: Date?
    var uptimeMs: Double?
}

struct SessionsInfo: Codable, Equatable, Sendable {
    var total: Int?
    var active: Int?
    var available: Bool?
}

struct AgentsInfo: Codable, Equatable, Sendable {
    var running: Int?
    var idle: Int?
    var available: Bool?
    var items: [AgentItem]?
}

struct AgentItem: Codable, Equatable, Sendable, Identifiable {
    var id: String?
    var title: String?
    var status: String?
    var cwd: String?
    var lastActivityAt: Date?

    /// `id` 缺失时用标题兜底，保证 ForEach 可用。
    var stableID: String {
        id ?? title ?? UUID().uuidString
    }
}

struct TeamsInfo: Codable, Equatable, Sendable {
    var available: Bool?
    var members: Int?
    var tasks: TeamTasks?
}

struct TeamTasks: Codable, Equatable, Sendable {
    var pending: Int?
    var inProgress: Int?
    var completed: Int?
}

struct JobsInfo: Codable, Equatable, Sendable {
    var available: Bool?
    var running: Int?
    var total: Int?
}

struct SchedulesInfo: Codable, Equatable, Sendable {
    var available: Bool?
    var active: Int?
}

struct ApprovalsInfo: Codable, Equatable, Sendable {
    var available: Bool?
    var pending: Int?
}

struct DevicesInfo: Codable, Equatable, Sendable {
    var count: Int?
    var lastSeenAt: Date?
}

struct UpdateSummary: Codable, Equatable, Sendable {
    var channel: String?
    var current: String?
    var latest: String?
    var updateAvailable: Bool?
    var checkedAt: Date?
    var sourceUrl: String?
    var error: String?
}

/// 单个端点的一次探测结果（`StatusCenter` 里按 endpoint.id 缓存）。
struct EndpointSnapshot: Equatable, Sendable {

    enum Connection: Equatable, Sendable {
        case unknown
        case online
        case offline(String)
    }

    var connection: Connection = .unknown
    var status: HostStatus?
    var fetchedAt: Date?
    var latencyMs: Double?

    var isOnline: Bool {
        connection == .online
    }

    var offlineReason: String? {
        if case .offline(let reason) = connection { return reason }
        return nil
    }

    var runningAgents: Int? {
        status?.agents?.running
    }

    static let empty = EndpointSnapshot()
}
