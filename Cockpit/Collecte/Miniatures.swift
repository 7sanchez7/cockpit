import Foundation

/// Les images des vidéos, des comptes et des apps, téléchargées par les sources dans le cache : l'interface les lit
/// sans réseau (Miniature.swift). Une image déjà là n'est plus retéléchargée ; vider le dossier les fait toutes revenir
/// au passage suivant.
enum Miniatures {
    static let dossier = URL.cachesDirectory.appending(path: "Cockpit/miniatures")

    /// Le fichier d'une vidéo (son id) ou d'un compte (`avatar:tiktok:holaestony`).
    static func fichier(_ cle: String) -> URL {
        dossier.appending(path: cle.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_"))
    }

    static func avatar(_ compte: String) -> String { "avatar:\(compte)" }
    /// La première image d'une vidéo, extraite du flux : le titre incrusté s'y lit, contrairement à l'image choisie
    /// par YouTube ou Facebook.
    static func premiere(_ video: String) -> String { "premiere:\(video)" }
    static func icone(_ app: String) -> String { "icone:\(app)" }

    /// Les clés d'une vidéo, la meilleure d'abord : la première image extraite si la plateforme en a une.
    static func cles(_ video: String, _ plateforme: Plateforme) -> [String] {
        switch plateforme {
        case .youtube, .facebook: [premiere(video), video]
        case .tiktok, .instagram: [video]
        }
    }

    /// Les extractions lancées en même temps : chacune attend surtout le réseau (2 à 3 s).
    static let extractionsEnParallele = 4

    /// Télécharge les images absentes du cache (clé → URL) et rend les échecs, une ligne par image.
    static func telecharger(_ urls: [String: String], _ http: HTTP) async -> [String] {
        let manquantes = urls.filter { !existe($0.key) }
        guard !manquantes.isEmpty else { return [] }
        var echecs: [String] = []
        do {
            try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        } catch {
            return ["dossier \(dossier.path) : \(error.localizedDescription)"]
        }
        for (cle, url) in manquantes.sorted(by: { $0.key < $1.key }) {
            do {
                let image = try await http.donnees(HTTP.requete(url, entetes: ["User-Agent": HTTP.navigateur]))
                try image.write(to: fichier(cle), options: .atomic)
            } catch {
                echecs.append("image \(cle) : \(error.localizedDescription)")
            }
        }
        return echecs
    }

    /// Extrait la première image des vidéos qui n'en ont pas encore, dans l'ordre donné, `extractionsEnParallele` à
    /// la fois : yt-dlp donne le flux (960 px de haut au plus), ffmpeg en lit la première image. Rend les échecs.
    static func extrairePremieres(_ videos: [Video]) async -> [String] {
        var vues = Set<String>()
        let aExtraire = videos.compactMap { v in v.url.map { (id: v.id, url: $0) } }
            .filter { vues.insert($0.id).inserted && !existe(premiere($0.id)) }
        guard !aExtraire.isEmpty else { return [] }
        do {
            try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        } catch {
            return ["dossier \(dossier.path) : \(error.localizedDescription)"]
        }
        return await withTaskGroup(of: String?.self) { groupe in
            var echecs: [String] = []
            for (i, v) in aExtraire.enumerated() {
                if i >= extractionsEnParallele, case let e?? = await groupe.next() { echecs.append(e) }
                groupe.addTask { await extraire(v.id, v.url) }
            }
            for await case let e? in groupe { echecs.append(e) }
            return echecs
        }
    }

    /// La première image d'une vidéo ; rend l'échec.
    private static func extraire(_ id: String, _ url: String) async -> String? {
        let f = fichier(premiere(id)).path
        do {
            // écrit à côté puis renomme : une extraction coupée ne laisse pas d'image tronquée
            _ = try await Commande.shell("""
                U=$(yt-dlp -g -f 'bv*[height<=960]/b[height<=960]/b' '\(url)') \\
                && ffmpeg -v error -i "$U" -frames:v 1 -q:v 3 -f mjpeg -y '\(f).part' && mv -f '\(f).part' '\(f)'
                """)
            return nil
        } catch {
            return "première image \(id) : \(error.localizedDescription)"
        }
    }

    private static func existe(_ cle: String) -> Bool { FileManager.default.fileExists(atPath: fichier(cle).path) }
}
