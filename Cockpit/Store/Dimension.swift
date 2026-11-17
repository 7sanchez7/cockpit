import Foundation

/// Le catalogue fermé des dimensions d'un install (colonne `valeurs` de la table `install`, docs/donnees.md) :
/// une valeur par dimension, plusieurs pour les intérêts et les blocages, aucune s'il n'a pas répondu.
enum Dimension: String, CaseIterable {
    /// Le rang de l'écran du tunnel le plus loin atteint, 0 à 17 (`PostHog.ecrans`).
    case loin
    case langue, maternelle, source, age, motivation, blocage, interet, niveau, tuteur, notifs, compte, pays, version, build, produit
    /// La zone du pays, déduite au décodage.
    case zone

    /// Les dimensions lues dans PostHog, dans l'ordre des colonnes de la requête.
    static let lues = allCases.filter { $0 != .zone }

    /// La valeur des installs d'avant `mesureeDepuis` : la question n'était pas posée, ou pas enregistrée.
    static let pasMesure = "?"

    var nom: String {
        switch self {
        case .loin: "Écran atteint"
        case .langue: "Langue apprise"
        case .maternelle: "Langue maternelle"
        case .source: "Connu par"
        case .age: "Âge"
        case .motivation: "Motivation"
        case .blocage: "Ce qui bloque"
        case .interet: "Centres d'intérêt"
        case .niveau: "Niveau de départ"
        case .tuteur: "Tuteur choisi"
        case .notifs: "Notifications"
        case .compte: "Compte lié"
        case .pays: "Pays"
        case .version: "Version de l'app"
        case .build: "Build"
        case .produit: "Offre prise"
        case .zone: "Zone"
        }
    }

    /// Le premier jour où au moins 90 % des installs arrivés à l'écran y ont une réponse ; nil si elle l'a toujours été.
    var mesureeDepuis: String? {
        switch self {
        case .tuteur: "2026-09-02"
        case .motivation: "2026-09-16"
        case .interet, .maternelle, .niveau: "2026-10-13"
        case .age: "2026-10-24"
        case .notifs: "2026-11-09"
        default: nil
        }
    }

    /// Les régions d'outre-mer françaises, une zone à part plutôt que leur continent.
    private static let outreMer: Set = ["RE", "YT", "GP", "MQ", "GF", "PF", "NC", "PM", "BL", "MF", "WF"]

    /// La zone d'un code pays ISO, nil s'il n'est pas reconnu.
    static func zone(de pays: String) -> String? {
        if outreMer.contains(pays) { return "outre_mer" }
        let r = Locale.Region(pays)
        switch r.continent?.identifier {
        case "002": return "afrique"
        case "150": return "europe"
        case "142": return "asie"
        case "009": return "oceanie"
        case "019": return r.containingRegion?.identifier == "021" ? "amerique_nord" : "amerique_latine"
        default: return nil
        }
    }
}
