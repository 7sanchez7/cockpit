import Foundation

/// Charge et échecs IA, messages et retours en attente, et le SAV (`Firebase+SAV`), lus dans Firestore.
/// Voir docs/sources/firebase.md.
struct Firebase: Source {
    static let idSource = "firebase"
    let id = Firebase.idSource
    let nom = "Firebase"
    let cadence: TimeInterval = 15 * 60

    /// Jours relus quand hier ou le plus vieux manque : `aiLoad` n'en garde que 30 (TTL Firestore de Roleo).
    static let joursHistorique = 30
    /// Échecs d'un fournisseur en une heure (429 compris) qui font une ligne du fil.
    static let seuilEchecs = 20
    /// Requêtes de l'heure à partir desquelles un fournisseur tout en échec fait une ligne, même sous le seuil.
    static let minimumPanne = 5
    /// Un message sans réponse depuis plus longtemps passe en alerte.
    static let delaiMessage: TimeInterval = 24 * 3600
    static let longueurExtrait = 80
    static let noms = [
        "anthropic": "Anthropic", "mistral": "Mistral", "deepinfra": "DeepInfra", "fireworks": "Fireworks", "gemini": "Gemini",
    ]

    /// Le dashboard admin, sur le site Hosting par défaut du projet.
    static func dashboard(_ projet: String) -> String { "https://\(projet).web.app" }

    func collecte(_ ctx: Contexte) async throws -> Int {
        try await Self.parProjet(ctx) { b, firestore in try await collecte(b, firestore, ctx) }
    }

    /// Lance `lire` pour chaque business qui a un projet Firebase et somme les lignes ; une erreur porte le nom du business.
    static func parProjet(_ ctx: Contexte, _ lire: (Business, Firestore) async throws -> Int) async throws -> Int {
        let projets = ctx.businesses.compactMap { b in
            b.config.firebaseProject.flatMap { $0.isEmpty ? nil : (business: b, projet: $0) }
        }
        guard !projets.isEmpty else { throw SourceErreur.nonConfigure("aucun business n'a de projet Firebase") }
        var lignes = 0
        for (b, projet) in projets {
            do {
                lignes += try await lire(b, Firestore(projet: projet, http: ctx.http, jeton: try await ctx.gcloud.jeton()))
            } catch SourceErreur.nonConfigure(let m) {
                throw SourceErreur.nonConfigure("\(b.nom) : \(m)")
            } catch {
                throw SourceErreur.commande("\(b.nom) : \(error.localizedDescription)")
            }
        }
        return lignes
    }

    private func collecte(_ b: Business, _ firestore: Firestore, _ ctx: Contexte) async throws -> Int {
        let maintenant = Date.now
        let historique = try ctx.store.historiqueIncomplet(b.id, Metrique.coutTexte, jours: Self.joursHistorique,
                                                           jusqua: Jour.cle(maintenant))
        let heures = Self.heures(jours: historique ? Self.joursHistorique : 2, jusqua: maintenant)
        let docs = try await firestore.documents("aiLoad", heures.map(Self.idHeure), champs: ["m"])
        let charges = try heures.map { (debut: $0, charge: try Self.charge(docs[Self.idHeure($0)])) }
        let messages = try await firestore.ou("users", "supportOpen", egal: ["booleanValue": true], champs: Self.champsFil)
        let retours = try await firestore.ou("feedback", "status", egal: ["stringValue": "new"], champs: nil)
        let sav = try await Self.lireSAV(business: b.id, firestore, ouverts: messages, nouveaux: retours, store: ctx.store)
        let base = Self.dashboard(firestore.projet)
        return try ctx.store.lot {
            try ecrire(charges, business: b.id, lien: base + "/ia/", store: ctx.store)
                + ecrire(messages: messages, retours: retours, business: b.id, base: base, maintenant: maintenant, store: ctx.store)
                + ctx.store.synchroniserSAV(business: b.id, sav)
        }
    }

    // MARK: charge IA

    /// Le début de chaque heure, de minuit à Paris il y a `jours - 1` jours jusqu'à l'heure de `fin` comprise.
    static func heures(jours: Int, jusqua fin: Date) -> [Date] {
        guard let debut = Jour.date(Jour.decale(Jour.cle(fin), jours: 1 - jours)) else { return [] }
        return Array(stride(from: debut, through: fin, by: 3600))
    }

    /// L'id du document `aiLoad` d'une heure : `2026-11-12T23`, heure UTC.
    static func idHeure(_ debut: Date) -> String { String(debut.iso.prefix(13)) }

    /// La charge d'un document `aiLoad`, vide s'il n'existe pas (heure sans appel ou pas commencée).
    static func charge(_ doc: Firestore.Document?) throws -> Charge {
        guard let doc else { return Charge() }
        guard let m = doc["m"] else { throw SourceErreur.format("aiLoad/\(doc.id) sans champ m") }
        return try Charge(m)
    }

