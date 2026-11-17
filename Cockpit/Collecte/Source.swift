import Foundation

/// Un service interrogé à sa cadence. Une source lit, n'écrit que par `Store`, ne modifie rien chez le service ;
/// seule exception, les actions de l'écran SAV (`Firebase+SAV`), qui écrivent dans Firestore et envoient la notif.
/// Le contrat complet est dans docs/collecte.md, chaque source a sa fiche dans docs/sources/.
protocol Source {
    /// Clé de la source dans la table `collecte` et préfixe de ses lignes du fil (`posthog`).
    var id: String { get }
    /// Nom affiché (`PostHog`).
    var nom: String { get }
    /// Intervalle entre deux passages réussis, en secondes.
    var cadence: TimeInterval { get }
    /// Délai avant de retenter après un échec ; 10 minutes par défaut (`Collecteur.repriseApresEchec`).
    var reprise: TimeInterval { get }
    /// Lit la source pour chaque business qui l'utilise et rend le nombre de lignes écrites.
    /// Lève `SourceErreur.nonConfigure` si aucun business n'est configuré pour elle.
    func collecte(_ ctx: Contexte) async throws -> Int
}

extension Source {
    var reprise: TimeInterval { Collecteur.repriseApresEchec }
}

/// Ce qu'une source reçoit pour travailler.
struct Contexte {
    let store: Store
    let secrets: Secrets
    let http: HTTP
    let gcloud: GCloud
    let businesses: [Business]
}

enum SourceErreur: LocalizedError {
    /// Clé absente, business sans config pour cette source : gris dans la barre du haut, pas une panne.
    case nonConfigure(String)
    case http(Int, String)
    case format(String)
    case commande(String)

    var errorDescription: String? {
        switch self {
        case .nonConfigure(let m): "Non configuré : \(m)"
        case .http(let code, let extrait): "HTTP \(code) : \(extrait)"
        case .format(let m): "Réponse inattendue : \(m)"
        case .commande(let m): m
        }
    }
}
