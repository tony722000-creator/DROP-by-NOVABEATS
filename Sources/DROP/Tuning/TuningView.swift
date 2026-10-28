import SwiftUI
import AppKit
import DKWCore

/// Onglet TUNING KITS : même boîtier, panneau du kit + cover à gauche, éléments du kit à droite.
struct TuningLayout: View {
    @Environment(TuningModel.self) private var tuning
    let dropTargeted: Bool

    var body: some View {
        @Bindable var tuning = tuning
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 26) {
                KitPanel(targeted: dropTargeted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                KitItemsPanel()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, 18)
            TuningControlRow()
                .padding(.top, 22)
        }
        .alert("Des fichiers .nfo existent déjà", isPresented: $tuning.confirmForeign) {
            Button("Mettre à jour") { tuning.apply() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(foreignMessage)
        }
        .alert("Retirer le tuning de DROP ?", isPresented: $tuning.confirmRemove) {
            Button("Retirer", role: .destructive) { tuning.removeTuning() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les .nfo et images ajoutés par DROP seront supprimés et les .nfo d'origine remis comme avant. Les samples ne sont pas touchés.")
        }
        .sheet(isPresented: $tuning.showReport) {
            TuningSummarySheet().environment(tuning)
        }
    }

    private var foreignMessage: String {
        let names = tuning.foreignToConfirm.map(\.lastPathComponent)
        let list = names.prefix(6).joined(separator: ", ") + (names.count > 6 ? "…" : "")
        return "\(list)\n\nSeules les lignes Bitmap, Tip et Color seront remplacées ; le reste est gardé. « Retirer le tuning » les remettra comme avant."
    }
}

// MARK: Panneau gauche : la cover du kit, à la place du trou noir

private struct KitPanel: View {
    @Environment(TuningModel.self) private var tuning
    let targeted: Bool

    var body: some View {
        ZStack {
            if let kit = tuning.kitRoot {
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        // carré le plus grand possible, centré
                        let side = max(80, min(geo.size.width - 40, geo.size.height - 28))
                        ImageWell(target: .cover, size: CGSize(width: side, height: side), radius: 14)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2 + 6)
                    }
                    HStack(spacing: 12) {
                        Text("COVER · " + kit.lastPathComponent.uppercased())
                            .silkscreen(size: 10).lineLimit(1).truncationMode(.middle)
                            .help(kit.path)
                        if tuning.hasDropTuning {
                            Button("RETIRER LE TUNING") { tuning.confirmRemove = true }
                                .buttonStyle(CreamButtonStyle(height: 26))
                                .help("Supprime uniquement ce que DROP a ajouté à ce kit")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .frame(minHeight: 40)
                }
                .overlay(alignment: .topTrailing) {
                    Button { tuning.close() } label: { Image(systemName: "xmark") }
                        .buttonStyle(CreamIconButtonStyle(size: 22))
                        .help("Fermer ce kit")
                        .padding(12)
                }
            } else {
                Button { tuning.chooseKit() } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Studio.cream.opacity(targeted ? 0.95 : 0.6), style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                            .padding(14)
                        VStack(spacing: 18) {
                            Image(systemName: "folder")
                                .font(.system(size: 56, weight: .light)).foregroundStyle(.white)
                                .shadow(color: .white.opacity(0.5), radius: 6)
                                .scaleEffect(targeted ? 1.08 : 1)
                            Text("Glisse le dossier d'un kit ici")
                                .font(.system(size: 20, weight: .semibold)).tracking(2.5).foregroundStyle(.white)
                            Text("OU CLIQUE POUR CHOISIR").silkscreen(size: 9.5, opacity: 0.55)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .recessed(radius: 16)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Studio.accent, lineWidth: 2)
                .opacity(targeted ? 1 : 0)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.2), value: targeted)
    }
}

// MARK: Panneau droit : éléments du kit

private struct KitItemsPanel: View {
    @Environment(TuningModel.self) private var tuning

