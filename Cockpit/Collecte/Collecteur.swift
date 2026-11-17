import Foundation
import Observation
import os

/// Lance chaque source à sa cadence, écrit chaque passage dans la table `collecte`, notifie les nouveautés.
/// Les règles (échéance, reprise après échec, notifications) sont dans docs/collecte.md.
@Observable
final class Collecteur {
    /// Ids des sources en train de tourner, pour les indicateurs de la barre du haut.
    private(set) var enCours: Set<String> = []
    @ObservationIgnored let sources: [any Source]
    @ObservationIgnored let secrets: Secrets
    @ObservationIgnored private let store: Store
    @ObservationIgnored private let http = HTTP()
    @ObservationIgnored private let gcloud: GCloud
    @ObservationIgnored private var boucle: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.tonysanchez.cockpit", category: "collecte")

    /// Une source en erreur ou non configurée (session expirée, clé absente) est retentée au plus tard 10 minutes après :
    /// elle repasse au vert dès que la session revient, sans attendre sa cadence.
    static let repriseApresEchec: TimeInterval = 600
    /// Une nouveauté plus vieille que ça ne notifie pas (retour de veille, rattrapage).
    static let fraicheurNotif: TimeInterval = 2 * 3600
    /// Réglage qui met la collecte en pause quand il vaut « 1 ».
    static let reglagePause = "collecte.pause"

    init(store: Store, sources: [any Source]) {
        self.store = store
        self.sources = sources
        gcloud = GCloud(http: http)
        secrets = Secrets(gcloud: gcloud, http: http)
    }

    func demarrer() {
        guard boucle == nil else { return }
        boucle = Task {
            while !Task.isCancelled {
                tour()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Lance les sources arrivées à échéance, sauf si la collecte est en pause.
    func tour() {
        guard (try? store.reglage(Self.reglagePause)) != "1" else { return }
        for s in sources where aEcheance(s) {
            Task { await lancer(s) }
        }
    }

    /// Relance tout de suite une source, ou toutes (⌘R, bouton de Santé).
    func relancer(_ id: String? = nil) {
        for s in sources where id == nil || s.id == id {
            Task { await lancer(s) }
        }
    }

    /// Ce qu'une source ou une action du SAV reçoit pour travailler.
    func contexte() throws -> Contexte {
        Contexte(store: store, secrets: secrets, http: http, gcloud: gcloud, businesses: try store.businesses())
    }

    private func aEcheance(_ s: any Source) -> Bool {
        guard let dernier = try? store.dernierPassage(s.id) else { return true }
        let delai = dernier.etat == .ok ? s.cadence : min(s.cadence, s.reprise)
        return dernier.debut.addingTimeInterval(delai) <= .now
    }

    func lancer(_ s: any Source) async {
        guard !enCours.contains(s.id) else { return }
        enCours.insert(s.id)
        defer {
            enCours.remove(s.id)
            store.aChange()
        }
        let premier = (try? store.dernierSucces(s.id)) == nil
        let avant = try? store.dernierPassage(s.id)
        var p = Passage(source: s.id, debut: .now, fin: .now, etat: .ok, erreur: nil, lignes: 0)
        do {
            p.lignes = try await s.collecte(try contexte())
        } catch SourceErreur.nonConfigure(let m) {
            p.etat = .nonConfigure
            p.erreur = m
        } catch {
            p.etat = .erreur
            p.erreur = error.localizedDescription
        }
        p.fin = .now
        do {
            try store.journal(p)
        } catch {
            log.error("journal de \(s.id, privacy: .public) : \(error.localizedDescription, privacy: .public)")
        }
        if p.etat == .ok {
            log.info("\(s.id, privacy: .public) : \(p.lignes) lignes en \(p.fin.timeIntervalSince(p.debut), format: .fixed(precision: 1)) s")
        } else {
            log.error("\(s.id, privacy: .public) : \(p.erreur ?? "", privacy: .public)")
        }

        let nouveaux = store.prendreNouveaux(source: s.id)
        if !premier { notifier(nouveaux) }
        if p.etat == .erreur, avant?.etat == .ok {
            Notifs.envoyer(titre: "Cockpit · \(s.nom) en panne", corps: p.erreur ?? "", id: "panne:\(s.id):\(p.debut.iso)")
        }
    }

    /// Une notification par nouveauté récente dont le type est activé dans Réglages ; au-delà de 3, un résumé.
    private func notifier(_ evenements: [Evenement]) {
        let noms = Dictionary(((try? store.businesses()) ?? []).map { ($0.id, $0.nom) }, uniquingKeysWith: { a, _ in a })
        let aEnvoyer = evenements.filter {
            $0.at > .now.addingTimeInterval(-Self.fraicheurNotif)
                && (try? store.reglage($0.type.reglageNotif)) != "0"
        }
        for e in aEnvoyer.prefix(3) {
            Notifs.envoyer(titre: "\(noms[e.business] ?? e.business) · \(e.type.libelle)", corps: e.texte, id: e.id)
        }
        if aEnvoyer.count > 3 {
            Notifs.envoyer(titre: "Cockpit", corps: "\(aEnvoyer.count - 3) autres nouveautés", id: "resume:\(Date.now.iso)")
        }
    }
}

extension TypeFil {
    /// Réglage qui coupe les notifications de ce type quand il vaut « 0 ».
    var reglageNotif: String { "notifs.\(rawValue.lowercased())" }
}
