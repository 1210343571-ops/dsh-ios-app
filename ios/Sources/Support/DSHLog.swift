import Foundation
import os

/// 统一日志入口。所有失败分支都通过它留痕，避免空的 catch 块。
enum DSHLog {

    private static let logger = Logger(subsystem: "com.deepseek.dshmobile", category: "app")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
