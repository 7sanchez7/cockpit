import Foundation

/// Voir docs/sources/facebook.md.
struct Facebook: Source {
    let id = "facebook"
    let nom = "Facebook"
    let cadence: TimeInterval = 3 * 3600

    static let suite = "https://business.facebook.com"
    /// La requête du tableau Contenu de Business Suite (Statistiques → Contenu).
    static let requeteTable = "BizWebInsightsContentOrganicTableQueryRendererQuery"
    static let docTable = "40040115705602765"

    struct Jetons {
        var dtsg: String
        var lsd: String
        var rev: String
    }

    struct Table {
        var videos: [Video] = []
        var releves: [Releve] = []
        var analyses: [String: Analyse] = [:]
        /// Id de vidéo, ou clé d'avatar, → URL de l'image.
        var images: [String: String] = [:]
    }

    func collecte(_ ctx: Contexte) async throws -> Int {
        let store = ctx.store
        let maintenant = Date.now
        let suivis = Set(ctx.businesses.map(\.id))
        let comptes = try store.comptes().filter { $0.plateforme == .facebook && $0.actif && suivis.contains($0.business) }
        guard !comptes.isEmpty else { throw SourceErreur.nonConfigure("aucune Page Facebook suivie, en ajouter dans Vidéos") }
        let cookies = try Safari.cookies("facebook.com", requis: "c_user")
        let cookie = cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        let utilisateur = cookies["c_user"] ?? ""

        var echecs: [String] = []
        var table = Table()
        var profils: [ReleveCompte] = []
        for c in comptes {
            do {
                let page = try await Self.pageId(c.handle, cookie: cookie, ctx.http)
                let accueil = try await Self.page("\(Self.suite)/latest/home?asset_id=\(page)", cookie: cookie, ctx.http)
                if let abonnes = Self.nombre(apres: #""page_total_likes_or_followers":{"count":"#, dans: accueil) {
                    profils.append(ReleveCompte(compte: c.id, at: maintenant, abonnes: abonnes))
                }
                let reponse = try await Self.appel(Self.requete(page: page, utilisateur: utilisateur, jetons: Self.jetons(accueil),
                                                                cookie: cookie), ctx.http)
                let t = try Self.table(Self.objets(reponse), business: c.business, compte: c.handle, at: maintenant)
                table.videos += t.videos
                table.releves += t.releves
                table.analyses.merge(t.analyses) { a, _ in a }
                table.images.merge(t.images) { a, _ in a }
            } catch {
                echecs.append("\(c.handle) : \(error.localizedDescription)")
            }
        }
        echecs += await Miniatures.telecharger(table.images, ctx.http)
        echecs += await Miniatures.extrairePremieres(table.videos)

        try store.lot {
            for v in table.videos {
                try store.video(v)
                guard let publiee = v.publieeLe else { continue }
                try store.fil(Evenement(id: "facebook:pub:\(v.id)", business: v.business, at: publiee, type: .video,
                                        texte: "Nouvelle vidéo sur Facebook \(v.compte)" + (v.legende.map { " : \($0.prefix(60))" } ?? ""),
                                        lien: v.url))
            }
            for r in table.releves { try store.releve(r) }
            for (id, a) in table.analyses where !a.estVide { try store.analyse(id, at: maintenant, a) }
            for p in profils { try store.releve(p) }
        }
        if !echecs.isEmpty { throw SourceErreur.format("\(echecs.count) échecs, dont \(echecs[0])") }
        return table.videos.count + table.releves.count + table.analyses.count + profils.count
    }

    // MARK: requêtes

    /// Un appel à Facebook dont l'erreur ne cite pas le corps : il peut porter des jetons de session.
    static func appel(_ requete: URLRequest, _ http: HTTP) async throws -> Data {
        do {
            return try await http.donnees(requete)
        } catch SourceErreur.http(let code, _) {
            throw SourceErreur.http(code, "facebook")
        }
    }

    /// Une page HTML ouverte comme par le navigateur, avec la session de Safari.
    static func page(_ url: String, cookie: String, _ http: HTTP) async throws -> String {
        String(decoding: try await appel(HTTP.requete(url, entetes: [
            "User-Agent": HTTP.navigateur, "Cookie": cookie, "Accept-Language": "fr-FR,fr;q=0.9",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Sec-Fetch-Dest": "document", "Sec-Fetch-Mode": "navigate", "Sec-Fetch-Site": "none", "Sec-Fetch-User": "?1",
            "Upgrade-Insecure-Requests": "1",
        ]), http), as: UTF8.self)
    }

