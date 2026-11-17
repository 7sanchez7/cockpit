import Foundation

/// Voir docs/sources/tiktok.md.
struct TikTok: Source {
    let id = "tiktok"
    let nom = "TikTok"
    let cadence: TimeInterval = 30 * 60

    static let analytics = "https://www.tiktok.com/tiktokstudio/analytics"
    /// Les types de la page Analytics d'une vidéo : TikTok ne rend les `_realtime` que demandés tous ensemble.
    static let types = ["video_info", "item_search_terms", "video_traffic_source_percent_realtime",
                        "video_retention_rate_realtime", "video_view_realtime", "video_total_duration_realtime",
                        "video_per_duration_realtime", "video_finish_rate_realtime", "video_new_follower_realtime",
                        "video_vv_history_7d", "video_vv_history_48_hours", "video_uv", "video_viewer_new_viewer_percent",
                        "video_viewer_follower_percent_realtime", "video_viewer_nonfollower_percent_realtime",
                        "video_viewer_age_percent_realtime", "video_viewer_gender_percent_realtime",
                        "video_viewer_location_percent_realtime", "video_like_distribution_realtime"]
    static let paliers = [1_000, 10_000, 100_000, 1_000_000]
    /// Une vidéo plus jeune est relevée à chaque passage, une plus vieille une fois par jour.
    static let recente: TimeInterval = 14 * 86_400

