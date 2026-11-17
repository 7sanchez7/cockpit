import Foundation
import Testing
@testable import CockpitNoyau

@MainActor
struct LecturesSanteTests {
    let store = try! Store.memoire()
    var lectures: Lectures { Lectures(db: store.db, businesses: try! store.businesses()) }

    @Test func dernierSuccesIgnoreLesEchecs() throws {
        let ok = Date(iso: "2026-11-13T10:00:00Z")!
        let panne = Date(iso: "2026-11-13T11:00:00Z")!
        try store.journal(Passage(source: "tiktok", debut: ok, fin: ok, etat: .ok, erreur: nil, lignes: 3))
        try store.journal(Passage(source: "tiktok", debut: panne, fin: panne, etat: .erreur, erreur: "HTTP 500", lignes: 0))
        try store.journal(Passage(source: "asc", debut: panne, fin: panne, etat: .nonConfigure, erreur: "pas de clé", lignes: 0))
        let succes = lectures.derniersSucces()
        #expect(succes["tiktok"] == ok)
        #expect(succes["asc"] == nil)
    }
}
