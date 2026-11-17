# Cockpit

Une app Mac pour suivre ses business au même endroit, écrite pour Roleo et branchable sur n'importe quelle app mobile. Elle remplace l'ouverture de PostHog, RevenueCat, App Store Connect, TikTok Studio et du dashboard Firebase : on ouvre le cockpit, on voit tout, on sait quoi faire.

## Ce qu'elle montre

| Écran | La question à laquelle il répond |
|---|---|
| App | Comment va l'app aujourd'hui, sur 7, 30 ou 90 jours, comparée à la période d'avant ? |
| Data | Combien on gagne, qui convertit en essai puis en payant, qui revient, découpé jusqu'au segment (âge, source, écran du tunnel…) ? |
| Vidéos | Quelle vidéo TikTok marche, laquelle passe le seuil de partages et d'enregistrements ? |
| Santé | Les sources répondent-elles, l'IA tient-elle (replis, 429, latence), combien coûte la journée ? |
| SAV | Le dashboard admin de Roleo dans le cockpit : les fils avec les users, la réponse qui part avec une notif, les retours (idées, soucis, signalements) à traiter ; dessous, les avis sans réponse, les verdicts de vidéos et les tâches à la main. |
| Apps de potes | Où sont nos apps et celles des potes dans le top 200 de l'App Store, pays par pays ? |

Plus une icône dans la barre des menus (MRR, actifs, à traiter) et des notifications macOS (achat, avis, vidéo qui décolle, rang qui bouge, source en panne).

## Comment elle marche

Une app SwiftUI native (macOS 26, verre liquide), sans serveur. Un collecteur interroge chaque source à sa cadence (15 min à 3 h), écrit dans une base SQLite locale, et les écrans ne lisent que cette base : l'app s'ouvre instantanément, garde l'historique et marche hors ligne. Les clés viennent du Trousseau macOS, sinon de Secret Manager, avec les identifiants par défaut de Google (ADC) : aucune valeur sur le disque ni dans le dépôt.

```bash
make run     # génère le projet Xcode, compile, lance
make test    # tests unitaires
```

## L'installer chez soi

Il faut un Mac sous macOS 26 avec Xcode 26, un identifiant Apple (un compte gratuit suffit) et Claude Code. Puis :

```bash
git clone https://github.com/7sanchez7/cockpit && cd cockpit && claude "/installer"
```

L'agent vérifie le Mac, écrit `Local.xcconfig` (l'équipe qui signe l'app), demande le business et les comptes, écrit la graine, lance l'app et guide pour les clés. Les clés ne passent jamais par le chat : on les colle soi-même dans Réglages, onglet Clés. Le détail est dans [`docs/runbook.md`](docs/runbook.md) § Installer. Les mises à jour : `git pull`, sans conflit avec ses réglages, qui ne sont jamais dans le dépôt.

## Où lire la suite

Tout est dans [`docs/`](docs/README.md). Un agent commence par [`AGENTS.md`](AGENTS.md).

## Licence

MIT, voir [`LICENSE`](LICENSE).