    var body: some View {
        @Bindable var tuning = tuning
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Text("ÉLÉMENTS DU KIT").silkscreen(size: 12)
                Rectangle().fill(.white.opacity(0.55)).frame(height: 1)
                HStack(spacing: 8) {
                    CreamCheckbox(isOn: tuning.includeFiles, enabled: tuning.kitRoot != nil) { tuning.includeFiles.toggle() }
                    Text("FICHIERS").silkscreen(size: 10, opacity: tuning.kitRoot != nil ? 0.9 : 0.4)
                }
                .help("Afficher aussi les sons, pour leur mettre une image un par un")
            }
            .padding(.top, 4)

            if tuning.kitRoot == nil {
                placeholder("LES DOSSIERS DU KIT APPARAÎTRONT ICI")
            } else if tuning.isLoading && tuning.items.isEmpty {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("LECTURE DU KIT…").silkscreen(size: 10) }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).recessed(radius: 10, darkness: 0.3)
            } else if tuning.items.isEmpty {
                placeholder("CE DOSSIER NE CONTIENT AUCUN SOUS-DOSSIER")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(tuning.items) { item in KitItemRow(item: item) }
                    }
                    .padding(.trailing, 4).padding(.bottom, 18)
                }
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9),
                                             .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack(spacing: 8) {
            HStack { Text(text).silkscreen(size: 10, opacity: 0.5); Spacer() }
                .padding(.horizontal, 14).frame(height: 46).recessed(radius: 10, darkness: 0.22)
            Spacer(minLength: 0)
        }
    }
}

private struct KitItemRow: View {
    @Environment(TuningModel.self) private var tuning
    let item: KitItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isDirectory ? "folder.fill" : "waveform")
                .font(.system(size: 13)).foregroundStyle(Studio.lavender)
                .frame(width: 18)
            Text(item.name)
                .font(.system(size: 14, design: .monospaced)).tracking(0.8)
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1).truncationMode(.middle)
            if let t = item.detectedType, item.isDirectory {
                Text(t.badgeLabel).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1)
                    .foregroundStyle(.white).padding(.horizontal, 7).frame(height: 17)
                    .background(Capsule().fill(t.color))
            }
            Spacer(minLength: 8)
            ImageWell(target: item.target, size: CGSize(width: 150, height: 25), radius: 4)
        }
        .padding(.leading, 12 + CGFloat(item.depth) * 18)
        .padding(.trailing, 12)
        .frame(height: 44)
        .recessed(radius: 10, darkness: 0.3)
    }
}

