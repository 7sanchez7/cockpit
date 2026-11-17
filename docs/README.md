# La carte des docs

Chaque fichier répond à une question. Un agent lit [`../AGENTS.md`](../AGENTS.md) d'abord, puis le fichier de sa tâche.

| Fichier | Répond à |
|---|---|
| [`architecture.md`](architecture.md) | Où est quoi dans le code, comment une donnée va du service à l'écran. |
| [`donnees.md`](donnees.md) | Chaque table et chaque métrique de la base : colonnes, unités, qui écrit, qui lit. |
| [`collecte.md`](collecte.md) | Le collecteur, les cadences, les secrets, les notifications, le contrat d'une source, ajouter un business, la graine (`graine.json`). |
| [`sources/`](sources/README.md) | Une fiche par service : requêtes exactes, ce qui est écrit, ce qui peut casser. Dont [`classements-itunes.md`](sources/classements-itunes.md), le top 200 App Store par iTunes. |
| [`ecrans.md`](ecrans.md) | Chaque écran : la question à laquelle il répond, ses blocs, les lectures qu'il fait. Plus la palette ⌘K, la barre de menus, le widget du bureau et les Réglages. |
| [`design.md`](design.md) | La maquette de référence, les jetons de `Theme`, les composants partagés. |
| [`runbook.md`](runbook.md) | Installer sur un autre Mac (`Local.xcconfig`, graine, `/installer`), lancer, tester, essayer une source, déboguer, réparer l'environnement (gcloud, yt-dlp, ADC). |
| [`publication-iphone.md`](publication-iphone.md) | Publier une vidéo sur TikTok, Instagram, YouTube et Facebook depuis l'iPhone, par les apps officielles et iCTRL. Plan, pas encore codé. |
