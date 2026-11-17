# RevenueCat

Fichier : `Cockpit/Sources/RevenueCat.swift`. Cadence : 30 min. Clé : `REVENUECAT_SECRET_KEY_V2` (Secret Manager `roleo-73820`). Tests : `CockpitTests/RevenueCatTests.swift`.

L'argent de Roleo : MRR, abonnés, essais en cours, revenu, achats du jour, fil des achats, et le paiement des installs que PostHog a vus convertir. Uniquement l'API v2 (`https://api.revenuecat.com/v2`, `Authorization: Bearer <clé>`), en lecture. Testé et branché le 13 nov. 2026.

**Jamais l'API v1 `GET /subscribers/{id}`** : elle crée le client qu'elle ne trouve pas. En v2, `GET …/customers/{id}/subscriptions` rend 404 sans rien créer.

Un business est lu si la clé se trouve (variable d'environnement, Trousseau, puis Secret Manager de son `firebaseProject` s'il en a un) ; sans clé, il est sauté. Le fil `ACHAT` demande en plus un `firebaseProject` (il part du Firestore de Roleo) ; sans lui, séries et paiements sont écrits, pas le fil. Aucun business lu : `nonConfigure`.

## Le projet : `GET /projects`

```
GET /v2/projects
→ {"items":[{"id":"projf3216d5f","name":"Roleo",…}]}
```

On prend le projet qui porte le nom du business, sinon le seul de la liste. Plusieurs projets sans nom correspondant : erreur `.format`.

## Aujourd'hui : `GET /projects/{id}/metrics/overview`

```
GET /v2/projects/{projet}/metrics/overview
→ {"currency":"USD","metrics":[{"id":"mrr","value":947,…},{"id":"active_subscriptions","value":100},…]}
```

