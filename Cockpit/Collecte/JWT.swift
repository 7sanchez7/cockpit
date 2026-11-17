import Foundation

/// Les JWT signés sur le Mac : ES256 pour App Store Connect, RS256 pour les comptes de service Google.
enum JWT {
    /// `entete.charge.signature` en base64url, la signature calculée sur `entete.charge`.
    static func jeton(entete: [String: Any], charge: [String: Any], signe: (Data) throws -> Data) throws -> String {
        func segment(_ o: [String: Any]) throws -> String {
            base64url(try JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes]))
        }
        let corps = try segment(entete) + "." + segment(charge)
        return corps + "." + base64url(try signe(Data(corps.utf8)))
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