    /// Écrit les séries IA des jours de Paris touchés par `heures`, et une ligne du fil par heure
    /// et fournisseur notables. Le journalier est la somme des heures. Rend le nombre de lignes.
    func ecrire(_ heures: [(debut: Date, charge: Charge)], business: String, lien: String, store: Store) throws -> Int {
        var jours: [String: [Int: Charge]] = [:]
        var lignes = 0
        for (debut, charge) in heures {
            // deux heures UTC tombent sur la même heure de Paris au passage à l'heure d'hiver
            jours[Jour.cle(debut), default: [:]][Jour.heure(debut), default: Charge()].ajoute(charge)
            for (f, c) in charge.fournisseurs {
                guard let texte = Self.alerte(f, c) else { continue }
                let e = Evenement(id: "\(id):ia:\(f):\(Self.idHeure(debut))", business: business, at: debut, type: .ia,
                                  texte: texte, lien: lien)
                if try store.fil(e) { lignes += 1 }
            }
        }
        for (jour, parHeure) in jours {
            let total = parHeure.values.reduce(into: Charge()) { $0.ajoute($1) }
            try store.serie(business, Metrique.tokensIA, jour: jour, Double(total.tokens))
            try store.serie(business, Metrique.echecsIA, jour: jour, Double(total.echecs))
            try store.serie(business, Metrique.coutTexte, jour: jour, CoutIA.euros(tokens: Double(total.tokens)))
            // un jour sans voix garde ce qui est déjà relevé : Roleo ne compte la voix dans aiLoad que depuis le 17 nov. 2026
            if !total.voix.isEmpty {
                try store.serie(business, Metrique.coutVoix, jour: jour, try CoutIA.euros(voix: total.voix))
                lignes += 1
            }
            try store.somme(business, Metrique.coutIA, de: [Metrique.coutTexte, Metrique.coutVoix], jour: jour)
            lignes += 4
            for (f, c) in total.fournisseurs {
                lignes += try serie(c, f, business, jour, -1, store)
                for (h, charge) in parHeure {
                    lignes += try serie(charge.fournisseurs[f] ?? Charge.Compteurs(), f, business, jour, h, store)
                }
            }
        }
        return lignes
    }

    private func serie(_ c: Charge.Compteurs, _ f: String, _ business: String, _ jour: String, _ heure: Int,
                       _ store: Store) throws -> Int {
        try store.serie(business, Metrique.requetesIA(f), jour: jour, heure: heure, Double(c.n))
        try store.serie(business, Metrique.q429IA(f), jour: jour, heure: heure, Double(c.q))
        try store.serie(business, Metrique.erreursIA(f), jour: jour, heure: heure, Double(c.e))
        guard c.n > 0 else { return 3 }
        try store.serie(business, Metrique.latenceIA(f), jour: jour, heure: heure, Double(c.ms) / Double(c.n))
        return 4
    }

    /// Le texte du fil quand un fournisseur a trop échoué dans l'heure, nil sinon.
    static func alerte(_ fournisseur: String, _ c: Charge.Compteurs) -> String? {
        let nom = noms[fournisseur] ?? fournisseur.capitalized
        if c.n >= minimumPanne && c.q + c.e >= c.n {
            return "\(nom) ne répond plus, \(c.n) requêtes en échec cette heure"
        }
        guard c.q + c.e >= seuilEchecs else { return nil }
        var morceaux: [String] = []
        if c.q > 0 { morceaux.append(c.q == 1 ? "1 erreur 429" : "\(c.q) erreurs 429") }
        if c.e > 0 { morceaux.append(c.e == 1 ? "1 échec" : "\(c.e) échecs") }
        return "\(nom), \(morceaux.joined(separator: " et ")) cette heure"
    }

    // MARK: messages et retours

    /// Fils ouverts et retours nouveaux : compteurs du jour, tâches (un seul appel, la liste complète),
    /// lignes du fil. Rend le nombre de lignes.
    func ecrire(messages: [Firestore.Document], retours: [Firestore.Document], business: String, base: String,
                maintenant: Date, store: Store) throws -> Int {
        var taches: [Tache] = []
        var evenements: [Evenement] = []
        for d in messages {
            guard let at = d["supportLastAt"]?.instant else { throw SourceErreur.format("un fil ouvert sans supportLastAt") }
            let cle = "msg:\(d.id):\(at.iso)"
            let texte = Self.extrait(d["supportPreview"]?.texte ?? "") ?? "Nouveau message"
            let lien = base + "/messages/"
            let ton: Tache.Ton = maintenant.timeIntervalSince(at) > Self.delaiMessage ? .alerte : .neutre
            taches.append(Tache(cle: cle, texte: texte, etiquette: Self.age(depuis: at, maintenant: maintenant), ton: ton, lien: lien))
            evenements.append(Evenement(id: "\(id):\(cle)", business: business, at: at, type: .msg, texte: texte, lien: lien))
        }
        for d in retours {
            guard let at = d["createdAt"]?.instant else { throw SourceErreur.format("un retour sans createdAt") }
            let cle = "retour:\(d.id)"
            let texte = Self.libelle(d)
            let lien = base + "/feedback/"
            taches.append(Tache(cle: cle, texte: texte, etiquette: Self.age(depuis: at, maintenant: maintenant), lien: lien))
            evenements.append(Evenement(id: "\(id):\(cle)", business: business, at: at, type: .retour, texte: texte, lien: lien))
        }
        try store.synchroniserTaches(source: id, business: business, taches)
        let jour = Jour.cle(maintenant)
        try store.serie(business, Metrique.messagesOuverts, jour: jour, Double(messages.count))
        try store.serie(business, Metrique.retoursNouveaux, jour: jour, Double(retours.count))
        let nouveaux = try evenements.filter { try store.fil($0) }.count
        return taches.count + nouveaux + 2
    }