/// Emplacement d'image : aperçu, glisser-déposer, clic pour choisir, × pour retirer.
private struct ImageWell: View {
    @Environment(TuningModel.self) private var tuning
    let target: TuningTarget
    let size: CGSize
    let radius: CGFloat
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let preview = tuning.preview(for: target)
        Button { tuning.chooseImage(for: target) } label: {
            ZStack {
                shape.fill(.black.opacity(0.35))
                if let preview {
                    Image(nsImage: preview).resizable().interpolation(.high)
                        .aspectRatio(contentMode: target == .cover ? .fill : .fit)
                        .frame(width: size.width, height: size.height)
                        .clipShape(shape)
                } else {
                    shape.strokeBorder(Studio.cream.opacity(hovering ? 0.9 : 0.45), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    if target == .cover {
                        VStack(spacing: 10) {
                            Image(systemName: "photo").font(.system(size: 34, weight: .light))
                            Text("GLISSE LA COVER DU KIT").font(.system(size: 11, weight: .semibold)).tracking(2)
                            Text("OU CLIQUE · CARRÉE DE PRÉFÉRENCE").font(.system(size: 8.5, weight: .semibold)).tracking(1.5).opacity(0.7)
                        }
                        .foregroundStyle(.white.opacity(0.7))
                    } else {
                        Label("IMAGE", systemImage: "plus")
                            .font(.system(size: 9, weight: .semibold)).tracking(1)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .overlay(shape.strokeBorder(Studio.accent, lineWidth: hovering ? 2 : 0))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(target == .cover ? "Cover du kit (256×256) : glisse une image ou clique" : "Bannière (300 px de large) : glisse une image ou clique")
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { TuningModel.imageTypes.contains($0.pathExtension.lowercased()) }) else { return false }
            tuning.setImage(url, for: target)
            return true
        } isTargeted: { hovering = $0 }
        .overlay(alignment: .topTrailing) {
            if preview != nil {
                Button { tuning.clear(target) } label: { Image(systemName: "xmark") }
                    .buttonStyle(CreamIconButtonStyle(size: 16))
                    .help("Retirer cette image")
                    .offset(x: 7, y: -7)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if tuning.isProposed(target) {
                Text("AUTO").font(.system(size: 7, weight: .heavy, design: .monospaced)).tracking(1)
                    .foregroundStyle(Studio.ink).padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(Studio.cream)).offset(x: -6, y: 6)
                    .help("Proposée automatiquement depuis ton dossier de bannières (réglages)")
            }
        }
    }
}

// MARK: Rangée du bas

private struct TuningControlRow: View {
    @Environment(TuningModel.self) private var tuning

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("TUNING").silkscreen()
                Text(tuning.kitRoot == nil ? "CHARGE UN KIT, AJOUTE DES IMAGES, PUIS START." : tuning.pendingSummary)
                    .font(.system(size: 14, weight: .medium, design: .monospaced)).tracking(1)
                    .foregroundStyle(Studio.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .background(CreamSurface())
                Text(tuning.hint ?? "LE BROWSER DE FL AFFICHERA LES IMAGES (.NFO + .IMAGES)")
                    .silkscreen(size: 9, opacity: 0.6)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            EngravedSeparator()
            HStack(alignment: .top, spacing: 6) {
                PedalLED(on: tuning.canApply, blinking: tuning.isApplying)
                Button { tuning.applyTapped() } label: { EmptyView() }
                    .buttonStyle(StartButtonStyle())
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(!tuning.canApply)
                    .help(tuning.hint.map { $0.capitalized } ?? "Appliquer le tuning (Entrée)")
            }
        }
    }
}

// MARK: Résumé

struct TuningSummarySheet: View {
    @Environment(TuningModel.self) private var tuning
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let r = tuning.report
        ZStack {
            PedalBackground()
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    PedalLED(on: (r?.errors.isEmpty ?? false), blinking: false)
                    Text(r?.removedAll == true ? "TUNING RETIRÉ" : "TUNING APPLIQUÉ")
                        .font(.system(size: 24, weight: .heavy)).tracking(3).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 8) {
                    if let r {
                        if r.created > 0 { line("\(r.created) .NFO CRÉÉ\(r.created > 1 ? "S" : "")", "plus.circle") }
                        if r.updated > 0 { line("\(r.updated) .NFO MIS À JOUR", "arrow.triangle.2.circlepath") }
                        if r.cleared > 0 { line("\(r.cleared) IMAGE\(r.cleared > 1 ? "S" : "") RETIRÉE\(r.cleared > 1 ? "S" : "")", "minus.circle") }
                        if r.created + r.updated + r.cleared == 0 && r.errors.isEmpty { line("RIEN À CHANGER", "checkmark.circle") }
                        ForEach(Array(r.errors.enumerated()), id: \.offset) { _, e in
                            Label("Échec : \(e.name) (\(e.reason))", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        Text("Les samples n'ont pas été touchés. Dans FL Studio, rafraîchis le Browser pour voir les images.")
                            .font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .recessed(radius: 12, darkness: 0.3)

                HStack(spacing: 12) {
                    Button("FERMER") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button {
                        if let kit = r?.kitRoot { NSWorkspace.shared.activateFileViewerSelecting([kit]) }
                    } label: {
                        Label("OUVRIR LE KIT DANS LE FINDER", systemImage: "folder")
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .buttonStyle(CreamButtonStyle(height: 34))
            }
            .padding(30)
        }
        .frame(width: 520)
        .environment(\.colorScheme, .dark)
    }

    private func line(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon).silkscreen(size: 11)
    }
}

// MARK: Sélecteur d'onglet (en-tête)

struct TabSelector: View {
    @Binding var tab: MainTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MainTab.allCases, id: \.self) { t in
                let selected = t == tab
                Button { tab = t } label: {
                    Text(t.title)
                        .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1.4)
                        .foregroundStyle(Studio.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(CreamSurface(radius: 6, pressed: selected, dimmed: !selected))
                        .offset(y: selected ? 1 : 0)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .recessed(radius: 10, darkness: 0.3)
    }
}
