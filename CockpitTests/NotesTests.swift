import Foundation
import Testing
@testable import CockpitNoyau

struct NotesTests {
    /// Une clé et sa valeur protobuf : un entier (type 0) ou des octets (type 2).
    func varint(_ v: Int) -> [UInt8] {
        var v = UInt64(v)
        var r: [UInt8] = []
        repeat {
            r.append(UInt8(v & 0x7F) | (v > 0x7F ? 0x80 : 0))
            v >>= 7
        } while v > 0
        return r
    }
    func entier(_ n: Int, _ v: Int) -> [UInt8] { varint(n << 3) + varint(v) }
    func octets(_ n: Int, _ v: [UInt8]) -> [UInt8] { varint(n << 3 | 2) + varint(v.count) + v }

    /// Le `ZDATA` d'une note : ses lignes, chacune avec son style et sa case cochée ou non.
    func zdata(_ lignes: [(texte: String, style: Int?, fait: Bool)]) throws -> Data {
        let texte = lignes.map(\.texte).joined(separator: "\n")
        let morceaux = lignes.enumerated().flatMap { i, l -> [UInt8] in
            let longueur = l.texte.utf16.count + (i < lignes.count - 1 ? 1 : 0)
            var style: [UInt8] = []
            if let s = l.style { style = entier(1, s) }
            if l.style == Notes.Style.caseACocher { style += octets(5, octets(1, Array("id".utf8)) + entier(2, l.fait ? 1 : 0)) }
            return octets(5, entier(1, longueur) + (l.style == nil ? [] : octets(2, style)))
        }
        let protobuf = octets(2, octets(3, octets(2, Array(texte.utf8)) + morceaux))
        let deflate = try (Data(protobuf) as NSData).compressed(using: .zlib) as Data
        return Data([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 3] + deflate + [UInt8](repeating: 0, count: 8))
    }

    @Test func intertitresEtCases() throws {
        let d = try zdata([
            ("Cockpit", Notes.Style.titre, false),
            ("Finir l'accueil", nil, false),
            ("", nil, false),
            ("Cette semaine", Notes.Style.intertitre, false),
            ("Tourner 3 vidéos", Notes.Style.caseACocher, true),
            ("Relancer l'essai 3 j \u{FFFC}", Notes.Style.caseACocher, false),
            ("Idées", Notes.Style.sousTitre, false),
            ("Carrousel « 5 erreurs » é", 100, false),
        ])
        #expect(Notes.lignes(try Notes.note(d)) == [
            LignePlan(section: "Plan", texte: "Finir l'accueil"),
            LignePlan(section: "Cette semaine", texte: "Tourner 3 vidéos", coche: true, fait: true),
            LignePlan(section: "Cette semaine", texte: "Relancer l'essai 3 j", coche: true, fait: false),
            LignePlan(section: "Idées", texte: "Carrousel « 5 erreurs » é"),
        ])
    }

    @Test func emojisCompteEnUTF16() throws {
        let d = try zdata([("Cockpit", Notes.Style.titre, false), ("🎬 Monter", Notes.Style.caseACocher, false),
                           ("Texte", nil, false)])
        #expect(Notes.lignes(try Notes.note(d)) == [
            LignePlan(section: "Plan", texte: "🎬 Monter", coche: true), LignePlan(section: "Plan", texte: "Texte"),
        ])
    }

    @Test func gzipAvecNomDeFichier() throws {
        var d = [UInt8](try zdata([("Cockpit", 0, false), ("A", nil, false)]))
        d[3] = 8
        d.insert(contentsOf: Array("note.pb".utf8) + [0], at: 10)
        #expect(Notes.lignes(try Notes.note(Data(d))) == [LignePlan(section: "Plan", texte: "A")])
    }

    @Test func refuseCeQuiNEstPasDuGzip() {
        #expect(throws: SourceErreur.self) { try Notes.note(Data(repeating: 1, count: 40)) }
        #expect(throws: SourceErreur.self) { try Protobuf(Data([0x12, 0x09, 0x01])) }
    }
}
