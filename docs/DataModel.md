# Modèle de données

## 1. Vue d'ensemble

Il existe trois représentations distinctes, volontairement séparées :

| Représentation | Portée | Forme |
| --- | --- | --- |
| `world` | serveur uniquement | tables Luau avec références, fonctions de catalogue, RNG |
| **snapshot** | envoyé aux clients | tables simples, sérialisables, sans Instance ni fonction |
| **sauvegarde** | DataStore / stockage mémoire | tables simples, versionnées, JSON-compatibles |

Le client ne voit jamais `world` : il ne reçoit que `SnapshotService.build`.

## 2. Racine `world`

Construite par `WorldService.create(config, catalogs, options?)`.

| Champ | Type | Rôle |
| --- | --- | --- |
| `version` | string | version du format (`0.4.0`, lecture de `0.3.0` prise en charge) |
| `config` | table | `Config` partagé |
| `catalogs` | table | `{ vehicles, qualifications, equipment, incidents, permissions }` |
| `budget` | number | solde courant, peut être négatif |
| `purchaseTurn` | table de session | responsable des achats et expiration selon les postes en ligne |
| `mission` | table de session | scénario et interventions qui portent ses objectifs |
| `transactions` | array | 120 dernières écritures |
| `vehicles` | map `id → vehicle` | flotte |
| `personnel` | map `id → person` | effectifs |
| `equipmentStock` | map `equipmentId → quantity` | stock global |
| `incidents` | map `"INC-xxx" → incident` | interventions |
| `groups` | map `id → group` | groupes tactiques |
| `sectors` | map `id → sector` | secteurs |
| `players` | map `userId → player` | joueurs enregistrés |
| `log` | array | journal, plus récent en tête, max 120 |
| `time` | number | secondes simulées depuis le début |
| `alarmCountdown` | number | secondes avant la prochaine alerte |
| `spawnedIncidents` | number | compteur d'alertes créées |
| `finished` | boolean | fin de service atteinte |
| `saveRequested` | boolean | sauvegarde demandée |
| `nextVehicleId` | number | compteur d'identifiants |
| `nextPersonnelId` | number | — |
| `nextIncidentId` | number | — |
| `nextGroupId` | number | — |
| `nextSectorId` | number | — |
| `nextLogId` | number | identifiant monotone du journal |
| `rng` | `Rng` | générateur déterministe |
| `cityPlan` | table | plan déterministe `City.build(CITY_SEED)` |
| `roadNetwork` | table | graphe routier construit depuis `cityPlan` |
| `stats` | table | compteurs de carrière |

`cityPlan` et `roadNetwork` sont des données pures, reconstruites au chargement :
elles ne sont **jamais** sauvegardées ni envoyées par le réseau.

### `stats`

```lua
{
  dispatched = 0,     -- engagements individuels réussis
  resolved = 0,       -- succès complets
  degraded = 0,       -- succès dégradés
  failed = 0,         -- échecs
  savedVictims = 0,   -- victimes prises en charge
  spent = 0,          -- dépenses cumulées
  earned = 0,         -- recettes cumulées
}
```

## 3. Entités

### Véhicule

```lua
{
  id = 1,                      -- entier, clé de world.vehicles
  typeId = "FPT",              -- clé du catalogue Vehicles
  callsign = "FPT 1",          -- unique
  status = "available",        -- Constants.VEHICLE_STATUS
  condition = 100,             -- 1..100
  position = { x = 14, z = 62 },
  home = { x = 14, z = 62 },   -- emplacement au poste
  crew = { 2, 3, 4, 5 },       -- ids de personnel
  equipment = { ARI = 4 },     -- matériel embarqué
  incidentId = nil,            -- intervention en cours
  route = nil,                 -- trajet Navigation.Route (polyligne routière)
  repairRemaining = 0,         -- secondes d'atelier
}
```

Un trajet routier contient `points` (suite de `{ x, z }` sur la chaussée),
`cumulative` (longueurs cumulées), `length` (longueur totale), `startTime` et
`duration`. La position de l'engin est dérivée de ces champs à chaque tic ; le
client n'a donc qu'à interpoler les positions du snapshot.

Statuts : `available`, `dispatched`, `onscene`, `returning`, `maintenance`.
Un véhicule ne peut être affecté qu'à un seul incident et un membre qu'à un seul
véhicule.

### Personnel

```lua
{
  id = 2,
  name = "Lieutenant Perrin",
  grade = "Lieutenant",
  service = "fire",                 -- fire|medical|police|technical|logistics|command
  qualifications = { SAPEUR = true, CONDUCTEUR = true },
  experience = 82,                  -- 0..100
  fatigue = 0,                      -- 0..100
  health = 100,                     -- 0..100
  status = "available",
  vehicleId = 1,                    -- nil si non affecté
}
```

### Intervention

