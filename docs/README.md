# Emergency Response Simulator — documentation

**Version locale 0.4.0 — interventions de terrain, missions et progression.**

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

## Construire et tester

Les exécutables portables utilisés pour cette version sont Luau 0.748 et Rojo 7.7.1. Depuis la racine du dépôt, lancez les commandes suivantes dans PowerShell.

```powershell
.\tools\check.ps1
New-Item -Type Directory -Force build | Out-Null
& "$env:LOCALAPPDATA\Temp\opencode\rojo\rojo.exe" build -o build\ERS.rbxlx
```

Le fichier local `build/ERS.rbxlx` s’ouvre dans Roblox Studio. Utilisez **F5** pour lancer la partie, puis **8** pour choisir une mission au poste Direction ou Commandement.

## Vérifications locales

Le contrôle de syntaxe couvre 75 fichiers Luau. Les quatre suites totalisent **1 082 assertions réussies**.

| Suite | Assertions |
| --- | ---: |
| Unitaire | 124 |
| Intégration | 267 |
| Multijoueur | 85 |
| Interface | 606 |

Les tests déroulent les trois missions, les navettes vers l’hôpital et le passage de 19 h à 21 h. Ils mesurent le HUD en 1024 × 768, 1280 × 720, 1920 × 1080 et 2560 × 1440. Dans Roblox Studio, la mission de l’église a été menée jusqu’à l’admission d’une victime. Le crépuscule et le HUD corrigé ont été observés en partie. À 21 h, la sonde comptait 60 lampadaires et 334 vitres allumés. Le client a mesuré un signal en sortie de la radio et pendant la lecture de la sirène.

## Commandes en jeu

| Touche | Effet |
| --- | --- |
| `1` … `7` | sélectionne le groupe tactique s'il existe, sinon ouvre le panneau (Interventions, Flotte, Personnel, Matériel, Commandement, Achats et finances, Postes) |
| `8` | ouvre les missions, les objectifs et le bulletin de service |
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
├─ build/ERS.rbxlx            place locale générée par Rojo
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
│  │  └─ Services/            simulation, réseau, sauvegarde et scène
│  └─ StarterPlayer/StarterPlayerScripts/
│     ├─ Bootstrap.client.luau
│     ├─ Controllers/         5 contrôleurs (interface, réseau, caméra, entrées, audio)
│     └─ UI/                  thème, widgets, mini-carte, barre, scène, 8 panneaux, menu
├─ tests/
│  ├─ __env.luau, __prelude.luau, __stubs.luau
│  └─ Unit/ Integration/ Multiplayer/ UI/
└─ tools/check.ps1            compilation + 4 suites
```

Détail des fichiers et des dépendances : [Architecture.md](Architecture.md).

## Sauvegarde et audio

Le serveur relit les sauvegardes 0.3.0. Si le DataStore est inaccessible à l’ouverture, la garde utilise la mémoire locale. Les voix françaises utilisent la synthèse Roblox et la sirène utilise un enregistrement du Creator Store. [Sources audio](../assets/ATTRIBUTION.md)
