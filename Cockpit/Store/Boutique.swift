/// Les stores où une app est en vente, identifiants de RevenueCat. Une métrique par store s'écrit
/// `<métrique>.<boutique>` (`installs.play_store`) ; le total garde le nom nu (`installs`).
nonisolated enum Boutique: String, CaseIterable, Sendable {
    case appStore = "app_store"
    case playStore = "play_store"

    var nom: String { self == .appStore ? "App Store" : "Play Store" }

    func metrique(_ base: String) -> String { "\(base).\(rawValue)" }

    /// Écrit les téléchargements du jour pour ce store, puis le total, somme des deux stores.
    @MainActor func telechargements(_ business: String, jour: String, _ n: Double, _ store: Store) throws {
        try store.serie(business, metrique(Metrique.telechargements), jour: jour, n)
        try store.somme(business, Metrique.telechargements, de: Self.allCases.map { $0.metrique(Metrique.telechargements) }, jour: jour)
    }

    /// Les métriques écrites aussi store par store (PostHog, RevenueCat) ; les autres n'ont que le total.
    static let separees: Set<String> = [
        Metrique.actifs, Metrique.actifsJ7, Metrique.actifsHeure, Metrique.installs, Metrique.installsJ7,
        Metrique.essais, Metrique.essaisJ7, Metrique.ronds, Metrique.rondsJ7,
        Metrique.achats, Metrique.mrrBrut, Metrique.mrrNet, Metrique.abonnes, Metrique.essaisActifs,
        Metrique.revenu28j, Metrique.revenu, Metrique.nouveauxClients, Metrique.telechargements,
    ]
}