```lua
{
  id = "INC-001",
  typeId = "FEU_VEHICULE",
  status = "pending",               -- pending|active|resolved|failed
  severity = 1,                     -- 1..3
  position = { x = 18, z = 40 },
  createdAt = 42.5,
  deadline = 117.5,                 -- date limite de prise en charge
  assigned = { [1] = true },        -- véhicules engagés
  onScene = { [1] = true },         -- véhicules arrivés
  stepIndex = 1,                    -- index de l'étape courante
  stepProgress = 0,                 -- secondes cumulées dans l'étape
  underpoweredFor = 0,              -- secondes sans couverture suffisante
  emptyFor = 0,                     -- secondes sans aucun moyen sur place
  victims = 0,
  savedVictims = 0,
  closedAt = nil,
  outcome = nil,                    -- "success"|"degraded"|raison d'échec
}
```

### Groupe et secteur

```lua
group = {
  id = 1,
  name = "Groupe Nord",
  service = nil,                    -- nil = inter-services
  vehicles = { 2, 3 },
  sectorId = 1,                     -- lien réciproque
}

sector = {
  id = 1,
  name = "Secteur Nord",
  x = 18, z = 40, radius = 20,
  groupId = 1,
}
```

Créer ou dissoudre un groupe met à jour le lien réciproque. Un secteur ne peut
être affecté qu'à un groupe, et un groupe qu'à un secteur.

### Joueur

```lua
{
  userId = 123456,
  name = "Builderman",
  role = "direction",               -- Constants.ROLE
  joinedAt = 12.0,
  lastAction = -math.huge,          -- horloge os.clock, anti-spam
  connected = true,
}
```

Le premier joueur enregistré reçoit la Direction ; les suivants sont
Observateurs jusqu'à ce qu'ils prennent un poste.

### Journal et transactions

```lua
logEntry = { id = 7, time = 42.5, clock = "06:00", kind = "dispatch", message = "…" }
transaction = { time = 42.5, amount = -120, reason = "Mobilisation FPT 1", balance = 24880 }
```

`id` est monotone et ne recule jamais : l'interface peut réconcilier les lignes
sans clignotement. `kind` ∈ `system`, `info`, `success`, `failure`, `money`,
`dispatch`, `incident` (`Constants.LOG`).

## 4. Catalogues

Les catalogues sont des modules Luau faisant foi (voir `data/README.md`).

### Type de véhicule (`Catalogs/Vehicles`)

| Champ | Rôle |
| --- | --- |
| `id`, `name`, `category`, `service` | identité et rattachement |
| `speed`, `acceleration` | temps de trajet |
| `seats`, `crewRequired`, `driverRequired` | équipage |
| `qualifications` | qualifications devant être présentes dans l'équipage |
| `capabilities` | puissance par capacité (`fire`, `rescue`, `medical`…) |
| `equipmentSlots`, `capacity` | limites de chargement |
| `defaultEquipment` | matériel installé à la création, dans la limite du stock |
| `cost`, `mobilizationCost` | achat et départ |
| `description` | texte affiché |

34 types couvrent incendie, secours, police, technique, logistique et
commandement. Ils reprennent les rôles du roster EM4/CSP-IRG (UMH, VLM, VSR,
CCGC, VCH, VMO, VRI, VLOG) avec des coûts et des capacités propres à ERS.

### Type d'intervention (`Catalogs/Incidents`)

| Champ | Rôle |
| --- | --- |
| `id`, `name`, `service`, `severity` | identité, gravité 1–3 |
| `briefing` | texte de situation |
| `requires` | capacités cumulées exigées à la conclusion |
| `steps` | étapes `{ id, label, requires, seconds }` ordonnées |
| `equipment`, `qualifications` | exigences de conclusion |
| `responseDeadline` | secondes avant échec si non engagée |
| `victims`, `reward`, `penalty` | enjeu et économie |
| `weight` | poids de tirage |

32 interventions sont définies ; `PROTOTYPE_SCENARIOS` restreint le tirage
automatique à une rotation jouable avec la flotte initiale.

### Qualification, équipement, rôle

- `Qualifications` : 23 entrées `{ id, name, description, category }`.
- `Equipment` : 24 entrées `{ id, name, category, bonus, description }` ; le
  `bonus` est un mapa de capacités ajoutées.
- `Permissions` : 7 rôles `{ label, description, actions, services }`.

## 5. Snapshot

Produit par `SnapshotService.build(world)` et vérifié récursivement par
`SnapshotService.isSerializable`.

```lua
{
  version, time, clock, timeScale, paused, budget, spent, earned, finished,
  players   = { { userId, name, role, roleLabel, connected } },
  vehicles  = { { id, typeId, name, callsign, service, status, condition, x, z,
                  crew, crewCount, crewRequired, equipment, incidentId,
                  route, repairRemaining } },
  personnel = { { id, name, grade, service, status, vehicleId, fatigue, health,
                  experience, qualifications, qualificationIds } },
  incidents = { { id, typeId, name, briefing, service, severity, status, x, z,
                  victims, savedVictims, stepIndex, stepCount, stepLabel,
                  stepProgress, stepSeconds, deadlineIn, assigned, onScene,
                  requires, equipment, qualifications, outcome } },
  groups    = { { id, name, service, vehicles, sectorId } },
  sectors   = { { id, name, x, z, radius, groupId } },
  stock     = { { id, name, quantity } },
  log       = { { id, time, clock, kind, message } },   -- 60 max
  stats     = { ... },
  alerts    = 2,
}
```

