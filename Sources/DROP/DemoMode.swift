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

    /// DROP_DEMO=tuning : kit d'exemple temporaire (dossiers vides) chargé dans l'onglet TUNING KITS.
    @MainActor
    static func loadTuning(model: AppModel, tuning: TuningModel) {
        guard env["DROP_DEMO"] == "tuning" else { return }
        let kit = FileManager.default.temporaryDirectory.appendingPathComponent("DROP demo/TONY CARLOS Drum Kit")
        try? FileManager.default.removeItem(at: kit.deletingLastPathComponent())
        for d in ["808s", "Claps", "Hats", "Kicks", "Snares", "FX", "Percs"] {
            try? FileManager.default.createDirectory(at: kit.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        // bannières de test (jamais intégrées à l'app) : Branding/tuning-kits-test/sources-hd
        model.settings.bannersPath = FileManager.default.currentDirectoryPath + "/Branding/tuning-kits-test/sources-hd"
        if let dir = env["DROP_TEST_BANNERS"] { model.settings.bannersPath = dir }
        model.tab = .tuning
        tuning.load(kit: kit)
        if let cover = env["DROP_TEST_COVER"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { tuning.setImage(URL(fileURLWithPath: cover), for: .cover) }
        }
    }

    @MainActor
    static func load(into model: AppModel) {
        model.settings.skippedSetup = env["DROP_DEMO"] != "setup"
        if env["DROP_DEMO"] == "setup" { model.settings.libraryPath = "" }
        model.settings.outputPath = NSHomeDirectory() + "/Music/DROP"
        model.artist = "TONY CARLOS"
        guard env["DROP_DEMO"] != "empty", env["DROP_DEMO"] != "tuning" else { return }

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
