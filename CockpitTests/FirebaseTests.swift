import Foundation
import Testing
@testable import CockpitNoyau

@MainActor
struct FirebaseTests {
    let store = try! Store.memoire()
    let source = Firebase()
    let base = "https://roleo-73820.web.app"

    func document(_ json: String) throws -> Firestore.Document {
        try JSONDecoder().decode(Firestore.Document.self, from: Data(json.utf8))
    }

    func valeur(_ metrique: String, _ jour: String, heure: Int = -1) throws -> Double? {
        try store.db.query("select valeur from serie where business = 'roleo' and metrique = ? and jour = ? and heure = ?",
                           [metrique, jour, heure]).first?.nombre("valeur")
    }

    // MARK: valeurs typées

    @Test func valeursTypees() throws {
        let d = try document("""
            {"name": "projects/p/databases/(default)/documents/feedback/abc", "fields": {
              "n": {"integerValue": "22"}, "x": {"doubleValue": 1.5}, "s": {"stringValue": "salut"},
              "b": {"booleanValue": true}, "t": {"timestampValue": "2026-11-12T23:49:10.123456Z"},
              "m": {"mapValue": {"fields": {"k": {"integerValue": "3"}}}}, "vide": {"mapValue": {}},
              "l": {"arrayValue": {"values": [{"stringValue": "a"}, {"nullValue": null}]}}, "z": {"nullValue": null}}}
            """)
        #expect(d.id == "abc")
        #expect(d["n"] == .entier(22))
        #expect(d["n"]?.nombre == 22)
        #expect(d["x"]?.nombre == 1.5)
        #expect(d["s"]?.texte == "salut")
        #expect(d["s"]?.nombre == nil)
        #expect(d["b"]?.booleen == true)
        #expect(d["t"]?.instant?.iso == "2026-11-12T23:49:10Z")
        #expect(d["m"]?["k"] == .entier(3))
        #expect(d["vide"] == .carte([:]))
        #expect(d["l"] == .liste([.texte("a"), .nul]))
        #expect(d["z"] == .nul)
        #expect(d["absent"] == nil)
        #expect(try document(#"{"name": "a/b"}"#)["x"] == nil)
    }

    @Test func valeurIllisibleLeve() {
        #expect(throws: DecodingError.self) { try document(#"{"name": "a/b", "fields": {"n": {"integerValue": "douze"}}}"#) }
        #expect(throws: DecodingError.self) { try document(#"{"name": "a/b", "fields": {"t": {"timestampValue": "hier"}}}"#) }
        #expect(throws: DecodingError.self) { try document(#"{"name": "a/b", "fields": {"g": {"geoPointValue": {}}}}"#) }
    }

    // MARK: charge IA

    /// Un `aiLoad` réduit à deux minutes, à la forme de la prod.
    static let aiLoad = """
        {"name": "projects/roleo-73820/databases/(default)/documents/aiLoad/2026-11-12T23", "fields": {"m": {"mapValue": {"fields": {
          "05": {"mapValue": {"fields": {
            "mistral": {"mapValue": {"fields": {"n": {"integerValue": "10"}, "q": {"integerValue": "2"}, "e": {"integerValue": "1"},
                                                "ms": {"integerValue": "5000"}, "p": {"integerValue": "1"}}}},
            "tk": {"integerValue": "12000"}, "f": {"integerValue": "1"}, "w": {"integerValue": "300"},
            "v": {"mapValue": {"fields": {"voxtral3": {"integerValue": "1000"}}}}}}},
          "06": {"mapValue": {"fields": {
            "mistral": {"mapValue": {"fields": {"n": {"integerValue": "30"}, "q": {"integerValue": "20"}, "ms": {"integerValue": "15000"}}}},
            "anthropic": {"mapValue": {"fields": {"n": {"integerValue": "4"}, "ms": {"integerValue": "2400"}}}},
            "tk": {"integerValue": "8000"},
            "v": {"mapValue": {"fields": {"voxtral3": {"integerValue": "500"}, "kokoro": {"doubleValue": 2000}}}}}}}}}}}}
        """

