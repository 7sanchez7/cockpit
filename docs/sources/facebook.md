# Facebook

Fichier : `Cockpit/Sources/Facebook.swift`, la session dans `Collecte/Safari.swift`. Cadence : 3 h. Aucune clé : la session `facebook.com` de Safari. Tests : `CockpitTests/ReseauxTests.swift`.

Les vidéos des Pages Facebook suivies (table `compte`, le handle = le nom de la Page ou son id), avec leurs vraies stats : temps de visionnage, spectateurs, abonnés gagnés. Lues dans le tableau Statistiques → Contenu de Meta Business Suite, par son API interne. Branchée le 13 nov. 2026.

## La session et les jetons

`Safari.cookies("facebook.com", requis: "c_user")` : `c_user` est l'id de l'utilisateur, envoyé en `av` et `__user`. Puis la page `https://business.facebook.com/latest/home?asset_id=<page>`, ouverte comme par le navigateur, d'où l'on lit trois jetons : `fb_dtsg` (`DTSGInitialData`), `lsd` (`LSD`) et `__rev` (`server_revision`). Sans eux, la session a expiré : source en gris, « se reconnecter sur business.facebook.com dans Safari ».

Les cookies, les jetons et le HTML de Business Suite ne sont jamais affichés, écrits ni mis dans une erreur : `Facebook.appel` ne cite que le code HTTP.

## La Page

Un handle tout en chiffres est l'id de la Page. Sinon, la page publique `https://www.facebook.com/<handle>` donne `delegate_page_id` (ou un `asset_id=`). La page d'accueil de Business Suite donne les abonnés : `page_total_likes_or_followers.count`.

## Le tableau Contenu

```
POST https://business.facebook.com/api/graphql/
fb_api_req_friendly_name=BizWebInsightsContentOrganicTableQueryRendererQuery
doc_id=40040115705602765
variables={"ids": [<page>], "timeRange": {"type": "LAST_90D"}, "count": 100, …}
```

Corps en `application/x-www-form-urlencoded`, avec `X-FB-LSD` et `X-FB-Friendly-Name`. La réponse commence par `for (;;);` et met plusieurs objets JSON bout à bout (`Facebook.objets` les sépare). Les lignes sont sous `data.tofu_unified_table.content.edges[].node` : les publications des 90 derniers jours. Gardées : `content_type` VIDEO, ou une ligne qui a un temps de visionnage.

Chaque case est `fields.<clé>.renderer.value_for_sort` ; une case dont le `__typename` contient « Error » est absente, pas à zéro.

| Clé | Colonne ou champ |
|---|---|
| `views` | `vues` |
| `net_reactions`, `net_comments`, `shares`, `net_saves` | `likes`, `commentaires`, `partages`, `enregistrements` |
| `new_follows` | `abonnes` |
| `video_average_play_time` (ms) | `watch_moyen_s` |
| `video_play_time` (ms) | `Analyse.watchTotalS` |
| `viewers` | `Analyse.spectateurs` |
| `video_three_second_views`, `video_one_minute_views`, `video_thruplays` | `Analyse.jalons` (3 s, 1 min, ThruPlay), en part des vues |

Sous `header.entity.entity_info` : `title`, `created_at`, `image_source.uri` (miniature, 100x100) et `owner.entity_info.image_source.uri` (l'avatar de la Page).

## Ce que la source fait

Pour chaque Page active des business suivis : id, accueil (abonnés et jetons), tableau, puis les images absentes du cache et la première image des vidéos qui ne l'ont pas encore (`Miniatures.extrairePremieres`, 960 px de haut), puis un seul `lot` : `video` et sa ligne du fil `facebook:pub:<id>`, `video_releve`, `video_analyse`, `compte_releve`. Relevé du 13 nov. 2026 : 43 vidéos, 10 465 abonnés sur `holaestony`.

## Ce qui peut casser

- Session expirée : plus de jetons dans la page, source en gris.
- Meta change la requête : un nouveau `doc_id` (relu dans l'onglet Réseau de la page Statistiques → Contenu de Business Suite), ou des clés renommées. Une erreur graphql sort telle quelle (`graphql : <message>`).
- Les miniatures du tableau sont petites (100x100) : la grille montre la première image extraite, la miniature seulement en attendant.