| `id` | Métrique | Remarque |
|---|---|---|
| `mrr` | `mrr_brut`, et `mrr_net` = brut × 0,72 (`Metrique.partNette`) | en dollars, TVA et commission Apple comprises, arrondi au dollar ; les écrans montrent le brut en euros, `mrr_net` n'est pas affiché |
| `active_subscriptions` | `abonnes` | |
| `active_trials` | `essais_actifs` | |
| `revenue` (`period` `P28D`) | `revenu_28j` (aujourd'hui) | dollars bruts sur 28 jours glissants |

`new_customers` et `active_users` sont ignorés. Un des quatre `id` absent : erreur `.format`.

## L'historique : `GET /projects/{id}/charts/{nom}`

```
GET /v2/projects/{projet}/charts/mrr?resolution=0&start_date=2026-08-15&end_date=2026-11-13
→ {"measures":[{"display_name":"MRR",…}],
   "values":[{"cohort":1794355200,"incomplete":false,"measure":0,"value":947.95},…]}
```

- `resolution=0` = au jour (1 semaine, 2 mois, 3 trimestre, 4 année).
- `cohort` = minuit UTC du jour, en secondes. Le jour s'écrit à la date de Paris de cet instant, donc la même date. Les jours de RevenueCat sont des jours UTC : un achat à 0 h 30 à Paris compte la veille.
- `measure` = index dans `measures`. On lit la mesure **par son `display_name`** ; un nom disparu fait une erreur `.format`.
- Le jour en cours arrive avec `incomplete: true`. Les graphiques ne sont pas en retard sur l'overview : les valeurs du 11 et du 12 nov. 2026 tombaient pile sur l'overview.
- Limite : 25 requêtes par minute sur les graphiques. Un passage en fait 6.

| Graphique | Mesure lue | Métrique |
|---|---|---|
| `mrr` | `MRR` | `mrr_brut`, `mrr_net` |
| `actives` | `Actives` | `abonnes` |
| `trials` | `Active Trials` | `essais_actifs` |
| `actives_new` | `Total Paid Subscriptions` moins `Product Changes` | `achats` |
| `customers_new` | `New Customers` | `nouveaux_clients`, aujourd'hui compris (encore partiel) |
| `revenue` | `Revenue` | `revenu`, le brut de chaque jour lu, aujourd'hui compris (encore partiel) ; et `revenu_28j` des jours passés : somme des 28 jours finissant à chacun (`revenus28j`), lue 27 jours avant le début de la fenêtre ; un jour dont la fenêtre n'est pas complète n'est pas écrit |

**Par store.** Chaque graphique est demandé avec `&segment=store` : la réponse porte `segments` (`display_name`, `is_total`) et chaque point son `segment`. Le total se lit sur le segment `is_total` ; un store, sur le segment dont le nom est « App Store » ou contient « Play » (`RevenueCat.boutique(segment:)`), à 0 les jours où il n'apparaît pas. L'overview ne se découpe pas : aujourd'hui, chaque store prend la part qu'il a dans les graphiques du jour (MRR, abonnés, essais) ou des 28 derniers jours (revenu). Les métriques par store s'écrivent suffixées (`mrr_brut.play_store`) et somment au total. L'app Play est `app90af4fbfd0` dans le projet RevenueCat de Roleo ; le segment n'apparaît qu'avec ses premières données. `customers_new` refuse `segment=store` (400) : il est demandé avec `segment=first_platform`, segments Total, iOS, Android et Unknown ; iOS va à l'App Store, Android au Play Store, Unknown (une poignée par jour au plus) au total seulement, si bien que les deux stores peuvent faire un de moins que le total.

`actives_new` a six mesures : `Trial Conversions`, `Intro Offers`, `Direct Subscriptions`, `Product Changes`, `Resubscriptions`, `Total Paid Subscriptions`. Un changement de formule n'est pas un achat, d'où la soustraction.

Fenêtre : 90 jours au premier passage, ou quand `revenu_28j`, `revenu` ou `nouveaux_clients` d'hier ou de J-89 manque ; sinon les 7 derniers (RevenueCat consolide les jours récents). Les jours passés viennent des graphiques ; aujourd'hui vient de l'overview, sauf `achats`, `revenu` et `nouveaux_clients` qui n'existent que dans le graphique.

## Le fil `ACHAT`

La v2 n'a **aucune liste des transactions d'un projet** : les transactions se lisent abonnement par abonnement, `GET /projects/{p}/subscriptions` ne cherche que par identifiant du store, et la liste des clients n'a pas d'ordre. Le webhook de Roleo ne garde pas les événements non plus : il relit le compte (`users/{uid}` : `premiumUntil`, `premiumTrial`, `entitlementCheckedAt`). On part donc de là :

1. **Firestore** (jeton Google, `x-goog-user-project`) : les comptes dont le droit court encore, une centaine de documents.

   ```
   POST https://firestore.googleapis.com/v1/projects/roleo-73820/databases/(default)/documents:runQuery
   {"structuredQuery":{"from":[{"collectionId":"users"}],
     "select":{"fields":[{"fieldPath":"premiumTrial"},{"fieldPath":"entitlementCheckedAt"}]},
     "where":{"fieldFilter":{"field":{"fieldPath":"premiumUntil"},"op":"GREATER_THAN","value":{"timestampValue":"<maintenant>"}}}}}
   ```

   On garde ceux hors essai (`premiumTrial` différent de `true`) relus depuis le dernier passage réussi moins 2 h (3 jours au premier passage). Un achat, une fin d'essai payée, un renouvellement font relire le compte par le webhook. Filtrer sur `entitlementCheckedAt` seul ramènerait ~450 comptes gratuits par jour.

2. **Abonnements du compte** : `GET /v2/projects/{p}/customers/{uid}/subscriptions?limit=50` (404 = compte inconnu de RevenueCat, sauté). On garde les abonnements `environment: "production"` commencés (`starts_at`, en millisecondes) au plus 8 jours avant la fenêtre, le temps d'un essai.

3. **Transactions** de chaque abonnement pas encore dans le fil : `GET /v2/projects/{p}/subscriptions/{sid}/transactions?sort=purchased_at&direction=asc&limit=20`. La première avec `revenue_in_local_currency.gross > 0` est l'achat ; une transaction à 0 avant elle est l'essai. Pas encore de paiement : rien, l'abonnement est relu au passage suivant.

| Champ | Valeur |
|---|---|
| id | `revenuecat:achat:<id de l'abonnement>` (`subAap…`), stable |
| `at` | `purchased_at` de la première transaction payée |
| texte | `Annuel après essai, 69,99 €, France` : formule, prix dans la devise du client (format français), pays |
| lien | aucun |

La formule se lit dans `product_store_identifier` : `week`/`hebdo` Hebdo, `month` Mensuel, `quarter`/`trimestr` Trimestriel, `year`/`annual` Annuel, sinon l'identifiant tel quel (`Yearly`, `monthly`, `roleo_quarterly:trimestriel`, `roleo_weekly:hebdo`, `roleo_annual_downsell` existent). Un achat trouvé en retard s'écrit quand même, à son heure ; le collecteur ne notifie que ce qui a moins de 2 h.

Vérifié le 13 nov. 2026 : les 2 achats du 12 et les 5 du 11 du fil sont exactement les `achats` du graphique ces jours-là. Le premier passage remonte aussi des achats plus anciens de comptes relus récemment (jusqu'au 3 nov.), pas tous.

## Le paiement des installs convertis

PostHog dit qui a pris un essai ou acheté (`install.client`, l'`app_user_id` RevenueCat), pas qui a payé : un essai annulé ou un achat remboursé y restent. La source relit donc ces clients chez RevenueCat et écrit leur état dans la table `paiement`, que l'arbre des installs de Data joint pour compter les payants.

1. **Les clients à lire** (`Store.clientsAVerifier`) : ceux de `install` jamais lus, puis ceux encore en essai ou sans paiement, lus il y a plus de 6 h (`relecturePaiement`) et installés dans les 40 derniers jours (`suiviPaiement`, assez pour qu'un essai finisse et que le premier renouvellement passe). Les plus récents d'abord, 500 au plus par passage (`paiementsParPassage`) : les 367 convertis de 97 jours se lisent au premier passage.
2. **`GET /v2/projects/{p}/customers/{id}/subscriptions?limit=50`**, l'id encodé en URL. Les mêmes que pour le fil : rien n'est créé.
3. **L'état**, sur les seuls abonnements `environment: "production"` : `paye` dès que l'un a `total_revenue_in_usd.gross > 0`, sinon `essai` si l'un est `trialing`, sinon `non` (essai annulé, remboursé). `inconnu` sans abonnement de production (testeur en sandbox) ou sur un 404 (client que RevenueCat ne connaît pas, compte anonyme non lié).

Un `paye` ou un `inconnu` n'est plus relu ; un `essai` ou un `non` l'est toutes les 6 h tant que l'install a moins de 40 jours.

## Ce que la source fait

Pour chaque business : `projects`, `overview`, les 6 graphiques, puis les séries dans un `lot` ; ensuite Firestore et le fil. Appels : 8 vers RevenueCat, 1 vers Firestore, puis 1 par compte relu, 1 par abonnement neuf et 1 par client converti à lire (500 au plus). Premier passage de Roleo : 472 lignes en 13 s.

Relevé du 13 nov. 2026 à 1 h : MRR 947 $ brut (682 $ net), 100 abonnés, 23 essais en cours, revenu 28 j 3 268 $. Historique depuis le 15 août : 11 abonnés le 15 sept., 34 le 15 oct., 100 le 11 nov.

## Ce qui peut casser

- RevenueCat renomme une mesure (`display_name`) ou un `id` de l'overview : erreur `.format`, Santé le montre.
- Le webhook de Roleo arrête de relire les comptes, ou les champs `premiumUntil`, `premiumTrial`, `entitlementCheckedAt` changent de nom : le fil ACHAT se tait sans erreur ; `achats` (graphique) reste juste. Comparer les deux en cas de doute.
- Un achat sur un compte dont l'uid n'est pas l'`app_user_id` RevenueCat (anonyme non lié) : 404, absent du fil.
- Un client converti dont le `distinct_id` PostHog n'est pas l'`app_user_id` RevenueCat : 404, compté « à vérifier » dans Data, jamais payant.
- Plus de quelques centaines de comptes relus par passage : beaucoup d'appels `customers`, la limite de débit de RevenueCat rendrait des 429 (`HTTP` rejoue 3 fois).
- `mrr` est en dollars et brut ; `mrr_net` applique 72 %, une moyenne (TVA et commission varient par pays).