    func collecte(_ ctx: Contexte) async throws -> Int {
        let store = ctx.store
        let maintenant = Date.now
        let suivis = Set(ctx.businesses.map(\.id))
        let comptes = try store.comptes().filter { $0.plateforme == .tiktok && $0.actif && suivis.contains($0.business) }
        guard !comptes.isEmpty else { throw SourceErreur.nonConfigure("aucun compte TikTok suivi, en ajouter dans Vidéos") }

        var echecs: [String] = []
        var liste = YtDlp.Liste()
        var profils: [ReleveCompte] = []
        var images: [String: String] = [:]
        for c in comptes {
            do {
                let l = try YtDlp.liste(await YtDlp.liste(c.plateforme.profil(c.handle)), plateforme: .tiktok,
                                        business: c.business, compte: c.handle, at: maintenant)
                liste.videos += l.videos
                liste.releves += l.releves
                images.merge(l.images) { a, _ in a }
            } catch {
                echecs.append("@\(c.handle) : \(error.localizedDescription)")
            }
            do {
                let page = try await ctx.http.donnees(HTTP.requete(c.plateforme.profil(c.handle), entetes: ["User-Agent": HTTP.navigateur]))
                let (r, avatar) = try Self.profil(page, compte: c.id, at: maintenant)
                profils.append(r)
                if let avatar { images[Miniatures.avatar(c.id)] = avatar }
            } catch {
                echecs.append("profil @\(c.handle) : \(error.localizedDescription)")
            }
        }
        let releveesAujourdhui = Set(try store.db.query("select distinct video from video_releve where at >= ?",
                                                        [Jour.date(Jour.cle(maintenant)) ?? maintenant]).compactMap { $0.texte("video") })
        let parId = Dictionary(liste.videos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func aRelever(_ id: String) -> Bool {
            maintenant.timeIntervalSince(parId[id]?.publieeLe ?? maintenant) < Self.recente || !releveesAujourdhui.contains(id)
        }
        var releves = Dictionary(liste.releves.filter { aRelever($0.video) }.map { ($0.video, $0) }, uniquingKeysWith: { a, _ in a })
        var analyses: [String: Analyse] = [:]

        // stats privées (watch time, abonnés gagnés) : seulement le compte connecté dans Safari
        var sansStudio: String?
        var studio: (session: String, business: String, historique: [Int?])?
        do {
            let cookie = try Safari.entete("tiktok.com", requis: "sessionid")
            let session = try await Self.compteSession(cookie, ctx.http).lowercased()
            if let c = comptes.first(where: { $0.handle == session }) {
                for v in liste.videos where v.compte == session && aRelever(v.id) {
                    do {
                        let requete = try Self.requete(Self.types.map { ["insigh_type": $0, "aweme_id": v.id] },
                                                       referer: "\(Self.analytics)/\(v.id)/overview", cookie: cookie)
                        var reponse = try await ctx.http.donnees(requete)
                        if !Self.complete(reponse) {
                            // les types temps réel arrivent parfois vides au premier appel
                            try await Task.sleep(for: .seconds(3))
                            reponse = try await ctx.http.donnees(requete)
                        }
                        releves[v.id] = try Self.releve(reponse, video: v.id, at: maintenant)
                        analyses[v.id] = try Self.analyse(reponse)
                    } catch {
                        echecs.append("stats \(v.id) : \(error.localizedDescription)")
                    }
                    // pas de rafale sur l'API interne
                    try await Task.sleep(for: .milliseconds(300))
                }
                let historique = try Self.historique(await ctx.http.donnees(Self.requete(
                    [["insigh_type": "vv_history", "days": 7, "end_days": 1]], referer: "\(Self.analytics)/overview", cookie: cookie)))
                studio = (session, c.business, historique)
            } else {
                sansStudio = "stats privées : @\(session) connecté dans Safari n'est pas suivi"
            }
        } catch SourceErreur.nonConfigure(let m) {
            sansStudio = "stats privées : \(m)"
        } catch {
            echecs.append("stats privées : \(error.localizedDescription)")
        }
        echecs += await Miniatures.telecharger(images, ctx.http)

        let titres = Dictionary(try store.db.query("select id, titre from video where plateforme = 'tiktok' and titre is not null")
            .compactMap { l in l.texte("id").map { ($0, l.texte("titre") ?? "") } }, uniquingKeysWith: { a, _ in a })
        func titre(_ v: Video) -> String? { Self.titre(legende: v.legende, fiche: titres[v.id]) }
        var lignes = 0
        try store.lot {
            for v in liste.videos {
                try store.video(v)
                guard let publiee = v.publieeLe else { continue }
                try store.fil(Evenement(id: "tiktok:pub:\(v.id)", business: v.business, at: publiee, type: .video,
                                        texte: "Nouvelle vidéo sur @\(v.compte)" + (titre(v).map { " : \($0)" } ?? ""), lien: v.url))
            }
            for r in releves.values {
                let recente = maintenant.timeIntervalSince(parId[r.video]?.publieeLe ?? .distantPast) < 86_400
                let avant = try store.db.query("select vues from video_releve where video = ? and at < ? order by at desc limit 1",
                                               [r.video, maintenant]).first?.entier("vues") ?? (recente ? 0 : nil)
                try store.releve(r)
                guard let avant, let palier = Self.palier(avant: avant, apres: r.vues), let v = parId[r.video] else { continue }
                try store.fil(Evenement(id: "tiktok:palier:\(v.id):\(palier)", business: v.business, at: maintenant, type: .video,
                                        texte: "\(Self.libelle(palier)) vues pour " + (titre(v).map { "« \($0) »" } ?? "une vidéo de @\(v.compte)"),
                                        lien: v.url))
            }
            for p in profils { try store.releve(p) }
            for (id, a) in analyses where !a.estVide { try store.analyse(id, at: maintenant, a) }
            lignes = liste.videos.count + releves.count + profils.count + analyses.count
            guard let studio else { return }
            let b = studio.business
            // les 7 jours d'avant, exacts, pour le compte connecté ; TikTok coupe ses jours à minuit UTC
            let aujourdhui = Jour.cle(maintenant)
            let aujourdhuiUTC = String(maintenant.iso.prefix(10))
            for (i, vues) in studio.historique.enumerated() {
                guard let vues else { continue }
                try store.serie(b, Metrique.vuesTikTok, jour: Jour.decale(aujourdhuiUTC, jours: i - studio.historique.count), Double(vues))
                lignes += 1
            }
            if let vues = try Self.vuesGagnees(store, business: b, jour: aujourdhui, jusqua: maintenant) {
                try store.serie(b, Metrique.vuesTikTok, jour: aujourdhui, Double(vues))
                lignes += 1
            }
            if let ilYA7Jours = Jour.calendrier.date(byAdding: .day, value: -7, to: maintenant),
               let vues = try Self.vuesGagnees(store, business: b, jour: Jour.cle(ilYA7Jours), jusqua: ilYA7Jours) {
                try store.serie(b, Metrique.vuesTikTokJ7, jour: aujourdhui, Double(vues))
                lignes += 1
            }
        }
        if !echecs.isEmpty { throw SourceErreur.format("\(echecs.count) échecs, dont \(echecs[0])") }
        if let sansStudio { throw SourceErreur.nonConfigure(sansStudio) }
        return lignes
    }

    // MARK: requêtes

    /// Une requête à l'API interne de TikTok Studio, celle qu'appelle la page Analytics.
    static func requete(_ demandes: [[String: Any]], referer: String, cookie: String) throws -> URLRequest {
        var u = URLComponents(string: "https://www.tiktok.com/aweme/v2/data/insight/")!
        u.queryItems = [.init(name: "aid", value: "1988"), .init(name: "app_name", value: "tiktok_creator_center"),
                        .init(name: "device_platform", value: "web_pc"), .init(name: "tz_name", value: "Europe/Paris"),
                        .init(name: "type_requests", value: String(decoding: try JSONSerialization.data(withJSONObject: demandes), as: UTF8.self))]
        return try HTTP.requete(u.string ?? "", entetes: ["Cookie": cookie, "Referer": referer, "User-Agent": HTTP.navigateur])
    }

    /// Le nom du compte connecté dans Safari : seules ses vidéos ont des stats.
    static func compteSession(_ cookie: String, _ http: HTTP) async throws -> String {
        let o = try await http.objet(HTTP.requete(
            "https://www.tiktok.com/passport/web/account/info/?aid=1988&app_name=tiktok_creator_center&device_platform=web_pc",
            entetes: ["Cookie": cookie, "Referer": "\(analytics)/overview", "User-Agent": HTTP.navigateur]))
        guard let nom = (o["data"] as? [String: Any])?["username"] as? String, !nom.isEmpty else {
            throw SourceErreur.format("session TikTok de Safari expirée, se reconnecter sur tiktok.com dans Safari")
        }
        return nom
    }

    // MARK: décodage

    /// Les compteurs d'un compte et son avatar, lus dans le JSON de sa page publique.
    static func profil(_ page: Data, compte: String, at: Date) throws -> (ReleveCompte, avatar: String?) {
        let html = String(decoding: page, as: UTF8.self)
        guard let debut = html.range(of: #"id="__UNIVERSAL_DATA_FOR_REHYDRATION__""#),
              let ouvre = html.range(of: ">", range: debut.upperBound..<html.endIndex),
              let ferme = html.range(of: "</script>", range: ouvre.upperBound..<html.endIndex),
              let o = try? JSONSerialization.jsonObject(with: Data(html[ouvre.upperBound..<ferme.lowerBound].utf8)) as? [String: Any],
              let info = ((o["__DEFAULT_SCOPE__"] as? [String: Any])?["webapp.user-detail"] as? [String: Any])?["userInfo"] as? [String: Any],
              let stats = info["stats"] as? [String: Any] else {
            throw SourceErreur.format("page de profil sans compteurs")
        }
        let user = info["user"] as? [String: Any]
        return (ReleveCompte(compte: compte, at: at, abonnes: stats["followerCount"] as? Int, videos: stats["videoCount"] as? Int,
                             likes: (stats["heartCount"] as? Int) ?? (stats["heart"] as? Int)),
                (user?["avatarMedium"] as? String) ?? (user?["avatarThumb"] as? String))
    }

    /// La réponse porte les types temps réel : sinon TikTok ne les avait pas encore prêts.
    static func complete(_ reponse: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: reponse) as? [String: Any])?["realtime_total_video_views"] != nil
    }

