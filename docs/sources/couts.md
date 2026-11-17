# Coût IA

Fichier : `Cockpit/Sources/Firebase+Cout.swift` (`CoutIA`). Tests : `cout()`, `seriesIAALHeureDeParis` et `jourSansVoixGardeLeCoutReleve` dans `CockpitTests/FirebaseTests.swift`.

Le coût IA d'un jour, en euros : le texte plus la voix.

| Métrique | Écrite par | Jour |
|---|---|---|
| `cout_texte` | [Firebase](firebase.md), d'après les tokens | Paris |
| `cout_voix` | [Firebase](firebase.md#voix), d'après les caractères | Paris (UTC avant le 17 nov. 2026) |
| `cout_ia` | Firebase, `cout_texte + cout_voix` (`Store.somme`) | Paris |

La voix pèse 75 à 90 % du total depuis le 28 oct. 2026 : le 12 nov., 4,46 € de voix pour 0,52 € de texte.

## Texte

Même calcul que le dashboard admin de Roleo (`textCostEUR`, `firebase/functions/src/ratelimit/cost.ts`), pour que les deux chiffres soient égaux.

```
cout_texte = tokens_ia × (partEntree × entreeUSD + (1 − partEntree) × sortieUSD) / 1 000 000 × eurParUSD
        = tokens_ia × (0,8 × 0,10 + 0,2 × 0,50) / 1 000 000 × 0,92
        = tokens_ia × 0,1656 € par million de tokens
```

`tokens_ia` est le compteur `tk` de Roleo : tokens d'entrée hors lecture de cache (écritures de cache comprises) plus tokens de sortie, pour tous les appels qui passent par `src/ai/client.ts`. Exemple : le 12 nov. 2026 (Paris), 3 139 114 tokens, 0,52 €.

| Constante | Valeur | Source |
|---|---|---|
| `entreeUSD` | 0,10 $ / M | prix d'entrée de Claude Haiku 5.5, grille Anthropic relevée le 13 nov. 2026 |
| `sortieUSD` | 0,50 $ / M | prix de sortie de Claude Haiku 5.5, même grille |
| `partEntree` | 0,8 | mélange observé par Roleo, environ 80 % d'entrée non cachée et 20 % de sortie (commentaire de `cost.ts`) |
| `Metrique.eurParUSD` | 0,92 | taux fixe de Roleo (`usdToEUR`), pas le cours du jour ; partagé avec la voix et l'écran Data |

## Voix

```
cout_voix = Σ caractères du moteur × prix du moteur / 1 000 000 × eurParUSD
```

Les caractères sont la carte `v` d'`aiLoad`, par moteur (`TTSProvider` de Roleo). Prix relevés le 13 nov. 2026 (`CoutIA.voixUSD`) :

| Moteur | Rôle | $ par million de caractères |
|---|---|---|
| `voxtral3` | Voxtral 3 (Mistral), la voix des tuteurs | 13 |
| `kokoro` | Kokoro (DeepInfra), le repli et la voix de l'app | 1,485, d'après la facture DeepInfra |
| `voxtral` | Voxtral mini, le repli de Kokoro | 16 |
| `gemini` | Gemini Flash TTS, Mia en espagnol pour les uids listés | 20 |

Un moteur sans prix fait lever le passage (`CoutIA.euros(voix:)`) : un nouveau moteur chez Roleo s'ajoute ici, avec son prix. Exemple : 1 M de caractères Voxtral 3 à 13 $ font 11,96 €.

## Ce qui n'est pas compté

- **Une partie de la voix** : les transcriptions (Voxtral mini, dictée) n'ont pas de compteur, et les reprises du fredonnement (`src/ai/hum.ts`, retiré du code le 17 nov. 2026) ne comptaient la phrase qu'une fois. Le coût réel de la voix est un peu au-dessus de `cout_voix`.
- **Le cache** : les lectures du cache d'Anthropic (0,01 $ / M) ne sont pas dans `tk`. Les écritures (0,125 $ / M) y sont, comptées au prix d'entrée.
- **Le vrai fournisseur** : la reprise GLM chez Mistral passe par le même client, ses tokens sont dans `tk` au prix de Haiku. La vision (Mistral Medium) y est aussi, très probablement : elle est appelée dans `client.ts`, non vérifié sur un appel réel.
- **L'historique** : avant le 12 nov. 2026, le texte passait par GLM chez Fireworks. Ces jours sont comptés au prix de Haiku, comme le fait le dashboard. C'est un ordre de grandeur, pas la facture.
- L'infra Google (Functions, Firestore, Storage), RevenueCat, la commission Apple.

## Quand le modèle ou les prix changent

1. Changer les constantes de `CoutIA` (et `Metrique.eurParUSD` si Roleo change `usdToEUR`), et la date et la source dans les tableaux. Pour le texte, Roleo change `textCostEUR` en même temps, sinon le Cockpit et le dashboard divergent.
2. Mettre à jour les valeurs attendues de `cout()` dans `FirebaseTests.swift`.
3. Firebase ne réécrit qu'hier et aujourd'hui, sauf trou. Pour recalculer le texte et la voix, supprimer les lignes `cout_texte` du business dans la base : le passage suivant relit 30 jours, pas plus (`aiLoad` n'en garde que 30), et refait `cout_voix` et `cout_ia`.
