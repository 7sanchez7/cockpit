import Foundation
import Testing
@testable import CockpitNoyau

@MainActor
struct StoreTests {
    let store = try! Store.memoire()

    @Test func graine() throws {
        #expect(try store.businesses().map(\.id) == ["roleo"])
        #expect(try store.comptes().count == Graine.roleo.comptes.count)
    }

    @Test func graineRelueSeulementQuandElleChange() throws {
        let url = Graine.fichier(Graine.json)
        let chemin = FileManager.default.temporaryDirectory.appending(path: "graine-\(UUID().uuidString).sqlite").path
        try Store(chemin: chemin, graine: url).activer(compte: "tiktok:tonyolingo", false)
        try Store(chemin: chemin, graine: url).supprimerBusiness("roleo")
        // même fichier : rien ne revient
        #expect(try Store(chemin: chemin, graine: url).businesses().isEmpty)
        // fichier modifié : le business revient, le compte en pause y reste
        try Data(Graine.json.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(60)], ofItemAtPath: url.path)
        let s = try Store(chemin: chemin, graine: url)
        #expect(try s.businesses().map(\.id) == ["roleo"])
        #expect(try s.comptes().first { $0.id == "tiktok:tonyolingo" }?.actif == false)
    }

    @Test func graineAbsenteOuIllisible() throws {
        let absente = FileManager.default.temporaryDirectory.appending(path: "absente.json")
        #expect(try Store(chemin: ":memory:", graine: absente).businesses().isEmpty)
        #expect(throws: SourceErreur.self) { try Store(chemin: ":memory:", graine: Graine.fichier(#"{"businesses": [{"nom": "X"}]}"#)) }
    }

    @Test func graineExemple() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "outils/graine.exemple.json")
        let s = try Store(chemin: ":memory:", graine: url)
        #expect(try s.businesses().first?.config.evenements.usage == "lesson_completed")
        #expect(try s.comptes().count == 3)
    }

    @Test func graineMinimale() throws {
        let s = try Store(chemin: ":memory:", graine: Graine.fichier(#"""
            {"businesses": [{"id": "app", "nom": "mon app"}],
             "comptes": [{"business": "app", "plateforme": "tiktok", "handle": "@Mon.App"}]}
            """#))
        let b = try s.businesses()[0]
        #expect(b.lettre == "M" && b.teinte == "menthe" && b.config.evenements.essai == "trial_started")
        #expect(try s.comptes().map(\.id) == ["tiktok:mon.app"])
    }

    @Test func comptesSuivisEditables() throws {
        try store.ajouter(Compte(business: "roleo", plateforme: .facebook, handle: "roleo.app"))
        try store.activer(compte: "tiktok:tonyolingo", false)
        try store.retirer(compte: "youtube:holaestony")
        let c = try store.comptes()
        #expect(c.map(\.id).contains("facebook:roleo.app"))
        #expect(!c.map(\.id).contains("youtube:holaestony"))
        #expect(c.first { $0.id == "tiktok:tonyolingo" }?.actif == false)
        // réajouter un compte en pause le relance
        try store.ajouter(Compte(business: "roleo", plateforme: .tiktok, handle: "tonyolingo"))
        #expect(try store.comptes().first { $0.id == "tiktok:tonyolingo" }?.actif == true)
    }

    @Test func handleDepuisSaisie() {
        #expect(Compte.handle("@Hola.EsTony") == "hola.estony")
        #expect(Compte.handle("https://www.tiktok.com/@tonyolingo?lang=fr") == "tonyolingo")
        #expect(Compte.handle("https://www.instagram.com/holaestony/") == "holaestony")
        #expect(Compte.handle("deux mots") == nil)
    }

    @Test func serieRemplaceLaValeurDuJour() throws {
        try store.serie("roleo", "actifs", jour: "2026-11-13", 10)
        try store.serie("roleo", "actifs", jour: "2026-11-13", 12)
        let l = try store.db.query("select valeur from serie where metrique = 'actifs'")
        #expect(l.count == 1)
        #expect(l.first?.nombre("valeur") == 12)
    }

    @Test func historiqueIncompletSiHierOuLePlusVieuxManque() throws {
        func incomplet() throws -> Bool { try store.historiqueIncomplet("roleo", "actifs", jours: 30, jusqua: "2026-11-13") }
        #expect(try incomplet())
        try store.serie("roleo", "actifs", jour: "2026-11-12", 1)
        #expect(try incomplet())
        try store.serie("roleo", "actifs", jour: "2026-10-15", 1)
        #expect(try !incomplet())
    }

    @Test func filNeRenotifiePas() throws {
        let e = Evenement(id: "posthog:essai:1", business: "roleo", at: .now, type: .essai, texte: "Essai annuel")
        #expect(try store.fil(e))
        #expect(try !store.fil(e))
        #expect(store.prendreNouveaux(source: "revenuecat").isEmpty)
        #expect(store.prendreNouveaux(source: "posthog").map(\.id) == ["posthog:essai:1"])
        #expect(store.prendreNouveaux(source: "posthog").isEmpty)
    }

    @Test func tachesSynchronisees() throws {
        try store.synchroniserTaches(source: "asc", business: "roleo", [Tache(cle: "avis:1", texte: "a"), Tache(cle: "avis:2", texte: "b")])
        try store.synchroniserTaches(source: "asc", business: "roleo", [Tache(cle: "avis:2", texte: "b")])
        let ouvertes = try store.db.query("select id from a_traiter where fait_le is null").compactMap { $0.texte("id") }
        #expect(ouvertes == ["asc:avis:2"])
    }

    @Test func clientsAVerifier() throws {
        let relu = Date(timeIntervalSince1970: 1_794_000_000)
        try store.installs(business: "roleo", depuis: "2026-10-01", [
            Install(jour: "2026-10-05", essai: true, client: "ancien"),
            Install(jour: "2026-11-10", essai: true, client: "jamais"),
            Install(jour: "2026-11-11", essai: true, client: "paye"),
            Install(jour: "2026-11-12", essai: true, client: "essai-vieux"),
            Install(jour: "2026-11-13", essai: true, client: "essai-frais"),
            Install(jour: "2026-11-13"),
        ])
        for (client, etat, lu) in [("ancien", EtatPaiement.essai, -60.0), ("paye", .paye, -60), ("essai-vieux", .essai, -60),
                                   ("essai-frais", .essai, 60)] {
            try store.paiement(business: "roleo", client: client, etat, lu: relu.addingTimeInterval(lu))
        }
        #expect(try store.clientsAVerifier(business: "roleo", depuis: "2026-11-01", relu: relu, limite: 10) == ["essai-vieux", "jamais"])
        #expect(try store.clientsAVerifier(business: "roleo", depuis: "2026-11-01", relu: relu, limite: 1) == ["essai-vieux"])
    }

    @Test func journal() throws {
        let debut = Date.now
        try store.journal(Passage(source: "posthog", debut: debut, fin: debut, etat: .erreur, erreur: "HTTP 500", lignes: 0))
        #expect(try store.dernierSucces("posthog") == nil)
        try store.journal(Passage(source: "posthog", debut: debut.addingTimeInterval(1), fin: debut.addingTimeInterval(2), etat: .ok, erreur: nil, lignes: 3))
        #expect(try store.dernierPassage("posthog")?.lignes == 3)
        #expect(try store.dernierSucces("posthog") != nil)
    }
}
