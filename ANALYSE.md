# Analyse du script `fiiiiish` et du processus joueur

> Ressource FiveM « Quasar Fisher Job » (`qs-fisher`, dossier `fiiiiish`).
> Client Lua + serveur Lua + interface NUI (React) + base MySQL.

## 1. Ce que fait la ressource

La ressource ajoute un métier de pêche complet :

| Fichier | Rôle |
|---|---|
| `client/fishing.lua` | tout le mini-jeu : lancer, attente, touche, combat, décision |
| `server/fishing.lua` | tirage du poisson, difficulté, récompenses, inventaire, XP |
| `config/config.lua` | toutes les valeurs réglables (puissance, profondeur, appâts, cannes, difficulté) |
| `web/build/` | interface NUI : jauge de profondeur, jauge de lancer, écran de touche, HUD de combat, modal garder/relâcher |
| `client/main.lua` | PNJ de départ, panneau de métier, boutique, statistiques |
| `client/shop.lua` | achat/vente via la NUI |
| `server/schema.lua` | tables MySQL (records, stocks, tournois…) |

Le joueur interagit avec le PNJ (`Config.StartJob` dans `config/config.lua:248`, PNJ créé dans `client/main.lua:248`), puis avec l'eau.
Le cœur du jeu est le combat à la ligne (`client/fishing.lua:1174`), et c'est ce que le script Python automatise.

## 2. Le processus que le joueur doit faire, de A à Z

### Étape 0 — préparation (une seule fois)

1. **Parler au PNJ** aux coordonnées `-1590.55, 5207.95, 4.0` (marker flottant, `Config.PedMarker`).
   Le panneau de métier s'ouvre (`OpenPartyMenu`) : missions, équipage, statistiques, boutique.
2. **Acheter une canne** (`Config.RodTiers`, `config/config.lua:1684`) :
   `wooden_rod` 20 $ (niv. 1), `carbon_rod` 120 $ (niv. 3), `composite_rod` 350 $ (niv. 8),
   `tournament_rod` 700 $ (niv. 16), `master_rod` 1500 $ (niv. 28).
3. **Acheter des appâts** (`Config.FishingAttachments`) : `earthworms`, `crickets`, `leech`, `shrimp`, etc.
   Chaque poisson a un appât favori (multiplicateur de poids 3,4), mais aucun appât n'est obligatoire.
4. **Équiper la canne et les accessoires** dans la boîte à pêche (tackle box) : 4 slots
   `bait`, `hook`, `reel`, `line`. Les bonus utiles sont `fightEase` (difficulté du combat),
   `lineStrength` (angle avant rupture), `biteTimeReduction` (attente avant la touche),
   `extraCatchChance`, `specimenSize`, `rodDurability`, `baitSaver`.

### Étape 1 — se placer devant l'eau

Le joueur doit être **debout, face à l'eau, sans véhicule, sans filet, sans feu de camp,
et à plus de 5 m du PNJ** (`noFishingRadius`). La jauge de profondeur NUI apparaît quand la
canne est en main : elle affiche la profondeur, la bande (`shallow`, `mid`, `deep`, `abyss`)
et le prompt `START_FISHING` avec la touche `E`.

### Étape 2 — lancer

1. Le joueur appuie sur **E** (`Config.Keys.InteractKey = 38`). Le client sonde l'eau
   (`ProbeWater`) puis lance `ChargeCastPower` (`client/fishing.lua:1354`).
2. La jauge de puissance NUI apparaît. Le joueur **maintient le clic gauche** : la puissance
   monte et descend en triangle (1,1 s par montée, 6 s max). Il **relâche** à la puissance voulue.
3. La puissance (0–100 %) décide de la distance (`6 + 20 × power` mètres), des chances de
   touche, de la taille du poisson et des poissons accessibles.
4. Le serveur valide (`beginCast`, `server/fishing.lua:804`) : profondeur, canne, niveau,
   anti-spam 1,5 s, puissance minimale 5 %. Il renvoie un `token`, le temps d'attente,
   la distance et les paramètres du combat.

### Étape 3 — attendre la touche

Le serveur tire un temps d'attente entre **5 et 10 s** (`Config.BiteTime`), réduit par les
bonus (plancher 1,5 s). La NUI passe en état « waiting ». **Il ne faut pas appuyer sur E**
pendant l'attente : cela annulerait le lancer (`CAST_CANCELLED`).

### Étape 4 — ferrer

À la touche, la NUI passe en état « bite » pendant **3 s** (`FishingConfig.BiteWindow`).
Le joueur appuie sur **E** dans cette fenêtre. S'il ne le fait pas, le poisson s'échappe.
S'il appuie trop tôt, le lancer est annulé.

### Étape 5 — le combat (le cœur du mini-jeu)

La NUI affiche trois choses :