    @Test func chargeSommeLesMinutes() throws {
        let c = try Firebase.charge(document(Self.aiLoad))
        #expect(c.tokens == 20000)
        #expect(c.echecs == 1)
        #expect(c.fournisseurs["mistral"] == .init(n: 40, q: 22, e: 1, ms: 20000))
        #expect(c.fournisseurs["anthropic"] == .init(n: 4, q: 0, e: 0, ms: 2400))
        #expect(c.fournisseurs.count == 2)
        #expect(c.voix == ["voxtral3": 1500, "kokoro": 2000])
        #expect(try Firebase.charge(nil) == Firebase.Charge())
        #expect(throws: SourceErreur.self) { try Firebase.charge(document(#"{"name": "a/aiLoad/x", "fields": {}}"#)) }
        let faux = #"{"name": "a/aiLoad/x", "fields": {"m": {"mapValue": {"fields": {"05": {"mapValue": {"fields": {"tk": {"stringValue": "1"}}}}}}}}}"#
        #expect(throws: SourceErreur.self) { try Firebase.charge(document(faux)) }
        let voixFausse = #"{"name": "a/aiLoad/x", "fields": {"m": {"mapValue": {"fields": {"05": {"mapValue": {"fields": {"v": {"integerValue": "1"}}}}}}}}}"#
        #expect(throws: SourceErreur.self) { try Firebase.charge(document(voixFausse)) }
    }

    @Test func heuresDeParisEnIdsUTC() throws {
        let h = Firebase.heures(jours: 2, jusqua: Date(iso: "2026-11-13T14:20:00Z")!)
        #expect(h.count == 40)
        #expect(Firebase.idHeure(h.first!) == "2026-11-11T23")
        #expect(Firebase.idHeure(h.last!) == "2026-11-13T14")
        // passage à l'heure d'hiver : 25 heures UTC, 24 heures de Paris
        let hiver = Firebase.heures(jours: 1, jusqua: Date(iso: "2026-10-25T22:30:00Z")!)
        #expect(hiver.count == 25)
        #expect(Set(hiver.map(Jour.heure)).count == 24)
        #expect(Set(hiver.map(Jour.cle)) == ["2026-10-25"])
    }

    @Test func seriesIAALHeureDeParis() throws {
        let charge = try Firebase.charge(document(Self.aiLoad))
        let suite = Firebase.Charge(tokens: 100, fournisseurs: ["anthropic": .init(n: 2, ms: 200)])
        let heures = [(debut: Date(iso: "2026-11-12T23:00:00Z")!, charge: charge),
                      (debut: Date(iso: "2026-11-13T00:00:00Z")!, charge: suite)]
        let n = try source.ecrire(heures, business: "roleo", lien: base + "/ia/", store: store)

        let jour = "2026-11-13"
        #expect(try valeur(Metrique.tokensIA, jour) == 20100)
        #expect(try valeur(Metrique.tokensIA, "2026-11-12") == nil)
        #expect(try valeur(Metrique.echecsIA, jour) == 1)
        #expect(try valeur(Metrique.coutTexte, jour) == CoutIA.euros(tokens: 20100))
        let voix = try CoutIA.euros(voix: ["voxtral3": 1500, "kokoro": 2000])
        #expect(try valeur(Metrique.coutVoix, jour) == voix)
        #expect(try valeur(Metrique.coutIA, jour) == CoutIA.euros(tokens: 20100) + voix)
        #expect(try valeur(Metrique.requetesIA("mistral"), jour, heure: 0) == 40)
        #expect(try valeur(Metrique.requetesIA("mistral"), jour, heure: 1) == 0)
        #expect(try valeur(Metrique.requetesIA("mistral"), jour) == 40)
        #expect(try valeur(Metrique.q429IA("mistral"), jour) == 22)
        #expect(try valeur(Metrique.erreursIA("mistral"), jour, heure: 0) == 1)
        #expect(try valeur(Metrique.latenceIA("mistral"), jour, heure: 0) == 500)
        #expect(try valeur(Metrique.latenceIA("mistral"), jour, heure: 1) == nil)
        #expect(try valeur(Metrique.requetesIA("anthropic"), jour) == 6)
        #expect(try valeur(Metrique.latenceIA("anthropic"), jour) == 2600.0 / 6)

        let fil = try store.db.query("select id, at, type, texte, lien from fil")
        #expect(fil.count == 1)
        #expect(fil.first?.texte("id") == "firebase:ia:mistral:2026-11-12T23")
        #expect(fil.first?.date("at") == Date(iso: "2026-11-12T23:00:00Z"))
        #expect(fil.first?.texte("type") == "IA")
        #expect(fil.first?.texte("texte") == "Mistral, 22 erreurs 429 et 1 échec cette heure")
        #expect(fil.first?.texte("lien") == base + "/ia/")
        // 4 séries du jour et la voix, 2 fournisseurs × 3 périodes, 4 séries sauf mistral à 1 h (3), 1 ligne du fil
        #expect(n == 5 + 4 + 4 + 3 + 4 + 4 + 4 + 1)

        #expect(try source.ecrire(heures, business: "roleo", lien: base + "/ia/", store: store) == n - 1)
    }

