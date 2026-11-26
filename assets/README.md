# assets/ — ressources originales

## Politique

**Aucun asset propriétaire.** Tout modèle, texture, son ou icône doit être :

1. **original**, créé pour ERS (code, Blender, outil interne) ; ou
2. provençable d'une source Roblox officielle/autorisee, avec la preuve
   d'origine et la licence conservées dans ce dossier.

Il est interdit de copier un asset d'Emergency 4, du CSP-IRG, d'un jeu Roblox
tiers, d'un site de modèles ou d'une capture d'écran. Les ressemblances
fonctionnelles (véhicules français, rôles, interventions) sont permises ; la
copie d'un modèle, d'une texture ou d'une interface ne l'est pas.

## État actuel (Phase 0)

Le dossier ne contient que ce README. **Aucun asset externe n'est utilisé.**

- La scène 3D est générée en code par `SceneService` (sol, routes, caserne,
  points d'intérêt, bâtiments déterministes).
- L'interface est entièrement construite par `UI/Theme`, `UI/Widgets` et les
  panneaux : rectangles, textes, cadres, sans image.
- Les véhicules et personnages ne sont pas encore modélisés : la Phase 0 est
  une simulation tactique, pas une scène peuplée.

## Organisation cible (non encore créée)

```text
assets/
├─ Map/            terrain, routes, quartiers, POI
├─ Vehicles/       engins originaux (FPT, VSAV, VPC, …)
├─ Characters/     tenues et équipements de sapeurs, soignants, policiers
├─ Equipment/      ARI, extincteurs, défibrillateurs, balises…
├─ UI/             icônes et éléments graphiques originaux
├─ Audio/          sons originaux (sirènes, radio, ambiance)
├─ Source/         fichiers Blender, scripts de génération, textures sources
├─ ATTRIBUTION.md  sources, auteurs, licences, preuves
└─ README.md
```

## Conventions

- Dossiers et fichiers en `snake_case`, sans accents ni espaces :
  `vehicles/fpt_01.blend`, `vehicles/fpt_01.fbx`.
- Un asset = un nom stable + une version (`fpt_01_v2.fbx`) ; ne pas écraser
  une version validée.
- Échelle de la carte : **6 studs par unité de carte** (`Config.WORLD_SCALE`).
  Origine au sol, axe `+Y` vers le haut, orientation `+Z` vers l'avant.
- Polygone budget : privilégier des formes lisibles à distance tactique.
- Aucun script dans les modèles importés : les comportements restent dans les
  services Luau.
- Chaque import doit être documenté dans `ATTRIBUTION.md` avant d'être utilisé
  dans le jeu.

## Modèle d'attribution

```text
Nom :
Fichier :
Auteur :
Date :
Source / méthode de création :
Licence :
Preuve (lien, capture, fichier source) :
Utilisation dans ERS :
```

## Ce qui n'est pas autorisé

- Captures, rips ou conversions d'autres jeux.
- Textures ou sons trouvés en ligne sans licence explicite.
- Marques, logos ou livrées réelles non autorisées.
- Publication du jeu ou d'assets sur la place publique sans décision explicite.
