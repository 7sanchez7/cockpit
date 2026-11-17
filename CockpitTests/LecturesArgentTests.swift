import Foundation
import Testing
@testable import CockpitNoyau

@MainActor
struct LecturesArgentTests {
    let store = try! Store.memoire()
    let maintenant = Date(iso: "2026-11-13T14:00:00Z")!
    var lectures: Lectures { Lectures(db: store.db, businesses: try! store.businesses(), maintenant: maintenant) }

    private func cohorte(_ jour: String, _ installs: Int, j1: Int?) -> Cohorte {
        Cohorte(jour: jour, installs: installs, j1: j1, j7: nil, j14: nil, j30: nil)
    }

    @Test func objectifEnEurosEtArrivee() throws {
        try store.serie("roleo", Metrique.mrrBrut, jour: "2026-10-14", 250)
        try store.serie("roleo", Metrique.mrrBrut, jour: "2026-11-13", 700)
        let o = try #require(lectures.objectif(jour: "2026-11-13"))
        #expect(o.cibleEUR == 10_000)
        #expect(abs(o.mrrEUR - 644) < 1e-9)
        #expect(abs(o.resteEUR - 9_356) < 1e-9)
        #expect(abs(o.part - 0.0644) < 1e-9)
        #expect(abs((o.rythmeParJourEUR ?? 0) - 13.8) < 1e-9)
        let arrivee = try #require(o.arrivee(depuis: maintenant))
        #expect(abs(arrivee.timeIntervalSince(maintenant) / 86_400 - 9_356 / 13.8) < 1e-6)
    }

    @Test func pasDArriveeSansHausseNiTropLoin() throws {
        try store.serie("roleo", Metrique.mrrBrut, jour: "2026-11-13", 700)
        #expect(try #require(lectures.objectif(jour: "2026-11-13")).arrivee(depuis: maintenant) == nil)
        let lente = Objectif(cibleEUR: 10_000, mrrEUR: 600, rythmeParJourEUR: 1)
        #expect(lente.arrivee(depuis: maintenant) == nil)
        let baisse = Objectif(cibleEUR: 10_000, mrrEUR: 600, rythmeParJourEUR: -2)
        #expect(baisse.arrivee(depuis: maintenant) == nil)
        #expect(lectures.objectif(jour: "2026-11-12") == nil)
    }

    @Test func sommeSurNJours() throws {
        try store.serie("roleo", Metrique.achats, jour: "2026-11-13", 3)
        try store.serie("roleo", Metrique.achats, jour: "2026-11-10", 2)
        try store.serie("roleo", Metrique.achats, jour: "2026-11-05", 9)
        #expect(lectures.somme(Metrique.achats, 7, jusqua: "2026-11-13") == 5)
        #expect(lectures.somme(Metrique.achats, 3, jusqua: "2026-11-04") == nil)
    }

    @Test func retourPondereEtComparaison() {
        // 14 cohortes complètes, les 7 récentes à 10 sur 100, les 7 d'avant à 5 sur 50, puis 2 ouvertes
        let ouvertes = [cohorte("2026-11-13", 40, j1: nil), cohorte("2026-11-12", 80, j1: nil)]
        let recentes = (0..<7).map { cohorte(Jour.decale("2026-11-11", jours: -$0), 100, j1: 10) }
        let avant = (0..<7).map { cohorte(Jour.decale("2026-11-04", jours: -$0), 50, j1: 5 + ($0 == 0 ? 7 : 0)) }
        let r = (ouvertes + recentes + avant).retour(\.j1)
        #expect(r?.taux == 0.1)
        #expect(r?.cohortes == 7)
        #expect(r?.avant == 42.0 / 350)
    }

    @Test func retourSansAssezDeCohortes() {
        let c = [cohorte("2026-10-12", 73, j1: 1), cohorte("2026-10-11", 108, j1: 1), cohorte("2026-10-10", 0, j1: 0)]
        #expect(c.retour(\.j1) == TauxRetour(taux: 2.0 / 181, cohortes: 2, avant: nil))
        #expect([cohorte("2026-11-13", 40, j1: nil)].retour(\.j1) == nil)
        let attendue: [Double] = [1.0 / 108, 1.0 / 73]
        #expect(c.serie(\.j1) == attendue)
    }

    @Test func plusGrossePerteDuTunnel() {
        #expect(Lectures.plusGrossePerte([("Installs", 950), ("Accueil", 915), ("Paywall vu", 863), ("Essai touché", 362)]) == 3)
        #expect(Lectures.plusGrossePerte([("Installs", 10), ("Accueil", 10)]) == nil)
        #expect(Lectures.plusGrossePerte([]) == nil)
    }
}
