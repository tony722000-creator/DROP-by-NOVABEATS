import SwiftUI
import AppKit
import AVFoundation

// Trou noir du panneau gauche.
// • Vidéo en boucle (décodée par la puce vidéo), fusionnée en « écran » : le noir disparaît.
// • Au dépôt d'un .flp : vidéo d'absorption (5 s, flash ≈ 3 s, onde de choc ≈ 4 s)
//   + effets en code synchronisés sur le démarrage réel de la vidéo.
// • Pause quand la fenêtre n'est pas visible ou que l'app est en arrière-plan.
// • Vidéo absente ou illisible : disque + volutes en images qui tournent (secours).

/// Repères de la vidéo d'absorption (en secondes).
enum AbsorbTiming {
    static let flash = 3.0
    static let shockwave = 4.0
    static let duration = 5.04
}

struct BlackHoleView: View {
    let absorbToken: Int
    @State private var absorbStart: Date?
    @State private var videoFailed = PedalAssets.loopVideo == nil

    var body: some View {
        ZStack {
            if DemoMode.isSnapshot {
                PosterFrame()
            } else if videoFailed {
                FallbackDisk(absorbing: absorbStart != nil)
            } else {
                BlackHoleVideo(absorbToken: absorbToken,
                               onAbsorbStart: { startEffects(at: $0) },
                               onFailure: { videoFailed = true })
            }
            if let start = absorbStart {
                AbsorbEffects(start: start)
            }
        }
        .onChange(of: absorbToken) { _, new in
            // sans vidéo d'absorption, les effets démarrent tout de suite
            if videoFailed || PedalAssets.absorbVideo == nil { BlackHoleVideo.playedToken = new; startEffects(at: .now) }
        }
        .onAppear {
            if videoFailed || PedalAssets.absorbVideo == nil, absorbToken > BlackHoleVideo.playedToken {
                BlackHoleVideo.playedToken = absorbToken
                startEffects(at: .now)
            }
        }
    }

    private func startEffects(at date: Date) {
        absorbStart = date
        Task {
            try? await Task.sleep(for: .seconds(AbsorbTiming.duration + 0.1))
            if absorbStart == date { absorbStart = nil } // plus aucun calcul une fois l'effet fini
        }
    }
}

// MARK: Vidéo

struct BlackHoleVideo: NSViewRepresentable {
    let absorbToken: Int
    let onAbsorbStart: (Date) -> Void
    let onFailure: () -> Void

    /// Dernière absorption jouée (la vue est recréée en changeant d'onglet : on ne la rejoue pas).
    static var playedToken = 0

    func makeNSView(context: Context) -> BlackHoleNSView {
        let v = BlackHoleNSView()
        v.onAbsorbStart = onAbsorbStart
        v.onFailure = onFailure
        context.coordinator.lastToken = absorbToken
        // premier .flp : la vue apparaît justement parce qu'on vient d'en déposer un
        if absorbToken > Self.playedToken {
            Self.playedToken = absorbToken
            DispatchQueue.main.async { v.absorb() }
        }
        return v
    }

    func updateNSView(_ v: BlackHoleNSView, context: Context) {
        v.onAbsorbStart = onAbsorbStart
        v.onFailure = onFailure
        if absorbToken != context.coordinator.lastToken {
            context.coordinator.lastToken = absorbToken
            Self.playedToken = absorbToken
            v.absorb()
        }
    }

    static func dismantleNSView(_ v: BlackHoleNSView, coordinator: Coordinator) { v.teardown() }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var lastToken = 0 }
}

final class BlackHoleNSView: NSView {
    var onAbsorbStart: ((Date) -> Void)?
    var onFailure: (() -> Void)?

    private let container = CALayer()
    private let fadeMask = CAGradientLayer()
    private let loopLayer = AVPlayerLayer()
    private let absorbLayer = AVPlayerLayer()
    private let loopPlayer = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var absorbPlayer: AVPlayer?
    private var isAbsorbing = false
    private var observers: [NSObjectProtocol] = []
    private var windowObservers: [NSObjectProtocol] = []
    private var kvo: [NSKeyValueObservation] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layerUsesCoreImageFilters = true // nécessaire pour la fusion « écran » sur macOS

        container.compositingFilter = "screenBlendMode" // le noir de la vidéo devient transparent
        // bords adoucis : même si la fusion n'est pas appliquée, pas de carré noir visible
        fadeMask.type = .radial
        fadeMask.colors = [NSColor.white.cgColor, NSColor.white.cgColor, NSColor.clear.cgColor]
        fadeMask.locations = [0, 0.62, 1]
        fadeMask.startPoint = CGPoint(x: 0.5, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 1)
        container.mask = fadeMask
        layer?.addSublayer(container)

