import Foundation
import Observation

/// La base du cockpit. Les sources écrivent par ces méthodes, les écrans lisent par `Lectures`.
/// Chaque table et chaque métrique est décrite dans docs/donnees.md.
@Observable
final class Store {
    @ObservationIgnored let db: Database
    /// Incrémenté après chaque collecte : les écrans qui le lisent se redessinent.
    private(set) var version = 0
    /// Lignes du fil insérées depuis le dernier `prendreNouveaux`, pour les notifications.
    @ObservationIgnored private var nouveaux: [Evenement] = []

    /// `graine` est appliquée si elle a changé depuis la dernière fois (docs/collecte.md § Graine).
    init(chemin: String, graine: URL? = nil) throws {
        db = try Database(chemin: chemin)
        try db.script(Schema.sql)
        for (table, colonne, definition) in Schema.colonnes where try !db.colonneExiste(table, colonne) {
            try db.execute("alter table \(table) add column \(colonne) \(definition)")
        }
        if let graine { try semer(graine) }
        try db.execute("delete from collecte where debut < ?", [Date.now.addingTimeInterval(-30 * 86_400)])
    }

    /// La base de l'app.
    static let fichier = URL.applicationSupportDirectory.appending(path: "Cockpit/cockpit.sqlite")
    /// Les businesses et comptes de ce Mac, écrits par /installer, hors du dépôt.
    static let graine = URL.applicationSupportDirectory.appending(path: "Cockpit/graine.json")

