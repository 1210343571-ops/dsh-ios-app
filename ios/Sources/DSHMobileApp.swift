import SwiftUI

@main
struct DSHMobileApp: App {

    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.endpoints)
                .environmentObject(model.settings)
                .environmentObject(model.status)
                .onOpenURL { url in
                    model.handleOpenURL(url)
                }
        }
    }
}
