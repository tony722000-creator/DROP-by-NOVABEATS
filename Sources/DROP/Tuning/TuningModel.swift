import Foundation
import AppKit
import Observation
import UniformTypeIdentifiers
import DKWCore

/// État de l'onglet TUNING KITS. Indépendant de l'extraction : rien ici ne touche à l'analyse ni à la copie.
@MainActor
@Observable
final class TuningModel {
    enum Change {
        case set(png: Data, preview: NSImage, proposed: Bool)
        case clear
    }

    var kitRoot: URL?
    var includeFiles = false { didSet { if oldValue != includeFiles { rescan() } } }
    var items: [KitItem] = []
    var isLoading = false
    /// Images déjà affichées dans FL (d'après les .nfo du kit).
    var current: [TuningTarget: NSImage] = [:]
    /// Changements pas encore appliqués.
    var changes: [TuningTarget: Change] = [:]
    var hasDropTuning = false
    var isApplying = false
    /// Réglages partagés (dossier de bannières) ; branché au lancement.
    var settings: AppSettings?

    var report: TuningReport?
    var showReport = false
    var foreignToConfirm: [URL] = []
    var confirmForeign = false
    var confirmRemove = false

    static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff", "webp", "gif", "bmp"]

    // MARK: Chargement

    func chooseKit() {
        if let url = FolderPicker.pick(message: "Choisis le dossier principal du kit") { load(kit: url) }
    }

    func load(kit url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
        kitRoot = url
        changes = [:]
        current = [:]
        items = []
        rescan(proposeBanners: true)
    }

    func close() {
        kitRoot = nil; items = []; changes = [:]; current = [:]; hasDropTuning = false
    }

    private func rescan(proposeBanners: Bool = false) {
        guard let kit = kitRoot else { return }
        isLoading = true
        let files = includeFiles
        Task {
            let scanned = await Task.detached { () -> ([KitItem], [TuningTarget: URL], Bool) in
                let items = KitTuner.scan(kitRoot: kit, includeFiles: files)
                var imgs: [TuningTarget: URL] = [:]
                for t in [TuningTarget.cover] + items.map(\.target) {
                    if let u = KitTuner.currentImage(for: t, kitRoot: kit) { imgs[t] = u }
                }
                return (items, imgs, KitTuner.hasDropTuning(kitRoot: kit))
            }.value
            guard kitRoot == kit else { return }
            items = scanned.0
            current = scanned.1.compactMapValues { NSImage(contentsOf: $0) }
            hasDropTuning = scanned.2
            isLoading = false
            if proposeBanners { proposeDropBanners() }
        }
    }

    /// Dossiers reconnus (Claps → CLAP…) sans image : on propose la bannière du dossier de bannières choisi.
    private func proposeDropBanners() {
        guard let folder = settings?.bannersPath, !folder.isEmpty else { return }
        for item in items where item.isDirectory && current[item.target] == nil && changes[item.target] == nil {
            guard let type = item.detectedType, let png = DropBanners.banner(for: type, in: folder),
                  let preview = NSImage(data: png) else { continue }
            changes[item.target] = .set(png: png, preview: preview, proposed: true)
        }
    }

    // MARK: Images

