# Analyse du script de pêche FiveM (`qs-fishingjob` v3.2.1)

> Support de conception du bot Python `fishing_bot/`. Toutes les références
> pointent vers le code présent dans ce dépôt. Le bot ne modifie **aucun** fichier
> Lua : il reproduit uniquement ce qu'un joueur fait avec son clavier et sa souris.

---

## 1. Architecture de la ressource

| Partie | Rôle |
|---|---|
| `fxmanifest.lua` | Déclare `ui_page 'web/build/index.html'`, charge `config/*.lua` en shared, les scripts client (`client/fishing.lua`, `client/main.lua`, …) et serveur (`server/fishing.lua`, …). Version `3.2.1`, `lua54 'yes'`. |
| `config/config.lua` | Source de vérité : touches, poissons, profondeurs, appâts, cannes, boutique, minijeu. |
| `client/fishing.lua` | Boucle de jeu locale : sonde d'eau, animation, charge du lancer, attente, ferrage, **combat**, modale de décision. Envoie des `SendNUIMessage`. |
| `server/fishing.lua` | Autorité : tirage du poisson, token de lancer, temps d'attente, difficulté, récompenses, casse de canne, XP. Accessible via `lib.callback` (ox_lib). |
| `web/build/assets/index.js` + `index.css` | NUI React : carte de puissance, bouchon + anneau de ferrage, HUD de combat (chevrons, barres), modale Garder/Relâcher, jauge de profondeur. |
| `items_ox.lua` / `items_qs.lua` / `server/framework/*.lua` | Rend les objets `wooden_rod`, `carbon_rod`, …, `fishing_kit` utilisables → déclenchent `toggleFishingRod` / `toggleFishingKit`. |

Le serveur est **autoritatif** : le client ne décide jamais du poisson, du prix ni
de l'XP. Il ne peut que demander un lancer, ferrer, gagner/perdre le combat et
choisir Garder/Relâcher. C'est important pour l'automatisation : appeler les
événements Lua directement serait à la fois invalide (tokens, cooldowns) et hors
sujet. Le bot doit donc passer par les vraies entrées.

---

## 2. Pré-conditions avant le premier lancer

1. **Avoir une canne utilisable.** `server/fishing.lua:826` (`UsableRods`) vérifie
   l'inventaire et le niveau requis (`Config.RodTiers`, `config/config.lua:1684`).
   `wooden_rod` = niveau 1, `carbon_rod` = 3, `composite_rod` = 8,
   `tournament_rod` = 16, `master_rod` = 28.
2. **Équiper la canne** en utilisant l'objet dans l'inventaire →
   `client/fishing.lua:123` `ToggleFishingRod()`. Tant que `Player.rodIsIn ~= "hand"`,
   la boucle principale (`client/fishing.lua:1584`) ne propose rien.
3. **Optionnel : le kit.** `fishing_kit` ouvre la boîte d'attaches
   (`client/fishing.lua:179`). Quatre slots : `bait`, `hook`, `reel`, `line`.
   L'appât est **consommé à chaque prise** (`server/fishing.lua:1042`), les autres
   bonus modifient les odds (`fightEase`, `biteTimeReduction`, `lineStrength`, …).
4. **Être au bon endroit** :
   - face à l'eau, sans nager (`ProbeWater`, `client/fishing.lua:402`) ;
   - pas dans un véhicule, pas à moins de `5.0 m` du PNJ
     (`Config.StartJob.ped.noFishingRadius`, `config/config.lua:248`) ;
   - pas de filet / feu de camp actif ;
   - profondeur ≤ `Config.Depth.Base (12) + 0.9*niveau + 0.35*gear`
     (`server/fishing.lua:372`). Depuis la rive, la profondeur est plafonnée à
     `ShoreDepth = 6.0` ; il faut un bateau pour les bandes `deep` / `abyss`.
   - La jauge de profondeur à droite affiche la bande (`shallow`, `mid`, `deep`,
     `abyss`) et la touche **E** verte quand le lancer est autorisé.

---

## 3. Le cycle complet, étape par étape

