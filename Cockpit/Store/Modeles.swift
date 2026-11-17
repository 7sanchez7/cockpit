import Foundation

/// Une ligne du fil « En direct ». `id` commence par l'id de la source (`posthog:essai:<uuid>`).
struct Evenement: Hashable {
    var id: String
    var business: String
    var at: Date
    var type: TypeFil
    var texte: String
    var lien: String?
}

enum TypeFil: String, CaseIterable {
    case essai = "ESSAI", achat = "ACHAT", avis = "AVIS", msg = "MSG", retour = "RETOUR"
    case video = "VIDEO", rang = "RANG", ia = "IA", version = "VERSION"

    var libelle: String {
        switch self {
        case .essai: "Essai"
        case .achat: "Achat"
        case .avis: "Avis"
        case .msg: "Message"
        case .retour: "Retour"
        case .video: "Vidéo"
        case .rang: "Classement"
        case .ia: "IA"
        case .version: "Version"
        }
    }
}

/// Une plateforme vidéo suivie.
enum Plateforme: String, CaseIterable, Identifiable, Decodable {
    case tiktok, instagram, youtube, facebook

    var id: String { rawValue }

    var nom: String {
        switch self {
        case .tiktok: "TikTok"
        case .instagram: "Instagram"
        case .youtube: "YouTube"
        case .facebook: "Facebook"
        }
    }

    /// Le profil public d'un compte.
    func profil(_ handle: String) -> String {
        switch self {
        case .tiktok: "https://www.tiktok.com/@\(handle)"
        case .instagram: "https://www.instagram.com/\(handle)/"
        case .youtube: "https://www.youtube.com/@\(handle)"
        case .facebook: "https://www.facebook.com/\(handle)"
        }
    }

    /// Le lien public d'une vidéo.
    func lien(_ brut: String, compte: String) -> String {
        switch self {
        case .tiktok: "https://www.tiktok.com/@\(compte)/video/\(brut)"
        case .instagram: "https://www.instagram.com/reel/\(brut)/"
        case .youtube: "https://www.youtube.com/shorts/\(brut)"
        case .facebook: "https://www.facebook.com/\(brut)"
        }
    }

    /// L'id d'une vidéo dans la table `video` : brut pour TikTok (les liens des fiches s'en servent), préfixé sinon.
    func idVideo(_ brut: String) -> String { self == .tiktok ? brut : "\(rawValue):\(brut)" }
}

/// Un compte suivi sur une plateforme, ajouté dans l'écran Vidéos ou par un agent (docs/runbook.md).
struct Compte: Hashable, Identifiable {
    var business: String
    var plateforme: Plateforme
    /// Sans `@`, en minuscules : `holaestony`.
    var handle: String
    /// En pause, le compte n'est plus collecté mais reste affiché.
    var actif = true

    var id: String { Self.id(plateforme, handle) }

    static func id(_ p: Plateforme, _ handle: String) -> String { "\(p.rawValue):\(handle)" }

    /// `@Hola.EsTony` ou un lien de profil → `hola.estony` ; nil si ce n'est pas un nom de compte.
    static func handle(_ saisie: String) -> String? {
        var h = saisie.trimmingCharacters(in: .whitespaces)
        if let m = h.firstMatch(of: /(?:tiktok|instagram|youtube|facebook)\.com\/@?([A-Za-z0-9._-]+)/) { h = String(m.1) }
        h = h.replacingOccurrences(of: "@", with: "").lowercased()
        return h.wholeMatch(of: /[a-z0-9._-]{1,64}/) != nil ? h : nil
    }
}

extension Compte: Decodable {
    /// Dans la graine, `actif` vaut vrai par défaut et le handle se normalise comme une saisie (`@MonApp` → `monapp`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Cles.self)
        business = try c.decode(String.self, forKey: .business)
        plateforme = try c.decode(Plateforme.self, forKey: .plateforme)
        let saisie = try c.decode(String.self, forKey: .handle)
        guard let h = Compte.handle(saisie) else {
            throw DecodingError.dataCorruptedError(forKey: .handle, in: c, debugDescription: "« \(saisie) » n'est pas un nom de compte")
        }
        handle = h
        actif = try c.decodeIfPresent(Bool.self, forKey: .actif) ?? true
    }

    private enum Cles: String, CodingKey { case business, plateforme, handle, actif }
}

