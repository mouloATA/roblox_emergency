# Architecture

## 1. Principes

1. **Le serveur possède l'état.** Toute la vérité d'une partie tient dans une
   seule table `world`. Les services la lisent et la mutent ; ils ne conservent
   aucun état caché. Cela rend la sauvegarde, les tests et le multijoueur
   déterministes.
2. **Le client ne décide de rien.** Il envoie des intentions
   (`RemoteEvent Command`), reçoit des snapshots et des retours. Il peut
   désactiver un bouton pour l'ergonomie, jamais pour la sécurité.
3. **Une responsabilité par module.** Les bootstraps assemblent ; les services
   appliquent ; les contrôleurs traduisent ; les panneaux affichent.
4. **Aucune dépendance circulaire.** Le graphe ci-dessous est strictement
   orienté. Un service ne remonte jamais vers un module qui le requiert.
5. **Aucun asset externe.** La ville et la scène sont construites en code
   (`Shared/City`), sans asset propriétaire.

## 2. Arbre à l'exécution (mapping Rojo)

`default.project.json` produit exactement cette hiérarchie :

```text
ReplicatedStorage
├─ Shared                     (dossier de modules)
│  ├─ Config
│  ├─ Constants
│  ├─ Types
│  ├─ City                   (plan de ville déterministe)
│  ├─ Utilities/{Result, MathX, Rng, TimeUtil, Signal, Navigation, RoadNetwork, Crew, Operations}
│  └─ Catalogs/{Vehicles, Qualifications, Equipment, Incidents, Permissions}
└─ Remotes                    (Folder créé par le serveur)

ServerScriptService
└─ ERS
   ├─ Bootstrap              (Script)
   └─ Services/{...}         (15 ModuleScripts)

StarterPlayer/StarterPlayerScripts
└─ ERSClient
   ├─ Bootstrap              (LocalScript)
   ├─ Controllers/{InterfaceController, NetworkController, CameraController, InputController, AudioController}
   └─ UI/{Theme, Widgets, MiniMap, BottomBar, SceneView, EngagementHints, 7 panneaux, MainMenu, App}

Workspace
└─ ERS_Scene                  (généré par SceneService au démarrage)
```

Conséquence pratique : **tous les `require` sont absolus**, par exemple
`require(game:GetService("ReplicatedStorage").Shared.Catalogs.Vehicles)`.
Aucun module de production n'utilise `script.Parent` : le chemin reste valide
quel que soit le mode de synchronisation (Rojo serve, build, tests).

Le client atteint ses modules par le chemin réel du joueur :

```lua
Players.LocalPlayer.PlayerScripts.ERSClient
```

C'est ce que reproduit le harnais de test headless.

## 3. Graphe de dépendances

```text
Utilities (Result, MathX, Rng, TimeUtil, Signal, Navigation, RoadNetwork, Crew, Operations)
        │
Config ─┼─ Constants
        │
Catalogs (Vehicles, Qualifications, Equipment, Incidents, Permissions)
        │
        ├─> BudgetService        (Result)
        ├─> PermissionService    (Constants, Result, Catalogs)
        ├─> PersonnelService     (Constants, Result, Crew, Operations, Permission)
        ├─> EquipmentService     (Constants, Result, Operations, Permission)
        ├─> VehicleService       (…, Permission, Budget)
        │
        ├─> DispatchService      (Permission, Budget, Vehicle, Crew, Navigation, Operations)
        │
        ├─> CommandService       (Permission, Dispatch, MathX, Operations)
        │
        └─> IncidentService      (Budget, Command, Crew, MathX, Operations)

Operations       -> Navigation, RoadNetwork
WorldService     -> Personnel, Vehicle, Operations, Rng, City, RoadNetwork
SimulationService-> Dispatch, Incident, Vehicle, Personnel
SnapshotService  -> Constants, TimeUtil, Catalogs
SaveService      -> Vehicle, Crew, Operations
NetworkService   -> Permission, Personnel, Equipment, Vehicle, Dispatch,
                    Command, Snapshot
SceneService     -> Rng, City
LightingService  -> TimeUtil, Config
AudioController  -> Config, Constants

Bootstrap serveur -> tous les services ci-dessus
Bootstrap client  -> InterfaceController, NetworkController, CameraController,
                     InputController, AudioController, App
App               -> Theme, Widgets, MiniMap, BottomBar, SceneView, 7 panneaux,
                     MainMenu
MiniMap           -> Theme, Widgets, City, Config
Panneaux          -> Theme, Widgets, Config/Constants/Catalogues (lecture seule)
```

