# Classements App Store (iTunes)

Fichier : `Cockpit/Sources/Classements.swift`. Cadence : 3 h. Aucune clé. Tests : `CockpitTests/ClassementsTests.swift`.

Où sont nos apps et celles des potes dans le top 200 de l'App Store, pays par pays. Apple n'a pas d'API officielle des classements ; on lit l'ancien endpoint de la boutique iTunes, le seul qui va jusqu'à 200. Testé le 12 nov. 2026, source branchée le 13.

## Le top 200 : `viewTop`

```
GET https://itunes.apple.com/WebObjects/MZStore.woa/wa/viewTop?genreId=6017&popId=27
X-Apple-Store-Front: 143442,32
```

- `genreId` : la catégorie. `6017` = Éducation, `36` = toutes catégories. Les autres : la [liste des genres](https://itunes.apple.com/WebObjects/MZStoreServices.woa/ws/genres?id=36), noms français dans `Classements.genres`. `6061` (Enfants) n'a pas de page viewTop : passe au RSS.
- `popId=27` : classements iPhone.
- `X-Apple-Store-Front` : `<storefront>,32`, **obligatoire et sans suffixe de langue** : `143454-1,32` rend une page vide, et `?cc=de` sans l'en-tête rend une page de 5 Ko sans données.

| Pays | Code | Storefront | Langue de la page |
|---|---|---|---|
| France | `fr` | 143442 | fr |
| Espagne | `es` | 143454 | es |
| Belgique | `be` | 143446 | en-gb |
| États-Unis | `us` | 143441 | en |
| Royaume-Uni | `gb` | 143444 | en-gb |
| Allemagne | `de` | 143443 | de |
| Italie | `it` | 143450 | it |
| Suisse | `ch` | 143459 | de-ch |
| Canada | `ca` | 143455 | en-ca |

Les neuf codes vérifiés un par un le 13 nov. 2026, chacun rend ses trois listes. Un pays de business absent de ce tableau coupe la source (`nonConfigure`) : l'ajouter à `Classements.storefronts`.

### Lire les listes

La page HTML porte ses données dans `<script>its.serverData={…}</script>`. Le JSON utile est `pageData.topChartsPageData` :

- `topCharts` : les trois listes, chacune `{"adamIds":[…], "shortTitle", "id", "title"}`. `adamIds` = ids App Store dans l'ordre du classement ; payantes et recettes en ont 200, gratuites 209 ou 210. On garde les 200 premiers.
- `selectedChart` : la liste du `popId` demandé une seconde fois (le doublon des gratuites). Ignoré.

**On identifie une liste par son `id`, pas par son titre** : l'`id` est le `popId` de la liste, le même partout, alors que le titre est traduit par pays. Dans le JSON, le titre vient d'ailleurs après `adamIds`, pas avant.

| Liste | `id` | fr | es | us, gb, be, ca | de, ch | it |
|---|---|---|---|---|---|---|
| `gratuit` | 27 | Gratuites | Gratis | Free | Gratis | Gratis |
| `payant` | 30 | Payantes | De pago | Paid | Gekauft | A pagamento |
| `recettes` | 38 | Rentables | Por ingresos | Top Grossing | Umsatz | Top redditizie |

(`shortTitle`. Le `title` complet, en France : « Classement des apps gratuites (iPhone) ».) S'il manque `its.serverData`, le chemin JSON ou une des trois listes, la page est illisible : repli RSS.

## Repli : flux RSS, top 100

```
GET https://itunes.apple.com/{pays}/rss/top{free|paid|grossing}applications/limit=100/genre=6017/json
```

`limit=200`, `page=2` et `rss.marketingtools.apple.com` plafonnent aussi à 100 ou rendent une 500. Un flux rend 98 à 100 entrées, pas toujours 100. Les ids sont dans `feed.entry[].id.attributes["im:id"]` ; une seule entrée arrive en objet, pas en tableau.

Trois appels par pays et genre. Les rangs lus en RSS s'écrivent dans `rang`, mais ne font aucune ligne du fil, et le passage finit en erreur `Réponse inattendue : viewTop sans listes, repli RSS top 100 pour Éducation France, …` : Santé le montre, le collecteur le rejoue au bout de 10 min.

## Détails d'une app : `lookup`

```
GET https://itunes.apple.com/lookup?id=6770304361,1234567890&country=fr
```

Jusqu'à 100 ids par appel. Donne `trackName` (nom), `artistName` (éditeur), `artworkUrl512` (icône, `artworkUrl100` à défaut), `primaryGenreId`, `averageUserRating` et `userRatingCount` (pour ce pays), `version`. Un résultat sans `trackId` est ignoré.

Nos apps se lisent dans le premier pays de leur business, celles des potes dans le **pays principal** (`Classements.paysPrincipal` : le premier pays du premier business qui en a, `fr` pour Roleo).

## Ce que la source fait

Un seul passage global, pas un par business :

1. Pays = l'union des `pays` de tous les business. Apps = la `config.appStoreId` de chaque business, plus les apps suivies sans business (les potes).
2. `lookup` de toutes ces apps. Une de nos apps absente du lookup fait échouer le passage (`.format`, avec le nom du business). Les icônes (`artworkUrl512`) absentes du cache y sont téléchargées (`icone:<id>`, `Classements.icones`) : l'interface les lit sans réseau. Une icône en échec fait finir le passage en erreur, après l'écriture.
3. Genres = les `config.genre` des business, les genres rendus par le lookup et ceux des potes, plus `36`. Pour chaque pays et genre, un `viewTop`, 0,5 s de pause entre deux appels.
4. Tout s'écrit dans un seul `lot`, après les appels réseau : un passage qui échoue n'écrit rien (sauf le repli RSS, qui écrit puis lève).
   - `app` pour chaque app lue ; nos apps avec leur `business`, et `suivie = 1`.
   - `serie(note)` (si l'app a une note) et `serie(nb_notes)` du jour, pour chaque business.
   - `rang(app, pays, genre, liste, at, position)` pour chaque app suivie et chaque liste où elle est. Toutes les lignes du passage ont le même `at`.
   - Le fil, pour **nos** apps seulement (voir plus bas).

Appels par passage pour Roleo (4 pays, genres 6017 et 36) : 1 lookup + 8 viewTop = 9, entre 4 et 6 s. Chaque app de pote d'une autre catégorie ajoute 4 viewTop.

Relevé du 13 nov. 2026 vers 1 h : Roleo (6770304361) 152e en gratuit et 188e en recettes, Éducation France ; hors top 200 partout ailleurs (toutes catégories France, Éducation en Espagne, Belgique, États-Unis, et aussi Royaume-Uni, Allemagne, Italie, Suisse, Canada vérifiés à la main). Note 4,70 sur 73 notes, version 2.0.3.

### Le fil `RANG`

Le passage compare chaque liste au **passage précédent**, le `max(at)` de `rang` avant le passage en cours :

| Cas | Texte | Id |
|---|---|---|
| Entrée dans le top 200 | `188e en recettes, Éducation France (entrée)` | `classements:<app>:<pays>:<genre>:<liste>:<at>` |
| Au moins 20 places gagnées ou perdues | `152e en gratuit, Éducation France (+24)` | idem |
| Sortie du top 200 | `Hors top 200 en gratuit, Éducation Espagne (était 199e)` | idem, avec l'`at` du passage précédent |

Lien : `https://apps.apple.com/<pays>/app/id<app>`. L'`at` dans l'id est en ISO UTC (`2026-11-12T23:56:46Z`). Une sortie porte l'`at` où l'app a été vue pour la dernière fois, pour qu'une même sortie ne revienne pas.

Pas de fil au tout premier passage (`rang` vide), ni pour une liste lue en RSS, ni quand le passage précédent a fini en erreur après avoir écrit ses rangs (un repli RSS : ses rangs s'arrêtent à 100, la comparaison inventerait des entrées). Limites connues :

- Un pays ajouté à un business fait des lignes « entrée » à son premier passage.
- Le passage précédent est le dernier qui a écrit au moins un rang. Si aucune app n'était classée nulle part, le passage suivant se compare à un plus ancien.

Vérifié sur la vraie API : deux passages de suite ne font aucune ligne ; avec des rangs précédents modifiés à la main, le passage suivant sort bien les trois textes du tableau.

## Apps de potes

L'écran Apps de potes utilise deux fonctions de la source :

- `Classements.idApp(_ saisie: String) -> String?` : l'id d'une saisie, `6770304361` ou un lien `https://apps.apple.com/fr/app/roleo/id6770304361?l=en` (espaces autour tolérés). Nil si rien ne ressemble à un id.
- `Classements.ajouterApp(_ id: String, store: Store, http: HTTP) async throws -> Appli` : `lookup` dans le pays principal, puis `store.app`, `store.suivre(id, true)` et le téléchargement de son icône (en échec : l'app reste suivie, l'erreur le dit). L'app n'a pas de `business`. Lève `.format` si l'id n'existe pas dans ce pays. Ses rangs arrivent au passage suivant.

Retirer une app : `store.suivre(id, false)`.

## Ce qui peut casser

- Apple change la page : plus de `its.serverData`, un autre chemin JSON, ou d'autres `id` de liste. La source passe au RSS et le passage finit en erreur, Santé le montre.
- Une limite de débit sur `itunes.apple.com` (403 ou 429) : `HTTP` rejoue, puis erreur.
- Une app retirée de la vente : absente du lookup. Pour une des nôtres, le passage échoue ; pour un pote, elle garde ses anciennes infos et n'a plus de rang.
