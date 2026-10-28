import SwiftUI
import DKWCore

/// Fenêtre principale : le boîtier de la pédale.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var model = model
        ZStack {
            PedalBackground()
            if model.settings.needsSetup {
                SetupView().transition(.opacity)
            } else {
                PedalLayout(dropTargeted: dropTargeted).transition(.opacity)
            }
            WindowScrews()
        }
        .environment(\.colorScheme, .dark) // objet physique : même rendu en mode clair et sombre
        .tint(Studio.accent)
        .animation(.smooth(duration: 0.35), value: model.settings.needsSetup)
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls: urls); return true
        } isTargeted: { dropTargeted = $0 }
        .sheet(isPresented: $model.showSummary) {
            SummarySheet().environment(model)
        }
    }
}

/// 4 vis dans les coins du boîtier (celle du haut à gauche passe sous les feux de la fenêtre).
private struct WindowScrews: View {
    var body: some View {
        ZStack {
            Screw(angle: 18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.leading, 20).padding(.top, 46)
            Screw(angle: 74).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(.trailing, 20).padding(.top, 18)
            Screw(angle: 131).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(.leading, 20).padding(.bottom, 20)
            Screw(angle: 202).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(.trailing, 20).padding(.bottom, 20)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct PedalLayout: View {
    let dropTargeted: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                LogoView(width: 200, neon: true)
                Spacer()
                SettingsLink { Image(systemName: "gearshape.fill") }
                    .buttonStyle(CreamIconButtonStyle())
                    .help("Réglages (⌘,)")
                    .padding(.trailing, 28)
            }
            .padding(.top, 34)

            HStack(alignment: .top, spacing: 26) {
                SourcePanel(dropTargeted: dropTargeted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                SamplesPanel()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, 18)

            ControlRow()
                .padding(.top, 22)
        }
        .padding(.horizontal, 48)
        .padding(.bottom, 30)
    }
}

// MARK: Panneau gauche : zone de dépôt puis trou noir

private struct SourcePanel: View {
    @Environment(AppModel.self) private var model
    let dropTargeted: Bool

    var body: some View {
        ZStack {
            if model.projects.isEmpty {
                EmptyDropZone(targeted: dropTargeted)
                    .transition(.opacity)
            } else {
                BlackHoleStage(targeted: dropTargeted)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .recessed(radius: 16)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Studio.accent, lineWidth: 2)
                .shadow(color: Studio.accent, radius: 10)
                .opacity(dropTargeted ? 1 : 0)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.2), value: dropTargeted)
        .animation(.smooth(duration: 0.5), value: model.projects.isEmpty)
    }
}

private struct EmptyDropZone: View {
    @Environment(AppModel.self) private var model
    let targeted: Bool

    var body: some View {
        Button { model.openPanel() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Studio.cream.opacity(targeted ? 0.95 : 0.6), style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                    .padding(14)
                VStack(spacing: 18) {
                    Image(systemName: "doc")
                        .font(.system(size: 58, weight: .light))
                        .foregroundStyle(.white)
                        .shadow(color: .white.opacity(0.5), radius: 6)
                        .scaleEffect(targeted ? 1.08 : 1)
                    Text("Glisse ton .flp ici")
                        .font(.system(size: 21, weight: .semibold)).tracking(3)
                        .foregroundStyle(.white)
                    Text("OU CLIQUE POUR CHOISIR · ⌘O").silkscreen(size: 9.5, opacity: 0.55)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: targeted)
    }
}

private struct BlackHoleStage: View {
    @Environment(AppModel.self) private var model
    let targeted: Bool

