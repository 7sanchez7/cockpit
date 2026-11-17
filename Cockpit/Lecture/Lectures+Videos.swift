import Foundation

/// Les lectures de l'écran Vidéos : comptes suivis, abonnés et rythme de publication.
extension Lectures {
    /// Les comptes suivis des business affichés : dernier nombre d'abonnés, écart sur 7 jours, courbe de 14 jours.
    func comptes() -> [LigneCompte] {
        let jours = Jour.derniers(14, jusqua: Jour.cle(maintenant))
        let ilYa7j = maintenant.addingTimeInterval(-7 * 86_400)
        var parCompte: [String: [(at: Date, abonnes: Int)]] = [:]
        for l in q("select compte, at, abonnes from compte_releve where abonnes is not null and at >= ? order by at",
                   [maintenant.addingTimeInterval(-15 * 86_400)]) {
            if let c = l.texte("compte"), let at = l.date("at"), let n = l.entier("abonnes") { parCompte[c, default: []].append((at, n)) }
        }
        return q("""
            select c.id, c.plateforme, c.handle, c.business, c.actif,
                (select count(*) from video v where v.plateforme = c.plateforme and v.compte = c.handle) as videos,
                (select r.abonnes from compte_releve r where r.compte = c.id and r.abonnes is not null
                    order by r.at desc limit 1) as abonnes,
                (select max(r.at) from compte_releve r where r.compte = c.id) as releve_le
            from compte c where c.business in \(dans) order by c.business, c.plateforme, c.ajoute_le
            """, ids).compactMap { l in
            guard let id = l.texte("id"), let p = Plateforme(rawValue: l.texte("plateforme") ?? "") else { return nil }
            let releves = parCompte[id] ?? []
            var parJour: [String: Double] = [:]
            for r in releves { parJour[Jour.cle(r.at)] = Double(r.abonnes) }
            let abonnes = l.entier("abonnes")
            let avant = releves.last { $0.at <= ilYa7j }?.abonnes
            return LigneCompte(id: id, plateforme: p, handle: l.texte("handle") ?? "", business: l.texte("business") ?? "",
                               actif: l.booleen("actif"), abonnes: abonnes,
                               gain7j: abonnes.flatMap { n in avant.map { n - $0 } },
                               serie: jours.map { parJour[$0] }, videos: l.entier("videos") ?? 0,
                               releveLe: l.date("releve_le"))
        }
    }

    /// Les vidéos publiées chaque jour de Paris sur les `n` jours jusqu'à `jusqua`, du plus ancien au plus récent.
    func publications(_ n: Int, jusqua: String = Jour.aujourdhui) -> [Double] {
        let cles = Jour.derniers(n, jusqua: jusqua)
        guard let debut = cles.first.flatMap(Jour.date), let fin = Jour.date(Jour.decale(jusqua, jours: 1)) else { return [] }
        var parJour: [String: Double] = [:]
        for l in q("select publiee_le from video where publiee_le >= ? and publiee_le < ? and business in \(dans)",
                      [debut, fin] + ids) {
            if let d = l.date("publiee_le") { parJour[Jour.cle(d), default: 0] += 1 }
        }
        return cles.map { parJour[$0] ?? 0 }
    }

    /// Les clés des images à mettre en mémoire, dans l'ordre où l'app les montre : icônes des apps, avatars des
    /// comptes, puis les vidéos les plus récentes. `limite` borne les vidéos à ce que le cache mémoire tient.
    func images(limite: Int) -> [[String]] {
        let apps = businesses.compactMap(\.config.appStoreId) + q("select id from app where suivie = 1").compactMap { $0.texte("id") }
        let comptes = q("select id from compte where business in \(dans)", ids).compactMap { $0.texte("id") }
        let videos = q("""
            select v.id, v.plateforme from video v join compte c on c.plateforme = v.plateforme and c.handle = v.compte
            where v.business in \(dans) order by v.publiee_le desc limit ?
            """, ids + [limite]).compactMap { l in
            l.texte("id").flatMap { id in Plateforme(rawValue: l.texte("plateforme") ?? "").map { Miniatures.cles(id, $0) } }
        }
        return apps.map { [Miniatures.icone($0)] } + comptes.map { [Miniatures.avatar($0)] } + videos
    }
}

struct LigneCompte: Identifiable, Hashable {
    var id: String
    var plateforme: Plateforme
    var handle: String
    var business: String
    var actif: Bool
    var abonnes: Int?
    /// Abonnés gagnés depuis le relevé d'il y a 7 jours ; nil si le compte est suivi depuis moins longtemps.
    var gain7j: Int?
    /// Le dernier nombre d'abonnés de chacun des 14 derniers jours.
    var serie: [Double?]
    var videos: Int
    var releveLe: Date?
}
