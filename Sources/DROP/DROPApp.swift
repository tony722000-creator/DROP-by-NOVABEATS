import SwiftUI
import DKWCore

@main
struct DROPApp: App {
    @State private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 1000, minHeight: 600)
                .onOpenURL { model.add(urls: [$0]) }
                .onAppear { DemoMode.scheduleSnapshot() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 640)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("À propos de DROP") { openWindow(id: "about") }
            }
            CommandGroup(replacing: .newItem) {
                Button("Ouvrir un projet FL Studio…") { model.openPanel() }
                    .keyboardShortcut("o")
                Button("Tout fermer") { model.clear() }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                    .disabled(model.projects.isEmpty)
            }
        }

        Window("À propos de DROP", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Settings {
            SettingsView().environment(model)
        }
    }
}
