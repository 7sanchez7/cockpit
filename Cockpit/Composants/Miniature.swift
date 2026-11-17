import ImageIO
import SwiftUI
import os

extension Plateforme {
    /// Le logo officiel, en couleur (Logos.xcassets, tracés de Simple Icons).
    func logo(_ taille: CGFloat) -> some View {
        Image("logo-\(rawValue)").resizable().scaledToFit().frame(width: taille, height: taille)
    }

    var couleur: Color {
        switch self {
        case .tiktok: Theme.aqua
        case .instagram: Theme.violet
        case .youtube: Theme.orange
        case .facebook: Theme.bleu
        }
    }
}

/// Les images du cache disque (Miniatures.swift) décodées une fois, hors du fil principal, à la taille d'affichage,
/// puis gardées en mémoire pour toute la session : changer d'onglet les rend sans relire le disque.
enum Images {
    /// Le grand côté décodé, en pixels : une case de la grille fait au plus 338 pt de haut, soit 676 px en Retina.
    nonisolated static let cote = 720
    /// Une icône d'app s'affiche au plus en `Taille.avatar` : décodée au double de sa taille Retina, l'écran ne la
    /// réduit plus que de moitié et elle reste nette.
    nonisolated static let coteIcone = Int(Theme.Taille.avatar) * 4
    /// Une vidéo verticale décodée pèse ~1,2 Mo : 300 tiennent dans la mémoire avec les avatars et les icônes.
    static let videosEnMemoire = 300

    private static let memoire: NSCache<NSString, CGImage> = {
        let c = NSCache<NSString, CGImage>()
        c.totalCostLimit = 400 << 20
        return c
    }()
    private static let log = Logger(subsystem: "com.tonysanchez.cockpit", category: "images")

    /// La première des clés déjà en mémoire.
    static func enMemoire(_ cles: [String]) -> CGImage? {
        cles.lazy.compactMap { memoire.object(forKey: $0 as NSString) }.first
    }

    /// La première des clés présente en mémoire ou sur disque, décodée au besoin ; nil si aucune n'est encore téléchargée.
    static func charger(_ cles: [String]) async -> CGImage? {
        for cle in cles {
            if let i = memoire.object(forKey: cle as NSString) { return i }
            do {
                let pixels = cle.hasPrefix(Miniatures.icone("")) ? coteIcone : cote
                guard let i = try await decoder(Miniatures.fichier(cle), cote: pixels) else { continue }
                memoire.setObject(i, forKey: cle as NSString, cost: i.bytesPerRow * i.height)
                return i
            } catch {
                log.error("\(cle, privacy: .public) : \(error.localizedDescription, privacy: .public)")
            }
        }
        return nil
    }

    /// Met en mémoire les images d'un écran avant qu'il s'ouvre, une par une, sans bloquer l'interface.
    static func precharger(_ listes: [[String]]) async {
        for cles in listes where !Task.isCancelled {
            _ = await charger(cles)
        }
    }

    /// Décode un fichier réduit à `cote` px de grand côté ; nil s'il n'existe pas. Un fichier illisible est retiré du cache disque
    /// pour que la source le retélécharge au passage suivant.
    @concurrent nonisolated private static func decoder(_ fichier: URL, cote: Int) async throws -> CGImage? {
        guard FileManager.default.fileExists(atPath: fichier.path) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: cote,
        ]
        guard let source = CGImageSourceCreateWithURL(fichier as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            try FileManager.default.removeItem(at: fichier)
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: fichier.path])
        }
        return image
    }
}

/// Une image du cache, la première trouvée parmi `cles` ; le glyphe de la plateforme (ou un fond neutre) tant
/// qu'aucune n'est téléchargée. Rendue tout de suite si elle est en mémoire, sinon décodée en arrière-plan puis
/// montrée en fondu.
struct Miniature: View {
    @Environment(AppState.self) private var app
    let cles: [String]
    var plateforme: Plateforme?
    @State private var lue: (cles: [String], image: CGImage)?

    init(cles: [String], plateforme: Plateforme? = nil) {
        self.cles = cles
        self.plateforme = plateforme
    }

    init(cle: String, plateforme: Plateforme? = nil) {
        self.init(cles: [cle], plateforme: plateforme)
    }

    private var affichee: CGImage? { Images.enMemoire(cles) ?? (lue?.cles == cles ? lue?.image : nil) }

    var body: some View {
        ZStack {
            if let image = affichee {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .transition(.opacity)
            } else if let plateforme {
                Rectangle().fill(Theme.doux(plateforme.couleur))
                plateforme.logo(Theme.Taille.logoGrand)
            } else {
                Rectangle().fill(.white.opacity(Theme.Blanc.pilule))
            }
        }
        // une source qui vient de télécharger une image fait changer la version
        .task(id: Cle(cles: cles, version: app.store.version)) {
            let avant = affichee
            guard let image = await Images.charger(cles), image !== avant else { return }
            withAnimation(Theme.Anim.survol) { lue = (cles, image) }
        }
    }

    private struct Cle: Equatable {
        let cles: [String]
        let version: Int
    }
}
