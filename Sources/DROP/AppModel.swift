import Foundation
import Observation
import AppKit
import DKWCore
import UniformTypeIdentifiers

enum IndexStatus: Equatable {
    case idle
    case indexing
    case ready(Int)
}

@Observable
final class Project: Identifiable {
    enum State { case analyzing, ready, failed(String) }
    let id = UUID()
    let flpURL: URL
    var title = ""
    var items: [SampleItem] = []
    var state: State = .analyzing
    var truncated = false

    init(flpURL: URL) { self.flpURL = flpURL }

    var defaultTitle: String { flpURL.deletingPathExtension().lastPathComponent }
    var effectiveTitle: String {
        let t = title.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? defaultTitle : t
    }
    var missingCount: Int { items.filter { !$0.isFound }.count }
    var includedCount: Int { items.filter { $0.included && $0.isFound }.count }
}

@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    var projects: [Project] = []
    var artist: String
    var indexStatus: IndexStatus = .idle
    var isExtracting = false
    var reports: [ExtractionReport] = []
    var showSummary = false
    var searchMessage: String?
    /// Incrémenté à chaque nouveau .flp : déclenche l'animation d'absorption du trou noir.
    var absorbToken = 0
    var selectedProjectID: UUID?

    private var resolver = SampleResolver()
    private var extraIndexes: [SearchIndex] = []
    private var indexTask: Task<Void, Never>?

    init() {
        settings = DemoMode.isOn ? AppSettings(defaults: DemoMode.defaults) : AppSettings()
        artist = settings.lastArtist
        if DemoMode.isOn { DemoMode.load(into: self) } else { refreshIndexes() }
    }

    var selectedProject: Project? {
        projects.first { $0.id == selectedProjectID } ?? projects.first
    }

    /// Ce qui manque pour pouvoir lancer START (nil = prêt).
    var startHint: String? {
        if isExtracting { return "COPIE EN COURS…" }
        if projects.isEmpty { return "AJOUTE UN .FLP" }
        if projects.contains(where: { if case .analyzing = $0.state { return true }; return false }) { return "ANALYSE EN COURS…" }
        if outputURL == nil { return "CHOISIS UN DOSSIER DE SORTIE" }
        if !projects.contains(where: { $0.includedCount > 0 }) { return "AUCUN SON SÉLECTIONNÉ" }
        return nil
    }

    // MARK: Index

    /// Charge le cache tout de suite, puis rescanne en arrière-plan.
    func refreshIndexes() {
        let library = settings.libraryPath
        let fallbacks = settings.fallbackPaths
        indexTask?.cancel()
        indexStatus = library.isEmpty && fallbacks.isEmpty ? .idle : .indexing
        indexTask = Task {
            if !library.isEmpty, let cached = IndexCache.load(root: library) {
                resolver.library = cached
            }
            let built = await Task.detached(priority: .userInitiated) { () -> SampleResolver in
                var r = SampleResolver()
                if !library.isEmpty {
                    r.library = IndexCache.refresh(root: URL(fileURLWithPath: library)).index
                }
                let dl = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
                r.downloads = Indexer.scan(root: dl, maxDepth: 4)
                r.fallbacks = fallbacks.map { IndexCache.refresh(root: URL(fileURLWithPath: $0)).index }
                return r
            }.value
            guard !Task.isCancelled else { return }
            resolver = built
            resolver.fallbacks += extraIndexes
            indexStatus = library.isEmpty ? .idle : .ready(built.library?.fileCount ?? 0)
        }
    }

    // MARK: Ouverture de projets

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "flp") ?? .data]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choisis un ou plusieurs projets FL Studio (.flp)"
        panel.prompt = "Ouvrir"
        if panel.runModal() == .OK { add(urls: panel.urls) }
    }

    func add(urls: [URL]) {
        var added = false
        for url in urls where url.pathExtension.lowercased() == "flp" {
            if projects.contains(where: { $0.flpURL == url }) { continue }
            let project = Project(flpURL: url)
            projects.append(project)
            selectedProjectID = project.id
            added = true
            analyze(project)
        }
        if added { absorbToken += 1 }
    }

    private func analyze(_ project: Project) {
        Task {
            await indexTask?.value
            var current = resolver
            let url = project.flpURL
            func run(_ r: SampleResolver) async -> Result<AnalyzedProject, Error> {
                await Task.detached { Result { try ProjectAnalyzer.analyze(flp: url, resolver: r) } }.value
            }
            var result = await run(current)
            // Des sons manquent ? Les dossiers ont peut-être changé : on rescanne une fois.
            if case .success(let a) = result, a.items.contains(where: { !$0.isFound }), !settings.libraryPath.isEmpty {
                let lib = settings.libraryPath
                let fresh = await Task.detached { IndexCache.refresh(root: URL(fileURLWithPath: lib)).index }.value
                current.library = fresh
                resolver.library = fresh
                result = await run(current)
            }
            switch result {
            case .success(let analyzed):
                project.items = analyzed.items
                project.truncated = analyzed.truncated
                project.state = .ready
            case .failure(let error):
                project.state = .failed(error.localizedDescription)
            }
        }
    }

    func remove(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        if selectedProjectID == project.id { selectedProjectID = projects.first?.id }
    }
    func clear() { projects.removeAll(); selectedProjectID = nil }

    // MARK: Édition

    func setType(_ type: SoundType, project: Project, item: SampleItem) {
        guard let i = project.items.firstIndex(where: { $0.id == item.id }) else { return }
        project.items[i].type = type
    }

    func setIncluded(_ on: Bool, project: Project, item: SampleItem) {
        guard let i = project.items.firstIndex(where: { $0.id == item.id }) else { return }
        project.items[i].included = on && project.items[i].isFound
    }

    func setAll(_ on: Bool, project: Project) {
        for i in project.items.indices { project.items[i].included = on && project.items[i].isFound }
    }

    // MARK: Recherche manuelle

    var totalMissing: Int { projects.reduce(0) { $0 + $1.missingCount } }

    func searchInFolder() {
        let box = NSButton(checkboxWithTitle: "Ajouter aux dossiers de secours", target: nil, action: nil)
        box.state = .on
        guard let folder = FolderPicker.pick(message: "Choisis un dossier (ou un disque externe) où chercher les sons manquants",
                                             accessory: box) else { return }
        let addToFallbacks = box.state == .on
        searchMessage = "Recherche dans « \(folder.lastPathComponent) »…"
        Task {
            let index = await Task.detached { Indexer.scan(root: folder) }.value
            if addToFallbacks {
                if !settings.fallbackPaths.contains(folder.path) { settings.fallbackPaths.append(folder.path) }
                IndexCache.save(index)
            }
            extraIndexes.append(index)
            resolver.fallbacks.append(index)
            let r = resolver
            var found = 0
            for p in projects {
                let before = p.missingCount
                let updated = await Task.detached { [items = p.items] in ProjectAnalyzer.reresolve(items, resolver: r) }.value
                p.items = updated
                found += before - p.missingCount
            }
            searchMessage = found > 0 ? "\(found) son(s) retrouvé(s) ✨" : "Aucun son retrouvé dans ce dossier."
            try? await Task.sleep(for: .seconds(4))
            searchMessage = nil
        }
    }

    // MARK: Extraction

    var outputURL: URL? { settings.outputPath.isEmpty ? nil : URL(fileURLWithPath: settings.outputPath) }

    var canExtract: Bool { startHint == nil }

    func chooseOutput() {
        if let url = FolderPicker.pick(message: "Choisis le dossier de sortie", start: settings.outputPath) {
            settings.outputPath = url.path
        }
    }

    func extract() {
        guard canExtract, let out = outputURL else { return }
        settings.lastArtist = artist
        isExtracting = true
        let jobs = projects.filter { $0.includedCount > 0 }.map {
            ExtractionJob(flpName: $0.defaultTitle, artist: artist, title: $0.effectiveTitle, outputRoot: out, items: $0.items)
        }
        Task {
            var results: [ExtractionReport] = []
            for job in jobs {
                if let r = await Task.detached(operation: { try? Extractor.run(job) }).value { results.append(r) }
            }
            reports = results
            isExtracting = false
            showSummary = true
        }
    }
}
