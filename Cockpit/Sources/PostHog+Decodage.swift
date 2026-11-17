import Foundation

/// Ce qu'un passage a lu de PostHog pour un business, prêt à écrire.
struct LecturePostHog {
    /// Le total (nil) puis chaque store, d'après le `$os` des events.
    var series: [Boutique?: Series] = [:]
    /// Par segment, par jour puis par heure.
    var actifsHeure: [Boutique?: [String: [Int: Int]]] = [:]
    var fil: [Evenement] = []
    /// Nul quand le passage ne l'a pas recalculé (une fois par heure).
    var horaire: Horaire?

    /// Les installs et les portes des jours à partir de `debut`.
    struct Horaire {
        var debut: String
        var installs: [Install]
        var portes: [Porte]
    }

    /// Par jour, le compte entier et le compte avant la coupe (l'heure qu'il est, 7 jours plus tôt).
    struct Series {
        var actifs: [String: Compte] = [:]
        var essais: [String: Compte] = [:]
        var ronds: [String: Compte] = [:]
        var installs: [String: Compte] = [:]
    }

    struct Compte: Equatable {
        var tout: Int
        var coupe: Int
    }
}

extension PostHog {
    /// Les portes du paywall hors tunnel (`PaywallSource` de l'app Roleo).
    static let nomsPortes = [
        "round_locked": "rond verrouillé", "app_open": "retour dans l'app", "tutor_call": "appel au tuteur",
        "navigation_wall": "mur de l'app", "account": "onglet Compte", "mic": "micro", "listen": "écoute",
        "situations": "situations", "debates": "débats", "home_rounds": "ronds de l'accueil", "quota": "quota",
        "immersion": "immersion", "server_refusal": "refus du serveur", "round_done": "rond fini",
    ]

    // MARK: décodage

    /// Les lignes d'une réponse HogQL, colonnes dans l'ordre du select.
    static func lignes(_ reponse: [String: Any]) throws -> [[Any]] {
        guard let lignes = reponse["results"] as? [[Any]] else {
            throw SourceErreur.format("HogQL sans results (\(reponse.keys.sorted().joined(separator: ", ")))")
        }
        // jamais de chiffre tronqué en silence
        if reponse["hasMore"] as? Bool == true { throw SourceErreur.format("HogQL coupé par sa limit") }
        return lignes
    }

    /// Lignes `jour, n1, n2…` en `jour → [n1, n2…]`.
    static func parJour(_ lignes: [[Any]], colonnes: Int) throws -> [String: [Int]] {
        var r: [String: [Int]] = [:]
        for l in lignes {
            try forme(l, colonnes + 1)
            let jour = try texte(l[0])
            r[jour] = try l.dropFirst().map(entier)
        }
        return r
    }

    /// Les lignes de `requeteJours` et `requeteInstalls` en séries, une par segment.
    static func series(jours: [[Any]], installs: [[Any]]) throws -> [Boutique?: LecturePostHog.Series] {
        let j = try parJour(jours, colonnes: 6 * segments.count), i = try parJour(installs, colonnes: 2 * segments.count)
        func comptes(_ d: [String: [Int]], _ c: Int) -> [String: LecturePostHog.Compte] {
            d.mapValues { .init(tout: $0[c], coupe: $0[c + 1]) }
        }
        var r: [Boutique?: LecturePostHog.Series] = [:]
        for (k, b) in segments.enumerated() {
            r[b] = .init(actifs: comptes(j, 6 * k), essais: comptes(j, 6 * k + 2), ronds: comptes(j, 6 * k + 4),
                         installs: comptes(i, 2 * k))
        }
        return r
    }

    /// Lignes `jour, heure`, puis un compte par segment, en `segment → jour → heure → n`.
    static func parHeure(_ lignes: [[Any]]) throws -> [Boutique?: [String: [Int: Int]]] {
        var r: [Boutique?: [String: [Int: Int]]] = [:]
        for l in lignes {
            try forme(l, 2 + segments.count)
            let jour = try texte(l[0]), heure = try entier(l[1])
            for (k, b) in segments.enumerated() { r[b, default: [:]][jour, default: [:]][heure] = try entier(l[2 + k]) }
        }
        return r
    }

    /// Lignes `uuid, instant, produit, porte, pays` en lignes du fil.
    static func fil(_ lignes: [[Any]], business: String) throws -> [Evenement] {
        try lignes.map { l in
            try forme(l, 5)
            let uuid = try texte(l[0]), instant = try entier(l[1])
            return Evenement(id: "posthog:essai:\(uuid)", business: business,
                             at: Date(timeIntervalSince1970: TimeInterval(instant)), type: .essai,
                             texte: texteEssai(produit: l[2] as? String, porte: l[3] as? String, pays: l[4] as? String))
        }
    }

    /// `Essai annuel, Espagne`, plus la porte du paywall quand l'essai ne vient pas du tunnel.
    static func texteEssai(produit: String?, porte: String?, pays: String?) -> String {
        let p = produit?.lowercased() ?? ""
        let offre = p.contains("year") || p.contains("annual") ? "Essai annuel"
            : p.contains("quarter") ? "Essai trimestriel"
            : p.contains("month") ? "Essai mensuel"
            : p.contains("week") ? "Essai hebdo"
            : "Essai"
        var morceaux = [offre]
        if let pays, let nom = Locale(identifier: "fr_FR").localizedString(forRegionCode: pays) { morceaux.append(nom) }
        if let porte, porte != "onboarding" { morceaux.append(nomsPortes[porte] ?? porte) }
        return morceaux.joined(separator: ", ")
    }

