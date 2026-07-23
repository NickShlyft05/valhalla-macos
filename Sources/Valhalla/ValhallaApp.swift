import SwiftUI

@main
struct ValhallaApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1_080, minHeight: 720)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Device") {
                Button("Scan for Download Mode Device") {
                    model.scanForDevice()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Read Device PIT") {
                    model.readDevicePIT()
                }
                .disabled(!model.connection.isConnected || model.operationInProgress)
            }
        }
    }
}
