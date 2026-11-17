import Foundation

/// Rangs top 200 de nos apps et de celles des potes, notes de nos apps. Voir docs/sources/classements-itunes.md.
struct Classements: Source {
    let id = "classements"
    let nom = "Classements"
    let cadence: TimeInterval = 3 * 3600

    /// Storefront de chaque pays, pour l'en-tête `X-Apple-Store-Front`. Un pays absent coupe la source.
    static let storefronts: [String: Int] = [
        "fr": 143442, "es": 143454, "be": 143446, "us": 143441, "gb": 143444,
        "de": 143443, "it": 143450, "ch": 143459, "ca": 143455,
    ]
    /// Les listes de viewTop par leur `id` (le `popId`), le même dans tous les pays. Les titres, eux, sont traduits.
    static let popIds: [String: Liste] = ["27": .gratuit, "30": .payant, "38": .recettes]
    static let fluxRSS: [Liste: String] = [
        .gratuit: "topfreeapplications", .payant: "toppaidapplications", .recettes: "topgrossingapplications",
    ]
    static let toutesCategories = 36
    /// Catégories App Store, noms de la page viewTop française.
    static let genres: [Int: String] = [
        36: "Toutes catégories", 6000: "Économie et entreprise", 6001: "Météo", 6002: "Utilitaires", 6003: "Voyages",
        6004: "Sports", 6005: "Réseaux sociaux", 6006: "Références", 6007: "Productivité", 6008: "Photo et vidéo",
        6009: "Actualités", 6010: "Navigation", 6011: "Musique", 6012: "Style de vie", 6013: "Forme et santé",
        6014: "Jeux", 6015: "Finance", 6016: "Divertissement", 6017: "Éducation", 6018: "Livres", 6020: "Médecine",
        6021: "Journaux et magazines", 6023: "Cuisine et boissons", 6024: "Shopping", 6026: "Outils de développement",
        6027: "Graphisme et design",
    ]
    static let taille = 200
    /// Places gagnées ou perdues qui font une ligne du fil.
    static let seuil = 20
    static let pause: Duration = .milliseconds(500)

    /// Les trois listes d'un pays et d'une catégorie, ids dans l'ordre du classement.
    struct Top {
        var pays: String
        var genre: Int
        var listes: [Liste: [String]]
        /// Lu dans les flux RSS (top 100) faute de viewTop : pas de fil.
        var rss = false
    }

