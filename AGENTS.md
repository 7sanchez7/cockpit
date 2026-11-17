# Cockpit, consignes pour les agents

**Règle absolue : chaque modification met à jour le bon fichier de `docs/` dans le même changement.** Une table qui gagne une colonne change [`docs/donnees.md`](docs/donnees.md), une source qui récupère un chiffre de plus change son fichier de [`docs/sources/`](docs/sources/), un écran qui bouge change [`docs/ecrans.md`](docs/ecrans.md).

Cockpit est une app Mac pour suivre ses business, écrite par Tony (seul dev, à l'aise backend et infra) pour Roleo et publiée : chacun clone le dépôt et le branche sur son business par le skill `/installer`. Lire [`README.md`](README.md) pour le quoi, [`docs/README.md`](docs/README.md) pour la carte.

## Quoi lire avant de toucher

| Tâche | Lire d'abord |
|---|---|
| Comprendre le code, savoir où est quoi | [`docs/architecture.md`](docs/architecture.md) |
| Toucher à une table, lire ou écrire un chiffre | [`docs/donnees.md`](docs/donnees.md) |
| Ajouter ou réparer une source | [`docs/collecte.md`](docs/collecte.md), puis [`docs/sources/<source>.md`](docs/sources/) |
| Coder ou changer un écran | [`docs/ecrans.md`](docs/ecrans.md) et [`docs/design.md`](docs/design.md) |
| Lancer, tester, déboguer | [`docs/runbook.md`](docs/runbook.md) |
| Installer le cockpit sur un autre Mac, pour un autre business | skill `/installer` ([`.claude/skills/installer/SKILL.md`](.claude/skills/installer/SKILL.md)), [`docs/runbook.md`](docs/runbook.md) § Installer |
| Ajouter un business (App 2) | [`docs/collecte.md`](docs/collecte.md) § Business et § Graine, puis Réglages, onglet Business |
| Publier une vidéo depuis l'iPhone (plan) | [`docs/publication-iphone.md`](docs/publication-iphone.md) |
| Répondre aux users, traiter les retours | [`docs/ecrans.md`](docs/ecrans.md) § SAV, puis [`docs/sources/firebase.md`](docs/sources/firebase.md) § SAV |
| Suivre l'app d'un pote | écran Apps de potes, champ d'ajout (id ou lien App Store) ; [`docs/sources/classements-itunes.md`](docs/sources/classements-itunes.md) |

## Règles

- **Aucune valeur de secret dans le dépôt, ni dans la base, ni dans un log.** Les clés passent par `Secrets` (Trousseau, sinon Secret Manager). Ne jamais afficher une clé, même tronquée, dans une sortie de commande.
- **Rien de propre à un utilisateur dans le dépôt** : l'équipe de signature est dans `Local.xcconfig`, le business et les comptes dans la graine (`graine.json`), les clés dans le Trousseau. Le code garde des valeurs par défaut, celles de Roleo (`Business.Evenements`).
- **Les écrans ne parlent jamais au réseau.** Ils lisent la base par `Lectures`. Seules les sources (`Cockpit/Sources/`) appellent des API. Exceptions, dans Apps de potes : les icônes (`AsyncImage` sur l'URL d'artwork d'iTunes) et l'ajout d'une app (`Classements.ajouterApp`, un lookup iTunes) ; dans SAV, les trois actions, qui passent par `AppState` (`repondre`, `fermer`, `traiter`) vers `Firebase+SAV`.
- **Une source n'écrit que par `Store`** et seulement dans les tables et métriques documentées dans `docs/donnees.md`.
- **Lecture seule partout, sauf le SAV.** Le cockpit ne modifie rien chez PostHog, RevenueCat, App Store Connect, TikTok ni Firestore. Seule exception, propre à Roleo : l'écran SAV écrit dans le Firestore de Roleo ce qu'écrit son dashboard admin (la réponse de l'équipe et le résumé du fil, un fil fermé sans réponse, un retour traité ou rouvert) et envoie la notif FCM de la réponse. Tout passe par `Cockpit/Sources/Firebase+SAV.swift`, sur un clic de Tony, jamais pendant un passage ([`docs/sources/firebase.md`](docs/sources/firebase.md) § SAV). Une écriture de plus s'ajoute là et dans cette règle.
- **RevenueCat v1 `GET /subscribers/{id}` crée le client s'il n'existe pas** : ne jamais l'appeler. L'API v2 en lecture seulement.
- **Clé PostHog personnelle scopée au projet**, jamais à l'organisation.
- Design : la maquette « Console en verre liquide » est la référence ([`docs/design.md`](docs/design.md)). Fond uni sombre, jamais de halos ni de dégradés de couleur derrière le verre. Couleurs, rayons, tailles : uniquement les jetons de `Cockpit/Design/Theme.swift`.
- Textes de l'UI en français, sans tiret cadratin (une virgule à la place), nombres au format français (`48 200`, `7,10 €`).

## Écrire du code

- Le plus simple qui marche, sans abstraction prématurée, lisible par quelqu'un qui découvre le projet.
- Aucune dépendance externe : SwiftUI, Swift Charts, SQLite3, CryptoKit, CommonCrypto, Security, UserNotifications.
- Pas de code mort, pas de bloc commenté. Commentaires courts, seulement quand la logique n'est pas évidente.
- Une constante définie une fois (`Theme`, `Metrique`, `Jour`), réutilisée partout.
- Une erreur de source n'est jamais avalée : elle remonte au `Collecteur`, qui l'écrit dans la table `collecte` et l'affiche dans Santé.
- **Avant de terminer** : `make test` et `make build` passent, sans avertissement nouveau.

## Git

Dépôt public sous licence MIT, séparé de Roleo : chaque utilisateur clone et tire les mises à jour par `git pull`. Rien de propre à un utilisateur n'y entre (§ Règles), et Tony commite avec son email `noreply` de GitHub. `main` toujours compilable. Commits courts : `feat: …`, `fix: …`, `docs: …`, sans ligne `Co-Authored-By` (elle fait apparaître Claude parmi les contributeurs du dépôt).
