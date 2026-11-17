import CryptoKit
import Foundation
import Testing
@testable import CockpitNoyau

/// Réponses figées de l'API App Store Connect (ids inventés) et forme du JWT.
@MainActor
struct AppStoreConnectTests {
    let store = try! Store.memoire()
    let maintenant = Date(iso: "2026-11-13T00:00:00Z")!

    static let avis = #"""
        {"data":[
          {"type":"customerReviews","id":"r-top","attributes":{"rating":5,"title":"Top","body":"Super app",
            "reviewerNickname":"Lea","createdDate":"2026-11-11T00:18:14-08:00","territory":"FRA"},
            "relationships":{"response":{"data":null,"links":{"self":"…"}}}},
          {"type":"customerReviews","id":"r-repondu","attributes":{"rating":2,"title":"Bof","body":"Trop cher",
            "reviewerNickname":"Max","createdDate":"2026-11-10T09:00:00-08:00","territory":"BEL"},
            "relationships":{"response":{"data":{"type":"customerReviewResponses","id":"rep-1"}}}},
          {"type":"customerReviews","id":"r-moyen","attributes":{"rating":3,"title":null,"body":"Correct",
            "reviewerNickname":"Sam","createdDate":"2026-11-02T10:00:00-07:00","territory":"FRA"},
            "relationships":{"response":{"data":null}}},
          {"type":"customerReviews","id":"r-nul","attributes":{"rating":1,"title":"Nul","body":"Plante",
            "reviewerNickname":"Tom","createdDate":"2026-10-01T10:00:00-07:00","territory":"ESP"},
            "relationships":{"response":{"data":null}}}],
         "included":[{"type":"customerReviewResponses","id":"rep-1","attributes":{"responseBody":"Merci","state":"PUBLISHED"}}],
         "links":{"self":"…"},"meta":{"paging":{"total":4,"limit":200}}}
        """#

    static let versions = #"""
        {"data":[
          {"type":"appStoreVersions","id":"v-203","attributes":{"platform":"IOS","versionString":"2.0.3",
            "appStoreState":"READY_FOR_SALE","appVersionState":"READY_FOR_DISTRIBUTION","createdDate":"2026-11-01T14:25:38-08:00"}},
          {"type":"appStoreVersions","id":"v-204","attributes":{"platform":"IOS","versionString":"2.0.4",
            "appStoreState":"WAITING_FOR_REVIEW","appVersionState":"WAITING_FOR_REVIEW","createdDate":"2026-11-12T08:00:00-08:00"}}],
         "links":{"self":"…"},"meta":{"paging":{"total":2,"limit":5}}}
        """#

    static func base64url(_ s: Substring) throws -> Data {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b += String(repeating: "=", count: (4 - b.count % 4) % 4)
        return try #require(Data(base64Encoded: b))
    }

    @Test func jetonSigneES256() throws {
        let cle = P256.Signing.PrivateKey()
        let jwt = try AppStoreConnect.jeton(kid: "KEY1234", issuer: "issuer-1", cle: cle, maintenant: maintenant)
        #expect(!jwt.contains("=") && !jwt.contains("+") && !jwt.contains("/"))
        let parties = jwt.split(separator: ".")
        try #require(parties.count == 3)
        let entete = try #require(try JSONSerialization.jsonObject(with: Self.base64url(parties[0])) as? [String: Any])
        #expect(entete["alg"] as? String == "ES256")
        #expect(entete["kid"] as? String == "KEY1234")
        #expect(entete["typ"] as? String == "JWT")
        let charge = try #require(try JSONSerialization.jsonObject(with: Self.base64url(parties[1])) as? [String: Any])
        let iat = try #require(charge["iat"] as? Int)
        let exp = try #require(charge["exp"] as? Int)
        #expect(charge["iss"] as? String == "issuer-1")
        #expect(charge["aud"] as? String == "appstoreconnect-v1")
        #expect(iat == Int(maintenant.timeIntervalSince1970))
        #expect(exp > iat && exp - iat <= 20 * 60)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: Self.base64url(parties[2]))
        #expect(cle.publicKey.isValidSignature(signature, for: Data("\(parties[0]).\(parties[1])".utf8)))
        #expect(!P256.Signing.PrivateKey().publicKey.isValidSignature(signature, for: Data("\(parties[0]).\(parties[1])".utf8)))
    }

    @Test func cleLueDansLeDossier() throws {
        let dossier = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dossier) }
        #expect(throws: SourceErreur.self) { try AppStoreConnect.cle(dossier: dossier) }
        let cle = P256.Signing.PrivateKey()
        try cle.pemRepresentation.write(to: dossier.appending(path: "AuthKey_TEST1234.p8"), atomically: true, encoding: .utf8)
        let lue = try AppStoreConnect.cle(dossier: dossier)
        #expect(lue.kid == "TEST1234")
        #expect(lue.cle.publicKey.rawRepresentation == cle.publicKey.rawRepresentation)
    }

    @Test func avisDecodes() throws {
        let avis = try AppStoreConnect.avis(Data(Self.avis.utf8), business: "roleo")
        #expect(avis.map(\.id) == ["r-top", "r-repondu", "r-moyen", "r-nul"])
        #expect(avis.map(\.repondu) == [false, true, false, false])
        #expect(avis[0].at == Date(iso: "2026-11-11T08:18:14Z"))
        #expect(avis[0].pays == "FRA")
        #expect(avis[0].auteur == "Lea")
        #expect(avis[2].titre == nil)
    }

    @Test func tachesPourLesAvisSansReponse() throws {
        let avis = try AppStoreConnect.avis(Data(Self.avis.utf8), business: "roleo")
        let taches = AppStoreConnect.taches(avis, app: "123")
        #expect(taches.map(\.cle) == ["avis:r-moyen", "avis:r-nul"])
        #expect(taches.map(\.ton) == [.neutre, .alerte])
        #expect(taches[0].texte == "Répondre à Sam")
        #expect(taches[1].texte == "Répondre à Tom, « Nul »")
        #expect(taches[1].etiquette == "1 ★")
        #expect(taches[1].lien == "https://appstoreconnect.apple.com/apps/123/distribution/activity/ios/ratingsResponses")
    }

    @Test func filDesAvisRecents() throws {
        let avis = try AppStoreConnect.avis(Data(Self.avis.utf8), business: "roleo")
        let fil = AppStoreConnect.filAvis(avis, app: "123", maintenant: maintenant)
        #expect(fil.map(\.id) == ["asc:avis:r-top", "asc:avis:r-repondu"])
        #expect(fil.map(\.texte) == ["★★★★★ Top", "★★☆☆☆ Bof"])
        #expect(fil.allSatisfy { $0.type == .avis })
    }

    @Test func versionLaPlusRecente() throws {
        let data = Data(Self.versions.utf8)
        let v = try #require(try AppStoreConnect.version(data, business: "roleo", app: "123", at: maintenant))
        #expect(v.id == "asc:version:v-204:WAITING_FOR_REVIEW")
        #expect(v.texte == "2.0.4 en attente d'examen")
        #expect(v.at == maintenant)
        let premier = try #require(try AppStoreConnect.version(data, business: "roleo", app: "123", at: nil))
        #expect(premier.at == Date(iso: "2026-11-12T16:00:00Z"))
        #expect(try AppStoreConnect.version(Data(#"{"data":[]}"#.utf8), business: "roleo", app: "123", at: nil) == nil)
    }

    @Test func etats() {
        #expect(AppStoreConnect.etat("READY_FOR_SALE") == "en vente")
        #expect(AppStoreConnect.etat("IN_REVIEW") == "en examen")
        #expect(AppStoreConnect.etat("NOUVEL_ETAT") == "nouvel etat")
    }

    @Test func ecritureDansLeStore() throws {
        let avis = try AppStoreConnect.avis(Data(Self.avis.utf8), business: "roleo")
        let version = try AppStoreConnect.version(Data(Self.versions.utf8), business: "roleo", app: "123", at: maintenant)
        let n = try AppStoreConnect.ecrire(avis, version: version, app: "123", business: "roleo", store, maintenant: maintenant)
        // 4 avis, 2 tâches, 2 avis récents et une version dans le fil
        #expect(n == 9)
        #expect(try store.db.query("select id from avis where repondu = 1").compactMap { $0.texte("id") } == ["r-repondu"])
        #expect(try store.db.query("select id from fil order by id").compactMap { $0.texte("id") }
                == ["asc:avis:r-repondu", "asc:avis:r-top", "asc:version:v-204:WAITING_FOR_REVIEW"])
        let ouvertes = try store.db.query("select id, ton from a_traiter where fait_le is null order by id")
        #expect(ouvertes.compactMap { $0.texte("id") } == ["asc:avis:r-moyen", "asc:avis:r-nul"])
        #expect(ouvertes.compactMap { $0.texte("ton") } == ["neutre", "alerte"])

        // l'avis à 3 étoiles a reçu une réponse : sa tâche passe à fait, rien ne rentre deux fois dans le fil
        let suite = avis.map { a in var a = a; if a.id == "r-moyen" { a.repondu = true }; return a }
        let m = try AppStoreConnect.ecrire(suite, version: version, app: "123", business: "roleo", store, maintenant: maintenant)
        #expect(m == 5)
        #expect(try store.db.query("select id from a_traiter where fait_le is null").compactMap { $0.texte("id") } == ["asc:avis:r-nul"])
        #expect(try store.db.query("select count(*) as n from fil").first?.entier("n") == 3)
    }

    /// Un rapport de ventes quotidien : premiers téléchargements (1F, 1T) de l'app, sans retéléchargement (3F), mise à
    /// jour (7F), achat intégré (IAY) ni autre app.
    @Test func telechargementsDuRapportDeVentes() throws {
        let colonnes = ["Provider", "SKU", "Product Type Identifier", "Units", "Begin Date", "Apple Identifier"]
        let lignes = [["APPLE", "roleo", "1F", "12", "11/12/2026", "123"], ["APPLE", "roleo", "1F", "3", "11/12/2026", "123"],
                      ["APPLE", "roleo", "1T", "2", "11/12/2026", "123"], ["APPLE", "roleo", "3F", "7", "11/12/2026", "123"],
                      ["APPLE", "roleo", "7F", "40", "11/12/2026", "123"], ["APPLE", "an", "IAY", "1", "11/12/2026", "123"],
                      ["APPLE", "autre", "1F", "50", "11/12/2026", "999"]]
        let tsv = ([colonnes] + lignes).map { $0.joined(separator: "\t") }.joined(separator: "\r\n") + "\r\n"
        #expect(try AppStoreConnect.telechargements(Data(tsv.utf8), app: "123") == 17)
        #expect(throws: SourceErreur.self) { try AppStoreConnect.telechargements(Data("Provider\tUnits\n".utf8), app: "123") }
    }

    @Test func joursDeVentesARelire() {
        let tous = Set(Jour.derniers(AppStoreConnect.historiqueVentes, jusqua: "2026-11-12"))
        #expect(AppStoreConnect.aRelire(tous, jusqua: "2026-11-13").isEmpty)
        let manquants = AppStoreConnect.aRelire(tous.subtracting(["2026-11-12", "2026-10-01"]), jusqua: "2026-11-13")
        #expect(manquants == ["2026-10-01", "2026-11-12"])
    }

    @Test func telechargementsSommentLesStores() throws {
        let t = Metrique.telechargements
        try Boutique.appStore.telechargements("roleo", jour: "2026-11-12", 47, store)
        #expect(try store.db.query("select valeur from serie where metrique = ?", [t]).first?.nombre("valeur") == 47)
        try Boutique.playStore.telechargements("roleo", jour: "2026-11-12", 6, store)
        #expect(try store.db.query("select valeur from serie where metrique = ?", [t]).first?.nombre("valeur") == 53)
    }
}
