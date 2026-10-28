import Foundation

/// Index "nom de fichier (minuscule) → chemins" d'un dossier de samples.
public struct SearchIndex: Sendable, Codable {
    public let root: String
    public let signature: String
    public let fileCount: Int
    public let byName: [String: [String]]

    public func paths(named fileName: String) -> [String] {
        byName[fileName.lowercased()] ?? []
    }
}

public enum Indexer {
    /// Parcourt `root` et construit l'index. `maxDepth` limite la profondeur (nil = illimité).
    /// Fonction synchrone : à appeler hors du thread principal.
    public static func scan(root: URL, maxDepth: Int? = nil) -> SearchIndex {
        var byName: [String: [String]] = [:]
        var count = 0, dirCount = 0
        var maxMTime: TimeInterval = 0
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        if let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let url as URL in e {
                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true {
                    dirCount += 1
                    if let m = values?.contentModificationDate?.timeIntervalSince1970 { maxMTime = max(maxMTime, m) }
                    if let maxDepth, e.level >= maxDepth { e.skipDescendants() }
                } else if AudioFiles.isAudio(url.lastPathComponent) {
                    byName[url.lastPathComponent.lowercased(), default: []].append(url.path)
                    count += 1
                }
            }
        }
        return SearchIndex(root: root.path, signature: "\(dirCount)-\(Int(maxMTime))-\(count)",
                           fileCount: count, byName: byName)
    }
}

/// Cache disque des index (~/Library/Application Support/DROP/Index).
public enum IndexCache {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DROP/Index", isDirectory: true)
    }

    static func file(for root: String) -> URL {
        var hash: UInt64 = 14695981039346656037
        for b in root.utf8 { hash = (hash ^ UInt64(b)) &* 1099511628211 }
        return directory.appendingPathComponent(String(hash, radix: 16) + ".json")
    }

    public static func load(root: String) -> SearchIndex? {
        guard let data = try? Data(contentsOf: file(for: root)) else { return nil }
        return try? JSONDecoder().decode(SearchIndex.self, from: data)
    }

    public static func save(_ index: SearchIndex) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(index) { try? data.write(to: file(for: index.root)) }
    }

    /// Rescanne le dossier et met à jour le cache. `changed` = false si rien n'a bougé.
    public static func refresh(root: URL, maxDepth: Int? = nil, previous: SearchIndex? = nil) -> (index: SearchIndex, changed: Bool) {
        let fresh = Indexer.scan(root: root, maxDepth: maxDepth)
        let old = previous ?? load(root: root.path)
        let changed = old?.signature != fresh.signature
        if changed { save(fresh) }
        return (fresh, changed)
    }
}
