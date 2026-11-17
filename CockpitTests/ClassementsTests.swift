import Foundation
import Testing
@testable import CockpitNoyau

@MainActor
struct ClassementsTests {
    let store = try! Store.memoire()
    let roleo = "6770304361"

    /// Une page viewTop réduite : les trois listes dans le désordre, gratuites à 210 ids, et le doublon `selectedChart`.
    func page(gratuites: [String]) -> String {
        func liste(_ id: String, _ titre: String, _ ids: [String]) -> String {
            #"{"adamIds":["# + ids.map { "\"\($0)\"" }.joined(separator: ",") + #"],"shortTitle":"\#(titre)","id":"\#(id)","title":"Classement des apps \#(titre.lowercased()) (iPhone)"}"#
        }
        let charts = [liste("30", "Payantes", ["1", "2"]), liste("27", "Gratuites", gratuites), liste("38", "Rentables", [roleo])]
        return #"<html><script>its.serverData={"pageData":{"topChartsPageData":{"topCharts":["#
            + charts.joined(separator: ",")
            + #"],"selectedChart":{"adamIds":["999"],"id":"27"}}}}</script><script>autre</script></html>"#
    }

    @Test func listesDeViewTop() throws {
        let gratuites = (1...210).map(String.init)
        let listes = try Classements.listes(page(gratuites: gratuites))
        #expect(listes[.payant] == ["1", "2"])
        #expect(listes[.gratuit] == Array(gratuites.prefix(200)))
        #expect(listes[.recettes] == [roleo])
    }

    @Test func viewTopSansListes() {
        #expect(throws: SourceErreur.self) { try Classements.listes("<html>vide</html>") }
        let incomplete = page(gratuites: []).replacingOccurrences(of: #""id":"38""#, with: #""id":"99""#)
        #expect(throws: SourceErreur.self) { try Classements.listes(incomplete) }
    }

    @Test func fluxRSS() throws {
        let plusieurs = #"{"feed":{"entry":[{"id":{"attributes":{"im:id":"1"}}},{"id":{"attributes":{"im:id":"2"}}}]}}"#
        let une = #"{"feed":{"entry":{"id":{"attributes":{"im:id":"3"}}}}}"#
        #expect(try Classements.listeRSS(Data(plusieurs.utf8)) == ["1", "2"])
        #expect(try Classements.listeRSS(Data(une.utf8)) == ["3"])
        #expect(try Classements.listeRSS(Data(#"{"feed":{}}"#.utf8)) == [])
    }

    @Test func lookup() throws {
        let json = """
        {"resultCount":2,"results":[
          {"trackId":6770304361,"trackName":"Roleo : Parler anglais IA","artistName":"Tony Sanchez",
           "artworkUrl100":"https://exemple/100x100bb.jpg","artworkUrl512":"https://exemple/512x512bb.jpg",
           "primaryGenreId":6017,"averageUserRating":4.69862,"userRatingCount":73,"version":"2.0.3"},
          {"wrapperType":"artist","artistName":"Sans app"}
        ]}
        """
        let applis = try Classements.applis(Data(json.utf8))
        #expect(applis.count == 1)
        let a = try #require(applis.first)
        #expect(a.id == roleo)
        #expect(a.nom == "Roleo : Parler anglais IA")
        #expect(a.editeur == "Tony Sanchez")
        #expect(a.icone == "https://exemple/512x512bb.jpg")
        #expect(a.genre == 6017)
        #expect(a.note == 4.69862)
        #expect(a.nbNotes == 73)
        #expect(a.version == "2.0.3")
        #expect(a.business == nil)
        #expect(throws: SourceErreur.self) { try Classements.applis(Data("pas du json".utf8)) }
    }

    /// Un classement où Roleo est à `position`, ou absent.
    func top(_ pays: String, _ genre: Int, gratuit: Int? = nil, recettes: Int? = nil, rss: Bool = false) -> Classements.Top {
        func ids(_ position: Int?) -> [String] {
            var ids = (1...200).map { "autre\($0)" }
            if let position { ids[position - 1] = roleo }
            return ids
        }
        return Classements.Top(pays: pays, genre: genre, listes: [.gratuit: ids(gratuit), .payant: ids(nil), .recettes: ids(recettes)], rss: rss)
    }

    @Test func filDesRangs() throws {
        let source = Classements()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let t1 = t0.addingTimeInterval(3 * 3600)
        let tops = [top("fr", 6017, gratuit: 152, recettes: nil), top("fr", 36, gratuit: 190), top("es", 6017, gratuit: 30)]

        #expect(try source.fil(app: roleo, business: "roleo", tops: tops, at: t1, store: store).isEmpty)

        try store.rang(app: roleo, pays: "fr", genre: 6017, liste: .gratuit, at: t0, position: 176)
        try store.rang(app: roleo, pays: "fr", genre: 6017, liste: .recettes, at: t0, position: 188)
        try store.rang(app: roleo, pays: "es", genre: 6017, liste: .gratuit, at: t0, position: 40)
        let fil = try source.fil(app: roleo, business: "roleo", tops: tops, at: t1, store: store)

        #expect(fil.map(\.texte).sorted() == [
            "152e en gratuit, Éducation France (+24)",
            "190e en gratuit, Toutes catégories France (entrée)",
            "Hors top 200 en recettes, Éducation France (était 188e)",
        ])
        #expect(fil.allSatisfy { $0.type == .rang && $0.business == "roleo" && $0.at == t1 })
        let ids = Set(fil.map(\.id))
        #expect(ids.contains("classements:\(roleo):fr:6017:gratuit:\(t1.iso)"))
        #expect(ids.contains("classements:\(roleo):fr:6017:recettes:\(t0.iso)"))
        #expect(fil.first?.lien == "https://apps.apple.com/fr/app/id\(roleo)")

        // Une liste lue en RSS ne fait pas de fil.
        #expect(try source.fil(app: roleo, business: "roleo", tops: [top("fr", 6017, gratuit: 100, rss: true)], at: t1, store: store).isEmpty)
    }

    @Test func idApp() {
        #expect(Classements.idApp(roleo) == roleo)
        #expect(Classements.idApp("  \(roleo)\n") == roleo)
        #expect(Classements.idApp("https://apps.apple.com/fr/app/roleo-parler-anglais-ia/id\(roleo)?l=en") == roleo)
        #expect(Classements.idApp("https://apps.apple.com/us/app/squid123/id456789") == "456789")
        #expect(Classements.idApp("apps.apple.com/app/id42") == "42")
        #expect(Classements.idApp("Roleo") == nil)
        #expect(Classements.idApp("") == nil)
    }

    @Test func place() {
        #expect(Classements.place(1) == "1re")
        #expect(Classements.place(152) == "152e")
    }
}
