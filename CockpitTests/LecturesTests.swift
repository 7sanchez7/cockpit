import Foundation
import Testing
@testable import CockpitNoyau

@MainActor
struct LecturesTests {
    let store = try! Store.memoire()
    let maintenant = Date(iso: "2026-11-13T14:00:00Z")!
    var lectures: Lectures { Lectures(db: store.db, businesses: try! store.businesses(), maintenant: maintenant) }

    @Test func valeurEtJoursSansRelevé() throws {
        try store.serie("roleo", Metrique.actifs, jour: "2026-11-13", 386)
        try store.serie("roleo", Metrique.actifs, jour: "2026-11-11", 300)
        #expect(lectures.valeur(Metrique.actifs, jour: "2026-11-13") == 386)
        #expect(lectures.valeur(Metrique.installs, jour: "2026-11-13") == nil)
        #expect(lectures.jours(Metrique.actifs, 3, jusqua: "2026-11-13") == [300, nil, 386])
    }

    @Test func periodeCouverteEnPartie() throws {
        for jour in ["2026-11-10", "2026-11-11", "2026-11-12"] { try store.serie("roleo", Metrique.vuesTikTok, jour: jour, 100) }
        for jour in Jour.derniers(14, jusqua: "2026-11-12") { try store.serie("roleo", Metrique.mrrBrut, jour: jour, 500) }
        let f = Fenetre(periode: .semaine, maintenant: maintenant)
        let vues = f.mesure(lectures, Metrique.vuesTikTok)
        #expect(vues.valeur == 300 && vues.avant == nil && vues.couverture == "sur 3 j")
        let mrr = f.mesure(lectures, Metrique.mrrBrut, cumul: .dernier)
        #expect(mrr.valeur == 500 && mrr.jours == nil)
        let euros = vues.map(Metrique.enEuros)
        #expect(euros.valeur == 276 && euros.serie.last == 92 && euros.couverture == "sur 3 j")
    }

    @Test func heuresSurVingtQuatre() throws {
        try store.serie("roleo", Metrique.actifsHeure, jour: "2026-11-13", heure: 9, 32)
        let h = lectures.heures(Metrique.actifsHeure, jour: "2026-11-13")
        #expect(h.count == 24)
        #expect(h[9] == 32)
        #expect(h[10] == nil)
    }

    @Test func filtreSurLeBusiness() throws {
        try store.enregistrer(Business(id: "app2", nom: "App 2", lettre: "A", teinte: "ciel", config: .init()))
        try store.serie("roleo", Metrique.installs, jour: "2026-11-13", 10)
        try store.serie("app2", Metrique.installs, jour: "2026-11-13", 5)
        let tous = try store.businesses()
        #expect(Lectures(db: store.db, businesses: tous).valeur(Metrique.installs, jour: "2026-11-13") == 15)
        #expect(Lectures(db: store.db, businesses: tous.filter { $0.id == "app2" }).valeur(Metrique.installs, jour: "2026-11-13") == 5)
    }

    @Test func vueParStore() throws {
        try store.serie("roleo", Metrique.actifs, jour: "2026-11-13", 158)
        try store.serie("roleo", Boutique.appStore.metrique(Metrique.actifs), jour: "2026-11-13", 152)
        try store.serie("roleo", Boutique.playStore.metrique(Metrique.actifs), jour: "2026-11-13", 6)
        try store.serie("roleo", Metrique.coutIA, jour: "2026-11-13", 7)
        var l = lectures
        #expect(l.valeur(Metrique.actifs, jour: "2026-11-13") == 158)
        l.boutique = .playStore
        #expect(l.valeur(Metrique.actifs, jour: "2026-11-13") == 6)
        #expect(l.jours(Metrique.actifs, 1, jusqua: "2026-11-13") == [6])
        // une métrique sans découpe reste le total
        #expect(l.valeur(Metrique.coutIA, jour: "2026-11-13") == 7)
        l.boutique = .appStore
        #expect(l.valeur(Metrique.actifs, jour: "2026-11-13") == 152)
    }

    @Test func filBorneSurLesJoursDeParis() throws {
        for (id, at) in [("veille", "2026-11-11T22:30:00Z"), ("jour", "2026-11-11T23:30:00Z"), ("lendemain", "2026-11-12T23:30:00Z")] {
            _ = try store.fil(Evenement(id: id, business: "roleo", at: Date(iso: at)!, type: .achat, texte: id, lien: nil))
        }
        let du = try #require(Jour.date("2026-11-12")), au = try #require(Jour.date("2026-11-13"))
        #expect(lectures.fil(du: du, au: au).map(\.id) == ["jour"])
        #expect(lectures.fil().map(\.id) == ["lendemain", "jour", "veille"])
    }

