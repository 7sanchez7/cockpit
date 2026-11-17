import Foundation
import Testing
@testable import CockpitNoyau

/// Foundation a aussi un `Dimension`.
typealias Dimension = CockpitNoyau.Dimension

@MainActor
struct PostHogTests {
    let store = try! Store.memoire()
    /// Jeudi 13 novembre 2026, 14 h 30 à Paris.
    let maintenant = Jour.date("2026-11-13")!.addingTimeInterval(14.5 * 3600)

    /// Une réponse HogQL figée, telle que `/query/` la rend.
    func lignes(_ results: String, hasMore: Bool = false) throws -> [[Any]] {
        let json = #"{"columns": [], "types": [], "limit": 100, "offset": 0, "hasMore": \#(hasMore), "results": \#(results)}"#
        return try PostHog.lignes(JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any])
    }

    func valeur(_ metrique: String, _ jour: String, heure: Int = -1) throws -> Double? {
        try store.db.query("select valeur from serie where business = 'roleo' and metrique = ? and jour = ? and heure = ?",
                           [metrique, jour, heure]).first?.nombre("valeur")
    }

    func lecture() throws -> LecturePostHog {
        var l = LecturePostHog()
        // le total, puis App Store, puis Play Store
        l.series = try PostHog.series(jours: lignes(#"""
            [["2026-11-06", 327, 160, 8, 4, 20, 10, 300, 150, 7, 4, 18, 9, 20, 8, 1, 0, 2, 1],
             ["2026-11-12", 490, 490, 6, 6, 300, 300, 470, 470, 6, 6, 290, 290, 15, 15, 0, 0, 10, 10],
             ["2026-11-13", 230, 230, 3, 3, 100, 100, 220, 220, 2, 2, 95, 95, 9, 9, 1, 1, 5, 5]]
            """#), installs: lignes(#"[["2026-11-06", 115, 40, 110, 38, 5, 2], ["2026-11-13", 51, 51, 47, 47, 4, 4]]"#))
        l.actifsHeure = try PostHog.parHeure(lignes(#"[["2026-11-13", 0, 20, 19, 1], ["2026-11-13", 9, 31, 28, 3]]"#))
        l.fil = try PostHog.fil(lignes(#"""
            [["0193a1b2-0000-0000-0000-000000000001", 1794470458, "Yearly", "onboarding", "BE"],
             ["0193a1b2-0000-0000-0000-000000000002", 1794454390, "Yearly", "round_locked", "ES"],
             ["0193a1b2-0000-0000-0000-000000000003", 1794409202, "roleo_quarterly:trimestriel", null, null]]
            """#), business: "roleo")
        l.horaire = .init(debut: "2026-11-01", installs: try PostHog.installs(lignes("[" + [
            install("2026-11-03", loin: 17, [1, 1, 0, 1, 1, 1, 0, 0], client: "c1",
                    [.age: "18_24", .source: "tiktok", .interet: "music, films", .pays: "FR", .version: "2.0.2", .build: "43"]),
            install("2026-11-03", loin: 16, [1, 0, 1, 1, 0, 0, 0, 0], client: "c2",
                    [.age: "25_34", .source: "tiktok", .interet: "music", .pays: "FR", .version: "2.0.2", .build: "43"]),
            install("2026-11-05", loin: 17, [1, 1, 0, 0, 0, 0, 0, 0], client: "c3",
                    [.age: "18_24", .source: "instagram", .pays: "ES", .version: "2.0.2", .build: "43"]),
            install("2026-11-12", loin: 6, [0, 0, 0, 0, 0, 0, 0, 0], [.age: "18_24", .source: "tiktok", .version: "2.0.3", .build: "9"]),
            install("2026-11-12", loin: 0, [0, 0, 0, 0, 0, 0, 0, 0]),
        ].joined(separator: ", ") + "]")),
            portes: try PostHog.portes(lignes(#"[["2026-11-12", "onboarding", 8, 2, 1], ["2026-11-12", "round_locked", 12, 1, 0]]"#)))
        return l
    }

    /// Une ligne de la requête par install ; `drapeaux` dans l'ordre paywall, essai, direct, rond, j1, j7, j14, j30.
    func install(_ jour: String, loin: Int, _ drapeaux: [Int], client: String = "", _ valeurs: [Dimension: String] = [:]) -> String {
        let v = Dimension.lues.map { "\"\($0 == .loin ? String(loin) : valeurs[$0] ?? "")\"" }
        return "[\"\(jour)\", \(loin), \(drapeaux.map(String.init).joined(separator: ", ")), \"\(client)\", \(v.joined(separator: ", "))]"
    }

    /// La lecture écrite, le calcul horaire daté de maintenant, et ce que RevenueCat a dit des convertis.
    func arbre(paiements: Bool = true) throws -> Lectures {
        _ = try ecrire(lecture())
        try store.regler("posthog.horaire.roleo", maintenant.iso)
        if paiements {
            for (client, etat) in [("c1", EtatPaiement.paye), ("c2", .paye), ("c3", .essai)] {
                try store.paiement(business: "roleo", client: client, etat, lu: maintenant)
            }
        }
        return Lectures(db: store.db, businesses: try store.businesses(), maintenant: maintenant)
    }

    func ecrire(_ l: LecturePostHog) throws -> Int {
        try PostHog.ecrire(l, business: "roleo", jours: ["2026-11-12", "2026-11-13"], joursHeures: ["2026-11-13"],
                           maintenant: maintenant, store: store)
    }

    @Test func reponseTronqueeOuSansResultats() throws {
        #expect(throws: SourceErreur.self) { try lignes("[]", hasMore: true) }
        #expect(throws: SourceErreur.self) { try PostHog.lignes(["error": "boom"]) }
        #expect(throws: SourceErreur.self) { try PostHog.parJour(lignes(#"[["2026-11-13", 1]]"#), colonnes: 4) }
        #expect(throws: SourceErreur.self) { try PostHog.installs(lignes(#"[["2026-11-13", 1]]"#)) }
    }

    @Test func seriesEtLeurJ7() throws {
        _ = try ecrire(lecture())
        #expect(try valeur(Metrique.actifs, "2026-11-13") == 230)
        #expect(try valeur(Metrique.actifsJ7, "2026-11-13") == 160)
        #expect(try valeur(Metrique.essais, "2026-11-13") == 3)
        #expect(try valeur(Metrique.essaisJ7, "2026-11-13") == 4)
        #expect(try valeur(Metrique.installs, "2026-11-13") == 51)
        #expect(try valeur(Metrique.installsJ7, "2026-11-13") == 40)
        #expect(try valeur(Metrique.ronds, "2026-11-13") == 100)
        #expect(try valeur(Metrique.rondsJ7, "2026-11-13") == 10)
        // jour sans ligne : zéro, pas de trou
        #expect(try valeur(Metrique.installs, "2026-11-12") == 0)
        #expect(try valeur(Metrique.actifsJ7, "2026-11-12") == 0)
    }

    @Test func seriesParStore() throws {
        _ = try ecrire(lecture())
        let play = Boutique.playStore, app = Boutique.appStore
        #expect(try valeur(play.metrique(Metrique.actifs), "2026-11-13") == 9)
        #expect(try valeur(play.metrique(Metrique.actifsJ7), "2026-11-13") == 8)
        #expect(try valeur(play.metrique(Metrique.essais), "2026-11-13") == 1)
        #expect(try valeur(play.metrique(Metrique.installs), "2026-11-13") == 4)
        #expect(try valeur(play.metrique(Metrique.installsJ7), "2026-11-13") == 2)
        #expect(try valeur(play.metrique(Metrique.rondsJ7), "2026-11-13") == 1)
        #expect(try valeur(app.metrique(Metrique.installs), "2026-11-13") == 47)
        #expect(try valeur(app.metrique(Metrique.ronds), "2026-11-12") == 290)
        // un store sans ligne : zéro
        #expect(try valeur(play.metrique(Metrique.installs), "2026-11-12") == 0)
        #expect(throws: SourceErreur.self) { try PostHog.series(jours: lignes(#"[["2026-11-13", 1, 1, 0, 0, 0, 0]]"#), installs: []) }
    }

    @Test func requetesParSegment() {
        let jours = PostHog.requeteJours(.init(), depuis: 0, coupe: 1)
        #expect(jours.contains("uniqExactIf(person_id, true)"))
        #expect(jours.contains("countIf(event = 'trial_started' and properties.$os = 'Android' and timestamp < fromUnixTimestamp(1))"))
        let installs = PostHog.requeteInstalls(.init(), depuis: 0, coupe: 1)
        #expect(installs.contains("countIf(os in ('iOS', 'iPadOS')), countIf(os in ('iOS', 'iPadOS') and f < fromUnixTimestamp(1))"))
        #expect(installs.contains("where os in ('iOS', 'iPadOS', 'Android')"))
    }

    @Test func requetesSurLesEvenementsDuBusiness() {
        var e = Business.Evenements()
        e.installation = "signup"
        e.essai = "trial"
        #expect(PostHog.requeteInstalls(e, depuis: 0, coupe: 1).contains("where event = 'signup'"))
        let parInstall = PostHog.requeteParInstall(e, depuis: 0)
        #expect(parInstall.contains("minIf(timestamp, event = 'signup')") && parInstall.contains("countIf(event = 'trial') > 0 as essai"))
        #expect(!parInstall.contains("onboarding_started") && !parInstall.contains("trial_started"))
    }

    @Test func rondsSeulementDepuisLaMesure() throws {
        _ = try PostHog.ecrire(LecturePostHog(), business: "roleo", jours: ["2026-10-14", "2026-10-21", "2026-10-22"],
                               joursHeures: [], maintenant: maintenant, store: store)
        #expect(try valeur(Metrique.ronds, "2026-10-14") == nil)
        #expect(try valeur(Metrique.ronds, "2026-10-21") == 0)
        #expect(try valeur(Metrique.rondsJ7, "2026-10-21") == nil)
        #expect(try valeur(Metrique.rondsJ7, "2026-10-22") == 0)
        #expect(try valeur(Metrique.actifs, "2026-10-14") == 0)
    }

    @Test func actifsParHeureJusquaLHeureEnCours() throws {
        _ = try ecrire(lecture())
        #expect(try valeur(Metrique.actifsHeure, "2026-11-13", heure: 0) == 20)
        #expect(try valeur(Metrique.actifsHeure, "2026-11-13", heure: 9) == 31)
        #expect(try valeur(Metrique.actifsHeure, "2026-11-13", heure: 14) == 0)
        #expect(try valeur(Metrique.actifsHeure, "2026-11-13", heure: 15) == nil)
        #expect(try valeur(Boutique.playStore.metrique(Metrique.actifsHeure), "2026-11-13", heure: 9) == 3)
        #expect(try valeur(Boutique.appStore.metrique(Metrique.actifsHeure), "2026-11-13", heure: 14) == 0)
    }

    @Test func filDesEssais() throws {
        let l = try lecture()
        #expect(l.fil.map(\.texte) == ["Essai annuel, Belgique", "Essai annuel, Espagne, rond verrouillé", "Essai trimestriel"])
        #expect(l.fil[0].id == "posthog:essai:0193a1b2-0000-0000-0000-000000000001")
        #expect(l.fil[0].at == Date(iso: "2026-11-12T08:00:58Z"))
        #expect(l.fil.allSatisfy { $0.type == .essai })
        #expect(PostHog.texteEssai(produit: "monthly", porte: "porte_inconnue", pays: "US") == "Essai mensuel, États-Unis, porte_inconnue")
    }

    @Test func lignesEcritesEtFilSansDoublon() throws {
        let l = try lecture()
        // 2 jours × 8 séries × 3 segments, 15 heures × 3 segments, 3 essais, 5 installs, 2 portes
        #expect(try ecrire(l) == 48 + 45 + 3 + 7)
        #expect(try ecrire(l) == 48 + 45 + 7)
        #expect(try store.db.query("select 1 from install").count == 5)
    }

    @Test func installsDecodes() throws {
        let i = try #require(try lecture().horaire?.installs)
        #expect(i.count == 5)
        #expect(i[0].loin == 17 && i[0].paywall && i[0].essai && !i[0].direct && i[0].j7 && !i[0].j14 && i[0].client == "c1")
        #expect(i[0].valeurs[.interet] == ["music", "films"] && i[0].valeurs[.loin] == ["17"] && i[0].valeurs[.zone] == ["europe"])
        #expect(i[4].client == nil && i[4].valeurs == [.loin: ["0"]])
    }

    @Test func noeudRacineEtRetoursComplets() throws {
        let (d, f) = ("2026-11-01", "2026-11-13")
        let sans = try arbre(paiements: false).noeud([], du: d, au: f)
        #expect(sans.payants == 0 && sans.aVerifier == 3)
        let l = try arbre()
        let tous = l.noeud([], du: d, au: f)
        #expect(tous.installs == 5 && tous.paywall == 3 && tous.essais == 2 && tous.directs == 1 && tous.ronds == 2)
        #expect(tous.payants == 2 && tous.essaisPayes == 1 && tous.enCours == 1 && tous.aVerifier == 0)
        #expect(tous.essaiVersPayant == 1)
        // le 12 n'a pas encore eu son J1, le 5 pas son J7
        #expect(tous.baseJ1 == 3 && tous.j1 == 1 && tous.baseJ7 == 2 && tous.j7 == 1)
        #expect(l.noeud([], du: "2026-11-13", au: "2026-11-13") == .vide)
        #expect(l.premierInstall() == "2026-11-03")
        #expect(l.parJour(du: d, au: f).map(\.installs) == [2, 1, 2])
        #expect(l.cohortes(du: d, au: f) == [
            Cohorte(jour: "2026-11-12", installs: 2, j1: nil, j7: nil, j14: nil, j30: nil),
            Cohorte(jour: "2026-11-05", installs: 1, j1: 0, j7: nil, j14: nil, j30: nil),
            Cohorte(jour: "2026-11-03", installs: 2, j1: 1, j7: 1, j14: nil, j30: nil),
        ])
    }

    @Test func buildsEtLeursInstalls() throws {
        let l = try arbre()
        let b43 = Build(numero: "43", version: "2.0.2", debut: "2026-11-03", fin: "2026-11-05", installs: 3)
        #expect(l.builds() == [b43, Build(numero: "9", version: "2.0.3", debut: "2026-11-12", fin: "2026-11-12", installs: 1)])
        #expect(l.enfants([], par: .build, du: "2026-11-01", au: "2026-11-13").map(\.valeur) == ["43", "9", ""])
        #expect(l.noeud([b43.filtre], du: b43.debut, au: b43.fin).payants == 2)
        #expect(l.parJour([b43.filtre], du: b43.debut, au: b43.fin).map(\.installs) == [2, 1])
        #expect(l.cohortes([b43.filtre], du: b43.debut, au: b43.fin).map(\.installs) == [1, 2])
        #expect(l.cohortes([.valeur(.build, "9")], du: "2026-11-01", au: "2026-11-13").map(\.jour) == ["2026-11-12"])
    }

    @Test func decoupeEtFiltres() throws {
        let l = try arbre()
        let (d, f) = ("2026-11-01", "2026-11-13")
        let ages = l.enfants([], par: .age, du: d, au: f)
        #expect(ages.map(\.valeur) == ["18_24", "", "25_34"] && ages.map(\.installs) == [3, 1, 1])
        let jeunes = l.noeud([.valeur(.age, "18_24")], du: d, au: f)
        #expect(jeunes.installs == 3 && jeunes.essais == 2 && jeunes.payants == 1 && jeunes.enCours == 1)
        #expect(l.noeud([.valeur(.age, "")], du: d, au: f).installs == 1)
        // plusieurs réponses : l'install compte dans chacune
        let interets = l.enfants([], par: .interet, du: d, au: f)
        #expect(interets.map(\.valeur) == ["", "music", "films"] && interets.map(\.installs) == [3, 2, 1])
        #expect(l.enfants([.valeur(.interet, "films")], par: .source, du: d, au: f).map(\.valeur) == ["tiktok"])
        // l'écran atteint suit l'ordre du tunnel
        #expect(l.enfants([], par: .loin, du: d, au: f).map(\.valeur) == ["0", "6", "16", "17"])
        #expect(l.noeud([.ecran(16)], du: d, au: f).installs == 3)
        #expect(l.noeud([.paywall], du: d, au: f).installs == 3)
        #expect(l.noeud([.essai], du: d, au: f).installs == 2)
        #expect(l.noeud([.payant], du: d, au: f).installs == 2)
        #expect(l.noeud([.valeur(.age, "18_24"), .essai, .payant], du: d, au: f).installs == 1)
        #expect(Filtre.valeur(.age, "18_24").libelle == "Âge : 18-24 ans" && Dimension.age.libelle("35_plus") == "35 ans et plus")
        #expect(Dimension.interet.multiple && !Dimension.source.multiple)
    }

    @Test func ecarterUneValeur() throws {
        let l = try arbre()
        let (d, f) = ("2026-11-01", "2026-11-13")
        #expect(l.noeud([.sauf(.age, "18_24")], du: d, au: f).installs == 2)
        #expect(l.noeud([.sauf(.zone, "europe")], du: d, au: f).installs == 2)
        #expect(l.noeud([.sauf(.interet, "music")], du: d, au: f).installs == 3)
        #expect(Filtre.sauf(.zone, "afrique").libelle == "Zone : sauf Afrique")
    }

    @Test func avantLaMesure() throws {
        let l = try arbre()
        // un install d'avant les ronds fiables, un d'avant la question de l'âge ; rien à remplacer
        try store.installs(business: "roleo", depuis: "9999", PostHog.installs(lignes("[" + [
            install("2026-10-10", loin: 17, [0, 0, 0, 1, 1, 0, 0, 0], [.pays: "SN"]),
            install("2026-10-20", loin: 17, [0, 0, 0, 1, 0, 0, 0, 0], [.pays: "RE"]),
        ].joined(separator: ", ") + "]")))
        let (d, f) = ("2026-10-01", "2026-11-13")
        let tous = l.noeud([], du: d, au: f)
        #expect(tous.installs == 7 && tous.baseRond == 6 && tous.ronds == 3 && tous.baseJ1 == 4 && tous.j1 == 1)
        let ages = l.enfants([], par: .age, du: d, au: f)
        #expect(Dictionary(uniqueKeysWithValues: ages.map { ($0.valeur, $0.installs) }) == ["18_24": 3, "?": 2, "": 1, "25_34": 1])
        #expect(l.noeud([.valeur(.age, Dimension.pasMesure)], du: d, au: f).installs == 2)
        #expect(l.noeud([.valeur(.age, "")], du: d, au: f).installs == 1)
        #expect(l.noeud([.sauf(.age, Dimension.pasMesure)], du: d, au: f).installs == 5)
        // la zone n'a pas de date de mesure : un pays absent reste vide
        let zones = l.enfants([], par: .zone, du: d, au: f)
        #expect(Dictionary(uniqueKeysWithValues: zones.map { ($0.valeur, $0.installs) }) == ["europe": 3, "": 2, "afrique": 1, "outre_mer": 1])
        #expect(l.noeud([.sauf(.zone, "afrique")], du: d, au: f).installs == 6)
        #expect(l.cohortes(du: d, au: f).map(\.jour) == ["2026-11-12", "2026-11-05", "2026-11-03", "2026-10-20"])
        #expect(Dimension.age.libelle(Dimension.pasMesure).hasPrefix("Pas mesuré (avant le "))
    }

    @Test func zoneDuPays() {
        let attendu = ["FR": "europe", "ES": "europe", "SN": "afrique", "MA": "afrique", "RE": "outre_mer", "US": "amerique_nord",
                       "CA": "amerique_nord", "DO": "amerique_latine", "MX": "amerique_latine", "JP": "asie", "AU": "oceanie"]
        for (pays, zone) in attendu { #expect(Dimension.zone(de: pays) == zone, "\(pays)") }
        #expect(Dimension.zone(de: "XX") == nil)
    }

    @Test func tunnelDuNoeudEtPortes() throws {
        let l = try arbre()
        let t = l.tunnel([], du: "2026-11-01", au: "2026-11-13")
        #expect(t.count == PostHog.ecrans.count)
        #expect(t[0] == 4 && t[5] == 4 && t[6] == 3 && t[15] == 3 && t[16] == 2)
        #expect(Array(l.tunnel([.valeur(.source, "tiktok")], du: "2026-11-01", au: "2026-11-13").suffix(2)) == [2, 1])
        let portes = l.portes(du: "2026-11-12", au: "2026-11-12")
        #expect(portes.map(\.porte) == ["round_locked", "onboarding"])
        #expect(portes[1].nom == "fin du tunnel" && portes[1].conversion == 3.0 / 8)
    }
}
