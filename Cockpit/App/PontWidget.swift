import Foundation
import os
import WidgetKit

/// Écrit le résumé du widget dans le conteneur partagé quand il change, et fait relire le widget
/// au plus toutes les 15 min : WidgetKit rationne les rechargements.
@MainActor
final class PontWidget {
    private static let intervalle: TimeInterval = 900
    private var ecrit: Data?
    private var enAttente = false
    private var recharge = Date.distantPast
    private let log = Logger(subsystem: "com.tonysanchez.cockpit", category: "widget")
    private let encodeur: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }()

    func publier(_ resume: ResumeWidget, maintenant: Date) {
        do {
            guard let url = ResumeWidget.url else { throw CocoaError(.fileNoSuchFile) }
            let data = try encodeur.encode(resume)
            if data != ecrit {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                ecrit = data
                enAttente = true
            }
        } catch {
            log.error("résumé du widget : \(error.localizedDescription, privacy: .public)")
            return
        }
        guard enAttente, maintenant.timeIntervalSince(recharge) >= Self.intervalle else { return }
        WidgetCenter.shared.reloadAllTimelines()
        recharge = maintenant
        enAttente = false
    }
}
