import Foundation
import Testing
@testable import CockpitNoyau

/// Réponses figées de l'API v2 de RevenueCat et de Firestore (ids inventés).
@MainActor
struct RevenueCatTests {
    let store = try! Store.memoire()

    static let projets = #"""
        {"items":[{"object":"project","id":"proj_autre","name":"App 2","created_at":1750000000000},
                  {"object":"project","id":"proj_roleo","name":"Roleo","created_at":1750000000000}],"next_page":null}
        """#

    static let overview = #"""
        {"object":"overview_metrics","currency":"USD","metrics":[
          {"object":"overview_metric","id":"active_trials","name":"Active Trials","unit":"#","period":"P0D","value":23},
          {"object":"overview_metric","id":"active_subscriptions","name":"Active Subscriptions","unit":"#","period":"P0D","value":100},
          {"object":"overview_metric","id":"mrr","name":"MRR","unit":"$","period":"P28D","value":947},
          {"object":"overview_metric","id":"revenue","name":"Revenue","unit":"$","period":"P28D","value":3268},
          {"object":"overview_metric","id":"new_customers","name":"New Customers","unit":"#","period":"P28D","value":2400}]}
        """#

    /// `actives_new` sur deux jours : minuit UTC du 11 et du 12 novembre 2026.
    static let activesNew = #"""
        {"object":"chart_data","category":"subscription","display_name":"New Paid Subscriptions","resolution":"day",
         "measures":[{"display_name":"Trial Conversions","unit":"#","chartable":true,"decimal_precision":0},
                     {"display_name":"Intro Offers","unit":"#","chartable":true,"decimal_precision":0},
                     {"display_name":"Direct Subscriptions","unit":"#","chartable":true,"decimal_precision":0},
                     {"display_name":"Product Changes","unit":"#","chartable":true,"decimal_precision":0},
                     {"display_name":"Resubscriptions","unit":"#","chartable":true,"decimal_precision":0},
                     {"display_name":"Total Paid Subscriptions","unit":"#","chartable":true,"decimal_precision":0}],
         "values":[{"cohort":1794355200,"incomplete":false,"measure":0,"value":1},
                   {"cohort":1794355200,"incomplete":false,"measure":2,"value":4},
                   {"cohort":1794355200,"incomplete":false,"measure":3,"value":1},
                   {"cohort":1794355200,"incomplete":false,"measure":5,"value":6},
                   {"cohort":1794441600,"incomplete":true,"measure":2,"value":2},
                   {"cohort":1794441600,"incomplete":true,"measure":3,"value":0},
                   {"cohort":1794441600,"incomplete":true,"measure":5,"value":2}]}
        """#

    static let mrr = #"""
        {"resolution":"day","measures":[{"display_name":"MRR","unit":"$"}],
         "values":[{"cohort":1794355200,"incomplete":false,"measure":0,"value":947.95},
                   {"cohort":1794441600,"incomplete":true,"measure":0,"value":947.69}]}
        """#

    @Test func projetParNom() throws {
        #expect(try RevenueCat.projet(Data(Self.projets.utf8), nom: "Roleo") == "proj_roleo")
        #expect(throws: SourceErreur.self) { try RevenueCat.projet(Data(Self.projets.utf8), nom: "App 3") }
        let seul = #"{"items":[{"id":"proj_seul","name":"Roleo iOS"}]}"#
        #expect(try RevenueCat.projet(Data(seul.utf8), nom: "Roleo") == "proj_seul")
    }

    @Test func apercu() throws {
        let a = try RevenueCat.apercu(Data(Self.overview.utf8))
        #expect(a == RevenueCat.Apercu(mrr: 947, abonnes: 100, essais: 23, revenu28j: 3268))
        let tronque = #"{"metrics":[{"id":"mrr","value":947}]}"#
        #expect(throws: SourceErreur.self) { try RevenueCat.apercu(Data(tronque.utf8)) }
    }

    @Test func graphiqueALaJourneeDeParis() throws {
        let g = try RevenueCat.graphique(Data(Self.mrr.utf8))
        #expect(try RevenueCat.mesure("MRR", g) == ["2026-11-11": 947.95, "2026-11-12": 947.69])
        #expect(throws: SourceErreur.self) { try RevenueCat.mesure("Actives", g) }
    }

    @Test func achatsSansChangementsDeProduit() throws {
        let g = try RevenueCat.graphique(Data(Self.activesNew.utf8))
        #expect(try RevenueCat.achats(g) == ["2026-11-11": 5, "2026-11-12": 2])
    }

    @Test func seriesEcrites() throws {
        let a = try RevenueCat.apercu(Data(Self.overview.utf8))
        let mrr = try RevenueCat.mesure("MRR", RevenueCat.graphique(Data(Self.mrr.utf8)))
        let achats = try RevenueCat.achats(RevenueCat.graphique(Data(Self.activesNew.utf8)))
        let points = RevenueCat.points(a, mrr: mrr, abonnes: ["2026-11-11": 100], essais: ["2026-11-11": 20],
                                       achats: achats, revenu: ["2026-11-11": 120, "2026-11-12": 35],
                                       revenu28j: ["2026-11-11": 3200, "2026-11-12": 1], aujourdhui: "2026-11-12")
        try RevenueCat.ecrire(points, business: "roleo", store)
        func valeur(_ metrique: String, _ jour: String) throws -> Double? {
            try store.db.query("select valeur from serie where business = 'roleo' and metrique = ? and jour = ?",
                               [metrique, jour]).first?.nombre("valeur")
        }
        #expect(try valeur(Metrique.mrrBrut, "2026-11-11") == 947.95)
        // aujourd'hui vient de l'overview, pas du graphique incomplet
        #expect(try valeur(Metrique.mrrBrut, "2026-11-12") == 947)
        #expect(try valeur(Metrique.mrrNet, "2026-11-12") == 947 * Metrique.partNette)
        #expect(try valeur(Metrique.abonnes, "2026-11-12") == 100)
        #expect(try valeur(Metrique.essaisActifs, "2026-11-11") == 20)
        #expect(try valeur(Metrique.revenu28j, "2026-11-12") == 3268)
        #expect(try valeur(Metrique.revenu28j, "2026-11-11") == 3200)
        #expect(try valeur(Metrique.achats, "2026-11-12") == 2)
        // le revenu du jour vient du graphique, aujourd'hui compris
        #expect(try valeur(Metrique.revenu, "2026-11-11") == 120)
        #expect(try valeur(Metrique.revenu, "2026-11-12") == 35)
        #expect(try store.db.query("select count(*) as n from serie").first?.entier("n") == points.count)
    }

    /// Un graphique demandé avec `segment=store` sur le 11 et le 12 nov. 2026 : par segment, les valeurs de chaque mesure
    /// jour par jour.
    static func segmente(_ mesures: [String], _ segments: KeyValuePairs<String, [[Double]]>) -> Data {
        let liste = segments.map { #"{"display_name":"\#($0.key)","is_total":\#($0.key == "Total")}"# }
        let valeurs = segments.enumerated().flatMap { s, segment in
            segment.value.enumerated().flatMap { m, jours in
                jours.enumerated().map { j, v in
                    #"{"cohort":\#(1794355200 + 86400 * j),"measure":\#(m),"segment":\#(s),"value":\#(v)}"#
                }
            }
        }
        let corps = #"{"measures":[\#(mesures.map { #"{"display_name":"\#($0)"}"# }.joined(separator: ","))],"#
            + #""segments":[\#(liste.joined(separator: ","))],"values":[\#(valeurs.joined(separator: ","))]}"#
        return Data(corps.utf8)
    }

    @Test func graphiqueParStore() throws {
        let sansPlay = Self.segmente(["MRR"], ["Total": [[900, 950]], "App Store": [[900, 950]]])
        #expect(try RevenueCat.mesure("MRR", RevenueCat.graphique(sansPlay)) == ["2026-11-11": 900, "2026-11-12": 950])
        #expect(try RevenueCat.mesure("MRR", RevenueCat.graphique(sansPlay, boutique: .appStore)) == ["2026-11-11": 900, "2026-11-12": 950])
        // Play sans segment : 0 chaque jour du total, pour que sa vue montre zéro et pas un trou
        #expect(try RevenueCat.mesure("MRR", RevenueCat.graphique(sansPlay, boutique: .playStore)) == ["2026-11-11": 0, "2026-11-12": 0])
        let avecPlay = Self.segmente(["MRR"], ["Total": [[900, 1000]], "App Store": [[900, 750]], "Play Store": [[0, 250]]])
        #expect(try RevenueCat.mesure("MRR", RevenueCat.graphique(avecPlay, boutique: .playStore)) == ["2026-11-11": 0, "2026-11-12": 250])
        #expect(RevenueCat.boutique(segment: "Google Play") == .playStore && RevenueCat.boutique(segment: "Stripe") == nil)
        #expect(RevenueCat.boutique(segment: "iOS") == .appStore && RevenueCat.boutique(segment: "Android") == .playStore)
        #expect(RevenueCat.boutique(segment: "Unknown") == nil)
    }

    @Test func storesSommentAuTotal() throws {
        let a = try RevenueCat.apercu(Data(Self.overview.utf8))
        func un(_ mesure: String, _ total: [Double], _ appStore: [Double]) -> Data {
            Self.segmente([mesure], ["Total": [total], "App Store": [appStore], "Play Store": [zip(total, appStore).map(-)]])
        }
        let g = RevenueCat.Graphiques(
            mrr: un("MRR", [900, 1000], [900, 750]), abonnes: un("Actives", [90, 100], [90, 80]),
            essais: un("Active Trials", [20, 25], [20, 25]),
            achats: Self.segmente(["Product Changes", "Total Paid Subscriptions"],
                                  ["Total": [[0, 0], [4, 3]], "App Store": [[0, 0], [4, 2]], "Play Store": [[0, 0], [0, 1]]]),
            revenu: un("Revenue", [100, 60], [100, 30]),
            nouveaux: Self.segmente(["New Customers"],
                                    ["Total": [[101, 47]], "iOS": [[100, 38]], "Android": [[0, 9]], "Unknown": [[1, 0]]]))
        func points(_ b: Boutique?) throws -> [String: Double] {
            let p = try RevenueCat.points(g, a, boutique: b, depuis: "2026-11-11", aujourdhui: "2026-11-12")
            return Dictionary(uniqueKeysWithValues: p.map { ("\($0.metrique) \($0.jour)", $0.valeur) })
        }
        let total = try points(nil), ios = try points(.appStore), play = try points(.playStore)
        #expect(play["mrr_brut.play_store 2026-11-11"] == 0)
        #expect(play["achats.play_store 2026-11-12"] == 1 && ios["achats.app_store 2026-11-12"] == 2)
        #expect(play["revenu.play_store 2026-11-12"] == 30)
        // aujourd'hui, l'overview au prorata du graphique : 947 × 250/1000 côté Play
        #expect(play["mrr_brut.play_store 2026-11-12"] == 947 * 0.25)
        for m in [Metrique.mrrBrut, Metrique.abonnes, Metrique.essaisActifs, Metrique.revenu28j] {
            let somme = (ios["\(Boutique.appStore.metrique(m)) 2026-11-12"] ?? -1) + (play["\(Boutique.playStore.metrique(m)) 2026-11-12"] ?? -1)
            #expect(abs(somme - (total["\(m) 2026-11-12"] ?? 0)) < 1e-9, "\(m)")
        }
        #expect(total["mrr_brut 2026-11-12"] == 947 && total["mrr_brut 2026-11-11"] == 900)
        // nouveaux clients par première plateforme, aujourd'hui compris ; « Unknown » ne va à aucun store
        #expect(total["nouveaux_clients 2026-11-11"] == 101 && ios["nouveaux_clients.app_store 2026-11-11"] == 100)
        #expect(play["nouveaux_clients.play_store 2026-11-12"] == 9 && ios["nouveaux_clients.app_store 2026-11-12"] == 38)
    }

    @Test func revenuGlissantSurVingtHuitJours() {
        let revenu = Dictionary(uniqueKeysWithValues: Jour.derniers(30, jusqua: "2026-11-12").enumerated().map { ($1, Double($0 + 1)) })
        let r = RevenueCat.revenus28j(revenu, depuis: "2026-10-13", jusqua: "2026-11-12")
        // le 14 oct. vaut 1 : le 9 nov. manque d'un jour, le 10 somme 1…28, le 11 2…29 ; aujourd'hui vient de l'overview
        #expect(r["2026-10-13"] == nil && r["2026-11-09"] == nil)
        #expect(r["2026-11-10"] == Double((1...28).reduce(0, +)))
        #expect(r["2026-11-11"] == Double((2...29).reduce(0, +)))
        #expect(r["2026-11-12"] == nil)
    }

    @Test func requeteComptesValide() {
        #expect(JSONSerialization.isValidJSONObject(RevenueCat.requeteComptes()))
    }

    @Test func comptesPayesRelusRecemment() throws {
        let reponse = #"""
            [{"document":{"name":"projects/p/databases/(default)/documents/users/uid-paye",
                          "fields":{"premiumTrial":{"booleanValue":false},
                                    "entitlementCheckedAt":{"timestampValue":"2026-11-12T20:47:30.123456Z"}}},
              "readTime":"2026-11-13T00:00:00Z"},
             {"document":{"name":"projects/p/databases/(default)/documents/users/uid-essai",
                          "fields":{"premiumTrial":{"booleanValue":true},
                                    "entitlementCheckedAt":{"timestampValue":"2026-11-12T20:00:00.5Z"}}}},
             {"document":{"name":"projects/p/databases/(default)/documents/users/uid-ancien",
                          "fields":{"entitlementCheckedAt":{"timestampValue":"2026-11-01T10:00:00Z"}}}},
             {"document":{"name":"projects/p/databases/(default)/documents/users/uid-vide","fields":{}}}]
            """#
        let depuis = try #require(Date(iso: "2026-11-12T00:00:00Z"))
        #expect(try RevenueCat.comptesPayes(Data(reponse.utf8), depuis: depuis) == ["uid-paye"])
        #expect(try RevenueCat.comptesPayes(Data(#"[{"readTime":"2026-11-13T00:00:00Z"}]"#.utf8), depuis: depuis).isEmpty)
    }

    @Test func abonnementsDeProductionRecents() throws {
        let reponse = #"""
            {"items":[{"object":"subscription","id":"sub_recent","starts_at":1794132000000,"environment":"production","country":"FR","status":"active"},
                      {"object":"subscription","id":"sub_sandbox","starts_at":1794132000000,"environment":"sandbox","country":"FR"},
                      {"object":"subscription","id":"sub_ancien","starts_at":1792490400000,"environment":"production","country":null}],
             "next_page":null}
            """#
        let depuis = try #require(Date(iso: "2026-11-01T00:00:00Z"))
        let a = try RevenueCat.abonnements(Data(reponse.utf8), depuis: depuis)
        #expect(a == [RevenueCat.Abonnement(id: "sub_recent", startsAt: 1794132000000, environment: "production", country: "FR")])
    }

    @Test func achatApresEssai() throws {
        let transactions = #"""
            {"items":[{"object":"transaction","id":"t2","purchased_at":1794492042000,"product_store_identifier":"Yearly",
                       "revenue_in_local_currency":{"currency":"EUR","gross":69.99,"proceeds":59.49,"tax":11.67,"commission":8.75}},
                      {"object":"transaction","id":"t1","purchased_at":1793872800000,"product_store_identifier":"Yearly",
                       "revenue_in_local_currency":{"currency":"EUR","gross":0.0,"proceeds":0.0,"tax":0.0,"commission":0.0}}]}
            """#
        let a = RevenueCat.Abonnement(id: "sub1", startsAt: 1793872800000, environment: "production", country: "FR")
        let e = try #require(try RevenueCat.achat("revenuecat:achat:sub1", a, Data(transactions.utf8), business: "roleo"))
        #expect(e.type == .achat)
        #expect(e.at == Date(timeIntervalSince1970: 1794492042))
        #expect(e.texte.hasPrefix("Annuel après essai, 69,99"))
        #expect(e.texte.hasSuffix("€, France"))
        #expect(try store.fil(e))
        #expect(try store.db.query("select texte from fil where id = 'revenuecat:achat:sub1' and type = 'ACHAT'").count == 1)
    }

    @Test func achatDirectEtEssaiEnCours() throws {
        let direct = #"""
            {"items":[{"id":"t1","purchased_at":1794516438000,"product_store_identifier":"roleo_quarterly:trimestriel",
                       "revenue_in_local_currency":{"currency":"CAD","gross":29.99}}]}
            """#
        let a = RevenueCat.Abonnement(id: "sub2", startsAt: 1794516438000, environment: "production", country: nil)
        let e = try #require(try RevenueCat.achat("revenuecat:achat:sub2", a, Data(direct.utf8), business: "roleo"))
        #expect(e.texte.hasPrefix("Trimestriel, 29,99"))
        #expect(!e.texte.contains("essai"))
        let essai = #"{"items":[{"id":"t1","purchased_at":1794516438000,"product_store_identifier":"Yearly","revenue_in_local_currency":{"currency":"EUR","gross":0}}]}"#
        #expect(try RevenueCat.achat("revenuecat:achat:sub3", a, Data(essai.utf8), business: "roleo") == nil)
    }

    @Test func paiementDuClient() throws {
        func etat(_ items: String) throws -> EtatPaiement { try RevenueCat.paiement(Data(#"{"items":[\#(items)]}"#.utf8)) }
        let paye = #"{"status":"active","environment":"production","total_revenue_in_usd":{"gross":69.99}}"#
        let essai = #"{"status":"trialing","environment":"production","total_revenue_in_usd":{"gross":0}}"#
        let fini = #"{"status":"expired","environment":"production","total_revenue_in_usd":{"gross":0}}"#
        let sandbox = #"{"status":"active","environment":"sandbox","total_revenue_in_usd":{"gross":9.99}}"#
        #expect(try etat(paye + "," + essai) == .paye)
        #expect(try etat(essai + "," + fini) == .essai)
        #expect(try etat(fini) == .non)
        #expect(try etat(sandbox) == .inconnu)
        #expect(try etat("") == .inconnu)
    }

    @Test func formules() {
        #expect(RevenueCat.formule("monthly") == "Mensuel")
        #expect(RevenueCat.formule("Yearly") == "Annuel")
        #expect(RevenueCat.formule("roleo_annual_downsell") == "Annuel")
        #expect(RevenueCat.formule("roleo_weekly:hebdo") == "Hebdo")
        #expect(RevenueCat.formule("roleo_quarterly") == "Trimestriel")
        #expect(RevenueCat.formule("lifetime") == "lifetime")
    }

    @Test func erreurNommeLeBusiness() {
        let e = RevenueCat.nomme(SourceErreur.http(401, "clé refusée"), Business.roleo)
        #expect(e.localizedDescription == "HTTP 401 : Roleo : clé refusée")
    }
}
