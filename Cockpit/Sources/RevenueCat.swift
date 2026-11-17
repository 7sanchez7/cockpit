import Foundation

/// MRR, abonnés, essais, revenu, achats, fil ACHAT et paiement des installs convertis, par l'API v2 de RevenueCat
/// en lecture seule.
/// Voir docs/sources/revenuecat.md. Jamais l'API v1 `GET /subscribers/{id}` : elle crée le client qu'elle ne trouve pas.
struct RevenueCat: Source {
    let id = "revenuecat"
    let nom = "RevenueCat"
    let cadence: TimeInterval = 30 * 60

    static let base = "https://api.revenuecat.com/v2"
    static let nomCle = "REVENUECAT_SECRET_KEY_V2"
    /// Jours relus dans les graphiques : 90 au premier passage, puis les derniers qui se consolident.
    static let historique = 90
    static let relecture = 7
    /// Jours du revenu glissant, comme l'overview.
    static let fenetreRevenu = 28
    /// Achats cherchés au premier passage.
    static let premiersAchats: TimeInterval = 3 * 86_400
    /// Un essai dure au plus 7 jours : le premier paiement tombe au plus 8 jours après le début de l'abonnement.
    static let essaiMax: TimeInterval = 8 * 86_400
    /// Les convertis de la table `install` : lus une fois, puis relus toutes les 6 h tant que l'essai court ou qu'ils
    /// n'ont pas payé, sur les installs des 40 derniers jours ; au plus 500 par passage.
    static let paiementsParPassage = 500
    static let relecturePaiement: TimeInterval = 6 * 3600
    static let suiviPaiement = 40

    func collecte(_ ctx: Contexte) async throws -> Int {
        let dernier = try ctx.store.dernierSucces(id)
        var lignes = 0
        var configures = 0
        for b in ctx.businesses {
            let cle: String
            do {
                cle = try await ctx.secrets.valeur(Self.nomCle, b)
            } catch SourceErreur.nonConfigure {
                continue
            }
            configures += 1
            do {
                lignes += try await collecte(b, cle: cle, dernier: dernier, ctx)
            } catch {
                throw Self.nomme(error, b)
            }
        }
        guard configures > 0 else { throw SourceErreur.nonConfigure("aucun business avec \(Self.nomCle)") }
        return lignes
    }

