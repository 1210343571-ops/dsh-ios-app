import Foundation

/// ISO8601 解析：网关返回的时间戳可能带/不带毫秒，两种都接受。
enum DateParsing {

    private static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return withFractionalSeconds.date(from: trimmed) ?? withoutFractionalSeconds.date(from: trimmed)
    }
}

extension Date {

    /// 解析失败时解码器会返回 1970-01-01，用该哨兵值表示「未知」。
    var dshIsUnknown: Bool {
        timeIntervalSince1970 <= 0
    }
}

enum DSHFormat {

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    /// 相对时间（"3 分钟前"）；未知显示 `common.unknown`。
    static func relative(_ date: Date?) -> String {
        guard let date, !date.dshIsUnknown else { return t("common.unknown") }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func timestamp(_ date: Date?) -> String {
        guard let date, !date.dshIsUnknown else { return t("common.unknown") }
        return timestampFormatter.string(from: date)
    }

    /// 毫秒时长 → "2 小时 15 分"。
    static func uptime(milliseconds: Double?) -> String {
        guard let milliseconds, milliseconds > 0 else { return t("common.unknown") }
        let totalMinutes = Int(milliseconds / 60_000)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60
        var parts: [String] = []
        if days > 0 { parts.append(String(format: t("format.days"), days)) }
        if hours > 0 { parts.append(String(format: t("format.hours"), hours)) }
        if minutes > 0 && days == 0 { parts.append(String(format: t("format.minutes"), minutes)) }
        if parts.isEmpty { parts.append(String(format: t("format.seconds"), Int(milliseconds / 1000))) }
        return parts.joined(separator: " ")
    }

    static func number(_ value: Int?) -> String {
        guard let value else { return t("common.unknown") }
        return String(value)
    }

    static func text(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return t("common.unknown")
        }
        return value
    }

    static func latency(_ milliseconds: Double?) -> String {
        guard let milliseconds else { return t("common.unknown") }
        return String(format: "%.0f ms", milliseconds)
    }
}
