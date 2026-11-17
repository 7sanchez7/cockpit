import Foundation

/// Le plan de l'accueil : la note « Cockpit » de l'app Notes, lue dans la base de Notes en lecture seule. Cockpit doit
/// avoir l'accès complet au disque, comme pour Safari. Voir docs/sources/notes.md.
struct Notes: Source {
    let id = "notes"
    let nom = "Notes"
    let cadence: TimeInterval = 60

    static let base = URL.homeDirectory.appending(path: "Library/Group Containers/group.com.apple.notes/NoteStore.sqlite")
    /// Le titre de la note lue, sa première ligne.
    static let titre = "Cockpit"
    /// La section des lignes écrites avant le premier intertitre.
    static let sectionParDefaut = "Plan"

    /// Les styles de paragraphe de Notes qui comptent ici ; les autres (puces, numéros, texte) font une ligne simple.
    enum Style {
        static let titre = 0, intertitre = 1, sousTitre = 2, caseACocher = 103
    }

    func collecte(_ ctx: Contexte) async throws -> Int {
        let lignes = Self.lignes(try Self.note(try Self.lire()))
        try ctx.store.plan(lignes)
        return lignes.count
    }

    /// Le contenu de la note « Cockpit » modifiée en dernier, hors corbeille et hors note verrouillée.
    static func lire() throws -> Data {
        do {
            try FileHandle(forReadingFrom: base).close()
        } catch CocoaError.fileReadNoPermission, CocoaError.fileWriteNoPermission {
            // FileHandle rend le refus de macOS (EPERM) en fileWriteNoPermission, même en lecture
            throw SourceErreur.nonConfigure(
                "Notes illisible : donner l'accès complet au disque à Cockpit (Réglages Système, Confidentialité et sécurité)")
        } catch CocoaError.fileReadNoSuchFile {
            throw SourceErreur.nonConfigure("pas de base Notes sur ce Mac")
        }
        let db = try Database(chemin: base.path, lecture: true)
        let lignes = try db.query("""
            select d.ZDATA as donnees from ZICCLOUDSYNCINGOBJECT n
            join ZICNOTEDATA d on d.Z_PK = n.ZNOTEDATA
            left join ZICCLOUDSYNCINGOBJECT f on f.Z_PK = n.ZFOLDER
            where trim(n.ZTITLE1) = ? collate nocase and coalesce(n.ZMARKEDFORDELETION, 0) = 0
                and coalesce(n.ZISPASSWORDPROTECTED, 0) = 0 and coalesce(f.ZFOLDERTYPE, 0) != 1
            order by n.ZMODIFICATIONDATE1 desc limit 1
            """, [titre])
        guard let donnees = lignes.first?.donnees("donnees") else {
            throw SourceErreur.nonConfigure("pas de note « \(titre) » dans Notes : la créer, intertitres et cases à cocher")
        }
        return donnees
    }

    /// Le texte d'une note et ses morceaux de même style, dans l'ordre.
    struct Note: Equatable {
        var texte: String
        var morceaux: [Morceau]

        /// `longueur` en unités UTF-16, comme les chaînes de Notes ; `style` vaut -1 pour du texte simple.
        struct Morceau: Equatable {
            var longueur: Int
            var style = -1
            var fait = false
        }
    }

    /// `ZDATA` est un protobuf en gzip : document (2), note (3), texte (2) et morceaux (5) ; un morceau porte sa
    /// longueur (1) et son style de paragraphe (2), qui a son type (1) et sa case cochée ou non (5, puis 2).
    static func note(_ zdata: Data) throws -> Note {
        guard let note = try Protobuf(try gunzip(zdata)).message(2)?.message(3),
              let texte = note.octets(2).flatMap({ String(data: $0, encoding: .utf8) }) else {
            throw SourceErreur.format("note Notes sans texte")
        }
        let morceaux = try note.messages(5).map { m in
            let style = try m.message(2)
            return Note.Morceau(longueur: Int(truncatingIfNeeded: m.entier(1) ?? 0),
                                style: style?.entier(1).map { Int(truncatingIfNeeded: $0) } ?? -1,
                                fait: try style?.message(5)?.entier(2).map { $0 != 0 } ?? false)
        }
        return Note(texte: texte, morceaux: morceaux)
    }

