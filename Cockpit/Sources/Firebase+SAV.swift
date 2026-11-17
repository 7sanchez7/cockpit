import Foundation

/// Le SAV : fils avec les users et retours, lus à chaque passage ; réponse, fermeture d'un fil et traitement
/// d'un retour écrits dans Firestore comme le dashboard admin. Voir docs/sources/firebase.md § SAV.
extension Firebase {
    /// Fils et retours les plus récents relus à chaque passage, en plus des ouverts.
    static let recentsSAV = 50
    /// Le fil complet que l'app et le dashboard affichent (`threadLimit` de Roleo).
    static let messagesParFil = 100
    /// Une réponse, en caractères Unicode (`maxMessageRunes` de Roleo).
    static let longueurReponse = 2000
    static let longueurApercu = 140
    /// Ce que le SAV lit d'un `users/{uid}`.
    static let champsFil = ["supportLastAt", "supportLastFrom", "supportPreview", "supportOpen", "supportUnread", "displayName"]

    /// Le début des ids de tâche d'un fil, `firebase:msg:<uid>:` (docs/donnees.md).
    static func prefixeTacheFil(_ uid: String) -> String { "\(idSource):msg:\(uid):" }
    static func tacheRetour(_ id: String) -> String { "\(idSource):retour:\(id)" }

    // MARK: lecture

    /// Les fils ouverts et récents, les retours à traiter et récents, les messages des fils qui ont bougé depuis
    /// la dernière lecture, les emails pas encore connus.
    static func lireSAV(business: String, _ f: Firestore, ouverts: [Firestore.Document], nouveaux: [Firestore.Document],
                        store: Store) async throws -> ReleveSAV {
        var r = ReleveSAV()
        // un compte qui n'a jamais écrit a supportLastAt à null, trié après les autres
        let recents = try await f.derniers("users", ordre: "supportLastAt", limite: recentsSAV, champs: champsFil)
            .filter { $0["supportLastAt"]?.instant != nil }
        r.fils = try uniques(ouverts + recents).map { try fil($0, business: business) }
        let retoursRecents = try await f.derniers("feedback", ordre: "createdAt", limite: recentsSAV)
        r.retours = try uniques(nouveaux + retoursRecents).map { try retour($0, business: business) }
        let lus = try store.filsLus(business: business)
        for fil in r.fils where lus[fil.uid] != fil.dernierAt.iso {
            r.messages[fil.uid] = try await f.derniers("support", sous: "users/\(fil.uid)", ordre: "createdAt",
                                                       limite: messagesParFil).reversed().map(message)
        }
        let connus = try store.comptesSAV(business: business)
        r.emails = try await emails(Array(Set(r.fils.map(\.uid) + r.retours.compactMap(\.uid)).subtracting(connus)), f)
        return r
    }

    static func fil(_ d: Firestore.Document, business: String) throws -> FilSAV {
        guard let at = d["supportLastAt"]?.instant else { throw SourceErreur.format("users/\(d.id) sans supportLastAt") }
        // `readUnread` de Roleo
        let u = d["supportUnread"]
        let nonVu = u?["id"]?.texte != nil && u?["text"]?.texte != nil && u?["at"]?.instant != nil
        return FilSAV(business: business, uid: d.id, nom: nonVide(d["displayName"]?.texte), dernierAt: at,
                      dernierEquipe: d["supportLastFrom"]?.texte == "team", apercu: d["supportPreview"]?.texte ?? "",
                      ouvert: d["supportOpen"]?.booleen == true, nonVu: nonVu)
    }

    static func message(_ d: Firestore.Document) throws -> MessageSAV {
        guard let at = d["createdAt"]?.instant else { throw SourceErreur.format("un message de support sans createdAt") }
        return MessageSAV(id: d.id, equipe: d["from"]?.texte == "team", texte: d["text"]?.texte ?? "", at: at)
    }

