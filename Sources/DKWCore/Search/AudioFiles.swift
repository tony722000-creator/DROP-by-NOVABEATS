import Foundation

public enum AudioFiles {
    public static let extensions: Set<String> = ["wav", "mp3", "aif", "aiff", "flac", "ogg"]

    public static func isAudio(_ name: String) -> Bool {
        extensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// Dernier élément d'un chemin, qu'il soit Windows (\) ou Mac (/).
    public static func fileName(of path: String) -> String {
        components(of: path).last ?? path
    }

    public static func parentFolderName(of path: String) -> String? {
        let c = components(of: path)
        return c.count >= 2 ? c[c.count - 2] : nil
    }

    public static func components(of path: String) -> [String] {
        path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init)
    }
}