### Étape 0 — Jauge de profondeur
`client/fishing.lua:1584` sonde 16 points devant le joueur jusqu'à
`PROBE_MAX_DIST = 5.0 m` (puis jusqu'à la distance de lancer), calcule la
profondeur (`DepthAt`) et affiche `depthMeter`. **Action joueur : aucune**, c'est
le signal « prêt ».

### Étape 1 — Démarrer le lancer : `E`
`IsControlJustPressed(0, 38)` → `StartFishing()` (`client/fishing.lua:1453`) →
`ChargeCastPower()` (`:1354`).

⚠️ `E` doit être **maintenu** pendant la charge : `cancelPressed` est initialisé à
`not IsControlPressed(0, 38)` ; relâcher `E` puis le represser annule le lancer.

### Étape 2 — Charger la puissance : clic gauche maintenu
`ChargeCastPower` envoie `castStart`, attend
`IsDisabledControlJustPressed(0, 24)` (clic gauche), puis calcule :

```
cycle = ((now - startTime) % (2 * 1100)) / 1100
power = cycle            si cycle <= 1     (montée 0 -> 1 en 1,1 s)
      = 2 - cycle        sinon              (descente 1 -> 0 en 1,1 s)
```

`CHARGE_ANIM_DURATION = 1100`, `CAST_MAX_TIME = 6000`
(`client/fishing.lua:328-329`). Relâcher le clic fige `power` (`castEnd`).
`E` peut alors être relâché.

Conséquences de `power` (`config/config.lua:522`, `server/fishing.lua:623-700`) :

| Effet | Formule |
|---|---|
| Distance du bouchon | `6 + 20 * power` mètres (`MinDistance=6`, `MaxDistance=26`) |
| Ticket « rien n'a mordu » | `28 * (1 - 0.45 * power)` → une vieille botte |
| Accès aux poissons rares | `requiredPower = (100 - proba)/100 * 0.6`, sous ce seuil le poids est ×0.18 |
| Taille du spécimen | bonus de puissance dans `RollFishStats` |
| Validation serveur | `power < 0.05` → `CAST_TOO_WEAK` (`server/fishing.lua:832`) |

👉 Cible retenue par le bot : **0.86** (≈ 23,2 m, haut de la phase montante,
marge de ~140 ms avant le pic).

### Étape 3 — Attente de la touche
`StartFishing` joue l'animation `cast` (1500 ms), fait voler le bouchon
(750 ms), puis envoie `biteStart` avec :

```
waitTime = max(1500 ms, rand(5..10 s) * (1 - biteTimeReduction/100))
window   = 3000 ms                      (FishingConfig.BiteWindow)
```

`Config.BiteTime` (`config/config.lua:1795`) = 5 à 10 s, plancher 1,5 s.
Le niveau et la ligne (`biteTimeReduction`) raccourcissent l'attente.

**Pendant `waitTime`, toute pression sur `E` annule la ligne**
(`client/fishing.lua:1530`). Le joueur ne doit surtout pas appuyer trop tôt.

### Étape 4 — Ferrage : `E` dans la fenêtre de 3 s
À l'expiration de `waitTime`, la NUI passe en état `bite` : bouchon qui tangue,
halo cyan, anneau de compte à rebours (3 s), encadré **« Hook it! / E »**
(`web/build/assets/index.js`, handler `biteStart` ; CSS `_wrap_1k7mm_1`,
`_ringFill_1k7mm_146`, `_key_1k7mm_178`).

Une seule pression sur `E` dans les 3000 ms → `hooked = true`. Sinon :
`ResolveCatch(token, false)` → perte, consommation d'appât, risque de casse.
Après 300 ms, `StartFishingFight()` démarre.

### Étape 5 — Le combat (le seul vrai mini-jeu)
`client/fishing.lua:1174`. **Aucune touche n'est lue** (sauf `ESC` = control 200
qui annule). Le client calcule à chaque frame :

```
angle = normalize( atan2(bobber - ped) - camRot ) - 90°   (degrés)
side  = "center"  si |angle| <= 8°   (DeadZone)
      = "right"   si angle > 8°
      = "left"    si angle < -8°

# premier côté hors centre :
targetSide = opposé(side)          # <<< piège classique

isPullingCorrectly = (side == targetSide)
tension += (|angle| / maxAngle) * 0.01   si correct
targetSide bascule quand tension >= rand(0.5..1.0) / turnRate

distance -= (|angle| / maxAngle) * pullSpeed   si correct
distance += slipSpeed                          sinon
danger   = |angle| / maxAngle * 100
si |angle| > maxAngle  ->  ligne cassée immédiatement
```