    /// La valeur d'un type quand TikTok l'a calculée (`status` 0) : `{status, value}`, ou sous `value` pour un `_realtime`.
    static func champ(_ o: [String: Any], _ cle: String) -> Any? {
        guard var c = o[cle] as? [String: Any] else { return nil }
        if c["status"] == nil, let v = c["value"] as? [String: Any] { c = v }
        return (c["status"] as? Int) == 0 ? c["value"] : nil
    }

    /// Le relevé d'une vidéo dans une réponse `insight`.
    static func releve(_ reponse: Data, video: String, at: Date) throws -> Releve {
        let o = try objet(reponse)
        guard let stats = (o["video_info"] as? [String: Any])?["statistics"] as? [String: Any],
              let vues = stats["play_count"] as? Int else {
            throw SourceErreur.format("insight : pas de statistiques")
        }
        return Releve(video: video, at: at, vues: vues, likes: stats["digg_count"] as? Int,
                      commentaires: stats["comment_count"] as? Int, partages: stats["share_count"] as? Int,
                      enregistrements: stats["collect_count"] as? Int,
                      watchMoyenS: champ(o, "video_per_duration_realtime") as? Double,
                      completion: champ(o, "video_finish_rate_realtime") as? Double,
                      abonnes: champ(o, "realtime_new_followers") as? Int)
    }

