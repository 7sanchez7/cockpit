# PostHog

Fichiers : `Cockpit/Sources/PostHog.swift` (requêtes, passage) et `PostHog+Decodage.swift` (décodage, écriture). Cadence : 15 min. Clés : `POSTHOG_PERSONAL_API_KEY` et `POSTHOG_PROJECT_ID` (clé personnelle limitée au projet, lecture seule). Hôte : `config.posthogHost` du business. Tests : `CockpitTests/PostHogTests.swift`.

Actifs, installs, essais, ronds finis, actifs par heure, fil des essais, détail de chaque install (tunnel, réponses, conversion, retour) et portes du paywall, lus en HogQL. Les définitions sont celles de `docs/donnees.md` et de `tools/suivi/hebdo.py` côté Roleo. Branchée le 13 nov. 2026.

Les noms d'événements de cette fiche sont ceux de Roleo, les valeurs par défaut de `Business.Evenements`. Un autre business donne les siens dans `config.evenements` de sa graine ([`../collecte.md`](../collecte.md) § Graine) :

| Champ | Roleo | Rôle |
|---|---|---|
| `installation` | `onboarding_started` | le premier fait l'install |
| `etape` | `onboarding_step_completed` | étape du tunnel franchie, propriété `step` |
| `paywall` | `paywall_viewed` | paywall vu, propriété `source` |
| `essai` | `trial_started` | essai pris, propriété `product` |
| `achat` | `purchase_completed` | achat tenté, propriété `product` |
| `usage` | `path_round_done` | l'usage qui compte (le rond fini), base des retours JN |

