import Foundation

/// Un dossier ou un fichier son d'un kit.
public struct KitItem: Identifiable, Sendable, Hashable {
    public var id: String { relativePath }
    public let relativePath: String
    public let name: String
    public let depth: Int
    public let isDirectory: Bool
    /// Type reconnu d'après le nom (mêmes règles que l'extraction).
    public let detectedType: SoundType?

    public var target: TuningTarget { .item(relativePath: relativePath, isDirectory: isDirectory) }
}

/// Changement demandé pour une cible.
public enum TuningChange: Sendable {
    case set(png: Data)
    case clear
}

public struct TuningReport: Sendable, Identifiable {
    public let id = UUID()
    public let kitRoot: URL
    public var created = 0      // .nfo créés
    public var updated = 0      // .nfo existants mis à jour
    public var cleared = 0      // habillages retirés
    public var errors: [(name: String, reason: String)] = []
    public var removedAll = false
}

/// Habille un kit pour le Browser de FL Studio : ajoute seulement des .nfo et des images dans .images.
/// Ne modifie, ne déplace et ne supprime JAMAIS les samples.
/// Tout ce que DROP ajoute ou change est noté dans .images/.drop-tuning.json pour pouvoir le retirer.
public enum KitTuner {

    // MARK: Lecture du kit

    public static func scan(kitRoot: URL, includeFiles: Bool) -> [KitItem] {
        var out: [KitItem] = []
        func walk(_ dir: URL, rel: String, depth: Int) {
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            let sorted = entries.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            for url in sorted {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                let name = url.lastPathComponent
                let childRel = rel.isEmpty ? name : rel + "/" + name
                if isDir {
                    out.append(KitItem(relativePath: childRel, name: name, depth: depth, isDirectory: true,
                                       detectedType: Classifier.match(name)))
                    walk(url, rel: childRel, depth: depth + 1)
                } else if includeFiles, AudioFiles.isAudio(name) {
                    out.append(KitItem(relativePath: childRel, name: name, depth: depth, isDirectory: false,
                                       detectedType: Classifier.match((name as NSString).deletingPathExtension)))
                }
            }
        }
        walk(kitRoot, rel: "", depth: 0)
        return out
    }