    static func ouvrir() throws -> Store {
        try FileManager.default.createDirectory(at: fichier.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try Store(chemin: fichier.path, graine: graine)
    }

    /// Écrit les businesses de la graine et ajoute ses comptes absents, une fois par version du fichier : un compte mis
    /// en pause reste en pause, un business supprimé dans les réglages ne revient qu'avec une nouvelle graine.
    private func semer(_ url: URL) throws {
        guard let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { return }
        guard try reglage("graine") != date.iso else { return }
        let g: Graine
        do {
            g = try JSONDecoder().decode(Graine.self, from: Data(contentsOf: url))
        } catch {
            throw SourceErreur.commande("\(url.path) illisible : \(error)")
        }
        let suivis = Set(try comptes().map(\.id))
        try lot {
            for b in g.businesses { try enregistrer(b) }
            for c in g.comptes where !suivis.contains(c.id) { try ajouter(c) }
            try regler("graine", date.iso)
        }
    }

    func aChange() { version += 1 }

    /// Plusieurs écritures en une transaction.
    func lot<T>(_ f: () throws -> T) throws -> T { try db.transaction(f) }

    // MARK: business

    func businesses() throws -> [Business] {
        try db.query("select * from business order by ordre, nom").map { l in
            let config = try JSONDecoder().decode(Business.Config.self, from: Data((l.texte("config") ?? "{}").utf8))
            return Business(id: l.texte("id") ?? "", nom: l.texte("nom") ?? "", lettre: l.texte("lettre") ?? "",
                            teinte: l.texte("teinte") ?? "menthe", config: config)
        }
    }

    func enregistrer(_ b: Business) throws {
        let config = String(decoding: try JSONEncoder().encode(b.config), as: UTF8.self)
        try db.execute("""
            insert into business (id, nom, lettre, teinte, config) values (?, ?, ?, ?, ?)
            on conflict (id) do update set nom = excluded.nom, lettre = excluded.lettre,
                teinte = excluded.teinte, config = excluded.config
            """, [b.id, b.nom, b.lettre, b.teinte, config])
    }

    func supprimerBusiness(_ id: String) throws {
        try db.execute("delete from business where id = ?", [id])
    }

    // MARK: comptes

    func comptes() throws -> [Compte] {
        try db.query("select * from compte order by business, plateforme, ajoute_le").compactMap { l in
            guard let p = Plateforme(rawValue: l.texte("plateforme") ?? ""), let h = l.texte("handle") else { return nil }
            return Compte(business: l.texte("business") ?? "", plateforme: p, handle: h, actif: l.booleen("actif"))
        }
    }

    /// Suit un compte ; un compte déjà là change de business et repart.
    func ajouter(_ c: Compte) throws {
        try db.execute("""
            insert into compte (id, business, plateforme, handle, actif, ajoute_le) values (?, ?, ?, ?, ?, ?)
            on conflict (id) do update set business = excluded.business, actif = excluded.actif
            """, [c.id, c.business, c.plateforme.rawValue, c.handle, c.actif, Date.now])
    }

    func activer(compte id: String, _ actif: Bool) throws {
        try db.execute("update compte set actif = ? where id = ?", [actif, id])
    }

    /// Le compte n'est plus suivi ni affiché ; ses vidéos et relevés restent dans la base.
    func retirer(compte id: String) throws {
        try db.execute("delete from compte where id = ?", [id])
    }

    func releve(_ r: ReleveCompte) throws {
        try db.execute("insert or replace into compte_releve (compte, at, abonnes, videos, likes) values (?, ?, ?, ?, ?)",
                       [r.compte, r.at, r.abonnes, r.videos, r.likes])
    }

    // MARK: séries

    /// Écrit la valeur d'une métrique ; `heure` -1 = la journée entière. Réécrit la ligne si elle existe.
    func serie(_ business: String, _ metrique: String, jour: String, heure: Int = -1, _ valeur: Double) throws {
        try db.execute("""
            insert into serie (business, metrique, jour, heure, valeur, maj) values (?, ?, ?, ?, ?, ?)
            on conflict (business, metrique, jour, heure) do update set valeur = excluded.valeur, maj = excluded.maj
            """, [business, metrique, jour, heure, valeur, Date.now])
    }

    /// Écrit la journée de `metrique` comme la somme des journées de `parts` ; rien si aucune n'est relevée.
    func somme(_ business: String, _ metrique: String, de parts: [String], jour: String) throws {
        try db.execute("""
            insert into serie (business, metrique, jour, heure, valeur, maj)
            select ?, ?, ?, -1, sum(valeur), ? from serie
            where business = ? and jour = ? and heure = -1 and metrique in (\(parts.map { _ in "?" }.joined(separator: ", ")))
            group by business
            on conflict (business, metrique, jour, heure) do update set valeur = excluded.valeur, maj = excluded.maj
            """, [business, metrique, jour, Date.now, business, jour] + parts.map { $0 as Any? })
    }

    /// Vrai s'il manque hier ou le plus vieux des `jours` jours finissant aujourd'hui : l'historique est à relire.
    func historiqueIncomplet(_ business: String, _ metrique: String, jours: Int, jusqua aujourdhui: String) throws -> Bool {
        try [1, jours - 1].contains { recul in
            try db.query("select 1 from serie where business = ? and metrique = ? and jour = ? and heure = -1",
                         [business, metrique, Jour.decale(aujourdhui, jours: -recul)]).isEmpty
        }
    }

    // MARK: fil

    /// Ajoute une ligne au fil ; rend `true` si elle est nouvelle (elle sera notifiée).
    @discardableResult
    func fil(_ e: Evenement) throws -> Bool {
        try db.execute("insert or ignore into fil (id, business, at, type, texte, lien) values (?, ?, ?, ?, ?, ?)",
                       [e.id, e.business, e.at, e.type.rawValue, e.texte, e.lien])
        guard db.changements > 0 else { return false }
        nouveaux.append(e)
        return true
    }

    /// Les lignes du fil ajoutées par une source depuis le dernier appel.
    func prendreNouveaux(source: String) -> [Evenement] {
        let prefixe = source + ":"
        let miens = nouveaux.filter { $0.id.hasPrefix(prefixe) }
        nouveaux.removeAll { $0.id.hasPrefix(prefixe) }
        return miens
    }

    // MARK: vidéos

    /// Ce que la plateforme dit d'une vidéo. Ne touche pas à ce que la fiche a écrit.
    func video(_ v: Video) throws {
        try db.execute("""
            insert into video (id, business, compte, legende, publiee_le, duree_s, url, plateforme) values (?, ?, ?, ?, ?, ?, ?, ?)
            on conflict (id) do update set business = excluded.business, compte = excluded.compte, plateforme = excluded.plateforme,
                legende = coalesce(excluded.legende, video.legende),
                publiee_le = coalesce(excluded.publiee_le, video.publiee_le),
                duree_s = coalesce(excluded.duree_s, video.duree_s),
                url = coalesce(excluded.url, video.url)
            """, [v.id, v.business, v.compte, v.legende, v.publieeLe, v.dureeS, v.url, v.plateforme.rawValue])
    }

    /// Ce que la fiche `contenu/bank` dit d'une vidéo.
    func ficheVideo(_ f: FicheVideo) throws {
        try db.execute("""
            insert into video (id, business, compte, url, titre, format, fiche, verdict) values (?, ?, ?, ?, ?, ?, ?, ?)
            on conflict (id) do update set titre = excluded.titre, format = excluded.format,
                fiche = excluded.fiche, verdict = excluded.verdict
            """, [f.id, f.business, f.compte, f.url, f.titre, f.format, f.fiche, f.verdict])
    }

    func releve(_ r: Releve) throws {
        try db.execute("""
            insert or replace into video_releve (video, at, vues, likes, commentaires, partages, enregistrements,
                watch_moyen_s, completion, abonnes) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [r.video, r.at, r.vues, r.likes, r.commentaires, r.partages, r.enregistrements,
                  r.watchMoyenS, r.completion, r.abonnes])
    }

    /// Remplace l'analyse d'une vidéo, en JSON (docs/donnees.md).
    func analyse(_ video: String, at: Date, _ a: Analyse) throws {
        try db.execute("insert or replace into video_analyse (video, at, donnees) values (?, ?, ?)",
                       [video, at, String(decoding: try JSONEncoder().encode(a), as: UTF8.self)])
    }

    // MARK: apps et classements

    /// Ce que l'App Store dit d'une app. Ne touche pas à `suivie`.
    func app(_ a: Appli) throws {
        try db.execute("""
            insert into app (id, nom, editeur, icone, genre, note, nb_notes, version, business)
            values (?, ?, ?, ?, ?, ?, ?, ?, ?)
            on conflict (id) do update set nom = excluded.nom, editeur = excluded.editeur, icone = excluded.icone,
                genre = excluded.genre, note = excluded.note, nb_notes = excluded.nb_notes,
                version = excluded.version, business = coalesce(excluded.business, app.business)
            """, [a.id, a.nom, a.editeur, a.icone, a.genre, a.note, a.nbNotes, a.version, a.business])
    }

    func suivre(_ app: String, _ oui: Bool) throws {
        try db.execute("update app set suivie = ? where id = ?", [oui, app])
    }

    func appsSuivies() throws -> [Appli] {
        try db.query("select * from app where suivie = 1 order by business is null, nom").map { l in
            Appli(id: l.texte("id") ?? "", nom: l.texte("nom") ?? "", editeur: l.texte("editeur"),
                  icone: l.texte("icone"), genre: l.entier("genre"), note: l.nombre("note"),
                  nbNotes: l.entier("nb_notes"), version: l.texte("version"), business: l.texte("business"))
        }
    }

    /// Une position dans un classement. Tous les rangs d'un même passage partagent le même `at`.
    func rang(app: String, pays: String, genre: Int, liste: Liste, at: Date, position: Int) throws {
        try db.execute("insert or replace into rang (app, pays, genre, liste, at, position) values (?, ?, ?, ?, ?, ?)",
                       [app, pays, genre, liste.rawValue, at, position])
    }

    // MARK: avis

    func avis(_ a: Avis) throws {
        try db.execute("""
            insert into avis (id, business, pays, note, titre, texte, auteur, at, repondu) values (?, ?, ?, ?, ?, ?, ?, ?, ?)
            on conflict (id) do update set note = excluded.note, titre = excluded.titre, texte = excluded.texte,
                repondu = excluded.repondu
            """, [a.id, a.business, a.pays, a.note, a.titre, a.texte, a.auteur, a.at, a.repondu])
    }

    // MARK: à traiter

    /// Remplace les tâches ouvertes d'une source pour un business : les nouvelles entrent,
    /// celles qui ne sont plus renvoyées passent à fait. Une tâche cochée reste faite.
    func synchroniserTaches(source: String, business: String, _ taches: [Tache]) throws {
        try lot {
            var ids: [String] = []
            for t in taches {
                let id = "\(source):\(t.cle)"
                ids.append(id)
                try db.execute("""
                    insert into a_traiter (id, business, texte, etiquette, ton, echeance, source, lien, cree_le)
                    values (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    on conflict (id) do update set texte = excluded.texte, etiquette = excluded.etiquette,
                        ton = excluded.ton, echeance = excluded.echeance, lien = excluded.lien
                    """, [id, business, t.texte, t.etiquette, t.ton.rawValue, t.echeance, source, t.lien, Date.now])
            }
            let ouvertes = try db.query("select id from a_traiter where source = ? and business = ? and fait_le is null",
                                        [source, business])
            for l in ouvertes {
                guard let id = l.texte("id"), !ids.contains(id) else { continue }
                try db.execute("update a_traiter set fait_le = ? where id = ?", [Date.now, id])
            }
        }
    }

    func ajouterTache(texte: String, business: String?, echeance: String?) throws {
        try db.execute("""
            insert into a_traiter (id, business, texte, echeance, source, cree_le) values (?, ?, ?, ?, 'manuel', ?)
            """, ["manuel:\(UUID().uuidString)", business, texte, echeance, Date.now])
    }

    func cocher(_ id: String, fait: Bool) throws {
        try db.execute("update a_traiter set fait_le = ? where id = ?", [fait ? Date.now : nil, id])
    }

    func supprimerTache(_ id: String) throws {
        try db.execute("delete from a_traiter where id = ? and source = 'manuel'", [id])
    }

    // MARK: SAV

    /// Écrit ce qu'un passage a lu du SAV. Un fil ouvert ou un retour à traiter en base qui n'est plus dans le relevé
    /// a été traité ailleurs (dashboard) : il passe fermé, ou traité. Rend le nombre de lignes écrites.
    func synchroniserSAV(business: String, _ r: ReleveSAV) throws -> Int {
        try lot {
            for f in r.fils {
                try db.execute("""
                    insert or replace into sav_fil (business, uid, nom, dernier_at, dernier_equipe, apercu, ouvert, non_vu)
                    values (?, ?, ?, ?, ?, ?, ?, ?)
                    """, [business, f.uid, f.nom, f.dernierAt, f.dernierEquipe, f.apercu, f.ouvert, f.nonVu])
            }
            let ouverts = Set(r.fils.filter(\.ouvert).map(\.uid))
            for l in try db.query("select uid from sav_fil where business = ? and ouvert = 1", [business]) {
                guard let uid = l.texte("uid"), !ouverts.contains(uid) else { continue }
                try db.execute("update sav_fil set ouvert = 0 where business = ? and uid = ?", [business, uid])
            }
            for x in r.retours {
                try db.execute("""
                    insert or replace into sav_retour (business, id, uid, source, categorie, etoiles, message, citation,
                        conversation, traite, traite_le, plateforme, build, at)
                    values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, [business, x.id, x.uid, x.source, x.categorie, x.etoiles, x.message, x.citation, x.conversation,
                          x.traite, x.traiteLe, x.plateforme, x.build, x.at])
            }
            let aTraiter = Set(r.retours.filter { !$0.traite }.map(\.id))
            for l in try db.query("select id from sav_retour where business = ? and traite = 0", [business]) {
                guard let id = l.texte("id"), !aTraiter.contains(id) else { continue }
                try db.execute("update sav_retour set traite = 1 where business = ? and id = ?", [business, id])
            }
            for (uid, messages) in r.messages {
                try db.execute("delete from sav_message where business = ? and uid = ?", [business, uid])
                for m in messages { try message(business: business, uid: uid, m) }
            }
            for (uid, email) in r.emails {
                try db.execute("insert or replace into sav_compte (business, uid, email) values (?, ?, ?)", [business, uid, email])
            }
            return r.fils.count + r.retours.count + r.messages.values.map(\.count).reduce(0, +) + r.emails.count
        }
    }

