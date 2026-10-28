import Foundation

public enum ResolveSource: String, Sendable {
    case exact, library, downloads, fallback, missing

    public var label: String {
        switch self {
        case .exact: return "chemin d'origine"
        case .library: return "bibliothèque"
        case .downloads: return "Téléchargements"
        case .fallback: return "dossier de secours"
        case .missing: return "introuvable"
        }
    }
}

/// Retrouve un sample dans l'ordre : chemin exact → bibliothèque → Téléchargements → dossiers de secours.
public struct SampleResolver: Sendable {
    public var library: SearchIndex?
    public var downloads: SearchIndex?
    public var fallbacks: [SearchIndex]

    public init(library: SearchIndex? = nil, downloads: SearchIndex? = nil, fallbacks: [SearchIndex] = []) {
        self.library = library
        self.downloads = downloads
        self.fallbacks = fallbacks
    }

    public func resolve(path: String) -> (url: URL?, source: ResolveSource) {
        let fm = FileManager.default
        for candidate in FLPathVariables.candidates(for: path) {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate, isDirectory: &isDir), !isDir.boolValue {
                return (URL(fileURLWithPath: candidate), .exact)
            }
        }
        let name = AudioFiles.fileName(of: path)
        let wantedFolders = Array(AudioFiles.components(of: path).dropLast())
        let stages: [(SearchIndex?, ResolveSource)] =
            [(library, .library), (downloads, .downloads)] + fallbacks.map { ($0, .fallback) }
        for (index, source) in stages {
            if let index, let hit = Self.best(index.paths(named: name), wantedFolders: wantedFolders) {
                return (URL(fileURLWithPath: hit), source)
            }
        }
        return (nil, .missing)
    }

    /// Parmi plusieurs fichiers du même nom, préfère celui dont les dossiers ressemblent le plus au chemin d'origine.
    static func best(_ paths: [String], wantedFolders: [String]) -> String? {
        let fm = FileManager.default
        let existing = paths.filter { fm.fileExists(atPath: $0) }
        guard existing.count > 1 else { return existing.first }
        let wanted = wantedFolders.map { $0.lowercased() }
        func score(_ p: String) -> Int {
            let folders = AudioFiles.components(of: p).dropLast().map { $0.lowercased() }
            var n = 0
            for (a, b) in zip(folders.reversed(), wanted.reversed()) { if a == b { n += 1 } else { break } }
            return n
        }
        return existing.max { (score($0), -$0.count) < (score($1), -$1.count) }
    }
}