`IncidentService → CommandService` sert uniquement au bonus de secteur ; comme
`CommandService` ne connaît pas `IncidentService`, il n'y a pas de cycle.

## 4. Services serveur

| Service | Responsabilité | Ne fait pas |
| --- | --- | --- |
| `BudgetService` | dépense, recette, pénalité, journal des transactions | ne décide pas d'un achat |
| `PermissionService` | rôles, attribution, contrôles d'action et de périmètre | ne mute pas le gameplay |
| `PersonnelService` | recrutement, affectation aux engins, fatigue, santé | ne déplace pas les engins |
| `EquipmentService` | stock, installation et retrait sur un véhicule | ne calcule pas les besoins |
| `VehicleService` | création, achat, disponibilité, usure, atelier | ne planifie pas les trajets |
| `DispatchService` | engagement, trajet routier, arrivée, rappel, retour | ne résout pas l'intervention |
| `IncidentService` | alerte, étapes, couverture des moyens, succès/échec | n'affecte pas les joueurs |
| `CommandService` | groupes, secteurs, engagement groupé, bonus | ne crée pas d'incident |
| `WorldService` | construction de l'état initial | ne tourne pas en boucle |
| `SimulationService` | ordre d'un tic de simulation, échelle de temps validée | ne sérialise rien |
| `SnapshotService` | projection sérialisable de l'état | ne sauvegarde pas |
| `SaveService` | sérialisation persistante, chargement, version | ne restaure pas la session |
| `NetworkService` | validation d'entrée, anti-spam, routage | ne contient pas de règle métier |
| `SceneService` | ville 3D générée depuis `Shared/City` | n'a aucun rôle de gameplay |
| `LightingService` | ciel, ambiance, cycle jour/nuit, lampadaires et vitres | ne modifie pas l'horloge simulée |

### Ordre d'un tic (`SimulationService.step`)

```text
world.time += dt
  ├─ fin de service éventuelle (SHIFT_SECONDS) → saveRequested
  ├─ compte à rebours d'alerte → spawnRandom (si < MAX_ACTIVE_INCIDENTS)
  ├─ DispatchService.step     déplace les engins, gère les arrivées et retours
  ├─ IncidentService.step     fait progresser ou échouer les interventions
  ├─ VehicleService.stepRepair
  └─ PersonnelService.stepFatigue
```

`dt` est fourni par le bootstrap (boucle `task.wait`), jamais lu implicitement
par les services. Les tests appellent `step(world, dt)` avec le pas voulu.

## 5. Frontière réseau

Quatre objets, créés par `Bootstrap.server.luau` dans `ReplicatedStorage.Remotes` :

| Objet | Type | Sens | Contenu |
| --- | --- | --- | --- |
| `Command` | RemoteEvent | client → serveur | `(action: string, payload: table?)` |
| `Feedback` | RemoteEvent | serveur → client | `Result { ok, message, data? }` |
| `Snapshot` | RemoteEvent | serveur → client | snapshot sérialisable |
| `RequestSnapshot` | RemoteFunction | client → serveur | renvoie un snapshot complet |

`NetworkService.handle(world, player, action, payload)` :

