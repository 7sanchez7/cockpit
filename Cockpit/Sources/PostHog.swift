import Foundation

/// Actifs, installs, essais, ronds, actifs par heure, fil des essais, détail de chaque install et portes du paywall, en HogQL.
/// Voir docs/sources/posthog.md ; le décodage et l'écriture sont dans PostHog+Decodage.swift.
struct PostHog: Source {
    let id = "posthog"
    let nom = "PostHog"
    let cadence: TimeInterval = 15 * 60
    static let cleProjet = "POSTHOG_PROJECT_ID"
    static let cleAPI = "POSTHOG_PERSONAL_API_KEY"

    func collecte(_ ctx: Contexte) async throws -> Int {
        let suivis = ctx.businesses.filter { !($0.config.posthogHost ?? "").isEmpty }
        guard !suivis.isEmpty else { throw SourceErreur.nonConfigure("aucun business n'a d'hôte PostHog") }
        var lignes = 0
        for b in suivis {
            do {
                lignes += try await collecte(b, ctx)
            } catch SourceErreur.nonConfigure(let m) {
                throw SourceErreur.nonConfigure("\(b.nom) : \(m)")
            } catch {
                throw SourceErreur.commande("\(b.nom) : \(error.localizedDescription)")
            }
        }
        return lignes
    }

    private func collecte(_ b: Business, _ ctx: Contexte) async throws -> Int {
        let projet = try await ctx.secrets.valeur(Self.cleProjet, b)
        let cle = try await ctx.secrets.valeur(Self.cleAPI, b)
        let url = "\(b.config.posthogHost ?? "")/api/projects/\(projet)/query/"
        func hogql(_ requete: String) async throws -> [[Any]] {
            let r = try HTTP.requete(url, methode: "POST", jeton: cle,
                                     corps: ["query": ["kind": "HogQLQuery", "query": requete]])
            return try PostHog.lignes(try await ctx.http.objet(r))
        }

        let maintenant = Date.now
        let aujourdhui = Jour.cle(maintenant)
        // historique : au premier passage, ou quand hier ou J-90 manque pour un segment
        let historique = try PostHog.segments.contains {
            try ctx.store.historiqueIncomplet(b.id, $0?.metrique(Metrique.actifs) ?? Metrique.actifs,
                                              jours: PostHog.joursHistorique, jusqua: aujourdhui)
        }
        let jours = Jour.derniers(historique ? PostHog.joursHistorique : 2, jusqua: aujourdhui)
        let joursHeures = Jour.derniers(historique ? 9 : 2, jusqua: aujourdhui)
        let coupe = Int(Jour.calendrier.date(byAdding: .day, value: -7, to: maintenant)!.timeIntervalSince1970)
        let depuis = PostHog.minuit(Jour.decale(jours[0], jours: -7))

        let e = b.config.evenements
        var l = LecturePostHog()
        l.series = try PostHog.series(jours: try await hogql(PostHog.requeteJours(e, depuis: depuis, coupe: coupe)),
                                      installs: try await hogql(PostHog.requeteInstalls(e, depuis: depuis, coupe: coupe)))
        l.actifsHeure = try PostHog.parHeure(try await hogql(PostHog.requeteHeures(depuis: PostHog.minuit(joursHeures[0]))))
        let veille = Int(maintenant.timeIntervalSince1970) - 48 * 3600
        l.fil = try PostHog.fil(try await hogql(PostHog.requeteEssais(e, depuis: veille)), business: b.id)

        // installs détaillés et portes : une fois par heure
        let cleHoraire = "posthog.horaire.\(b.id)"
        let derniere = try ctx.store.reglage(cleHoraire).flatMap { Date(iso: $0) }
        if derniere.map({ maintenant.timeIntervalSince($0) >= 3600 }) ?? true {
            let debut = Jour.decale(aujourdhui, jours: -PostHog.joursInstalls)
            l.horaire = .init(debut: debut,
                              installs: try PostHog.installs(try await hogql(PostHog.requeteParInstall(e, depuis: PostHog.minuit(debut)))),
                              portes: try PostHog.portes(try await hogql(PostHog.requetePortes(e, depuis: PostHog.minuit(debut)))))
        }

        return try ctx.store.lot {
            let n = try PostHog.ecrire(l, business: b.id, jours: jours, joursHeures: joursHeures,
                                       maintenant: maintenant, store: ctx.store)
            if l.horaire != nil { try ctx.store.regler(cleHoraire, maintenant.iso) }
            return n
        }
    }
}

