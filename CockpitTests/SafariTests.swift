import Foundation
import Testing
@testable import CockpitNoyau

struct SafariTests {
    /// Un fichier `Cookies.binarycookies`, une page par liste.
    func binarycookies(_ pages: [[Safari.Cookie]]) -> Data {
        func petit(_ v: Int) -> [UInt8] { withUnsafeBytes(of: UInt32(v).littleEndian, Array.init) }
        func grand(_ v: Int) -> [UInt8] { withUnsafeBytes(of: UInt32(v).bigEndian, Array.init) }
        let corps = pages.map { cookies in
            let cookies = cookies.map { c -> [UInt8] in
                let chaines = [c.domaine, c.nom, "/", c.valeur].map { Array($0.utf8) + [0] }
                var decalages: [Int] = []
                var fin = 56
                for s in chaines {
                    decalages.append(fin)
                    fin += s.count
                }
                func date(_ d: Date) -> [UInt8] {
                    withUnsafeBytes(of: d.timeIntervalSinceReferenceDate.bitPattern.littleEndian, Array.init)
                }
                return petit(fin) + petit(0) + petit(0) + petit(0) + decalages.flatMap(petit)
                    + [UInt8](repeating: 0, count: 8) + date(c.expire) + date(c.cree) + chaines.flatMap { $0 }
            }
            var page: [UInt8] = [0, 0, 1, 0] + petit(cookies.count)
            var decalage = 8 + 4 * cookies.count + 4
            for c in cookies {
                page += petit(decalage)
                decalage += c.count
            }
            return page + [0, 0, 0, 0] + cookies.flatMap { $0 }
        }
        return Data(Array("cook".utf8) + grand(pages.count) + corps.flatMap { grand($0.count) } + corps.flatMap { $0 })
    }

    @Test func litLesPagesEtFiltreLeDomaine() throws {
        let maintenant = Date(timeIntervalSince1970: 1_794_500_000)
        let demain = maintenant.addingTimeInterval(86_400)
        let cookies = [
            [Safari.Cookie(domaine: ".tiktok.com", nom: "sessionid", valeur: "abc123", expire: demain, cree: maintenant),
             Safari.Cookie(domaine: "nottiktok.com", nom: "autre", valeur: "x", expire: demain)],
            [Safari.Cookie(domaine: "www.tiktok.com", nom: "tt_csrf", valeur: "def", expire: demain),
             Safari.Cookie(domaine: ".tiktok.com", nom: "perime", valeur: "y", expire: maintenant.addingTimeInterval(-1))],
        ]
        let lus = try Safari.lire(binarycookies(cookies))
        #expect(lus == cookies.flatMap { $0 })
        #expect(Safari.session(lus, domaine: "tiktok.com", maintenant: maintenant) == ["sessionid": "abc123", "tt_csrf": "def"])
    }

    @Test func prendLeProfilConnecteEnDernier() {
        let maintenant = Date(timeIntervalSince1970: 1_794_500_000)
        func profil(_ valeur: String, il jours: Double) -> [Safari.Cookie] {
            [Safari.Cookie(domaine: ".instagram.com", nom: "sessionid", valeur: valeur, expire: maintenant.addingTimeInterval(86_400),
                           cree: maintenant.addingTimeInterval(-jours * 86_400))]
        }
        let profils = [profil("vieille", il: 90), profil("neuve", il: 2), [], profil("moyenne", il: 30)]
        #expect(Safari.plusRecente(profils, domaine: "instagram.com", requis: "sessionid", maintenant: maintenant) == ["sessionid": "neuve"])
        #expect(Safari.plusRecente([[]], domaine: "instagram.com", requis: "sessionid", maintenant: maintenant) == nil)
    }

    @Test func garderLeCookieLePlusRecentEnDouble() {
        let maintenant = Date(timeIntervalSince1970: 1_794_500_000)
        func cookie(_ domaine: String, _ valeur: String, il jours: Double) -> Safari.Cookie {
            Safari.Cookie(domaine: domaine, nom: "csrftoken", valeur: valeur, expire: maintenant.addingTimeInterval(86_400),
                          cree: maintenant.addingTimeInterval(-jours * 86_400))
        }
        let cookies = [cookie(".instagram.com", "neuf", il: 1), cookie("www.instagram.com", "vieux", il: 40)]
        #expect(Safari.session(cookies, domaine: "instagram.com", maintenant: maintenant) == ["csrftoken": "neuf"])
    }

    @Test func refuseUnFichierInconnu() {
        #expect(throws: CocoaError.self) { try Safari.lire(Data("pas un fichier".utf8)) }
        let tronque = binarycookies([[Safari.Cookie(domaine: "a.com", nom: "n", valeur: "v", expire: .now)]]).dropLast(3)
        #expect(throws: CocoaError.self) { try Safari.lire(tronque) }
    }
}
