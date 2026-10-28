import SwiftUI
import AppKit
import DKWCore

/// Mode démonstration, pour fabriquer des captures d'écran sans toucher aux vrais réglages :
///   DROP_DEMO=full|empty|setup   remplit l'interface avec des sons d'exemple (réglages dans un domaine séparé)
///   DROP_SHOW=about   ouvre aussi la fenêtre À propos (c'est elle qui est capturée)
///   DROP_SNAPSHOT=<chemin.png>   enregistre la fenêtre en PNG après 3 s puis quitte
enum DemoMode {
    static let env = ProcessInfo.processInfo.environment
    static let isOn = env["DROP_DEMO"] != nil
    static let snapshotPath = env["DROP_SNAPSHOT"]
    static var isSnapshot: Bool { snapshotPath != nil }
    static let defaults = UserDefaults(suiteName: "com.tonycarlos.drop.demo") ?? .standard

    @MainActor
    static func load(into model: AppModel) {
        model.settings.skippedSetup = env["DROP_DEMO"] != "setup"
        if env["DROP_DEMO"] == "setup" { model.settings.libraryPath = "" }
        model.settings.outputPath = NSHomeDirectory() + "/Music/DROP"
        model.artist = "NOVABEATS"
        guard env["DROP_DEMO"] != "empty" else { return }

        func project(_ name: String, title: String, _ files: [(String, Bool)]) -> Project {
            let p = Project(flpURL: URL(fileURLWithPath: "/tmp/\(name).flp"))
            p.title = title
            p.items = files.map { file, found in
                let d = Classifier.detect(fileName: file, parentFolder: nil, channelName: nil)
                return SampleItem(originalPath: "C:\\Samples\\\(file)", fileName: file, channelName: nil,
                                  resolved: found ? URL(fileURLWithPath: "/tmp/\(file)") : nil,
                                  source: found ? .library : .missing, type: d.type, detectedBy: d.source, included: found)
            }
            p.state = .ready
            return p
        }
        let main = project("my_track", title: "MY TRACK", [
            ("808_Dark.wav", true), ("Kick_Big.wav", true), ("Vox_Chop_A.wav", false), ("Clap_Classic.wav", true),
            ("Hihat_Open.wav", true), ("Snare_Dry.wav", true), ("Perc_Shaker_07.wav", true),
        ])
        model.projects = [main, project("monalisa", title: "", [("Kick 01.wav", true), ("Open Hat 03.wav", true)])]
        model.selectedProjectID = main.id
    }

    /// Enregistre le contenu de la fenêtre principale en PNG (sans autorisation d'enregistrement d'écran).
    @MainActor
    static func scheduleSnapshot() {
        guard let path = snapshotPath else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            let wantAbout = env["DROP_SHOW"] == "about"
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && (!wantAbout || $0.title.contains("propos")) }),
                  let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(2) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            NSApp.terminate(nil)
        }
    }
}
