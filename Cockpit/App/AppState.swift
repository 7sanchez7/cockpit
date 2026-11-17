import Foundation
import Observation
import os

/// Les écrans de la barre du haut, dans l'ordre, avec leur raccourci ⌘1 à ⌘6.
enum Ecran: String, CaseIterable, Identifiable {
    case app, data, videos, sante, aTraiter, apps

    var id: String { rawValue }

    var titre: String {
        switch self {
        case .app: "Accueil"
        case .data: "Data"
        case .videos: "Vidéos"
        case .sante: "Santé"
        case .aTraiter: "SAV"
        case .apps: "Apps de potes"
        }
    }

    var icone: String {
        switch self {
        case .app: "square.grid.2x2"
        case .data: "chart.pie"
        case .videos: "play.rectangle"
        case .sante: "waveform.path.ecg"
        case .aTraiter: "bubble.left.and.bubble.right"
        case .apps: "chart.bar"
        }
    }

    /// La place dans la barre du haut, de 0 à 5.
    var rang: Int { Ecran.allCases.firstIndex(of: self) ?? 0 }
    var raccourci: Character { Character(String(rang + 1)) }
}

/// L'état de la fenêtre : écran affiché, business sélectionné, palette ouverte. Le choix d'écran et de business
/// survit au relancement (réglages `ecran` et `business`).
@Observable
final class AppState {
    let store: Store
    let collecteur: Collecteur
    var ecran: Ecran = .app {
        didSet {
            garder("ecran", ecran.rawValue)
            avance = ecran.rang >= oldValue.rang
        }
    }
    /// Vrai si le dernier écran choisi est plus à droite dans la barre : le nouveau arrive de la droite.
    private(set) var avance = true
    /// Le business du segmenté ; nil = tous.
    var selection: String? { didSet { garder("business", selection) } }
    /// Le store affiché sur l'Accueil et Data ; nil = les deux.
    var boutique: Boutique? { didSet { garder("boutique", boutique?.rawValue) } }
    var palette = false
    /// Les panneaux Réseaux et Plan de l'Accueil, ouverts ou repliés (réglages `accueil.reseau` et `accueil.plan`).
    var reseauOuvert = true { didSet { garder("accueil.reseau", reseauOuvert ? nil : "0") } }
    var planOuvert = true { didSet { garder("accueil.plan", planOuvert ? nil : "0") } }
    /// La période de l'Accueil, remise à aujourd'hui à chaque lancement.
    var periode: Periode = .jour
    /// Le build choisi dans Data, dont les installs remplacent la période ; nil : la période.
    var build: String?
    /// Le chemin ouvert dans l'arbre des installs de l'écran Data.
    var chemin: [Filtre] = []
    /// La dimension qui découpe le nœud ouvert de l'arbre.
    var decoupe: Dimension = .age
    /// La vidéo ouverte dans l'écran Vidéos.
    var videoChoisie: String?
    /// Le fil ouvert dans l'écran SAV.
    var filChoisi: CleFil?
    /// Rafraîchi toutes les 30 s pour que « il y a 3 min » et l'heure courante avancent.
    private(set) var maintenant = Date.now
    @ObservationIgnored private var horloge: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.tonysanchez.cockpit", category: "app")
    @ObservationIgnored private let widget = PontWidget()

    init(store: Store, collecteur: Collecteur) {
        self.store = store
        self.collecteur = collecteur
        ecran = (try? store.reglage("ecran")).flatMap { Ecran(rawValue: $0) } ?? .app
        selection = try? store.reglage("business")
        boutique = (try? store.reglage("boutique")).flatMap { Boutique(rawValue: $0) }
        reseauOuvert = (try? store.reglage("accueil.reseau")) != "0"
        planOuvert = (try? store.reglage("accueil.plan")) != "0"
        horloge = Task { [weak self] in
            while !Task.isCancelled {
                self?.publierWidget()
                try? await Task.sleep(for: .seconds(30))
                self?.maintenant = .now
            }
        }
    }

    /// Ouvre la base et démarre la collecte ; une base ou une graine illisible arrête l'app avec son erreur.
    static func lancer() -> AppState {
        do {
            let store = try Store.ouvrir()
            let collecteur = Collecteur(store: store, sources: Registre.sources)
            collecteur.demarrer()
            Notifs.autoriser()
            return AppState(store: store, collecteur: collecteur)
        } catch {
            fatalError("Cockpit ne démarre pas : \(error.localizedDescription)")
        }
    }

    /// Le widget du bureau montre toujours tous les business, quel que soit celui affiché.
    private func publierWidget() {
        widget.publier(Lectures(db: store.db, businesses: tousLesBusiness, maintenant: .now).resumeWidget(), maintenant: .now)
    }

    var tousLesBusiness: [Business] {
        _ = store.version
        do {
            return try store.businesses()
        } catch {
            log.error("businesses : \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Les business affichés : tous, ou celui du segmenté.
    var affiches: [Business] {
        let tous = tousLesBusiness
        guard let selection, let b = tous.first(where: { $0.id == selection }) else { return tous }
        return [b]
    }

    var lectures: Lectures {
        _ = store.version
        return Lectures(db: store.db, businesses: affiches, maintenant: maintenant, boutique: boutique)
    }

    /// Lance une écriture du store, journalise l'erreur et redessine.
    func ecrire(_ f: (Store) throws -> Void) {
        do {
            try f(store)
        } catch {
            log.error("écriture : \(error.localizedDescription, privacy: .public)")
        }
        store.aChange()
    }

    // MARK: SAV, les seules écritures chez un service (docs/ecrans.md § SAV)

    /// Envoie la réponse et rend ce que l'écran affiche sous le champ.
    func repondre(_ texte: String, a cle: CleFil) async throws -> String {
        defer { store.aChange() }
        return try await Firebase.repondre(texte, a: cle, try collecteur.contexte())
    }

    func fermer(_ cle: CleFil) async throws {
        defer { store.aChange() }
        try await Firebase.fermer(cle, try collecteur.contexte())
    }

    func traiter(_ r: RetourSAV, _ traite: Bool) async throws {
        defer { store.aChange() }
        try await Firebase.traiter(r, traite: traite, try collecteur.contexte())
    }

    var enPause: Bool {
        get { reglage(Collecteur.reglagePause) == "1" }
        set { ecrire { try $0.regler(Collecteur.reglagePause, newValue ? "1" : nil) } }
    }

    func reglage(_ cle: String) -> String? {
        _ = store.version
        return try? store.reglage(cle)
    }

    private func garder(_ cle: String, _ valeur: String?) {
        do {
            try store.regler(cle, valeur)
        } catch {
            log.error("réglage \(cle, privacy: .public) : \(error.localizedDescription, privacy: .public)")
        }
    }
}