Règles :

- uniquement des nombres, chaînes, booléens, tableaux et dictionnaires ;
- profondeur limitée à 12 ;
- listes triées par identifiant pour un rendu stable ;
- `crew` contient des **noms** (affichage), pas des identifiants ;
- `deadlineIn` est un temps restant, jamais une date absolue ;
- `route` est le trajet routier du véhicule (`points`, `length`, `duration`) ;
  il ne contient aucune Instance et reste sérialisable ;
- `timeScale` est l'échelle validée par le serveur (`0`, `1`, `2`, `4`) et
  `paused` en est le reflet (`timeScale == 0`) ; le client ne les calcule pas ;
- `clock` est l'heure de service formatée (`HH:MM`), calculée par `TimeUtil` ;
- les libellés (`roleLabel`, noms de matériel, de qualification) viennent du
  catalogue : le client ne code pas ces chaînes.

## 6. Sauvegarde

`SaveService.serialize(world)` produit :

```lua
{
  version = "0.3.0",
  savedAt = 1760000000,
  budget = 24880,
  stats = { ... },
  equipmentStock = { ARI = 6, ... },
  vehicles  = { { id, typeId, callsign, condition, equipment, crew } },
  personnel = { { id, name, grade, service, qualifications, experience, fatigue, health } },
  groups    = { { id, name, service, vehicles, sectorId } },
  sectors   = { { id, name, x, z, radius, groupId } },
}
```

### Ce qui est restauré

- budget et statistiques ;
- flotte possédée (type, indicatif, état, matériel) ;
- effectifs, qualifications, expérience, fatigue, santé ;
- stock ;
- groupes et secteurs, y compris leurs liens réciproques ;
- affectations d'équipage, dans une seconde passe : un membre n'est réaffecté
  que si le véhicule et le membre existent encore et que `Crew.canAssign`
  l'autorise (service compatible, sièges libres, fatigue et santé acceptables).

### Ce qui n'est pas restauré

- joueurs connectés et rôles ;
- interventions en cours ou terminées ;
- trajets, statuts de session et dégâts liés à une intervention en cours ;
- transactions : l'historique repart vide, le solde et les cumuls sont
  conservés.

Au chargement, les véhicules sont replacés à leur emplacement au poste et les
compteurs d'identifiants sont recalculés à partir des entités restaurées
(`nextIncidentId` repart à 1, les interventions étant vidées).

### Robustesse

- Une version différente est refusée (`Result.err`), pas migrée implicitement.
- Les entrées inconnues (type supprimé, qualification retirée, quantité
  invalide) sont ignorées et comptées dans `ignored` ; elles ne sont jamais
  injectées telles quelles.
- Les nombres sont vérifiés (`NaN` et infinis refusés) et bornés (état 1–100,
  fatigue 0–100, santé 0–100).
- Le stockage est injectable : `SaveService.configure(store)` avec
  `store.get` / `store.set`. En l'absence de DataStore, le bootstrap utilise un
  stockage mémoire et le journalise.

Clé par défaut : `ERS_World` / `world` (`Config.SAVE_STORE`, `SAVE_KEY`).
Sauvegarde automatique toutes les 60 s et à la fermeture du serveur
(`BindToClose`).

## 7. Invariants

1. Une intervention ouverte (`pending`/`active`) possède un identifiant
   `INC-xxx` unique et croissant.
2. `incident.assigned` et `incident.onScene` ne contiennent que des véhicules
   dont `vehicle.incidentId == incident.id`.
3. `vehicle.crew` ne contient que des personnels dont `person.vehicleId ==
   vehicle.id`.
4. Un groupe et un secteur ne peuvent être liés qu'à un seul homologue.
5. Le journal est borné (`LOG_LIMIT = 120`) et chaque entrée a un `id`
   strictement croissant.
6. `budget` peut être négatif ; aucune autre grandeur économique n'est
   négative.
7. Toute table envoyée au client passe `SnapshotService.isSerializable`.
8. Aucun identifiant de catalogue n'est deviné : `catalogs.*.exists/get` fait
   foi.

## 8. Déterminisme

`Rng.new(seed)` est un LCG local :

```text
state = (state × 1103515245 + 12345) mod 2^31
```

Il fournit `next`, `integer(min, max)` et `weighted(list, weightOf)`. Une graine
fixe rejoue la même séquence de scénarios, de positions et de bâtiments
décoratifs. `WorldService.create(..., { seed = … })` est utilisé par les tests ;
le serveur utilise `os.time()` par défaut.
