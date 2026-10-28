import Foundation

/// Un sample audio référencé par un channel (Sampler ou audio clip) du projet.
public struct FLPSampleRef: Sendable, Equatable {
    /// Chemin tel que stocké dans le .flp (peut être un chemin Windows ou contenir %FLStudioFactoryData%).
    public let path: String
    public let channelName: String?
    public let channelIndex: Int?
}

public struct FLPProject: Sendable {
    public let flVersion: String?
    public let channelCount: Int
    public let samples: [FLPSampleRef]
    /// Vrai si la fin du fichier était abîmée (on garde ce qui a pu être lu).
    public let truncated: Bool
}

public enum FLPError: Error, LocalizedError {
    case unreadable(String)
    case tooSmall
    case notFLP
    case corrupted

    public var errorDescription: String? {
        switch self {
        case .unreadable(let m): return "Impossible de lire le fichier : \(m)"
        case .tooSmall: return "Ce fichier est trop petit pour être un projet FL Studio."
        case .notFLP: return "Ce fichier n'est pas un projet FL Studio (.flp) valide."
        case .corrupted: return "Ce projet FL Studio semble abîmé : aucune donnée exploitable."
        }
    }
}