    private var analyzing: Bool { model.projects.contains { if case .analyzing = $0.state { return true }; return false } }
    private var total: Int { model.projects.reduce(0) { $0 + $1.items.count } }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height * 1.55)
                BlackHoleView(absorbToken: model.absorbToken)
                    .frame(width: side, height: side)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2 + side * 0.03)
            }
            .clipped()

            HStack(spacing: 12) {
                if analyzing {
                    ProgressView().controlSize(.small)
                    Text("ANALYSE EN COURS…").silkscreen(size: 10)
                } else {
                    Text(summary).silkscreen(size: 10)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                if model.totalMissing > 0 && !analyzing {
                    Button("CHERCHER…") { model.searchInFolder() }
                        .buttonStyle(CreamButtonStyle(height: 26))
                        .help("Choisir un dossier ou un disque externe où chercher les sons introuvables")
                }
            }
            .padding(.bottom, 14)
            .frame(minHeight: 40)
        }
        .overlay(alignment: .topTrailing) {
            Button { model.clear() } label: { Image(systemName: "xmark") }
                .buttonStyle(CreamIconButtonStyle(size: 22))
                .help("Retirer tous les projets (⇧⌘W)")
                .padding(12)
        }
    }

    private var summary: String {
        if let msg = model.searchMessage { return msg.uppercased() }
        let missing = model.totalMissing
        var s = "\(total) SON\(total > 1 ? "S" : "")"
        if model.projects.count > 1 { s = "\(model.projects.count) PROJETS · " + s }
        if missing > 0 { s += " · \(missing) INTROUVABLE\(missing > 1 ? "S" : "")" }
        return s
    }
}

// MARK: Rangée du bas : artiste, titre, sortie, LED, START

private struct ControlRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .bottom, spacing: 22) {
                    LabeledControl(label: "ARTISTE") {
                        CreamTextField(placeholder: "NOM D'ARTISTE", text: $model.artist) { model.extract() }
                    }
                    EngravedSeparator()
                    LabeledControl(label: "TITRE") { TitleField() }
                    EngravedSeparator()
                    LabeledControl(label: "DOSSIER DE SORTIE") { OutputPicker() }
                }
                Text(model.startHint ?? " ")
                    .silkscreen(size: 9, opacity: 0.6)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            EngravedSeparator()
            HStack(alignment: .top, spacing: 6) {
                PedalLED(on: model.canExtract, blinking: model.isExtracting)
                Button { model.extract() } label: { EmptyView() }
                    .buttonStyle(StartButtonStyle())
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(!model.canExtract)
                    .help(model.startHint.map { $0.capitalized } ?? "Extraire les samples (Entrée)")
            }
        }
    }
}

private struct TitleField: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let project = model.selectedProject {
            @Bindable var project = project
            CreamTextField(placeholder: project.defaultTitle.uppercased(), text: $project.title) { model.extract() }
        } else {
            CreamTextField(placeholder: "TITRE DE LA PROD", text: .constant("")).disabled(true).opacity(0.7)
        }
    }
}

private struct OutputPicker: View {
    @Environment(AppModel.self) private var model

    private var shortPath: String {
        let path = model.settings.outputPath
        guard !path.isEmpty else { return "CHOISIR…" }
        let parts = (path as NSString).abbreviatingWithTildeInPath.split(separator: "/")
        return parts.suffix(2).joined(separator: "/")
    }

    var body: some View {
        Button { model.chooseOutput() } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder").font(.system(size: 15, weight: .medium))
                Text(shortPath)
                    .font(.system(size: 14, weight: .medium, design: .monospaced)).tracking(0.6)
                    .lineLimit(1).truncationMode(.head)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Studio.ink)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(CreamSurface())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.settings.outputPath.isEmpty ? "Choisir le dossier de sortie" : model.settings.outputPath)
    }
}

// MARK: Premier lancement

struct SetupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 22) {
            LogoView(width: 340, neon: true)
            Text("OÙ SE TROUVE TA BIBLIOTHÈQUE DE DRUMS ?").silkscreen(size: 13)
            Text("DROP s'en souviendra (modifiable dans les réglages).")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            Button("CHOISIR MA BIBLIOTHÈQUE…") {
                if let url = FolderPicker.pick(message: "Choisis le dossier de ta bibliothèque de drums") {
                    model.settings.libraryPath = url.path
                    model.refreshIndexes()
                }
            }
            .buttonStyle(CreamButtonStyle(height: 38))
            Button("Passer pour l'instant") { model.settings.skippedSetup = true }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(48)
        .recessed(radius: 20)
        .padding(60)
    }
}

/// État de l'index (affiché dans les réglages).
struct IndexStatusLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.indexStatus {
            case .idle:
                if model.settings.libraryPath.isEmpty {
                    Label("Aucune bibliothèque configurée", systemImage: "exclamationmark.triangle")
                } else { EmptyView() }
            case .indexing:
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Indexation de la bibliothèque…") }
            case .ready(let n):
                Label("Bibliothèque prête : \(n.formatted()) sons indexés", systemImage: "checkmark.circle")
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}