        for l in [loopLayer, absorbLayer] {
            l.videoGravity = .resizeAspect
            l.backgroundColor = NSColor.clear.cgColor
            container.addSublayer(l)
        }
        absorbLayer.opacity = 0

        guard let loopURL = PedalAssets.loopVideo else { return }
        loopPlayer.isMuted = true
        loopPlayer.preventsDisplaySleepDuringVideoPlayback = false
        let looper = AVPlayerLooper(player: loopPlayer, templateItem: AVPlayerItem(url: loopURL))
        self.looper = looper
        loopLayer.player = loopPlayer
        kvo.append(looper.observe(\.status, options: [.new]) { [weak self] l, _ in
            if l.status == .failed { DispatchQueue.main.async { self?.onFailure?() } }
        })

        if let absorbURL = PedalAssets.absorbVideo {
            let p = AVPlayer(url: absorbURL)
            p.isMuted = true
            p.preventsDisplaySleepDuringVideoPlayback = false
            p.actionAtItemEnd = .pause
            absorbPlayer = p
            absorbLayer.player = p
            observers.append(NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { [weak self] _ in
                    self?.absorbFinished()
                })
            kvo.append(p.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                guard player.timeControlStatus == .playing else { return }
                DispatchQueue.main.async {
                    guard let self, self.isAbsorbing, !self.absorbReported else { return }
                    self.absorbReported = true
                    // aligne les effets en code sur la position réelle de la vidéo
                    let elapsed = player.currentTime().seconds
                    self.onAbsorbStart?(Date().addingTimeInterval(-(elapsed.isFinite ? elapsed : 0)))
                }
            })
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private var absorbReported = false

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = bounds
        fadeMask.frame = container.bounds
        loopLayer.frame = container.bounds
        absorbLayer.frame = container.bounds
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let nc = NotificationCenter.default
        windowObservers.forEach { nc.removeObserver($0) }
        windowObservers.removeAll()
        guard let window else { pauseAll(); return }
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification] {
            windowObservers.append(nc.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in self?.updatePlayback() })
        }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            windowObservers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.updatePlayback() })
        }
        updatePlayback()
    }

    private var shouldPlay: Bool {
        guard let window else { return false }
        return window.occlusionState.contains(.visible) && !window.isMiniaturized && NSApp.isActive
    }

    private func updatePlayback() {
        if !shouldPlay { pauseAll(); return }
        if isAbsorbing { absorbPlayer?.play() } else { loopPlayer.play() }
    }

    private func pauseAll() {
        loopPlayer.pause()
        absorbPlayer?.pause()
    }

    func absorb() {
        guard let p = absorbPlayer else { return }
        isAbsorbing = true
        absorbReported = false
        p.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        p.play()
        // court fondu depuis la boucle, puis la boucle se cale au début (même image que la fin de l'absorption)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        absorbLayer.opacity = 1
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.isAbsorbing else { return }
            self.loopPlayer.pause()
            self.loopPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    private func absorbFinished() {
        isAbsorbing = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        absorbLayer.opacity = 0
        CATransaction.commit()
        updatePlayback()
    }

    func teardown() {
        pauseAll()
        (observers + windowObservers).forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        windowObservers.removeAll()
        kvo.forEach { $0.invalidate() }
        kvo.removeAll()
        looper?.disableLooping()
        loopLayer.player = nil
        absorbLayer.player = nil
    }
}

// MARK: Secours (images) et image fixe pour les captures

private struct FallbackDisk: View {
    let absorbing: Bool
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: activeState == .inactive)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let speed = absorbing ? 4.0 : 1.0
            ZStack {
                if let wisps = PedalAssets.wisps {
                    Image(nsImage: wisps).resizable().scaledToFit()
                        .rotationEffect(.degrees(-(t * 4 * speed).truncatingRemainder(dividingBy: 360)))
                        .opacity(0.7)
                }
                if let disk = PedalAssets.disk {
                    Image(nsImage: disk).resizable().scaledToFit().scaleEffect(0.78)
                        .rotationEffect(.degrees(-(t * 9 * speed).truncatingRemainder(dividingBy: 360)))
                }
                Circle().fill(Color.black).scaleEffect(0.2)
            }
            .scaleEffect(y: 0.55) // incliné comme la vidéo
        }
    }
}

/// Première image de la boucle (utilisée pour les captures d'écran de démonstration).
private struct PosterFrame: View {
    @State private var image: CGImage?

