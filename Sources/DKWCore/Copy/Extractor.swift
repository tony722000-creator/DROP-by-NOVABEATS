import Foundation

public struct ExtractionJob: Sendable {
    public var flpName: String
    public var artist: String
    public var title: String
    public var outputRoot: URL
    public var items: [SampleItem]

    public init(flpName: String, artist: String, title: String, outputRoot: URL, items: [SampleItem]) {
        self.flpName = flpName; self.artist = artist; self.title = title
        self.outputRoot = outputRoot; self.items = items
    }
}

public struct CopiedFile: Sendable {
    public let type: SoundType
    public let source: URL
    public let destination: URL
}

public struct ExtractionReport: Sendable, Identifiable {
    public let id = UUID()
    public let flpName: String
    public let destination: URL
    public let copied: [CopiedFile]
    public let notFound: [SampleItem]
    public let failed: [(item: SampleItem, reason: String)]
    /// Fichiers dont les balises intégrées n'ont pas pu être retirées (OGG, fichier abîmé) :
    /// copiés tels quels, mais sans les infos macOS attachées.
    public let metadataKept: [String]

    public var countsByType: [(type: SoundType, count: Int)] {
        SoundType.allCases.compactMap { t in
            let n = copied.filter { $0.type == t }.count
            return n > 0 ? (t, n) : nil
        }
    }
}

public enum Extractor {
    /// COPIE (jamais de déplacement ni de modification des originaux).
    public static func run(_ job: ExtractionJob) throws -> ExtractionReport {
        let artist = Naming.sanitize(job.artist, underscoreSpaces: true).nonEmpty ?? "Inconnu"
        let title = Naming.sanitize(job.title, underscoreSpaces: true).nonEmpty
            ?? Naming.sanitize(job.flpName, underscoreSpaces: true).nonEmpty ?? "Sans_titre"
        let fm = FileManager.default
        // Un seul dossier par type (<sortie>/clap/…), qui se remplit au fil des prods :
        // c'est le nom du fichier (type-artiste-titre) qui le rend unique.
        let root = job.outputRoot

        var copied: [CopiedFile] = []
        var notFound: [SampleItem] = []
        var failed: [(SampleItem, String)] = []
        var counters: [SoundType: Int] = [:]
        var done: [String: URL] = [:] // source déjà copiée → destination
        var metadataKept: [String] = []

        for item in job.items where item.included {
            guard let source = item.resolved else { notFound.append(item); continue }
            let key = source.standardizedFileURL.path
            if done[key] != nil { continue } // même fichier source : une seule copie

            let typeDir = root.appendingPathComponent(item.type.folderName, isDirectory: true)
            do {
                try fm.createDirectory(at: typeDir, withIntermediateDirectories: true)
                let ext = source.pathExtension.lowercased()
                // Contenu final préparé en mémoire (la source n'est que lue) : balises intégrées retirées.
                // Écrire un fichier neuf (au lieu de copier) laisse aussi de côté les infos macOS attachées
                // (icône personnalisée, étiquettes, provenance…).
                let original = try Data(contentsOf: source)
                let finalData: Data
                if let clean = MetadataStripper.strip(original, fileExtension: ext) {
                    finalData = clean
                } else {
                    finalData = original
                    metadataKept.append(source.lastPathComponent)
                }
                var n = counters[item.type, default: 0]
                var dest: URL
                var alreadyThere = false
                repeat {
                    n += 1
                    dest = typeDir.appendingPathComponent(
                        Naming.fileName(type: item.type, artist: artist, title: title, number: n, ext: ext))
                    if fm.fileExists(atPath: dest.path) {
                        if (try? Data(contentsOf: dest)) == finalData { alreadyThere = true }
                        else { continue } // nom pris par un autre son : on ne l'écrase jamais
                    }
                    break
                } while true
                counters[item.type] = n
                if !alreadyThere { try finalData.write(to: dest, options: .withoutOverwriting) }
                done[key] = dest
                copied.append(CopiedFile(type: item.type, source: source, destination: dest))
            } catch {
                failed.append((item, error.localizedDescription))
            }
        }
        return ExtractionReport(flpName: job.flpName, destination: root, copied: copied,
                                notFound: notFound + job.items.filter { $0.included == false && !$0.isFound },
                                failed: failed, metadataKept: metadataKept)
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