// MARK: requêtes HogQL

extension PostHog {
    /// Événements envoyés sans que l'user ouvre l'app (même liste que tools/suivi/hebdo.py de Roleo).
    static let bruit = "('$identify', '$set', '$feature_flag_called', '$opt_in', '$screen_view_exit')"

    /// Jours de séries relus quand l'historique a un trou : les 90 jours complets de la plus longue période de l'en-tête, plus aujourd'hui.
    static let joursHistorique = 91

    /// L'événement `usage` ne part de façon fiable chez Roleo que depuis la 2.0.1 : avant, rond fini et retours ne sont pas mesurés.
    static let rondsDepuis = "2026-10-15"

    /// Les écrans du tunnel de Roleo dans l'ordre, clé PostHog et nom affiché ; `paywall_viewed` y tient lieu de l'événement `paywall`.
    static let ecrans: [(cle: String, nom: String)] = [
        ("welcome", "Accueil"), ("language", "Langue apprise"), ("native_language", "Langue maternelle"),
        ("acquisition_source", "Connu comment"), ("first_name", "Prénom"), ("age", "Âge"),
        ("motivation", "Motivation"), ("pain", "Ce qui bloque"), ("interests", "Centres d'intérêt"),
        ("level", "Niveau"), ("social_proof", "Preuve sociale"), ("app_tour", "Présentation"),
        ("projection", "Projection"), ("account_setup", "Compte"), ("persona", "Choix du tuteur"),
        ("paywall_viewed", "Paywall vu"), ("paywall", "Essai touché"),
    ]

    /// Secondes Unix de minuit à Paris.
    static func minuit(_ jour: String) -> Int { Int(Jour.date(jour)!.timeIntervalSince1970) }

    /// Les séries se lisent pour le total puis pour chaque store, dans cet ordre de colonnes.
    static let segments: [Boutique?] = [nil] + Boutique.allCases.map(Optional.some)

    /// Le segment en HogQL, d'après l'`$os` de l'event (le total garde tout, web et sans `$os` compris).
    static func filtre(_ b: Boutique?, os: String = "properties.$os") -> String {
        switch b {
        case nil: "true"
        case .appStore: "\(os) in ('iOS', 'iPadOS')"
        case .playStore: "\(os) = 'Android'"
        }
    }

    /// Par jour de Paris et pour chaque segment : actifs, essais, ronds finis, chacun en entier puis avant la coupe.
    static func requeteJours(_ e: Business.Evenements, depuis: Int, coupe: Int) -> String {
        let avant = "timestamp < fromUnixTimestamp(\(coupe))"
        let colonnes = segments.map { filtre($0) }.map { s in
            """
            uniqExactIf(person_id, \(s)), uniqExactIf(person_id, \(s) and \(avant)),
                countIf(event = '\(e.essai)' and \(s)), countIf(event = '\(e.essai)' and \(s) and \(avant)),
                countIf(event = '\(e.usage)' and \(s)), countIf(event = '\(e.usage)' and \(s) and \(avant))
            """
        }
        return """
            select toString(toDate(toTimeZone(timestamp, 'Europe/Paris'))) as jour,
                \(colonnes.joined(separator: ",\n    "))
            from events
            where timestamp >= fromUnixTimestamp(\(depuis)) and event not in \(bruit)
            group by jour order by jour limit 100
            """
    }

