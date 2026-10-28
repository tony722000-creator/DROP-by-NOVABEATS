import Foundation
import DKWCore

/// Tests automatiques (pas besoin d'Xcode) : `dkw-flp --self-test`.
enum SelfTest {
    nonisolated(unsafe) static var failures = 0
    static func check(_ ok: Bool, _ label: String) {
        print(ok ? "  ✅ \(label)" : "  ❌ \(label)")
        if !ok { failures += 1 }
    }

    // --- Fabrique de faux .flp ---
    static func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
    static func u32(_ v: Int) -> [UInt8] { u16(v & 0xFFFF) + u16(v >> 16) }
    static func varint(_ n: Int) -> [UInt8] {
        var n = n, out: [UInt8] = []
        repeat { var b = UInt8(n & 0x7F); n >>= 7; if n > 0 { b |= 0x80 }; out.append(b) } while n > 0
        return out
    }
    static func text(_ id: Int, _ s: String, utf16: Bool) -> [UInt8] {
        let body: [UInt8] = utf16 ? Array(s.utf16).flatMap { u16(Int($0)) } + [0, 0] : Array(s.utf8) + [0]
        return [UInt8(id)] + varint(body.count) + body
    }
    static func flp(version: String, utf16: Bool, channels: [(name: String, path: String?)], extra: [UInt8] = []) -> Data {
        var ev: [UInt8] = text(199, version, utf16: false)
        ev += [28, 1]                          // événement BYTE quelconque
        ev += [128 + 5] + u32(12345)           // événement DWORD quelconque
        for (i, c) in channels.enumerated() {
            ev += [64] + u16(i)
            ev += [21, 0]
            ev += text(203, c.name, utf16: utf16)
            if let p = c.path { ev += text(196, p, utf16: utf16) }
            ev += [210] + varint(5) + [1, 2, 3, 4, 5] // blob plugin ignoré
        }
        ev += extra
        let header: [UInt8] = Array("FLhd".utf8) + u32(6) + u16(0) + u16(channels.count) + u16(96)
        return Data(header + Array("FLdt".utf8) + u32(ev.count) + ev)
    }

