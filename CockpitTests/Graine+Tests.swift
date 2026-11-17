import Foundation
@testable import CockpitNoyau

/// La graine des tests : Roleo et ses comptes vidéo.
extension Graine {
    static let json = #"""
    {
      "businesses": [
        {"id": "roleo", "nom": "Roleo", "lettre": "R", "teinte": "menthe", "config": {
          "appStoreId": "6770304361", "ascIssuer": "00000000-0000-0000-0000-000000000000", "playPackage": "app.roleo.roleo",
          "firebaseProject": "roleo-73820", "posthogHost": "https://eu.posthog.com",
          "contenuDir": "~/Documents/code/app/Roleo/contenu/bank", "pays": ["fr", "es", "be", "us"], "genre": 6017}}
      ],
      "comptes": [
        {"business": "roleo", "plateforme": "tiktok", "handle": "holaestony"},
        {"business": "roleo", "plateforme": "tiktok", "handle": "tonyolingo"},
        {"business": "roleo", "plateforme": "instagram", "handle": "holaestony"},
        {"business": "roleo", "plateforme": "youtube", "handle": "holaestony"},
        {"business": "roleo", "plateforme": "facebook", "handle": "holaestony"}
      ]
    }
    """#

    static let roleo = try! JSONDecoder().decode(Graine.self, from: Data(json.utf8))

    /// Écrit `contenu` dans un fichier temporaire neuf.
    static func fichier(_ contenu: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "graine-\(UUID().uuidString).json")
        try! Data(contenu.utf8).write(to: url)
        return url
    }

    static let url = fichier(json)
}

extension Business {
    static var roleo: Business { Graine.roleo.businesses[0] }
}

extension Store {
    /// Une base en mémoire semée avec la graine des tests.
    static func memoire() throws -> Store { try Store(chemin: ":memory:", graine: Graine.url) }
}
