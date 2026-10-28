import Foundation

/// Un son trouvé dans un projet, prêt à être affiché puis copié.
public struct SampleItem: Identifiable, Sendable {
    public let id = UUID()
    public let originalPath: String
    public let fileName: String
    public let channelName: String?
    public var resolved: URL?
    public var source: ResolveSource
    public var type: SoundType
    public var detectedBy: DetectionSource
    public var included: Bool

    public var isFound: Bool { resolved != nil }

    public init(originalPath: String, fileName: String, channelName: String?, resolved: URL?,
                source: ResolveSource, type: SoundType, detectedBy: DetectionSource, included: Bool) {
        self.originalPath = originalPath; self.fileName = fileName; self.channelName = channelName
        self.resolved = resolved; self.source = source; self.type = type
        self.detectedBy = detectedBy; self.included = included
    }
}

public struct AnalyzedProject: Sendable {
    public let flpURL: URL
    public let defaultTitle: String
    public var items: [SampleItem]
    public let truncated: Bool
}

public enum ProjectAnalyzer {
    public static func analyze(flp url: URL, resolver: SampleResolver) throws -> AnalyzedProject {
        let project = try FLPParser.parse(url: url)
        var seen = Set<String>()
        var seenResolved = Set<String>()
        var items: [SampleItem] = []
        for ref in project.samples where AudioFiles.isAudio(ref.path) {
            let key = ref.path.lowercased()
            guard seen.insert(key).inserted else { continue } // même fichier utilisé plusieurs fois
            let (resolved, source) = resolver.resolve(path: ref.path)
            if let resolved, !seenResolved.insert(resolved.standardizedFileURL.path).inserted { continue }
            let fileName = AudioFiles.fileName(of: ref.path)
            let parent = resolved?.deletingLastPathComponent().lastPathComponent ?? AudioFiles.parentFolderName(of: ref.path)
            let detection = Classifier.detect(fileName: fileName, parentFolder: parent, channelName: ref.channelName)
            items.append(SampleItem(originalPath: ref.path, fileName: fileName, channelName: ref.channelName,
                                    resolved: resolved, source: source, type: detection.type,
                                    detectedBy: detection.source, included: resolved != nil))
        }
        return AnalyzedProject(flpURL: url, defaultTitle: url.deletingPathExtension().lastPathComponent,
                               items: items, truncated: project.truncated)
    }

    /// Relance la recherche des sons manquants (sans toucher aux types choisis par l'utilisateur).
    public static func reresolve(_ items: [SampleItem], resolver: SampleResolver) -> [SampleItem] {
        items.map { item in
            guard !item.isFound else { return item }
            let (url, source) = resolver.resolve(path: item.originalPath)
            guard let url else { return item }
            var copy = item
            copy.resolved = url
            copy.source = source
            copy.included = true
            return copy
        }
    }
}
