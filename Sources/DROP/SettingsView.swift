import SwiftUI
import DKWCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Bibliothèque de drums") {
                HStack {
                    Text(settings.libraryPath.isEmpty ? "Aucune" : (settings.libraryPath as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1).truncationMode(.head)
                    Spacer()
                    Button("Changer…") {
                        if let url = FolderPicker.pick(message: "Choisis le dossier de ta bibliothèque", start: settings.libraryPath) {
                            settings.libraryPath = url.path
                            model.refreshIndexes()
                        }
                    }
                    Button("Réindexer") { model.refreshIndexes() }.disabled(settings.libraryPath.isEmpty)
                }
                if let packs = FLPathVariables.factoryPacksFolders().first {
                    HStack {
                        Text("Sons de FL Studio détectés").foregroundStyle(.secondary)
                        Spacer()
                        Button("Utiliser comme bibliothèque") {
                            settings.libraryPath = packs
                            model.refreshIndexes()
                        }
                        .disabled(settings.libraryPath == packs)
                        Button("Ajouter aux secours") {
                            settings.fallbackPaths.append(packs)
                            model.refreshIndexes()
                        }
                        .disabled(settings.fallbackPaths.contains(packs) || settings.libraryPath == packs)
                    }
                    .help(packs)
                }
                IndexStatusLabel()
            }
            Section("Dossiers de secours (ex. disque externe)") {
                ForEach(settings.fallbackPaths, id: \.self) { path in
                    HStack {
                        Image(systemName: "externaldrive")
                        Text((path as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.head)
                        Spacer()
                        Button { settings.fallbackPaths.removeAll { $0 == path }; model.refreshIndexes() } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain)
                    }
                }
                Button("Ajouter un dossier…") {
                    if let url = FolderPicker.pick(message: "Dossier de secours où chercher les sons") {
                        if !settings.fallbackPaths.contains(url.path) { settings.fallbackPaths.append(url.path) }
                        model.refreshIndexes()
                    }
                }
                Text("Téléchargements (~/Downloads) est toujours inclus automatiquement.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Bannières (TUNING KITS)") {
                HStack {
                    Text(settings.bannersPath.isEmpty ? "Aucun dossier" : (settings.bannersPath as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1).truncationMode(.head)
                    Spacer()
                    Button("Choisir…") {
                        if let url = FolderPicker.pick(message: "Dossier de tes bannières (clap.png, kick.png, 808.png…)", start: settings.bannersPath) {
                            settings.bannersPath = url.path
                        }
                    }
                    if !settings.bannersPath.isEmpty {
                        Button("Retirer") { settings.bannersPath = "" }
                    }
                }
                Text(bannersHelp).font(.caption).foregroundStyle(.secondary)
            }
            Section("Sortie") {
                HStack {
                    Text(settings.outputPath.isEmpty ? "Aucun" : (settings.outputPath as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1).truncationMode(.head)
                    Spacer()
                    Button("Changer…") { model.chooseOutput() }
                }
                TextField("Dernier artiste", text: $settings.lastArtist)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 640)
        .tint(Studio.accent)
    }

    private var bannersHelp: String {
        let names = SoundType.allCases.map { $0.folderName + ".png" }.joined(separator: ", ")
        guard !model.settings.bannersPath.isEmpty else {
            return "Range tes bannières dans un dossier avec ces noms : \(names). DROP les proposera pour les dossiers reconnus (Claps → clap.png)."
        }
        let found = DropBanners.available(in: model.settings.bannersPath)
        return found.isEmpty ? "Aucune bannière trouvée. Noms attendus : \(names)."
                             : "Bannières trouvées : " + found.map(\.badgeLabel).joined(separator: ", ") + "."
    }
}