    func collecte(_ ctx: Contexte) async throws -> Int {
        let at = Date.now
        guard let principal = Self.paysPrincipal(ctx.businesses) else {
            throw SourceErreur.nonConfigure("aucun business n'a de pays")
        }
        var pays: [(code: String, storefront: Int)] = []
        for code in ctx.businesses.flatMap(\.config.pays) where !pays.contains(where: { $0.code == code }) {
            guard let storefront = Self.storefronts[code] else {
                throw SourceErreur.nonConfigure("pays \(code) sans storefront connu, à ajouter à Classements.storefronts")
            }
            pays.append((code, storefront))
        }
        let nos = ctx.businesses.compactMap { b in
            b.config.appStoreId.map { (business: b, app: $0, pays: b.config.pays.first ?? principal) }
        }
        let potes = try ctx.store.appsSuivies().filter { $0.business == nil }
        guard !nos.isEmpty || !potes.isEmpty else { throw SourceErreur.nonConfigure("aucune app à suivre") }

        // Nos apps dans le premier pays de leur business, celles des potes dans le premier pays suivi.
        var aLire: [String: [String]] = [:]
        for n in nos { aLire[n.pays, default: []].append(n.app) }
        if !potes.isEmpty { aLire[principal, default: []] += potes.map(\.id) }
        var applis: [String: Appli] = [:]
        for (code, ids) in aLire.sorted(by: { $0.key < $1.key }) {
            for debut in stride(from: 0, to: ids.count, by: 100) {
                for a in try await Self.lookup(Array(ids[debut..<min(debut + 100, ids.count)]), pays: code, http: ctx.http) {
                    applis[a.id] = a
                }
            }
        }
        var notres: [(business: Business, appli: Appli)] = []
        for n in nos {
            guard var a = applis[n.app] else {
                throw SourceErreur.format("\(n.business.nom) : app \(n.app) absente de l'App Store \(n.pays.uppercased())")
            }
            a.business = n.business.id
            applis[n.app] = a
            notres.append((n.business, a))
        }

        let genres = Set(nos.map(\.business.config.genre) + applis.values.compactMap(\.genre) + potes.compactMap(\.genre)
                         + [Self.toutesCategories]).sorted()
        var tops: [Top] = []
        var repli: [String] = []
        for p in pays {
            for g in genres {
                if !tops.isEmpty { try await Task.sleep(for: Self.pause) }
                do {
                    tops.append(Top(pays: p.code, genre: g, listes: try await Self.viewTop(storefront: p.storefront, genre: g, http: ctx.http)))
                } catch SourceErreur.format(_) {
                    tops.append(Top(pays: p.code, genre: g, listes: try await Self.rss(pays: p.code, genre: g, http: ctx.http), rss: true))
                    repli.append("\(Self.nomGenre(g)) \(Self.nomPays(p.code))")
                }
            }
        }

        let icones = await Miniatures.telecharger(Self.icones(Array(applis.values)), ctx.http)
        let suivies = notres.map(\.appli.id) + potes.map(\.id)
        var lignes = 0
        try ctx.store.lot {
            for a in applis.values {
                try ctx.store.app(a)
                lignes += 1
            }
            for (b, a) in notres {
                try ctx.store.suivre(a.id, true)
                if let note = a.note {
                    try ctx.store.serie(b.id, Metrique.note, jour: Jour.cle(at), note)
                    lignes += 1
                }
                try ctx.store.serie(b.id, Metrique.nbNotes, jour: Jour.cle(at), Double(a.nbNotes ?? 0))
                lignes += 1
                for e in try fil(app: a.id, business: b.id, tops: tops, at: at, store: ctx.store) {
                    if try ctx.store.fil(e) { lignes += 1 }
                }
            }
            for top in tops {
                for (liste, ids) in top.listes {
                    for app in suivies {
                        guard let i = ids.firstIndex(of: app) else { continue }
                        try ctx.store.rang(app: app, pays: top.pays, genre: top.genre, liste: liste, at: at, position: i + 1)
                        lignes += 1
                    }
                }
            }
        }
        guard repli.isEmpty else {
            throw SourceErreur.format("viewTop sans listes, repli RSS top 100 pour \(repli.joined(separator: ", "))")
        }
        if let e = icones.first { throw SourceErreur.format("\(icones.count) icônes en échec, dont \(e)") }
        return lignes
    }

    /// Les icônes des apps à mettre en cache (Miniatures.swift), pour que l'interface les montre sans réseau.
    static func icones(_ applis: [Appli]) -> [String: String] {
        Dictionary(applis.compactMap { a in a.icone.map { (Miniatures.icone(a.id), $0) } }, uniquingKeysWith: { a, _ in a })
    }