1. vérifie la forme du joueur (`UserId`, `Name`) et de l'action ;
2. refuse une charge utile non table ;
3. enregistre le joueur s'il est inconnu (`PermissionService.seed`) ;
4. applique l'anti-spam (`ACTION_COOLDOWN`, horloge `os.clock`) ;
5. appelle le handler déclaré, qui valide chaque champ ;
6. renvoie toujours un `Result` (jamais d'exception attendue).

### Actions acceptées

| Action | Charge utile | Service appelé |
| --- | --- | --- |
| `dispatch` | `vehicleId`, `incidentId` | `DispatchService.dispatch` |
| `recall` | `vehicleId` | `DispatchService.recall` |
| `auto_crew` | `vehicleId` | `PersonnelService.autoCrew` |
| `assign_personnel` | `personId`, `vehicleId` | `PersonnelService.assign` |
| `unassign_personnel` | `personId` | `PersonnelService.unassign` |
| `install_equipment` | `vehicleId`, `equipmentId`, `quantity` | `EquipmentService.install` |
| `uninstall_equipment` | `vehicleId`, `equipmentId`, `quantity` | `EquipmentService.uninstall` |
| `buy_vehicle` | `typeId` | `VehicleService.buy` |
| `repair_vehicle` | `vehicleId` | `VehicleService.repair` |
| `create_group` | `name`, `service?` | `CommandService.createGroup` |
| `add_to_group` | `groupId`, `vehicleId` | `CommandService.addUnit` |
| `remove_from_group` | `groupId`, `vehicleId` | `CommandService.removeUnit` |
| `dissolve_group` | `groupId` | `CommandService.dissolve` |
| `dispatch_group` | `groupId`, `incidentId` | `CommandService.dispatchGroup` |
| `create_sector` | `name`, `x`, `z`, `radius` | `CommandService.createSector` |
| `assign_group_sector` | `sectorId`, `groupId` | `CommandService.assignGroupToSector` |
| `claim_role` | `role` | `PermissionService.claim` |
| `assign_role` | `userId`, `role` | `PermissionService.assignRole` |
| `save` | — | contrôle `SAVE` puis `world.saveRequested = true` |
| `set_time_scale` | `scale` ∈ `Config.TIME_SCALES` | `SimulationService.setTimeScale` (permission `SET_TIME`) |
| `request_snapshot` | — | accusé ; l'appelant renvoie le snapshot |

Règles de validation : identifiants entiers `1..1e9`, identifiants
d'intervention `INC-xxx` (1–16 caractères), textes bornés
(`MAX_COMMAND_LENGTH`), quantités entières `1..99`. Toute action inconnue est
refusée.

### Flux d'une intention

```text
clic panneau
  └─ InterfaceController:command(action, payload)
       └─ NetworkController.command → Command:FireServer
            └─ Bootstrap serveur (OnServerEvent)
                 └─ NetworkService.handle  ← validation + anti-spam
                      └─ Service métier    ← permissions + état + mutation
                           ├─ Feedback:FireServer(result)  → toast
                           └─ prochain Snapshot            → rendu
```

Le client n'applique jamais le résultat localement : il attend le snapshot.
Un refus serveur devient un message visible, jamais un succès silencieux.

## 6. Interface client

| Module | Rôle |
| --- | --- |
| `UI/Theme` | couleurs, tailles, polices, libellés de statut, format monétaire |
| `UI/Widgets` | fabrique d'Instances, listes réconciliées par identifiant, boutons, tags |
| `UI/MiniMap` | mini-carte encadrée en haut à droite : plan, marqueurs, couches, cadre de visée |
| `UI/BottomBar` | barre fixe : catégories, groupes, vitesses, commandes, équipage |
| `UI/SceneView` | engins et balises d'urgence dans la scène 3D |
| `UI/IncidentPanel` | briefing, étape, moyens requis, engagement et rappel |
| `UI/VehiclePanel` | flotte, équipage automatique, matériel embarqué, réparation |
| `UI/PersonnelPanel` | effectifs, affectation, fatigue |
| `UI/EquipmentPanel` | stock et installation sur l'engin sélectionné |
| `UI/CommandPanel` | groupes, membres, secteurs, engagement groupé |
| `UI/BudgetPanel` | solde, achats, opérations, sauvegarde |
| `UI/MultiplayerPanel` | postes, joueurs, attribution, resynchronisation |
| `UI/MainMenu` | accueil, choix du poste, commandes |
| `UI/App` | coque : barre d'état, onglets, mini-carte, tiroir, journal, toasts |
| `Controllers/InterfaceController` | état local, permissions d'affichage, transport |
| `Controllers/NetworkController` | branchement des remotes |
| `Controllers/CameraController` | caméra isométrique : orbite, zoom, focus, suivi |
| `Controllers/InputController` | raccourcis clavier et souris |

### 6.1 Composition de l'écran

La ville 3D occupe tout l'écran ; l'interface se superpose en quatre zones
fixes, comme dans Emergency 4 :

1. **Barre supérieure** : statut (horloge, budget, alertes, poste, effectif) et
   bouton Menu.
2. **Colonne d'onglets** à gauche : sept panneaux numérotés.
3. **Mini-carte** encadrée en haut à droite, avec couches et cadre de visée.
4. **Barre inférieure** fixe (188 px) et **tiroir** de panneaux qui s'ouvre
   juste au-dessus d'elle.

Le `ScreenGui` utilise **`ZIndexBehavior = Enum.ZIndexBehavior.Sibling`**. En
mode `Global` (historique), un enfant resté à `ZIndex = 1` passait sous le fond
de son conteneur : la barre et la mini-carte apparaissaient vides. En mode
`Sibling`, un enfant est toujours dessiné au-dessus de son parent et le
`ZIndex` ne classe que les frères (`barre 12`, `tiroir 20`, `notifications 30`,
`menu 40`).

Le tiroir mesure `Theme.sizes.drawerHeight = 340` px et porte
`ClipsDescendants = true`. Les panneaux denses sont en deux colonnes (liste à
gauche, détail à droite) et leur détail est un `ScrollingFrame` : aucun contenu
ne peut déborder sur la barre inférieure. Le journal est décalé à droite de la
colonne d'onglets (`Position.X = tabsCompact + 16`) pour ne pas être recouvert.

La mini-carte porte un `UIScale` borné (0,55–1). `App:render` appelle
`MiniMap.resize(viewportX, viewportY)` à chaque frame : sur une fenêtre courte,
elle se réduit au lieu de passer sous la barre.

`InterfaceController` ne calcule aucun résultat : il conserve l'onglet, les
sélections, le menu et les notifications, puis rend le dernier snapshot. Les
listes de `Widgets.list` réutilisent les lignes par clé (`id` du véhicule, de
l'urgence, du journal…), ce qui évite clignotement et perte de défilement.

## 7. Harnais de test

`tools/check.ps1` n'ouvre pas Roblox :

1. copie les sources dans `%LOCALAPPDATA%\Temp\opencode\ers-check` (chemin
   ASCII : le CLI Luau refuse les accents) ;
2. réécrit chaque fichier en UTF-8 **sans BOM** ;
3. génère un manifeste qui reproduit l'arbre Rojo, pour que les `require`
   absolus fonctionnent hors Studio ;
4. injecte un en-tête `__env` dans chaque module (globales Roblox, `require`
   virtuel) ;
5. compile tous les fichiers, puis exécute les suites dans l'ordre.

| Suite | Fichier | Portée |
| --- | --- | --- |
| Unitaires | `tests/Unit/spec.luau` | maths, RNG, horloge, Result, réseau routier et navigation, catalogues, budget, équipages, permissions |
| Intégration | `tests/Integration/sim.luau` | monde initial, alerte → engagement → résolution, sauvegarde, atelier, commandement, boucle |
| Multijoueur | `tests/Multiplayer/permissions.luau` | enregistrement, attribution, périmètres, refus serveur, validation réseau, anti-spam |
| Interface | `tests/UI/ui.luau` | construction, menus, clics réels via `NetworkService.handle`, boutons désactivés, toasts, réconciliation, mini-carte, caméra, raccourcis, mise en page du tiroir |

`tests/__stubs.luau` fournit les Instances GUI, signaux, tweens, caméra et
entrées. `tests/__prelude.luau` installe le chargeur de modules virtuel.

Le CLI Luau donne à chaque module sa propre table de globales : les doublures
sont donc injectées par en-tête dans **chaque** fichier testé. Aucun test ne
dépend de `_G`.

## 8. Ajouter une action de bout en bout

1. Ajouter la chaîne d'action dans `Shared/Constants` si nécessaire.
2. Écrire la fonction métier dans le service concerné, avec contrôle de
   permission et d'état, et retour `Result`.
3. Déclarer le handler et la validation de charge utile dans
   `NetworkService.actions` (et la liste `NetworkService.actions` reste la
   source de vérité des actions connues).
4. Brancher le panneau : bouton → `controller:command(action, payload)`,
   désactivation si `controller:can(...)` est faux.
5. Ajouter un test d'intégration **et** un clic dans `tests/UI/ui.luau`.
6. Mettre à jour `docs/Changelog.md` et, si le contrat change,
   `docs/Architecture.md`.

Une action sans handler, sans validation ou sans test est un bug, pas une
fonctionnalité.

## 9. Déterminisme et performance

- `Rng` est un générateur congruentiel linéaire local, pas `math.random` :
  une graine fixe rejoue exactement la même partie.
- Les itérations qui produisent des effets sont triées par identifiant
  (interventions, véhicules en sauvegarde) pour éviter les ordres instables.
- `TICK_RATE = 1 Hz` et `SNAPSHOT_RATE = 4 Hz` : la simulation est légère, les
  snapshots sont bornés (`SNAPSHOT_LOG_LIMIT = 60`).
- Aucune instance 3D n'est créée par la simulation : la scène est statique et
  l'interface est en 2D. Seuls `SceneService` (ville) et `SceneView` (engins)
  créent des parts, une fois au démarrage puis par différences.
- La ville n'est **jamais** transmise par le réseau : `City.build(seed)` est pur
  et déterministe, appelé par le serveur (géométrie) et par chaque client
  (mini-carte). Seules les positions dynamiques passent dans le snapshot.
- Les mouvements de caméra (pan, zoom, rotation) restent locaux : ils ne
  produisent aucun message réseau.

## 10. Réseau routier

`Shared/Utilities/RoadNetwork` transforme le plan de ville en graphe orienté
testable :

```text
City.build(CITY_SEED)
  └─ roads (avenues nord-sud, rues est-ouest)
       └─ RoadNetwork.build
            ├─ 25 nœuds   : un carrefour par croisement
            ├─ 40 arêtes  : tronçons entre carrefours voisins
            └─ adjacency  : voisin + longueur, dans les deux sens
```

- **Déterminisme.** Nœuds et arêtes sont créés dans l'ordre des avenues et des
  rues triées : deux appels produisent le même graphe, sans aléatoire.
- **Plus court chemin.** `RoadNetwork.shortest` applique Dijkstra sur les
  longueurs ; à distance égale, l'ordre d'itération fixe le résultat.
- **Trajet.** `RoadNetwork.path(from, to)` projette les extrémités sur la
  chaussée la plus proche, choisit le meilleur couple de nœuds d'entrée/sortie,
  puis renvoie une **polyligne** : point de départ, entrée sur la route,
  carrefours traversés, sortie, point d'arrivée. Le cas « même tronçon » reste
  sur ce tronçon, sans détour par un carrefour.
- **Mesure.** `Navigation.measure` calcule les longueurs cumulées ;
  `Navigation.route` y ajoute `startTime`, `duration`, `siren`, `length`.
  `Operations.moveTo` et `Operations.release` passent la polyligne à
  `Navigation.route` ; `DispatchService` utilise `route.length` pour l'usure.
- **Repli.** Graphe absent ou dégénéré : la polyligne se réduit à
  `[départ, arrivée]` et le trajet direct reste possible (tests isolés).
- **Client.** La polyligne n'est pas envoyée : le client reçoit les positions
  du snapshot et interpole. Le graphe n'est donc jamais sérialisé.
