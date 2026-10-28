import Foundation

public enum SoundType: String, CaseIterable, Sendable, Codable, Identifiable {
    case drum808 = "808"
    case kick, snare, clap, hihat, openhat, perc, rim, crash, fx, vox, loop
    case autres

    public var id: String { rawValue }

    /// Nom utilisé pour les dossiers et fichiers copiés.
    public var folderName: String { rawValue }

    /// Nom affiché dans l'interface.
    public var displayName: String {
        switch self {
        case .drum808: return "808"
        case .kick: return "Kick"
        case .snare: return "Snare"
        case .clap: return "Clap"
        case .hihat: return "Hi-hat"
        case .openhat: return "Open hat"
        case .perc: return "Perc"
        case .rim: return "Rim"
        case .crash: return "Crash"
        case .fx: return "FX"
        case .vox: return "Vox"
        case .loop: return "Loop"
        case .autres: return "Autres"
        }
    }
}