    /// Par jour de Paris et pour chaque segment : installs (premier événement `installation` sur iPhone, iPad ou Android),
    /// installs avant la coupe. Le total est la somme des deux stores.
    static func requeteInstalls(_ e: Business.Evenements, depuis: Int, coupe: Int) -> String {
        let colonnes = segments.map { filtre($0, os: "os") }.map { "countIf(\($0)), countIf(\($0) and f < fromUnixTimestamp(\(coupe)))" }
        return """
            select toString(toDate(toTimeZone(f, 'Europe/Paris'))) as jour, \(colonnes.joined(separator: ", "))
            from (select person_id, min(timestamp) as f, argMin(properties.$os, timestamp) as os
                  from events where event = '\(e.installation)'
                  group by person_id having f >= fromUnixTimestamp(\(depuis)))
            where os in ('iOS', 'iPadOS', 'Android')
            group by jour order by jour limit 100
            """
    }

    /// Par jour et heure de Paris : actifs de chaque segment.
    static func requeteHeures(depuis: Int) -> String {
        """
        select toString(toDate(toTimeZone(timestamp, 'Europe/Paris'))) as jour,
            toHour(toTimeZone(timestamp, 'Europe/Paris')) as heure,
            \(segments.map { "uniqExactIf(person_id, \(filtre($0)))" }.joined(separator: ", "))
        from events
        where timestamp >= fromUnixTimestamp(\(depuis)) and event not in \(bruit)
        group by jour, heure order by jour, heure limit 1000
        """
    }

    /// Les essais : uuid, instant, produit, porte du paywall, pays.
    static func requeteEssais(_ e: Business.Evenements, depuis: Int) -> String {
        """
        select toString(uuid), toUnixTimestamp(timestamp), properties.product, properties.source,
            properties.$geoip_country_code
        from events
        where event = '\(e.essai)' and timestamp >= fromUnixTimestamp(\(depuis))
        order by timestamp desc limit 200
        """
    }

    /// Les personnes installées depuis `depuis`, iOS ou iPadOS.
    private static func installes(_ e: Business.Evenements, depuis: Int) -> String {
        """
        select person_id from events where event = '\(e.installation)' group by person_id
        having min(timestamp) >= fromUnixTimestamp(\(depuis)) and argMin(properties.$os, timestamp) in ('iOS', 'iPadOS')
        """
    }

    /// Les jours d'install recalculés à chaque heure : 90 jours, plus de quoi comparer une semaine.
    static let joursInstalls = 97

    /// Une ligne par install : jour d'install, rang de l'écran le plus loin atteint, paywall vu, essai gratuit, achat sans essai,
    /// rond fini, rond fini entre N et N+1 jours après l'install (1, 7, 14, 30), l'id RevenueCat s'il a converti,
    /// puis la valeur de chaque `Dimension`.
    static func requeteParInstall(_ e: Business.Evenements, depuis: Int) -> String {
        let cles = ecrans.map { "'\($0.cle)'" }.joined(separator: ", ")
        let retours = [1, 7, 14, 30].map {
            "arrayExists(t -> t >= fu + \($0) * 86400 and t < fu + \($0 + 1) * 86400, finis) as r\($0)"
        }
        let valeurs = Dimension.lues.map { "\(valeur($0, e)) as v_\($0.rawValue)" }
        return """
        select toString(toDate(toTimeZone(f, 'Europe/Paris'))) as jour, loin, vu, essai, direct, rond, r1, r7, r14, r30, client,
            \(Dimension.lues.map { "v_\($0.rawValue)" }.joined(separator: ", "))
        from (select person_id, minIf(timestamp, event = '\(e.installation)') as f, toUnixTimestamp(f) as fu,
                arrayMax(arrayMap(x -> indexOf([\(cles)], x),
                    groupUniqArrayIf(if(event = '\(e.etape)', toString(properties.step), 'paywall_viewed'),
                                     event in ('\(e.etape)', '\(e.paywall)')))) as loin,
                countIf(event = '\(e.paywall)') > 0 as vu, countIf(event = '\(e.essai)') > 0 as essai,
                countIf(event = '\(e.achat)') > 0 and countIf(event = '\(e.essai)') = 0 as direct,
                groupArrayIf(toUnixTimestamp(timestamp), event = '\(e.usage)') as finis, length(finis) > 0 as rond,
                \(retours.joined(separator: ", ")),
                if(essai or direct, ifNull(argMaxIf(distinct_id, timestamp, event in ('\(e.essai)', '\(e.achat)')), ''), '')
                    as client,
                \(valeurs.joined(separator: ",\n                "))
              from events
              where timestamp >= fromUnixTimestamp(\(depuis)) and person_id in (\(installes(e, depuis: depuis)))
                  and event in ('\(e.installation)', '\(e.etape)', '\(e.paywall)', '\(e.essai)', '\(e.achat)', '\(e.usage)')
              group by person_id)
        order by f limit 50000
        """
    }

