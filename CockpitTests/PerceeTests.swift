import Foundation
import Testing
@testable import CockpitNoyau

@MainActor
struct PerceeTests {
    let maintenant = Date(iso: "2026-11-13T14:00:00Z")!

    /// Dix vidéos de 100 à 1 000 vues : le taux de likes monte avec les vues, celui des commentaires descend.
    private func compte(likes: (Int) -> Int = { $0 * $0 }) -> [LigneVideo] {
        (1...10).map { i in
            LigneVideo(id: "\(i)", business: "roleo", compte: "holaestony", titre: "\(i)", verdict: false, vues: 100 * i,
                       likes: likes(i), commentaires: (11 - i) * i, releveLe: maintenant)
        }
    }

    @Test func spearman() {
        #expect(Percee.spearman([(1, 1), (2, 2), (3, 3)]) == 1)
        #expect(Percee.spearman([(1, 3), (2, 2), (3, 1)]) == -1)
        #expect(Percee.spearman([(1, 2), (2, 2), (3, 2)]) == 0)
        // ex aequo au rang moyen
        #expect(abs(Percee.spearman([(1, 1), (2, 1), (3, 2)]) - 0.866) < 0.001)
    }

    @Test func leLevierEstLaMesureQuiPorteLesVues() throws {
        let videos = compte()
        let l = try #require(Percee.levier(videos[9], parmi: videos, accroches: [:]))
        #expect(l.mesure == .likes)
        #expect(l.valeur == 0.1)
        #expect(l.rang == 1)
        #expect(l.poids == 1)
        #expect(l.percee)
    }

    @Test func uneMesureQuiSuitMalLesVuesNestJamaisLeLevier() {
        // la vidéo la moins vue commente le plus, mais les commentaires descendent quand les vues montent
        let videos = compte()
        #expect(Percee.levier(videos[0], parmi: videos, accroches: [:]) == nil)
    }

    @Test func sousLaMedianeLeMeilleurAtout() throws {
        let videos = compte { $0 == 3 ? 60 : $0 * $0 }
        let l = try #require(Percee.levier(videos[2], parmi: videos, accroches: [:]))
        #expect(l.mesure == .likes)
        #expect(l.rang == 1)
        #expect(!l.percee)
    }

    @Test func lesComptesNeSeMelangentPas() {
        var videos = Array(compte().prefix(7))
        videos += compte().map { var v = $0; v.id += "-autre"; v.compte = "tonyolingo"; return v }
        #expect(Percee.compte(videos[6], parmi: videos).count == 7)
        #expect(Percee.levier(videos[6], parmi: videos, accroches: [:]) == nil)
    }

    @Test func accrocheLueDansLaCourbe() throws {
        let store = try Store.memoire()
        for id in ["1", "2"] {
            try store.video(Video(id: id, business: "roleo", compte: "holaestony", legende: id, publieeLe: maintenant,
                                  dureeS: 10, url: nil))
        }
        try store.analyse("1", at: maintenant, Analyse(retention: [1, 0.8, 0.7, 0.58, 0.5]))
        try store.analyse("2", at: maintenant, Analyse(retention: [1, 0.6]))
        let l = Lectures(db: store.db, businesses: try store.businesses(), maintenant: maintenant)
        #expect(l.accroches() == ["1": 0.58])
    }
}