    @Test func alertes() {
        typealias C = Firebase.Charge.Compteurs
        #expect(Firebase.alerte("mistral", C(n: 100, q: 19)) == nil)
        #expect(Firebase.alerte("mistral", C(n: 100, q: 20)) == "Mistral, 20 erreurs 429 cette heure")
        #expect(Firebase.alerte("mistral", C(n: 100, e: 25)) == "Mistral, 25 échecs cette heure")
        #expect(Firebase.alerte("nouveau", C(n: 100, q: 1, e: 19)) == "Nouveau, 1 erreur 429 et 19 échecs cette heure")
        #expect(Firebase.alerte("deepinfra", C(n: 6, e: 6)) == "DeepInfra ne répond plus, 6 requêtes en échec cette heure")
        #expect(Firebase.alerte("anthropic", C(n: 4, e: 4)) == nil)
    }

    // MARK: coût

    @Test func cout() {
        #expect(abs(CoutIA.euros(tokens: 1_000_000) - 0.1656) < 1e-12)
        #expect(abs(CoutIA.euros(tokens: 3_058_771) - 0.50653) < 1e-5)
        #expect(CoutIA.euros(tokens: 0) == 0)
        #expect(CoutIA.euros(tokens: -5) == 0)
        #expect(abs(CoutIA.euros(caracteres: 1_000_000, usdParMillion: 13) - 11.96) < 1e-12)
        let voix = try? CoutIA.euros(voix: ["voxtral3": 1_000_000, "kokoro": 2_000_000, "voxtral": 500_000, "gemini": 250_000])
        #expect(abs(voix! - (13 + 2 * 1.485 + 0.5 * 16 + 0.25 * 20) * 0.92) < 1e-9)
        #expect(throws: SourceErreur.self) { try CoutIA.euros(voix: ["inconnu": 1]) }
    }

    // MARK: voix

    @Test func jourSansVoixGardeLeCoutReleve() throws {
        try store.serie("roleo", Metrique.coutVoix, jour: "2026-11-13", 4)
        let heures = [(debut: Date(iso: "2026-11-13T09:00:00Z")!, charge: Firebase.Charge(tokens: 1_000_000))]
        _ = try source.ecrire(heures, business: "roleo", lien: base + "/ia/", store: store)
        #expect(try valeur(Metrique.coutVoix, "2026-11-13") == 4)
        #expect(try valeur(Metrique.coutIA, "2026-11-13") == 4 + CoutIA.euros(tokens: 1_000_000))
        // sans aucune part, pas de total
        try store.somme("roleo", Metrique.coutIA, de: [Metrique.coutTexte, Metrique.coutVoix], jour: "2026-09-01")
        #expect(try valeur(Metrique.coutIA, "2026-09-01") == nil)
    }

    // MARK: messages et retours

    func message(_ uid: String, _ at: String, _ apercu: String) throws -> Firestore.Document {
        try document("""
            {"name": "projects/p/databases/(default)/documents/users/\(uid)", "fields": {
              "supportLastAt": {"timestampValue": "\(at)"}, "supportPreview": {"stringValue": "\(apercu)"}}}
            """)
    }

