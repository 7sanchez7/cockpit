import Foundation
import Testing
@testable import CockpitNoyau

@MainActor
struct AccueilTests {
    let store = try! Store.memoire()
    let maintenant = Date(iso: "2026-11-13T14:00:00Z")!
    var lectures: Lectures { Lectures(db: store.db, businesses: try! store.businesses(), maintenant: maintenant) }

    @Test func planDansLOrdreDeLaNote() throws {
        let lignes = [LignePlan(section: "Cette semaine", texte: "Sortir le build 51", coche: true, fait: true),
                      LignePlan(section: "Cette semaine", texte: "3 vidéos par jour", coche: true),
                      LignePlan(section: "Idées", texte: "Carte de leçon")]
        try store.plan(lignes)
        #expect(lectures.plan() == lignes)
        try store.plan(Array(lignes.prefix(1)))
        #expect(lectures.plan() == Array(lignes.prefix(1)))
    }

    @Test func reseauCompteLesVideosDuJourAParis() throws {
        // minuit à Paris le 13 novembre = 23 h UTC le 12
        for (id, compte, publiee) in [("1", "holaestony", "2026-11-12T22:30:00Z"), ("2", "holaestony", "2026-11-13T09:00:00Z"),
                                      ("3", "holaestony", "2026-11-13T12:00:00Z"), ("4", "tonyolingo", "2026-11-11T10:00:00Z")] {
            try store.video(Video(id: id, business: "roleo", compte: compte, legende: id, publieeLe: Date(iso: publiee), dureeS: nil, url: nil))
        }
        let r = lectures.reseau()
        let hola = try #require(r.first { $0.id == "tiktok:holaestony" })
        #expect(hola.aujourdhui == 2)
        #expect(hola.derniere == Date(iso: "2026-11-13T12:00:00Z"))
        let tony = try #require(r.first { $0.id == "tiktok:tonyolingo" })
        #expect(tony.aujourdhui == 0)
        #expect(tony.derniere == Date(iso: "2026-11-11T10:00:00Z"))
        #expect(r.first { $0.id == "instagram:holaestony" }?.derniere == nil)
    }

    @Test func semaineDuLundiAuDimanche() {
        #expect(Jour.semaine(de: "2026-11-13") == (0..<7).map { Jour.decale("2026-11-09", jours: $0) })
        #expect(Jour.semaine(de: "2026-11-13").last == "2026-11-15")
        #expect(Jour.semaine(de: "2026-11-15").first == "2026-11-09")
        #expect(Jour.semaine(de: "2026-11-16").first == "2026-11-16")
    }

    @Test func scoreSemaineContreSemaine() throws {
        // semaine d'avant : 6 au 12 nov. moins 7 jours ; semaine courante : 6 au 12
        for j in 0..<7 {
            let avant = Jour.decale("2026-10-30", jours: j), courant = Jour.decale("2026-11-06", jours: j)
            try store.serie("roleo", Metrique.installs, jour: avant, 10)
            try store.serie("roleo", Metrique.installs, jour: courant, 20)
            try store.serie("roleo", Metrique.essais, jour: avant, 2)
            try store.serie("roleo", Metrique.essais, jour: courant, 2)
            try store.serie("roleo", Metrique.revenu, jour: avant, 100)
            try store.serie("roleo", Metrique.revenu, jour: courant, 80)
        }
        let s = lectures.score(jusqua: "2026-11-12")
        let notes = Dictionary(uniqueKeysWithValues: s.axes.map { ($0.nom, $0.note) })
        #expect(notes["Installs"] == 100)
        #expect(notes["Conversion"] == 50)
        #expect(notes["Revenu"] == 80)
        #expect(notes["Vidéos"] == .some(nil))
        #expect(notes["Vues"] == .some(nil))
        #expect(s.global == 77)
        #expect(s.faible?.nom == "Conversion")
    }

    @Test func pasDePointFaibleQuandToutVaBien() {
        let s = Score(axes: [AxeScore(nom: "Vues", note: 100), AxeScore(nom: "Revenu", note: nil)])
        #expect(s.global == 100)
        #expect(s.faible == nil)
        #expect(Score.note(5, 0) == nil)
        #expect(Score.note(30, 10) == 100)
    }
}
