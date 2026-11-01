import SwiftUI

/// 应用根视图：锁定态与主界面之间的切换、全局提示、前后台生命周期。
struct RootView: View {

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if app.isLocked {
                LockView()
            } else {
                RootTabView()
            }
        }
        // 语言切换后重建整棵视图树，让所有 t(...) 文案立即刷新。
        .id(settings.language)
        .onAppear {
            app.appDidBecomeActive()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                app.appDidBecomeActive()
            } else if phase == .background {
                app.appDidEnterBackground()
            }
        }
        .alert(app.alert?.title ?? "", isPresented: alertPresented) {
            Button(t("common.ok"), role: .cancel) {
                app.alert = nil
            }
        } message: {
            Text(app.alert?.message ?? "")
        }
    }

    private var alertPresented: Binding<Bool> {
        Binding(get: { app.alert != nil },
                set: { newValue in
                    if !newValue { app.alert = nil }
                })
    }
}
