import Foundation

/// Un business suivi, créé par la graine ou dans les réglages. Sa config dit où chaque source le trouve ; un champ vide coupe la source pour lui.
/// Ses comptes vidéo sont dans la table `compte`.
struct Business: Identifiable, Hashable {
    var id: String
    var nom: String
    var lettre: String
    /// Jeton de couleur de `Theme.teinte` : menthe (aqua), ciel (bleu), lilas (violet), ambre (orange).
    var teinte: String
    var config: Config

    struct Config: Codable, Hashable {
        var appStoreId: String?
        /// Issuer de la clé API App Store Connect (pas un secret, la clé `.p8` l'est).
        var ascIssuer: String?
        /// Numéro de fournisseur App Store Connect (Ventes et tendances), pour les rapports de ventes ; pas un secret.
        var ascVendor: String?
        /// Paquet Android et bucket des rapports groupés de la Play Console (`pubsite_prod_rev_…`, sans `gs://`).
        var playPackage: String?
        var playBucket: String?
        var firebaseProject: String?
        var posthogHost: String?
        var contenuDir: String?
        /// Storefronts suivis, codes ISO à 2 lettres ; le premier sert pour la note.
        var pays: [String] = []
        /// Catégorie App Store, 6017 = Éducation.
        var genre: Int = 6017
        var objectifMensuelEUR: Double = 10_000
        var evenements = Evenements()
    }

    /// Les événements PostHog que lisent les requêtes ; par défaut ceux de Roleo.
    struct Evenements: Codable, Hashable {
        /// Le premier de chaque personne date son install.
        var installation = "onboarding_started"
        /// Un écran du tunnel passé, l'écran dans `properties.step`.
        var etape = "onboarding_step_completed"
        var paywall = "paywall_viewed"
        var essai = "trial_started"
        /// Part aussi au début d'un essai : l'achat direct est un achat sans essai.
        var achat = "purchase_completed"
        /// L'action clé de l'app, celle qui compte les retours (un rond fini chez Roleo).
        var usage = "path_round_done"
    }
}

extension Business: Decodable {
    /// Seuls `id` et `nom` sont obligatoires dans la graine.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Cles.self)
        id = try c.decode(String.self, forKey: .id)
        nom = try c.decode(String.self, forKey: .nom)
        lettre = try c.decodeIfPresent(String.self, forKey: .lettre) ?? String(nom.prefix(1)).uppercased()
        teinte = try c.decodeIfPresent(String.self, forKey: .teinte) ?? "menthe"
        config = try c.decodeIfPresent(Config.self, forKey: .config) ?? Config()
    }

    private enum Cles: String, CodingKey { case id, nom, lettre, teinte, config }
}

/// Les businesses et les comptes de ce Mac, lus dans `graine.json` (docs/collecte.md § Graine).
struct Graine: Decodable {
    var businesses: [Business] = []
    var comptes: [Compte] = []

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Cles.self)
        businesses = try c.decodeIfPresent([Business].self, forKey: .businesses) ?? []
        comptes = try c.decodeIfPresent([Compte].self, forKey: .comptes) ?? []
    }

    private enum Cles: String, CodingKey { case businesses, comptes }
}

extension Business.Config {
    /// Un champ absent du JSON prend sa valeur par défaut.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        appStoreId = try c.decodeIfPresent(String.self, forKey: .appStoreId)
        ascIssuer = try c.decodeIfPresent(String.self, forKey: .ascIssuer)
        ascVendor = try c.decodeIfPresent(String.self, forKey: .ascVendor)
        playPackage = try c.decodeIfPresent(String.self, forKey: .playPackage)
        playBucket = try c.decodeIfPresent(String.self, forKey: .playBucket)
        firebaseProject = try c.decodeIfPresent(String.self, forKey: .firebaseProject)
        posthogHost = try c.decodeIfPresent(String.self, forKey: .posthogHost)
        contenuDir = try c.decodeIfPresent(String.self, forKey: .contenuDir)
        pays = try c.decodeIfPresent([String].self, forKey: .pays) ?? pays
        genre = try c.decodeIfPresent(Int.self, forKey: .genre) ?? genre
        objectifMensuelEUR = try c.decodeIfPresent(Double.self, forKey: .objectifMensuelEUR) ?? objectifMensuelEUR
        evenements = try c.decodeIfPresent(Business.Evenements.self, forKey: .evenements) ?? evenements
    }
}

extension Business.Evenements {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        installation = try c.decodeIfPresent(String.self, forKey: .installation) ?? installation
        etape = try c.decodeIfPresent(String.self, forKey: .etape) ?? etape
        paywall = try c.decodeIfPresent(String.self, forKey: .paywall) ?? paywall
        essai = try c.decodeIfPresent(String.self, forKey: .essai) ?? essai
        achat = try c.decodeIfPresent(String.self, forKey: .achat) ?? achat
        usage = try c.decodeIfPresent(String.self, forKey: .usage) ?? usage
    }
}
