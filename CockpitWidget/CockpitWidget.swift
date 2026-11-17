import os
import SwiftUI
import WidgetKit

@main
struct CockpitWidgets: WidgetBundle {
    var body: some Widget { WidgetChiffres() }
}

/// Le widget du bureau : le revenu du jour et les chiffres de l'Accueil, tous business confondus.
struct WidgetChiffres: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "chiffres", provider: Fournisseur()) { entree in
            VueWidget(resume: entree.resume)
                .containerBackground(for: .widget) { FondWidget() }
        }
        .configurationDisplayName("Cockpit")
        .description("Le revenu du jour et les chiffres de l'Accueil.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct VueWidget: View {
    @Environment(\.widgetFamily) private var famille
    let resume: ResumeWidget?

    var body: some View {
        if let r = resume {
            switch famille {
            case .systemSmall: WidgetPetit(r: r)
            case .systemMedium: WidgetMoyen(r: r)
            default: WidgetGrand(r: r)
            }
        } else {
            WidgetVide()
        }
    }
}

nonisolated struct Entree: TimelineEntry {
    let date: Date
    let resume: ResumeWidget?
}

/// Lit le résumé que l'app écrit ; c'est l'app qui fait relire le widget quand il change.
nonisolated struct Fournisseur: TimelineProvider {
    private static let log = Logger(subsystem: "com.tonysanchez.cockpit.widget", category: "widget")

    func placeholder(in context: TimelineProviderContext) -> Entree { Entree(date: .now, resume: .exemple) }

    func getSnapshot(in context: TimelineProviderContext, completion: @escaping (Entree) -> Void) {
        completion(Entree(date: .now, resume: lire() ?? (context.isPreview ? .exemple : nil)))
    }

    func getTimeline(in context: TimelineProviderContext, completion: @escaping (Timeline<Entree>) -> Void) {
        completion(Timeline(entries: [Entree(date: .now, resume: lire())], policy: .never))
    }

    /// nil tant que l'app n'a rien écrit ; un fichier illisible est journalisé.
    private func lire() -> ResumeWidget? {
        guard let url = ResumeWidget.url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder().decode(ResumeWidget.self, from: Data(contentsOf: url))
        } catch {
            Self.log.error("résumé illisible : \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

nonisolated private extension ResumeWidget {
    /// Ce que montre la galerie des widgets avant la première écriture de l'app.
    static let exemple = ResumeWidget(
        maj: "14:32", revenu: "42 €", hier: "hier 31 €", detail: "4 essais, 1 achat",
        cumul: (1...30).map { Double($0 * $0) / 2 }, jours: 30,
        kpis: [
            Kpi(libelle: "Abonnés", valeur: "41", delta: "+2", ecart: 2, note: "MRR 612 €", serie: (1...14).map { Double(30 + $0) }),
            Kpi(libelle: "Essais", valeur: "4", delta: "+1", ecart: 1, note: "6 en cours", serie: (1...14).map { Double($0 % 5) }),
            Kpi(libelle: "Installs", valeur: "58", delta: "+12 %", ecart: 6, note: "7 % en essai", serie: (1...14).map { Double(40 + $0 % 7 * 3) }),
            Kpi(libelle: "Actifs", valeur: "212", delta: "−3 %", ecart: -7, note: "96 ronds", serie: (1...14).map { Double(220 - $0) }),
            Kpi(libelle: "Vues TikTok", valeur: "18 400", delta: "+40 %", ecart: 5200, note: "1 vidéo publiée", serie: (1...14).map { Double($0 * $0 * 90) }),
        ],
        aTraiter: 3)
}
