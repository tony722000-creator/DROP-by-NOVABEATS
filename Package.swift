// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DROP",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DROP", targets: ["DROP"]),
        .executable(name: "dkw-flp", targets: ["dkw-flp"]),
    ],
    targets: [
        // Logique pure (parseur, recherche, classification, copie) : aucune interface,
        // réutilisable pour une future version Windows.
        .target(name: "DKWCore"),
        // L'application macOS (SwiftUI).
        .executableTarget(name: "DROP", dependencies: ["DKWCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        // Outil en ligne de commande : affiche les samples d'un .flp (même code de parsing que l'app).
        .executableTarget(name: "dkw-flp", dependencies: ["DKWCore"]),
    ]
)