    /// « Problème : le micro coupe », d'après la provenance du retour.
    static func libelle(_ d: Firestore.Document) -> String {
        let genre = switch (d["source"]?.texte, d["category"]?.texte) {
        case ("profile", "idea"): "Idée"
        case ("profile", "problem"): "Problème"
        case ("rating", _): "Après le bilan"
        case ("chat_report", _): "Signalement"
        default: "Retour"
        }
        return extrait(d["message"]?.texte ?? "").map { "\(genre) : \($0)" } ?? genre
    }

    /// Le texte sur une ligne, coupé à `longueurExtrait` caractères ; nil s'il est vide.
    static func extrait(_ texte: String) -> String? {
        let ligne = texte.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !ligne.isEmpty else { return nil }
        return ligne.count > longueurExtrait ? String(ligne.prefix(longueurExtrait - 1)) + "…" : ligne
    }

    /// « 12 min », « 2 h », « 3 j ».
    static func age(depuis at: Date, maintenant: Date) -> String {
        let minutes = max(1, Int(maintenant.timeIntervalSince(at) / 60))
        if minutes < 60 { return "\(minutes) min" }
        if minutes < 24 * 60 { return "\(minutes / 60) h" }
        return "\(minutes / (24 * 60)) j"
    }
}

extension Firebase {
    /// Ce que Roleo compte dans `aiLoad.m.<minute>` : par fournisseur `n`, `q` (429), `e` (autres échecs),
    /// `ms` (latence cumulée) ; `tk` les tokens facturables, `f` les échecs vus par l'user, `v` les caractères
    /// de voix par moteur.
    struct Charge: Equatable {
        var tokens = 0
        var echecs = 0
        var fournisseurs: [String: Compteurs] = [:]
        var voix: [String: Int] = [:]

        struct Compteurs: Equatable {
            var n = 0
            var q = 0
            var e = 0
            var ms = 0

            mutating func ajoute(_ c: Compteurs) {
                n += c.n
                q += c.q
                e += c.e
                ms += c.ms
            }
        }

        mutating func ajoute(_ c: Charge) {
            tokens += c.tokens
            echecs += c.echecs
            for (f, x) in c.fournisseurs { fournisseurs[f, default: Compteurs()].ajoute(x) }
            for (moteur, n) in c.voix { voix[moteur, default: 0] += n }
        }
    }
}

extension Firebase.Charge {
    /// Somme les minutes de `m` ; une clé dont la valeur est une carte est un fournisseur, sauf `v`.
    init(_ m: Firestore.Valeur) throws {
        guard case .carte(let minutes) = m else { throw SourceErreur.format("aiLoad.m n'est pas une carte") }
        for minute in minutes.values {
            guard case .carte(let champs) = minute else { throw SourceErreur.format("une minute d'aiLoad n'est pas une carte") }
            for (cle, v) in champs {
                if cle == "v" {
                    guard case .carte(let moteurs) = v else { throw SourceErreur.format("aiLoad v n'est pas une carte") }
                    for (moteur, n) in moteurs { voix[moteur, default: 0] += try Self.compte(n) }
                } else if case .carte(let c) = v {
                    fournisseurs[cle, default: Compteurs()].ajoute(Compteurs(
                        n: try Self.compte(c["n"]), q: try Self.compte(c["q"]), e: try Self.compte(c["e"]), ms: try Self.compte(c["ms"])))
                } else if cle == "tk" {
                    tokens += try Self.compte(v)
                } else if cle == "f" {
                    echecs += try Self.compte(v)
                }
            }
        }
    }

    private static func compte(_ v: Firestore.Valeur?) throws -> Int {
        switch v {
        case nil: 0
        case .entier(let n)?: n
        case .reel(let x)?: Int(x)
        default: throw SourceErreur.format("un compteur d'aiLoad n'est pas un nombre")
        }
    }
}
