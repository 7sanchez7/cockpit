import Foundation
import Testing
@testable import CockpitNoyau

@MainActor
struct TikTokTests {
    let store = try! Store.memoire()

    @Test func listeYtDlp() throws {
        let at = Date(timeIntervalSince1970: 1794527444)
        let sortie = Data("""
            {"id": "holaestony", "_type": "playlist", "entries": [
              {"id": "7707322854827707680", "url": "https://www.tiktok.com/@holaestony/video/7707322854827707680",
               "timestamp": 1794500946, "duration": 44, "title": "#espagnol ", "description": "#espagnol #apprendrelespagnol ",
               "view_count": 1674, "like_count": 7, "comment_count": 1, "repost_count": 0, "save_count": 2,
               "thumbnails": [{"id": "dynamicCover", "url": "https://x/anim"}, {"id": "cover", "url": "https://x/cover"}]},
              {"id": "7705857921501957409", "timestamp": 1794159866, "duration": 63.5, "title": "Quand tu dis bonjour #espagnol"}
            ]}
            """.utf8)
        let l = try YtDlp.liste(sortie, plateforme: .tiktok, business: "roleo", compte: "holaestony", at: at)
        #expect(l.videos.count == 2)
        #expect(l.videos[0] == Video(id: "7707322854827707680", business: "roleo", compte: "holaestony",
                                     legende: "#espagnol #apprendrelespagnol ", publieeLe: Date(timeIntervalSince1970: 1794500946),
                                     dureeS: 44, url: "https://www.tiktok.com/@holaestony/video/7707322854827707680"))
        #expect(l.videos[1].legende == "Quand tu dis bonjour #espagnol")
        #expect(l.videos[1].url == "https://www.tiktok.com/@holaestony/video/7705857921501957409")
        // compteurs publics : pas de watch time ; la seconde n'a pas de vues, pas de relevé
        #expect(l.releves == [Releve(video: "7707322854827707680", at: at, vues: 1674, likes: 7, commentaires: 1,
                                     partages: 0, enregistrements: 2)])
        #expect(l.images == ["7707322854827707680": "https://x/cover"])
        #expect(throws: SourceErreur.self) { try YtDlp.liste(Data("ERROR".utf8), plateforme: .tiktok, business: "roleo", compte: "x", at: at) }
    }

    @Test func pageDeProfil() throws {
        let page = Data(#"""
            <html><script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">{"__DEFAULT_SCOPE__":
            {"webapp.user-detail": {"userInfo": {"user": {"avatarThumb": "https://x/a.jpg"},
             "stats": {"followerCount": 35, "followingCount": 2, "heart": 206, "heartCount": 206, "videoCount": 11},
             "statsV2": {"followerCount": "35"}}}}}</script></html>
            """#.utf8)
        let at = Date(timeIntervalSince1970: 1794527444)
        let (r, avatar) = try TikTok.profil(page, compte: "tiktok:tonyolingo", at: at)
        #expect(r == ReleveCompte(compte: "tiktok:tonyolingo", at: at, abonnes: 35, videos: 11, likes: 206))
        #expect(avatar == "https://x/a.jpg")
        #expect(throws: SourceErreur.self) { try TikTok.profil(Data("<html></html>".utf8), compte: "x", at: at) }
    }

    @Test func insight() throws {
        let reponse = Data("""
            {"status_code": 0, "status_msg": "", "extra": {"now": 1794527444000},
             "video_info": {"aweme_id": "7667975806622141728", "create_time": 1785339746, "desc": "Les 4 mots #espagnol",
               "statistics": {"collect_count": 83, "comment_count": 3, "digg_count": 228, "play_count": 31057, "share_count": 18},
               "video": {"duration": 43235}},
             "video_per_duration_realtime": {"is_after_7d": false, "value": {"status": 0, "value": 5.97}},
             "video_finish_rate_realtime": {"is_after_7d": false, "value": {"status": 0, "value": 0.0275}},
             "video_traffic_source_percent_realtime": null,
             "realtime_new_followers": {"is_after_7d": false, "value": {"status": 0, "value": 20}}}
            """.utf8)
        let at = Date(timeIntervalSince1970: 1794527444)
        #expect(try TikTok.releve(reponse, video: "7667975806622141728", at: at) == Releve(
            video: "7667975806622141728", at: at, vues: 31057, likes: 228, commentaires: 3, partages: 18,
            enregistrements: 83, watchMoyenS: 5.97, completion: 0.0275, abonnes: 20))

        // vidéo du jour : abonnés pas encore calculés, pas de temps réel
        let fraiche = Data("""
            {"status_code": 0, "video_info": {"statistics": {"play_count": 1674, "digg_count": 172}},
             "realtime_new_followers": {"value": {"status": 2}}}
            """.utf8)
        let r = try TikTok.releve(fraiche, video: "1", at: at)
        #expect(r.vues == 1674 && r.likes == 172 && r.abonnes == nil && r.watchMoyenS == nil && r.completion == nil)

        // vidéo d'un compte qui n'est pas celui de la session
        #expect(throws: SourceErreur.self) {
            try TikTok.releve(Data(#"{"status_code": 5, "status_msg": "Invalid parameters"}"#.utf8), video: "1", at: at)
        }
    }

    @Test func historiqueDuCompte() throws {
        let reponse = Data("""
            {"status_code": 0, "vv_history": [{"status": 0, "value": 24329}, {"status": 0, "value": 44092}, {"status": 2}]}
            """.utf8)
        #expect(try TikTok.historique(reponse) == [24329, 44092, nil])
        #expect(throws: SourceErreur.self) { try TikTok.historique(Data(#"{"status_code": 8}"#.utf8)) }
    }

    @Test func vuesGagnees() throws {
        func iso(_ s: String) -> Date { Date(iso: s)! }
        // minuit à Paris le 13 nov. = 2026-11-12T23:00Z
        try store.video(Video(id: "a", business: "roleo", compte: "holaestony", publieeLe: iso("2026-11-01T10:00:00Z")))
        try store.video(Video(id: "b", business: "roleo", compte: "holaestony", publieeLe: iso("2026-11-13T07:00:00Z")))
        try store.video(Video(id: "c", business: "roleo", compte: "holaestony", publieeLe: iso("2026-10-01T10:00:00Z")))
        for (video, at, vues) in [("a", "2026-11-12T20:00:00Z", 1000), ("a", "2026-11-13T08:00:00Z", 1100),
                                  ("a", "2026-11-13T10:00:00Z", 1300), ("b", "2026-11-13T09:00:00Z", 500),
                                  ("c", "2026-11-13T08:00:00Z", 2000), ("c", "2026-11-13T10:00:00Z", 2050)] {
            try store.releve(Releve(video: video, at: iso(at), vues: vues))
        }
        // a : 1100 − 1000 de la veille ; b : sortie ce jour-là, depuis 0 ; c : depuis son premier relevé du jour
        #expect(try TikTok.vuesGagnees(store, business: "roleo", jour: "2026-11-13", jusqua: iso("2026-11-13T09:30:00Z")) == 600)
        #expect(try TikTok.vuesGagnees(store, business: "roleo", jour: "2026-11-13", jusqua: iso("2026-11-13T11:00:00Z")) == 850)
        #expect(try TikTok.vuesGagnees(store, business: "roleo", jour: "2026-11-06", jusqua: iso("2026-11-06T11:00:00Z")) == nil)
    }

    @Test func paliersEtTitres() {
        #expect(TikTok.palier(avant: 900, apres: 1200) == 1_000)
        #expect(TikTok.palier(avant: 900, apres: 12_000) == 10_000)
        #expect(TikTok.palier(avant: 1200, apres: 1500) == nil)
        #expect(TikTok.palier(avant: 999_999, apres: 1_000_000) == 1_000_000)
        #expect(TikTok.libelle(1_000_000) == "1 million de")
        #expect(TikTok.titre(legende: "#espagnol #apprendrelespagnol ", fiche: nil) == nil)
        #expect(TikTok.titre(legende: "Quand tu dis bonjour\n#espagnol", fiche: nil) == "Quand tu dis bonjour")
        #expect(TikTok.titre(legende: "Quand tu dis bonjour", fiche: "Bonjour natif") == "Bonjour natif")
    }
}
