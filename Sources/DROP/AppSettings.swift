import Foundation
import Observation

/// Réglages mémorisés pour toujours (UserDefaults).
@Observable
final class AppSettings {
    private let d: UserDefaults

    var libraryPath: String { didSet { d.set(libraryPath, forKey: "libraryPath") } }
    var outputPath: String { didSet { d.set(outputPath, forKey: "outputPath") } }
    var lastArtist: String { didSet { d.set(lastArtist, forKey: "lastArtist") } }
    var fallbackPaths: [String] { didSet { d.set(fallbackPaths, forKey: "fallbackPaths") } }
    var skippedSetup: Bool { didSet { d.set(skippedSetup, forKey: "skippedSetup") } }

    init(defaults: UserDefaults = .standard) {
        d = defaults
        libraryPath = d.string(forKey: "libraryPath") ?? ""
        outputPath = d.string(forKey: "outputPath") ?? ""
        lastArtist = d.string(forKey: "lastArtist") ?? ""
        fallbackPaths = d.stringArray(forKey: "fallbackPaths") ?? []
        skippedSetup = d.bool(forKey: "skippedSetup")
    }

    var needsSetup: Bool { libraryPath.isEmpty && !skippedSetup }
}
