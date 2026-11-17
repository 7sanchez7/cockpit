import Foundation

/// Ce que `yt-dlp` dit des vidéos publiques d'un compte TikTok ou YouTube : liste, compteurs, miniatures.
enum YtDlp {
    struct Liste {
        var videos: [Video] = []
        /// Les compteurs publics, sans watch time : la plateforme ne le montre qu'au propriétaire.
        var releves: [Releve] = []
        /// Id de vidéo → URL de sa miniature.
        var images: [String: String] = [:]
        /// Les abonnés de la chaîne, quand la liste les donne (YouTube).
        var abonnes: Int?
        /// L'image de la chaîne, quand la liste la donne (YouTube).
        var avatar: String?
    }

    /// `yt-dlp --flat-playlist -J` : toutes les vidéos d'une page de profil, sans les ouvrir une par une.
    static func liste(_ url: String) async throws -> Data {
        try await Commande.shell("yt-dlp --flat-playlist -J '\(url)'")
    }

    /// `yt-dlp -j` sur quelques vidéos : une ligne JSON complète par vidéo (date, durée, likes).
    static func details(_ urls: [String]) async throws -> Data {
        try await Commande.shell("yt-dlp -j --skip-download " + urls.map { "'\($0)'" }.joined(separator: " "))
    }

    static func liste(_ sortie: Data, plateforme: Plateforme, business: String, compte: String, at: Date) throws -> Liste {
        guard let o = try? JSONSerialization.jsonObject(with: sortie) as? [String: Any],
              let entrees = o["entries"] as? [[String: Any]] else {
            throw SourceErreur.format("yt-dlp \(plateforme.nom) @\(compte) : pas de liste de vidéos")
        }
        let avatar = ((o["thumbnails"] as? [[String: Any]]) ?? []).first { $0["id"] as? String == "avatar_uncropped" }
        var l = Liste(abonnes: o["channel_follower_count"] as? Int, avatar: avatar?["url"] as? String)
        for e in entrees {
            guard let (v, r, image) = entree(e, plateforme: plateforme, business: business, compte: compte, at: at) else { continue }
            l.videos.append(v)
            if let r { l.releves.append(r) }
            if let image { l.images[v.id] = image }
        }
        return l
    }

    /// La sortie de `details` : une entrée complète par ligne.
    static func details(_ sortie: Data, plateforme: Plateforme, business: String, compte: String, at: Date) throws -> Liste {
        var l = Liste()
        for ligne in sortie.split(separator: UInt8(ascii: "\n")) where !ligne.isEmpty {
            guard let e = try? JSONSerialization.jsonObject(with: Data(ligne)) as? [String: Any] else {
                throw SourceErreur.format("yt-dlp \(plateforme.nom) : ligne illisible")
            }
            guard let (v, r, _) = entree(e, plateforme: plateforme, business: business, compte: compte, at: at) else { continue }
            l.videos.append(v)
            if let r { l.releves.append(r) }
            l.abonnes = (e["channel_follower_count"] as? Int) ?? l.abonnes
        }
        return l
    }

    private static func entree(_ e: [String: Any], plateforme: Plateforme, business: String, compte: String,
                               at: Date) -> (Video, Releve?, String?)? {
        guard let brut = e["id"] as? String else { return nil }
        let id = plateforme.idVideo(brut)
        let titre = e["title"] as? String
        let description = (e["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let v = Video(id: id, business: business, compte: compte,
                      // TikTok met la légende dans `description`, YouTube le titre dans `title`
                      legende: plateforme == .tiktok ? description ?? titre : titre ?? description,
                      publieeLe: (e["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) },
                      dureeS: e["duration"] as? Double,
                      url: (e["webpage_url"] as? String) ?? (e["url"] as? String) ?? plateforme.lien(brut, compte: compte),
                      plateforme: plateforme)
        let r = (e["view_count"] as? Int).map {
            Releve(video: id, at: at, vues: $0, likes: e["like_count"] as? Int, commentaires: e["comment_count"] as? Int,
                   partages: e["repost_count"] as? Int, enregistrements: e["save_count"] as? Int)
        }
        let images = (e["thumbnails"] as? [[String: Any]]) ?? []
        // TikTok : la couverture ; YouTube : la plus grande
        let image = images.first { $0["id"] as? String == "cover" }
            ?? images.max { ($0["height"] as? Int ?? 0) < ($1["height"] as? Int ?? 0) }
        return (v, r, image?["url"] as? String)
    }
}