    /// Image actuellement affichée pour une cible (d'après son .nfo, de DROP ou d'origine).
    public static func currentImage(for target: TuningTarget, kitRoot: URL) -> URL? {
        let nfo = FLBrowserFormat.nfoURL(for: target, kitRoot: kitRoot)
        guard let text = readText(nfo),
              let bitmap = FLBrowserFormat.parse(text)[FLBrowserFormat.bitmapKey.lowercased()], !bitmap.isEmpty else { return nil }
        let url = nfo.deletingLastPathComponent().appendingPathComponent(bitmap.replacingOccurrences(of: "\\", with: "/")).standardizedFileURL
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public static func hasDropTuning(kitRoot: URL) -> Bool {
        FileManager.default.fileExists(atPath: manifestURL(kitRoot).path)
    }

    /// .nfo qui existent déjà sans venir de DROP et que ces changements modifieraient (à confirmer).
    public static func foreignNFOs(touchedBy changes: [TuningTarget: TuningChange], kitRoot: URL) -> [URL] {
        let manifest = loadManifest(kitRoot)
        return changes.keys.compactMap { target in
            let nfo = FLBrowserFormat.nfoURL(for: target, kitRoot: kitRoot)
            guard FileManager.default.fileExists(atPath: nfo.path), manifest.entries[key(nfo, kitRoot)] == nil else { return nil }
            return nfo
        }
        .sorted { $0.path < $1.path }
    }

    // MARK: Appliquer

    public static func apply(_ changes: [TuningTarget: TuningChange], kitRoot: URL) -> TuningReport {
        var report = TuningReport(kitRoot: kitRoot)
        var manifest = loadManifest(kitRoot)
        let fm = FileManager.default
        let images = FLBrowserFormat.imagesFolder(kitRoot: kitRoot)

        for (target, change) in changes.sorted(by: { order($0.key) < order($1.key) }) {
            let nfo = FLBrowserFormat.nfoURL(for: target, kitRoot: kitRoot)
            let k = key(nfo, kitRoot)
            let name = nfo.deletingPathExtension().lastPathComponent
            let existing = readText(nfo)
            var entry = manifest.entries[k]
            do {
                switch change {
                case .set(let png):
                    try fm.createDirectory(at: images, withIntermediateDirectories: true)
                    let imageURL = freeImageURL(for: target, in: images, manifest: manifest, current: entry?.image)
                    try png.write(to: imageURL, options: .atomic)
                    let imageRel = relative(imageURL, to: kitRoot)
                    if let old = entry?.image, old != imageRel { try? fm.removeItem(at: kitRoot.appendingPathComponent(old)) }

                    if entry == nil {
                        entry = existing == nil
                            ? .init(created: true, previous: nil, image: nil)
                            : .init(created: false, previous: previousValues(existing!), image: nil)
                        if existing == nil { report.created += 1 } else { report.updated += 1 }
                    } else {
                        report.updated += 1
                    }
                    entry?.image = imageRel
                    let text = FLBrowserFormat.render(existing: existing, values: [
                        FLBrowserFormat.tipKey: FLBrowserFormat.tipValue(for: target, kitRoot: kitRoot),
                        FLBrowserFormat.bitmapKey: FLBrowserFormat.bitmapValue(image: imageURL, nfo: nfo),
                        FLBrowserFormat.colorKey: FLBrowserFormat.colorValue(),
                    ])
                    try Data(text.utf8).write(to: nfo, options: .atomic)
                    manifest.entries[k] = entry

                case .clear:
                    if let e = entry {
                        try revert(e, nfo: nfo, kitRoot: kitRoot)
                        manifest.entries[k] = nil
                        report.cleared += 1
                    } else if let existing, FLBrowserFormat.parse(existing)[FLBrowserFormat.bitmapKey.lowercased()] != nil {
                        // image d'origine (kit du commerce) : on retire seulement la ligne Bitmap, en notant l'ancienne valeur
                        manifest.entries[k] = .init(created: false, previous: previousValues(existing), image: nil)
                        let text = FLBrowserFormat.render(existing: existing, values: [FLBrowserFormat.bitmapKey: String?.none])
                        try Data(text.utf8).write(to: nfo, options: .atomic)
                        report.cleared += 1
                    }
                }
            } catch {
                report.errors.append((name, error.localizedDescription))
            }
        }
        saveManifest(manifest, kitRoot: kitRoot, report: &report)
        return report
    }

    // MARK: Retirer tout le tuning DROP

    public static func removeAll(kitRoot: URL) -> TuningReport {
        var report = TuningReport(kitRoot: kitRoot)
        report.removedAll = true
        var manifest = loadManifest(kitRoot)
        for (k, entry) in manifest.entries {
            let nfo = k.hasPrefix("/") ? URL(fileURLWithPath: k) : kitRoot.deletingLastPathComponent().appendingPathComponent(k)
            do {
                try revert(entry, nfo: nfo, kitRoot: kitRoot)
                manifest.entries[k] = nil
                report.cleared += 1
            } catch {
                report.errors.append((nfo.deletingPathExtension().lastPathComponent, error.localizedDescription))
            }
        }
        saveManifest(manifest, kitRoot: kitRoot, report: &report)
        return report
    }

    // MARK: Interne

    struct Manifest: Codable {
        var version = 1
        /// clé = chemin du .nfo relatif au dossier qui contient le kit
        var entries: [String: Entry] = [:]
    }

    struct Entry: Codable {
        /// .nfo créé par DROP (sinon : .nfo d'origine dont on a changé des lignes)
        var created: Bool
        /// valeurs d'origine de Tip, Bitmap, Color (nil = ligne absente), pour les remettre
        var previous: [String: String?]?
        /// image copiée par DROP, relative à la racine du kit
        var image: String?
    }

    static func manifestURL(_ kitRoot: URL) -> URL {
        FLBrowserFormat.imagesFolder(kitRoot: kitRoot).appendingPathComponent(FLBrowserFormat.manifestName)
    }

    static func loadManifest(_ kitRoot: URL) -> Manifest {
        guard let data = try? Data(contentsOf: manifestURL(kitRoot)),
              let m = try? JSONDecoder().decode(Manifest.self, from: data) else { return Manifest() }
        return m
    }

    static func saveManifest(_ m: Manifest, kitRoot: URL, report: inout TuningReport) {
        let fm = FileManager.default
        let url = manifestURL(kitRoot)
        if m.entries.isEmpty {
            try? fm.removeItem(at: url)
            // .images retiré seulement s'il est vide (les images d'un kit du commerce restent)
            let images = FLBrowserFormat.imagesFolder(kitRoot: kitRoot)
            let left = ((try? fm.contentsOfDirectory(atPath: images.path)) ?? []).filter { $0 != ".DS_Store" }
            if left.isEmpty { try? fm.removeItem(at: images) }
        } else {
            do {
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try enc.encode(m).write(to: url, options: .atomic)
            } catch {
                report.errors.append(("suivi du tuning", error.localizedDescription))
            }
        }
    }

    /// Remet un .nfo dans son état d'avant DROP et supprime l'image ajoutée.
    static func revert(_ e: Entry, nfo: URL, kitRoot: URL) throws {
        let fm = FileManager.default
        if e.created {
            if fm.fileExists(atPath: nfo.path) { try fm.removeItem(at: nfo) }
        } else if let previous = e.previous, let text = readText(nfo) {
            let restored = FLBrowserFormat.render(existing: text, values: previous)
            try Data(restored.utf8).write(to: nfo, options: .atomic)
        }
        if let img = e.image { try? fm.removeItem(at: kitRoot.appendingPathComponent(img)) }
    }

    static func previousValues(_ text: String) -> [String: String?] {
        let parsed = FLBrowserFormat.parse(text)
        var out: [String: String?] = [:]
        for k in [FLBrowserFormat.tipKey, FLBrowserFormat.bitmapKey, FLBrowserFormat.colorKey] {
            out[k] = .some(parsed[k.lowercased()])
        }
        return out
    }

    static func readText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    static func key(_ nfo: URL, _ kitRoot: URL) -> String {
        relative(nfo, to: kitRoot.deletingLastPathComponent())
    }

    /// Chemin relatif sans « standardiser » : macOS transforme /private/tmp en /tmp seulement si le fichier
    /// existe déjà, ce qui rendait la comparaison incohérente (fichier pas encore créé).
    static func relative(_ url: URL, to base: URL) -> String {
        let b = base.pathComponents, u = url.pathComponents
        guard u.count > b.count, Array(u[0..<b.count]) == b else { return url.path }
        return u[b.count...].joined(separator: "/")
    }

    /// Nom libre dans .images : jamais une image du kit d'origine (d'un autre auteur).
    static func freeImageURL(for target: TuningTarget, in images: URL, manifest: Manifest, current: String?) -> URL {
        let kitRoot = images.deletingLastPathComponent()
        let ours = Set(manifest.entries.values.compactMap(\.image))
        let base = FLBrowserFormat.imageName(for: target)
        let stem = (base as NSString).deletingPathExtension
        var n = 0
        while true {
            let name = n == 0 ? base : "\(stem)-drop\(n == 1 ? "" : String(n)).png"
            let url = images.appendingPathComponent(name)
            let rel = relative(url, to: kitRoot)
            if rel == current || !FileManager.default.fileExists(atPath: url.path) && !ours.contains(rel) { return url }
            n += 1
        }
    }

    static func order(_ t: TuningTarget) -> String {
        if case .item(let rel, _) = t { return "1" + rel }
        return "0"
    }
}