    static func run() -> Bool {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("dkw-selftest-\(UUID().uuidString)")
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        print("Parseur")
        let modern = flp(version: "21.2.3.3586", utf16: true, channels: [
            ("Kick Principal", "C:\\Users\\Beat\\Sounds\\Kick 01.wav"),
            ("Mon 808", "%FLStudioFactoryData%\\Data\\Patches\\Packs\\808 Low.wav"),
            ("FPC", nil),
            ("Hat", "/Users/x/Drums/closed_hat.WAV"),
            ("Doublon", "C:\\Users\\Beat\\Sounds\\Kick 01.wav"),
            ("Interdit", "C:\\notes.txt"),
        ])
        let p1 = try? FLPParser.parse(data: modern)
        check(p1?.samples.count == 5, "UTF-16 : 5 chemins lus (dont le doublon et le .txt)")
        check(p1?.samples.first?.path == "C:\\Users\\Beat\\Sounds\\Kick 01.wav", "UTF-16 : chemin Windows exact")
        check(p1?.samples.first?.channelName == "Kick Principal", "UTF-16 : nom du channel associé")
        check(p1?.flVersion == "21.2.3.3586", "version de FL lue")

        let old = flp(version: "9.1.0", utf16: false, channels: [("Snare", "C:\\Old\\snare.wav")])
        let p2 = try? FLPParser.parse(data: old)
        check(p2?.samples.first?.path == "C:\\Old\\snare.wav", "ASCII (ancienne version de FL)")

        check((try? FLPParser.parse(data: Data("pas un flp du tout, vraiment pas un flp".utf8))) == nil, "fichier quelconque → erreur propre")
        check((try? FLPParser.parse(data: Data())) == nil, "fichier vide → erreur propre")
        let cut = modern.prefix(modern.count - 30)
        let p3 = try? FLPParser.parse(data: Data(cut))
        check(p3 != nil && p3!.truncated, "fichier coupé → lecture partielle sans planter")
        var rng = SystemRandomNumberGenerator()
        var noPanic = true
        for _ in 0..<300 {
            var bytes = [UInt8](modern)
            for _ in 0..<12 { bytes[Int.random(in: 0..<bytes.count, using: &rng)] = UInt8.random(in: 0...255, using: &rng) }
            _ = try? FLPParser.parse(data: Data(bytes))
        }
        check(noPanic, "300 fichiers corrompus au hasard : aucun plantage")
        noPanic = true

        print("Classification")
        func t(_ f: String, _ parent: String? = nil, _ ch: String? = nil) -> SoundType {
            Classifier.detect(fileName: f, parentFolder: parent, channelName: ch).type
        }
        check(t("808 Kick.wav") == .drum808, "808 testé avant kick")
        check(t("Open Hat 03.wav") == .openhat, "open hat avant hihat")
        check(t("OpenHat.wav") == .openhat, "OpenHat (camelCase)")
        check(t("closed_hat_2.wav") == .hihat, "closed hat")
        check(t("Hi-Hat.wav") == .hihat, "Hi-Hat")
        check(t("BD_01.wav") == .kick, "bd = mot entier")
        check(t("abdomen.wav") == .autres, "bd dans « abdomen » ignoré")
        check(t("thatsound.wav") == .autres, "hat dans « thatsound » ignoré")
        check(t("Tomorrow.wav") == .autres, "tom dans « Tomorrow » ignoré")
        check(t("Kickdrum.wav") == .kick, "kickdrum (mot long reconnu à l'intérieur)")
        check(t("Clap_Layer.wav") == .clap, "clap")
        check(t("SD 2.wav") == .snare, "sd")
        check(t("RimShot.wav") == .rim, "rimshot")
        check(t("Ride Cymbal.wav") == .crash, "ride/cymbal → crash")
        check(t("Bride.wav") == .autres, "ride dans « Bride » ignoré")
        check(t("Riser_up.wav") == .fx, "riser → fx")
        check(t("Mélodie 1.wav") == .loop, "mélodie (accent)")
        check(t("xyz123.wav", "Snares") == .snare, "dossier parent utilisé")
        check(t("xyz.wav", "stuff", "Mon Clap") == .clap, "nom du channel utilisé en dernier")
        check(t("Sampler.wav", nil, "Sampler") == .autres, "« Sampler » ≠ loop")
        check(t("zzz.wav") == .autres, "inconnu → autres")

        print("Nommage")
        check(Naming.sanitize("Mon  Titre: *cool*?", underscoreSpaces: true) == "Mon_Titre_cool", "caractères interdits + espaces → _")

        print("Recherche + copie")
        let lib = tmp.appendingPathComponent("Biblio/Drums/Kicks")
        let dl = tmp.appendingPathComponent("Downloads")
        let sec = tmp.appendingPathComponent("Disque")
        for d in [lib, dl, sec] { try? fm.createDirectory(at: d, withIntermediateDirectories: true) }
        func touch(_ u: URL, _ content: String) { try? Data(content.utf8).write(to: u) }
        touch(lib.appendingPathComponent("Kick 01.wav"), "kick")
        touch(lib.appendingPathComponent("808 Low.wav"), "808low")
        touch(dl.appendingPathComponent("closed_hat.wav"), "hat")
        touch(sec.appendingPathComponent("snare.wav"), "snare")

        let libIndex = Indexer.scan(root: tmp.appendingPathComponent("Biblio"))
        check(libIndex.fileCount == 2, "index : 2 fichiers audio")
        var resolver = SampleResolver(library: libIndex, downloads: Indexer.scan(root: dl, maxDepth: 3))

        let big = flp(version: "21.2.3.3586", utf16: true, channels: [
            ("Kick", "C:\\Users\\Beat\\Sounds\\Kick 01.wav"),
            ("Mon 808", "%FLStudioFactoryData%\\Data\\Patches\\Packs\\808 Low.wav"),
            ("Hat", "/Users/x/Drums/closed_hat.wav"),
            ("Snare", "D:\\Disque\\snare.wav"),
            ("Kick bis", "C:\\autre\\Kick 01.wav"),
            ("Kick 2", "C:\\Users\\Beat\\Sounds\\kick 02.wav"),
        ])
        let flpURL = tmp.appendingPathComponent("monalisa.flp")
        try? big.write(to: flpURL)
        guard var project = try? ProjectAnalyzer.analyze(flp: flpURL, resolver: resolver) else {
            check(false, "analyse du projet"); return false
        }
        check(project.items.count == 5, "5 sons uniques (Kick 01 compté une fois par chemin)")
        let missing = project.items.filter { !$0.isFound }
        check(missing.count == 2, "2 introuvables (snare sur disque débranché, kick 02)")
        check(project.items.first { $0.fileName == "closed_hat.wav" }?.source == .downloads, "trouvé dans Téléchargements")
        check(project.items.first { $0.fileName == "808 Low.wav" }?.source == .library, "variable FL → recherche par nom")
        check(project.items.first { $0.fileName == "808 Low.wav" }?.type == .drum808, "type 808 détecté")

        resolver.fallbacks = [Indexer.scan(root: sec)]
        project.items = ProjectAnalyzer.reresolve(project.items, resolver: resolver)
        check(project.items.filter { !$0.isFound }.count == 1, "dossier de secours : snare retrouvé")

        let out = tmp.appendingPathComponent("Sorties")
        let job = ExtractionJob(flpName: "monalisa", artist: "wazanolimit", title: "mona lisa", outputRoot: out, items: project.items)
        guard let report = try? Extractor.run(job) else { check(false, "extraction"); return false }
        check(report.copied.count == 4, "4 sons copiés (dédoublonnés)")
        check(fm.fileExists(atPath: out.appendingPathComponent("wazanolimit - mona_lisa/kick/kick-wazanolimit-mona_lisa.wav").path), "chemin de sortie conforme")
        check(fm.fileExists(atPath: out.appendingPathComponent("wazanolimit - mona_lisa/808/808-wazanolimit-mona_lisa.wav").path), "dossier 808")
        check(fm.fileExists(atPath: lib.appendingPathComponent("Kick 01.wav").path), "originaux intacts")
        let again = try? Extractor.run(job)
        check(again?.copied.count == 4 && (try? fm.contentsOfDirectory(atPath: out.appendingPathComponent("wazanolimit - mona_lisa/kick").path))?.count == 1,
              "relancer ne crée pas de doublons")

        print(failures == 0 ? "\nTous les tests passent ✅" : "\n\(failures) test(s) en échec ❌")
        return failures == 0
    }
}
