import AppKit

/// Images et vidéos de la pédale (Branding/ui → DROP.app/Contents/Resources/ui).
/// Chaque image est chargée une seule fois (static let) puis gardée en mémoire.
/// Un fichier absent ou illisible donne nil : l'interface dessine alors un rendu de secours.
enum PedalAssets {
    static func url(_ name: String) -> URL? {
        if let res = Bundle.main.resourceURL?.appendingPathComponent("ui/\(name)"),
           FileManager.default.fileExists(atPath: res.path) { return res }
        let dev = URL(fileURLWithPath: "Branding/ui/\(name)") // lancement depuis le dossier du projet
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    /// `points` = taille d'affichage de référence (l'image en pixels est 2× plus grande → nette sur Retina).
    static func image(_ name: String, points: NSSize? = nil) -> NSImage? {
        guard let url = url(name), let img = NSImage(contentsOf: url), img.isValid else { return nil }
        if let points { img.size = points }
        return img
    }

    static let texture = image("bg-texture.jpg", points: NSSize(width: 1024, height: 1024))
    static let pad = image("start-pad.png")
    static let bezel = image("start-bezel.png")
    static let screw = image("screw.png")
    static let disk = image("blackhole-disk.png")
    static let wisps = image("blackhole-wisps.png")
    static let edgeChips = makeEdgeChips()

    static let loopVideo = url("blackhole-loop.mp4")
    static let absorbVideo = url("blackhole-absorb.mp4")

    /// bg-edge-wear.png a une bande violet uni qui écraserait le relief de la texture :
    /// on ne garde que les écaillures et le liseré argentés (pixels peu saturés).
    private static func makeEdgeChips() -> NSImage? {
        guard let url = url("bg-edge-wear.png"), let src = NSImage(contentsOf: url),
              let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let r = Float(px[i]), g = Float(px[i + 1]), b = Float(px[i + 2])
            let mx = max(r, g, b), mn = min(r, g, b)
            let sat = mx > 0 ? (mx - mn) / mx : 0
            // écaillures et liseré = gris clair ; la bande violette et ses traits sombres disparaissent
            let keep = min(max((0.42 - sat) / 0.22, 0), 1) * min(max((mx - 95) / 60, 0), 1)
            if keep < 1 {
                px[i] = UInt8(r * keep); px[i + 1] = UInt8(g * keep)
                px[i + 2] = UInt8(b * keep); px[i + 3] = UInt8(Float(px[i + 3]) * keep)
            }
        }
        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: w / 2, height: h / 2))
    }
}
