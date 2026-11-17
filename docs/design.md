# Design

La référence est un **terminal de marché noir et blanc** (14 nov. 2026, d'après liquidjournal et Scale) : fond noir, cartes noires à peine relevées, chiffres blancs énormes, petits titres en capitales monospace. La couleur ne sert qu'à porter un sens. Dense, lisible d'un coup d'œil, satisfaisant au toucher.

## Les règles

- **Fond noir** `Theme.fond`, avec une seule lueur blanche qui tombe du haut de la fenêtre (`Theme.lueur`, posée par `Racine`). Jamais de dégradé de couleur ni d'image derrière les cartes.
- **La carte** : `.verre(rayon:)` ou `.verre(Capsule())` sur chaque panneau, pilule ou bouton (`Verre.swift`). Fond `carte`, reflet blanc qui s'éteint vers le bas (`reflet`), filet `Blanc.bord`, arête claire en haut (`arete`), ombre longue. Pas de `.glassEffect` système.
- **Couleur = sens**, jamais décor, et toujours avec un libellé :
  - blanc (`accent` = `texte`) : ce qui est choisi, la série principale, un lien, ce qui passe un seuil ;
  - vert `succes` et rouge `danger` : ce qui monte ou baisse (`Ton`, `Design/Ton.swift`), une source ok ou en panne, une vidéo qui a percé ou pas ;
  - ambre : ce qui demande d'agir (tâche, retard, collecte en pause, erreur d'une source) ;
  - orange, bleu, aqua, violet : des séries, des plateformes ou des business à distinguer, dans cet ordre.
  Tout le reste est blanc en opacité (`Theme.Blanc`), `secondaire` ou `tertiaire`. Jamais de fond coloré plein : une pastille prend `Theme.doux(c)`.
- **Texte** : SF Pro, uniquement par `Theme.Police`. Les petits titres de carte, les tags et les axes sont en monospace (`surtitre`, `tag`, `axe`), le titre de carte par `.surtitre()` (capitales, interlettrage 1,5, `tertiaire`). Chiffres en `.monospacedDigit()` dès qu'ils changent, un gros chiffre par `Chiffre`, serré (`tracking` négatif). Français, sans tiret cadratin, nombres par `Format`.
- **Une donnée ne se coupe jamais.** Dans une carte, le libellé se tronque avant la pastille de delta (`layoutPriority(1)`) ; un lien passe sur la ligne du titre plutôt que de couper une pastille.
- **Couleurs, opacités et polices** viennent toujours de `Theme.swift` ; rayons, espaces et tailles aussi dès que le jeton existe. Une mesure propre à un seul composant peut rester locale, nommée dans un `private enum Mesure` si elle sert plus d'une fois dans le fichier. Elle monte dans `Theme` dès qu'un deuxième composant en a besoin.
- **Tout bouge, rien ne boucle.** Chaque changement d'état s'anime (écran, business, période, données, survol, appui), mais aucune animation ne tourne en continu. Voir § Mouvement.
- Pas de redesign au passage : on applique les composants existants.

## Jetons (`Cockpit/Design/Theme.swift`)

