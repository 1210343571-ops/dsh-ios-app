import SwiftUI

/// 四个主 Tab：仪表盘 / 工作台 / 更新 / 设置（见 docs/SPEC.md 第 6 节）。
struct RootTabView: View {

    @EnvironmentObject private var app: AppModel

    var body: some View {
        TabView(selection: $app.selectedTab) {
            DashboardView()
                .tabItem {
                    Label(t("tab.dashboard"), systemImage: "square.grid.2x2.fill")
                }
                .tag(AppTab.dashboard)

            WorkspaceTabView()
                .tabItem {
                    Label(t("tab.workspace"), systemImage: "macwindow")
                }
                .tag(AppTab.workspace)

            UpdateView()
                .tabItem {
                    Label(t("tab.updates"), systemImage: "arrow.triangle.2.circlepath")
                }
                .tag(AppTab.updates)

            SettingsView()
                .tabItem {
                    Label(t("tab.settings"), systemImage: "gearshape.fill")
                }
                .tag(AppTab.settings)
        }
        .overlay(alignment: .top) {
            if app.isBusyPairing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(t("pair.deeplink.progress"))
                        .font(.footnote)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 8)
            }
        }
    }
}