`maxAngle`, `pullSpeed`, `slipSpeed`, `turnRate` viennent du serveur
(`BuildFightParameters`, `server/fishing.lua:753`) :

```
difficulty   = clamp(Tiers[bande] + 0.15*qualité, 0, 1) * (1 - fightEase/100)
maxAngle     = 70 * (1 + lineStrength/100) * (1 - 0.35*difficulty)
pullSpeed    = 0.025 * (1 - 0.45*difficulty)
slipSpeed    = 0.005 * (1 + 1.2*difficulty)
turnRate     = 1 + 0.5*difficulty
```

`Tiers` (`config/config.lua:1820`) : shallow 0.10, mid 0.35, deep 0.65, abyss 0.90.
Donc un poisson abyssal dur a `maxAngle ≈ 70 * (1 - 0.315) ≈ 48°`.

**Ce que fait réellement le joueur** : tourner la caméra avec la souris (ou se
déplacer latéralement) pour que le bouchon soit du côté indiqué par les chevrons
lumineux `#7dd3fc` (`_cueOn_1te5d_69`), tout en gardant `danger` sous ~82 %
(seuil rouge de la NUI) pour ne pas casser la ligne. La barre bleue
« Reel progress » monte quand le côté est correct ; la barre de tension indique
`|angle|/maxAngle`. Quand le chevron change de côté, il faut repasser de l'autre
côté en traversant la zone morte de 8°.

Le HUD est en bas au centre : `_wrap_1te5d_1` (`bottom:8%`, largeur 620 px),
chevrons au-dessus, deux barres dans `_panel_1te5d_104`.

### Étape 6 — Résolution serveur
`ResolveCatch` (`client/fishing.lua:1139`) appelle
`qs-fisher:resolveCatch` (`server/fishing.lua:1013`) avec le token. Le serveur
vérifie `now >= readyAt`, consomme l'appât (sauf `baitSaver`), applique la casse
de canne en cas d'échec (10 % de base, ou `RodTiers[].breakChance`), tire les
poids/tailles, puis renvoie soit `garbage` (botte), soit `decide: true`.

### Étape 7 — Garder ou Relâcher
`OpenCatchDecisionModal` (`client/fishing.lua:1093`) ouvre la modale à droite
(`_overlay_dxhav_14`, `justify-content:flex-end`, `zoom:1.4`, ~644×503 px) avec
deux boutons. `Config.CatchDecision` (`config/config.lua:541`) :

| Choix | Résultat |
|---|---|
| **Keep** | objet dans l'inventaire, XP × 1.0 |
| **Release** | pas d'objet, XP × 1.75 (× 1.5 si trophée), compte quand même pour les records |
| Timeout 9000 ms | `TimeoutKeeps = true` → gardé automatiquement |

Le clic envoie le callback NUI `decideCatch` → `qs-fisher:decideCatch`
(`server/fishing.lua:1157`). Il n'y a **pas de raccourci clavier** dans la NUI :
il faut cliquer.

### Étape 8 — Boucle / logistique
- Cooldown serveur : `lastCastTime` 1500 ms (`server/fishing.lua:868`).
- Vente des poissons au PNJ `Old Pete` (`config/config.lua:248`) ou via la
  boutique ; rachat d'appâts / cannes.
- L'appât part à chaque prise ; la canne peut casser → il faut la rééquiper.

---

## 4. Ce que le serveur empêche naturellement

| Garde-fou | Emplacement |
|---|---|
| Token unique par lancer + `activeCasts[src]` | `server/fishing.lua:879`, `:1017` |
| `now >= readyAt` (impossible de résoudre avant la touche) | `:1021` |
| Cooldown 1500 ms entre deux lancers | `:868` |
| Un seul lancer actif, profondeur autorisée, canne présente | `:804` |
| Appât retiré de l'inventaire, `gearChanged` si épuisé | `:1042` |
| Décision liée au token, expiration + 2500 ms | `:1135`, `:1147` |

👉 Un bot fiable ne peut pas « forcer » ces étapes : il doit respecter le rythme
du jeu. C'est exactement ce que fait la machine à états.

---

## 5. Cartographie « action joueur → automatisation »

