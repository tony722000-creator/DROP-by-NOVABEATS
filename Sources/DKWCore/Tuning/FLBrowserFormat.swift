import Foundation

// ─────────────────────────────────────────────────────────────────────────────
//  FORMAT DES .nfo DU BROWSER DE FL STUDIO — le seul fichier à modifier si FL
//  n'affiche pas les images comme prévu (pas de documentation officielle).
//
//  Pour un dossier « Claps » : fichier « Claps.nfo » à côté de lui, fins de ligne CRLF :
//      Tip=Claps
//      Bitmap=.images/clap.png
//      Color=$F65C8B
//  • Bitmap : chemin de l'image, relatif au dossier qui contient le .nfo.
//  • Images copiées dans « .images » à la racine du kit (comme les kits du commerce).
//  • Color : « $ » + BBGGRR (bleu, vert, rouge).
//  • Cover : « Nom du kit.nfo » à côté du dossier du kit, Bitmap=Nom du kit/.images/cover.png
//  Référence : Branding/tuning-kits-test/
// ─────────────────────────────────────────────────────────────────────────────

/// Ce qu'on habille dans le Browser : le kit entier (cover), un dossier ou un fichier.
public enum TuningTarget: Hashable, Sendable {
    case cover
    case item(relativePath: String, isDirectory: Bool)
}

public enum FLBrowserFormat {
    // MARK: Réglages du format

    public static let imagesFolderName = ".images"
    public static let nfoExtension = "nfo"
    public static let lineEnding = "\r\n"
    public static let tipKey = "Tip"
    public static let bitmapKey = "Bitmap"
    public static let colorKey = "Color"

    /// Couleur des dossiers dans le Browser (violet DROP #8B5CF6).
    public static let folderColorRGB: UInt32 = 0x8B5CF6

    /// Taille des images copiées dans le kit (en pixels).
    public static let bannerWidth = 300
    public static let bannerMaxHeight = 50   // ratio 6:1 ; plus haut → recadré au centre
    public static let coverSize = 256        // carré ; pas carré → recadré au centre

    /// « Clap 1.wav » → « Clap 1.nfo » (false) ou « Clap 1.wav.nfo » (true).
    public static let fileNFOKeepsExtension = false

    /// Fichier où DROP note ce qu'il a ajouté (pour « Retirer le tuning »).
    public static let manifestName = ".drop-tuning.json"

    // MARK: Emplacements

    public static func imagesFolder(kitRoot: URL) -> URL {
        kitRoot.appendingPathComponent(imagesFolderName, isDirectory: true)
    }

    /// Emplacement du .nfo pour une cible.
    public static func nfoURL(for target: TuningTarget, kitRoot: URL) -> URL {
        switch target {
        case .cover:
            return kitRoot.deletingLastPathComponent()
                .appendingPathComponent(kitRoot.lastPathComponent + "." + nfoExtension)
        case .item(let rel, let isDirectory):
            let item = kitRoot.appendingPathComponent(rel)
            let base = isDirectory || fileNFOKeepsExtension
                ? item.lastPathComponent
                : item.deletingPathExtension().lastPathComponent
            return item.deletingLastPathComponent().appendingPathComponent(base + "." + nfoExtension)
        }
    }

    /// Valeur de la clé Bitmap : chemin de l'image relatif au dossier du .nfo, avec « / ».
    public static func bitmapValue(image: URL, nfo: URL) -> String {
        let from = nfo.deletingLastPathComponent().pathComponents
        let to = image.pathComponents
        var common = 0
        while common < from.count, common < to.count, from[common] == to[common] { common += 1 }
        let up = Array(repeating: "..", count: from.count - common)
        return (up + to[common...]).joined(separator: "/")
    }

    /// Valeur de la clé Tip (bulle d'aide) : nom du kit, du dossier ou du fichier sans extension.
    public static func tipValue(for target: TuningTarget, kitRoot: URL) -> String {
        switch target {
        case .cover: return kitRoot.lastPathComponent
        case .item(let rel, let isDirectory):
            let u = kitRoot.appendingPathComponent(rel)
            return isDirectory ? u.lastPathComponent : u.deletingPathExtension().lastPathComponent
        }
    }

    /// « $ » + BBGGRR. #8B5CF6 → $F65C8B.
    public static func colorValue(rgb: UInt32 = folderColorRGB) -> String {
        let r = (rgb >> 16) & 0xFF, g = (rgb >> 8) & 0xFF, b = rgb & 0xFF
        return "$" + String(format: "%02X%02X%02X", b, g, r)
    }

    // MARK: Lecture / écriture

    /// Valeurs des clés d'un .nfo (clés en minuscules).
    public static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in lines(text) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            out[String(line[..<eq]).trimmingCharacters(in: .whitespaces).lowercased()] = String(line[line.index(after: eq)...])
        }
        return out
    }

    /// Texte du .nfo : les autres lignes d'un .nfo existant sont gardées ; Tip, Bitmap et Color
    /// sont remplacées (valeur nil = ligne retirée).
    public static func render(existing: String?, values: [String: String?]) -> String {
        var remaining = values // clé d'origine → valeur
        var out: [String] = []
        for line in lines(existing ?? "") {
            if let eq = line.firstIndex(of: "="),
               let key = values.keys.first(where: { $0.lowercased() == line[..<eq].trimmingCharacters(in: .whitespaces).lowercased() }) {
                if let v = remaining.removeValue(forKey: key), let v { out.append("\(key)=\(v)") }
                continue // doublon ou valeur retirée
            }
            if !line.isEmpty { out.append(line) }
        }
        for key in [tipKey, bitmapKey, colorKey] + values.keys.filter({ ![tipKey, bitmapKey, colorKey].contains($0) }) {
            if let v = remaining[key], let v { out.append("\(key)=\(v)") }
        }
        return out.isEmpty ? "" : out.joined(separator: lineEnding) + lineEnding
    }

    static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Nom de l'image copiée dans .images (ex. « drums-claps.png », « cover.png »).
    public static func imageName(for target: TuningTarget) -> String {
        switch target {
        case .cover: return "cover.png"
        case .item(let rel, _):
            let slug = rel.lowercased().folding(options: .diacriticInsensitive, locale: nil)
                .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            let s = String(slug).split(separator: "-").joined(separator: "-")
            return (s.isEmpty ? "item" : s) + ".png"
        }
    }
}
