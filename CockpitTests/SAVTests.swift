import Foundation
import Testing
@testable import CockpitNoyau

@MainActor
struct SAVTests {
    let store = try! Store.memoire()
    var lectures: Lectures { Lectures(db: store.db, businesses: try! store.businesses()) }
    let u1 = CleFil(business: "roleo", uid: "u1")

    func document(_ json: String) throws -> Firestore.Document {
        try JSONDecoder().decode(Firestore.Document.self, from: Data(json.utf8))
    }

    func user(_ champs: String) throws -> FilSAV {
        try Firebase.fil(document(#"{"name": "projects/p/databases/(default)/documents/users/u1", "fields": {\#(champs)}}"#),
                         business: "roleo")
    }

    func fil(_ uid: String, _ at: String, ouvert: Bool, equipe: Bool = false) -> FilSAV {
        FilSAV(business: "roleo", uid: uid, nom: nil, dernierAt: Date(iso: at)!, dernierEquipe: equipe, apercu: "salut",
               ouvert: ouvert, nonVu: false)
    }

    func retour(_ id: String, traite: Bool, uid: String? = nil, at: String = "2026-11-14T10:00:00Z") -> RetourSAV {
        RetourSAV(business: "roleo", id: id, uid: uid, source: "profile", categorie: "idea", message: "une idée", traite: traite,
                  at: Date(iso: at)!)
    }

    func message(_ id: String, equipe: Bool = false, _ at: String) -> MessageSAV {
        MessageSAV(id: id, equipe: equipe, texte: id, at: Date(iso: at)!)
    }

    func ouvertes() throws -> Set<String> {
        Set(try store.db.query("select id from a_traiter where fait_le is null").compactMap { $0.texte("id") })
    }

    // MARK: lecture de Firestore

    @Test func etatDuFil() throws {
        let at = #""supportLastAt": {"timestampValue": "2026-11-14T10:00:00.250Z"}"#
        let aRepondre = try user(at + #", "supportLastFrom": {"stringValue": "user"}, "supportOpen": {"booleanValue": true},"# +
                                 #""supportPreview": {"stringValue": "Bonjour"}, "displayName": {"stringValue": "Lina"}"#)
        #expect(aRepondre.etat == .aRepondre)
        #expect(aRepondre.nom == "Lina")
        #expect(aRepondre.apercu == "Bonjour")
        #expect(aRepondre.dernierAt.iso == "2026-11-14T10:00:00Z")
        let unread = #""supportUnread": {"mapValue": {"fields": {"id": {"stringValue": "m1"}, "text": {"stringValue": "Re"},"# +
            #""at": {"timestampValue": "2026-11-14T10:00:00Z"}}}}"#
        let equipe = at + #", "supportLastFrom": {"stringValue": "team"}, "supportOpen": {"booleanValue": false}"#
        #expect(try user(equipe + ", " + unread).etat == .pasLu)
        #expect(try user(equipe + #", "supportUnread": {"nullValue": null}"#).etat == .lu)
        #expect(try user(at + #", "supportLastFrom": {"stringValue": "user"}, "displayName": {"stringValue": ""}"#).etat == .traite)
        #expect(try user(at).nom == nil)
        #expect(throws: SourceErreur.self) { try user(#""supportOpen": {"booleanValue": true}"#) }
    }

    @Test func retourLu() throws {
        let complet = try Firebase.retour(document("""
            {"name": "projects/p/databases/(default)/documents/feedback/r1", "fields": {
              "uid": {"stringValue": "u1"}, "source": {"stringValue": "chat_report"}, "category": {"stringValue": "weird"},
              "message": {"stringValue": "bizarre"}, "quote": {"stringValue": "Hola"}, "conversationId": {"stringValue": "c1"},
              "status": {"stringValue": "done"}, "handledAt": {"timestampValue": "2026-11-14T11:00:00Z"},
              "platform": {"stringValue": "ios"}, "appBuild": {"integerValue": "49"}, "stars": {"integerValue": "2"},
              "createdAt": {"timestampValue": "2026-11-14T10:00:00Z"}}}
            """), business: "roleo")
        #expect(complet.id == "r1")
        #expect(complet.uid == "u1")
        #expect(complet.source == "chat_report")
        #expect(complet.categorie == "weird")
        #expect(complet.citation == "Hola")
        #expect(complet.conversation == "c1")
        #expect(complet.traite)
        #expect(complet.traiteLe?.iso == "2026-11-14T11:00:00Z")
        #expect(complet.plateforme == "ios")
        #expect(complet.build == "49")
        #expect(complet.etoiles == 2)
        let ancien = try Firebase.retour(document("""
            {"name": "a/feedback/r0", "fields": {"message": {"stringValue": "vieux"}, "status": {"stringValue": "new"},
              "createdAt": {"timestampValue": "2026-09-01T10:00:00Z"}}}
            """), business: "roleo")
        #expect(ancien.uid == nil && ancien.source == nil && ancien.categorie == nil && ancien.build == nil)
        #expect(!ancien.traite)
        #expect(throws: SourceErreur.self) {
            try Firebase.retour(document(#"{"name": "a/feedback/r2", "fields": {"message": {"stringValue": "x"}}}"#), business: "roleo")
        }
    }

    @Test func messageLu() throws {
        let m = try Firebase.message(document("""
            {"name": "a/users/u1/support/m1", "fields": {"from": {"stringValue": "team"}, "text": {"stringValue": "Re"},
              "createdAt": {"timestampValue": "2026-11-14T10:00:00Z"}}}
            """))
        #expect(m == MessageSAV(id: "m1", equipe: true, texte: "Re", at: Date(iso: "2026-11-14T10:00:00Z")!))
    }

    // MARK: écriture

    @Test func apercuEtReponse() {
        #expect(Firebase.apercu("Salut\n\n  toi\t!") == "Salut toi !")
        let long = String(repeating: "é", count: 200)
        #expect(Firebase.apercu(long).unicodeScalars.count == Firebase.longueurApercu)
        #expect(Firebase.apercu(long).hasSuffix("…"))
        let juste = String(repeating: "a", count: Firebase.longueurApercu)
        #expect(Firebase.apercu(juste) == juste)
        #expect(Firebase.reponse("  merci \n") == "merci")
        #expect(Firebase.reponse(" \n ") == nil)
        #expect(Firebase.reponse(String(repeating: "a", count: Firebase.longueurReponse)) != nil)
        #expect(Firebase.reponse(String(repeating: "a", count: Firebase.longueurReponse + 1)) == nil)
        let id = Firebase.nouvelId()
        #expect(id.count == 20 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    @Test func valeursFirestore() throws {
        let instant = Date(iso: "2026-11-14T10:00:00.250Z")!
        #expect(try Firestore.valeur(nil)["nullValue"] is NSNull)
        #expect(try Firestore.valeur(true)["booleanValue"] as? Bool == true)
        #expect(try Firestore.valeur(3)["integerValue"] as? String == "3")
        #expect(try Firestore.valeur("x")["stringValue"] as? String == "x")
        #expect(try Firestore.valeur(instant)["timestampValue"] as? String == "2026-11-14T10:00:00.250Z")
        let carte = try Firestore.valeur(["id": "m1", "at": nil] as [String: Any?])
        let champs = (carte["mapValue"] as? [String: Any])?["fields"] as? [String: [String: Any]]
        #expect(champs?["id"]?["stringValue"] as? String == "m1")
        #expect(champs?["at"]?["nullValue"] is NSNull)
        #expect(throws: SourceErreur.self) { try Firestore.valeur(1.5) }
    }

    @Test func ecritureFirestore() throws {
        let f = Firestore(projet: "p", http: HTTP(), jeton: "j")
        let e = try f.ecriture("users/u1", ["supportOpen": false, "supportPreview": "Re"], existe: true)
        let update = e["update"] as? [String: Any]
        #expect(update?["name"] as? String == "projects/p/databases/(default)/documents/users/u1")
        #expect((update?["fields"] as? [String: [String: Any]])?["supportOpen"]?["booleanValue"] as? Bool == false)
        #expect(Set((e["updateMask"] as? [String: [String]])?["fieldPaths"] ?? []) == ["supportOpen", "supportPreview"])
        #expect((e["currentDocument"] as? [String: Bool])?["exists"] == true)
        #expect(JSONSerialization.isValidJSONObject(e))
    }

    @Test func notifSupport() {
        let n = Firebase.notif("jeton", titre: "Roleo", id: "m1", corps: "Re")
        #expect(n["token"] as? String == "jeton")
        #expect(n["data"] as? [String: String] == ["kind": "support", "message_id": "m1", "title": "Roleo", "body": "Re"])
        #expect(n["android"] as? [String: String] == ["priority": "HIGH"])
        let aps = ((n["apns"] as? [String: Any])?["payload"] as? [String: Any])?["aps"] as? [String: Any]
        #expect(aps?["alert"] as? [String: String] == ["title": "Roleo", "body": "Re"])
        #expect(JSONSerialization.isValidJSONObject(n))
    }

    // MARK: base

    @Test func synchronisation() throws {
        var r = ReleveSAV()
        r.fils = [fil("u1", "2026-11-14T10:00:00Z", ouvert: true), fil("u2", "2026-11-14T11:00:00Z", ouvert: false, equipe: true)]
        r.retours = [retour("r1", traite: false, uid: "u1"), retour("r2", traite: true)]
        r.messages = ["u1": [message("m1", "2026-11-14T09:00:00Z"), message("m2", "2026-11-14T10:00:00Z")]]
        r.emails = ["u1": "lina@exemple.fr", "u2": ""]
        #expect(try store.synchroniserSAV(business: "roleo", r) == 8)
        #expect(try store.filsLus(business: "roleo") == ["u1": "2026-11-14T10:00:00Z"])
        #expect(try store.comptesSAV(business: "roleo") == ["u1"])
        #expect(lectures.nbSAV() == (fils: 1, retours: 1))
        #expect(lectures.retoursSAV(traites: false).first?.email == "lina@exemple.fr")
        #expect(lectures.emailSAV(CleFil(business: "roleo", uid: "u2")) == "")
        #expect(lectures.emailSAV(CleFil(business: "roleo", uid: "u9")) == nil)

        // u1 et r1 traités sur le dashboard : absents du relevé suivant ; u2 relu
        var suite = ReleveSAV()
        suite.fils = [fil("u2", "2026-11-14T12:00:00Z", ouvert: true)]
        suite.messages = ["u2": [message("m3", "2026-11-14T12:00:00Z")]]
        _ = try store.synchroniserSAV(business: "roleo", suite)
        #expect(lectures.filSAV(u1)?.ouvert == false)
        #expect(lectures.retoursSAV(traites: false).isEmpty)
        #expect(lectures.messagesSAV(u1).map(\.id) == ["m1", "m2"])
        #expect(lectures.messagesSAV(CleFil(business: "roleo", uid: "u2")).map(\.id) == ["m3"])

        // un fil relu remplace ses messages
        var relu = ReleveSAV()
        relu.messages = ["u1": [message("m4", "2026-11-14T13:00:00Z")]]
        _ = try store.synchroniserSAV(business: "roleo", relu)
        #expect(lectures.messagesSAV(u1).map(\.id) == ["m4"])
    }

    @Test func filsRanges() throws {
        var r = ReleveSAV()
        r.fils = [fil("u1", "2026-11-14T08:00:00Z", ouvert: true), fil("u2", "2026-11-14T12:00:00Z", ouvert: false),
                  fil("u3", "2026-11-14T10:00:00Z", ouvert: false)]
        r.emails = ["u2": "a@exemple.fr"]
        _ = try store.synchroniserSAV(business: "roleo", r)
        let fils = lectures.filsSAV()
        #expect(fils.map(\.uid) == ["u1", "u2", "u3"])
        #expect(fils[1].email == "a@exemple.fr")
        #expect(fils[2].email == nil)
    }

    @Test func reponseFermeLeFilEtSesTaches() throws {
        try store.synchroniserTaches(source: "firebase", business: "roleo", [
            Tache(cle: "msg:u1:2026-11-14T10:00:00Z", texte: "Bonjour"),
            Tache(cle: "msg:u10:2026-11-14T10:00:00Z", texte: "Autre"),
        ])
        var r = ReleveSAV()
        r.fils = [fil("u1", "2026-11-14T10:00:00Z", ouvert: true)]
        _ = try store.synchroniserSAV(business: "roleo", r)
        try store.repondreSAV(u1, message("m9", equipe: true, "2026-11-14T11:00:00Z"), apercu: "Re")
        let f = try #require(lectures.filSAV(u1))
        #expect(f.etat == .pasLu)
        #expect(f.apercu == "Re")
        #expect(f.dernierAt.iso == "2026-11-14T11:00:00Z")
        #expect(lectures.messagesSAV(u1).map(\.id) == ["m9"])
        #expect(try ouvertes() == ["firebase:msg:u10:2026-11-14T10:00:00Z"])

        // un compte qui n'avait jamais écrit : le fil naît de la réponse
        let u5 = CleFil(business: "roleo", uid: "u5")
        try store.repondreSAV(u5, message("m10", equipe: true, "2026-11-14T12:00:00Z"), apercu: "Bienvenue")
        #expect(lectures.filSAV(u5)?.etat == .pasLu)
    }

    @Test func fermerSansRepondre() throws {
        try store.synchroniserTaches(source: "firebase", business: "roleo", [Tache(cle: "msg:u1:2026-11-14T10:00:00Z", texte: "x")])
        var r = ReleveSAV()
        r.fils = [fil("u1", "2026-11-14T10:00:00Z", ouvert: true)]
        _ = try store.synchroniserSAV(business: "roleo", r)
        try store.fermerFilSAV(u1)
        #expect(lectures.filSAV(u1)?.etat == .traite)
        #expect(try ouvertes().isEmpty)
    }

    @Test func traiterEtRouvrirUnRetour() throws {
        try store.synchroniserTaches(source: "firebase", business: "roleo", [Tache(cle: "retour:r1", texte: "Idée")])
        var r = ReleveSAV()
        r.retours = [retour("r1", traite: false)]
        _ = try store.synchroniserSAV(business: "roleo", r)
        let le = Date(iso: "2026-11-14T12:00:00Z")!
        try store.traiterRetourSAV(business: "roleo", id: "r1", traite: true, le: le)
        #expect(lectures.retoursSAV(traites: true).first?.traiteLe == le)
        #expect(try ouvertes().isEmpty)
        try store.traiterRetourSAV(business: "roleo", id: "r1", traite: false, le: le)
        #expect(lectures.retoursSAV(traites: false).first?.traiteLe == nil)
        #expect(try ouvertes() == ["firebase:retour:r1"])
    }
}
