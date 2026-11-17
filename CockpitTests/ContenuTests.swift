import Foundation
import Testing
@testable import CockpitNoyau

@MainActor
struct ContenuTests {
    let store = try! Store.memoire()

    @Test func fiche() {
        let f = Contenu.fiche("""
            ---
            format: 3-apps
            statut: publiée          # écrite → tournée → montée → publiée → analysée
            groupe: 30
            export:                  # ~/Movies/tiktok/<slug>.mp4
            tiktok: https://www.tiktok.com/@holaestony/video/7696188146974739745
            variable: première vidéo du format
            ---

            # 2026-10-13 — 3 apps pour apprendre l'espagnol

            ## Script

            ```
            # pas un titre
            ```

            ## Verdict

            Le format tient.
            """)
        #expect(f.champs == ["format": "3-apps", "statut": "publiée", "groupe": "30",
                             "tiktok": "https://www.tiktok.com/@holaestony/video/7696188146974739745",
                             "variable": "première vidéo du format"])
        #expect(f.titre == "3 apps pour apprendre l'espagnol")
        #expect(f.verdict)
        #expect(!Contenu.fiche("---\nformat: x\n---\n\n# Titre\n\n## Stats\n").verdict)
    }

    @Test func titreDUnSlug() {
        #expect(Contenu.fiche("# 2026-09-11 — espagnol-learn\n\n```\nTitre : 4 astuces pour apprendre\n```").titre
                == "4 astuces pour apprendre")
        #expect(Contenu.fiche("# 2026-09-17 — 4-astuces-draguer\n").titre == "4 astuces draguer")
        #expect(Contenu.fiche("# Tu me manques trop\n\nTitre : autre chose").titre == "Tu me manques trop")
    }

    @Test func idDuLien() {
        let v = Contenu.video(url: "https://www.tiktok.com/@holaestony/video/7696188146974739745?lang=fr")
        #expect(v?.id == "7696188146974739745" && v?.compte == "holaestony")
        #expect(Contenu.video(url: "https://www.tiktok.com/@holaestony") == nil)
    }

    @Test func tachesDeVerdict() throws {
        func fiche(_ id: String?, verdict: Bool = false, date: String) -> Contenu.Fiche {
            var f = Contenu.Fiche(chemin: "/bank/format-scripte/4-astuces/fait/\(id ?? "x").md", dossier: "4-astuces",
                                  titre: "Vidéo \(id ?? "x")", verdict: verdict, date: Jour.date(date))
            if let id { f.champs["tiktok"] = "https://www.tiktok.com/@holaestony/video/\(id)" }
            return f
        }
        // la date de TikTok passe avant celle de la fiche
        try store.video(Video(id: "444", business: "roleo", compte: "holaestony", publieeLe: Date(iso: "2026-11-05T10:00:00Z")))
        let fiches = [fiche("111", date: "2026-11-01"), fiche("222", verdict: true, date: "2026-10-01"),
                      fiche("333", date: "2026-11-10"), fiche("444", date: "2026-11-12"), fiche(nil, date: "2026-10-01")]
        #expect(try Contenu.ecrire(fiches, business: "roleo", store, aujourdhui: "2026-11-13") == 6)

        let taches = try store.db.query("select * from a_traiter where fait_le is null order by id")
        #expect(taches.map { $0.texte("id") } == ["contenu:verdict:111", "contenu:verdict:444"])
        #expect(taches.map { $0.texte("ton") } == ["alerte", "neutre"])
        #expect(taches.map { $0.texte("etiquette") } == ["8 nov.", "12 nov."])
        #expect(taches[0].texte("texte") == "Verdict : Vidéo 111")
        #expect(taches[0].texte("lien") == "file:///bank/format-scripte/4-astuces/fait/111.md")
        let videos = try store.db.query("select id, format, verdict from video where titre is not null order by id")
        #expect(videos.map { $0.texte("id") } == ["111", "222", "333", "444"])
        #expect(videos[1].booleen("verdict") && videos[0].texte("format") == "4-astuces")

        // le verdict écrit, la tâche se ferme
        _ = try Contenu.ecrire([fiche("111", verdict: true, date: "2026-11-01")], business: "roleo", store, aujourdhui: "2026-11-13")
        #expect(try store.db.query("select id from a_traiter where fait_le is null").isEmpty)
    }

    @Test func fichiersLus() throws {
        let racine = FileManager.default.temporaryDirectory.appending(path: "contenu-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: racine) }
        for (chemin, texte) in [("_fiche.md", "# modèle"), ("famille/comment-dire/a.md", "# A"),
                                ("famille/comment-dire/fait/2026-10-13-b.md", "# B"), ("famille/comment-dire/brouillons/c.md", "# C")] {
            let u = racine.appending(path: chemin)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try texte.write(to: u, atomically: true, encoding: .utf8)
        }
        let fiches = try Contenu.lire(racine.path)
        #expect(fiches.map(\.titre) == ["A", "B"])
        #expect(fiches.map(\.dossier) == ["comment-dire", "comment-dire"])
        #expect(fiches[1].date == Jour.date("2026-10-13"))
        #expect(throws: SourceErreur.self) { try Contenu.lire(racine.path + "/absent") }
    }
}
