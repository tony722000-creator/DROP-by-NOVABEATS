import Foundation

public enum Naming {
    static let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)

    /// Retire les caractères interdits ; `underscoreSpaces` remplace les espaces par "_".
    public static func sanitize(_ text: String, underscoreSpaces: Bool) -> String {
        var s = text.unicodeScalars.filter { !forbidden.contains($0) }.map(String.init).joined()
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if underscoreSpaces {
            s = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: "_")
        }
        while s.hasPrefix(".") { s.removeFirst() }
        return s
    }

    public static func fileName(type: SoundType, artist: String, title: String, number: Int, ext: String) -> String {
        let suffix = number > 1 ? "-\(number)" : ""
        return "\(type.folderName)-\(artist)-\(title)\(suffix).\(ext)"
    }
}