/// Un relevé des compteurs d'un compte.
struct ReleveCompte: Hashable {
    var compte: String
    var at: Date
    var abonnes: Int?
    var videos: Int?
    var likes: Int?
}

/// Une vidéo vue par sa plateforme.
struct Video: Hashable {
    var id: String
    var business: String
    var compte: String
    var legende: String?
    var publieeLe: Date?
    var dureeS: Double?
    var url: String?
    var plateforme: Plateforme = .tiktok
}

/// Ce que la fiche `contenu/bank` dit d'une vidéo.
struct FicheVideo: Hashable {
    var id: String
    var business: String
    var compte: String
    var url: String
    var titre: String
    var format: String?
    var fiche: String
    var verdict: Bool
}

struct Releve: Hashable {
    var video: String
    var at: Date
    var vues: Int
    var likes: Int?
    var commentaires: Int?
    var partages: Int?
    var enregistrements: Int?
    var watchMoyenS: Double?
    var completion: Double?
    var abonnes: Int?
}

/// Ce que seul le propriétaire voit d'une vidéo, au dernier passage : rétention, sources, public.
struct Analyse: Codable, Equatable {
    var watchTotalS: Double?
    var spectateurs: Int?
    /// Part des spectateurs qui n'avaient jamais vu le compte.
    var nouveaux: Double?
    /// Part des vues venues d'abonnés.
    var abonnesPart: Double?
    /// Part des spectateurs encore là, une valeur par seconde de la vidéo.
    var retention: [Double] = []
    var sources: [Part] = []
    var recherches: [Part] = []
    var ages: [Part] = []
    var pays: [Part] = []
    /// Facebook : vues de 3 s, d'une minute et ThruPlay, en part des vues.
    var jalons: [Part] = []
    /// Vues de chacun des 7 premiers jours, depuis la publication (TikTok).
    var vuesParJour: [Int] = []

    struct Part: Codable, Equatable, Hashable {
        var nom: String
        var part: Double
    }

    var estVide: Bool { self == Analyse() }
}

/// Une app de l'App Store : à nous si `business` est rempli, sinon à un pote.
struct Appli: Hashable, Identifiable {
    var id: String
    var nom: String
    var editeur: String?
    var icone: String?
    var genre: Int?
    var note: Double?
    var nbNotes: Int?
    var version: String?
    var business: String?
}

enum Liste: String, CaseIterable {
    case gratuit, payant, recettes
}

struct Avis: Hashable {
    var id: String
    var business: String
    var pays: String?
    var note: Int
    var titre: String?
    var texte: String?
    var auteur: String?
    var at: Date
    var repondu: Bool
}

/// Une tâche posée par une source. `cle` est unique dans la source (`avis:<id>`).
struct Tache: Hashable {
    var cle: String
    var texte: String
    var etiquette: String?
    var ton: Ton = .neutre
    var echeance: String?
    var lien: String?

    enum Ton: String { case alerte, neutre }
}

/// Un fil du SAV : la conversation d'un user avec l'équipe, résumée comme sur `users/{uid}` dans Firestore.
struct FilSAV: Identifiable, Hashable {
    var business: String
    var uid: String
    var nom: String?
    /// Vide quand le compte n'a pas d'email (invité) ; nil tant qu'il n'est pas lu.
    var email: String?
    var dernierAt: Date
    var dernierEquipe: Bool
    var apercu: String
    /// Le dernier message vient de l'user et l'équipe n'a pas répondu ni marqué traité.
    var ouvert: Bool
    /// La dernière réponse de l'équipe n'est pas encore lue dans l'app.
    var nonVu: Bool

