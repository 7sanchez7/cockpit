# TikTok

Fichiers : `Cockpit/Sources/TikTok.swift`, la liste dans `Collecte/YtDlp.swift`, la session dans `Collecte/Safari.swift`. Cadence : 30 min. Aucune clé : la session `tiktok.com` de Safari. Tests : `CockpitTests/TikTokTests.swift`, `CockpitTests/SafariTests.swift`, `ReseauxTests.swift` (analyse).

Les vidéos et les compteurs publics de chaque compte TikTok suivi (table `compte`, voir [`../donnees.md`](../donnees.md)) et, pour le compte connecté dans Safari, ses stats privées : watch time, rétention, sources, public. TikTok ne donne pas les stats d'un créateur sans app développeur validée : on appelle l'API interne de TikTok Studio, celle de la page Analytics, comme `contenu/outils/tiktok/stats.py` du dépôt Roleo. Branchée le 13 nov. 2026.

## La liste : yt-dlp

```
yt-dlp --flat-playlist -J https://www.tiktok.com/@holaestony
```

Lancé par `Commande.shell` (zsh de login, donc le `PATH` Homebrew). Public, sans cookie, marche pour tous les comptes. Lu dans `entries[]` : `id`, `url`, `timestamp` (publication, Unix), `duration` (s), `description` sinon `title` (la légende, souvent rien que des hashtags), les compteurs publics (`view_count`, `like_count`, `comment_count`, `repost_count`, `save_count`) et la miniature (`thumbnails[]` d'id `cover`). Le nom de compte est normalisé à l'ajout (`Compte.handle`).

## Le profil : la page publique

`GET https://www.tiktok.com/@<compte>` avec un User-Agent de navigateur, sans cookie. Le JSON du `<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__">`, sous `__DEFAULT_SCOPE__["webapp.user-detail"].userInfo` : `stats.followerCount`, `videoCount`, `heartCount` (un `compte_releve`) et `user.avatarMedium` (l'avatar).

## La session : les cookies de Safari

`Safari.cookies(domaine, requis:)` (`Collecte/Safari.swift`) lit `~/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies` (profil par défaut), puis `WebKit/WebsiteDataStore/<profil>/Cookies/Cookies.binarycookies` (profils créés dans Safari, comme `tony_roleo`) : parmi ceux qui ont le cookie `requis`, gagne celui où il a été créé en dernier, donc le profil où l'on s'est connecté le plus récemment. Un vieux profil garde parfois une session que le site refuse (Instagram, le 13 nov. 2026). Le fichier n'est pas chiffré, mais macOS le protège.

- **Accès complet au disque** pour Cockpit (Réglages Système, Confidentialité et sécurité, Accès complet au disque), à accorder une fois. L'app est signée « Apple Development » : l'accès tient d'un build à l'autre. Sans lui, toutes les sources à session passent en gris : « Safari illisible : donner l'accès complet au disque à Cockpit ».
- Format `cook` : nombre et tailles des pages en big-endian ; dans chaque page, les décalages des cookies ; chaque cookie en little-endian (taille, décalages du domaine, du nom, du chemin et de la valeur, chaînes terminées par un zéro, expiration à l'octet 40 et création à l'octet 48, en secondes depuis 2001). Un fichier qui ne suit pas ce format lève une erreur.
- Sont gardés les cookies du domaine et de ses sous-domaines (`.tiktok.com`, `www.tiktok.com`), pas expirés. Tous partent dans l'en-tête `Cookie`. Sans `sessionid`, la source passe en gris.

Aucune valeur de cookie n'est affichée, écrite, ou mise dans une erreur.

## Le compte connecté : `passport`

```
GET https://www.tiktok.com/passport/web/account/info/?aid=1988&app_name=tiktok_creator_center&device_platform=web_pc
```

`data.username` = le compte de la session (`holaestony` le 13 nov. 2026). Sans `username`, la session a expiré : erreur `session TikTok de Safari expirée, se reconnecter sur tiktok.com dans Safari`.

## Les stats d'une vidéo : `insight`

Une seule requête par vidéo demande tous les types de la page Analytics (`TikTok.types`) : TikTok ne rend les `_realtime` que demandés ensemble. Si la réponse n'a pas `realtime_total_video_views`, TikTok n'avait pas fini de calculer : second essai après 3 s.

```
GET https://www.tiktok.com/aweme/v2/data/insight/?aid=1988&app_name=tiktok_creator_center&device_platform=web_pc&tz_name=Europe/Paris&type_requests=[…]
Referer: https://www.tiktok.com/tiktokstudio/analytics/<id vidéo>/overview
User-Agent: <Chrome macOS>
Cookie: <session Safari>
```

`type_requests` est un tableau JSON de `{"insigh_type": "<type>", "aweme_id": "<id>"}` (sic, `insigh_type`). Une valeur arrive en `{"status", "value"}` : `status` 0 = calculée, sinon nulle.

| Type | Lu | Colonne |
|---|---|---|
| `video_info` | `statistics.play_count`, `digg_count`, `comment_count`, `share_count`, `collect_count` | `vues`, `likes`, `commentaires`, `partages`, `enregistrements` |
| `video_per_duration_realtime` | `value.value`, en secondes | `watch_moyen_s` |
| `video_finish_rate_realtime` | `value.value`, fraction de 0 à 1 | `completion` |
| `realtime_new_followers` (type `video_new_follower_realtime`) | `value.value` ; `status` 2 = pas encore calculé (vidéo du jour) | `abonnes` |

Le reste va dans `video_analyse` (une ligne par vidéo, remplacée à chaque passage), affiché par le détail de l'écran Vidéos :

| Type | Lu | Champ de `Analyse` |
|---|---|---|
| `video_total_duration_realtime` | secondes cumulées | `watchTotalS` |
| `video_uv` | spectateurs uniques | `spectateurs` |
| `video_viewer_new_viewer_percent` | part de nouveaux spectateurs | `nouveaux` |
| `video_viewer_follower_percent_realtime` | part de vues d'abonnés | `abonnesPart` |
| `video_retention_rate_realtime` | `value.list[]` de `{timestamp, value}`, trié par temps ; un point par seconde, le premier à 1 | `retention` (l'accroche du levier est `retention[3]`, voir [`../ecrans.md`](../ecrans.md) § Vidéos) |
| `video_traffic_source_percent_realtime` | `[{key, value}]` | `sources` |
| `item_search_terms` | `[{key, value}]` | `recherches` |
| `video_viewer_age_percent_realtime` | `[{key, value}]` | `ages` |
| `video_viewer_location_percent_realtime` | `value.country_percent_list[]` de `{country_name, country_vv_percent}` | `pays` |
| `video_vv_history_7d` | les vues des 7 premiers jours après la publication | `vuesParJour` |

Une valeur en `{status, value}` ou, pour les `_realtime`, `{is_after_7d, value: {status, value}}` : `TikTok.champ` déballe les deux. `status_code` 5 « Invalid parameters » = vidéo d'un autre compte que celui de la session.

## Les vues du compte : `vv_history`

Même endpoint, `type_requests=[{"insigh_type":"vv_history","days":7,"end_days":1}]`, Referer `…/tiktokstudio/analytics/overview`. Rend 7 `{status, value}` : les vues de tout le compte, d'il y a 7 jours à hier.

**TikTok coupe ses jours à minuit UTC**, malgré `tz_name` : la fenêtre a glissé entre 23 h 51 et 0 h 04 UTC le 13 nov. Les jours s'écrivent donc depuis la date UTC. Juste après minuit UTC, le dernier jour n'est pas encore calculé (`status` ≠ 0) : pas écrit.

## Ce que la source fait

Pour les comptes TikTok actifs des business suivis (aucun : source en gris, « en ajouter dans Vidéos ») :

1. yt-dlp et la page de profil pour chaque compte. Chaque vidéo s'écrit par `Store.video` (sans toucher à ce que la fiche a écrit) avec sa ligne du fil `tiktok:pub:<id>`, `at` = publication : « Nouvelle vidéo sur @holaestony : <titre> ». Le collecteur ne notifie que les lignes de moins de 2 h : les anciennes vidéos ne sonnent pas. Les compteurs publics font le relevé des vidéos qui n'ont pas de stats privées.
2. Cookies de Safari, puis `passport`. Si le compte de la session n'est pas suivi, pas de stats privées : la source finit en gris avec la raison, après avoir écrit le reste.
3. Un `insight` pour chaque vidéo du compte de la session : à chaque passage si elle a moins de 14 jours, sinon une fois par jour (aucun relevé depuis minuit à Paris). Il remplace le relevé public. 300 ms entre deux appels.
4. Un `vv_history`.
5. Les miniatures et avatars absents du cache (`Collecte/Miniatures.swift`, voir [`../collecte.md`](../collecte.md)).
6. Tout s'écrit dans un seul `lot`, après les appels :
   - `video_releve` pour chaque relevé, tous au même `at`.
   - `compte_releve` de chaque profil, `video_analyse` de chaque analyse non vide.
   - Le fil `tiktok:palier:<id>:<palier>` quand les vues passent 1 000, 10 000, 100 000 ou 1 million entre le relevé précédent et celui-ci (une vidéo de moins de 24 h sans relevé part de 0) : « 10 000 vues pour « Dans cinq ans, je serai riche » ». Titre = celui de la fiche (source Contenu), sinon la légende sans hashtags (60 caractères), sinon « une vidéo de @compte ».
   - `serie(vues_tiktok)` des jours du `vv_history`, réécrits à chaque passage : le chiffre exact de TikTok remplace l'estimation de la veille.
   - `serie(vues_tiktok)` du jour, estimée par les relevés (plus bas).
   - `serie(vues_tiktok_j7)` sur le jour = le même calcul pour J-7, de minuit à la même heure, quand des relevés existent ce jour-là (donc une semaine après le premier passage).
7. Les échecs (une liste, un profil, une vidéo, une image) font finir le passage en erreur après avoir écrit le reste : `N échecs, dont stats <id> : …`.

### Vues du jour

Pour chaque vidéo : dernier relevé du jour − départ. Départ = son dernier relevé d'avant minuit ; sinon 0 si elle est sortie ce jour-là ; sinon son premier relevé du jour. On somme. Conséquences :

- Le jour du tout premier passage compte à partir de ce passage (0 au premier).
- Une vidéo de plus de 14 jours n'a qu'un relevé par jour : son gain est celui d'un relevé à l'autre, compté au premier passage du jour.
- Le lendemain, le `vv_history` remplace l'estimation. Ses jours sont en UTC, les nôtres à Paris : une à deux heures de décalage, acceptées.

Relevé du 13 nov. 2026 vers 1 h : 105 vidéos sur `holaestony`, 11 sur `tonyolingo`. Vues du compte du 6 au 11 nov. : 14 088, 20 152, 24 329, 18 489, 15 230, 44 092 ; le 12 pas encore calculé à 0 h 06 UTC. Premier passage : 105 appels `insight` ; le suivant : 22 vidéos de moins de 14 jours, 21 s. Exemple, `7706850746066554145` (11 nov.) : 25 495 vues, 1 665 likes, 12 commentaires, 56 partages, 489 enregistrements, 18,5 s de visionnage moyen, 11,8 % de complétion, 58 abonnés.

## Comptes sans stats privées

Seul le compte connecté dans Safari a les stats privées : `holaestony` aujourd'hui. Les autres (`tonyolingo`) ont les compteurs publics de yt-dlp (vues, likes, commentaires, partages, enregistrements) et ceux du profil, sans visionnage, complétion, abonnés gagnés ni analyse. Pour les avoir : se connecter à ce compte dans Safari, et perdre l'autre.

## Ce qui peut casser

- Session expirée ou déconnectée dans Safari : erreur au `passport`, Santé le montre. Se reconnecter sur tiktok.com dans Safari.
- Pas d'accès complet au disque, ou pas de `sessionid` : source en gris.
- yt-dlp suit mal les changements de TikTok : `brew upgrade yt-dlp`. Le 13 nov. 2026, yt-dlp ne démarrait plus (lien Homebrew `/opt/homebrew/opt/openssl@4` manquant, réparé par `brew link openssl@4` ou `brew reinstall python@3.14`) : la source échoue avec le message de yt-dlp.
- TikTok change son API interne (paramètres, `insigh_type`, structure) : `Réponse inattendue : insight : …`.
- Une limite de débit : les vidéos refusées sortent dans l'erreur de fin de passage, les autres s'écrivent.
- Chromium change son chiffrement des cookies (préfixe autre que `v10`/`v11`) : les cookies chiffrés sont ignorés, plus de `sessionid`, source en gris.