    /// Lignes `jour, loin, paywall, essai, direct, rond, j1, j7, j14, j30, client`, puis une valeur par `Dimension.lues`
    /// (plusieurs séparées par des virgules, texte vide sans réponse) ; la zone se déduit du pays.
    static func installs(_ lignes: [[Any]]) throws -> [Install] {
        try lignes.map { l in
            try forme(l, 11 + Dimension.lues.count)
            let n = try l[1...9].map(entier)
            var valeurs: [Dimension: [String]] = [:]
            for (d, v) in zip(Dimension.lues, l.dropFirst(11)) {
                let liste = try texte(v).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if !liste.isEmpty { valeurs[d] = liste }
            }
            if let z = valeurs[.pays]?.first.flatMap(Dimension.zone) { valeurs[.zone] = [z] }
            let client = try texte(l[10])
            return Install(jour: try texte(l[0]), loin: n[0], paywall: n[1] != 0, essai: n[2] != 0, direct: n[3] != 0,
                           rond: n[4] != 0, j1: n[5] != 0, j7: n[6] != 0, j14: n[7] != 0, j30: n[8] != 0,
                           client: client.isEmpty ? nil : client, valeurs: valeurs)
        }
    }

    /// Lignes `jour, porte, vues, essais, directs`.
    static func portes(_ lignes: [[Any]]) throws -> [Porte] {
        try lignes.map { l in
            try forme(l, 5)
            return Porte(jour: try texte(l[0]), porte: try texte(l[1]), vues: try entier(l[2]), essais: try entier(l[3]),
                         directs: try entier(l[4]))
        }
    }

    private static func forme(_ l: [Any], _ colonnes: Int) throws {
        guard l.count == colonnes else { throw SourceErreur.format("HogQL, \(l.count) colonnes au lieu de \(colonnes)") }
    }

    private static func texte(_ v: Any) throws -> String {
        guard let s = v as? String else { throw SourceErreur.format("HogQL, texte attendu : \(v)") }
        return s
    }

    private static func entier(_ v: Any) throws -> Int {
        guard let n = v as? NSNumber else { throw SourceErreur.format("HogQL, nombre attendu : \(v)") }
        return n.intValue
    }

    // MARK: écriture

    /// Écrit une lecture et rend le nombre de lignes écrites : les séries des `jours` avec leur `_j7`, pour chaque segment
    /// (0 pour un jour absent ; les ronds seulement depuis `rondsDepuis`), les actifs par heure des `joursHeures` (jusqu'à l'heure en cours aujourd'hui),
    /// le fil, et les installs et les portes s'ils ont été lus.
    static func ecrire(_ l: LecturePostHog, business: String, jours: [String], joursHeures: [String],
                       maintenant: Date, store: Store) throws -> Int {
        var lignes = 0
        func serie(_ metrique: String, _ jour: String, heure: Int = -1, _ v: Int) throws {
            try store.serie(business, metrique, jour: jour, heure: heure, Double(v))
            lignes += 1
        }
        let zero = LecturePostHog.Compte(tout: 0, coupe: 0)
        try store.lot {
            for b in segments {
                let s = l.series[b] ?? .init()
                func nom(_ m: String) -> String { b?.metrique(m) ?? m }
                for j in jours {
                    let avant = Jour.decale(j, jours: -7)
                    try serie(nom(Metrique.actifs), j, (s.actifs[j] ?? zero).tout)
                    try serie(nom(Metrique.actifsJ7), j, (s.actifs[avant] ?? zero).coupe)
                    try serie(nom(Metrique.installs), j, (s.installs[j] ?? zero).tout)
                    try serie(nom(Metrique.installsJ7), j, (s.installs[avant] ?? zero).coupe)
                    try serie(nom(Metrique.essais), j, (s.essais[j] ?? zero).tout)
                    try serie(nom(Metrique.essaisJ7), j, (s.essais[avant] ?? zero).coupe)
                    if j >= PostHog.rondsDepuis { try serie(nom(Metrique.ronds), j, (s.ronds[j] ?? zero).tout) }
                    if avant >= PostHog.rondsDepuis { try serie(nom(Metrique.rondsJ7), j, (s.ronds[avant] ?? zero).coupe) }
                }
            }
            let aujourdhui = Jour.cle(maintenant)
            for b in segments {
                for j in joursHeures {
                    for h in 0...(j == aujourdhui ? Jour.heure(maintenant) : 23) {
                        try serie(b?.metrique(Metrique.actifsHeure) ?? Metrique.actifsHeure, j, heure: h, l.actifsHeure[b]?[j]?[h] ?? 0)
                    }
                }
            }
            for e in l.fil {
                if try store.fil(e) { lignes += 1 }
            }
            if let h = l.horaire {
                try store.installs(business: business, depuis: h.debut, h.installs)
                try store.portes(business: business, depuis: h.debut, h.portes)
                lignes += h.installs.count + h.portes.count
            }
        }
        return lignes
    }
}