- **progress** : 0 → 100 %, la distance restante ;
- **danger** : 0 → 100 %, l'angle de la ligne par rapport à la limite ;
- **side** : `left` / `right`, le côté où il faut tirer (chevrons + label `PULL_THIS_WAY`).

Le joueur doit **tourner la caméra** pour placer le flotteur du côté demandé, en restant
dans la limite d'angle. Le code exact (`client/fishing.lua:1174`) :

```
angle   = GetAngleDelta()                  # signé, en degrés
danger  = floor(|angle| / maxAngle * 100)
side    = right si angle > 8°, left si angle < -8°, sinon center
target  = côté opposé au premier côté joué (une seule fois)
tension += (|angle| / maxAngle) * 0.01     # par frame, si on tire du bon côté
si tension >= randomDuration (0.5–1.0 / turnRate) -> target bascule
distance -= (|angle| / maxAngle) * pullSpeed   # bon côté
distance += slipSpeed                          # mauvais côté
progress = (initial - distance) / (initial - 2)
```

- **Rupture** si `|angle| > maxAngle` (le danger affiché est alors > 100).
- **Annulation** si le joueur appuie sur **Échap**.
- **Succès** quand `progress >= 1` (le flotteur est ramené à 2 m).

Les paramètres viennent du serveur (`BuildFightParameters`, `server/fishing.lua:779`) :

```
maxAngle  = 70 * (1 + lineStrength/100) * (1 - 0.35 * difficulty)
pullSpeed = 0.025 * (1 - 0.45 * difficulty)
slipSpeed = 0.005 * (1 + 1.2 * difficulty)
turnRate  = 1 + 0.5 * difficulty
```

La difficulté dépend de la **bande de profondeur** et de la **qualité du spécimen**,
réduite par le bonus `fightEase` (plafonné à 40 %) :

| Bande | Difficulté de base |
|---|---|
| `shallow` | 0,10 |
| `mid` | 0,35 |
| `deep` | 0,65 |
| `abyss` | 0,90 |

`difficulty = (tier + qualité × 0,15) × (1 - fightEase/100)`.

### Étape 6 — garder ou relâcher

La NUI ouvre une modale avec le poisson, son poids, sa qualité, et deux boutons
**KEEP_FISH** / **RELEASE_FISH**. Le joueur a **9 s** (`Config.CatchDecision.Timeout`) ;
sans action, le serveur garde le poisson. Relâcher donne plus d'XP (×1,75, et ×1,5 pour un
trophée) mais ne met pas le poisson dans l'inventaire.

### Étape 7 — recommencer

Le joueur vend ses poissons à la boutique, gagne de l'XP, débloque de meilleures cannes et
accessoires, et repart. La boucle complète est : ** PNJ → boutique → eau → E → clic gauche →
attente → E → caméra → garder/relâcher → vente**.

## 3. Le point délicat : le retard de la NUI

La NUI ne reçoit pas l'angle réel. Le client envoie `fishingStatus` **toutes les 50 ms**
(20 Hz) avec `progress`, `danger` et `side`. React lisse ensuite ces valeurs à chaque frame :

```
progress_lissé += (progress_brut - progress_lissé) * (1 - exp(-9 * dt))
danger_lissé   += (danger_brut   - danger_lissé)   * (1 - exp(-16 * dt))
```

Conséquence : quand la caméra tourne vite, le danger affiché **traîne** derrière l'angle réel.
Un bot qui lit le danger affiché et qui traverse à 180°/s peut casser la ligne alors que le
danger affiché n'est que de 70 %. C'est exactement le piège qui rend un bot naïf instable.

## 4. La solution Python

### 4.1 Le simulateur ( testable sans jeu )

`fiiiiish_auto/` reproduit fidèlement :

- `fight.py` : le moteur du combat (mêmes formules, même dead zone, même tension, même
  distance, même succès/rupture), le modèle de caméra et le filtre NUI (9/s et 16/s, 20 Hz).
- `controller.py` : le contrôleur automatique. Il ne voit **que** ce que le joueur voit
  (`danger`, `progress`, `side`) et renvoie un pas de caméra en degrés.
- `fishing.py` : la boucle complète lancer → attente → touche → combat → décision.
- `loop.py` : le câblage moteur/caméra/NUI/contrôleur à pas fixe (60 Hz, 30 Hz de contrôle).

Le contrôleur :

1. **trigger** : tant que la NUI n'a pas donné de côté, il avance de 2°/tick pour révéler
   le premier côté (le jeu assigne alors le côté opposé).
2. **cross** : quand le côté demandé change, il traverse à 6°/tick (180°/s) jusqu'à ce que
   le danger lissé reparte à la hausse après son minimum : il a traversé le centre.