    /// Ce que la page Analytics d'une vidéo montre au-delà des compteurs : rétention, sources, public.
    static func analyse(_ reponse: Data) throws -> Analyse {
        let o = try objet(reponse)
        func parts(_ v: Any?) -> [Analyse.Part] {
            ((v as? [[String: Any]]) ?? []).compactMap { p in
                guard let nom = p["key"] as? String, let part = p["value"] as? Double else { return nil }
                return Analyse.Part(nom: nom, part: part)
            }
        }
        let courbe = (((o["video_retention_rate_realtime"] as? [String: Any])?["value"] as? [String: Any])?["list"] as? [[String: Any]]) ?? []
        let pays = (((o["video_viewer_location_percent_realtime"] as? [String: Any])?["value"] as? [String: Any])?["country_percent_list"]
            as? [[String: Any]]) ?? []
        return Analyse(
            watchTotalS: champ(o, "video_total_duration_realtime") as? Double,
            spectateurs: champ(o, "video_uv") as? Int,
            nouveaux: champ(o, "video_viewer_new_viewer_percent") as? Double,
            abonnesPart: champ(o, "video_viewer_follower_percent_realtime") as? Double,
            retention: courbe.compactMap { p in (p["timestamp"] as? String).flatMap(Double.init).map { ($0, p["value"] as? Double) } }
                .sorted { $0.0 < $1.0 }.compactMap(\.1),
            sources: parts(champ(o, "video_traffic_source_percent_realtime")),
            recherches: parts(champ(o, "item_search_terms")),
            ages: parts(champ(o, "video_viewer_age_percent_realtime")),
            pays: pays.compactMap { p in
                guard let nom = p["country_name"] as? String, let part = p["country_vv_percent"] as? Double else { return nil }
                return Analyse.Part(nom: nom, part: part)
            },
            vuesParJour: ((o["video_vv_history_7d"] as? [[String: Any]]) ?? []).compactMap { ($0["status"] as? Int) == 0 ? $0["value"] as? Int : nil })
    }

    /// Une réponse `insight` réussie.
    private static func objet(_ reponse: Data) throws -> [String: Any] {
        guard let o = try? JSONSerialization.jsonObject(with: reponse) as? [String: Any] else {
            throw SourceErreur.format("insight : pas un objet JSON")
        }
        guard (o["status_code"] as? Int) == 0 else {
            throw SourceErreur.format("insight : \(o["status_msg"] as? String ?? "refus") (status \(o["status_code"] as? Int ?? -1))")
        }
        return o
    }

    /// Les vues du compte jour par jour dans une réponse `vv_history`, la dernière = hier ; `nil` pour un jour pas encore calculé.
    static func historique(_ reponse: Data) throws -> [Int?] {
        guard let o = try? JSONSerialization.jsonObject(with: reponse) as? [String: Any], (o["status_code"] as? Int) == 0,
              let jours = o["vv_history"] as? [[String: Any]] else {
            throw SourceErreur.format("vv_history : \(String(decoding: reponse.prefix(200), as: UTF8.self))")
        }
        return jours.map { ($0["status"] as? Int) == 0 ? $0["value"] as? Int : nil }
    }

    // MARK: calculs

    /// Vues gagnées par les vidéos du business le `jour`, de minuit à `jusqua`, d'après les relevés.
    /// Départ d'une vidéo : son dernier relevé d'avant minuit, 0 si elle est sortie ce jour-là, sinon son premier relevé du jour.
    /// `nil` sans aucun relevé ce jour-là avant `jusqua`.
    static func vuesGagnees(_ store: Store, business: String, jour: String, jusqua: Date) throws -> Int? {
        guard let minuit = Jour.date(jour) else { return nil }
        let lignes = try store.db.query("""
            select v.publiee_le,
                (select vues from video_releve where video = v.id and at >= ?1 and at <= ?2 order by at desc limit 1) as fin,
                (select vues from video_releve where video = v.id and at >= ?1 and at <= ?2 order by at limit 1) as premier,
                (select vues from video_releve where video = v.id and at < ?1 order by at desc limit 1) as veille
            from video v where v.business = ?3 and v.plateforme = 'tiktok'
            """, [minuit, jusqua, business])
        var total: Int?
        for l in lignes {
            guard let fin = l.entier("fin") else { continue }
            let sortieCeJour = (l.date("publiee_le") ?? .distantPast) >= minuit
            let depart = l.entier("veille") ?? (sortieCeJour ? 0 : l.entier("premier") ?? fin)
            total = (total ?? 0) + max(0, fin - depart)
        }
        return total
    }

    /// Le plus haut palier franchi entre deux relevés.
    static func palier(avant: Int, apres: Int) -> Int? {
        paliers.last { avant < $0 && $0 <= apres }
    }

    static func libelle(_ palier: Int) -> String {
        palier == 1_000_000 ? "1 million de" : palier.formatted(.number.locale(Locale(identifier: "fr_FR")))
    }

    /// Le titre de la fiche, sinon le début de la légende sans les hashtags.
    static func titre(legende: String?, fiche: String?) -> String? {
        if let fiche, !fiche.isEmpty { return fiche }
        let mots = (legende ?? "").split(whereSeparator: \.isWhitespace).filter { !$0.hasPrefix("#") }.joined(separator: " ")
        guard !mots.isEmpty else { return nil }
        return mots.count > 60 ? mots.prefix(59) + "…" : mots
    }
}