    static func retour(_ d: Firestore.Document, business: String) throws -> RetourSAV {
        guard let at = d["createdAt"]?.instant else { throw SourceErreur.format("feedback/\(d.id) sans createdAt") }
        return RetourSAV(business: business, id: d.id, uid: nonVide(d["uid"]?.texte), source: nonVide(d["source"]?.texte),
                         categorie: nonVide(d["category"]?.texte), etoiles: d["stars"]?.nombre.map { Int($0) },
                         message: d["message"]?.texte ?? "", citation: nonVide(d["quote"]?.texte),
                         conversation: nonVide(d["conversationId"]?.texte), traite: d["status"]?.texte == "done",
                         traiteLe: d["handledAt"]?.instant, plateforme: nonVide(d["platform"]?.texte),
                         build: d["appBuild"]?.nombre.map { String(Int($0)) }, at: at)
    }

    /// L'email de chaque uid, vide pour un invité ou un compte supprimé. Cent par appel.
    static func emails(_ uids: [String], _ f: Firestore) async throws -> [String: String] {
        var emails: [String: String] = [:]
        for debut in stride(from: 0, to: uids.count, by: 100) {
            let lot = Array(uids[debut..<min(debut + 100, uids.count)])
            let req = try HTTP.requete("https://identitytoolkit.googleapis.com/v1/projects/\(f.projet)/accounts:lookup",
                                       methode: "POST", jeton: f.jeton, corps: ["localId": lot],
                                       entetes: ["x-goog-user-project": f.projet])
            for uid in lot { emails[uid] = "" }
            for c in try await f.http.json(Comptes.self, req).users ?? [] { emails[c.localId] = c.email ?? "" }
        }
        return emails
    }

    private struct Comptes: Decodable {
        let users: [Compte]?

        struct Compte: Decodable {
            let localId: String
            let email: String?
        }
    }

    // MARK: actions de l'écran SAV

    /// Envoie la réponse de l'équipe comme le dashboard (`sendTeamMessage` de Roleo) : le message et le résumé du fil
    /// en un commit, puis la notif sur chaque appareil. Rend ce que l'écran affiche sous le champ.
    static func repondre(_ texte: String, a cle: CleFil, _ ctx: Contexte) async throws -> String {
        guard let t = reponse(texte) else { throw SourceErreur.format("réponse vide ou de plus de \(longueurReponse) caractères") }
        let (f, nom) = try await firestore(cle.business, ctx)
        let id = nouvelId()
        let maintenant = Date.now
        let resume = apercu(t)
        try await f.commit([
            try f.ecriture("users/\(cle.uid)/support/\(id)",
                           ["from": "team", "text": t, "sentBy": "cockpit", "feedbackId": nil, "createdAt": maintenant],
                           existe: false),
            try f.ecriture("users/\(cle.uid)", [
                "supportLastAt": maintenant, "supportLastFrom": "team", "supportPreview": resume, "supportOpen": false,
                "supportUnread": ["id": id, "text": t, "at": maintenant] as [String: Any?],
            ], existe: true),
        ])
        try ctx.store.repondreSAV(cle, MessageSAV(id: id, equipe: true, texte: t, at: maintenant), apercu: resume)
        do {
            let n = try await notifier(cle.uid, titre: nom, id: id, corps: resume, f)
            return n == 0 ? "Envoyé, aucun appareil à notifier" : "Envoyé et notifié"
        } catch {
            return "Envoyé, la notif a échoué : \(error.localizedDescription)"
        }
    }

    /// Le fil marqué traité sans réponse (`closeThread` de Roleo).
    static func fermer(_ cle: CleFil, _ ctx: Contexte) async throws {
        let (f, _) = try await firestore(cle.business, ctx)
        try await f.commit([try f.ecriture("users/\(cle.uid)", ["supportOpen": false], existe: true)])
        try ctx.store.fermerFilSAV(cle)
    }