    var id: String { cle.id }
    var cle: CleFil { CleFil(business: business, uid: uid) }
    var etat: EtatFil { ouvert ? .aRepondre : nonVu ? .pasLu : dernierEquipe ? .lu : .traite }
}

/// Le fil d'un user d'un business.
struct CleFil: Hashable {
    var business: String
    var uid: String

    var id: String { "\(business):\(uid)" }
}

/// L'état d'un fil, celui du dashboard de Roleo.
enum EtatFil { case aRepondre, pasLu, lu, traite }

/// Un message d'un fil du SAV.
struct MessageSAV: Identifiable, Hashable {
    var id: String
    var equipe: Bool
    var texte: String
    var at: Date
}

/// Un retour de `feedback/{id}` : idée ou souci du profil, « pas vraiment » d'après bilan, signalement sous une bulle.
struct RetourSAV: Identifiable, Hashable {
    var business: String
    var id: String
    var uid: String?
    var email: String?
    /// `profile`, `rating`, `chat_report` ; nil pour un retour d'avant le 9 oct. 2026.
    var source: String?
    var categorie: String?
    var etoiles: Int?
    var message: String
    var citation: String?
    var conversation: String?
    var traite: Bool
    var traiteLe: Date?
    var plateforme: String?
    var build: String?
    var at: Date
}

/// Ce qu'un passage de Firebase lit pour le SAV d'un business.
struct ReleveSAV {
    /// Les fils ouverts et les plus récents ; un fil ouvert en base qui n'y est plus a été traité ailleurs.
    var fils: [FilSAV] = []
    /// Les retours nouveaux et les plus récents ; même règle.
    var retours: [RetourSAV] = []
    /// Les messages des fils relus, par uid, du plus ancien au plus récent.
    var messages: [String: [MessageSAV]] = [:]
    /// Les emails des comptes pas encore connus, par uid ; vide pour un compte sans email.
    var emails: [String: String] = [:]
}

/// Une ligne de la table `plan` : une ligne de la note « Cockpit » de Notes, sous son intertitre.
struct LignePlan: Hashable {
    var section: String
    var texte: String
    /// Une case à cocher ; sinon une puce ou du texte.
    var coche = false
    var fait = false
}

/// Une ligne de la table `install` : un install, ce qu'il a fait, l'id RevenueCat s'il a converti, et ses réponses.
struct Install: Hashable {
    var jour: String
    /// Le rang de l'écran du tunnel le plus loin atteint, 0 à 17.
    var loin = 0
    var paywall = false
    var essai = false
    /// Achat sans essai gratuit.
    var direct = false
    var rond = false
    /// Rond fini entre N et N+1 jours après l'install.
    var j1 = false
    var j7 = false
    var j14 = false
    var j30 = false
    var client: String?
    /// Une dimension sans réponse est absente.
    var valeurs: [Dimension: [String]] = [:]
}

/// Ce que RevenueCat dit d'un client qui a converti : il a payé, son essai court encore, il n'a pas payé,
/// ou RevenueCat ne le connaît pas en production.
enum EtatPaiement: String {
    case paye, essai, non, inconnu
}

/// Une ligne de la table `porte` : les paywalls vus, essais gratuits et achats sans essai d'un jour par porte du paywall.
struct Porte: Hashable {
    var jour: String
    var porte: String
    var vues: Int
    var essais: Int
    var directs: Int
}

/// Les installs d'un jour et leur retour : un Jn reste nul tant que la cohorte n'a pas eu tout son temps.
struct Cohorte: Hashable {
    var jour: String
    var installs: Int
    var j1: Int?
    var j7: Int?
    var j14: Int?
    var j30: Int?
}

/// Un passage d'une source, une ligne de la table `collecte`.
struct Passage: Hashable {
    var source: String
    var debut: Date
    var fin: Date
    var etat: Etat
    var erreur: String?
    var lignes: Int

    enum Etat: String { case ok, erreur, nonConfigure = "non_configure" }
}
