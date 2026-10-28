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
        check(fm.fileExists(atPath: out.appendingPathComponent("kick/kick-wazanolimit-mona_lisa.wav").path), "chemin de sortie conforme")
        check(fm.fileExists(atPath: out.appendingPathComponent("808/808-wazanolimit-mona_lisa.wav").path), "dossier 808")
        check(fm.fileExists(atPath: lib.appendingPathComponent("Kick 01.wav").path), "originaux intacts")
        let again = try? Extractor.run(job)
        check(again?.copied.count == 4 && (try? fm.contentsOfDirectory(atPath: out.appendingPathComponent("kick").path))?.count == 1,
              "relancer ne crée pas de doublons")

        // une 2e prod va dans les MÊMES dossiers de type, sans écraser la 1re
        let job2 = ExtractionJob(flpName: "autre", artist: "wazanolimit", title: "autre son", outputRoot: out, items: project.items)
        _ = try? Extractor.run(job2)
        let kicks = (try? fm.contentsOfDirectory(atPath: out.appendingPathComponent("kick").path)) ?? []
        check(kicks.sorted() == ["kick-wazanolimit-autre_son.wav", "kick-wazanolimit-mona_lisa.wav"], "2 prods → même dossier kick, noms distincts")
        let top = ((try? fm.contentsOfDirectory(atPath: out.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        check(top == ["808", "hihat", "kick", "snare"], "pas de dossier « artiste - titre »")

        print("Nettoyage des infos attachées")
        let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 0x11, count: 40) + [0xFF, 0xD9]
        func frame(_ id: String, _ body: [UInt8]) -> [UInt8] { Array(id.utf8) + [UInt8(body.count >> 24 & 0xFF), UInt8(body.count >> 16 & 0xFF), UInt8(body.count >> 8 & 0xFF), UInt8(body.count & 0xFF), 0, 0] + body }
        let frames = frame("TIT2", [0] + Array("Kit de quelqu'un".utf8)) + frame("APIC", [0] + Array("image/jpeg".utf8) + [0, 3, 0] + jpeg)
        let tag: [UInt8] = Array("ID3".utf8) + [3, 0, 0] + [0, 0, UInt8(frames.count >> 7 & 0x7F), UInt8(frames.count & 0x7F)] + frames
        let audio: [UInt8] = (0..<999).map { UInt8($0 % 251) }
        let mark = Array("Kit de quelqu'un".utf8)
        func has(_ hay: Data?, _ needle: [UInt8]) -> Bool { hay?.range(of: Data(needle)) != nil }
        func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF)] }
        func be32(_ v: Int) -> [UInt8] { le32(v).reversed() }

        // MP3 : ID3v2 + son + APE + ID3v1
        let mpegAudio: [UInt8] = [0xFF, 0xFB, 0x90, 0x00] + audio
        let apeItems: [UInt8] = Array(repeating: 0x41, count: 20)
        let apeFooter: [UInt8] = Array("APETAGEX".utf8) + le32(2000) + le32(apeItems.count + 32) + le32(1) + le32(0) + Array(repeating: 0, count: 8)
        let id3v1: [UInt8] = Array("TAG".utf8) + mark + Array(repeating: 0, count: 125 - mark.count)
        let mp3 = Data(tag + mpegAudio + apeItems + apeFooter + id3v1)
        check(MetadataStripper.strip(mp3, fileExtension: "mp3") == Data(mpegAudio), "MP3 : ID3v2, APE et ID3v1 retirés, son intact")

        // WAV : fmt + LIST INFO + id3 + bext + smpl + data
        let fmt: [UInt8] = Array("fmt ".utf8) + le32(16) + [1, 0, 1, 0] + le32(44100) + le32(88200) + [2, 0, 16, 0]
        let dataChunk: [UInt8] = Array("data".utf8) + le32(audio.count) + audio + [0]
        let info: [UInt8] = Array("INFO".utf8) + Array("IART".utf8) + le32(mark.count) + mark
        let listChunk: [UInt8] = Array("LIST".utf8) + le32(info.count) + info
        let id3Chunk: [UInt8] = Array("id3 ".utf8) + le32(tag.count) + tag + (tag.count % 2 == 1 ? [0] : [])
        let bext: [UInt8] = Array("bext".utf8) + le32(mark.count) + mark
        let smpl: [UInt8] = Array("smpl".utf8) + le32(8) + Array(repeating: 7, count: 8)
        let wavBody = Array("WAVE".utf8) + fmt + listChunk + id3Chunk + bext + smpl + dataChunk
        let wav = Data(Array("RIFF".utf8) + le32(wavBody.count) + wavBody)
        let cleanWav = MetadataStripper.strip(wav, fileExtension: "wav")
        let expectedBody = Array("WAVE".utf8) + fmt + smpl + dataChunk
        check(cleanWav == Data(Array("RIFF".utf8) + le32(expectedBody.count) + expectedBody), "WAV : infos et image retirées ; format, boucles et son gardés")
        check(MetadataStripper.strip(Data("pas un wav".utf8), fileExtension: "wav") == nil, "fichier abîmé : laissé tel quel")

        // AIFF : COMM + NAME + ID3 + SSND
        let comm: [UInt8] = Array("COMM".utf8) + be32(18) + Array(repeating: 1, count: 18)
        let ssnd: [UInt8] = Array("SSND".utf8) + be32(audio.count + 8) + Array(repeating: 0, count: 8) + audio + [0]
        let name: [UInt8] = Array("NAME".utf8) + be32(mark.count) + mark
        let aiffBody = Array("AIFF".utf8) + comm + name + Array("ID3 ".utf8) + be32(tag.count) + tag + (tag.count % 2 == 1 ? [0] : []) + ssnd
        let cleanAiff = MetadataStripper.strip(Data(Array("FORM".utf8) + be32(aiffBody.count) + aiffBody), fileExtension: "aiff")
        let expectedAiff = Array("AIFF".utf8) + comm + ssnd
        check(cleanAiff == Data(Array("FORM".utf8) + be32(expectedAiff.count) + expectedAiff), "AIFF : nom et balise retirés, son gardé")

        // FLAC : STREAMINFO + VORBIS_COMMENT + PICTURE (dernier) + trames
        let streamInfo: [UInt8] = [0x00, 0, 0, 34] + Array(repeating: 5, count: 34)
        let comment: [UInt8] = [0x04, 0, 0, UInt8(mark.count)] + mark
        let picture: [UInt8] = [0x86, 0, 0, UInt8(jpeg.count)] + jpeg
        let flacFrames: [UInt8] = [0xFF, 0xF8] + audio
        let cleanFlac = MetadataStripper.strip(Data(Array("fLaC".utf8) + streamInfo + comment + picture + flacFrames), fileExtension: "flac")
        check(cleanFlac == Data(Array("fLaC".utf8) + [0x80] + streamInfo.dropFirst() + flacFrames), "FLAC : commentaires et image retirés, son gardé")

        // Extraction : infos macOS attachées non recopiées, original intact, pas de doublon
        let srcDir = tmp.appendingPathComponent("KitSrc"), cleanOut = tmp.appendingPathComponent("CleanOut")
        try? fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
        let srcWav = srcDir.appendingPathComponent("Clap 1.wav")
        try? wav.write(to: srcWav)
        _ = srcWav.withUnsafeFileSystemRepresentation { path in
            Array("Kit de quelqu'un".utf8).withUnsafeBytes { setxattr(path!, "com.apple.metadata:kMDItemWhereFroms", $0.baseAddress, $0.count, 0, 0) }
        }
        let cleanItem = SampleItem(originalPath: srcWav.path, fileName: "Clap 1.wav", channelName: nil, resolved: srcWav,
                                   source: .exact, type: .clap, detectedBy: .fileName, included: true)
        let cleanJob = ExtractionJob(flpName: "x", artist: "nova", title: "piste", outputRoot: cleanOut, items: [cleanItem])
        _ = try? Extractor.run(cleanJob)
        _ = try? Extractor.run(cleanJob)
        let dest = cleanOut.appendingPathComponent("clap/clap-nova-piste.wav")
        // noms des attributs étendus ; « com.apple.provenance » est posé par macOS sur tout fichier créé (aucune info du kit)
        var xbuf = [CChar](repeating: 0, count: 4096)
        let xlen = listxattr(dest.path, &xbuf, xbuf.count, 0)
        let destXattrs = (xlen > 0 ? xbuf[0..<xlen].split(separator: 0).map { String(cString: Array($0) + [0]) } : [])
            .filter { $0 != "com.apple.provenance" }
        check((try? fm.contentsOfDirectory(atPath: cleanOut.appendingPathComponent("clap").path)) == ["clap-nova-piste.wav"], "relancer ne crée pas de doublon")
        check(!has(try? Data(contentsOf: dest), mark), "la copie n'a plus aucune info du kit")
        check(destXattrs.isEmpty, "la copie n'a plus d'infos macOS attachées (icône, étiquettes, lien de téléchargement…)")
        check((try? Data(contentsOf: srcWav)) == wav, "l'original n'est pas modifié")

        print(failures == 0 ? "\nTous les tests passent ✅" : "\n\(failures) test(s) en échec ❌")
        return failures == 0
    }
}