    func chooseImage(for target: TuningTarget) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.allowsMultipleSelection = false
        panel.message = target == .cover ? "Choisis l'image de la cover (carrée de préférence)" : "Choisis une image (bannière large de préférence)"
        panel.prompt = "Choisir"
        if panel.runModal() == .OK, let url = panel.url { setImage(url, for: target) }
    }

    /// Prépare l'image (redimensionnée, recadrée) en arrière-plan ; l'aperçu montre le résultat exact.
    func setImage(_ url: URL, for target: TuningTarget) {
        guard Self.imageTypes.contains(url.pathExtension.lowercased()) else { return }
        let kind: TuningImage.Kind = target == .cover ? .cover : .banner
        Task {
            guard let png = await Task.detached(operation: { TuningImage.prepare(url, as: kind) }).value,
                  let preview = NSImage(data: png) else { return }
            changes[target] = .set(png: png, preview: preview, proposed: false)
        }
    }

    /// Retire l'image : annule un changement en attente, sinon retire l'image actuelle du kit.
    func clear(_ target: TuningTarget) {
        if case .set = changes[target] {
            changes[target] = nil
        } else if current[target] != nil {
            changes[target] = .clear
        }
    }

    /// Image affichée dans l'aperçu (changement en attente, sinon image actuelle).
    func preview(for target: TuningTarget) -> NSImage? {
        switch changes[target] {
        case .set(_, let img, _): return img
        case .clear: return nil
        case nil: return current[target]
        }
    }

    func isProposed(_ target: TuningTarget) -> Bool {
        if case .set(_, _, true) = changes[target] { return true }
        return false
    }

    // MARK: Appliquer / retirer

    var canApply: Bool { kitRoot != nil && !changes.isEmpty && !isApplying && !isLoading }

    var hint: String? {
        if isApplying { return "APPLICATION EN COURS…" }
        if kitRoot == nil { return "CHARGE LE DOSSIER D'UN KIT" }
        if changes.isEmpty { return "AJOUTE OU CHANGE UNE IMAGE" }
        return nil
    }

    var pendingSummary: String {
        let sets = changes.values.filter { if case .set = $0 { return true }; return false }.count
        let clears = changes.count - sets
        var parts: [String] = []
        if sets > 0 { parts.append("\(sets) IMAGE\(sets > 1 ? "S" : "") À APPLIQUER") }
        if clears > 0 { parts.append("\(clears) À RETIRER") }
        return parts.isEmpty ? "RIEN À APPLIQUER" : parts.joined(separator: " · ")
    }

    func applyTapped() {
        guard canApply, let kit = kitRoot else { return }
        let plan = currentPlan()
        foreignToConfirm = KitTuner.foreignNFOs(touchedBy: plan, kitRoot: kit)
        if foreignToConfirm.isEmpty { apply() } else { confirmForeign = true }
    }

    func apply() {
        guard let kit = kitRoot else { return }
        let plan = currentPlan()
        isApplying = true
        Task {
            let r = await Task.detached { KitTuner.apply(plan, kitRoot: kit) }.value
            isApplying = false
            changes = [:]
            report = r
            showReport = true
            rescan()
        }
    }

    func removeTuning() {
        guard let kit = kitRoot else { return }
        isApplying = true
        Task {
            let r = await Task.detached { KitTuner.removeAll(kitRoot: kit) }.value
            isApplying = false
            changes = [:]
            report = r
            showReport = true
            rescan()
        }
    }

    private func currentPlan() -> [TuningTarget: TuningChange] {
        changes.mapValues { c in
            switch c {
            case .set(let png, _, _): return .set(png: png)
            case .clear: return .clear
            }
        }
    }
}

/// Bannières rangées par l'utilisateur dans un dossier (réglages) : « clap.png », « kick.png », « 808.png »…
/// Le nom attendu est celui du dossier de sortie du type. Préparées une seule fois.
@MainActor
enum DropBanners {
    private static var cache: [String: Data] = [:]
    static let extensions = ["png", "jpg", "jpeg"]

    static func banner(for type: SoundType, in folder: String) -> Data? {
        for ext in extensions {
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(type.folderName).\(ext)")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if let d = cache[url.path] { return d }
            guard let d = TuningImage.prepare(url, as: .banner) else { return nil }
            cache[url.path] = d
            return d
        }
        return nil
    }

    /// Types qui ont une bannière dans le dossier (pour les réglages).
    static func available(in folder: String) -> [SoundType] {
        SoundType.allCases.filter { t in
            extensions.contains { FileManager.default.fileExists(atPath: URL(fileURLWithPath: folder).appendingPathComponent("\(t.folderName).\($0)").path) }
        }
    }
}
