# Tester fishbot sur ta machine

Windows, Python 3.9 ou plus. Rien d'autre à installer que numpy.

Tout se lance **depuis `tools/fishbot`** (sinon `import fishbot` ne trouve rien).

```powershell
cd tools\fishbot
pip install -r requirements.txt
```

---

## Étape 0 — ça tourne sans le jeu (30 s)

```powershell
python -m fishbot.run --simulate
```

Ça n'ouvre pas GTA, ne touche ni la souris ni le clavier : le programme joue
contre un faux HUD et affiche ce qu'il ferait. Tu dois voir la fenêtre trouvée,
puis le statut toutes les 3 s. `F10` ou `Ctrl-C` pour arrêter.

Si cette étape marche, le Python, numpy et la boucle sont bons. Si elle casse,
le problème n'est pas le jeu.

## Étape 1 — il voit bien le jeu (`--probe`)

Lance FiveM, **rod en main, face à l'eau**, puis :

```powershell
python -m fishbot.run --probe
```

Tu obtiens la fenêtre trouvée et un relevé du HUD. Ce qu'il faut voir :

| ligne | attendu face à l'eau |
| --- | --- |
| `window` | `client=1920x1080 ... -> exclusive fullscreen` ou `windowed / borderless` |
| `cast gate` | `ready` (clé verte) — c'est ce qui autorise le lancer |
| les autres | `present=False` quand rien ne se passe (pas de faux positif) |

Si `window` échoue → `--window-title "FiveM"` (ou le titre exact).
Si tout est `no card` alors que tu es bien face à l'eau → passe à l'étape 2.

## Étape 2 — la calibration visuelle (`--snapshot`)

```powershell
python -m fishbot.run --snapshot
```

Ça écrit `fishbot-snapshot.png` : ta capture réelle avec **toutes les zones que
le bot lit** entourées. Ouvre l'image et vérifie que les rectangles tombent sur
les éléments du HUD (barre de tension, flèches, carte de profondeur, etc.).

- Si les rectangles sont **décalés** → dis-le moi avec l'image, c'est un
  problème de géométrie (le seul truc que je ne peux pas vérifier sans ton jeu).
- Si l'image est **toute noire** → exclusive fullscreen : passe le jeu en
  *borderless* (le bot te le dira aussi lui-même).
- Si elle est noire seulement avec `printwindow` → essaie `--capture bitblt`.

## Étape 3 — il joue mais ne touche à rien (`--dry-run`)

```powershell
python -m fishbot.run --dry-run --hz 10
```

Là il lit vraiment ton écran et prend toutes ses décisions, **sans envoyer un
seul clic ni une seule touche**. Lance un vrai lancer de ligne à la main et
regarde les messages : il doit annoncer `cast #1`, `bite - striking`,
`hooked - reeling`, `kept the fish` au bon moment.

C'est l'étape qui valide tout sans risque. Si les messages tombent juste, tu peux
passer à la suite.

## Étape 4 — le vrai test (commence petit)

```powershell
python -m fishbot.run --once 3
```

Garde le jeu **au premier plan** (sinon il refuse d'envoyer l'input, exprès).

1. Il s'arme et affiche `armed. Press F9 to start fishing.`
2. `F9` → il commence.
3. Regarde les 3 premiers poissons.
4. `F10` pour arrêter, ou `Ctrl-C`.

Si un combat part en vrille, `F11` met en pause immédiatement.

### Les touches

| touche | effet |
| --- | --- |
| `F9` | démarrer / reprendre après une pause |
| `F10` | stop |
| `F11` | pause (et c'est aussi ce qu'il fait tout seul si le sac est plein) |

### Ce qui doit arriver

- Il ne lance **que** quand la clé `E` du HUD est verte.
- Pendant un combat il ne touche **que** la souris (la caméra), jamais le clavier.
- Il clique `KEEP`, jamais `RELEASE`.
- Sac plein → il bipe, s'arrête, et attend. Tu vides le sac, `F9`, il repart.

---

## Si ça ne va pas, ce que je veux savoir

Copie-moi la sortie console (elle dit déjà beaucoup) et, si c'est visuel,
`fishbot-snapshot.png`. Les trois cas les plus utiles :

| symptôme | ce que ça veut dire |
| --- | --- |
| `cannot cast: the game's cast prompt is blocked` | il voit bien la clé grise : problème de position/depth côté jeu, pas du bot |
| `no reeling HUD after the strike` | le ferrrage rate, ou le HUD du combat n'est pas lu |
| `fight timed out` | le contrôleur ne progresse pas : mauvais mapping souris/sensibilité |

Ce dernier cas est réglable sans moi : `--sensitivity` fixe le point de départ
(en counts par pourcent de tension ; il s'auto-calibre ensuite et s'en souvient
dans `~/.fishbot/settings.json`). Si les combats sont systématiquement perdus,
essaie `--sensitivity 0.8` puis `--sensitivity 3`, et regarde lequel tient.

## Les tests automatiques (facultatif)

```powershell
python -m tests.test_vision      # la lecture du HUD
python -m tests.test_fight       # le combat simulé
python -m tests.test_e2e         # le bot complet contre un faux client
python -m tests.test_cli         # réglages, snapshot, démarrage
python -m tests.test_capture     # capture Win32 sur un faux GDI
```
