import Foundation

public enum DetectionSource: String, Sendable {
    case fileName, folder, channel, none

    public var label: String {
        switch self {
        case .fileName: return "nom du fichier"
        case .folder: return "dossier parent"
        case .channel: return "nom du channel"
        case .none: return "non reconnu"
        }
    }
}

public struct Detection: Sendable {
    public let type: SoundType
    public let source: DetectionSource
}

public enum Classifier {
    /// Cherche d'abord dans le nom du fichier, puis le dossier parent, puis le nom du channel FL.
    public static func detect(fileName: String, parentFolder: String?, channelName: String?) -> Detection {
        let stem = (fileName as NSString).deletingPathExtension
        let candidates: [(String?, DetectionSource)] = [
            (stem, .fileName), (parentFolder, .folder), (channelName, .channel),
        ]
        for (text, source) in candidates {
            if let text, let type = match(text) { return Detection(type: type, source: source) }
        }
        return Detection(type: ClassificationRules.fallback, source: .none)
    }

    public static func match(_ text: String) -> SoundType? {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return nil }
        let tokens = normalized.split(separator: " ").map(String.init)
        let padded = " " + normalized + " "

        for rule in ClassificationRules.ordered {
            for raw in rule.keywords {
                var kw = raw
                var forceWhole = false
                if kw.hasPrefix("=") { forceWhole = true; kw.removeFirst() }
                let isPhrase = kw.contains(" ")
                if isPhrase {
                    if padded.contains(" " + kw + " ") || (!forceWhole && normalized.contains(kw)) { return rule.type }
                } else if forceWhole || kw.count <= 3 {
                    if tokens.contains(where: { $0 == kw || $0 == kw + "s" }) { return rule.type }
                } else if normalized.contains(kw) {
                    return rule.type
                }
            }
        }
        return nil
    }

    /// minuscules, sans accents, "camelCase" et lettres/chiffres séparés, tout le reste → espace.
    static func normalize(_ text: String) -> String {
        var spaced = ""
        var prev: Character?
        for ch in text {
            if let p = prev {
                let camel = p.isLowercase && ch.isUppercase
                let digitBoundary = (p.isLetter && ch.isNumber) || (p.isNumber && ch.isLetter)
                if camel || digitBoundary { spaced.append(" ") }
            }
            spaced.append(ch)
            prev = ch
        }
        let folded = spaced.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        let cleaned = folded.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }
}