    /// La valeur d'une dimension pour un install, texte vide s'il n'a pas répondu ; plusieurs valeurs séparées
    /// par des virgules pour les intérêts et les blocages.
    private static func valeur(_ d: Dimension, _ e: Business.Evenements) -> String {
        /// La dernière réponse à un écran du tunnel.
        func reponse(_ prop: String, _ etapes: String...) -> String {
            let dans = etapes.map { "'\($0)'" }.joined(separator: ", ")
            return "ifNull(argMaxIf(toString(properties.\(prop)), timestamp, "
                + "event = '\(e.etape)' and properties.step in (\(dans))), '')"
        }
        /// La propriété au premier événement de la liste.
        func premiere(_ prop: String, _ evenements: String) -> String {
            "ifNull(argMinIf(toString(properties.\(prop)), timestamp, event in (\(evenements))), '')"
        }
        switch d {
        case .loin: return "toString(loin)"
        case .langue: return reponse("language", "language")
        case .maternelle: return reponse("native_language", "native_language")
        case .source: return reponse("source", "acquisition_source")
        case .age: return reponse("age_range", "age")
        case .motivation: return reponse("motivation", "motivation")
        // `pains` (écran à cocher) a remplacé `pain` (un seul blocage)
        case .blocage: return "if(\(reponse("pains", "pain")) != '', \(reponse("pains", "pain")), \(reponse("pain", "pain")))"
        case .interet: return reponse("interests", "interests")
        case .niveau: return reponse("start_level", "level", "projection")
        case .tuteur: return reponse("character", "persona")
        case .notifs: return reponse("notifs", "reminder")
        case .compte: return reponse("method", "account_link")
        case .pays: return premiere("$geoip_country_code", "'\(e.installation)'")
        case .version: return premiere("$app_version", "'\(e.installation)'")
        case .build: return premiere("$app_build", "'\(e.installation)'")
        case .produit: return premiere("product", "'\(e.essai)', '\(e.achat)'")
        case .zone: preconditionFailure("la zone se déduit du pays, hors de Dimension.lues")
        }
    }

    /// Par jour de Paris et par porte du paywall (`source`) : paywalls vus, essais gratuits, achats sans essai.
    /// L'achat part aussi au début d'un essai gratuit : la différence avec les essais est l'achat direct.
    static func requetePortes(_ e: Business.Evenements, depuis: Int) -> String {
        """
        select toString(toDate(toTimeZone(timestamp, 'Europe/Paris'))) as jour, ifNull(toString(properties.source), '') as porte,
            countIf(event = '\(e.paywall)'), countIf(event = '\(e.essai)'),
            greatest(countIf(event = '\(e.achat)') - countIf(event = '\(e.essai)'), 0)
        from events
        where timestamp >= fromUnixTimestamp(\(depuis)) and event in ('\(e.paywall)', '\(e.essai)', '\(e.achat)')
        group by jour, porte order by jour, porte limit 10000
        """
    }
}
