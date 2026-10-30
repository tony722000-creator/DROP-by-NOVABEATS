import SwiftUI
import AppKit
import DKWCore

extension SoundType {
    /// Couleurs des badges (Branding/BRANDING.md).
    var color: Color {
        switch self {
        case .drum808: return Studio.color(0x9333EA)
        case .kick: return Studio.color(0x2563EB)
        case .snare: return Studio.color(0xE11D48)
        case .clap: return Studio.color(0xEAB308)
        case .hihat: return Studio.color(0x0D9488)
        case .openhat: return Studio.color(0x06B6D4)
        case .perc: return Studio.color(0xF97316)
        case .rim: return Studio.color(0x84CC16)
        case .crash: return Studio.color(0xF59E0B)
        case .fx: return Studio.color(0xEC4899)
        case .vox: return Studio.color(0x14B8A6)
        case .loop: return Studio.color(0x6366F1)
        case .autres: return Studio.color(0x6B7280)
        }
    }

    /// Texte du badge, en majuscules comme une sérigraphie.
    var badgeLabel: String {
        switch self {
        case .openhat: return "OPEN HAT"
        case .hihat: return "HIHAT"
        default: return displayName.uppercased()
        }
    }
}

/// Palette « violet espace » + matières de la pédale.
enum Studio {
    static func ns(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    static func color(_ v: UInt32) -> Color { Color(nsColor: ns(v)) }

    static let space = color(0x08050F)
    static let accent = color(0x8B5CF6)      // violet électrique
    static let deep = color(0x5B21B6)        // violet profond
    static let glow = color(0xC026D3)        // magenta lueur
    static let lavender = color(0xC4B5FD)
    static let ledOn = color(0xA78BFA)

    static let cream = color(0xF2EEE8)
    static let creamShade = color(0xDCD5CB)
    static let ink = color(0x1E0B3A)
    static let paint = color(0x3A1C78)       // teinte du boîtier sous la texture

    static var gradient: LinearGradient {
        LinearGradient(colors: [glow, deep], startPoint: .top, endPoint: .bottom)
    }
}

/// Logo « DROP by TONY CARLOS » (copié dans DROP.app/Contents/Resources par build.sh).
enum Brand {
    static let logo: NSImage? = {
        if let url = Bundle.main.url(forResource: "drop-logo", withExtension: "png") { return NSImage(contentsOf: url) }
        return NSImage(contentsOfFile: "Branding/drop-logo.png") // lancement depuis le dossier du projet
    }()
}

struct LogoView: View {
    var width: CGFloat = 360
    /// Version « néon » de la maquette : logo rempli de lavande claire avec une lueur violette.
    var neon = false
    /// Lueur violette autour du logo (en-tête de la page principale).
    var glow = false

    var body: some View {
        Group {
            if let img = Brand.logo {
                if neon {
                    LinearGradient(colors: [.white, Studio.color(0xE9D5FF), Studio.lavender], startPoint: .top, endPoint: .bottom)
                        .mask(Image(nsImage: img).resizable().scaledToFit())
                        .frame(width: width, height: width * img.size.height / max(img.size.width, 1))
                        .shadow(color: Studio.accent, radius: 6)
                        .shadow(color: Studio.glow.opacity(0.6), radius: 16)
                } else {
                    Image(nsImage: img).resizable().scaledToFit().frame(width: width)
                        .shadow(color: Studio.space.opacity(glow ? 0.35 : 0.55), radius: 10) // ressort mieux sur la texture violette
                        .shadow(color: glow ? Studio.accent.opacity(0.75) : .clear, radius: 7)
                        .shadow(color: glow ? Studio.glow.opacity(0.45) : .clear, radius: 18)
                }
            } else {
                Text("DROP").font(.system(size: width / 5, weight: .black, design: .rounded))
                    .foregroundStyle(Studio.gradient)
            }
        }
        .accessibilityLabel("DROP by TONY CARLOS")
    }
}

/// Dialogue de choix de dossier.
@MainActor
enum FolderPicker {
    static func pick(message: String, start: String? = nil, accessory: NSView? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true // pour entrer dans « FL Studio.app »
        panel.message = message
        panel.prompt = "Choisir"
        if let start, !start.isEmpty { panel.directoryURL = URL(fileURLWithPath: start) }
        if let accessory { panel.accessoryView = accessory; panel.isAccessoryViewDisclosed = true }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