Restent propres à Roleo : la liste des écrans du tunnel (`PostHog.ecrans`, où `paywall_viewed` sert de clé quel que soit le nom de l'événement `paywall`), les propriétés de réponse des dimensions et `PostHog.rondsDepuis`.

## L'appel

```
POST {posthogHost}/api/projects/{POSTHOG_PROJECT_ID}/query/
Authorization: Bearer {POSTHOG_PERSONAL_API_KEY}
{"query": {"kind": "HogQLQuery", "query": "select …"}}
```

Réponse : `results` (lignes, colonnes dans l'ordre du select, nombres en NSNumber, `null` en NSNull), `hasMore`, `limit`, `columns`, `types`. **HogQL coupe à 100 lignes par défaut** : chaque requête porte sa `limit`, et une réponse avec `hasMore = true` fait échouer le passage (`.format`, « HogQL coupé par sa limit ») plutôt que d'écrire un chiffre tronqué. Une réponse sans `results` aussi.

Le projet PostHog est en UTC : tout découpage en jour ou en heure passe par `toTimeZone(timestamp, 'Europe/Paris')`. Les bornes sont envoyées en secondes Unix (`fromUnixTimestamp`), calculées côté Mac avec `Jour` (minuit à Paris).

## Définitions

- **Bruit** : `$identify`, `$set`, `$feature_flag_called`, `$opt_in`, `$screen_view_exit`, envoyés sans que l'user ouvre l'app. Exclus des actifs (même liste que `hebdo.py`).
- **Actif** : personne distincte avec au moins un événement hors bruit dans le jour de Paris.
- **Install** : premier `onboarding_started` d'une personne, dont l'`$os` de ce premier événement est `iOS`, `iPadOS` ou `Android` dans les séries ; le détail par install (`install`, `porte`) reste iOS et iPadOS seulement.
- **Store** : l'`$os` de l'événement (`PostHog.filtre`). `iOS` et `iPadOS` : App Store ; `Android` : Play Store. Un actif qui passe d'un OS à l'autre le même jour compte dans les deux stores, une fois au total.
- **Essai** : un événement `trial_started`.
- **Achat direct** : un `purchase_completed` sans `trial_started` chez la même personne. `purchase_completed` part aussi au début d'un essai gratuit. C'est une tentative : sur 97 jours au 13 nov. 2026, 22 des 78 n'ont jamais été encaissés (carte refusée, abonnement expiré ou en relance de facturation à 0 $). Le payé vient de RevenueCat (`paiement`).
- **Rond fini** : un événement `path_round_done`. Fiable seulement pour les installs depuis le 15 oct. 2026 (`PostHog.rondsDepuis`) : la 2.0.0 ne l'envoyait pas toujours. Rond fini, retours JN et cohortes de l'écran Data ne comptent que ces installs.
- **`_j7`** : le même compte 7 jours plus tôt, coupé à la même heure (`maintenant` moins 7 jours calendaires, heure d'été comprise). Aujourd'hui à 14 h 30 se compare au même jour de la semaine passée à 14 h 30 ; un jour fini se compare à un jour fini.
- **Retour JN** (N = 1, 7, 14, 30) : un `path_round_done` entre `install + N jours` et `install + N + 1 jours`, à la seconde près.

## Les requêtes

| Requête | Ce qu'elle rend | Fenêtre | `limit` |
|---|---|---|---|
| `requeteJours` | jour, puis pour chaque segment (total, App Store, Play Store) : actifs, essais, ronds finis, chacun en entier puis avant la coupe | les jours écrits, plus les 7 jours d'avant (pour `_j7`) | 100 |
| `requeteInstalls` | jour, puis pour chaque segment : installs, installs avant la coupe | idem | 100 |
| `requeteHeures` | jour, heure, actifs de chaque segment | les jours d'`actifs_h` | 1000 |
| `requeteEssais` | uuid, instant Unix, `product`, `source`, `$geoip_country_code` | 48 h glissantes | 200 |
| `requeteParInstall` | une ligne par install : jour, écran le plus loin, paywall vu, essai, achat direct, rond fini, retours J1 à J30, id client, une colonne par dimension | installs des 97 derniers jours de Paris (`joursInstalls`) | 50 000 |
| `requetePortes` | jour, porte (`source`), paywalls vus, essais, achats directs | 97 derniers jours de Paris | 10 000 |

Les colonnes « avant la coupe » ne servent qu'aux jours d'il y a 7 jours et plus : le `_j7` du jour J est la colonne coupée du jour J−7.

`requeteParInstall` part de la sous-requête `installes(depuis:)` (personnes dont le premier `onboarding_started` est après la borne, iOS ou iPadOS) et lit, pour chacune, ses six événements utiles (`onboarding_started`, `onboarding_step_completed`, `paywall_viewed`, `trial_started`, `purchase_completed`, `path_round_done`). L'écran le plus loin est le rang maximal, dans la liste `PostHog.ecrans`, parmi ses `onboarding_step_completed` (propriété `step`) et `paywall_viewed`, 0 s'il n'en a aucun. Une étape compte ceux qui l'ont atteinte **ou dépassée**, comme `hebdo.py` : un écran sauté (Prénom, Âge selon la version) ne casse pas la courbe. L'id client est le `distinct_id` du dernier `trial_started` ou `purchase_completed`, rempli seulement s'il a converti : c'est l'`app_user_id` RevenueCat (l'uid Firebase), lu ensuite par la source RevenueCat.

Les dimensions (`Dimension`, `Store/Dimension.swift`), texte vide quand l'install n'a pas répondu. Une question posée après le début des 97 jours a sa date (`mesureeDepuis`) : les installs d'avant sont « Pas mesuré », pas « Sans réponse ».

| Dimension | D'où elle vient |
|---|---|
| Écran le plus loin (`loin`) | le rang calculé ci-dessus |
| Langue apprise (`langue`) | `language` de l'étape `language` |
| Langue maternelle (`maternelle`) | `native_language` de l'étape `native_language`, depuis le 13 oct. 2026 |
| Connu comment (`source`) | `source` de l'étape `acquisition_source` |
| Âge (`age`) | `age_range` de l'étape `age`, depuis le 24 oct. 2026 |
| Motivation (`motivation`) | `motivation` de l'étape `motivation`, depuis le 16 sept. 2026 |
| Ce qui bloque (`blocage`) | `pains` de l'étape `pain` (plusieurs, séparés par des virgules), sinon l'ancien `pain` |
| Centres d'intérêt (`interet`) | `interests` de l'étape `interests` (plusieurs), depuis le 13 oct. 2026 |
| Niveau (`niveau`) | `start_level` des étapes `level` ou `projection`, depuis le 13 oct. 2026 |
| Tuteur (`tuteur`) | `character` de l'étape `persona`, depuis le 2 sept. 2026 |
| Notifications (`notifs`) | `notifs` de l'étape `reminder`, depuis le 9 nov. 2026 |
| Compte (`compte`) | `method` de l'étape `account_link` |
| Pays (`pays`) | `$geoip_country_code` du premier `onboarding_started` |
| Version (`version`) | `$app_version` du premier `onboarding_started` |
| Build (`build`) | `$app_build` du premier `onboarding_started` : le numéro du build, plus fin que la version (2.0.2 a eu les builds 42 et 43) |
| Offre prise (`produit`) | `product` du premier `trial_started` ou `purchase_completed` |
| Zone (`zone`) | déduite du pays : continent de `Locale.Region` (Amérique du Nord et latine séparées), l'outre-mer français à part |

Une réponse d'étape est la dernière donnée (`argMaxIf`) : un install revenu en arrière garde sa réponse finale.

`requetePortes` compte par jour et par `source` (le `PaywallSource` de l'app, `onboarding` pour la fin du tunnel, vide pour les versions qui ne l'envoyaient pas) les `paywall_viewed`, les `trial_started` et les achats directs, `purchase_completed` moins `trial_started`, jamais négatif.

Les 17 écrans, dans l'ordre : `welcome` Accueil, `language` Langue apprise, `native_language` Langue maternelle, `acquisition_source` Connu comment, `first_name` Prénom, `age` Âge, `motivation` Motivation, `pain` Ce qui bloque, `interests` Centres d'intérêt, `level` Niveau, `social_proof` Preuve sociale, `app_tour` Présentation, `projection` Projection, `account_setup` Compte, `persona` Choix du tuteur, `paywall_viewed` Paywall vu, `paywall` Essai touché (l'étape `paywall` validée = bouton d'essai touché, pas l'essai confirmé par Apple). Un écran ajouté au tunnel de l'app s'ajoute à `PostHog.ecrans`.

## Ce que la source fait

Un passage par business qui a un `posthogHost`, l'un après l'autre. Aucun : `nonConfigure`. Une erreur porte le nom du business (« Roleo : HTTP 401 … »).

1. **Historique ou pas** : si la série `actifs` d'hier ou de J-90 manque (premier passage, trou de plus d'un jour, ou historique plus court que la période la plus longue de l'en-tête), le passage lit 91 jours de séries, aujourd'hui compris (`PostHog.joursHistorique`) et 9 jours d'`actifs_h` (aujourd'hui et les 8 d'avant). Sinon, aujourd'hui et hier seulement.
2. Les quatre requêtes de chaque passage, à la suite : jours, installs, heures, essais.
3. **Installs et portes au plus une fois par heure** : le réglage `posthog.horaire.<business>` garde l'instant ISO du dernier calcul. S'il manque ou a une heure ou plus, `requeteParInstall` et `requetePortes` partent.
4. Tout s'écrit dans un seul `lot`, après les appels réseau : un passage qui échoue n'écrit rien. Le réglage est posé dans le même `lot`.

La source rend le nombre de lignes écrites : séries et heures (upserts, toujours comptées), lignes du fil nouvelles seulement, installs et portes.

## Ce qui est écrit

**`serie`**, `heure = -1`, pour chaque jour lu : `actifs`, `actifs_j7`, `installs`, `installs_j7`, `essais`, `essais_j7`, `ronds`, `ronds_j7`, chacune au total puis suffixée par store (`actifs.app_store`, `actifs.play_store`). Un jour sans ligne HogQL vaut 0, jamais un trou, sauf `ronds` avant le 15 oct. 2026 et `ronds_j7` dont le jour d'il y a 7 jours est avant : pas écrits, la mesure n'existait pas (`PostHog.rondsDepuis`). Le jour en cours se réécrit à chaque passage.

**`serie(actifs_h)`**, `heure` 0 à 23, au total et par store : les heures passées des jours lus, jusqu'à l'heure en cours pour aujourd'hui (l'heure en cours est partielle). Les heures sans ligne valent 0.

**`install`** : une ligne par install des 97 derniers jours de Paris, réponses en JSON dans `valeurs`. Les jours à partir du début de la fenêtre sont effacés puis réécrits à chaque calcul : un install qui convertit ou revient change sa ligne, et la limite de 50 000 n'est jamais atteinte par accumulation. Un retour JN est écrit tel que PostHog le voit ; c'est la lecture (`completJusqua`) qui ne le compte que pour les jours d'install qui ont eu tout leur temps.

**`porte`** : une ligne par jour et par porte, même fenêtre, même remplacement.

**Le fil `ESSAI`**, un par `trial_started` des 48 dernières heures :

| Champ | Valeur |
|---|---|
| `id` | `posthog:essai:<uuid de l'événement>` |
| `at` | l'instant de l'événement |
| `texte` | `Essai annuel, Espagne, rond verrouillé` |

L'offre vient de `product` (contient `year` ou `annual` : annuel, `quarter` : trimestriel, `month` : mensuel, `week` : hebdo, sinon « Essai » seul). Le pays vient de `$geoip_country_code`, nommé en français. La porte (`source`, le `PaywallSource` de l'app) n'est ajoutée que si l'essai ne vient pas du tunnel (`onboarding`), traduite par `PostHog.portes`, brute si inconnue. Une ligne déjà dans le fil n'est pas réécrite.

Pas de fil pour les installs ni pour `purchase_completed` : rien ne les définit dans `docs/donnees.md`. Les achats viennent de RevenueCat, PostHog en rate environ un sur cinq.

## Coût

Par passage de 15 min : 4 requêtes HogQL à la suite, 6 quand les installs et les portes sont dus (une fois par heure), soit 18 requêtes par heure et par business. PostHog limite le débit et la concurrence des requêtes `/query/` par projet (chiffres non vérifiés ici) : un outil Roleo qui interroge en même temps partage ce budget.

Mesuré le 13 nov. 2026 vers 1 h : passage historique, 6 requêtes, 442 lignes en 10,8 s ; passage normal, 4 requêtes, 38 lignes en 6,8 s. Vers 14 h, passage horaire : 6 682 lignes (environ 6 200 installs, 414 portes) en 7 s.

## Relevé du 13 nov. 2026

| Jour (Paris) | Actifs | `actifs_j7` | Installs | `installs_j7` | Essais | `essais_j7` |
|---|---|---|---|---|---|---|
| 13 nov. (1 h) | 20 | 18 | 3 | 4 | 0 | 0 |
| 12 nov. | 490 | 378 | 146 | 154 | 6 | 8 |
| 11 nov. | 520 | 405 | 191 | 187 | 10 | 11 |

Pic horaire du 12 : 77 actifs à 20 h. Fil : une quinzaine d'essais sur 48 h. Tunnel 7 jours : 951 installs, 916 à l'Accueil, 875 à la Preuve sociale, 862 au paywall, 361 essais touchés.

Comparé aux outils Roleo :

- J1 des cohortes du 26 oct. au 7 nov. : 15,2 %, contre 15,3 % dans `hebdo.py`.
- Installs de novembre : 1 679 (iOS et iPadOS, jours de Paris), contre 1 681 dans `tools/bilan.py`, qui compte tous les OS sur le mois UTC (dont 14 Android).
- `requeteParInstall` sur 97 jours, l'après-midi : 7 302 installs, 289 essais, 78 achats directs, 367 clients à lire chez RevenueCat.

## Ce qui peut casser

- **Un événement ou une propriété renommés dans l'app** : `onboarding_started`, `trial_started`, `purchase_completed`, `path_round_done`, `onboarding_step_completed` et sa propriété `step`, `paywall_viewed`, `product`, `source`, `$geoip_country_code`, `$os`, `$app_version`, `$app_build`, et chaque propriété de réponse du tableau des dimensions. Rien ne casse : les chiffres tombent à 0, ou une dimension passe à « Sans réponse », sans erreur. Une chute à 0 d'une série, ou une dimension soudain vide dans l'arbre de Data, est le signe à surveiller.
- **Une requête qui dépasse sa `limit`** : le passage échoue avec « HogQL coupé par sa limit ». Plus de 100 jours lus, plus de 200 essais en 48 h, plus de 50 000 installs en 97 jours (environ 515 par jour) ou plus de 10 000 lignes de portes, à relever le jour venu.
- **La clé** : révoquée ou sans le scope du projet, HTTP 401 ou 403, le passage échoue avec le nom du business.
- **Limite de débit ou panne PostHog** (429, 5xx) : `HTTP` rejoue, puis erreur.
- Les vieilles lignes d'`actifs_h` ne sont jamais purgées (le `Store` n'a pas de suppression) : une ligne par heure et par jour, négligeable.
- L'install Android est exclue : à revoir quand l'app sortira sur le Play Store.
