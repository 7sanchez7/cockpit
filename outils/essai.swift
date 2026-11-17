// Gabarit de `make essai SOURCE=X` : SOURCE() est remplacé par la source à essayer.
// Lance une collecte contre les vraies API sur .cache/essai.sqlite, puis affiche ce qu'elle a écrit.
import Foundation

let store = try Store(chemin: FileManager.default.currentDirectoryPath + "/.cache/essai.sqlite", graine: Store.graine)
let http = HTTP()
let gcloud = GCloud(http: http)
let ctx = Contexte(store: store, secrets: Secrets(gcloud: gcloud, http: http), http: http, gcloud: gcloud,
                   businesses: try store.businesses())
let source = SOURCE()
let debut = Date.now

do {
    let n = try await source.collecte(ctx)
    print("\(source.nom) : \(n) lignes en \(String(format: "%.1f", Date.now.timeIntervalSince(debut))) s\n")
} catch {
    print("\(source.nom) a échoué : \(error.localizedDescription)")
    exit(1)
}

func montrer(_ titre: String, _ sql: String, _ args: [Any?] = []) throws {
    let lignes = try store.db.query(sql, args)
    guard !lignes.isEmpty else { return }
    print("— \(titre) (\(lignes.count))")
    for l in lignes {
        print("  " + l.colonnes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "  "))
    }
    print()
}

let depuis = debut.iso
try montrer("serie", "select business, metrique, jour, heure, valeur from serie where maj >= ? order by metrique, jour desc, heure limit 60", [depuis])
try montrer("fil", "select at, type, texte from fil where id like ? order by at desc limit 15", [source.id + ":%"])
try montrer("a_traiter", "select id, texte, etiquette, ton, fait_le from a_traiter where source = ? order by cree_le desc limit 15", [source.id])
for table in ["video", "video_releve", "app", "rang", "avis", "install", "paiement", "porte", "sav_fil", "sav_message", "sav_retour", "sav_compte"] {
    let n = try store.db.query("select count(*) as n from \(table)").first?.entier("n") ?? 0
    if n > 0 { print("\(table) : \(n) lignes au total") }
}
