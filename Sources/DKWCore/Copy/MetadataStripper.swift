import Foundation

/// Retire d'un fichier audio toutes les informations attachées (titre, artiste, commentaires, images,
/// auteur du kit…) en gardant uniquement ce qui sert au son. Sans dépendance, en mémoire :
/// c'est l'appelant qui écrit la COPIE (jamais l'original).
///
/// • MP3  : balises ID3v2 (début), ID3v1 et APE (fin) retirées ; les trames audio restent intactes.
/// • WAV  : on ne garde que les blocs utiles au son (fmt, data, fact, boucles smpl, inst, repères cue/adtl, acid).
/// • AIFF : on ne garde que COMM, SSND, FVER, MARK, INST.
/// • FLAC : on ne garde que STREAMINFO, SEEKTABLE et CUESHEET.
/// • OGG  : non pris en charge (renvoie nil) ; le fichier est copié tel quel.
public enum MetadataStripper {
    public static let supportedExtensions: Set<String> = ["mp3", "wav", "aif", "aiff", "flac"]

    static let wavKeep: Set<String> = ["fmt ", "data", "fact", "smpl", "inst", "cue ", "acid", "plst"]
    static let aiffKeep: Set<String> = ["COMM", "SSND", "FVER", "MARK", "INST"]

    /// Contenu nettoyé, ou nil si le format n'est pas pris en charge ou si le fichier semble abîmé.
    public static func strip(_ file: Data, fileExtension: String) -> Data? {
        let b = [UInt8](file)
        let out: [UInt8]?
        switch fileExtension.lowercased() {
        case "mp3": out = stripMP3(b)
        case "wav": out = stripChunked(b, form: "RIFF", bigEndian: false, keep: wavKeep)
        case "aif", "aiff": out = stripChunked(b, form: "FORM", bigEndian: true, keep: aiffKeep)
        case "flac": out = stripFLAC(b)
        default: out = nil
        }
        return out.map { Data($0) }
    }

    // MARK: MP3

    static func stripMP3(_ b: [UInt8]) -> [UInt8]? {
        var start = 0
        // une ou plusieurs balises ID3v2 au début
        while start + 10 <= b.count, b[start] == 0x49, b[start + 1] == 0x44, b[start + 2] == 0x33 {
            let size = synchsafe(b, start + 6)
            let footer = (b[start + 3] == 4 && b[start + 5] & 0x10 != 0) ? 10 : 0
            let next = start + 10 + size + footer
            guard next <= b.count else { return nil }
            start = next
        }
        var end = b.count
        var changed = true
        while changed {
            changed = false
            // ID3v1 : 128 octets « TAG » à la fin
            if end - start >= 128, b[end - 128] == 0x54, b[end - 127] == 0x41, b[end - 126] == 0x47 {
                end -= 128; changed = true
            }
            // APEv2 : pied « APETAGEX » (32 octets) à la fin
            if end - start >= 32, String(decoding: b[(end - 32)..<(end - 24)], as: UTF8.self) == "APETAGEX" {
                let size = Int(readU32(b, end - 20, false)) // inclut le pied, pas l'en-tête
                let flags = readU32(b, end - 12, false)
                let total = size + (flags & 0x8000_0000 != 0 ? 32 : 0)
                guard total <= end - start else { return nil }
                end -= total; changed = true
            }
        }
        guard end > start else { return nil }
        return Array(b[start..<end])
    }

    // MARK: WAV / AIFF

    static func stripChunked(_ b: [UInt8], form: String, bigEndian: Bool, keep: Set<String>) -> [UInt8]? {
        guard b.count >= 12, String(decoding: b[0..<4], as: UTF8.self) == form else { return nil }
        let end = min(8 + Int(readU32(b, 4, bigEndian)), b.count)
        var kept: [UInt8] = []
        var hasAudio = false
        var i = 12
        while i + 8 <= end {
            let id = String(decoding: b[i..<i + 4], as: UTF8.self)
            let size = Int(readU32(b, i + 4, bigEndian))
            guard i + 8 + size <= b.count else { return nil } // fichier abîmé : on n'y touche pas
            let padded = size + (size & 1)
            var keepIt = keep.contains(id)
            // LIST : on garde « adtl » (étiquettes des repères), on retire « INFO » (titre, artiste…)
            if id == "LIST", size >= 4, String(decoding: b[(i + 8)..<(i + 12)], as: UTF8.self) == "adtl" { keepIt = true }
            if keepIt {
                kept += b[i..<(i + 8 + size)]
                if size & 1 == 1 { kept.append(0) }
                if id == "data" || id == "SSND" { hasAudio = true }
            }
            i += 8 + padded
        }
        guard hasAudio else { return nil }
        let body = Array(b[8..<12]) + kept
        return Array(form.utf8) + writeU32(UInt32(body.count), bigEndian) + body
    }

    // MARK: FLAC

    static func stripFLAC(_ b: [UInt8]) -> [UInt8]? {
        guard b.count >= 8, String(decoding: b[0..<4], as: UTF8.self) == "fLaC" else { return nil }
        var blocks: [[UInt8]] = []
        var i = 4
        var last = false
        while !last {
            guard i + 4 <= b.count else { return nil }
            last = b[i] & 0x80 != 0
            let type = b[i] & 0x7F
            let size = Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
            guard i + 4 + size <= b.count else { return nil }
            if type == 0 || type == 3 || type == 5 { blocks.append(Array(b[i..<(i + 4 + size)])) } // STREAMINFO, SEEKTABLE, CUESHEET
            i += 4 + size
        }
        guard let first = blocks.first, first[0] & 0x7F == 0 else { return nil }
        for k in blocks.indices { blocks[k][0] = (blocks[k][0] & 0x7F) | (k == blocks.count - 1 ? 0x80 : 0) }
        return Array("fLaC".utf8) + blocks.flatMap { $0 } + b[i...]
    }

    // MARK: Octets

    static func synchsafe(_ b: [UInt8], _ o: Int) -> Int {
        Int(b[o] & 0x7F) << 21 | Int(b[o + 1] & 0x7F) << 14 | Int(b[o + 2] & 0x7F) << 7 | Int(b[o + 3] & 0x7F)
    }

    static func readU32(_ b: [UInt8], _ o: Int, _ bigEndian: Bool) -> UInt32 {
        let v = [UInt32(b[o]), UInt32(b[o + 1]), UInt32(b[o + 2]), UInt32(b[o + 3])]
        return bigEndian ? v[0] << 24 | v[1] << 16 | v[2] << 8 | v[3] : v[3] << 24 | v[2] << 16 | v[1] << 8 | v[0]
    }

    static func writeU32(_ v: UInt32, _ bigEndian: Bool) -> [UInt8] {
        let be = [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
        return bigEndian ? be : be.reversed()
    }
}