    /// Le fil d'une de nos apps : entrée dans une liste, sortie, ou au moins `seuil` places gagnées ou perdues
    /// depuis le passage précédent. Rien au premier passage ni pour une liste lue en RSS.
    func fil(app: String, business: String, tops: [Top], at: Date, store: Store) throws -> [Evenement] {
        guard let avant = try passagePrecedent(store, at) else { return [] }
        var positions: [String: Int] = [:]
        for l in try store.db.query("select pays, genre, liste, position from rang where app = ? and at = ?", [app, avant]) {
            positions["\(l.texte("pays") ?? ""):\(l.entier("genre") ?? 0):\(l.texte("liste") ?? "")"] = l.entier("position")
        }
        var evenements: [Evenement] = []
        for top in tops where !top.rss {
            for liste in Liste.allCases {
                guard let ids = top.listes[liste] else { continue }
                let cle = "\(top.pays):\(top.genre):\(liste.rawValue)"
                let lieu = "en \(liste.rawValue), \(Self.nomGenre(top.genre)) \(Self.nomPays(top.pays))"
                let maintenant = ids.firstIndex(of: app).map { $0 + 1 }
                let texte: String
                // Une sortie porte le `at` où l'app a été vue la dernière fois : la même sortie ne revient pas.
                var quand = at.iso
                switch (positions[cle], maintenant) {
                case (nil, let m?):
                    texte = "\(Self.place(m)) \(lieu) (entrée)"
                case (let a?, nil):
                    texte = "Hors top \(Self.taille) \(lieu) (était \(Self.place(a)))"
                    quand = avant
                case (let a?, let m?) where abs(a - m) >= Self.seuil:
                    texte = "\(Self.place(m)) \(lieu) (\(a > m ? "+" : "-")\(abs(a - m)))"
                default:
                    continue
                }
                evenements.append(Evenement(id: "\(id):\(app):\(cle):\(quand)", business: business, at: at, type: .rang,
                                            texte: texte, lien: "https://apps.apple.com/\(top.pays)/app/id\(app)"))
            }
        }
        return evenements
    }

    /// Le `at` du passage précédent dans `rang`. Nil au premier passage, ou si le précédent a fini en repli RSS :
    /// ses rangs s'arrêtent à 100, la comparaison inventerait des entrées.
    private func passagePrecedent(_ store: Store, _ at: Date) throws -> String? {
        guard let avant = try store.db.query("select max(at) as at from rang where at < ?", [at]).first?.texte("at") else {
            return nil
        }
        if let dernier = try store.dernierPassage(id), dernier.etat == .erreur, avant >= dernier.debut.iso { return nil }
        return avant
    }

    // MARK: apps des potes

    /// L'id App Store d'une saisie de l'écran Apps de potes : `6770304361` ou un lien `https://apps.apple.com/…/id6770304361`.
    static func idApp(_ saisie: String) -> String? {
        let s = saisie.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.wholeMatch(of: /\d+/) != nil { return s }
        return s.firstMatch(of: /\/id(\d+)/).map { String($0.1) }
    }

    /// Ajoute une app de pote : ses détails dans le premier pays suivi, puis suivie. Ses rangs arrivent au passage suivant.
    static func ajouterApp(_ id: String, store: Store, http: HTTP) async throws -> Appli {
        guard let pays = paysPrincipal(try store.businesses()) else {
            throw SourceErreur.nonConfigure("aucun business n'a de pays")
        }
        guard let appli = try await lookup([id], pays: pays, http: http).first else {
            throw SourceErreur.format("aucune app \(id) sur l'App Store \(pays.uppercased())")
        }
        try store.lot {
            try store.app(appli)
            try store.suivre(id, true)
        }
        if let e = await Miniatures.telecharger(icones([appli]), http).first {
            throw SourceErreur.format("\(appli.nom) suivie, sans son icône : \(e)")
        }
        return appli
    }

    /// Le premier pays du premier business qui en a : celui de la note et des apps des potes.
    static func paysPrincipal(_ businesses: [Business]) -> String? {
        businesses.lazy.flatMap(\.config.pays).first
    }

    // MARK: iTunes

    private static func viewTop(storefront: Int, genre: Int, http: HTTP) async throws -> [Liste: [String]] {
        let r = try HTTP.requete("https://itunes.apple.com/WebObjects/MZStore.woa/wa/viewTop?genreId=\(genre)&popId=27",
                                 entetes: ["X-Apple-Store-Front": "\(storefront),32"])
        return try listes(String(decoding: try await http.donnees(r), as: UTF8.self))
    }

