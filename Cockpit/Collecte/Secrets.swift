import Foundation
import Security

/// Les clés des sources. Ordre : variable d'environnement du même nom, Trousseau
/// (service `cockpit`, compte `<business>.<NOM>`), Secret Manager du projet Firebase du business.
/// Une valeur n'est jamais écrite sur le disque, dans la base ni dans un log.
final class Secrets {
    static let service = "cockpit"
    private let gcloud: GCloud
    private let http: HTTP
    private var cache: [String: String] = [:]

    init(gcloud: GCloud, http: HTTP) {
        self.gcloud = gcloud
        self.http = http
    }

    func valeur(_ nom: String, _ b: Business) async throws -> String {
        let compte = "\(b.id).\(nom)"
        if let v = cache[compte] { return v }
        if let v = ProcessInfo.processInfo.environment[nom], !v.isEmpty { return v }
        if let v = try Trousseau.lire(Secrets.service, compte) {
            cache[compte] = v
            return v
        }
        guard let projet = b.config.firebaseProject else {
            throw SourceErreur.nonConfigure("clé \(nom) absente du Trousseau pour \(b.nom)")
        }
        let v = try await secretManager(nom, projet)
        cache[compte] = v
        return v
    }

    /// Range une clé dans le Trousseau (Réglages).
    func enregistrer(_ nom: String, _ b: Business, _ valeur: String) throws {
        let compte = "\(b.id).\(nom)"
        try Trousseau.ecrire(Secrets.service, compte, valeur)
        cache[compte] = valeur
    }

    func effacer(_ nom: String, _ b: Business) throws {
        let compte = "\(b.id).\(nom)"
        try Trousseau.effacer(Secrets.service, compte)
        cache[compte] = nil
    }

    /// Où la clé est rangée, sans la lire ailleurs que dans le Trousseau : pour Réglages.
    func dansTrousseau(_ nom: String, _ b: Business) -> Bool {
        (try? Trousseau.lire(Secrets.service, "\(b.id).\(nom)")) != nil
    }

    private func secretManager(_ nom: String, _ projet: String) async throws -> String {
        let jeton = try await gcloud.jeton()
        let url = "https://secretmanager.googleapis.com/v1/projects/\(projet)/secrets/\(nom)/versions/latest:access"
        let reponse: [String: Any]
        do {
            reponse = try await http.objet(HTTP.requete(url, jeton: jeton, entetes: ["x-goog-user-project": projet]))
        } catch SourceErreur.http(let code, _) where code == 404 || code == 403 {
            throw SourceErreur.nonConfigure("clé \(nom) absente du Trousseau et de Secret Manager (\(projet))")
        }
        guard let charge = reponse["payload"] as? [String: Any], let b64 = charge["data"] as? String,
              let data = Data(base64Encoded: b64) else {
            throw SourceErreur.format("Secret Manager, \(nom) sans payload")
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Mots de passe génériques du Trousseau de session.
enum Trousseau {
    static func lire(_ service: String, _ compte: String) throws -> String? {
        let requete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: compte,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var resultat: AnyObject?
        let statut = SecItemCopyMatching(requete as CFDictionary, &resultat)
        if statut == errSecItemNotFound { return nil }
        guard statut == errSecSuccess, let data = resultat as? Data else { throw erreur(statut) }
        return String(decoding: data, as: UTF8.self)
    }

    static func ecrire(_ service: String, _ compte: String, _ valeur: String) throws {
        try effacer(service, compte)
        let requete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: compte,
            kSecValueData as String: Data(valeur.utf8),
        ]
        let statut = SecItemAdd(requete as CFDictionary, nil)
        guard statut == errSecSuccess else { throw erreur(statut) }
    }

    static func effacer(_ service: String, _ compte: String) throws {
        let requete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: compte,
        ]
        let statut = SecItemDelete(requete as CFDictionary)
        guard statut == errSecSuccess || statut == errSecItemNotFound else { throw erreur(statut) }
    }

    private static func erreur(_ statut: OSStatus) -> Error {
        let message = SecCopyErrorMessageString(statut, nil) as String? ?? "code \(statut)"
        return SourceErreur.commande("Trousseau : \(message)")
    }
}
