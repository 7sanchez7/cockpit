# Architecture

Une app SwiftUI pour macOS 26, sans serveur ni dépendance externe. Trois couches qui ne se parlent que par la base SQLite :

```
services (PostHog, RevenueCat, ASC, TikTok, Instagram, YouTube, Facebook, Firestore, iTunes, fiches de contenu)
   │  Sources/      une struct par service, appelée par le Collecteur
   ▼
Store            cockpit.sqlite : écritures typées (serie, fil, video, rang, tache…)
   │  Lecture/      requêtes pour les écrans, aucune écriture sauf les tâches cochées
   ▼
Ecrans/ + Composants/   SwiftUI, ne touchent jamais le réseau
```

Une seule voie remonte vers un service : les trois actions de l'écran SAV (répondre à un user, fermer un fil, traiter un retour). L'écran appelle `AppState.repondre`, `fermer` ou `traiter`, qui passent le `Contexte` du collecteur à `Firebase+SAV` : l'écriture part dans Firestore (et la notif par FCM), puis dans le Store, et `aChange()` fait relire l'écran. Voir [sources/firebase.md](sources/firebase.md) § SAV.

L'app s'ouvre sur ce qui est déjà en base, le collecteur rafraîchit en arrière-plan, et `Store.aChange()` fait relire les écrans après chaque passage.

## Où est quoi

| Dossier | Contenu |
|---|---|
| `Cockpit/App/` | `CockpitApp` (scènes : fenêtre, barre de menus, Réglages ; menu Aller ⌘1-7, ⌘K, ⌘R), `AppState` (écran, business choisi, palette, horloge de 30 s), `Registre` (la liste des sources), `PontWidget` (écrit le résumé du widget, voir plus bas). |
| `Cockpit/Store/` | `Database` (SQLite3 brut), `Schema` (tables, sans migrations), `Store` (écritures et réglages), `Business` (config d'un business, ses événements PostHog, format de la graine), `Metrique` (catalogue fermé des métriques), `Dimension` (les réponses du tunnel qui découpent les installs), `Jour` (jours et heures de Paris), `Modeles`. |
| `Cockpit/Collecte/` | `Collecteur` (boucle de 60 s, échéances, journal, notifications), `Source` (le protocole et `Contexte`), `HTTP`, `GCloud` (jeton Google par l'ADC), `Secrets` (env, Trousseau, Secret Manager), `Commande` (programmes locaux), `Safari` (cookies de Safari), `YtDlp` (listes TikTok et YouTube), `Miniatures` (cache disque des images de vidéos), `Notifs`. |
| `Cockpit/Sources/` | Une source par fichier, ses aides en `<Source>+Quoi.swift`. Fiches dans [`sources/`](sources/README.md). |
| `Cockpit/Lecture/` | `Lectures` (fil, vidéos, comptes, tâches, apps, séries, rangs) et ses extensions par écran (`Lectures+Argent`, `Lectures+Data`, `Lectures+Videos`, `Lectures+Widget`…), `ResumeWidget` (ce que lit le widget), `Fenetre` (période choisie et période d'avant), `Decoupage` (libellés des dimensions et des filtres de l'arbre), `Format` (nombres, dates et durées en français). |
| `Cockpit/Design/` | `Theme` (jetons), `Verre` (le modificateur `.verre`, `Pastille`, `Point`, `Panneau`, `Vide`), `Marque` (le logo rond), `Ton` (la couleur d'un écart), `Mouvement` (`Chiffre`, transitions, entrées, appui, Reduce Motion). |
| `Cockpit/Composants/` | Ce que plusieurs écrans partagent : `Page`, `Bloc`, `Rangee`, `EnTete`, `Segmente`, `BarreHaut`, `CarteKPI`, `Graphiques`, `Fil`, `ListeTaches`, `TableVideos`, `Miniature`, `Palette`, `BarreMenus`. |
| `Cockpit/Ecrans/` | Un fichier par écran, plus `Reglages`. Décrits dans [`ecrans.md`](ecrans.md). |
| `CockpitWidget/` | Le widget du bureau : `CockpitWidget` (bundle, configuration, fournisseur de timeline), `VuesWidget` (les trois tailles, sans WidgetKit). |
| `CockpitTests/` | Tests du cœur : décodage de chaque source sur des réponses figées, `Store`, `Lectures`. |
| `outils/essai.swift` | Le gabarit de `make essai SOURCE=…`. |

## Trois cibles de compilation

- **L'app** : `project.yml` (XcodeGen) génère `Cockpit.xcodeproj`, ignoré par git. L'équipe de signature vient de `Local.xcconfig` (non versionné, branché par `configFiles`), propre à chaque Mac. Isolation par défaut sur le main actor, concurrence stricte. Pas de sandbox.
- **Le widget** : l'extension `CockpitWidget` (`com.tonysanchez.cockpit.widget`, sandboxée), embarquée dans l'app. Elle compile `CockpitWidget/` et cinq fichiers partagés : `Theme`, `Verre`, `Marque`, `Ton` et `Lecture/ResumeWidget.swift`. Ni `Format` ni le store : tout lui arrive formaté.
- **Les tests** : `Package.swift` compile `CockpitNoyau`, le dossier `Cockpit/` sans `App`, `Design`, `Ecrans` ni `Composants`. Donc rien du cœur (`Store`, `Collecte`, `Sources`, `Lecture`) ne dépend de SwiftUI ni de `Theme`.

## Un chiffre, de bout en bout

Les actifs du jour : `PostHog.collecte` lance une requête HogQL toutes les 15 min, écrit `Store.serie(business, Metrique.actifs, jour, -1, valeur)`, le collecteur journalise le passage dans `collecte` et appelle `aChange()`. L'Accueil lit `Lectures.valeur(Metrique.actifs, jour:)` et `Lectures.jours(…)` pour la courbe. Rien d'autre ne connaît PostHog.

## Le widget du bureau

Une extension ne lit pas la base de l'app. À chaque tick de l'horloge (30 s), `AppState.publierWidget` calcule `Lectures.resumeWidget()` sur tous les business et le passe à `PontWidget`, qui l'écrit en JSON (`widget.json`, clés triées) dans le conteneur du groupe `<équipe>.com.tonysanchez.cockpit`, seulement s'il a changé. Le groupe est préfixé par l'équipe qui signe (`$(DEVELOPMENT_TEAM)` dans les deux fichiers d'entitlements) : pas de profil de provisionnement à créer. Le code ne l'écrit nulle part : `ResumeWidget.groupe` le lit dans les entitlements du processus (`SecTaskCopyValueForEntitlement`), le même côté app et côté widget. `WidgetCenter.reloadAllTimelines()` part au plus toutes les 15 min (le budget de rechargement de WidgetKit) ; un changement écrit entre-temps attend le tick suivant. Côté widget, le fournisseur relit le fichier à chaque rechargement, timeline `.never` : c'est l'app qui décide quand. Sans fichier, le widget invite à ouvrir Cockpit. L'app fermée, le widget garde ses derniers chiffres, l'heure de mise à jour le dit.

## Réglages persistants

Table `reglage`, lue par `Store.reglage` et écrite par `Store.regler` (nil efface) :

| Clé | Effet |
|---|---|
| `ecran`, `business` | dernier écran et business affichés |
| `collecte.pause` | `1` suspend la collecte (`Collecteur.reglagePause`, `AppState.enPause`) |
| `notifs.<type>` | `0` coupe les notifications de ce type du fil (`TypeFil.reglageNotif`) |
| `graine` | date de modification de la graine déjà appliquée ([`collecte.md`](collecte.md) § Graine) |
