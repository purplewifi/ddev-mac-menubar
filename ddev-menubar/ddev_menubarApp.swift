import SwiftUI

@main
struct ddev_menubarApp: App {
    @State private var store = DdevProjectStore()
    @StateObject private var updater = UpdaterController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store)
                .environmentObject(updater)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: "logs", for: LogSession.self) { $session in
            if let session {
                LogViewerView(session: session)
            }
        }
        .defaultSize(width: 780, height: 520)
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        if store.runningCount > 0 {
            Label("DDEV", systemImage: "shippingbox.fill")
        } else {
            Label("DDEV", systemImage: "shippingbox")
        }
    }
}
