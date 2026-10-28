import Foundation

/// Lecteur de fichiers .flp (FL Studio), sans dépendance.
/// Format : "FLhd" + en-tête, puis "FLdt" + une suite d'événements.
/// IDs vérifiés avec PyFLP : 64 = nouveau channel, 192 = nom par défaut, 196 = chemin de sample,
/// 199 = version de FL, 203 = nom donné au channel/plugin.
public enum FLPParser {
    enum EventID {
        static let newChannel = 64
        static let defaultName = 192
        static let samplePath = 196
        static let flVersion = 199
        static let name = 203
    }

    public static func parse(url: URL) throws -> FLPProject {
        let data: Data
        do { data = try Data(contentsOf: url, options: .mappedIfSafe) }
        catch { throw FLPError.unreadable(error.localizedDescription) }
        return try parse(data: data)
    }

    public static func parse(data: Data) throws -> FLPProject {
        let b = [UInt8](data)
        guard b.count >= 22 else { throw FLPError.tooSmall }
        guard Array(b[0..<4]) == Array("FLhd".utf8) else { throw FLPError.notFLP }

        let headerLen = Int(u32(b, 4))
        let dtPos = 8 + headerLen
        guard headerLen < b.count, dtPos + 8 <= b.count,
              Array(b[dtPos..<dtPos + 4]) == Array("FLdt".utf8) else { throw FLPError.notFLP }

        let start = dtPos + 8
        let end = min(b.count, start + Int(u32(b, dtPos + 4)))

        var i = start
        var version: String?
        var utf16 = true // FL ≥ 11.5 ; corrigé dès qu'on lit la version
        var channel = -1
        var channelCount = 0
        var names: [Int: String] = [:]
        var defaultNames: [Int: String] = [:]
        var rawSamples: [(path: String, channel: Int)] = []
        var truncated = false
        var eventCount = 0

        parsing: while i < end {
            let id = Int(b[i]); i += 1
            var len: Int
            switch id {
            case 0..<64: len = 1
            case 64..<128: len = 2
            case 128..<192: len = 4
            default:
                len = 0
                var shift = 0
                while true {
                    guard i < end else { truncated = true; break parsing }
                    let byte = b[i]; i += 1
                    len |= Int(byte & 0x7F) << shift
                    shift += 7
                    if byte & 0x80 == 0 { break }
                    if shift > 28 { truncated = true; break parsing }
                }
            }
            guard len >= 0, i + len <= end else { truncated = true; break }
            let payload = b[i..<i + len]
            i += len
            eventCount += 1

            switch id {
            case EventID.newChannel:
                if len >= 2 { channel = Int(payload[payload.startIndex]) | Int(payload[payload.startIndex + 1]) << 8 }
                channelCount += 1
            case EventID.flVersion:
                let v = decode(payload, utf16: false)
                version = v
                let parts = v.split(separator: ".").compactMap { Int($0) }
                if let major = parts.first {
                    let minor = parts.count > 1 ? parts[1] : 0
                    utf16 = major > 11 || (major == 11 && minor >= 5)
                }
            case EventID.samplePath:
                let p = decode(payload, utf16: utf16)
                if !p.isEmpty { rawSamples.append((p, channel)) }
            case EventID.name:
                if channel >= 0 { names[channel] = decode(payload, utf16: utf16) }
            case EventID.defaultName:
                if channel >= 0 { defaultNames[channel] = decode(payload, utf16: utf16) }
            default: break
            }
        }

        guard eventCount > 0 else { throw FLPError.corrupted }

        func clean(_ s: String?) -> String? {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return t
        }
        let samples = rawSamples.map { raw in
            FLPSampleRef(path: raw.path,
                         channelName: clean(names[raw.channel]) ?? clean(defaultNames[raw.channel]),
                         channelIndex: raw.channel >= 0 ? raw.channel : nil)
        }
        return FLPProject(flVersion: version, channelCount: channelCount, samples: samples, truncated: truncated)
    }

    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }

    static func decode(_ bytes: ArraySlice<UInt8>, utf16: Bool) -> String {
        if utf16 && bytes.count % 2 == 0 {
            var units: [UInt16] = []
            var j = bytes.startIndex
            while j + 1 < bytes.endIndex {
                let u = UInt16(bytes[j]) | UInt16(bytes[j + 1]) << 8
                if u == 0 { break }
                units.append(u)
                j += 2
            }
            return String(decoding: units, as: UTF16.self)
        }
        let trimmed = Data(bytes.prefix { $0 != 0 })
        return String(data: trimmed, encoding: .utf8) ?? String(data: trimmed, encoding: .isoLatin1) ?? ""
    }
}