| Groupe | Contenu |
|---|---|
| Surfaces | `fond` 050506, `carte` 0C0C0E, `releve` 17171A (surface posée sur une carte : bulle, champ, ligne survolée) |
| Texte | `texte` F5F5F4, `secondaire` A1A1A6, `tertiaire` 66666C ; `accent` = `texte` |
| États | `succes` 4ADE80, `ambre` FBBF24, `danger` F87171 |
| Catégories | `orange` D95926, `bleu` 3987E5, `aqua` 199E70, `violet` 9085E9 ; `teinte(cle)` lit la teinte d'un business, gardée en base sous son ancien nom (`menthe` → aqua, `ciel` → bleu, `lilas` → violet, `ambre` → orange), `teintes` la propose dans Réglages ; `doux(c)` pour le fond d'une pastille |
| `Blanc` | opacités : `bord`, `bordFort`, `bloc`, `ligne`, `survol`, `pilule`, `actif`, `selection`, `fantome`, `barre`, `repere` (légende d'une série fantôme), `grille` (grille, filet), `serie` (série secondaire), `trait` (trait neutre), `ombre`, `halo` (chiffre héros, point au bout d'une courbe) |
| Styles | `lueur` (le haut de la fenêtre), `voile` (sous la palette), `trait` (`StrokeStyle` d'une courbe), `viseur` (repère pointillé sous la souris) ; dans `Verre.swift` : `reflet`, `arete`, `lavis` (aire sous la courbe héros), `degradeHeros` |
| `Rayon` | `panneau` 20, `carte` 18, `bloc` 14, `bouton` 12, `tache` 11, `ligne` 10, `avatar` 8, `barre` 4 |
| `Espace` | `xs` 2, `s` 4, `m` 8, `l` 10, `xl` 12, `xxl` 16, `panneau` 20, `page` 28 |
| `Taille` | `barreHaut` 52 et `feux` 78 (la place des boutons de la fenêtre), `avatar` 32, `avatarMini` 26 (le business dans la barre), `bulle` 300, `lueur` 680, fenêtre 1320 × 920 (au moins 1080 × 720), lignes (fil, vidéo, tâche), sparkline, `graphique` 128, `graphiqueHaut` 170, `graphiqueHeros` 210, `pointCourbe`, `marque` 20 (le logo de la barre), `panneauReseau` 248 et `panneauPlan` 280 (les panneaux de l'Accueil), `rail` 52 (un panneau replié), `conversation` 460 et `reponse` 88 (le fil et le champ de réponse du SAV), `radar` 156, `jauge` 6, palette, barre de menus, Réglages… ; le widget : `marqueWidget` 13, `courbeWidget` 40, `sparklineWidget` 16 |
| `Anim` | ressorts : `navigation` (écran, business, pilules, palette), `chiffre`, `survol` (survol, appui), `entree` (bloc, barre), `trace` (courbe, graphique) ; `decalage` 0,05 s entre deux blocs, `decalageBarre`, `rangMax` 8 ; échelles `appui` 0,96, `appuiCarte` 0,98, `survolEchelle`, `reduit` ; `glisse` 14, `flou` 8 |
| `Police` | texte : `titre`, `h2`, `kpi` 30, `grand`, `heros` 76, `marque` (« Cockpit », système semi-gras 18), `widgetHeros` 34, `widgetHerosGrand` 44 et `widgetKpi` 19 (le widget), `corps`, `corpsGras`, `ligne`, `label`, `petit`, `mini`, `miniGras` ; monospace : `surtitre`, `tag`, `axe` ; symboles SF : `coche` 9, `fleche` 10, `symbole` 13, `icone` 14, `symboleGrand` 15 |

`Theme` est `nonisolated` (et `Color(hex:)` aussi) : l'app isole tout sur le main actor par défaut, et des jetons statiques doivent rester lisibles de partout.

## La barre du haut (`Composants/BarreHaut.swift`)

Il n'y a pas de barre latérale. Une barre de 52 pt, dans la barre de titre de la fenêtre, en trois tiers (`TroisTiers`, un `Layout`) :

- **gauche**, après les boutons de la fenêtre : le business affiché (avatar, nom, chevrons) ; un menu pour passer à Tous, à un business, ou ouvrir Réglages ;
- **centre** : le logo (`Marque`, dans `Design/Marque.swift`, l'horizon de l'icône dessiné en formes SwiftUI, 20 pt) et « Cockpit » (`Police.marque`, en `texte`) au milieu de la fenêtre, entre deux pilules d'écrans coupées avant SAV pour faire à peu près la même largeur (Accueil, Data, Vidéos, Santé | SAV, Apps de potes). `Symetrie` (un `Layout`) garde le nom au centre tant que la place le permet, puis colle les pilules ; `TroisTiers` donne au centre la plus large bande centrée que la gauche et la droite au plus serré lui laissent (à 1080 pt de large, le nom glisse d'une trentaine de points à gauche). La pilule blanche glisse de l'ancien écran au nouveau, d'une pilule à l'autre (texte noir dessus) ; le compteur ambre du SAV suit le mot ; ⌘1 à ⌘6 dans l'aide ;
- **droite**, calée au bord avec la place que le centre lui laisse : la bande des sources (un point par source et « Collecte il y a … », les points seuls si la place manque ; au survol, une bulle avec l'état et l'erreur de chaque source ; un clic ouvre Santé), Rechercher ⌘K, Tout relancer (la flèche tourne pendant la collecte).

## Composants partagés

| Composant | Usage |
|---|---|
| `Page(titre:sousTitre:)` | le cadre d'un écran : `EnTete` fixe (titre, sous-titre, outils de l'écran, `Segmente` des business), contenu qui défile, blocs qui entrent l'un après l'autre |
| `Segmente(options:choix:)` | la pilule à choix unique : filtre des business, période, tri, liste, pays. La pilule blanche glisse d'un choix à l'autre. Le seul segmenté de l'app, jamais de `Picker` `.segmented` système |
| `HerosRevenu` | le revenu brut en euros en héros de l'Accueil (`EcranAccueil.swift`) : en-tête avec le choix de période en pilule de verre, chiffre en `.heros()` (76 pt, dégradé blanc, halo), pastille d'écart, essais et achats, aire blanche du revenu cumulé (`lavis`) ; au survol, un repère pointillé (`viseur`), le point du jour visé et une bulle `releve` avec la date et le cumul |
| `PanneauReseau`, `PanneauPlan` | les panneaux de verre de part et d'autre de l'Accueil (`PanneauxAccueil.swift`), repliables en rail de `Taille.rail` par `BoutonPanneau` ; `Jauge` pour l'objectif de vidéos du jour |
| `PanneauScore`, `Radar` | le score de la semaine : un radar en `Canvas` (deux anneaux, un rayon par axe, le polygone des notes en `Blanc.selection` bordé d'`accent`), la note sur 100 et le point faible |
| `GrilleKPI(colonnes:)` + `CarteKPI` | grille de cartes KPI (4 colonnes par défaut) : surtitre et pastille de delta, chiffre en `kpi`, sparkline à droite ; `grande` pose la sparkline dessous sur toute la place reçue ; `ton` colore le delta, `inverse` pour un rang ; `note` ajoute une ligne en `secondaire` sous le chiffre |
| `Rangee(poids:hauteurDe:)` | panneaux côte à côte aux largeurs proportionnelles, même hauteur |
| `Bloc`, `Panneau`, `EnTetePanneau` | un panneau titré en surtitre, avec un accessoire à droite |
| `Barres`, `Sparkline`, `Legende` | graphiques (formes) : `Barres` met la barre en cours en blanc avec un halo ; `Sparkline` finit sur un point lumineux |
| `axeDates(_:texte:)`, `axeNombres(_:texte:)` | les axes de tout graphique Swift Charts (`Graphiques.swift`) : grille `Blanc.grille`, libellés `Police.axe` en `tertiaire`, nombres à gauche. Une courbe prend `.lineStyle(Theme.trait)` et `.symbolSize(Theme.Taille.pointCourbe)`. Sur un axe de catégories (`String`), `AxisMarks(values:)` ne filtre rien : on espace les libellés dans la closure d'`AxisValueLabel` (une heure sur quatre, un jour sur quatre) |
| `PanneauFil`, `LigneFil` | le fil « En direct », titré d'un point vert |
| `PanneauTaches`, `LigneTacheVue`, `CaseRonde` | tâches cochables |
| `TableVideos`, `PastilleSeuil` | le tableau des vidéos et le rappel du seuil de 1,5 % |
| `Miniature` | une image du cache disque, la première trouvée parmi ses clés (`Miniatures.cles` : la première image de la vidéo, sinon sa miniature), le logo de la plateforme sur un fond doux tant qu'aucune n'est là ; `Plateforme.logo(taille)` (les logos officiels en couleur, SVG de `Logos.xcassets` tracés d'après Simple Icons, CC0 ; tailles `Taille.logoMini` 12, `logo` 16, `logoGrand` 20) et `Plateforme.couleur` (TikTok aqua, Instagram violet, YouTube orange, Facebook bleu). Les images passent par `Images` (voir plus bas) |
| `CarteCompte`, `CarteAjout`, `CaseVideo` | privés à `Ecrans/Videos.swift` : carte d'un compte suivi, carte « Suivre un compte », case de la grille des vidéos |
| `Pastille`, `Point`, `Vide` | étiquette colorée sur `doux`, pastille d'état avec halo, message de liste vide |
| `Avatar`, `IconeApp` | l'icône de l'app du business (`config.appStoreId`, image `icone:<id>` mise en cache par Classements), sa lettre s'il n'a pas d'app, le logo rond (`Marque`, en `texte`) pour « Tous » ; `IconeApp` sert aussi aux lignes d'Apps de potes. Une icône est cernée d'un filet `Blanc.bordFort` pour qu'une icône sombre se détache du noir |

## Le widget du bureau (`CockpitWidget/VuesWidget.swift`)

Le même terminal noir en petit : fond `carte` avec son `reflet` (`FondWidget`), en-tête `Marque` + surtitre et « maj » en `tag`, le revenu en `degradeHeros` avec son halo, la courbe du revenu cumulé sur le mois posée sur le `lavis` avec le point lumineux au bout. Les chiffres en `widgetKpi`, leur écart coloré par `Ton`, sinon une note en `tertiaire`. Dans le grand, chaque chiffre a sa tuile (`Blanc.bloc`, `Rayon.ligne`) et sa sparkline ; « À traiter » en ambre s'il reste des tâches. Pas d'animation : WidgetKit n'en joue pas. Pour régler la mise en page sans réinstaller le widget, les vues ne dépendent pas de WidgetKit : `ImageRenderer` les rend en PNG depuis un script qui compile le cœur, les quatre fichiers de `Design` partagés et `VuesWidget.swift`.

## Mouvement (`Cockpit/Design/Mouvement.swift`)

| Outil | Où |
|---|---|
| `Chiffre(texte:)` | les gros chiffres (cartes KPI, objectif de Data, barre de menus, abonnés et vues des vidéos) : partent de zéros à l'apparition et roulent à chaque changement (`.numericText`). `Pastille` roule aussi |
| `Bascule(sens:)` | le changement d'écran dans `Racine` : le nouvel écran glisse depuis la droite s'il est plus à droite dans la barre du haut (`AppState.avance`), depuis la gauche sinon, avec un flou qui se dissipe |
| `Surgit` | la carte de la palette ⌘K ; le voile, lui, est un fondu |
| `matchedGeometryEffect` | la pilule qui glisse : écran de la barre du haut, `Segmente`, ligne choisie de la palette |
| `sensoryFeedback` | un retour haptique au changement d'écran, de business et de période (`Racine`) et à chaque jour visé sur le héros du revenu |
| `.entree(rang:)` | les blocs d'une `Page` et les cartes d'une `GrilleKPI`, l'un après l'autre |
| `.revele()` | chaque graphique Swift Charts se dévoile de gauche à droite ; `Sparkline` se trace (`trim`), `Barres` poussent |
| `.buttonStyle(.appui)`, `.appuiCarte` | tous les boutons s'enfoncent à l'appui ; `.appuiCarte` pour une ligne ou une carte entière |
| `.survolable()` | une carte se soulève sous la souris : `CarteKPI`, `CarteCompte`, `CaseVideo`, Rechercher, Tout relancer |

`Racine` anime l'écran, le business choisi, la palette et `store.version` : chaque collecte fait glisser listes et graphiques vers leurs nouvelles valeurs. Un état local qui ouvre ou ferme une section passe par `withAnimation(Theme.Anim.navigation)`. Nouveau composant : il prend ces outils, jamais une durée ou un ressort en dur.

**Reduce Motion** : `.sobre()`, posé sur `Racine` et sur `BarreMenus`, retire toute animation de la transaction quand l'option d'accessibilité est active.

## Icône de l'app

`Cockpit/AppIcon.icon`, un document Icon Composer (verre liquide de macOS 26), en noir et blanc : un horizon artificiel, un anneau blanc autour d'un demi-disque blanc dont la ligne d'horizon monte de 12 degrés vers la droite, sur fond noir. Deux groupes dans `icon.json` (le premier, `Horizon`, est au premier plan ; puis `Anneau`), deux SVG 1024 dans `Assets/` (`horizon.svg`, `anneau.svg`), en **formes pleines** : un trait (`stroke`) sur un arc ouvert laisse des filets parasites au rendu. `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` dans `project.yml` ; Xcode en tire `AppIcon.icns` et `Assets.car`. Pour la voir sans compiler :

```bash
"$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool" Cockpit/AppIcon.icon \
  --export-image --output-file icone.png --platform macOS --rendition Default --width 512 --height 512 --scale 2
```

Le Dock et le Finder lisent l'icône dans le cache de LaunchServices, par bundle id : un autre build de `com.tonysanchez.cockpit` resté sur le disque (worktree, `.cache/build-*`) peut y imposer une vieille icône. Le désinscrire, puis réinscrire le bon :

```bash
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
$LSR -dump | grep -E "^path:.*Cockpit\.app"      # les builds connus
$LSR -u <autre>/Cockpit.app                       # pour chaque build en trop
$LSR -f build/Build/Products/Debug/Cockpit.app && killall Dock
```

Aucune image n'est chargée par le réseau depuis l'interface : miniatures, premières images, avatars et icônes d'apps sont téléchargés par les sources dans le cache disque (`Collecte/Miniatures.swift`). `Images` (`Composants/Miniature.swift`) les décode hors du fil principal, réduites à 720 px de grand côté (`Images.cote`, une case de la grille fait au plus 338 pt de haut), les icônes d'apps à 128 px (`Images.coteIcone`, le double de `Taille.avatar` en Retina : réduite d'un coup de 512 px à 44, une icône sortait floue et crénelée), et les garde en mémoire pour la session (`NSCache`, 400 Mo). `Racine` précharge à chaque écriture du store, en tâche de fond, les icônes, les avatars et les 300 vidéos les plus récentes de tous les business (`Lectures.images`, `Images.videosEnMemoire`) : changer d'onglet ou de business les rend tout de suite, sans relire le disque. Une image pas encore en mémoire est décodée à l'affichage puis apparaît en fondu. Un fichier illisible est retiré du cache pour être retéléchargé.
