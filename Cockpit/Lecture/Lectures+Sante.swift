import Foundation

/// Les lectures propres à l'écran Santé.
extension Lectures {
    /// La fin du dernier passage réussi de chaque source ; une source jamais réussie est absente.
    func derniersSucces() -> [String: Date] {
        Dictionary(q("select source, max(fin) as fin from collecte where etat = 'ok' group by source")
            .compactMap { l in l.texte("source").flatMap { s in l.date("fin").map { (s, $0) } } },
                   uniquingKeysWith: { a, _ in a })
    }
}