    /// Équivalent de la fusion « écran » : la luminosité devient l'opacité, le noir devient transparent.
    static func blackToAlpha(_ cg: CGImage) -> CGImage? {
        let w = cg.width, h = cg.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            px[i + 3] = max(px[i], px[i + 1], px[i + 2])
        }
        return ctx.makeImage()
    }

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            }
        }
        .task {
            guard let url = PedalAssets.loopVideo else { return }
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.maximumSize = CGSize(width: 1440, height: 1440)
            if let frame = try? await gen.image(at: CMTime(seconds: 2, preferredTimescale: 600)).image {
                image = Self.blackToAlpha(frame)
            }
        }
    }
}

// MARK: Effets d'absorption (calculés uniquement pendant les 5 s de l'effet)

private struct AbsorbEffects: View {
    let start: Date

    private struct Particle { let angle, radius, delay, duration, size: Double; let hot: Bool }
    @State private var particles: [Particle] = (0..<80).map { _ in
        Particle(angle: .random(in: 0..<(2 * .pi)), radius: .random(in: 0.3...0.62),
                 delay: .random(in: 0...1.1), duration: .random(in: 1.4...1.9),
                 size: .random(in: 1.2...2.8), hot: Bool.random())
    }

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            Canvas { g, size in
                let side = min(size.width, size.height)
                let c = CGPoint(x: size.width * 0.49, y: size.height * 0.44)
                g.blendMode = .plusLighter

                // particules aspirées en spirale (plan incliné comme le disque)
                for p in particles {
                    let q = (t - p.delay) / p.duration
                    guard q > 0, q < 1 else { continue }
                    let e = q * q
                    let r = side * p.radius * (1 - e)
                    let a = p.angle + q * 2.4 * .pi
                    let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r * 0.42)
                    let s = p.size * (1 - 0.6 * e)
                    let alpha = min(1, q * 8) * (1 - e * 0.5)
                    g.fill(Path(ellipseIn: CGRect(x: pt.x - s, y: pt.y - s, width: s * 2, height: s * 2)),
                           with: .color((p.hot ? Studio.lavender : Color.white).opacity(alpha)))
                }

                // le .flp spirale vers le centre et disparaît juste avant le flash
                let fq = t / (AbsorbTiming.flash - 0.15)
                if fq > 0, fq < 1, let chip = g.resolveSymbol(id: 0) {
                    let e = fq * fq
                    let r = side * 0.42 * (1 - e)
                    let a = 2.5 + fq * 1.7 * .pi
                    var cg = g
                    cg.translateBy(x: c.x + cos(a) * r, y: c.y + sin(a) * r * 0.5)
                    cg.rotate(by: .degrees(fq * 540))
                    cg.scaleBy(x: 1 - 0.9 * e, y: 1 - 0.9 * e)
                    cg.opacity = fq > 0.85 ? (1 - fq) / 0.15 : 1
                    cg.blendMode = .normal
                    cg.draw(chip, at: .zero)
                }

                // flash ≈ 3 s
                let ft = t - AbsorbTiming.flash
                let flash = ft < 0 ? max(0, 1 + ft / 0.15) : max(0, 1 - ft / 0.6)
                if flash > 0 {
                    let rr = side * 0.42
                    g.fill(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr * 0.7, width: rr * 2, height: rr * 1.4)),
                           with: .radialGradient(Gradient(colors: [.white.opacity(0.9 * flash), Studio.accent.opacity(0.5 * flash), .clear]),
                                                 center: c, startRadius: 0, endRadius: rr))
                }

                // onde de choc ≈ 4 s
                let sq = (t - AbsorbTiming.shockwave) / 0.9
                if sq > 0, sq < 1 {
                    let rr = side * (0.1 + 0.55 * sq)
                    let ring = Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr * 0.55, width: rr * 2, height: rr * 1.1))
                    g.stroke(ring, with: .color(Studio.lavender.opacity(0.85 * (1 - sq))), lineWidth: 1 + 6 * (1 - sq))
                    g.stroke(ring, with: .color(Studio.accent.opacity(0.3 * (1 - sq))), lineWidth: 18 * (1 - sq))
                }
            } symbols: {
                FlpChip().tag(0)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Le « fichier .flp » qui se fait aspirer.
private struct FlpChip: View {
    var body: some View {
        ZStack {
            Image(systemName: "doc.fill").font(.system(size: 40)).foregroundStyle(Studio.cream)
            Text("FLP").font(.system(size: 10, weight: .black, design: .monospaced)).foregroundStyle(Studio.ink)
                .offset(y: 5)
        }
        .shadow(color: Studio.accent, radius: 8)
    }
}
