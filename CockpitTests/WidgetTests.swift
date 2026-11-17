import Foundation
import Testing
@testable import CockpitNoyau

@MainActor
struct WidgetTests {
    let store = try! Store.memoire()
    let maintenant = Date(iso: "2026-11-13T14:00:00Z")!
    var lectures: Lectures { Lectures(db: store.db, businesses: try! store.businesses(), maintenant: maintenant) }

    @Test func revenuCumuleSauteLesJoursSansReleve() throws {
        try store.serie("roleo", Metrique.revenu, jour: "2026-11-11", 50)
        try store.serie("roleo", Metrique.revenu, jour: "2026-11-13", 100)
        let cumul = lectures.revenuCumule(3, jusqua: "2026-11-13")
        #expect(cumul.map(\.jour) == ["2026-11-11", "2026-11-13"])
        #expect(cumul.map(\.euros) == [Metrique.enEuros(50), Metrique.enEuros(150)])
    }

    @Test func resumeDuJour() throws {
        try store.serie("roleo", Metrique.revenu, jour: "2026-11-13", 100)
        try store.serie("roleo", Metrique.abonnes, jour: "2026-11-13", 41)
        try store.serie("roleo", Metrique.abonnes, jour: "2026-11-06", 39)
        try store.serie("roleo", Metrique.mrrBrut, jour: "2026-11-13", 600)
        try store.ajouterTache(texte: "Répondre à l'avis", business: nil, echeance: nil)
        let r = lectures.resumeWidget()
        #expect(r.revenu == Format.euros(Metrique.enEuros(100)))
        #expect(r.hier == "hier " + Format.vide)
        #expect(r.detail == Format.vide)
        #expect(r.maj == nil)
        #expect(r.kpis.map(\.libelle) == ["Abonnés", "Essais", "Installs", "Actifs", "Vues TikTok"])
        let abonnes = try #require(r.kpis.first)
        #expect(abonnes.valeur == "41" && abonnes.delta == "+2" && abonnes.ecart == 2)
        #expect(abonnes.note == "MRR " + Format.euros(Metrique.enEuros(600)))
        #expect(abonnes.serie.count == 14)
        #expect(r.aTraiter == 1)
    }

    @Test func memeResumeMemeJSON() throws {
        try store.serie("roleo", Metrique.revenu, jour: "2026-11-13", 100)
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        let a = try e.encode(lectures.resumeWidget()), b = try e.encode(lectures.resumeWidget())
        #expect(a == b)
        #expect(try JSONDecoder().decode(ResumeWidget.self, from: a) == lectures.resumeWidget())
    }
}