    /// Les fils dont les messages sont en base, avec l'instant de leur dernier message tel qu'écrit (`Date.iso`) :
    /// un fil dont l'instant a changé est à relire.
    func filsLus(business: String) throws -> [String: String] {
        let lignes = try db.query("""
            select uid, dernier_at from sav_fil f where business = ?
                and exists (select 1 from sav_message m where m.business = f.business and m.uid = f.uid)
            """, [business])
        var lus: [String: String] = [:]
        for l in lignes { if let uid = l.texte("uid"), let at = l.texte("dernier_at") { lus[uid] = at } }
        return lus
    }

    /// Les uid dont l'email est connu ; un invité, sans email, est relu à chaque passage (il a pu lier un compte).
    func comptesSAV(business: String) throws -> Set<String> {
        Set(try db.query("select uid from sav_compte where business = ? and email != ''", [business]).compactMap { $0.texte("uid") })
    }

    /// La réponse partie de l'écran SAV : le message, le fil passé à l'équipe et fermé, ses tâches faites.
    func repondreSAV(_ cle: CleFil, _ m: MessageSAV, apercu: String) throws {
        try lot {
            try message(business: cle.business, uid: cle.uid, m)
            try db.execute("""
                insert into sav_fil (business, uid, dernier_at, dernier_equipe, apercu, ouvert, non_vu) values (?, ?, ?, 1, ?, 0, 1)
                on conflict (business, uid) do update set dernier_at = excluded.dernier_at, dernier_equipe = 1,
                    apercu = excluded.apercu, ouvert = 0, non_vu = 1
                """, [cle.business, cle.uid, m.at, apercu])
            try fermerTaches(cle)
        }
    }

