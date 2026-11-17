import Foundation

/// Voir docs/sources/instagram.md.
struct Instagram: Source {
    let id = "instagram"
    let nom = "Instagram"
    let cadence: TimeInterval = 3 * 3600
    /// Des appels refusés toutes les 10 minutes entretiennent le blocage d'Instagram.
    let reprise: TimeInterval = 3 * 3600

    static let site = "https://www.instagram.com"
    /// L'id de l'app web d'Instagram, que l'API interne exige.
    static let appWeb = "936619743392459"
    /// La session refusée, avec ce qu'Instagram a renvoyé, sans jamais citer le corps.
    static func refusee(_ raison: String) -> SourceErreur {
        .nonConfigure("session Instagram de Safari refusée (\(raison)), se reconnecter sur instagram.com dans Safari")
    }

    struct Profil {
        var uid: String
        var releve: ReleveCompte
        var avatar: String?
    }

    func collecte(_ ctx: Contexte) async throws -> Int {
        let store = ctx.store
        let maintenant = Date.now
        let suivis = Set(ctx.businesses.map(\.id))
        let comptes = try store.comptes().filter { $0.plateforme == .instagram && $0.actif && suivis.contains($0.business) }
        guard !comptes.isEmpty else { throw SourceErreur.nonConfigure("aucun compte Instagram suivi, en ajouter dans Vidéos") }
        let cookies = try Safari.cookies("instagram.com", requis: "sessionid")
        let cookie = cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        func lire(_ chemin: String, _ c: Compte) async throws -> Data {
            try await Self.appel(HTTP.requete(Self.site + chemin, entetes: [
                "User-Agent": HTTP.safari, "Cookie": cookie, "X-IG-App-ID": Self.appWeb,
                "X-CSRFToken": cookies["csrftoken"] ?? "", "Referer": c.plateforme.profil(c.handle),
                "X-Requested-With": "XMLHttpRequest", "X-ASBD-ID": "359341",
                "Accept": "*/*", "Accept-Language": "fr-FR,fr;q=0.9",
            ]), ctx.http)
        }

        var echecs: [String] = []
        var liste = YtDlp.Liste()
        var profils: [ReleveCompte] = []
        for c in comptes {
            do {
                let p = try Self.profil(await lire("/api/v1/users/web_profile_info/?username=\(c.handle)", c), compte: c, at: maintenant)
                profils.append(p.releve)
                if let avatar = p.avatar { liste.images[Miniatures.avatar(c.id)] = avatar }
                let l = try Self.fil(await lire("/api/v1/feed/user/\(p.uid)/?count=33", c), business: c.business,
                                     compte: c.handle, at: maintenant)
                liste.videos += l.videos
                liste.releves += l.releves
                liste.images.merge(l.images) { a, _ in a }
            } catch SourceErreur.nonConfigure(let m) {
                throw SourceErreur.nonConfigure(m)
            } catch {
                echecs.append("@\(c.handle) : \(error.localizedDescription)")
            }
        }
        echecs += await Miniatures.telecharger(liste.images, ctx.http)

        try store.lot {
            for v in liste.videos {
                try store.video(v)
                guard let publiee = v.publieeLe else { continue }
                try store.fil(Evenement(id: "instagram:pub:\(v.id)", business: v.business, at: publiee, type: .video,
                                        texte: "Nouvelle vidéo sur Instagram @\(v.compte)" + (v.legende.map { " : \($0.prefix(60))" } ?? ""),
                                        lien: v.url))
            }
            for r in liste.releves { try store.releve(r) }
            for p in profils { try store.releve(p) }
        }
        if !echecs.isEmpty { throw SourceErreur.format("\(echecs.count) échecs, dont \(echecs[0])") }
        return liste.videos.count + liste.releves.count + profils.count
    }

    /// Un appel à l'API interne : une session refusée devient « reconnecte-toi », et l'erreur ne cite jamais le corps.
    /// Une session périmée reçoit un 404 sans JSON, comme un 401 ou un 403.
    static func appel(_ requete: URLRequest, _ http: HTTP) async throws -> Data {
        do {
            return try await http.donnees(requete)
        } catch SourceErreur.http(let code, let debut) where [401, 403, 404].contains(code) {
            // la page d'erreur dit si Instagram a reconnu la session
            throw refusee("HTTP \(code)" + (debut.contains("not-logged-in") ? ", session pas reconnue ; " + Safari.provenance("instagram.com", requis: "sessionid") : ""))
        } catch SourceErreur.http(let code, _) {
            throw SourceErreur.http(code, "instagram")
        }
    }

    /// `web_profile_info` : l'id du compte, ses abonnés, son nombre de publications et sa photo.
    static func profil(_ reponse: Data, compte: Compte, at: Date) throws -> Profil {
        let o = try objet(reponse)
        guard let u = (o["data"] as? [String: Any])?["user"] as? [String: Any], let uid = u["id"] as? String else {
            throw SourceErreur.format("Instagram @\(compte.handle) : profil introuvable")
        }
        func compteur(_ cle: String) -> Int? { (u[cle] as? [String: Any])?["count"] as? Int }
        return Profil(uid: uid, releve: ReleveCompte(compte: compte.id, at: at, abonnes: compteur("edge_followed_by"),
                                                     videos: compteur("edge_owner_to_timeline_media")),
                      avatar: (u["profile_pic_url_hd"] ?? u["profile_pic_url"]) as? String)
    }

    /// `feed/user` : les 33 dernières publications ; seules les vidéos (media_type 2) sont gardées.
    static func fil(_ reponse: Data, business: String, compte: String, at: Date) throws -> YtDlp.Liste {
        let o = try objet(reponse)
        guard let items = o["items"] as? [[String: Any]] else { throw SourceErreur.format("Instagram @\(compte) : pas de publications") }
        var l = YtDlp.Liste()
        for i in items where i["media_type"] as? Int == 2 {
            guard let code = i["code"] as? String else { continue }
            let id = Plateforme.instagram.idVideo(code)
            l.videos.append(Video(id: id, business: business, compte: compte,
                                  legende: (i["caption"] as? [String: Any])?["text"] as? String,
                                  publieeLe: (i["taken_at"] as? Double).map { Date(timeIntervalSince1970: $0) },
                                  dureeS: i["video_duration"] as? Double, url: Plateforme.instagram.lien(code, compte: compte),
                                  plateforme: .instagram))
            // ig_play_count : les lectures sur Instagram seul, sans celles du partage Facebook
            if let vues = (i["ig_play_count"] ?? i["play_count"] ?? i["view_count"]) as? Int {
                l.releves.append(Releve(video: id, at: at, vues: vues, likes: i["like_count"] as? Int,
                                        commentaires: i["comment_count"] as? Int))
            }
            let image = (((i["image_versions2"] as? [String: Any])?["candidates"] as? [[String: Any]])?.first)?["url"] as? String
            if let image { l.images[id] = image }
        }
        return l
    }

    /// Une réponse JSON de l'API ; la page de connexion à la place veut dire une session expirée.
    private static func objet(_ reponse: Data) throws -> [String: Any] {
        guard let o = try? JSONSerialization.jsonObject(with: reponse) as? [String: Any] else { throw refusee("réponse pas en JSON") }
        if o["require_login"] as? Bool == true { throw refusee("require_login") }
        return o
    }
}