    /// L'id de la Page : le handle s'il n'a que des chiffres, sinon lu sur sa page publique.
    static func pageId(_ handle: String, cookie: String, _ http: HTTP) async throws -> String {
        if handle.allSatisfy(\.isNumber) { return handle }
        let html = try await page("https://www.facebook.com/\(handle)", cookie: cookie, http)
        guard let id = texte(apres: #""delegate_page_id":""#, dans: html) ?? nombre(apres: "asset_id=", dans: html).map(String.init) else {
            throw SourceErreur.format("Page \(handle) introuvable, ou session Facebook de Safari expirée")
        }
        return id
    }

    /// La requête du tableau Contenu : les publications des 90 derniers jours et leurs statistiques.
    static func requete(page: String, utilisateur: String, jetons: Jetons, cookie: String) throws -> URLRequest {
        let variables: [String: Any] = [
            "callerID": "BIZWEB_INSIGHTS_ORGANIC_CONTENT", "count": 100, "ids": [page], "initialFilters": [], "skip": false,
            "timeRange": ["type": "LAST_90D"],
            "__relay_internal__pv__shouldFetchAssociatedAdsInforelayprovider": false,
            "__relay_internal__pv__shouldFetchAMPostPreviewrelayprovider": false,
            "__relay_internal__pv__shouldFetchEPAPostVariantImagerelayprovider": false,
        ]
        let champs = [
            ("av", utilisateur), ("__user", utilisateur), ("__a", "1"), ("__comet_req", "11"), ("fb_dtsg", jetons.dtsg),
            ("lsd", jetons.lsd), ("__rev", jetons.rev), ("fb_api_caller_class", "RelayModern"),
            ("fb_api_req_friendly_name", requeteTable),
            ("variables", String(decoding: try JSONSerialization.data(withJSONObject: variables, options: .sortedKeys), as: UTF8.self)),
            ("server_timestamps", "true"), ("doc_id", docTable),
        ]
        var r = try HTTP.requete("\(suite)/api/graphql/", methode: "POST", entetes: [
            "User-Agent": HTTP.navigateur, "Cookie": cookie, "Accept": "*/*", "Content-Type": "application/x-www-form-urlencoded",
            "Origin": suite, "Referer": "\(suite)/latest/insights/content?asset_id=\(page)",
            "Sec-Fetch-Dest": "empty", "Sec-Fetch-Mode": "cors", "Sec-Fetch-Site": "same-origin",
            "X-FB-Friendly-Name": requeteTable, "X-FB-LSD": jetons.lsd, "X-ASBD-ID": "359341",
        ])
        let permis = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        r.httpBody = Data(champs.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: permis) ?? "")" }
            .joined(separator: "&").utf8)
        return r
    }

    // MARK: décodage

    /// Les jetons de la session, lus dans une page de Business Suite ; jamais journalisés.
    static func jetons(_ html: String) throws -> Jetons {
        guard let dtsg = texte(apres: #"["DTSGInitialData",[],{"token":""#, dans: html) ?? texte(apres: #""dtsg":{"token":""#, dans: html),
              let lsd = texte(apres: #"["LSD",[],{"token":""#, dans: html),
              let rev = nombre(apres: #""server_revision":"#, dans: html) ?? nombre(apres: #""__spin_r":"#, dans: html) else {
            throw SourceErreur.nonConfigure("session Facebook de Safari expirée, se reconnecter sur business.facebook.com dans Safari")
        }
        return Jetons(dtsg: dtsg, lsd: lsd, rev: String(rev))
    }

    /// Le texte entre `marque` et le guillemet suivant.
    static func texte(apres marque: String, dans html: String) -> String? {
        guard let r = html.range(of: marque) else { return nil }
        let reste = html[r.upperBound...]
        guard let fin = reste.firstIndex(of: "\""), fin > reste.startIndex else { return nil }
        return String(reste[..<fin])
    }

    /// Le nombre écrit juste après `marque`.
    static func nombre(apres marque: String, dans html: String) -> Int? {
        guard let r = html.range(of: marque) else { return nil }
        return Int(html[r.upperBound...].prefix { $0.isASCII && $0.isNumber })
    }

    /// Les objets JSON mis bout à bout d'une réponse graphql, après le préfixe `for (;;);` : un par morceau livré.
    static func objets(_ reponse: Data) throws -> [[String: Any]] {
        let o = [UInt8](reponse)
        let (ouvre, ferme, guillemet, barre) = (UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "\""), UInt8(ascii: "\\"))
        var objets: [[String: Any]] = []
        var profondeur = 0, debut = 0, chaine = false, echappe = false
        for (i, c) in o.enumerated() {
            if chaine {
                if echappe { echappe = false } else if c == barre { echappe = true } else if c == guillemet { chaine = false }
                continue
            }
            if c == guillemet && profondeur > 0 {
                chaine = true
            } else if c == ouvre {
                if profondeur == 0 { debut = i }
                profondeur += 1
            } else if c == ferme && profondeur > 0 {
                profondeur -= 1
                guard profondeur == 0 else { continue }
                guard let objet = try? JSONSerialization.jsonObject(with: Data(o[debut...i])) as? [String: Any] else {
                    throw SourceErreur.format("graphql : morceau illisible")
                }
                objets.append(objet)
            }
        }
        return objets
    }

    /// Les vidéos du tableau Contenu, avec leurs compteurs et leur analyse.
    static func table(_ objets: [[String: Any]], business: String, compte: String, at: Date) throws -> Table {
        let erreurs = objets.flatMap { ($0["errors"] as? [[String: Any]]) ?? [] }.compactMap { $0["message"] as? String }
        let lignes = objets.flatMap { o -> [[String: Any]] in
            let contenu = (((o["data"] as? [String: Any])?["tofu_unified_table"] as? [String: Any])?["content"] as? [String: Any])
            return ((contenu?["edges"] as? [[String: Any]]) ?? []).compactMap { $0["node"] as? [String: Any] }
        }
        if lignes.isEmpty, let e = erreurs.first { throw SourceErreur.format("graphql : \(e)") }

        var t = Table()
        for n in lignes {
            guard let brut = n["row_id"] as? String else { continue }
            let entete = n["header"] as? [String: Any]
            let champs = (n["fields"] as? [String: Any]) ?? [:]
            func m(_ cle: String) -> Double? {
                guard let r = (champs[cle] as? [String: Any])?["renderer"] as? [String: Any],
                      !((r["__typename"] as? String) ?? "").localizedCaseInsensitiveContains("error") else { return nil }
                return r["value_for_sort"] as? Double
            }
            guard ((entete?["content_type"] as? String) ?? "").contains("VIDEO") || m("video_play_time") != nil else { continue }
            let info = ((entete?["entity"] as? [String: Any])?["entity_info"] as? [String: Any]) ?? [:]
            let id = Plateforme.facebook.idVideo(brut)
            t.videos.append(Video(id: id, business: business, compte: compte, legende: info["title"] as? String,
                                  publieeLe: (info["created_at"] as? Double).map { Date(timeIntervalSince1970: $0) },
                                  url: Plateforme.facebook.lien(brut, compte: compte), plateforme: .facebook))
            if let image = (info["image_source"] as? [String: Any])?["uri"] as? String { t.images[id] = image }
            if let avatar = ((((info["owner"] as? [String: Any])?["entity_info"] as? [String: Any])?["image_source"]
                as? [String: Any])?["uri"] as? String) {
                t.images[Miniatures.avatar(Compte.id(.facebook, compte))] = avatar
            }
            guard let vues = m("views").map({ Int($0) }) else { continue }
            func entier(_ cle: String) -> Int? { m(cle).map { Int($0) } }
            t.releves.append(Releve(video: id, at: at, vues: vues, likes: entier("net_reactions"), commentaires: entier("net_comments"),
                                    partages: entier("shares"), enregistrements: entier("net_saves"),
                                    watchMoyenS: m("video_average_play_time").map { $0 / 1000 }, abonnes: entier("new_follows")))
            let jalons: [(String, String)] = [("3 s", "video_three_second_views"), ("1 min", "video_one_minute_views"),
                                              ("ThruPlay", "video_thruplays")]
            t.analyses[id] = Analyse(
                watchTotalS: m("video_play_time").map { $0 / 1000 }, spectateurs: entier("viewers"),
                jalons: vues > 0 ? jalons.compactMap { nom, cle in m(cle).map { Analyse.Part(nom: nom, part: $0 / Double(vues)) } } : [])
        }
        return t
    }
}
