import Foundation
import Testing
@testable import CockpitNoyau

/// Les décodeurs d'Instagram, de YouTube, de Facebook et de l'Analytics TikTok, sur des réponses réduites et factices.
@MainActor
struct ReseauxTests {
    let at = Date(timeIntervalSince1970: 1794527444)

    /// Vrai si l'appel lève « reconnecte-toi » plutôt qu'une autre erreur.
    func demandeConnexion(_ f: () throws -> Void) -> Bool {
        do { try f(); return false } catch SourceErreur.nonConfigure(_) { return true } catch { return false }
    }

    // MARK: TikTok

    @Test func analyseTikTok() throws {
        let reponse = Data("""
            {"status_code": 0,
             "video_total_duration_realtime": {"is_after_7d": false, "value": {"status": 0, "value": 198026}},
             "video_uv": {"status": 0, "value": 24000},
             "video_viewer_new_viewer_percent": {"status": 2},
             "video_traffic_source_percent_realtime": {"is_after_7d": false, "value": {"status": 0, "value": [
               {"key": "For You", "value": 0.95}, {"key": "Search", "value": 0.01}]}},
             "video_retention_rate_realtime": {"value": {"list": [
               {"timestamp": "2000", "value": 0.33}, {"timestamp": "0", "value": 1}, {"timestamp": "1000", "value": 0.57}]}},
             "video_viewer_location_percent_realtime": {"value": {"country_percent_list": [
               {"country_name": "FR", "country_vv_percent": 0.8}]}},
             "item_search_terms": null,
             "video_vv_history_7d": [{"status": 0, "value": 579}, {"status": 0, "value": 120}, {"status": 2}]}
            """.utf8)
        #expect(try TikTok.analyse(reponse) == Analyse(
            watchTotalS: 198026, spectateurs: 24000, retention: [1, 0.57, 0.33],
            sources: [.init(nom: "For You", part: 0.95), .init(nom: "Search", part: 0.01)],
            pays: [.init(nom: "FR", part: 0.8)], vuesParJour: [579, 120]))
        // vidéo d'un autre compte : rien de privé
        #expect(try TikTok.analyse(Data(#"{"status_code": 0}"#.utf8)).estVide)
    }

    // MARK: Facebook

    @Test func tableFacebook() throws {
        let reponse = Data(#"""
            for (;;);{"data": {"tofu_unified_table": {"content": {"edges": [
              {"node": {"row_id": "123",
                "header": {"content_type": "VIDEO", "entity": {"entity_info": {"title": "Reel {test}", "created_at": 1794500000,
                  "image_source": {"uri": "https://x/i.jpg"}, "owner": {"entity_info": {"image_source": {"uri": "https://x/a.jpg"}}}}}},
                "fields": {
                  "views": {"renderer": {"value_for_sort": 1000}}, "net_reactions": {"renderer": {"value_for_sort": 50}},
                  "net_comments": {"renderer": {"value_for_sort": 2}}, "shares": {"renderer": {"value_for_sort": 3}},
                  "net_saves": {"renderer": {"value_for_sort": 4}}, "new_follows": {"renderer": {"value_for_sort": 7}},
                  "video_average_play_time": {"renderer": {"value_for_sort": 5970}},
                  "video_play_time": {"renderer": {"value_for_sort": 5970000}}, "viewers": {"renderer": {"value_for_sort": 800}},
                  "video_three_second_views": {"renderer": {"value_for_sort": 400}},
                  "video_one_minute_views": {"renderer": {"value_for_sort": 10}},
                  "video_thruplays": {"renderer": {"__typename": "BizWebInsightsErrorRenderer", "value_for_sort": 9}}}}},
              {"node": {"row_id": "456", "header": {"content_type": "PHOTO"}, "fields": {"views": {"renderer": {"value_for_sort": 80}}}}}
            ]}}}}{"label": "suite", "data": {"texte": "a } b \" {"}}
            """#.utf8)
        let objets = try Facebook.objets(reponse)
        #expect(objets.count == 2)
        let t = try Facebook.table(objets, business: "roleo", compte: "holaestony", at: at)
        #expect(t.videos == [Video(id: "facebook:123", business: "roleo", compte: "holaestony", legende: "Reel {test}",
                                   publieeLe: Date(timeIntervalSince1970: 1794500000), url: "https://www.facebook.com/123",
                                   plateforme: .facebook)])
        #expect(t.releves == [Releve(video: "facebook:123", at: at, vues: 1000, likes: 50, commentaires: 2, partages: 3,
                                     enregistrements: 4, watchMoyenS: 5.97, abonnes: 7)])
        // la case en erreur (ThruPlay) est absente, pas à zéro
        #expect(t.analyses == ["facebook:123": Analyse(watchTotalS: 5970, spectateurs: 800,
                                                       jalons: [.init(nom: "3 s", part: 0.4), .init(nom: "1 min", part: 0.01)])])
        #expect(t.images == ["facebook:123": "https://x/i.jpg", "avatar:facebook:holaestony": "https://x/a.jpg"])

        #expect(throws: SourceErreur.self) { try Facebook.objets(Data(#"for (;;);{"a": }"#.utf8)) }
        #expect(throws: SourceErreur.self) {
            try Facebook.table(Facebook.objets(Data(#"{"errors": [{"message": "boom"}]}"#.utf8)), business: "roleo", compte: "x", at: at)
        }
    }

    @Test func jetonsFacebook() throws {
        let html = #"""
            <script>["DTSGInitialData",[],{"token":"dtsg-factice"},1]["LSD",[],{"token":"lsd-factice"},2]
            {"server_revision":1029384,"x":1}{"page_total_likes_or_followers":{"count":10465}}</script>
            """#
        let j = try Facebook.jetons(html)
        #expect(j.dtsg == "dtsg-factice" && j.lsd == "lsd-factice" && j.rev == "1029384")
        #expect(Facebook.nombre(apres: #""page_total_likes_or_followers":{"count":"#, dans: html) == 10465)
        #expect(Facebook.texte(apres: #"["LSD",[],{"token":""#, dans: html) == "lsd-factice")
        #expect(demandeConnexion { _ = try Facebook.jetons("<html>connexion</html>") })

        let r = try Facebook.requete(page: "99", utilisateur: "1", jetons: j, cookie: "c_user=1")
        let corps = String(decoding: r.httpBody ?? Data(), as: UTF8.self)
        #expect(r.httpMethod == "POST")
        #expect(corps.contains("fb_dtsg=dtsg-factice") && corps.contains("doc_id=\(Facebook.docTable)"))
        #expect(!corps.contains("{"))
    }

    // MARK: Instagram

    @Test func profilEtFilInstagram() throws {
        let compte = Compte(business: "roleo", plateforme: .instagram, handle: "holaestony")
        let profil = try Instagram.profil(Data("""
            {"data": {"user": {"id": "42", "edge_followed_by": {"count": 1200}, "edge_owner_to_timeline_media": {"count": 87},
              "profile_pic_url": "https://x/p.jpg", "profile_pic_url_hd": "https://x/hd.jpg"}}, "status": "ok"}
            """.utf8), compte: compte, at: at)
        #expect(profil.uid == "42")
        #expect(profil.releve == ReleveCompte(compte: "instagram:holaestony", at: at, abonnes: 1200, videos: 87))
        #expect(profil.avatar == "https://x/hd.jpg")

        let fil = try Instagram.fil(Data("""
            {"items": [
              {"media_type": 2, "code": "ABC", "caption": {"text": "Hola"}, "taken_at": 1794500000, "video_duration": 21.5,
               "ig_play_count": 5000, "play_count": 9000, "like_count": 100, "comment_count": 5,
               "image_versions2": {"candidates": [{"url": "https://x/c.jpg"}]}},
              {"media_type": 1, "code": "PHOTO"},
              {"media_type": 2, "code": "DEF", "play_count": 300}]}
            """.utf8), business: "roleo", compte: "holaestony", at: at)
        #expect(fil.videos.map(\.id) == ["instagram:ABC", "instagram:DEF"])
        #expect(fil.videos[0] == Video(id: "instagram:ABC", business: "roleo", compte: "holaestony", legende: "Hola",
                                       publieeLe: Date(timeIntervalSince1970: 1794500000), dureeS: 21.5,
                                       url: "https://www.instagram.com/reel/ABC/", plateforme: .instagram))
        // ig_play_count passe avant play_count, qui compte aussi le partage Facebook
        #expect(fil.releves == [Releve(video: "instagram:ABC", at: at, vues: 5000, likes: 100, commentaires: 5),
                                Releve(video: "instagram:DEF", at: at, vues: 300)])
        #expect(fil.images == ["instagram:ABC": "https://x/c.jpg"])

        // page de connexion à la place du JSON : session à refaire
        #expect(demandeConnexion { _ = try Instagram.profil(Data("<html>".utf8), compte: compte, at: at) })
        #expect(demandeConnexion { _ = try Instagram.fil(Data(#"{"require_login": true}"#.utf8), business: "roleo", compte: "x", at: at) })
        #expect(throws: SourceErreur.self) { try Instagram.fil(Data(#"{"status": "ok"}"#.utf8), business: "roleo", compte: "x", at: at) }
    }

    // MARK: YouTube

    @Test func listeYouTube() throws {
        let l = try YtDlp.liste(Data("""
            {"id": "UC1", "channel_follower_count": 403,
             "thumbnails": [{"id": "banner_uncropped", "url": "https://x/b.jpg"}, {"id": "avatar_uncropped", "url": "https://x/av.jpg"}],
             "entries": [{"id": "abc", "title": "Le short", "view_count": 1200, "url": "https://www.youtube.com/shorts/abc"}]}
            """.utf8), plateforme: .youtube, business: "roleo", compte: "holaestony", at: at)
        #expect(l.abonnes == 403 && l.avatar == "https://x/av.jpg")
        #expect(l.videos == [Video(id: "youtube:abc", business: "roleo", compte: "holaestony", legende: "Le short",
                                   url: "https://www.youtube.com/shorts/abc", plateforme: .youtube)])
        #expect(l.releves == [Releve(video: "youtube:abc", at: at, vues: 1200)])
    }
}
