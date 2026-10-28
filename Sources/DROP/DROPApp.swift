import SwiftUI
import DKWCore

@main
struct DROPApp: App {
    @State private var model = AppModel()
    @State private var tuning = TuningModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(tuning)
                .frame(minWidth: 1000, minHeight: 600)
                .onOpenURL { model.add(urls: [$0]) }
                .onAppear {
                    if DemoMode.isOn, DemoMode.env["DROP_SHOW"] == "about" { openWindow(id: "about") }
                    tuning.settings = model.settings
                    DemoMode.loadTuning(model: model, tuning: tuning)
                    DemoMode.scheduleSnapshot()
                }
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
