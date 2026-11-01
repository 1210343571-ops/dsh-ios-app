import SwiftUI
import UIKit

/// 在线状态圆点。
struct StatusDot: View {

    let snapshot: EndpointSnapshot
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityLabel(text)
    }

    var color: Color {
        switch snapshot.connection {
        case .online:
            return .green
        case .unknown:
            return .gray
        case .offline:
            return .red
        }
    }

    var text: String {
        switch snapshot.connection {
        case .online:
            return t("status.online")
        case .unknown:
            return t("status.unknown")
        case .offline:
            return t("status.offline")
        }
    }
}

/// 一行「标签 : 值」。
struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct StateBadge: View {

    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
    }
}

struct EmptyHint: View {

    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 38))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 16)
    }
}

struct ErrorBanner: View {

    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