    /// Une ligne du plan par ligne de la note, sans le titre ni les lignes vides. Un titre, intertitre ou sous-titre
    /// ouvre une section ; le style d'une ligne est celui de son premier caractère.
    static func lignes(_ note: Note) -> [LignePlan] {
        var debuts: [(debut: Int, morceau: Note.Morceau)] = []
        var position = 0
        for m in note.morceaux {
            debuts.append((position, m))
            position += m.longueur
        }
        var section = sectionParDefaut
        var r: [LignePlan] = []
        var debut = 0
        for (n, ligne) in Array(note.texte.utf16).split(separator: 0x0A, omittingEmptySubsequences: false).enumerated() {
            defer { debut += ligne.count + 1 }
            // U+FFFC marque une pièce jointe
            let texte = String(decoding: ligne, as: UTF16.self).replacingOccurrences(of: "\u{FFFC}", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard n > 0, !texte.isEmpty else { continue }
            let m = debuts.last { $0.debut <= debut }?.morceau
            switch m?.style {
            case Style.titre, Style.intertitre, Style.sousTitre: section = texte
            case Style.caseACocher: r.append(LignePlan(section: section, texte: texte, coche: true, fait: m?.fait ?? false))
            default: r.append(LignePlan(section: section, texte: texte))
            }
        }
        return r
    }

    /// Saute l'en-tête gzip et ses champs optionnels, inflate le deflate brut, ignore les 8 octets de fin.
    static func gunzip(_ d: Data) throws -> Data {
        let o = [UInt8](d)
        guard o.count > 18, o[0] == 0x1F, o[1] == 0x8B, o[2] == 8 else { throw SourceErreur.format("note Notes pas en gzip") }
        let drapeaux = o[3]
        var i = 10
        func sauterChaine() { i = (i < o.count ? o[i...].firstIndex(of: 0) ?? o.count : o.count) + 1 }
        if drapeaux & 4 != 0, i + 2 <= o.count { i += 2 + (Int(o[i]) | Int(o[i + 1]) << 8) }
        if drapeaux & 8 != 0 { sauterChaine() }
        if drapeaux & 16 != 0 { sauterChaine() }
        if drapeaux & 2 != 0 { i += 2 }
        guard i < o.count - 8 else { throw SourceErreur.format("gzip de Notes tronqué") }
        do {
            return try (Data(o[i..<o.count - 8]) as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw SourceErreur.format("note Notes illisible : \(error.localizedDescription)")
        }
    }
}

/// Un message protobuf lu champ par champ, juste ce qu'il faut pour une note ; les champs de 32 et 64 bits sont sautés.
struct Protobuf {
    private var champs: [(numero: Int, entier: UInt64?, octets: Data?)] = []

    init(_ data: Data) throws {
        let o = [UInt8](data)
        var i = 0
        func varint() throws -> UInt64 {
            var v: UInt64 = 0
            var decalage: UInt64 = 0
            while i < o.count, decalage < 64 {
                let b = o[i]
                i += 1
                v |= UInt64(b & 0x7F) << decalage
                if b & 0x80 == 0 { return v }
                decalage += 7
            }
            throw SourceErreur.format("protobuf tronqué")
        }
        while i < o.count {
            let cle = try varint()
            let numero = Int(truncatingIfNeeded: cle >> 3)
            switch cle & 7 {
            case 0: champs.append((numero, try varint(), nil))
            case 1: i += 8
            case 2:
                guard let n = Int(exactly: try varint()), n <= o.count - i else { throw SourceErreur.format("protobuf tronqué") }
                champs.append((numero, nil, Data(o[i..<i + n])))
                i += n
            case 5: i += 4
            default: throw SourceErreur.format("protobuf : type de champ \(cle & 7) inconnu")
            }
        }
        guard i == o.count else { throw SourceErreur.format("protobuf tronqué") }
    }

    func entier(_ numero: Int) -> UInt64? { champs.first { $0.numero == numero && $0.entier != nil }?.entier }
    func octets(_ numero: Int) -> Data? { champs.first { $0.numero == numero && $0.octets != nil }?.octets }
    func message(_ numero: Int) throws -> Protobuf? { try octets(numero).map(Protobuf.init) }
    func messages(_ numero: Int) throws -> [Protobuf] {
        try champs.filter { $0.numero == numero }.compactMap(\.octets).map(Protobuf.init)
    }
}
