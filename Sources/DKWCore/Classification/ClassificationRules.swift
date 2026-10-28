// ─────────────────────────────────────────────────────────────────────────────
//  RÈGLES DE CLASSIFICATION — le seul fichier à modifier pour changer la détection.
//
//  • L'ORDRE COMPTE : le premier type dont un mot-clé correspond gagne.
//    ("808" avant "kick", "open hat" avant "hihat").
//  • Casse, accents, tirets, underscores et "camelCase" sont ignorés
//    ("OpenHat", "open_hat", "Open-Hat" → "open hat").
//  • Mots courts (3 lettres ou moins, ex. "bd", "sd", "hh", "oh", "808") : reconnus
//    seulement comme MOTS ENTIERS (un "s" final est toléré : "hats").
//  • Mots plus longs : reconnus aussi à l'intérieur d'un mot ("kickdrum").
//  • Préfixe "=" : force « mot entier » même pour un mot long ("=ride").
// ─────────────────────────────────────────────────────────────────────────────

public enum ClassificationRules {
    public static let ordered: [(type: SoundType, keywords: [String])] = [
        (.drum808,  ["808", "sub", "bass 808", "bass808"]),
        (.kick,     ["kick", "kck", "bd", "bassdrum", "bass drum"]),
        (.snare,    ["snare", "snr", "sd"]),
        (.clap,     ["clap", "clp"]),
        (.openhat,  ["open hat", "openhat", "open hh", "open hi hat", "openhihat", "ohh", "oh", "ohat"]),
        (.hihat,    ["hihat", "hi hat", "hh", "hat", "closed hat", "closedhat", "chh"]),
        (.rim,      ["rimshot", "rim"]),
        (.perc,     ["perc", "percussion", "conga", "bongo", "shaker", "tom"]),
        (.crash,    ["crash", "cymbal", "cymbale", "=ride"]),
        (.fx,       ["fx", "riser", "impact", "sweep", "transition", "reverse"]),
        (.vox,      ["vox", "vocal", "voice", "chant", "adlib", "ad lib"]),
        (.loop,     ["loop", "melody", "melodie", "=sample"]),
    ]

    /// Type utilisé quand rien n'est reconnu.
    public static let fallback: SoundType = .autres
}
