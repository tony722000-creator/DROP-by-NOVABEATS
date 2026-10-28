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
        .frame(width: 560, height: 480)
        .tint(Studio.accent)
    }
}
