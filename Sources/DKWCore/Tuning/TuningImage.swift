import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Prépare une image importée (PNG/JPG…) au format du Browser : PNG redimensionné et recadré au centre.
/// Les tailles viennent de FLBrowserFormat.
public enum TuningImage {
    public enum Kind: Sendable { case banner, cover }

    public static func prepare(_ source: URL, as kind: Kind) -> Data? {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil) else { return nil }
        return prepare(src, as: kind)
    }

    public static func prepare(data: Data, as kind: Kind) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return prepare(src, as: kind)
    }

    /// Taille en pixels d'une image PNG/JPG (pour les tests et l'affichage).
    public static func pixelSize(_ data: Data) -> (width: Int, height: Int)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return (img.width, img.height)
    }

    private static func prepare(_ src: CGImageSource, as kind: Kind) -> Data? {
        guard let img = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              img.width > 0, img.height > 0 else { return nil }
        let w = CGFloat(img.width), h = CGFloat(img.height)

        // zone gardée de l'image source (recadrage au centre) et taille finale
        var crop = CGRect(x: 0, y: 0, width: w, height: h)
        let outW: Int, outH: Int
        switch kind {
        case .cover:
            let side = min(w, h)
            crop = CGRect(x: (w - side) / 2, y: (h - side) / 2, width: side, height: side)
            outW = FLBrowserFormat.coverSize; outH = FLBrowserFormat.coverSize
        case .banner:
            let scale = CGFloat(FLBrowserFormat.bannerWidth) / w
            let scaledH = h * scale
            if scaledH > CGFloat(FLBrowserFormat.bannerMaxHeight) {
                let keepH = CGFloat(FLBrowserFormat.bannerMaxHeight) / scale
                crop = CGRect(x: 0, y: (h - keepH) / 2, width: w, height: keepH)
                outH = FLBrowserFormat.bannerMaxHeight
            } else {
                outH = max(1, Int(scaledH.rounded()))
            }
            outW = FLBrowserFormat.bannerWidth
        }

        guard let cropped = img.cropping(to: crop.integral),
              let ctx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        guard let out = ctx.makeImage() else { return nil }

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, out, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
