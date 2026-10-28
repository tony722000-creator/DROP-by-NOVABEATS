import SwiftUI
import DKWCore

/// Panneau droit : « SAMPLES DÉTECTÉS », onglets par .flp, liste qui défile.
struct SamplesPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Text("SAMPLES DÉTECTÉS").silkscreen(size: 12)
                Rectangle().fill(.white.opacity(0.55)).frame(height: 1)
            }
            .padding(.top, 4)

            if model.projects.count > 1 { ProjectTabs() }

            if let project = model.selectedProject {
                ProjectSamples(project: project)
            } else {
                EmptySlots()
            }
        }
    }
}

private struct ProjectTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.projects) { p in
                    let selected = p.id == model.selectedProject?.id
                    HStack(spacing: 6) {
                        Button {
                            model.selectedProjectID = p.id
                        } label: {
                            Text(p.effectiveTitle.uppercased())
                                .lineLimit(1).frame(maxWidth: 150)
                        }
                        .buttonStyle(.plain)
                        Button { model.remove(p) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .heavy)) }
                            .buttonStyle(.plain)
                            .help("Retirer ce projet")
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1)
                    .foregroundStyle(Studio.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(CreamSurface(radius: 6, pressed: selected, dimmed: !selected))
                    .offset(y: selected ? 1 : 0)
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 1)
        }
    }
}

private struct ProjectSamples: View {
    @Environment(AppModel.self) private var model
    let project: Project

    var body: some View {
        switch project.state {
        case .analyzing:
            message(icon: nil, "ANALYSE DE \(project.flpURL.lastPathComponent.uppercased())…", spinner: true)
        case .failed(let error):
            message(icon: "exclamationmark.triangle.fill", error, spinner: false)
        case .ready:
            if project.items.isEmpty {
                message(icon: "waveform.slash", "AUCUN FICHIER AUDIO EXTERNE DANS CE PROJET.", spinner: false)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if project.truncated {
                            Label("Fichier abîmé : lecture partielle", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        ForEach(project.items) { item in
                            SampleRow(project: project, item: item)
                        }
                    }
                    .padding(.trailing, 4)
                    .padding(.bottom, 18)
                }
                .scrollIndicators(.automatic)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9),
                                             .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            }
        }
    }

    private func message(icon: String?, _ text: String, spinner: Bool) -> some View {
        HStack(spacing: 10) {
            if spinner { ProgressView().controlSize(.small) }
            if let icon { Image(systemName: icon).foregroundStyle(.orange) }
            Text(text).silkscreen(size: 10).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .recessed(radius: 10, darkness: 0.3)
    }
}

private struct SampleRow: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let item: SampleItem
    @State private var choosingType = false

    var body: some View {
        HStack(spacing: 16) {
            CreamCheckbox(isOn: item.included, enabled: item.isFound) {
                model.setIncluded(!item.included, project: project, item: item)
            }
            Text(item.fileName)
                .font(.system(size: 15, weight: .regular, design: .monospaced)).tracking(1)
                .foregroundStyle(.white.opacity(item.isFound ? 0.95 : 0.45))
                .lineLimit(1).truncationMode(.middle)
                .help(item.isFound ? "\(item.resolved?.path ?? "")\nTrouvé via : \(item.source.label)"
                                   : "Introuvable : \(item.originalPath)")
            Spacer(minLength: 8)
            if item.isFound {
                Button { choosingType = true } label: { PedalBadge(type: item.type) }
                    .buttonStyle(.plain)
                    .help("Changer le type")
                    .popover(isPresented: $choosingType, arrowEdge: .leading) {
                        TypePicker(current: item.type) { t in
                            model.setType(t, project: project, item: item)
                            choosingType = false
                        }
                    }
            } else {
                PedalBadge(label: "NON TROUVÉ", color: Studio.color(0x4B4558))
                    .help("Ce fichier n'est pas sur ce Mac (ou son dossier est verrouillé). Bouton CHERCHER… pour le retrouver.")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .recessed(radius: 10, darkness: 0.3)
        .opacity(item.included || !item.isFound ? 1 : 0.6)
        .animation(.easeOut(duration: 0.15), value: item.included)
    }
}

private struct TypePicker: View {
    let current: SoundType
    let pick: (SoundType) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 8), count: 3), spacing: 8) {
            ForEach(SoundType.allCases) { t in
                Button { pick(t) } label: {
                    PedalBadge(type: t, minWidth: 96)
                        .overlay(Capsule().strokeBorder(.white, lineWidth: t == current ? 2 : 0))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }
}

/// Emplacements vides avant le premier .flp.
private struct EmptySlots: View {
    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { i in
                HStack(spacing: 16) {
                    CreamSurface(radius: 5, dimmed: true).frame(width: 22, height: 22)
                    if i == 0 {
                        Text("LES SAMPLES APPARAÎTRONT ICI").silkscreen(size: 10, opacity: 0.5)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .recessed(radius: 10, darkness: 0.22)
                .opacity(1 - Double(i) * 0.15)
            }
            Spacer(minLength: 0)
        }
    }
}