    func retour(_ id: String, _ source: String, _ categorie: String?, _ texte: String, _ at: String) throws -> Firestore.Document {
        let cat = categorie.map { #"{"stringValue": "\#($0)"}"# } ?? #"{"nullValue": null}"#
        return try document("""
            {"name": "projects/p/databases/(default)/documents/feedback/\(id)", "fields": {
              "source": {"stringValue": "\(source)"}, "category": \(cat), "message": {"stringValue": "\(texte)"},
              "createdAt": {"timestampValue": "\(at)"}}}
            """)
    }

    func taches() throws -> [String: Ligne] {
        let lignes = try store.db.query("select id, texte, etiquette, ton, lien, fait_le from a_traiter where source = 'firebase'")
        return Dictionary(uniqueKeysWithValues: lignes.map { ($0.texte("id")!, $0) })
    }

    @Test func messagesEtRetoursEnTaches() throws {
        let maintenant = Date(iso: "2026-11-13T12:00:00Z")!
        let messages = [try message("u1", "2026-11-13T09:59:59.250000Z", "Bonjour,\\n  l'appli plante"),
                        try message("u2", "2026-11-10T09:00:00Z", "")]
        let retours = [try retour("r1", "profile", "problem", "Le micro coupe", "2026-11-13T11:48:00Z"),
                       try retour("r2", "rating", nil, "", "2026-11-12T12:00:00Z"),
                       try retour("r3", "chat_report", "other", String(repeating: "a", count: 200), "2026-11-13T11:59:50Z")]
        let n = try source.ecrire(messages: messages, retours: retours, business: "roleo", base: base,
                                  maintenant: maintenant, store: store)
        #expect(n == 5 + 5 + 2)

        let t = try taches()
        #expect(t.count == 5)
        let u1 = try #require(t["firebase:msg:u1:2026-11-13T09:59:59Z"])
        #expect(u1.texte("texte") == "Bonjour, l'appli plante")
        #expect(u1.texte("etiquette") == "2 h")
        #expect(u1.texte("ton") == "neutre")
        #expect(u1.texte("lien") == base + "/messages/")
        let u2 = try #require(t["firebase:msg:u2:2026-11-10T09:00:00Z"])
        #expect(u2.texte("texte") == "Nouveau message")
        #expect(u2.texte("etiquette") == "3 j")
        #expect(u2.texte("ton") == "alerte")
        #expect(t["firebase:retour:r1"]?.texte("texte") == "Problème : Le micro coupe")
        #expect(t["firebase:retour:r1"]?.texte("etiquette") == "12 min")
        #expect(t["firebase:retour:r1"]?.texte("lien") == base + "/feedback/")
        #expect(t["firebase:retour:r2"]?.texte("texte") == "Après le bilan")
        #expect(t["firebase:retour:r2"]?.texte("etiquette") == "1 j")
        #expect(t["firebase:retour:r3"]?.texte("texte")?.count == "Signalement : ".count + 80)
        #expect(t["firebase:retour:r3"]?.texte("texte")?.hasSuffix("…") == true)
        #expect(t["firebase:retour:r3"]?.texte("etiquette") == "1 min")

        let fil = try store.db.query("select id, type, at from fil order by id")
        #expect(fil.map { $0.texte("id")! } == ["firebase:msg:u1:2026-11-13T09:59:59Z", "firebase:msg:u2:2026-11-10T09:00:00Z",
                                                "firebase:retour:r1", "firebase:retour:r2", "firebase:retour:r3"])
        #expect(fil.map { $0.texte("type")! } == ["MSG", "MSG", "RETOUR", "RETOUR", "RETOUR"])
        #expect(fil.last?.date("at") == Date(iso: "2026-11-13T11:59:50Z"))
        #expect(try valeur(Metrique.messagesOuverts, "2026-11-13") == 2)
        #expect(try valeur(Metrique.retoursNouveaux, "2026-11-13") == 3)

        // u1 réécrit, u2 a sa réponse, r1 et r2 sont traités
        let plusTard = Date(iso: "2026-11-13T13:00:00Z")!
        let n2 = try source.ecrire(messages: [try message("u1", "2026-11-13T12:30:00Z", "Toujours là")],
                                   retours: [retours[2]], business: "roleo", base: base, maintenant: plusTard, store: store)
        #expect(n2 == 2 + 1 + 2)
        let t2 = try taches()
        #expect(t2["firebase:msg:u1:2026-11-13T12:30:00Z"]?.texte("fait_le") == nil)
        #expect(t2["firebase:msg:u1:2026-11-13T09:59:59Z"]?.texte("fait_le") != nil)
        #expect(t2["firebase:msg:u2:2026-11-10T09:00:00Z"]?.texte("fait_le") != nil)
        #expect(t2["firebase:retour:r1"]?.texte("fait_le") != nil)
        #expect(t2["firebase:retour:r3"]?.texte("fait_le") == nil)
        #expect(t2["firebase:retour:r3"]?.texte("etiquette") == "1 h")
        #expect(try valeur(Metrique.messagesOuverts, "2026-11-13") == 1)
        #expect(try valeur(Metrique.retoursNouveaux, "2026-11-13") == 1)
    }

    @Test func messageSansDateLeve() throws {
        let d = try document(#"{"name": "a/users/u", "fields": {"supportPreview": {"stringValue": "x"}}}"#)
        #expect(throws: SourceErreur.self) {
            try source.ecrire(messages: [d], retours: [], business: "roleo", base: base, maintenant: .now, store: store)
        }
    }

    @Test func ages() {
        let t = Date(iso: "2026-11-13T12:00:00Z")!
        #expect(Firebase.age(depuis: t, maintenant: t.addingTimeInterval(30)) == "1 min")
        #expect(Firebase.age(depuis: t, maintenant: t.addingTimeInterval(59 * 60)) == "59 min")
        #expect(Firebase.age(depuis: t, maintenant: t.addingTimeInterval(3600)) == "1 h")
        #expect(Firebase.age(depuis: t, maintenant: t.addingTimeInterval(24 * 3600 - 60)) == "23 h")
        #expect(Firebase.age(depuis: t, maintenant: t.addingTimeInterval(24 * 3600)) == "1 j")
    }
}
