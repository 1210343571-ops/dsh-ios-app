import Foundation
import LocalAuthentication

enum BiometryKind: String, Equatable, Sendable {
    case none
    case touchID
    case faceID

    /// 设置页展示用（Face ID / Touch ID / 设备密码）。
    var displayName: String {
        switch self {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .none:
            return t("settings.biometric.passcode")
        }
    }
}

struct LockState: Equatable, Sendable {
    var available: Bool
    var kind: BiometryKind

    static let unavailable = LockState(available: false, kind: .none)
}

enum LockResult: Equatable, Sendable {
    case success
    case cancelled
    /// 设备没有可用的生物识别/密码。
    case unavailable(String)
    case failed(String)
}

/// Face ID / Touch ID 解锁。
/// 使用 `.deviceOwnerAuthentication` 策略：生物识别失败或不可用时会自动退回设备密码，
/// 这样永远不会把用户锁在门外（见 docs/SPEC.md 第 6 节）。
enum BiometricLock {

    /// LAErrorDomain 的字面值，避免依赖 SDK 里不同 Xcode 版本的桥接类型名。
    private static let laErrorDomain = "com.apple.LocalAuthentication"

    static func state() -> LockState {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable
        }
        let kind: BiometryKind
        switch context.biometryType {
        case .faceID:
            kind = .faceID
        case .touchID:
            kind = .touchID
        default:
            kind = .none
        }
        return LockState(available: true, kind: kind)
    }

    static func unlock(reason: String) async -> LockResult {
        let context = LAContext()
        context.localizedFallbackTitle = t("lock.fallbackTitle")
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable(error?.localizedDescription ?? t("lock.unavailable"))
        }
        do {
            let success = try await evaluate(context: context,
                                            policy: .deviceOwnerAuthentication,
                                            reason: reason)
            return success ? .success : .failed(t("lock.failedTitle"))
        } catch {
            return mapError(error)
        }
    }

    private static func evaluate(context: LAContext, policy: LAPolicy, reason: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            context.evaluatePolicy(policy, localizedReason: reason) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    private static func mapError(_ error: Error) -> LockResult {
        let nsError = error as NSError
        guard nsError.domain == laErrorDomain else {
            return .failed(nsError.localizedDescription)
        }
        switch nsError.code {
        case -2, -4, -9:
            // userCancel / systemCancel / appCancel
            return .cancelled
        case -5, -6, -7:
            // passcodeNotSet / biometryNotAvailable / biometryNotEnrolled
            return .unavailable(nsError.localizedDescription)
        default:
            return .failed(nsError.localizedDescription)
        }
    }
}