    /// Le fil marqué traité sans réponse.
    func fermerFilSAV(_ cle: CleFil) throws {
        try lot {
            try db.execute("update sav_fil set ouvert = 0 where business = ? and uid = ?", [cle.business, cle.uid])
            try fermerTaches(cle)
        }
    }

    /// Un retour marqué traité, ou rouvert, et sa tâche avec.
    func traiterRetourSAV(business: String, id: String, traite: Bool, le date: Date) throws {
        try lot {
            try db.execute("update sav_retour set traite = ?, traite_le = ? where business = ? and id = ?",
                           [traite, traite ? date : nil, business, id])
            try cocher(Firebase.tacheRetour(id), fait: traite)
        }
    }

    private func message(business: String, uid: String, _ m: MessageSAV) throws {
        try db.execute("insert or replace into sav_message (business, uid, id, equipe, texte, at) values (?, ?, ?, ?, ?, ?)",
                       [business, uid, m.id, m.equipe, m.texte, m.at])
    }

    private func fermerTaches(_ cle: CleFil) throws {
        let prefixe = Firebase.prefixeTacheFil(cle.uid)
        try db.execute("""
            update a_traiter set fait_le = ? where business = ? and fait_le is null and substr(id, 1, ?) = ?
            """, [Date.now, cle.business, prefixe.count, prefixe])
    }

