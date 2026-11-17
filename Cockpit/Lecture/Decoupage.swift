import Foundation

/// Les valeurs brutes des réponses du tunnel Roleo, dites en français ; une valeur inconnue s'affiche telle quelle.
extension Dimension {
    func libelle(_ valeur: String) -> String {
        if valeur == Self.pasMesure { return "Pas mesuré (avant le \(Format.jourCourt(cle: mesureeDepuis ?? "")))" }
        if valeur.isEmpty { return Self.vides[self] ?? "Sans réponse" }
        switch self {
        case .langue, .maternelle: return Format.locale.localizedString(forLanguageCode: valeur).map(majuscule) ?? valeur
        case .pays: return Format.locale.localizedString(forRegionCode: valeur) ?? valeur
        case .loin:
            let rang = Int(valeur) ?? 0
            return PostHog.ecrans.indices.contains(rang - 1) ? PostHog.ecrans[rang - 1].nom : "Aucun écran"
        case .niveau: return valeur.uppercased()
        case .tuteur: return majuscule(valeur)
        case .age: return valeur.hasSuffix("_plus") ? "\(valeur.dropLast(5)) ans et plus" : valeur.replacingOccurrences(of: "_", with: "-") + " ans"
        default: return Self.libelles[valeur] ?? majuscule(valeur.replacingOccurrences(of: "_", with: " "))
        }
    }

    private func majuscule(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    /// Ce que veut dire l'absence de valeur, quand ce n'est pas une question sautée.
    private static let vides: [Dimension: String] = [
        .compte: "Pas lié", .produit: "Ni essai ni achat", .pays: "Inconnu", .zone: "Inconnue",
    ]

    private static let libelles = [
        // source
        "tiktok": "TikTok", "instagram": "Instagram", "youtube": "YouTube", "facebook": "Facebook", "app_store": "App Store",
        "friends": "Amis", "chatgpt": "ChatGPT", "google": "Google", "other": "Autre",
        // motivation
        "mix": "Un peu de tout", "living_there": "Vivre là-bas", "studies": "Études", "personal_growth": "Pour soi",
        "travel": "Voyager", "work": "Travail",
        // blocage
        "understand_but_stuck": "Comprend mais bloque", "words_not_sentences": "Des mots, pas des phrases",
        "too_fast": "Ça va trop vite", "afraid_of_mistakes": "Peur de se tromper", "none": "Rien", "accent": "L'accent",
        // intérêts
        "sports": "Sport", "trips": "Voyages", "music": "Musique", "social": "Réseaux sociaux", "series": "Séries",
        "nightlife": "Sorties", "food": "Cuisine", "relationships": "Relations", "dating": "Rencontres", "fashion": "Mode",
        "beauty": "Beauté", "animals": "Animaux", "cars": "Voitures", "books": "Livres", "history": "Histoire",
        "games": "Jeux vidéo", "dance": "Danse", "parenting": "Parentalité", "hiking": "Randonnée", "ai": "IA",
        "popculture": "Pop culture", "cycling": "Vélo", "art": "Art", "photo": "Photo", "anime": "Animés", "films": "Films",
        "tech": "Tech", "fitness": "Fitness", "podcasts": "Podcasts", "business": "Business", "finance": "Finance",
        "startup": "Startups", "shopping": "Shopping",
        // motivation, suite
        "culture": "Culture", "loved_one": "Un proche",
        // notifications, compte, offre
        "granted": "Acceptées", "denied": "Refusées", "apple": "Apple", "Yearly": "Annuel", "monthly": "Mensuel",
        // zone
        "europe": "Europe", "afrique": "Afrique", "amerique_nord": "Amérique du Nord",
        "amerique_latine": "Amérique latine et Caraïbes", "asie": "Asie et Moyen-Orient", "oceanie": "Océanie",
        "outre_mer": "Outre-mer français",
    ]
}

extension LignePorte {
    /// La fin du tunnel, une porte de l'app, ou rien pour les versions qui ne la disaient pas.
    var nom: String {
        switch porte {
        case "onboarding": "fin du tunnel"
        case "": "sans porte (anciennes versions)"
        default: PostHog.nomsPortes[porte] ?? porte
        }
    }
}

extension Dimension {
    /// Un install y donne plusieurs réponses : ses valeurs se recoupent.
    var multiple: Bool { self == .interet || self == .blocage }
}

extension Filtre {
    /// Le pas tel qu'il s'affiche dans le chemin de l'arbre.
    var libelle: String {
        switch self {
        case .valeur(let d, let v): "\(d.nom) : \(d.libelle(v))"
        case .sauf(let d, let v): "\(d.nom) : sauf \(d.libelle(v))"
        case .ecran(let rang): "A passé : \(PostHog.ecrans[rang - 1].nom)"
        case .paywall: "A vu le paywall"
        case .essai: "A pris l'essai"
        case .payant: "Payant"
        }
    }
}
