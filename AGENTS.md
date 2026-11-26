# AGENTS.md — Emergency Response Simulator (ERS)

Ce fichier est le contrat de développement du projet. Il s'applique à toute
contribution humaine ou assistée par IA.

## 1. Mission

Construire **Emergency Response Simulator**, une simulation française de
commandement des secours sur Roblox (Luau), inspirée fonctionnellement
d'Emergency 4 et du mod CSP-IRG, **sans réutiliser aucun asset propriétaire**.

Le projet suit le cahier des charges ERS (phases 0 à 10). Une phase n'est
terminée que lorsque ses fonctionnalités sont **réellement testées**.

## 2. Règles non négociables

1. **Aucune fonction fictive.** Pas de bouton décoratif, pas de service qui
   renvoie `true` sans effet. Si une action existe dans l'UI, elle a un
   traitement serveur et un test (ou un test d'intégration).
2. **Le serveur fait autorité.** Budget, véhicules, personnels, équipements,
   incidents et résultats sont validés côté serveur. Le client n'envoie que des
   intentions (`RemoteEvent`) et affiche des snapshots.
3. **Modules courts et spécialisés.** Un service = une responsabilité.
   Interdiction de tout coder dans `Bootstrap.server.luau`.
4. **Aucun asset externe non autorisé.** Tout modèle doit être original
   (Blender/code) ou provenir d'une source Roblox autorisée et documentée.
5. **Ne jamais écraser un fichier sans l'avoir lu.** Les projets voisins
   (`centrale-112`, `roblox-911-fr`) sont hors périmètre.
6. **Ne pas publier** le jeu. Aucune action `Publish to Roblox`.
7. **Documenter** chaque fonction publique (commentaire au-dessus) et tenir
   `docs/Changelog.md`.
8. **Français** pour les libellés, commentaires, documentation et messages
   utilisateur. Identifiants techniques en anglais (`snake_case` pour les
   chaînes d'API, `PascalCase` pour les modules).

## 3. Architecture

```
src/ReplicatedStorage/Shared/       modules partagés (données, types, utils)
src/ReplicatedStorage/Shared/Catalogs/  véhicules, qualifications, équipements, incidents, permissions
src/ServerScriptService/Services/   logique serveur
src/StarterPlayer/StarterPlayerScripts/  contrôleurs + UI
tests/Unit | Integration | Multiplayer | UI
tools/check.ps1                     compilation + suites de tests hors Studio
docs/                               architecture, gameplay, modèle de données, changelog
```

- Chaque service reçoit le monde (`world`) en premier argument : aucune
  variable globale cachée, donc testable hors Studio.
- Les services ne se référencent que dans un sens, sans cycle :
  `Utilities/Config/Catalogs → BudgetService, PermissionService,
  PersonnelService, EquipmentService → VehicleService → IncidentService →
  DispatchService → CommandService`.
- `SnapshotService` sérialise uniquement des tables simples.
- `SaveService` utilise un store injectable (`SaveService.configure(store)`)
  pour être testable sans DataStore.

## 4. Conventions Luau

- `--!strict` pour les modules partagés et les nouveaux services.
- Types exportés dans `Shared/Types/init.luau`.
- Résultats d'API : `require(...Utilities.Result)` puis `Result.ok(message, data)`
  ou `Result.err(message, data)`.
- Chaînes d'état et d'action centralisées dans `Shared/Constants/init.luau`.
- Aucun `wait()`/`spawn()` : utiliser `task.wait`, `task.spawn`, `task.defer`.
- Toute entrée réseau est validée : type, longueur, existence, permission,
  disponibilité.

## 5. Boucle de développement

```powershell
# 1. Vérifier
powershell -ExecutionPolicy Bypass -File tools/check.ps1

# 2. Construire le place
& "$env:APPDATA\npm\rojo.cmd" build -o build\ERS.rbxlx

# 3. Ouvrir Studio sur build\ERS.rbxlx (ou rojo serve + plugin)
```

Le runner `tools/check.ps1` :
1. compile tous les `.luau` ;
2. exécute les tests unitaires ;
3. exécute l'intégration (boucle complète) ;
4. exécute les tests multijoueur/permissions ;
5. exécute le test d'interface headless.

Toute modification de gameplay doit être accompagnée d'un test. Le script doit
afficher `OK` avant de considérer une phase terminée.

## 6. Definition of Done (extrait)

- Le code compile (0 erreur).
- Les quatre suites de tests passent.
- Les actions UI sont branchées au serveur et validées.
- Les erreurs sont visibles dans l'UI et dans les logs serveur.
- `docs/Changelog.md` est mis à jour.
- Aucune ressource propriétaire n'est ajoutée.

## 7. Contraintes connues

- **Git n'est pas installé** sur la machine au moment de la Phase 0. `.gitignore`
  est prêt ; installer Git puis `git init` avant la prochaine phase (voir
  `docs/README.md` et le rapport de phase).
- Les dossiers `assets/` et `data/` décrivent l'organisation cible (voir leurs
  README). Les catalogues **faisant foi** sont les modules Luau de
  `src/ReplicatedStorage/Shared/Catalogs/` (Rojo ne synchronise pas de JSON
  brut dans le jeu).
- Les modèles 3D détaillés et la circulation arrivent en Phase 3 ; la Phase 1
  fournit la ville générée en code (`Shared/City`), la caméra isométrique et
  l'interface tactique. La Phase 2 ajoute le **réseau routier**
  (`Shared/Utilities/RoadNetwork`) : graphe déterministe, Dijkstra et trajets en
  polyligne, sans géométrie transmise par le réseau.
- Le kit EM4/CSP-IRG (`C:\Users\franc\Desktop\EM4_Roblox_Kit`) est une
  **référence de logique** : ses scripts et données d'équilibrage peuvent
  inspirer les catalogues, mais ses assets binaires (modèles, cartes, textures)
  restent la propriété de leurs auteurs, ne sont pas redistribués et doivent
  être refaits pour Roblox.
- La documentation de référence est `docs/README.md` (installation, commandes,
  tests), `docs/Architecture.md`, `docs/Gameplay.md`, `docs/DataModel.md` et
  `docs/Changelog.md`.