    @Test func videoGainSur24hEtSeuil() throws {
        try store.video(Video(id: "1", business: "roleo", compte: "holaestony", legende: "4 insultes\n#espagnol",
                              publieeLe: Date(iso: "2026-11-01T10:00:00Z"), dureeS: 30, url: nil))
        try store.releve(Releve(video: "1", at: Date(iso: "2026-11-12T13:00:00Z")!, vues: 1000, partages: 5, enregistrements: 10))
        try store.releve(Releve(video: "1", at: Date(iso: "2026-11-13T13:30:00Z")!, vues: 1400, partages: 8, enregistrements: 21))
        let v = try #require(lectures.videos().first)
        #expect(v.titre == "4 insultes")
        #expect(v.vues == 1400)
        #expect(v.gain24h == 400)
        #expect(v.seuilAtteint)
    }

    @Test func videoRecenteGagneToutesSesVues() throws {
        try store.video(Video(id: "2", business: "roleo", compte: "holaestony", legende: "Neuve",
                              publieeLe: Date(iso: "2026-11-13T08:00:00Z"), dureeS: nil, url: nil))
        try store.releve(Releve(video: "2", at: Date(iso: "2026-11-13T13:00:00Z")!, vues: 6420, partages: 20, enregistrements: 78))
        let v = try #require(lectures.videos().first)
        #expect(v.gain24h == 6420)
        #expect(!v.seuilAtteint)
    }

    @Test func tacheEnRetardPasseEnAlerteEtDevant() throws {
        try store.ajouterTache(texte: "Plus tard", business: nil, echeance: "2026-11-20")
        try store.ajouterTache(texte: "En retard", business: "roleo", echeance: "2026-11-10")
        let t = lectures.taches()
        #expect(t.map(\.texte) == ["En retard", "Plus tard"])
        #expect(t[0].ton == .alerte)
        #expect(t[0].pastille(aujourdhui: "2026-11-13") == "retard")
        #expect(t[1].pastille(aujourdhui: "2026-11-19") == "demain")
        #expect(lectures.nbATraiter() == 2)
    }

    @Test func rangEtGainDepuisLaVeille() throws {
        try store.app(Appli(id: "6770304361", nom: "Roleo", business: "roleo"))
        let veille = Date(iso: "2026-11-12T12:00:00Z")!
        try store.rang(app: "6770304361", pays: "fr", genre: 6017, liste: .gratuit, at: veille, position: 163)
        try store.rang(app: "6770304361", pays: "fr", genre: 6017, liste: .gratuit, at: maintenant, position: 152)
        let (cle, ligne) = try #require(lectures.rangPrincipal())
        #expect(ligne.rangs[cle] == 152)
        #expect(ligne.gain(cle) == 11)
    }

    @Test func dernierPassageParSource() throws {
        try store.journal(Passage(source: "posthog", debut: veilleDe(maintenant), fin: veilleDe(maintenant), etat: .erreur, erreur: "x", lignes: 0))
        try store.journal(Passage(source: "posthog", debut: maintenant, fin: maintenant, etat: .ok, erreur: nil, lignes: 12))
        #expect(lectures.derniersPassages()["posthog"]?.etat == .ok)
    }

    private func veilleDe(_ d: Date) -> Date { d.addingTimeInterval(-86_400) }
}

struct FormatTests {
    let espace = "\u{202F}"

    @Test func nombres() {
        #expect(Format.entier(48_200) == "48\(espace)200")
        #expect(Format.compact(337_500) == "338 k")
        #expect(Format.compact(25_400) == "25,4 k")
        #expect(Format.compact(48_000) == "48 k")
        #expect(Format.compact(2_000_000) == "2 M")
        #expect(Format.compact(6420) == "6\(espace)420")
        #expect(Format.delta(-96) == "\u{2212}96")
        #expect(Format.delta(0) == "+0")
        #expect(Format.points(0.123, 0.1) == "+2,3 pt")
        #expect(Format.points(0.05, 0.1) == "\u{2212}5,0 pt")
        #expect(Format.points(0.1, 0.1) == "= 0 pt")
        #expect(Format.points(0.1, nil) == nil)
        #expect(Format.pourcent(0.0099, decimales: 2) == "0,99 %")
        #expect(Format.variation(386, 354) == "+9 %")
        #expect(Format.variation(147, 153) == "\u{2212}4 %")
        #expect(Format.variation(3, 0) == nil)
    }

    @Test func argent() {
        #expect(Format.euros(7.1) == "7,10 €")
        #expect(Format.rang(152) == "152e")
        #expect(Format.rang(1) == "1er")
    }

    @Test func dates() {
        let d = Date(iso: "2026-11-12T13:52:00Z")!
        #expect(Format.heure(d) == "14:52")
        #expect(Format.dateLongue(d) == "Jeudi 12 novembre")
        #expect(Format.age(d, maintenant: Date(iso: "2026-11-13T09:00:00Z")!) == "J+1")
        #expect(Format.age(d, maintenant: Date(iso: "2026-12-01T09:00:00Z")!) == "19 j")
        #expect(Format.ilYa(d, maintenant: d.addingTimeInterval(190)) == "il y a 3 min")
    }
}