    /// Les listes de la page viewTop : le JSON `its.serverData`, `pageData.topChartsPageData.topCharts`.
    /// `selectedChart`, le doublon d'une des listes, est ignoré.
    static func listes(_ html: String) throws -> [Liste: [String]] {
        guard let debut = html.range(of: "its.serverData="),
              let fin = html.range(of: "</script>", range: debut.upperBound..<html.endIndex),
              let objet = try? JSONSerialization.jsonObject(with: Data(html[debut.upperBound..<fin.lowerBound].utf8)) as? [String: Any],
              let page = (objet["pageData"] as? [String: Any])?["topChartsPageData"] as? [String: Any],
              let charts = page["topCharts"] as? [[String: Any]] else {
            throw SourceErreur.format("viewTop sans pageData.topChartsPageData.topCharts")
        }
        var listes: [Liste: [String]] = [:]
        for c in charts {
            guard let pop = c["id"] as? String, let liste = popIds[pop], let ids = c["adamIds"] as? [String] else { continue }
            listes[liste] = Array(ids.prefix(taille))
        }
        guard listes.count == Liste.allCases.count else {
            throw SourceErreur.format("viewTop : \(listes.count) listes sur \(Liste.allCases.count)")
        }
        return listes
    }

    private static func rss(pays: String, genre: Int, http: HTTP) async throws -> [Liste: [String]] {
        var listes: [Liste: [String]] = [:]
        for liste in Liste.allCases {
            try await Task.sleep(for: pause)
            let r = try HTTP.requete("https://itunes.apple.com/\(pays)/rss/\(fluxRSS[liste] ?? "")/limit=100/genre=\(genre)/json")
            listes[liste] = try listeRSS(try await http.donnees(r))
        }
        return listes
    }

    /// Les ids d'un flux RSS, dans l'ordre. Une seule entrée arrive en objet, pas en tableau.
    static func listeRSS(_ data: Data) throws -> [String] {
        guard let objet = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = objet["feed"] as? [String: Any] else {
            throw SourceErreur.format("flux RSS sans feed")
        }
        let entrees = feed["entry"] as? [[String: Any]] ?? (feed["entry"] as? [String: Any]).map { [$0] } ?? []
        return entrees.compactMap { (($0["id"] as? [String: Any])?["attributes"] as? [String: Any])?["im:id"] as? String }
    }

    private static func lookup(_ ids: [String], pays: String, http: HTTP) async throws -> [Appli] {
        let r = try HTTP.requete("https://itunes.apple.com/lookup?id=\(ids.joined(separator: ","))&country=\(pays)")
        return try applis(try await http.donnees(r))
    }

    private struct Lookup: Decodable {
        let results: [Resultat]

        struct Resultat: Decodable {
            let trackId: Int?
            let trackName: String?
            let artistName: String?
            let artworkUrl100: String?
            let artworkUrl512: String?
            let primaryGenreId: Int?
            let averageUserRating: Double?
            let userRatingCount: Int?
            let version: String?
        }
    }

    /// Les apps d'une réponse `lookup`, sans `business`.
    static func applis(_ data: Data) throws -> [Appli] {
        let reponse: Lookup
        do {
            reponse = try JSONDecoder().decode(Lookup.self, from: data)
        } catch {
            throw SourceErreur.format("lookup : \(error)")
        }
        return reponse.results.compactMap { r in
            guard let id = r.trackId, let nom = r.trackName else { return nil }
            return Appli(id: String(id), nom: nom, editeur: r.artistName, icone: r.artworkUrl512 ?? r.artworkUrl100,
                         genre: r.primaryGenreId, note: r.averageUserRating, nbNotes: r.userRatingCount, version: r.version)
        }
    }

    // MARK: textes

    static func place(_ n: Int) -> String { n == 1 ? "1re" : "\(n)e" }

    static func nomGenre(_ genre: Int) -> String { genres[genre] ?? "catégorie \(genre)" }

    static func nomPays(_ code: String) -> String {
        Locale(identifier: "fr_FR").localizedString(forRegionCode: code.uppercased()) ?? code.uppercased()
    }
}
