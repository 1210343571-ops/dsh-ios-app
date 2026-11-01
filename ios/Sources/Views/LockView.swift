import SwiftUI
import UIKit

/// Face ID / Touch ID 锁屏。打开即自动请求验证，失败退回设备密码（由 LAContext 策略保证）。
struct LockView: View {

    @EnvironmentObject private var app: AppModel
    @State private var isUnlocking = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 54))
                .foregroundColor(.accentColor)

            Text(t("lock.title"))
                .font(.title2.bold())

            Text(t("lock.subtitle"))
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Button {
                Task { await attemptUnlock() }
            } label: {
                HStack(spacing: 8) {
                    if isUnlocking {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: app.biometry.kind == .faceID ? "faceid" : "touchid")
                    }
                    Text(t("lock.unlock"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isUnlocking)
            .padding(.horizontal, 44)
            .padding(.top, 8)

            Spacer()

            Text(app.biometry.kind.displayName)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
        .task {
            await attemptUnlock()
        }
    }

    @MainActor
    private func attemptUnlock() async {
        guard !isUnlocking else { return }
        isUnlocking = true
        await app.unlock()
        isUnlocking = false
    }
}
