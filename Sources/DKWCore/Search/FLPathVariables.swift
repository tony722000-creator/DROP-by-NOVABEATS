import Foundation

/// Résout les variables de chemin de FL Studio vers les emplacements Mac habituels.
public enum FLPathVariables {
    static let factoryVar = "%flstudiofactorydata%"
    static let userVar = "%flstudiouserdata%"

    public static func hasVariable(_ path: String) -> Bool {
        let l = path.lowercased()
        return l.hasPrefix(factoryVar) || l.hasPrefix(userVar)
    }

    /// Chemins candidats pour un chemin du .flp (le chemin lui-même si pas de variable).
    public static func candidates(for path: String) -> [String] {
        let lower = path.lowercased()
        for (variable, roots) in [(factoryVar, factoryRoots()), (userVar, userRoots())] where lower.hasPrefix(variable) {
            let rest = String(path.dropFirst(variable.count)).replacingOccurrences(of: "\\", with: "/")
            return roots.map { $0 + (rest.hasPrefix("/") ? rest : "/" + rest) }
        }
        return [path]
    }

    static func factoryRoots() -> [String] {
        var roots: [String] = []
        let fm = FileManager.default
        let apps = (try? fm.contentsOfDirectory(atPath: "/Applications")) ?? []
        for app in apps.sorted().reversed() where app.hasPrefix("FL Studio") && app.hasSuffix(".app") {
            let base = "/Applications/\(app)/Contents/Resources"
            roots += [base + "/FL", base + "/FL Studio", base]
        }
        let home = NSHomeDirectory()
        roots += ["/Library/Application Support/Image-Line/FL Studio",
                  home + "/Library/Application Support/Image-Line/FL Studio"]
        return roots
    }

    static func userRoots() -> [String] {
        let home = NSHomeDirectory()
        return [home + "/Documents/Image-Line/FL Studio",
                home + "/Documents/Image-Line",
                home + "/Library/Application Support/Image-Line/FL Studio"]
    }
}
