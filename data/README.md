# data/ — données de référence

## Rôle

Ce dossier est réservé aux **données exportables et aux schémas** :
documentation lisible par des outils, exports pour l'équilibrage ou pour un
futur pipeline (tableur, script de validation, site de documentation).

## Règles importantes

1. **Les catalogues Luau font foi.** Les données réellement chargées par le jeu
   sont les modules de
   `src/ReplicatedStorage/Shared/Catalogs/` :
   `Vehicles.luau`, `Qualifications.luau`, `Equipment.luau`,
   `Incidents.luau`, `Permissions.luau`.
   Rojo synchronise des Instances, pas des fichiers JSON bruts : un JSON posé
   ici n'est **pas** lu par le jeu.
2. **Aucune duplication manuelle.** Si un export JSON est ajouté, il doit être
   généré depuis les modules Luau, jamais recopié à la main. Une divergence
   entre les deux serait un bug.
3. **Identifiants stables.** Les identifiants (`FPT`, `ARI`, `FEU_VEHICULE`,
   `INCENDIE`) ne changent pas : ils apparaissent dans les sauvegardes, les
   journaux et les tests.
4. **Libellés en français**, identifiants techniques en anglais ou en
   constantes françaises existantes, conformément à `AGENTS.md`.

## Organisation cible (non encore créée)

```text
data/
├─ catalogs/          exports générés depuis les modules Luau
│  ├─ vehicles.json
│  ├─ qualifications.json
│  ├─ equipment.json
│  ├─ incidents.json
│  └─ permissions.json
├─ schema/            schémas de validation (JSON Schema)
├─ balance/           tables d'équilibrage et notes de révision
└─ README.md
```

## État actuel (Phase 0)

Le dossier ne contient que ce README. Les catalogues sont complets et testés
dans les modules Luau ; aucun export n'est nécessaire au fonctionnement du jeu.

## Modifier une donnée de jeu

1. Éditer le module Luau concerné dans `Shared/Catalogs/`.
2. Vérifier la cohérence : une qualification ou un équipement référencé doit
   exister dans son catalogue (les tests unitaires le vérifient).
3. Lancer `tools/check.ps1`.
4. Mettre à jour `docs/Gameplay.md` ou `docs/DataModel.md` si le contrat
   change, et `docs/Changelog.md`.

## Futur script d'export

L'export pourra être un module Luau exécuté hors Studio (même harnais que les
tests) qui parcourt `Catalogs` et écrit du JSON trié. Il devra :

- refuser les références inconnues ;
- produire un ordre stable (identifiants triés) ;
- échouer si le fichier existant diffère sans changement de version.
