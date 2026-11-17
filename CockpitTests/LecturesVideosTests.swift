import Foundation
import Testing
@testable import CockpitNoyau

@MainActor
struct LecturesVideosTests {
    let store = try! Store.memoire()
    let maintenant = Date(iso: "2026-11-13T14:00:00Z")!
    var lectures: Lectures { Lectures(db: store.db, businesses: try! store.businesses(), maintenant: maintenant) }

    private func video(_ id: String, _ compte: String, _ publiee: String) throws {
        try store.video(Video(id: id, business: "roleo", compte: compte, legende: id,
                              publieeLe: Date(iso: publiee), dureeS: nil, url: nil))
    }

    @Test func comptesAvecAbonnesEtGain() throws {
        try video("1", "holaestony", "2026-11-10T10:00:00Z")
        try video("2", "holaestony", "2026-11-11T10:00:00Z")
        try video("3", "tonyolingo", "2026-11-12T10:00:00Z")
        try store.releve(ReleveCompte(compte: "tiktok:holaestony", at: Date(iso: "2026-11-05T10:00:00Z")!, abonnes: 1000))
        try store.releve(ReleveCompte(compte: "tiktok:holaestony", at: Date(iso: "2026-11-13T10:00:00Z")!, abonnes: 1250))
        let c = lectures.comptes()
        #expect(c.map(\.id) == ["facebook:holaestony", "instagram:holaestony", "tiktok:holaestony", "tiktok:tonyolingo", "youtube:holaestony"])
        let tiktok = try #require(c.first { $0.id == "tiktok:holaestony" })
        #expect(tiktok.videos == 2)
        #expect(tiktok.abonnes == 1250)
        #expect(tiktok.gain7j == 250)
        #expect(tiktok.serie.last == 1250)
        #expect(c.first { $0.id == "tiktok:tonyolingo" }?.abonnes == nil)
    }

    @Test func compteRetireCacheSesVideos() throws {
        try video("1", "holaestony", "2026-11-10T10:00:00Z")
        try video("2", "tonyolingo", "2026-11-11T10:00:00Z")
        try store.releve(Releve(video: "1", at: maintenant, vues: 100))
        try store.releve(Releve(video: "2", at: maintenant, vues: 50))
        #expect(Set(lectures.videos().map(\.id)) == ["1", "2"])
        try store.retirer(compte: "tiktok:tonyolingo")
        #expect(lectures.videos().map(\.id) == ["1"])
        #expect(!lectures.comptes().contains { $0.handle == "tonyolingo" })
    }

    @Test func engagementEtConversion() throws {
        try video("1", "holaestony", "2026-11-10T10:00:00Z")
        try store.releve(Releve(video: "1", at: maintenant, vues: 2000, likes: 100, commentaires: 10, partages: 30,
                                enregistrements: 20, abonnes: 8))
        let v = try #require(lectures.videos().first)
        #expect(v.engagement == 0.08)
        #expect(v.conversion == 4)
    }

    @Test func publicationsParJourDeParis() throws {
        // 23 h 30 UTC le 11 = 0 h 30 le 12 à Paris
        try video("1", "holaestony", "2026-11-11T23:30:00Z")
        try video("2", "holaestony", "2026-11-12T09:00:00Z")
        try video("3", "tonyolingo", "2026-11-13T09:00:00Z")
        try video("4", "holaestony", "2026-11-01T09:00:00Z")
        #expect(lectures.publications(3, jusqua: "2026-11-13") == [0, 2, 1])
    }

    @Test func publicationsFiltreesSurLeBusiness() throws {
        try store.enregistrer(Business(id: "app2", nom: "App 2", lettre: "A", teinte: "ciel", config: .init()))
        try video("1", "holaestony", "2026-11-13T09:00:00Z")
        let app2 = try store.businesses().filter { $0.id == "app2" }
        let l = Lectures(db: store.db, businesses: app2, maintenant: maintenant)
        #expect(l.publications(1, jusqua: "2026-11-13") == [0])
        #expect(l.comptes().isEmpty)
    }

    @Test func imagesAPrecharger() throws {
        try video("1", "holaestony", "2026-11-10T10:00:00Z")
        try video("2", "holaestony", "2026-11-12T10:00:00Z")
        try store.video(Video(id: "youtube:abc", business: "roleo", compte: "holaestony", legende: "yt",
                              publieeLe: Date(iso: "2026-11-11T10:00:00Z"), dureeS: nil, url: nil, plateforme: .youtube))
        let images = lectures.images(limite: 2)
        #expect(images.first == [Miniatures.icone("6770304361")])
        #expect(images.contains([Miniatures.avatar("tiktok:holaestony")]))
        // les plus récentes d'abord, la première image avant la miniature
        #expect(images.suffix(2) == [["2"], [Miniatures.premiere("youtube:abc"), "youtube:abc"]])
    }
}