    /// Un retour marqué traité, ou rouvert, comme le bouton du dashboard.
    static func traiter(_ r: RetourSAV, traite: Bool, _ ctx: Contexte) async throws {
        let (f, _) = try await firestore(r.business, ctx)
        let maintenant = Date.now
        let champs: [String: Any?] = ["status": traite ? "done" : "new", "handledAt": traite ? maintenant : nil]
        try await f.commit([try f.ecriture("feedback/\(r.id)", champs, existe: true)])
        try ctx.store.traiterRetourSAV(business: r.business, id: r.id, traite: traite, le: maintenant)
    }

    /// La notif `support` sur chaque appareil du compte (`notifyUser` de Roleo) ; un jeton que FCM refuse est effacé.
    /// Rend le nombre d'appareils atteints ; lève la première autre erreur si aucun ne l'a été.
    private static func notifier(_ uid: String, titre: String, id: String, corps: String, _ f: Firestore) async throws -> Int {
        let appareils = try await f.ou("pushTokens", "uid", egal: ["stringValue": uid], champs: ["token"])
        var atteints = 0
        var morts: [[String: Any]] = []
        var erreur: Error?
        for a in appareils {
            guard let jeton = a["token"]?.texte else { continue }
            let req = try HTTP.requete("https://fcm.googleapis.com/v1/projects/\(f.projet)/messages:send", methode: "POST",
                                       jeton: f.jeton, corps: ["message": notif(jeton, titre: titre, id: id, corps: corps)],
                                       entetes: ["x-goog-user-project": f.projet])
            do {
                _ = try await f.http.donnees(req)
                atteints += 1
            } catch SourceErreur.http(let code, _) where code == 400 || code == 404 {
                // UNREGISTERED ou INVALID_ARGUMENT : app désinstallée, jeton tourné
                morts.append(["delete": a.name])
            } catch {
                erreur = erreur ?? error
            }
        }
        if !morts.isEmpty { try await f.commit(morts) }
        if atteints == 0, let erreur { throw erreur }
        return atteints
    }

    /// Le message FCM de `pushMessage` de Roleo : data seule sur Android, alerte APNs sur iOS.
    static func notif(_ jeton: String, titre: String, id: String, corps: String) -> [String: Any] {
        [
            "token": jeton,
            "data": ["kind": "support", "message_id": id, "title": titre, "body": corps],
            "android": ["priority": "HIGH"],
            "apns": ["payload": ["aps": ["alert": ["title": titre, "body": corps], "sound": "default"] as [String: Any]]],
        ]
    }

    // MARK: outils

    /// Le texte d'une réponse sans les blancs autour ; nil s'il est vide ou trop long (`parseText` de Roleo).
    static func reponse(_ texte: String) -> String? {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t.unicodeScalars.count > longueurReponse ? nil : t
    }

    /// Le résumé d'un fil (`preview` de Roleo) : blancs réduits à une espace, 140 caractères Unicode au plus.
    static func apercu(_ texte: String) -> String {
        let ligne = texte.replacing(/\s+/, with: " ")
        guard ligne.unicodeScalars.count > longueurApercu else { return ligne }
        return String(String.UnicodeScalarView(ligne.unicodeScalars.prefix(longueurApercu - 1))) + "…"
    }

    /// Un id de document comme Firestore les tire : 20 caractères alphanumériques.
    static func nouvelId() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<20).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }

    /// Le Firestore du projet d'un business, et son nom (titre des notifs).
    private static func firestore(_ business: String, _ ctx: Contexte) async throws -> (Firestore, String) {
        guard let b = ctx.businesses.first(where: { $0.id == business }), let projet = b.config.firebaseProject,
              !projet.isEmpty else { throw SourceErreur.nonConfigure("ce business n'a pas de projet Firebase") }
        return (Firestore(projet: projet, http: ctx.http, jeton: try await ctx.gcloud.jeton()), b.nom)
    }

    private static func uniques(_ docs: [Firestore.Document]) -> [Firestore.Document] {
        var vus = Set<String>()
        return docs.filter { vus.insert($0.id).inserted }
    }

    private static func nonVide(_ s: String?) -> String? { s?.isEmpty == false ? s : nil }
}
