/// Le catalogue fermé des métriques de la table `serie`, décrit dans docs/donnees.md.
/// Une métrique nouvelle s'ajoute ici et dans la doc, jamais en chaîne écrite ailleurs.
nonisolated enum Metrique {
    // PostHog
    static let actifs = "actifs"
    static let actifsJ7 = "actifs_j7"
    static let actifsHeure = "actifs_h"
    static let installs = "installs"
    static let installsJ7 = "installs_j7"
    static let essais = "essais"
    static let essaisJ7 = "essais_j7"
    static let ronds = "ronds"
    static let rondsJ7 = "ronds_j7"
    // RevenueCat
    static let achats = "achats"
    static let mrrBrut = "mrr_brut"
    static let mrrNet = "mrr_net"
    static let abonnes = "abonnes"
    static let essaisActifs = "essais_actifs"
    static let revenu28j = "revenu_28j"
    /// Revenu brut du jour en dollars, aujourd'hui compris (encore partiel).
    static let revenu = "revenu"
    /// Clients vus pour la première fois par RevenueCat ce jour-là (premier lancement avec le SDK), aujourd'hui compris.
    static let nouveauxClients = "nouveaux_clients"
    // App Store Connect et Play Console
    /// Premiers téléchargements comptés par le store, que l'app ait été ouverte ou non ; le total est la somme des
    /// deux stores (`telechargements.app_store`, `telechargements.play_store`).
    static let telechargements = "telechargements"
    // Firebase et Voix
    /// Texte plus voix, en euros.
    static let coutIA = "cout_ia"
    static let coutTexte = "cout_texte"
    static let coutVoix = "cout_voix"
    static let tokensIA = "tokens_ia"
    static let echecsIA = "echecs_ia"
    static let messagesOuverts = "messages_ouverts"
    static let retoursNouveaux = "retours_nouveaux"
    static func requetesIA(_ fournisseur: String) -> String { "req_ia.\(fournisseur)" }
    static func q429IA(_ fournisseur: String) -> String { "q429_ia.\(fournisseur)" }
    static func erreursIA(_ fournisseur: String) -> String { "err_ia.\(fournisseur)" }
    static func latenceIA(_ fournisseur: String) -> String { "ms_ia.\(fournisseur)" }
    // TikTok
    static let vuesTikTok = "vues_tiktok"
    static let vuesTikTokJ7 = "vues_tiktok_j7"
    // Classements
    static let note = "note"
    static let nbNotes = "nb_notes"

    /// Part du MRR brut RevenueCat qui reste après TVA et commission Apple.
    static let partNette = 0.72
    /// Taux fixe de Roleo (`usdToEUR`), pas le cours du jour.
    static let eurParUSD = 0.92

    /// Un montant RevenueCat en dollars, en euros au taux fixe, toujours brut.
    static func enEuros(_ usd: Double) -> Double { usd * eurParUSD }
}
