# Emergency Response Simulator — documentation

**Version 0.3.0 — Phase 2 (réseau routier et catalogues enrichis).**

ERS est une simulation française de commandement des secours sur Roblox :
réception des alertes, composition des équipages, engagement des engins,
gestion du budget, du matériel et des postes en coopération.

Le jeu est **autoritaire côté serveur** : le client n'envoie que des intentions
et affiche des snapshots. Aucun asset propriétaire n'est utilisé : la ville et
la scène sont entièrement générées en code.

## Sommaire

| Document | Contenu |
| --- | --- |
| [Architecture.md](Architecture.md) | couches, services, frontière client/serveur, réseau, tests |
| [Gameplay.md](Gameplay.md) | boucle de jeu, alertes, équipages, économie, rôles |
| [DataModel.md](DataModel.md) | structure du monde, snapshots, sauvegarde, invariants |
| [Changelog.md](Changelog.md) | historique des versions |
| [Comparaison-EM4-CSPIRG.md](Comparaison-EM4-CSPIRG.md) | écarts avec Emergency 4 / MOD CSP-IRG et problèmes constatés |
| `../AGENTS.md` | contrat de développement (règles non négociables) |

## Prérequis

| Outil | Version vérifiée | État |
| --- | --- | --- |
| Roblox Studio | installé sur la machine | présent |
| Rojo | 7.7.1 (`%APPDATA%\npm\rojo.cmd`) | présent |
| CLI Luau | `luau.exe` dans `%LOCALAPPDATA%\Temp\opencode\luau` | présent (tests hors Studio) |
| Node.js / npm | présents | présents |
| Git | — | **absent** (voir plus bas) |

Installation reproductible :

```powershell
# Rojo (si absent)
npm install -g rojo@7.7.1

# CLI Luau : télécharger la release Windows et placer luau.exe dans
#   %LOCALAPPDATA%\Temp\opencode\luau
# https://github.com/luau-lang/luau/releases

# Git (non effectué pendant la Phase 0)
winget install --id Git.Git -e
```

## Construire et lancer

```powershell
# 1. Vérifier le code et les tests (obligatoire avant toute phase terminée)
powershell -ExecutionPolicy Bypass -File tools\check.ps1

# 2. Construire la place
& "$env:APPDATA\npm\rojo.cmd" build -o build\ERS.rbxlx

# 3. Ouvrir build\ERS.rbxlx dans Roblox Studio, puis F5 (Play)
```

Variante live :

```powershell
& "$env:APPDATA\npm\rojo.cmd" serve
# puis, dans Studio : plugin Rojo → Connect → default.project.json
```

> Le build est produit par Rojo, jamais par « Save to file » de Studio : c'est
> ce qui garantit que `build\ERS.rbxlx` correspond exactement aux sources.

## Vérification attendue

`tools\check.ps1` compile tous les fichiers Luau puis exécute quatre suites.

```text
Compilation : 62 fichier(s), 0 erreur(s)
== tests/Unit/spec.luau ==            Unitaires    : 124 réussite(s), 0 échec(s)
== tests/Integration/sim.luau ==      Intégration  : 167 réussite(s), 0 échec(s)
== tests/Multiplayer/permissions.luau == Multijoueur : 67 réussite(s), 0 échec(s)
== tests/UI/ui.luau ==                Interface    : 251 réussite(s), 0 échec(s)
OK
```

Total : **609 assertions**, 0 échec. Le script sort en erreur (code non nul) au
premier échec.

## Commandes en jeu

| Touche | Effet |
| --- | --- |
| `1` … `7` | sélectionne le groupe tactique s'il existe, sinon ouvre le panneau (Interventions, Véhicules, Personnel, Matériel, Commandement, Budget, Postes) |
| `WASD` / flèches | déplace la caméra |
| `+` / `-` | zoome / dézoome |
| `Q` / `E` | pivote la caméra par quarts de tour |
| `Espace` | pause / reprise de la simulation (validée par le serveur) |
| `R` | recentre la caméra sur la caserne |
| `M` | ouvre le menu principal (le bouton **Menu** fait la même chose) |
| `Échap` | réservé au menu Roblox : l'interface ne l'intercepte pas |
| `Ctrl+S` | demande une sauvegarde (si le poste y a droit) ; `S` seul déplace la caméra |
| Molette | zoom |
| Clic sur la mini-carte | sélectionne une urgence ou un engin, ouvre le panneau et braque la caméra |
| Double-clic | recentre sur l'unité sélectionnée |

## Arborescence

```text
EmergencyResponseSimulator/
├─ AGENTS.md                  contrat de développement
├─ default.project.json       mapping Rojo
├─ opencode.json              configuration de l'agent
├─ build/ERS.rbxlx            place générée (Phase 2)
├─ docs/                      cette documentation
├─ data/                      organisation cible des données exportées
├─ assets/                    organisation cible des assets originaux
├─ src/
│  ├─ ReplicatedStorage/
│  │  ├─ Shared/              Config, Constants, Types, City, Utilities, Catalogs
│  │  │  └─ Utilities/        Result, MathX, Rng, TimeUtil, Crew, Navigation, RoadNetwork, Operations
│  │  └─ Remotes/             (créé par le serveur au démarrage)
│  ├─ ServerScriptService/
│  │  ├─ Bootstrap.server.luau
│  │  └─ Services/            15 services serveur
│  └─ StarterPlayer/StarterPlayerScripts/
│     ├─ Bootstrap.client.luau
│     ├─ Controllers/         5 contrôleurs (interface, réseau, caméra, entrées, audio)
│     └─ UI/                  thème, widgets, mini-carte, barre, scène, 7 panneaux, menu
├─ tests/
│  ├─ __env.luau, __prelude.luau, __stubs.luau
│  └─ Unit/ Integration/ Multiplayer/ UI/
└─ tools/check.ps1            compilation + 4 suites
```

Détail des fichiers et des dépendances : [Architecture.md](Architecture.md).

## Limites connues de la Phase 2

1. **Git n'est pas installé.** `.gitignore` est prêt, mais aucun dépôt ni
   historique n'existe encore. À faire avant la phase suivante.
2. **Interface vérifiée dans Studio.** Des sessions F5 sur `build/ERS.rbxlx` ont
   validé le menu, la barre d'état, les sept onglets, la mini-carte, les
   couches, la barre inférieure, le tiroir en deux colonnes, le journal et les
   notifications. Les défauts trouvés à ces occasions sont corrigés et listés
   dans [Changelog.md](Changelog.md). La lisibilité fine (petites polices,
   9–10 px) reste à confirmer sur d'autres résolutions.
3. **DataStore hors ligne.** Dans Studio sans connexion, le `DataStoreService`
   peut échouer : le serveur bascule sur un stockage mémoire, journalisé, sans
   bloquer la partie.
4. **Trajets routés, ville générée.** La ville reste une grille déterministe de
   dix routes et seize îlots, avec caserne, cinq points d'intérêt et deux
   espaces publics. Depuis la Phase 2, les engins suivent le **réseau routier**
   (`Shared/Utilities/RoadNetwork`) : graphe de 25 carrefours et 40 tronçons
   construit depuis `Shared/City`, plus court chemin Dijkstra déterministe et
   polyligne de trajet. Les modèles 3D détaillés et la circulation restent en
   Phase 3.
5. **Pas de publication.** Aucune action `Publish to Roblox` a été effectuée
   et ne doit l'être sans décision explicite.