3. **hold** : il se stabilise à **75 %** du budget d'angle avec un pas lent de 2,5°/tick
   (75°/s) et une zone morte de 3 points. Le danger réel reste sous ~79 %.
4. **safety** : au-dessus de 92 %, il revient vers le centre.
5. **reaction delay** : 50 ms de retard sur les changements de côté, pour ne pas se croire
   plus rapide qu'il ne l'est.

### 4.2 Les résultats du simulateur

Sur 40 courses par configuration, sans aucun échec :

| Bande | Puissance | Réussite | Combat moyen | Danger max |
|---|---|---|---|---|
| shallow | 0,2 | 100 % | 11,4 s | 76 |
| shallow | 0,5 | 100 % | 19,9 s | 76 |
| shallow | 0,8 | 100 % | 28,3 s | 76 |
| mid | 0,2 | 100 % | 13,3 s | 76 |
| mid | 0,5 | 100 % | 23,4 s | 76 |
| mid | 0,8 | 100 % | 33,4 s | 76 |
| deep | 0,2 | 100 % | 17,1 s | 78 |
| deep | 0,5 | 100 % | 30,2 s | 78 |
| deep | 0,8 | 100 % | 43,3 s | 78 |
| abyss | 0,2 | 100 % | 22,4 s | 79 |
| abyss | 0,5 | 100 % | 39,4 s | 79 |
| abyss | 0,8 | 100 % | 56,4 s | 79 |

Le contrôleur reste à 100 % de réussite avec une cadence de 15, 20 ou 30 Hz et un retard
de 0,05 à 0,15 s. Le danger maximal observé est de 79 %, soit une marge de 21 points avant
la rupture. Le combat est plus long en eau profonde et à forte puissance : c'est le prix de
la fiabilité. Pour un bot plus rapide, on peut baisser la puissance (0,2 → 10 m) au prix de
poissons plus petits / moins profonds.

### 4.3 Le bot live (Windows + FiveM)

`live.py` utilise le même contrôleur, mais remplace les deux adaptateurs :

- `nui.py` lit la vraie NUI via le **DevTools Protocol de CEF** (`http://127.0.0.1:13172`).
  Il récupère les valeurs exactes : `progress`, `danger`, `side`, l'état de la jauge de
  lancer, l'état de la touche, la modale de décision et le prompt `START_FISHING`.
  C'est beaucoup plus fiable que de l'OCR.
- `input.py` envoie des **mouvements relatifs de souris** via `SendInput` (la même API que
  pydirectinput), un clic gauche pour charger le lancer, et la touche E pour ferrer.

Le bot automatise :

1. **le lancer** : E, maintien du clic gauche, relâchement à la puissance configurée
   (50 % par défaut) ;
2. **la touche** : il attend l'état « bite » et appuie sur E dans la fenêtre de 3 s ;
3. **le combat** : le contrôleur ci-dessus, à 30 Hz ;
4. **la décision** : il clique sur « Keep » (sinon le timeout de 9 s garde le poisson).

Le joueur doit seulement : être au bord de l'eau, canne en main, appât/équipement en place,
et face à l'eau. Le bot appuie sur E dès que la jauge de profondeur affiche `START_FISHING`.

### 4.4 Limites et précautions

- **Windows uniquement** pour le live (SendInput). Le simulateur marche partout.
- Le bot ne déplace pas le personnage et n'équipe pas le matériel : c'est le rôle du joueur.
- La sensibilité souris dépend des réglages du jeu (0,10°/pixel par défaut). Le contrôleur
  est en boucle fermée, donc une valeur approximative suffit, mais `--sensitivity` permet
  de l'ajuster. Désactiver « Enhanced Pointer Precision » dans Windows aide à la régularité.
- Le bot doit tourner avec **le jeu au premier plan** et la fenêtre FiveM active. Il s'arrête
  si le jeu perd le focus, si F10 est pressé, ou si la NUI disparaît.
- Le bot ne peut pas contourner les vérifications serveur (profondeur, canne, niveau, cooldown).
- Sur un serveur multijoueur, l'automatisation peut être contraire au règlement. À utiliser
  pour du test, de l'accessibilité ou avec l'accord du serveur.

## 5. Fichiers du projet

```
fiiiiish_auto/
  config.py       constantes Lua + paramètres du bot
  rng.py          RNG déterministe
  fight.py        moteur du combat, caméra, filtre NUI
  controller.py   contrôleur (trigger / cross / hold / safety)
  loop.py         session de combat à pas fixe
  fishing.py      boucle complète + agrégation
  nui.py          lecture de la vraie NUI via CDP
  input.py        SendInput Windows + mode dry-run
  live.py         bot live
  cli.py          simulate / fight / replay / doctor / live
tests/            50 tests unitaires (moteur, contrôleur, boucle, CLI, adaptateurs)
ANALYSE.md        ce document
README.md         guide d'utilisation
```