| Étape | Signal écran détecté | Entrée simulée |
|---|---|---|
| Prêt | touche **E** verte de la jauge de profondeur (`#4ade80`) | — |
| Lancer | carte `Cast power` à `left:60%` | `keyDown(E)` |
| Charge | remplissage coloré de la piste 28×200 px | `mouseDown(left)` pendant `0.86 × 1100 = 946 ms`, puis `mouseUp` |
| Verrouillage | carte `locked` 700 ms | lecture de la puissance → correction adaptative du timing |
| Attente | bouchon + texte « waiting », **pas** d'anneau | aucune touche (garde-fou 1 s) |
| Ferrage | anneau cyan `#38bdf8` + encadré `E`, 2 frames consécutives | `press(E)` (60 ms) |
| Combat | HUD bas-centre, chevrons `#7dd3fc`, barre bleue | `moveRel(±10 px)` en boucle fermée, pause si `danger_high` |
| Décision | modale sombre à droite + icône cyan/verte | `click(Garder)` ou `click(Relâcher)` |
| Récupération | UI disparue | `release_all()`, attente 1700 ms, puis cycle suivant |
| Canne cassée / absente | jauge absente > 5 s | `actions.equip` (séquence inventaire configurable) |
| Appâts / revente | tous les N cycles | `actions.resupply` / `actions.sell` configurables |

### Pourquoi cette approche est précise

1. **Timing déterministe** pour la charge : le triangle 0→1→0 est connu au
   millième ; le bot vise 0.86 sur la montée (jamais sur la descente).
2. **Lecture optique de contrôle** : après relâche, la carte reste 700 ms en
   `locked` ; le bot mesure la puissance réelle et corrige
   `cast.hold_offset_ms` d'un cast à l'autre (dérive d'horloge, latence SendInput).
3. **Ferrage par vision, pas par minuteur** : l'attente est aléatoire (5–10 s)
   et raccourcie par le niveau/équipement ; seul l'anneau cyan fait foi.
   Hystérésis de 2 frames pour éviter un faux positif.
4. **Combat en boucle fermée** : le sens souris ↔ angle est déduit du premier
   chevron (le code Lua initialise `targetSide` au côté opposé), puis confirmé
   par la progression de la barre bleue. Si la progression s'arrête, inversion
   après `stall_flip_s`. La pause sur `danger_high` évite de dépasser
   `maxAngle`. Aucune hypothèse sur la sensibilité/inversion de la souris.
5. **Watchdogs partout** : timeout de ferrage, de combat, de modale, série
   d'échecs, touche F12, vérification du focus Windows, `release_all()` dans le
   `finally`. Les outcomes ambigus (botte, `CatchDecision.Enabled=false`) ne
   sont pas comptés comme échecs.
6. **Tests de régression** : `python -m fishing_bot --selftest` et `pytest`
   valident 31 détecteurs sur des images synthétiques conformes au CSS.

---

## 6. Limites connues

- Le bot ne **pilote pas le trajet jusqu'au spot** : il faut être positionné face
  à l'eau (ou sur un bateau) et, pour les bandes profondes, avoir rejoint le
  large. Pendant le combat, l'actionneur `strafe` peut en revanche faire quelques
  pas latéraux si la souris n'est pas acceptée par le jeu.
- Les séquences d'inventaire / boutique dépendent du framework (`ox_inventory`,
  `qs-inventory`, ESX, QB). Elles sont décrites par des `actions` JSON à calibrer
  une fois (voir `README.md`), pas devinées.
- La NUI doit être à l'échelle standard ; `--calibrate cast` mesure `ui.scale`
  si le serveur ou Windows applique un zoom.
- Si GTA ignore les déplacements souris envoyés par `SendInput` (pilote /
  raw input particulier), passer `--actuator strafe` (touches A/D) garde le même
  asservissement.
- Le bot ne lit pas l'audio (`info.mp3`, `warning.mp3`) : tout est visuel.

---

## 7. Cadre d'utilisation ⚠️

FiveM est un jeu multijoueur en ligne. L'automatisation d'une activité qui
rapporte de l'argent et de l'XP peut être interdite par les règles du serveur,
par les conditions d'utilisation de FiveM / Rockstar et détectée par un
anti-cheat. **N'utilisez ce script que sur votre propre serveur privé, en test,
ou avec l'accord explicite du propriétaire du serveur.** Ce dépôt ne fournit
aucun contournement d'anti-cheat, aucune lecture mémoire, aucune injection dans
le processus du jeu et aucun envoi d'événement réseau : uniquement des entrées
clavier/souris et de la lecture d'écran. L'utilisateur reste seul responsable
du respect des règles applicables.
