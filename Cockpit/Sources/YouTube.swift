import Foundation

/// Voir docs/sources/youtube.md.
struct YouTube: Source {
    let id = "youtube"
    let nom = "YouTube"
    let cadence: TimeInterval = 3600

    /// La liste à plat n'a ni date ni likes : on ouvre les vidéos inconnues et les récentes, au plus tant par passage.
    static let ouvertesMax = 20
    static let recente: TimeInterval = 7 * 86_400

    func collecte(_ ctx: Contexte) async throws -> Int {
        let store = ctx.store
        let maintenant = Date.now
        let suivis = Set(ctx.businesses.map(\.id))
        let comptes = try store.comptes().filter { $0.plateforme == .youtube && $0.actif && suivis.contains($0.business) }
        guard !comptes.isEmpty else { throw SourceErreur.nonConfigure("aucune chaîne YouTube suivie, en ajouter dans Vidéos") }
        let publiees = Dictionary(try store.db.query("select id, publiee_le from video where plateforme = 'youtube'")
            .compactMap { l in l.texte("id").map { ($0, l.date("publiee_le")) } }, uniquingKeysWith: { a, _ in a })

        var echecs: [String] = []
        var liste = YtDlp.Liste()
        var profils: [ReleveCompte] = []
        for c in comptes {
            do {
                let l = try YtDlp.liste(await YtDlp.liste(c.plateforme.profil(c.handle) + "/shorts"), plateforme: .youtube,
                                        business: c.business, compte: c.handle, at: maintenant)
                liste.videos += l.videos
                liste.releves += l.releves
                liste.images.merge(l.images) { a, _ in a }
                if let avatar = l.avatar { liste.images[Miniatures.avatar(c.id)] = avatar }
                profils.append(ReleveCompte(compte: c.id, at: maintenant, abonnes: l.abonnes, videos: l.videos.count))
                let aOuvrir = l.videos.filter { v in
                    guard let publiee = publiees[v.id] ?? nil else { return true }
                    return maintenant.timeIntervalSince(publiee) < Self.recente
                }.prefix(Self.ouvertesMax).compactMap(\.url)
                guard !aOuvrir.isEmpty else { continue }
                // après la liste : ses champs complets remplacent ceux de la liste à plat
                let d = try YtDlp.details(await YtDlp.details(Array(aOuvrir)), plateforme: .youtube,
                                          business: c.business, compte: c.handle, at: maintenant)
                liste.videos += d.videos
                liste.releves += d.releves
            } catch {
                echecs.append("@\(c.handle) : \(error.localizedDescription)")
            }
        }
        echecs += await Miniatures.telecharger(liste.images, ctx.http)
        echecs += await Miniatures.extrairePremieres(liste.videos)

        try store.lot {
            for v in liste.videos {
                try store.video(v)
                guard let publiee = v.publieeLe else { continue }
                try store.fil(Evenement(id: "youtube:pub:\(v.id)", business: v.business, at: publiee, type: .video,
                                        texte: "Nouvelle vidéo sur YouTube @\(v.compte)" + (v.legende.map { " : \($0.prefix(60))" } ?? ""),
                                        lien: v.url))
            }
            for r in liste.releves { try store.releve(r) }
            for p in profils { try store.releve(p) }
        }
        if !echecs.isEmpty { throw SourceErreur.format("\(echecs.count) échecs, dont \(echecs[0])") }
        return liste.videos.count + liste.releves.count + profils.count
    }
}
