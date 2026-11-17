import Foundation
import Security

/// Ce qu'affiche le widget du bureau, déjà mis en forme : l'app l'écrit dans le conteneur partagé, le widget le lit.
/// Compilé dans les deux cibles, il ne dépend de rien d'autre.
nonisolated struct ResumeWidget: Codable, Hashable, Sendable {
    /// Le groupe d'apps du cockpit et de son widget, lu dans les entitlements signés : il est préfixé par l'équipe
    /// de signature de chaque Mac (Local.xcconfig).
    static let groupe: String? = {
        guard let tache = SecTaskCreateFromSelf(nil),
              let groupes = SecTaskCopyValueForEntitlement(tache, "com.apple.security.application-groups" as CFString, nil) as? [String]
        else { return nil }
        return groupes.first
    }()
    static var url: URL? {
        guard let groupe else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupe)?.appending(path: "widget.json")
    }

    struct Kpi: Codable, Hashable, Sendable {
        let libelle: String
        let valeur: String
        let delta: String?
        /// L'écart signé qui donne sa couleur au delta et à la courbe.
        let ecart: Double?
        let note: String?
        /// Les 14 derniers jours.
        let serie: [Double?]
    }

    /// L'heure de la dernière collecte, précédée du jour si ce n'est pas aujourd'hui.
    let maj: String?
    /// Le revenu brut du jour en euros, `hier 31 €`, `3 essais, 1 achat`.
    let revenu: String
    let hier: String
    let detail: String
    /// Le revenu brut cumulé sur `jours` jours, en euros.
    let cumul: [Double]
    let jours: Int
    let kpis: [Kpi]
    let aTraiter: Int
}
