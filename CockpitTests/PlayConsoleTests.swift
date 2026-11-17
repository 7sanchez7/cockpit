import Foundation
import Security
import Testing
@testable import CockpitNoyau

/// Rapports Play figés et JWT RS256 du compte de service, avec une clé RSA tirée pour le test.
@MainActor
struct PlayConsoleTests {
    static let prefixe = "stats/installs/installs_app.roleo.roleo_"

    @Test func moisLus() {
        let noms = ["202607", "202608", "202609", "202610", "202611"].map { Self.prefixe + $0 + "_overview.csv" }
            + [Self.prefixe + "202611_country.csv", "stats/installs/installs_autre.app_202611_overview.csv"]
        #expect(PlayConsole.aLire(noms.shuffled(), prefixe: Self.prefixe, jusqua: "2026-11-14")
            == ["202608", "202609", "202610", "202611"].map { Self.prefixe + $0 + "_overview.csv" })
    }

    @Test func bucketCopieDepuisLaConsole() {
        for config in ["pubsite_prod_rev_0123", " gs://pubsite_prod_rev_0123/ ", "gs://pubsite_prod_rev_0123/stats/installs"] {
            #expect(PlayConsole.bucket(config) == "pubsite_prod_rev_0123")
        }
    }

    @Test func rapportEnUTF16() throws {
        let csv = """
            Date,Package Name,Daily Device Installs,Daily Device Uninstalls,Daily Device Upgrades,Total User Installs,\
            Daily User Installs,Daily User Uninstalls,Active Device Installs,Install events,Update events,Uninstall events
            2026-11-14,app.roleo.roleo,4,0,0,4,3,0,4,4,0,0
            2026-11-15,app.roleo.roleo,9,1,0,12,8,1,11,10,0,1

            """
        let data = try #require(csv.data(using: .utf16))
        #expect(data.prefix(2) == Data([0xFF, 0xFE]))
        #expect(try PlayConsole.installs(data) == ["2026-11-14": 3, "2026-11-15": 8])
        #expect(throws: SourceErreur.self) { try PlayConsole.installs(Data("Date,Installs\n2026-11-14,3\n".utf8)) }
    }

    @Test func assertionSigneeRS256() throws {
        let attributs: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048]
        let privee = try #require(SecKeyCreateRandomKey(attributs as CFDictionary, nil))
        let pkcs1 = try #require(SecKeyCopyExternalRepresentation(privee, nil) as Data?)
        // PrivateKeyInfo : version 0, algorithme rsaEncryption, la clé PKCS#1 en OCTET STRING
        let algorithme: [UInt8] = [0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00]
        let pkcs8 = Self.der(0x30, [0x02, 0x01, 0x00] + algorithme + Self.der(0x04, [UInt8](pkcs1)))
        #expect(try PlayConsole.pkcs1(Data(pkcs8)) == pkcs1)

        let pem = "-----BEGIN PRIVATE KEY-----\n" + Data(pkcs8).base64EncodedString(options: .lineLength64Characters)
            + "\n-----END PRIVATE KEY-----\n"
        let compte = PlayConsole.CompteService(email: "play@exemple.iam.gserviceaccount.com",
                                               urlJeton: "https://oauth2.googleapis.com/token", cle: try PlayConsole.cleRSA(pem))
        let maintenant = Date(iso: "2026-11-14T12:00:00Z")!
        let parties = try PlayConsole.assertion(compte, maintenant: maintenant).split(separator: ".")
        try #require(parties.count == 3)
        let charge = try #require(try JSONSerialization.jsonObject(with: Self.base64url(parties[1])) as? [String: Any])
        #expect(charge["iss"] as? String == compte.email)
        #expect(charge["scope"] as? String == "https://www.googleapis.com/auth/devstorage.read_only")
        #expect(charge["aud"] as? String == compte.urlJeton)
        #expect(charge["exp"] as? Int == Int(maintenant.timeIntervalSince1970) + 3600)
        let publique = try #require(SecKeyCopyPublicKey(privee))
        #expect(SecKeyVerifySignature(publique, .rsaSignatureMessagePKCS1v15SHA256, Data("\(parties[0]).\(parties[1])".utf8) as CFData,
                                      try Self.base64url(parties[2]) as CFData, nil))
    }

    @Test func pkcs8Abime() {
        #expect(throws: SourceErreur.self) { try PlayConsole.pkcs1(Data([0x30, 0x82, 0xff])) }
        #expect(throws: SourceErreur.self) { try PlayConsole.cleRSA("-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----") }
    }

    static func der(_ tag: UInt8, _ contenu: [UInt8]) -> [UInt8] {
        let n = contenu.count
        let longueur: [UInt8] = n < 0x80 ? [UInt8(n)] : n < 0x100 ? [0x81, UInt8(n)] : [0x82, UInt8(n >> 8), UInt8(n & 0xff)]
        return [tag] + longueur + contenu
    }

    static func base64url(_ s: Substring) throws -> Data {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b += String(repeating: "=", count: (4 - b.count % 4) % 4)
        return try #require(Data(base64Encoded: b))
    }
}
