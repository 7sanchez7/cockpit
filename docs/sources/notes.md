# Notes (app Notes de macOS)

Fichier : `Cockpit/Sources/Notes.swift`. Cadence : 1 min. Aucune clé : l'accès complet au disque pour Cockpit, le même que pour [Safari](tiktok.md). Tests : `CockpitTests/NotesTests.swift` (intertitres et cases, emojis comptés en UTF-16, gzip avec nom de fichier, refus de ce qui n'est pas du gzip) et `planDansLOrdreDeLaNote` dans `CockpitTests/AccueilTests.swift`.

Le panneau Plan de l'[Accueil](../ecrans.md#accueil) : ce que Tony a en cours et à faire, écrit dans une note iCloud, sur le Mac comme sur l'iPhone.

## La note

Une note dont la première ligne est **Cockpit** (casse indifférente), dans n'importe quel dossier :

```
Cockpit                       ← titre, sauté
Sortir le build 51            ← avant le premier intertitre : section « Plan »
Cette semaine                 ← intertitre (ou titre, sous-titre) : ouvre une section
☐ 3 vidéos par jour           ← case à cocher : tâche, cochée ou non
☑ Relancer RevenueCat
- carte de leçon              ← puce, numéro, texte : ligne simple
```

Plusieurs notes « Cockpit » : celle modifiée en dernier. Une note dans la corbeille, supprimée ou verrouillée par mot de passe est ignorée.

## D'où viennent les chiffres

`~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite`, ouvert en lecture seule :

- la note : `ZICCLOUDSYNCINGOBJECT` (`ZTITLE1`, `ZMARKEDFORDELETION`, `ZISPASSWORDPROTECTED`, `ZMODIFICATIONDATE1`, dossier `ZFOLDER` dont `ZFOLDERTYPE = 1` est la corbeille) ;
- son contenu : `ZICNOTEDATA.ZDATA`, un protobuf en gzip. Document (champ 2), note (3), texte (2), morceaux de même style (5). Un morceau porte sa longueur en unités UTF-16 (1) et son style de paragraphe (2) : type (1) et, pour une case, cochée ou non (5 puis 2).

| Style de Notes | Valeur | Ligne du plan |
|---|---|---|
| titre, intertitre, sous-titre | 0, 1, 2 | nouvelle section |
| case à cocher | 103 | `coche = 1`, `fait` selon la case |
| autre (texte, puces, numéros) | | ligne simple |

Le style d'une ligne est celui de son premier caractère. Les pièces jointes (U+FFFC) et les lignes vides sont retirées. Aucune dépendance : gzip et protobuf sont lus à la main (`Notes.gunzip`, `Protobuf`).

## Ce qui est écrit

La table `plan` ([donnees.md](../donnees.md#plan)), vidée et réécrite à chaque passage. Le plan ne dépend d'aucun business.

## Ce qui peut casser

- **Accès complet au disque** absent ou retiré : `non_configure`, « Notes illisible ». macOS refuse par EPERM, que `FileHandle` rend en `fileWriteNoPermission` (« pas l'autorisation d'enregistrer… ») : les deux codes sont attrapés.
- **Pas de note « Cockpit »** : `non_configure`, le panneau Plan affiche le message et l'aide.
- **Apple change le format** de `ZDATA` ou les colonnes : erreur `.format` ou SQL dans Santé, le plan garde son dernier état.
- Une note modifiée sur l'iPhone arrive quand iCloud a synchronisé le Mac, puis au passage suivant (1 min).
