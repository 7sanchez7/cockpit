import Foundation

/// Coût IA en euros : le texte d'après les tokens (la formule `textCostEUR` de Roleo), la voix d'après les caractères.
/// Voir docs/sources/couts.md avant de changer un prix.
enum CoutIA {
    /// Claude Haiku 5.5, dollars par million de tokens.
    static let entreeUSD = 0.10
    static let sortieUSD = 0.50
    /// Part d'entrée non cachée dans les tokens facturables, le reste est de la sortie (mélange observé par Roleo).
    static let partEntree = 0.8

    /// Dollars par million de caractères, par moteur de `aiLoad.m.<minute>.v` (`TTSProvider` de Roleo).
    static let voixUSD = [
        "voxtral3": 13.0, // Voxtral 3, Mistral
        "kokoro": 1.485, // Kokoro, facture DeepInfra
        "voxtral": 16.0, // Voxtral mini
        "gemini": 20.0, // Gemini Flash TTS
    ]

    static func euros(tokens: Double) -> Double {
        guard tokens > 0 else { return 0 }
        return tokens * (partEntree * entreeUSD + (1 - partEntree) * sortieUSD) / 1_000_000 * Metrique.eurParUSD
    }

    static func euros(caracteres: Double, usdParMillion: Double) -> Double {
        caracteres * usdParMillion / 1_000_000 * Metrique.eurParUSD
    }

    /// Le coût de caractères par moteur ; un moteur sans prix lève `.format` plutôt que de compter 0.
    static func euros(voix: [String: Int]) throws -> Double {
        try voix.reduce(0) { total, e in
            guard let prix = voixUSD[e.key] else { throw SourceErreur.format("moteur de voix sans prix : \(e.key)") }
            return total + euros(caracteres: Double(e.value), usdParMillion: prix)
        }
    }
}
