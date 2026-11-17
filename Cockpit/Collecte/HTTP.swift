import Foundation

/// Appels réseau des sources : une session sans cookies partagés, rejeu sur 429 et 5xx.
struct HTTP {
    /// Pour les pages publiques qui ne répondent qu'à un navigateur.
    static let navigateur = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
    /// Safari, pour les sessions lues dans Safari : un site peut refuser une session qui change de navigateur.
    static let safari = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.2 Safari/605.1.15"

    let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = 60
        return URLSession(configuration: c)
    }()

    /// Une requête prête : `jeton` part en `Authorization: Bearer`, `corps` est encodé en JSON.
    static func requete(_ url: String, methode: String = "GET", jeton: String? = nil, corps: Any? = nil,
                        entetes: [String: String] = [:]) throws -> URLRequest {
        guard let u = URL(string: url) else { throw SourceErreur.format("URL invalide") }
        var r = URLRequest(url: u)
        r.httpMethod = methode
        if let jeton { r.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization") }
        if let corps {
            r.httpBody = try JSONSerialization.data(withJSONObject: corps)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (k, v) in entetes { r.setValue(v, forHTTPHeaderField: k) }
        return r
    }

    /// Le corps d'une réponse 2xx. Rejoue jusqu'à 3 fois sur 429 et 5xx (Retry-After respecté, 30 s au plus).
    func donnees(_ requete: URLRequest) async throws -> Data {
        var attente = 1.0
        for essai in 1...3 {
            let (data, reponse) = try await session.data(for: requete)
            let http = reponse as? HTTPURLResponse
            let code = http?.statusCode ?? 0
            if (200..<300).contains(code) { return data }
            if (code == 429 || code >= 500) && essai < 3 {
                let delai = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? attente
                try await Task.sleep(for: .seconds(min(delai, 30)))
                attente *= 2
                continue
            }
            throw SourceErreur.http(code, String(decoding: data.prefix(300), as: UTF8.self))
        }
        throw SourceErreur.http(0, "aucune réponse")
    }

    /// Le corps décodé en type `Decodable`.
    func json<T: Decodable>(_ type: T.Type, _ requete: URLRequest) async throws -> T {
        let data = try await donnees(requete)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SourceErreur.format("\(T.self) : \(error)")
        }
    }

    /// Le corps en dictionnaire, pour les réponses qu'on ne lit qu'en partie.
    func objet(_ requete: URLRequest) async throws -> [String: Any] {
        let data = try await donnees(requete)
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SourceErreur.format("pas un objet JSON : \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        return o
    }
}