    // MARK: installs

    /// Remplace les installs d'un business à partir de `debut` : un jour recalculé perd ses anciennes lignes.
    func installs(business: String, depuis debut: String, _ lignes: [Install]) throws {
        try lot {
            try db.execute("delete from install where business = ? and jour >= ?", [business, debut])
            for i in lignes {
                let valeurs = Dictionary(uniqueKeysWithValues: i.valeurs.map { ($0.key.rawValue, $0.value) })
                let json = String(decoding: try JSONSerialization.data(withJSONObject: valeurs, options: .sortedKeys), as: UTF8.self)
                try db.execute("""
                    insert into install (business, jour, loin, paywall, essai, direct, rond, j1, j7, j14, j30, client, valeurs)
                    values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, [business, i.jour, i.loin, i.paywall, i.essai, i.direct, i.rond, i.j1, i.j7, i.j14, i.j30, i.client, json])
            }
        }
    }

    /// Les clients convertis à demander à RevenueCat, les plus récents d'abord : jamais lus, ou encore en essai
    /// (ou sans paiement), lus avant `relu` et installés depuis `depuis`.
    func clientsAVerifier(business: String, depuis: String, relu: Date, limite: Int) throws -> [String] {
        try db.query("""
            select i.client, max(i.jour) as jour from install i
            left join paiement p on p.business = i.business and p.client = i.client
            where i.business = ? and i.client is not null
                and (p.client is null or (p.etat in ('essai', 'non') and p.lu < ? and i.jour >= ?))
            group by i.client order by jour desc limit ?
            """, [business, relu, depuis, limite]).compactMap { $0.texte("client") }
    }

    func paiement(business: String, client: String, _ etat: EtatPaiement, lu: Date) throws {
        try db.execute("""
            insert into paiement (business, client, etat, lu) values (?, ?, ?, ?)
            on conflict (business, client) do update set etat = excluded.etat, lu = excluded.lu
            """, [business, client, etat.rawValue, lu])
    }

    /// Remplace les portes du paywall d'un business à partir de `debut`.
    func portes(business: String, depuis debut: String, _ lignes: [Porte]) throws {
        try lot {
            try db.execute("delete from porte where business = ? and jour >= ?", [business, debut])
            for p in lignes {
                try db.execute("insert into porte (business, jour, porte, vues, essais, directs) values (?, ?, ?, ?, ?, ?)",
                               [business, p.jour, p.porte, p.vues, p.essais, p.directs])
            }
        }
    }

    // MARK: plan

    /// Remplace le plan par les lignes de la note, dans leur ordre.
    func plan(_ lignes: [LignePlan]) throws {
        try lot {
            try db.execute("delete from plan")
            for (i, l) in lignes.enumerated() {
                try db.execute("insert into plan (ordre, section, texte, coche, fait) values (?, ?, ?, ?, ?)",
                               [i, l.section, l.texte, l.coche, l.fait])
            }
        }
    }

    // MARK: journal de collecte

    func journal(_ p: Passage) throws {
        try db.execute("insert into collecte (source, debut, fin, etat, erreur, lignes) values (?, ?, ?, ?, ?, ?)",
                       [p.source, p.debut, p.fin, p.etat.rawValue, p.erreur, p.lignes])
    }

    func dernierPassage(_ source: String) throws -> Passage? {
        try db.query("select * from collecte where source = ? order by debut desc limit 1", [source]).first.map(Passage.init)
    }

    func dernierSucces(_ source: String) throws -> Date? {
        try db.query("select max(fin) as fin from collecte where source = ? and etat = 'ok'", [source]).first?.date("fin")
    }


    // MARK: réglages

    func reglage(_ cle: String) throws -> String? {
        try db.query("select valeur from reglage where cle = ?", [cle]).first?.texte("valeur")
    }

    func regler(_ cle: String, _ valeur: String?) throws {
        if let valeur {
            try db.execute("insert or replace into reglage (cle, valeur) values (?, ?)", [cle, valeur])
        } else {
            try db.execute("delete from reglage where cle = ?", [cle])
        }
    }
}

extension Passage {
    init(_ l: Ligne) {
        self.init(source: l.texte("source") ?? "", debut: l.date("debut") ?? .distantPast, fin: l.date("fin") ?? .distantPast,
                  etat: Etat(rawValue: l.texte("etat") ?? "") ?? .erreur, erreur: l.texte("erreur"),
                  lignes: l.entier("lignes") ?? 0)
    }
}
