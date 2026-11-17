# Instagram

Fichier : `Cockpit/Sources/Instagram.swift`, la session dans `Collecte/Safari.swift`. Cadence : 3 h. Aucune clé : la session `instagram.com` de Safari. Tests : `CockpitTests/ReseauxTests.swift`.

Les Reels des comptes Instagram suivis (table `compte`), leurs compteurs et les abonnés du compte. Pas de watch time : l'API interne ne le donne pas sur le fil, et l'API officielle demande un compte pro relié à une app Meta. Branchée le 13 nov. 2026.

## La session

`Safari.cookies("instagram.com", requis: "sessionid")`, même lecture que pour TikTok (voir [tiktok.md](tiktok.md) § La session). Tous les cookies partent dans `Cookie`, `csrftoken` aussi dans `X-CSRFToken`. Aucune valeur n'est affichée, écrite ni mise dans une erreur.

En-têtes de chaque appel, ceux de la page web d'Instagram : User-Agent de Safari (`HTTP.safari`, la session vient de Safari), `X-IG-App-ID: 936619743392459` (l'app web d'Instagram, exigée par l'API interne), `X-Requested-With: XMLHttpRequest`, `X-ASBD-ID: 359341`, `Accept: */*`, `Accept-Language`, `Referer` = le profil. Un cookie présent en double (`.instagram.com` et `www.instagram.com`) part avec sa valeur la plus récente.

## Le profil : `web_profile_info`

```
GET https://www.instagram.com/api/v1/users/web_profile_info/?username=<compte>
```

Sous `data.user` : `id` (pour le fil), `edge_followed_by.count` (abonnés), `edge_owner_to_timeline_media.count` (publications), `profile_pic_url_hd` sinon `profile_pic_url` (l'avatar). Un `compte_releve` par passage.

## Le fil : `feed/user`

```
GET https://www.instagram.com/api/v1/feed/user/<id>/?count=33
```

Les 33 dernières publications, dans `items[]`. Seules les vidéos (`media_type` 2) sont gardées. Lu : `code` (id `instagram:<code>`, lien `/reel/<code>/`), `caption.text`, `taken_at`, `video_duration`, `like_count`, `comment_count`, `image_versions2.candidates[0].url` (la miniature). Vues : `ig_play_count` d'abord (les lectures sur Instagram seul), sinon `play_count` (qui compte aussi le partage Facebook), sinon `view_count`.

## Ce que la source fait

Pour chaque compte Instagram actif des business suivis : profil puis fil, miniatures et avatars absents du cache, puis un seul `lot` : `video` et sa ligne du fil `instagram:pub:<id>` (« Nouvelle vidéo sur Instagram @compte : … »), `video_releve`, `compte_releve`. Un compte en échec n'arrête pas les autres ; le passage finit en erreur après avoir écrit le reste.

## Ce qui peut casser

- Session refusée : Instagram rend un 401, 403 ou 404, ou une page de connexion à la place du JSON (`require_login`). La source passe en gris : « session Instagram de Safari refusée (HTTP 404, session pas reconnue ; défaut : 7 cookies, sessionid créé … ; 6b554c84 : 8 cookies, …), se reconnecter sur instagram.com dans Safari ». La parenthèse dit ce qu'Instagram a renvoyé (`HTTP <code>`, `réponse pas en JSON` ou `require_login`). Sur une page d'erreur marquée `not-logged-in`, elle ajoute la provenance des cookies (`Safari.provenance`) : pour chaque profil Safari lu, les 8 premiers caractères de son dossier (ou `défaut`), le nombre de cookies du domaine et les dates de création et d'expiration du `sessionid`, jamais une valeur. Cockpit prend le profil au `sessionid` le plus récent. Un `sessionid` créé récemment et refusé quand même veut dire qu'Instagram refuse l'adresse, pas la session : se reconnecter n'y change rien, il faut attendre.
- Le 13 nov. 2026 : la session Dia a répondu (profil de @holaestony lu vers 05:40Z), puis rendait 404 à 06:13Z, quelques minutes après une série d'appels de sonde. À 09:59Z, le profil Safari choisi a un `sessionid` créé le jour même, et un appel anonyme de `web_profile_info` depuis le Mac rend lui aussi le 404 HTML au lieu du JSON : c'est l'adresse du Mac qu'Instagram bloque sur `/api/v1/`, pendant que Safari navigue normalement. Les 15 essais du jour (un toutes les 10 minutes) entretenaient le blocage : un échec d'Instagram n'est plus retenté qu'à sa cadence, toutes les 3 heures (`reprise`).
- Instagram change l'id de son app web ou ses chemins `/api/v1/` : `Réponse inattendue`.
