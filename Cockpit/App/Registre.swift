/// Les sources du collecteur, dans l'ordre de la bande des sources de la barre du haut.
enum Registre {
    static let sources: [any Source] = [
        PostHog(), RevenueCat(), AppStoreConnect(), PlayConsole(), TikTok(), Instagram(), YouTube(), Facebook(), Contenu(), Firebase(),
        Classements(), Notes(),
    ]
}
