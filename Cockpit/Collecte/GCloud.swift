import Foundation

/// Un jeton OAuth Google du compte de Tony, gardé jusqu'à 5 minutes de son expiration.
/// Il ouvre Secret Manager et Firestore en REST (avec l'en-tête `x-goog-user-project`).
/// D'abord les identifiants par défaut (`gcloud auth application-default login`), rafraîchis en HTTP ;
/// sinon `gcloud auth print-access-token`.
final class GCloud {
    static let identifiants = URL.homeDirectory.appending(path: ".config/gcloud/application_default_credentials.json")
    private let http: HTTP
    private var cache: (jeton: String, expire: Date)?
    private var enCours: Task<(String, Date), Error>?

    init(http: HTTP) {
        self.http = http
    }

    func jeton() async throws -> String {
        if let cache, cache.expire > .now { return cache.jeton }
        if let enCours { return try await enCours.value.0 }
        let tache = Task { try await nouveau() }
        enCours = tache
        defer { enCours = nil }
        let (jeton, expire) = try await tache.value
        cache = (jeton, expire)
        return jeton
    }

    private func nouveau() async throws -> (String, Date) {
        if let data = try? Data(contentsOf: Self.identifiants),
           let id = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           id["type"] as? String == "authorized_user",
           let client = id["client_id"] as? String, let secret = id["client_secret"] as? String,
           let refresh = id["refresh_token"] as? String {
            var r = try HTTP.requete("https://oauth2.googleapis.com/token", methode: "POST",
                                     entetes: ["Content-Type": "application/x-www-form-urlencoded"])
            var corps = URLComponents()
            corps.queryItems = [.init(name: "grant_type", value: "refresh_token"), .init(name: "client_id", value: client),
                                .init(name: "client_secret", value: secret), .init(name: "refresh_token", value: refresh)]
            r.httpBody = Data((corps.percentEncodedQuery ?? "").utf8)
            let reponse = try await http.objet(r)
            guard let jeton = reponse["access_token"] as? String else { throw SourceErreur.format("jeton Google absent") }
            let duree = reponse["expires_in"] as? Double ?? 3600
            return (jeton, .now.addingTimeInterval(duree - 300))
        }
        let sortie: Data
        do {
            sortie = try await Commande.shell("gcloud auth print-access-token")
        } catch {
            throw SourceErreur.nonConfigure("pas de compte Google (gcloud auth application-default login) : \(error.localizedDescription)")
        }
        guard let jeton = String(decoding: sortie, as: UTF8.self).split(whereSeparator: \.isNewline).last.map(String.init),
              jeton.hasPrefix("ya29.") else {
            throw SourceErreur.nonConfigure("pas de compte Google : gcloud auth application-default login")
        }
        return (jeton, .now.addingTimeInterval(50 * 60))
    }
}