    private func collecte(_ b: Business, cle: String, dernier: Date?, _ ctx: Contexte) async throws -> Int {
        func lire(_ chemin: String) async throws -> Data {
            try await ctx.http.donnees(HTTP.requete(Self.base + chemin, jeton: cle))
        }
        let projet = try Self.projet(try await lire("/projects"), nom: b.nom)
        let apercu = try Self.apercu(try await lire("/projects/\(projet)/metrics/overview"))
        let aujourdhui = Jour.aujourdhui
        let suivies = [Metrique.revenu28j, Metrique.revenu, Metrique.nouveauxClients].flatMap { m in [m] + Boutique.allCases.map { $0.metrique(m) } }
        let complet = try dernier != nil
            && !suivies.contains { try ctx.store.historiqueIncomplet(b.id, $0, jours: Self.historique, jusqua: aujourdhui) }
        let debut = Jour.decale(aujourdhui, jours: -(complet ? Self.relecture : Self.historique))
        func graphique(_ nom: String, depuis: String, segment: String = "store") async throws -> Data {
            try await lire("/projects/\(projet)/charts/\(nom)?resolution=0&start_date=\(depuis)&end_date=\(aujourdhui)&segment=\(segment)")
        }
        let g = Graphiques(mrr: try await graphique("mrr", depuis: debut), abonnes: try await graphique("actives", depuis: debut),
                           essais: try await graphique("trials", depuis: debut), achats: try await graphique("actives_new", depuis: debut),
                           revenu: try await graphique("revenue", depuis: Jour.decale(debut, jours: 1 - Self.fenetreRevenu)),
                           nouveaux: try await graphique("customers_new", depuis: debut, segment: "first_platform"))
        var points: [Point] = []
        for boutique in [nil] + Boutique.allCases.map(Optional.some) {
            points += try Self.points(g, apercu, boutique: boutique, depuis: debut, aujourdhui: aujourdhui)
        }
        try Self.ecrire(points, business: b.id, ctx.store)
        var lignes = points.count

        // Fil ACHAT : la v2 ne liste pas les transactions d'un projet. On part des comptes payants que la Function
        // de Roleo vient de relire (webhook RevenueCat) dans Firestore, puis on lit leurs abonnements récents.
        if let firebase = b.config.firebaseProject {
            let depuis = dernier.map { $0.addingTimeInterval(-2 * 3600) } ?? .now.addingTimeInterval(-Self.premiersAchats)
            let comptes = try await firestore(firebase, Self.requeteComptes(), ctx)
            for uid in try Self.comptesPayes(comptes, depuis: depuis) {
                let reponse: Data
                do {
                    reponse = try await lire("/projects/\(projet)/customers/\(uid)/subscriptions?limit=50")
                } catch SourceErreur.http(404, _) {
                    continue
                }
                for a in try Self.abonnements(reponse, depuis: depuis.addingTimeInterval(-Self.essaiMax)) {
                    let idFil = "\(id):achat:\(a.id)"
                    guard try ctx.store.db.query("select 1 from fil where id = ?", [idFil]).isEmpty else { continue }
                    let transactions = try await lire("/projects/\(projet)/subscriptions/\(a.id)/transactions?sort=purchased_at&direction=asc&limit=20")
                    guard let e = try Self.achat(idFil, a, transactions, business: b.id) else { continue }
                    if try ctx.store.fil(e) { lignes += 1 }
                }
            }
        }

        // Paiements : parmi les installs que PostHog a vus convertir, qui a vraiment payé.
        let clients = try ctx.store.clientsAVerifier(business: b.id, depuis: Jour.decale(aujourdhui, jours: -Self.suiviPaiement),
                                                     relu: .now.addingTimeInterval(-Self.relecturePaiement),
                                                     limite: Self.paiementsParPassage)
        for client in clients {
            guard let id = client.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(["-", "_"])) else { continue }
            let etat: EtatPaiement
            do {
                etat = try Self.paiement(try await lire("/projects/\(projet)/customers/\(id)/subscriptions?limit=50"))
            } catch SourceErreur.http(404, _) {
                etat = .inconnu
            }
            try ctx.store.paiement(business: b.id, client: client, etat, lu: .now)
            lignes += 1
        }
        return lignes
    }

    private func firestore(_ projet: String, _ requete: [String: Any], _ ctx: Contexte) async throws -> Data {
        let url = "https://firestore.googleapis.com/v1/projects/\(projet)/databases/(default)/documents:runQuery"
        return try await ctx.http.donnees(HTTP.requete(url, methode: "POST", jeton: try await ctx.gcloud.jeton(),
                                                       corps: requete, entetes: ["x-goog-user-project": projet]))
    }

    // MARK: décodage

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try d.decode(T.self, from: data)
        } catch {
            throw SourceErreur.format("\(T.self) : \(error)")
        }
    }

    /// L'id du projet RevenueCat : celui qui porte le nom du business, sinon le seul.
    static func projet(_ data: Data, nom: String) throws -> String {
        struct Reponse: Decodable { let items: [P]; struct P: Decodable { let id: String; let name: String } }
        let items = try decode(Reponse.self, data).items
        guard let p = items.first(where: { $0.name == nom }) ?? (items.count == 1 ? items.first : nil) else {
            throw SourceErreur.format("aucun projet RevenueCat nommé \(nom)")
        }
        return p.id
    }

    struct Apercu: Equatable {
        var mrr: Double
        var abonnes: Double
        var essais: Double
        var revenu28j: Double
    }

    static func apercu(_ data: Data) throws -> Apercu {
        struct Reponse: Decodable { let metrics: [M]; struct M: Decodable { let id: String; let value: Double } }
        let v = Dictionary(try decode(Reponse.self, data).metrics.map { ($0.id, $0.value) }, uniquingKeysWith: { a, _ in a })
        guard let mrr = v["mrr"], let abonnes = v["active_subscriptions"], let essais = v["active_trials"],
              let revenu = v["revenue"] else {
            throw SourceErreur.format("overview sans mrr, active_subscriptions, active_trials ou revenue")
        }
        return Apercu(mrr: mrr, abonnes: abonnes, essais: essais, revenu28j: revenu)
    }

    /// Un graphique à la journée : jour → (nom de la mesure → valeur). `cohort` est minuit UTC du jour, en secondes.
    /// Demandé avec `segment=store`, il se lit pour le total (`boutique` nil) ou pour un store, à 0 les jours où le store
    /// n'a pas de segment (Play n'en a qu'avec ses premières données).
    static func graphique(_ data: Data, boutique: Boutique? = nil) throws -> [String: [String: Double]] {
        struct Reponse: Decodable {
            let measures: [Mesure]
            let segments: [Segment]?
            let values: [Point]
            struct Mesure: Decodable { let displayName: String }
            struct Segment: Decodable { let displayName: String; let isTotal: Bool }
            struct Point: Decodable { let cohort: Double; let measure: Int; let segment: Int?; let value: Double? }
        }
        let r = try decode(Reponse.self, data)
        let segments = r.segments ?? []
        func lus(_ garde: (Int?) -> Bool) -> [String: [String: Double]] {
            var jours: [String: [String: Double]] = [:]
            for p in r.values where r.measures.indices.contains(p.measure) && garde(p.segment) {
                guard let v = p.value else { continue }
                jours[Jour.cle(Date(timeIntervalSince1970: p.cohort)), default: [:]][r.measures[p.measure].displayName] = v
            }
            return jours
        }
        let total = lus { i in i.map { segments.indices.contains($0) && segments[$0].isTotal } ?? true }
        guard let boutique else { return total }
        let part = lus { i in
            guard let i, segments.indices.contains(i), !segments[i].isTotal else { return false }
            return Self.boutique(segment: segments[i].displayName) == boutique
        }
        return total.reduce(into: [:]) { r, j in
            r[j.key] = Dictionary(uniqueKeysWithValues: j.value.keys.map { ($0, part[j.key]?[$0] ?? 0) })
        }
    }

    /// Le store d'un segment, par son nom affiché : `App Store` ou `iOS`, `Play Store` ou `Android` (`first_platform`,
    /// seul découpage des nouveaux clients) ; les autres segments sont ignorés.
    static func boutique(segment nom: String) -> Boutique? {
        let n = nom.lowercased()
        if n == "app store" || n == "ios" { return .appStore }
        return n.contains("play") || n == "android" ? .playStore : nil
    }

    /// Les six graphiques d'un passage, bruts : segmentés par store, les nouveaux clients par première plateforme.
    struct Graphiques {
        var mrr, abonnes, essais, achats, revenu, nouveaux: Data
    }

    /// Les points du total (`boutique` nil) ou d'un store, aux métriques suffixées (`mrr_brut.play_store`). L'overview
    /// ne se découpe pas : aujourd'hui, un store en prend la part qu'il a dans les graphiques, les stores somment au total.
    static func points(_ g: Graphiques, _ apercu: Apercu, boutique: Boutique?, depuis debut: String,
                       aujourdhui: String) throws -> [Point] {
        func series(_ b: Boutique?) throws -> (mrr: [String: Double], abonnes: [String: Double], essais: [String: Double],
                                               achats: [String: Double], revenu: [String: Double]) {
            (try mesure("MRR", try graphique(g.mrr, boutique: b)), try mesure("Actives", try graphique(g.abonnes, boutique: b)),
             try mesure("Active Trials", try graphique(g.essais, boutique: b)), try achats(try graphique(g.achats, boutique: b)),
             try mesure("Revenue", try graphique(g.revenu, boutique: b)))
        }
        let s = try series(boutique)
        var a = apercu
        if boutique != nil {
            let t = try series(nil)
            func part(_ store: [String: Double], _ total: [String: Double], _ jours: [String] = [aujourdhui]) -> Double {
                let d = jours.compactMap { total[$0] }.reduce(0, +)
                return d > 0 ? jours.compactMap { store[$0] }.reduce(0, +) / d : 0
            }
            a = Apercu(mrr: apercu.mrr * part(s.mrr, t.mrr), abonnes: apercu.abonnes * part(s.abonnes, t.abonnes),
                       essais: apercu.essais * part(s.essais, t.essais),
                       revenu28j: apercu.revenu28j * part(s.revenu, t.revenu, Jour.derniers(fenetreRevenu, jusqua: aujourdhui)))
        }
        let nouveaux = try mesure("New Customers", try graphique(g.nouveaux, boutique: boutique))
        let p = points(a, mrr: s.mrr, abonnes: s.abonnes, essais: s.essais, achats: s.achats, revenu: s.revenu,
                       revenu28j: revenus28j(s.revenu, depuis: debut, jusqua: aujourdhui), aujourdhui: aujourdhui)
            + nouveaux.map { Point(metrique: Metrique.nouveauxClients, jour: $0.key, valeur: $0.value) }
        guard let boutique else { return p }
        return p.map { Point(metrique: boutique.metrique($0.metrique), jour: $0.jour, valeur: $0.valeur) }
    }

    /// Une mesure jour par jour ; lève si RevenueCat l'a renommée.
    static func mesure(_ nom: String, _ graphique: [String: [String: Double]]) throws -> [String: Double] {
        let jours = graphique.compactMapValues { $0[nom] }
        guard jours.count == graphique.count else { throw SourceErreur.format("mesure « \(nom) » absente du graphique") }
        return jours
    }

    /// Nouveaux abonnements payés du jour (fins d'essai, offres, achats directs, retours), sans les changements de produit.
    static func achats(_ graphique: [String: [String: Double]]) throws -> [String: Double] {
        let total = try mesure("Total Paid Subscriptions", graphique)
        let changements = try mesure("Product Changes", graphique)
        return total.reduce(into: [:]) { r, j in r[j.key] = j.value - (changements[j.key] ?? 0) }
    }

    struct Point: Equatable {
        let metrique: String
        let jour: String
        let valeur: Double
    }

    /// Le revenu des 28 jours finissant à chaque jour de `debut` à la veille d'`aujourdhui`, quand le graphique les a tous.
    static func revenus28j(_ revenu: [String: Double], depuis debut: String, jusqua aujourdhui: String) -> [String: Double] {
        var sommes: [String: Double] = [:]
        var jour = debut
        while jour < aujourdhui {
            let fenetre = Jour.derniers(fenetreRevenu, jusqua: jour).compactMap { revenu[$0] }
            if fenetre.count == fenetreRevenu { sommes[jour] = fenetre.reduce(0, +) }
            jour = Jour.decale(jour, jours: 1)
        }
        return sommes
    }

    /// Les jours passés viennent des graphiques, aujourd'hui de l'overview ; `achats` et `revenu` du graphique jusqu'à
    /// aujourd'hui.
    static func points(_ apercu: Apercu, mrr: [String: Double], abonnes: [String: Double], essais: [String: Double],
                       achats: [String: Double], revenu: [String: Double], revenu28j: [String: Double],
                       aujourdhui: String) -> [Point] {
        var points: [Point] = []
        for (jour, v) in mrr where jour < aujourdhui {
            points += [Point(metrique: Metrique.mrrBrut, jour: jour, valeur: v),
                       Point(metrique: Metrique.mrrNet, jour: jour, valeur: v * Metrique.partNette)]
        }
        for (jour, v) in abonnes where jour < aujourdhui { points.append(Point(metrique: Metrique.abonnes, jour: jour, valeur: v)) }
        for (jour, v) in essais where jour < aujourdhui { points.append(Point(metrique: Metrique.essaisActifs, jour: jour, valeur: v)) }
        for (jour, v) in achats { points.append(Point(metrique: Metrique.achats, jour: jour, valeur: v)) }
        for (jour, v) in revenu { points.append(Point(metrique: Metrique.revenu, jour: jour, valeur: v)) }
        for (jour, v) in revenu28j where jour < aujourdhui { points.append(Point(metrique: Metrique.revenu28j, jour: jour, valeur: v)) }
        return points + [
            Point(metrique: Metrique.mrrBrut, jour: aujourdhui, valeur: apercu.mrr),
            Point(metrique: Metrique.mrrNet, jour: aujourdhui, valeur: apercu.mrr * Metrique.partNette),
            Point(metrique: Metrique.abonnes, jour: aujourdhui, valeur: apercu.abonnes),
            Point(metrique: Metrique.essaisActifs, jour: aujourdhui, valeur: apercu.essais),
            Point(metrique: Metrique.revenu28j, jour: aujourdhui, valeur: apercu.revenu28j),
        ]
    }

    static func ecrire(_ points: [Point], business: String, _ store: Store) throws {
        try store.lot {
            for p in points { try store.serie(business, p.metrique, jour: p.jour, p.valeur) }
        }
    }

    // MARK: achats

    /// Les comptes dont le droit premium court encore (`users`, une centaine de documents).
    static func requeteComptes(maintenant: Date = .now) -> [String: Any] {
        ["structuredQuery": [
            "from": [["collectionId": "users"]],
            "select": ["fields": [["fieldPath": "premiumTrial"], ["fieldPath": "entitlementCheckedAt"]]],
            "where": ["fieldFilter": [
                "field": ["fieldPath": "premiumUntil"], "op": "GREATER_THAN",
                "value": ["timestampValue": maintenant.iso],
            ]],
        ]]
    }

    /// Les uid de ces comptes hors essai que la Function a relus depuis `depuis` : un achat les fait relire.
    static func comptesPayes(_ data: Data, depuis: Date) throws -> [String] {
        struct Ligne: Decodable { let document: Document? }
        struct Document: Decodable { let name: String; let fields: Champs? }
        struct Champs: Decodable { let premiumTrial: Valeur?; let entitlementCheckedAt: Valeur? }
        struct Valeur: Decodable { let timestampValue: String?; let booleanValue: Bool? }
        return try decode([Ligne].self, data).compactMap(\.document).compactMap { d in
            // Firestore donne des microsecondes, Date(iso:) n'en lit que trois
            guard d.fields?.premiumTrial?.booleanValue != true,
                  let releve = d.fields?.entitlementCheckedAt?.timestampValue,
                  let le = Date(iso: String(releve.prefix(19)) + "Z"), le >= depuis.addingTimeInterval(-1),
                  let uid = d.name.split(separator: "/").last else { return nil }
            return String(uid)
        }
    }

    struct Abonnement: Decodable, Equatable {
        let id: String
        let startsAt: Double
        let environment: String
        let country: String?
    }

    /// Les abonnements de production commencés depuis `depuis` (`starts_at` en millisecondes).
    static func abonnements(_ data: Data, depuis: Date) throws -> [Abonnement] {
        struct Reponse: Decodable { let items: [Abonnement] }
        return try decode(Reponse.self, data).items.filter {
            $0.environment == "production" && $0.startsAt / 1000 >= depuis.timeIntervalSince1970
        }
    }

    /// Payé dès qu'un abonnement de production a rapporté, en essai si l'un l'est encore, sinon non ;
    /// inconnu sans abonnement de production.
    static func paiement(_ data: Data) throws -> EtatPaiement {
        struct Reponse: Decodable { let items: [A] }
        struct A: Decodable { let status: String; let environment: String; let totalRevenueInUsd: Montant? }
        struct Montant: Decodable { let gross: Double }
        let production = try decode(Reponse.self, data).items.filter { $0.environment == "production" }
        if production.isEmpty { return .inconnu }
        if production.contains(where: { ($0.totalRevenueInUsd?.gross ?? 0) > 0 }) { return .paye }
        return production.contains { $0.status == "trialing" } ? .essai : .non
    }

    /// Le premier paiement d'un abonnement, nil tant qu'il est en essai. Une transaction à 0 avant lui = un essai.
    static func achat(_ id: String, _ a: Abonnement, _ transactions: Data, business: String) throws -> Evenement? {
        struct Reponse: Decodable { let items: [T] }
        struct T: Decodable {
            let productStoreIdentifier: String?
            let purchasedAt: Double
            let revenueInLocalCurrency: Montant
        }
        struct Montant: Decodable { let currency: String; let gross: Double }
        let items = try decode(Reponse.self, transactions).items.sorted { $0.purchasedAt < $1.purchasedAt }
        guard let i = items.firstIndex(where: { $0.revenueInLocalCurrency.gross > 0 }) else { return nil }
        let t = items[i]
        let fr = Locale(identifier: "fr_FR")
        let prix = t.revenueInLocalCurrency.gross.formatted(.currency(code: t.revenueInLocalCurrency.currency).locale(fr))
        let pays = a.country.flatMap { fr.localizedString(forRegionCode: $0) }
        let texte = [formule(t.productStoreIdentifier ?? "") + (i > 0 ? " après essai" : ""), prix, pays]
            .compactMap { $0 }.joined(separator: ", ")
        return Evenement(id: id, business: business, at: Date(timeIntervalSince1970: t.purchasedAt / 1000),
                         type: .achat, texte: texte)
    }

    /// La durée d'un produit, lue dans son identifiant du store (`Yearly`, `roleo_quarterly:trimestriel`).
    static func formule(_ produit: String) -> String {
        let p = produit.lowercased()
        if p.contains("week") || p.contains("hebdo") { return "Hebdo" }
        if p.contains("month") || p.contains("mensuel") { return "Mensuel" }
        if p.contains("quarter") || p.contains("trimestr") { return "Trimestriel" }
        if p.contains("year") || p.contains("annual") || p.contains("annuel") { return "Annuel" }
        return produit.isEmpty ? "Abonnement" : produit
    }

    /// Le message d'erreur nomme le business (`Roleo : HTTP 401 …`).
    static func nomme(_ error: Error, _ b: Business) -> Error {
        switch error {
        case SourceErreur.nonConfigure(let m): SourceErreur.nonConfigure("\(b.nom) : \(m)")
        case SourceErreur.http(let code, let m): SourceErreur.http(code, "\(b.nom) : \(m)")
        case SourceErreur.format(let m): SourceErreur.format("\(b.nom) : \(m)")
        case SourceErreur.commande(let m): SourceErreur.commande("\(b.nom) : \(m)")
        default: error
        }
    }
}
