import Foundation
import DKWCore

let usage = """
dkw-flp — liste les samples audio d'un projet FL Studio (.flp)

Usage :
  dkw-flp <projet.flp> [--library <dossier>] [--fallback <dossier>]... [--no-downloads]
  dkw-flp --self-test

Avec --library, chaque sample est aussi recherché (chemin exact, bibliothèque, ~/Downloads, secours).
"""

func printErr(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

var args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty || args.contains("-h") || args.contains("--help") { print(usage); exit(args.isEmpty ? 1 : 0) }
if args.contains("--self-test") { exit(SelfTest.run() ? 0 : 1) }

var flpPath: String?
var libraryPath: String?
var fallbackPaths: [String] = []
var useDownloads = true
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--library": libraryPath = args.isEmpty ? nil : args.removeFirst()
    case "--fallback": if !args.isEmpty { fallbackPaths.append(args.removeFirst()) }
    case "--no-downloads": useDownloads = false
    default: flpPath = a
    }
}
guard let flpPath else { print(usage); exit(1) }

var resolver = SampleResolver()
if let libraryPath {
    let lib = IndexCache.refresh(root: URL(fileURLWithPath: libraryPath)).index
    resolver.library = lib
    print("Bibliothèque : \(lib.fileCount) sons indexés")
    if let bad = lib.unreadable, !bad.isEmpty {
        print("⚠️  \(bad.count) dossier(s) illisible(s) (droits d'accès) :")
        bad.forEach { print("    \($0)") }
    }
    if useDownloads {
        let dl = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        resolver.downloads = Indexer.scan(root: dl, maxDepth: 4, skipPackages: true)
    }
    resolver.fallbacks = fallbackPaths.map { Indexer.scan(root: URL(fileURLWithPath: $0)) }
}

do {
    let url = URL(fileURLWithPath: flpPath)
    let project = try FLPParser.parse(url: url)
    print("Projet : \(url.lastPathComponent)  (FL \(project.flVersion ?? "?"), \(project.channelCount) channels)")
    if project.truncated { print("⚠️  Fin du fichier abîmée : lecture partielle.") }
    let analyzed = try ProjectAnalyzer.analyze(flp: url, resolver: resolver)
    print("\(analyzed.items.count) sample(s) audio :\n")
    for item in analyzed.items {
        let status = libraryPath == nil ? "" : (item.isFound ? "  ✅ \(item.source.label)" : "  ❌ introuvable")
        print("• [\(item.type.displayName)] \(item.fileName)  (channel : \(item.channelName ?? "-"), via \(item.detectedBy.label))\(status)")
        print("    \(item.originalPath)")
    }
} catch {
    printErr("Erreur : \(error.localizedDescription)")
    exit(2)
}
