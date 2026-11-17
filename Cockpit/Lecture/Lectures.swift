import Foundation
import os

/// Tout ce que les écrans lisent, filtré sur les business affichés (tous, ou celui du segmenté).
/// Rien que des `select` sur les tables décrites dans docs/donnees.md.
struct Lectures {
    let db: Database
    let businesses: [Business]
    var maintenant: Date = .now
    /// Le store affiché ; nil = les deux.
    var boutique: Boutique?

    /// Une vidéo passe le seuil quand ses partages ou ses enregistrements dépassent 1,5 % des vues (fiches contenu/bank).
    static let seuilVideo = 0.015
    private static let log = Logger(subsystem: "com.tonysanchez.cockpit", category: "lectures")

    var ids: [Any?] { businesses.map(\.id) }
    /// `(?, ?)` pour filtrer sur les business affichés.
    var dans: String { "(" + businesses.map { _ in "?" }.joined(separator: ", ") + ")" }

    /// Une erreur SQLite est journalisée et rend une liste vide : l'écran affiche « … » au lieu de planter.
    func q(_ sql: String, _ params: [Any?] = []) -> [Ligne] {
        do {
            return try db.query(sql, params)
        } catch {
            Self.log.error("\(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: séries

    /// La série lue : celle du store affiché quand la métrique est écrite par store, le total sinon.
    func serie(_ m: String) -> String {
        guard let boutique, Boutique.separees.contains(m) else { return m }
        return boutique.metrique(m)
    }

    /// Valeur d'une journée, sommée sur les business (moyenne pour une latence) ; nil si aucune source ne l'a écrite.
    func valeur(_ m: String, jour: String = Jour.aujourdhui, moyenne: Bool = false) -> Double? {
        q("select \(moyenne ? "avg" : "sum")(valeur) as v from serie where metrique = ? and jour = ? and heure = -1 and business in \(dans)",
          [serie(m), jour] + ids).first?.nombre("v")
    }

    /// Les `n` derniers jours jusqu'à `jusqua`, du plus ancien au plus récent ; nil pour un jour sans relevé.
    func jours(_ m: String, _ n: Int, jusqua: String = Jour.aujourdhui, moyenne: Bool = false) -> [Double?] {
        let cles = Jour.derniers(n, jusqua: jusqua)
        let lignes = q("""
            select jour, \(moyenne ? "avg" : "sum")(valeur) as v from serie
            where metrique = ? and heure = -1 and jour between ? and ? and business in \(dans) group by jour
            """, [serie(m), cles.first, cles.last] + ids)
        var parJour: [String: Double] = [:]
        for l in lignes { if let j = l.texte("jour"), let v = l.nombre("v") { parJour[j] = v } }
        return cles.map { parJour[$0] }
    }

    /// Les 24 heures d'une journée ; nil pour une heure sans relevé.
    func heures(_ m: String, jour: String = Jour.aujourdhui, moyenne: Bool = false) -> [Double?] {
        let lignes = q("""
            select heure, \(moyenne ? "avg" : "sum")(valeur) as v from serie
            where metrique = ? and jour = ? and heure >= 0 and business in \(dans) group by heure
            """, [serie(m), jour] + ids)
        var h = [Double?](repeating: nil, count: 24)
        for l in lignes { if let i = l.entier("heure"), (0..<24).contains(i) { h[i] = l.nombre("v") } }
        return h
    }

    /// Les fournisseurs IA appelés depuis `jour`, du plus sollicité au moins sollicité.
    /// `glob` et non `like` : sensible à la casse, il passe par la clé primaire de `serie`.
    func fournisseursIA(depuis jour: String) -> [String] {
        q("""
            select substr(metrique, 8) as f, sum(valeur) as n from serie
            where metrique glob 'req_ia.*' and heure = -1 and jour >= ? and business in \(dans) group by f order by n desc
            """, [jour] + ids).compactMap { $0.texte("f") }
    }

    // MARK: fil

    /// Les événements entre `du` (inclus) et `au` (exclu), les plus récents d'abord.
    func fil(du: Date = .distantPast, au: Date = .distantFuture, limite: Int = 40) -> [Evenement] {
        q("select * from fil where business in \(dans) and at >= ? and at < ? order by at desc limit ?",
          ids + [du, au, limite]).compactMap { l in
            guard let id = l.texte("id"), let at = l.date("at"), let type = TypeFil(rawValue: l.texte("type") ?? "") else {
                return nil
            }
            return Evenement(id: id, business: l.texte("business") ?? "", at: at, type: type,
                             texte: l.texte("texte") ?? "", lien: l.texte("lien"))
        }
    }

    // MARK: vidéos

    /// Les vidéos des comptes suivis avec leur dernier relevé, les plus vues d'abord. Un compte retiré ne montre plus
    /// ses vidéos, gardées dans la base.
    func videos(limite: Int = 1000) -> [LigneVideo] {
        let ilYa24h = maintenant.addingTimeInterval(-86_400)
        return q("""
            select v.id, v.business, v.compte, v.plateforme, v.titre, v.legende, v.format, v.fiche, v.url,
                v.publiee_le, v.duree_s, v.verdict, r.at, r.vues, r.likes, r.commentaires, r.partages,
                r.enregistrements, r.completion, r.watch_moyen_s, r.abonnes,
                (select a.vues from video_releve a where a.video = v.id and a.at <= ? order by a.at desc limit 1) as vues_avant
            from video v
            join compte c on c.plateforme = v.plateforme and c.handle = v.compte
            join video_releve r on r.video = v.id and r.at = (select max(at) from video_releve where video = v.id)
            where v.business in \(dans)
            order by r.vues desc limit ?
            """, [ilYa24h] + ids + [limite]).map { l in
            let vues = l.entier("vues") ?? 0
            let publiee = l.date("publiee_le")
            var gain: Int?
            if let avant = l.entier("vues_avant") {
                gain = vues - avant
            } else if let publiee, publiee > ilYa24h {
                gain = vues
            }
            return LigneVideo(
                id: l.texte("id") ?? "", business: l.texte("business") ?? "", compte: l.texte("compte") ?? "",
                plateforme: Plateforme(rawValue: l.texte("plateforme") ?? "") ?? .tiktok,
                titre: TikTok.titre(legende: l.texte("legende"), fiche: l.texte("titre"))
                    ?? "@\(l.texte("compte") ?? "")" + (publiee.map { ", " + Format.jourCourt($0) } ?? ""),
                format: l.texte("format"), fiche: l.texte("fiche"), url: l.texte("url"), publieeLe: publiee,
                dureeS: l.nombre("duree_s"), verdict: l.booleen("verdict"), vues: vues, likes: l.entier("likes"),
                commentaires: l.entier("commentaires"), partages: l.entier("partages"),
                enregistrements: l.entier("enregistrements"), completion: l.nombre("completion"),
                watchMoyenS: l.nombre("watch_moyen_s"), abonnes: l.entier("abonnes"), gain24h: gain,
                releveLe: l.date("at") ?? maintenant)
        }
    }

    /// Les relevés d'une vidéo, du plus ancien au plus récent.
    func releves(_ video: String) -> [(at: Date, vues: Int)] {
        q("select at, vues from video_releve where video = ? order by at", [video]).compactMap { l in
            l.date("at").map { ($0, l.entier("vues") ?? 0) }
        }
    }

    /// L'accroche de chaque vidéo qui a une courbe de rétention : la part encore là à `Percee.accrocheS` secondes.
    func accroches() -> [String: Double] {
        var r: [String: Double] = [:]
        for l in q("select video, json_extract(donnees, '$.retention[\(Percee.accrocheS)]') as a from video_analyse") {
            if let id = l.texte("video"), let a = l.nombre("a") { r[id] = a }
        }
        return r
    }

    /// L'analyse privée d'une vidéo et sa date ; nil si sa plateforme ne l'a jamais donnée.
    func analyse(_ video: String) -> (Analyse, at: Date)? {
        guard let l = q("select at, donnees from video_analyse where video = ?", [video]).first,
              let at = l.date("at"), let json = l.texte("donnees") else { return nil }
        do {
            return (try JSONDecoder().decode(Analyse.self, from: Data(json.utf8)), at)
        } catch {
            Self.log.error("analyse \(video, privacy: .public) : \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: à traiter

    /// Les tâches ouvertes : en retard et alertes d'abord, puis par échéance.
    func taches() -> [LigneTache] {
        let lignes = q("""
            select * from a_traiter where fait_le is null and (business is null or business in \(dans))
            order by echeance is null, echeance, cree_le desc
            """, ids).map(tache)
        return lignes.filter { $0.ton == .alerte } + lignes.filter { $0.ton != .alerte }
    }

    /// Les tâches faites ces derniers jours, les plus récentes d'abord.
    func tachesFaites(jours: Int = 7) -> [LigneTache] {
        q("""
            select * from a_traiter where fait_le >= ? and (business is null or business in \(dans))
            order by fait_le desc limit 30
            """, [maintenant.addingTimeInterval(-Double(jours) * 86_400)] + ids).map(tache)
    }

    func nbATraiter() -> Int {
        q("select count(*) as n from a_traiter where fait_le is null and (business is null or business in \(dans))", ids)
            .first?.entier("n") ?? 0
    }

    private func tache(_ l: Ligne) -> LigneTache {
        let echeance = l.texte("echeance")
        let enRetard = echeance.map { $0 < Jour.cle(maintenant) } ?? false
        return LigneTache(
            id: l.texte("id") ?? "", business: l.texte("business"), texte: l.texte("texte") ?? "",
            etiquette: l.texte("etiquette"),
            ton: enRetard ? .alerte : Tache.Ton(rawValue: l.texte("ton") ?? "") ?? .neutre,
            echeance: echeance, source: l.texte("source") ?? "manuel", lien: l.texte("lien"),
            creeLe: l.date("cree_le"), faitLe: l.date("fait_le"))
    }

    // MARK: SAV

    /// Les fils, ceux à répondre d'abord, puis du plus récent au plus ancien.
    func filsSAV(limite: Int = 100) -> [FilSAV] {
        q("""
            select f.*, c.email from sav_fil f left join sav_compte c on c.business = f.business and c.uid = f.uid
            where f.business in \(dans) order by f.ouvert desc, f.dernier_at desc limit ?
            """, ids + [limite]).compactMap(fil)
    }

    func filSAV(_ cle: CleFil) -> FilSAV? {
        q("""
            select f.*, c.email from sav_fil f left join sav_compte c on c.business = f.business and c.uid = f.uid
            where f.business = ? and f.uid = ?
            """, [cle.business, cle.uid]).first.flatMap(fil)
    }

    /// Les messages d'un fil, du plus ancien au plus récent.
    func messagesSAV(_ cle: CleFil) -> [MessageSAV] {
        q("select * from sav_message where business = ? and uid = ? order by at, id", [cle.business, cle.uid]).compactMap { l in
            guard let id = l.texte("id"), let at = l.date("at") else { return nil }
            return MessageSAV(id: id, equipe: l.booleen("equipe"), texte: l.texte("texte") ?? "", at: at)
        }
    }

    /// Les retours, les plus récents d'abord ; `traites` nil = tous.
    func retoursSAV(traites: Bool?, limite: Int = 100) -> [RetourSAV] {
        let filtre = traites.map { "and r.traite = \($0 ? 1 : 0)" } ?? ""
        return q("""
            select r.*, c.email from sav_retour r left join sav_compte c on c.business = r.business and c.uid = r.uid
            where r.business in \(dans) \(filtre) order by r.at desc limit ?
            """, ids + [limite]).compactMap { l in
            guard let business = l.texte("business"), let id = l.texte("id"), let at = l.date("at") else { return nil }
            return RetourSAV(business: business, id: id, uid: l.texte("uid"), email: l.texte("email"), source: l.texte("source"),
                             categorie: l.texte("categorie"), etoiles: l.entier("etoiles"), message: l.texte("message") ?? "",
                             citation: l.texte("citation"), conversation: l.texte("conversation"), traite: l.booleen("traite"),
                             traiteLe: l.date("traite_le"), plateforme: l.texte("plateforme"), build: l.texte("build"), at: at)
        }
    }

    /// L'email connu d'un compte, vide pour un invité, nil s'il n'a pas encore été lu.
    func emailSAV(_ cle: CleFil) -> String? {
        q("select email from sav_compte where business = ? and uid = ?", [cle.business, cle.uid]).first?.texte("email")
    }

    /// Les fils à répondre et les retours à traiter.
    func nbSAV() -> (fils: Int, retours: Int) {
        let n = q("""
            select (select count(*) from sav_fil where ouvert = 1 and business in \(dans)) as fils,
                (select count(*) from sav_retour where traite = 0 and business in \(dans)) as retours
            """, ids + ids).first
        return (n?.entier("fils") ?? 0, n?.entier("retours") ?? 0)
    }

    private func fil(_ l: Ligne) -> FilSAV? {
        guard let business = l.texte("business"), let uid = l.texte("uid"), let at = l.date("dernier_at") else { return nil }
        return FilSAV(business: business, uid: uid, nom: l.texte("nom"), email: l.texte("email"), dernierAt: at,
                      dernierEquipe: l.booleen("dernier_equipe"), apercu: l.texte("apercu") ?? "",
                      ouvert: l.booleen("ouvert"), nonVu: l.booleen("non_vu"))
    }

    // MARK: collecte

    /// Le dernier passage de chaque source.
    func derniersPassages() -> [String: Passage] {
        let lignes = q("select * from collecte c where debut = (select max(debut) from collecte where source = c.source)")
        return Dictionary(lignes.map { (Passage($0).source, Passage($0)) }, uniquingKeysWith: { a, _ in a })
    }

    /// Les derniers passages d'une source, ou de toutes.
    func journal(_ source: String? = nil, limite: Int = 60) -> [Passage] {
        if let source {
            return q("select * from collecte where source = ? order by debut desc limit ?", [source, limite]).map(Passage.init)
        }
        return q("select * from collecte order by debut desc limit ?", [limite]).map(Passage.init)
    }

    // MARK: classements

    /// Le dernier passage de la source Classements, et celui d'environ 24 h avant.
    private func passagesRang() -> (dernier: Date, veille: Date?)? {
        guard let dernier = q("select max(at) as at from rang").first?.date("at") else { return nil }
        let veille = q("select max(at) as at from rang where at <= ?", [dernier.addingTimeInterval(-23 * 3600)]).first?.date("at")
        return (dernier, veille)
    }

    private func positions(_ at: Date) -> [String: [CleRang: Int]] {
        var r: [String: [CleRang: Int]] = [:]
        for l in q("select app, pays, genre, liste, position from rang where at = ?", [at]) {
            guard let app = l.texte("app"), let pays = l.texte("pays"), let genre = l.entier("genre"),
                  let liste = Liste(rawValue: l.texte("liste") ?? ""), let p = l.entier("position") else { continue }
            r[app, default: [:]][CleRang(pays: pays, genre: genre, liste: liste)] = p
        }
        return r
    }

    /// Nos apps des business affichés, puis celles des potes, avec leurs rangs au dernier passage et à la veille.
    func apps() -> [LigneApp] {
        let suivies = q("select * from app where suivie = 1 and (business is null or business in \(dans)) order by business is null, nom", ids)
        let passages = passagesRang()
        let derniers = passages.map { positions($0.dernier) } ?? [:]
        let veille = passages?.veille.map(positions) ?? [:]
        return suivies.map { l in
            let a = Appli(id: l.texte("id") ?? "", nom: l.texte("nom") ?? "", editeur: l.texte("editeur"),
                          icone: l.texte("icone"), genre: l.entier("genre"), note: l.nombre("note"),
                          nbNotes: l.entier("nb_notes"), version: l.texte("version"), business: l.texte("business"))
            return LigneApp(app: a, rangs: derniers[a.id] ?? [:], veille: veille[a.id] ?? [:], lu: passages?.dernier)
        }
    }

    /// La meilleure position du jour dans un classement, sur les `n` derniers jours ; nil = hors top ou pas lu.
    func rangJours(_ app: String, _ cle: CleRang, _ n: Int) -> [Double?] {
        let cles = Jour.derniers(n, jusqua: Jour.cle(maintenant))
        guard let debut = cles.first.flatMap(Jour.date) else { return [] }
        var meilleur: [String: Int] = [:]
        for l in q("select at, position from rang where app = ? and pays = ? and genre = ? and liste = ? and at >= ?",
                   [app, cle.pays, cle.genre, cle.liste.rawValue, debut]) {
            guard let at = l.date("at"), let p = l.entier("position") else { continue }
            let j = Jour.cle(at)
            meilleur[j] = min(meilleur[j] ?? p, p)
        }
        return cles.map { meilleur[$0].map(Double.init) }
    }

    /// Le rang de notre app dans son classement principal : premier business affiché, premier pays, gratuit.
    func rangPrincipal() -> (cle: CleRang, ligne: LigneApp)? {
        guard let b = businesses.first(where: { $0.config.appStoreId != nil }), let id = b.config.appStoreId,
              let pays = b.config.pays.first, let ligne = apps().first(where: { $0.id == id }) else { return nil }
        return (CleRang(pays: pays, genre: b.config.genre, liste: .gratuit), ligne)
    }

    // MARK: avis

    func avis(limite: Int = 30) -> [Avis] {
        q("select * from avis where business in \(dans) order by at desc limit ?", ids + [limite]).compactMap { l in
            guard let id = l.texte("id"), let at = l.date("at") else { return nil }
            return Avis(id: id, business: l.texte("business") ?? "", pays: l.texte("pays"), note: l.entier("note") ?? 0,
                        titre: l.texte("titre"), texte: l.texte("texte"), auteur: l.texte("auteur"), at: at,
                        repondu: l.booleen("repondu"))
        }
    }
}

struct LigneVideo: Identifiable, Hashable {
    var id: String
    var business: String
    var compte: String
    var plateforme: Plateforme = .tiktok
    var titre: String
    var format: String?
    var fiche: String?
    var url: String?
    var publieeLe: Date?
    var dureeS: Double?
    var verdict: Bool
    var vues: Int
    var likes: Int?
    var commentaires: Int?
    var partages: Int?
    var enregistrements: Int?
    var completion: Double?
    var watchMoyenS: Double?
    var abonnes: Int?
    /// Vues gagnées sur 24 h ; nil sans relevé assez ancien.
    var gain24h: Int?
    var releveLe: Date

    var partPartages: Double? { part(partages) }
    var partEnreg: Double? { part(enregistrements) }
    var seuilAtteint: Bool { max(partPartages ?? 0, partEnreg ?? 0) >= Lectures.seuilVideo }
    /// Likes, commentaires, partages et enregistrements sur les vues ; nil sans aucun de ces compteurs.
    var engagement: Double? {
        let n = [likes, commentaires, partages, enregistrements].compactMap { $0 }
        return n.isEmpty || vues == 0 ? nil : Double(n.reduce(0, +)) / Double(vues)
    }
    /// Abonnés gagnés pour 1 000 vues : la vidéo qui convertit, connue seulement par les stats privées.
    var conversion: Double? { abonnes.flatMap { vues > 0 ? Double($0) * 1000 / Double(vues) : nil } }

    private func part(_ n: Int?) -> Double? { n.map { vues > 0 ? Double($0) / Double(vues) : 0 } }
}

struct LigneTache: Identifiable, Hashable {
    var id: String
    var business: String?
    var texte: String
    var etiquette: String?
    var ton: Tache.Ton
    var echeance: String?
    var source: String
    var lien: String?
    var creeLe: Date?
    var faitLe: Date?

    /// L'étiquette posée par la source, sinon l'échéance dite en clair.
    func pastille(aujourdhui: String = Jour.aujourdhui) -> String? {
        if let etiquette { return etiquette }
        guard let echeance else { return nil }
        if echeance < aujourdhui { return "retard" }
        if echeance == aujourdhui { return "aujourd'hui" }
        if echeance == Jour.decale(aujourdhui, jours: 1) { return "demain" }
        return Format.jourCourt(cle: echeance)
    }
}

/// Un classement lu par la source Classements.
struct CleRang: Hashable {
    var pays: String
    var genre: Int
    var liste: Liste
}

struct LigneApp: Identifiable, Hashable {
    var app: Appli
    /// Position au dernier passage ; une clé absente = hors top 200.
    var rangs: [CleRang: Int]
    var veille: [CleRang: Int]
    /// Heure du dernier passage de Classements, nil s'il n'y en a jamais eu.
    var lu: Date?

    var id: String { app.id }
    var estANous: Bool { app.business != nil }

    /// Places gagnées depuis la veille : positif = monte. Nil si absent d'un des deux passages.
    func gain(_ cle: CleRang) -> Int? {
        guard let p = rangs[cle], let v = veille[cle] else { return nil }
        return v - p
    }
}
