# Changelog

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.0.0/).
Le projet suit une version `MAJEUR.MINEUR.CORRECTIF`.

## [Non publié] — 2026-11-26

### Interface de la caserne

- La vue se déplace par glissement du bouton gauche sur la ville et par maintien des flèches ou de WASD. Le mouvement, le zoom et le recentrage sont lissés à chaque image. Le fond de la carte permet de viser un point libre. Les panneaux du HUD interceptent glissement et molette, même après personnalisation.
- Le bouton cadenas HUD ouvre la personnalisation des panneaux visibles. Le joueur les déplace et ajuste leur échelle, puis verrouille les commandes. Réinitialiser retrouve la disposition automatique. Les préférences sont validées et enregistrées par joueur, avec un repli explicite en mémoire quand le DataStore est inaccessible.
- La carte tactique se redimensionne par sa poignée inférieure gauche et le journal par sa poignée supérieure droite, à la souris ou au toucher. Les dimensions choisies restent actives pendant la session et sont limitées à l’espace disponible.
- La barre ERS occupe la zone libre à droite des bulles Roblox, sur la même ligne. Sa largeur suit automatiquement les commandes natives et les dimensions de la fenêtre.
- Tous les panneaux s’ouvrent à droite du menu latéral, y compris la flotte ouverte depuis les moyens disponibles. Dans une fenêtre étroite, les fiches larges défilent horizontalement et les boutons de navigation restent accessibles.
- Les achats de véhicules et le recrutement proposent un tri par prix croissant ou décroissant. Chaque catalogue conserve son choix de tri pendant la consultation des services.
- La navigation regroupe opérations, caserne et coordination. Les achats et les finances ont des vues distinctes. Les 34 véhicules se filtrent par service, avec le solde, le prix réel et les conditions d’achat visibles.
- Les vues Effectif et Recruter partagent le filtre de service. Chaque fiche affiche les qualifications et permet d’affecter l’agent directement à un engin admissible.
- Le magasin classe le stock par usage. On peut y choisir un véhicule et consulter le poids et les emplacements occupés à bord. Une confirmation apparaît dans l’en-tête après une action de gestion.
- Les tests d’interface parcourent les catégories, exercent les transactions sur le serveur et contrôlent la place du tiroir sur quatre résolutions de bureau.

### Jeu local 0.4.0

- Les équipages reçoivent des ordres d’extinction, de sauvetage, de désincarcération et de réserve. Les matériaux, la propagation et les réserves d’eau déterminent l’évolution des foyers.
- Les ambulances équipées chargent les victimes selon leur capacité, suivent les rues, transmettent les patients aux urgences et reviennent chercher les suivants.
- Le panneau Missions propose l’église, la collision routière et la forêt avec deux objectifs par scénario. Les bilans alimentent le score, l’évaluation sur 100, les pertes civiles et six distinctions adaptées d’EM4.
- La caserne accueille un technicien au départ et permet le recrutement, la cession et trois niveaux de formation. Direction et Commandement alternent les achats. Chaque acquisition augmente les tarifs de 30 €. Le jeu relit les sauvegardes 0.3.0.
- Des véhicules spécialisés, des façades et la circulation des passants et des voitures animent la ville. Le HUD adapte ses panneaux et sa typographie à la taille du bureau.
- Une sirène française enregistrée et des messages radio sous-titrés accompagnent les alertes et les équipages. [Attribution](../assets/ATTRIBUTION.md)
- La caméra tactique reprend sa position après le chargement du personnage ou le remplacement de la caméra Roblox. Son champ de vision est de 34°. Le titre et les commandes du HUD respectent la zone réservée à Roblox.
- Dans Studio 0.748.0.7481526, *Fumée au clocher* s’est terminée avec une admission aux urgences. À 21 h 02, le moteur comptait 60 lampadaires allumés et 334 vitres lumineuses. Les étoiles et la lune étaient actives. La lecture de la sirène (10,92 s) et de la voix française a produit un signal mesurable côté client.
- Les quatre suites locales passent avec 950 assertions. La session Studio instrumentée a mesuré un HUD de 1450 × 734. Les tests de disposition couvrent également 1024 × 768, 1280 × 720, 1920 × 1080 et 2560 × 1440.

### Ajouté

- 134 scripts texte du jeu EM4 de base, fournis dans `03_SCRIPTS_EM4.zip`,
  installés dans `references/em4_base/` comme exemples de logique à réimplémenter.
  Référence locale ignorée par Git, hors du projet Rojo ; aucun script du mod
  CSP-IRG ni fichier binaire n'a été ajouté.
- `references/README.md` explique la provenance et l'usage de ces exemples.
- L’onglet **Missions** propose trois scénarios jouables (église Saint-Marc,
  collision au carrefour et feu de lisière). Les appels de renfort sont déclenchés
  par l’arrivée au parvis, le balisage du carrefour et un signalement radio à 35 s.
  Chaque objectif ouvre la fiche de son intervention. La direction et le
  commandement peuvent lancer ou rejouer un scénario.
- Le bilan comptabilise la gravité, les admissions, les pertes civiles et la
  rapidité de la première arrivée. Le score, l’évaluation et les distinctions
  sont sauvegardés avec les statistiques. Les six catégories EM4 sont adaptées
  au jeu local (secours médical, police, incendie, sauvetage cynophile, gestion
  de catastrophe et or national) avec des seuils propres à ERS. Le maître-chien
  peut être recruté et embarqué sur un engin de sauvetage.

## [0.3.0] — 2026-11-20 — Phase 2 : réseau routier et catalogues enrichis

### Ajouté

- **Réseau routier partagé** `Shared/Utilities/RoadNetwork` : graphe construit
  depuis `Shared/City` (25 carrefours, 40 tronçons), plus court chemin
  **Dijkstra déterministe**, projection d'un point libre sur la chaussée la plus
  proche et trajet en **polyligne** passant par les carrefours. Le cas « même
  tronçon » reste sur ce tronçon, sans détour.
- **Navigation routée** : `Navigation.measure` calcule les longueurs cumulées ;
  `Navigation.route(..., path)` ajoute `points`, `cumulative` et `length` ;
  `Navigation.position` interpole sur la polyligne. Le repli direct reste
  possible quand aucun graphe n'est fourni.
- **Trajets réels** : `Operations.moveTo` et `Operations.release` passent la
  polyligne au trajet ; `WorldService.create` construit `cityPlan` et
  `roadNetwork` ; `DispatchService` calcule l'usure sur la **longueur routière**
  et conserve la distance à vol d'oiseau pour le rayon d'arrivée.
- **Catalogues enrichis** :
  - `Vehicles` : 26 → **34** types (UMH, VLM, VSR, CCGC, VCH, VMO, VRI, VLOG) ;
  - `Equipment` : 18 → **24** références (TRONCONNEUSE, HACHE, TAPIS_SAUT,
    GRENADE_FLASH, BARRAGE, POMPE) ;
  - `Qualifications` : 15 → **23** références (PLONGEUR, MAITRE_CHIEN, TIREUR,
    TIREUR_ELITE, ECLAIREUR, PROFILEUR, NEGOCIATEUR, DEMINEUR) ;
  - `Incidents` : 24 → **32** interventions (FUITE_GAZ, FEU_ELECTRIQUE,
    PRISE_OTAGE, EMEUTE, COLIS_SUSPECT, NOYADE, ACCIDENT_PIETON, SEISME).
- **Rotation d'alertes élargie** à six scénarios jouables avec la flotte
  initiale : `FEU_VEHICULE`, `ACCIDENT_VICTIME`, `FEU_HABITATION`, `MALAISE`,
  `ACCIDENT_DOMESTIQUE`, `VICTIME_INCONSCIENTE`.
- **Tests** : suite unitaire « Réseau routier et navigation » (graphe,
  déterminisme, points sur chaussée, même tronçon, positions début/fin) et audit
  « capacités fournies par le catalogue » vérifiant qu'aucune intervention
  n'exige une capacité absente des engins.
- Tests : **609 assertions** (124 unitaires, 167 intégration, 67 multijoueur,
  251 interface), 0 échec. Build : `build/ERS.rbxlx` (469 901 octets).

#### P0 — conduite et lisibilité (2026-11-22)

- **Éclairage lié à l'horloge** : `Services/LightingService` traduit
  `TimeUtil.hour(world)` en `Lighting.ClockTime`, règle latitude, brillance,
  ambiances intérieure/extérieure et installe une `Atmosphere` unique.
  `Bootstrap` l'applique au démarrage puis à chaque tic, sans réécriture inutile.
  `Config.GROUND_COLOR` passe à `96,108,86` : le sol ne se confond plus avec le
  vide.
- **Aides d'engagement** : nouveau `UI/EngagementHints`. Il produit une phrase
  stable expliquant pourquoi un engagement est impossible (aucune urgence ou
  aucun engin, hors périmètre, engin indisponible, équipage incomplet,
  intervention clôturée) et liste les **capacités manquantes** de l'engin
  choisi. Affiché dans les panneaux Véhicules et Interventions et dans la barre
  inférieure ; les boutons concernés affichent aussi un toast de repli.
- **Nouvelle partie** : action réseau `new_game` réservée à la direction.
  `WorldService.reset` remet budget, parc, effectif, stock, interventions,
  groupes, secteurs, statistiques et horloge à leur état de départ, **conserve
  les postes en ligne** et demande le remplacement de la sauvegarde. Bouton
  visible uniquement pour la direction, avec écran de confirmation.
- **Lisibilité** : titres de fiche véhicule sur deux lignes, boutons d'action
  agrandis (96/92/120/96 × 34), journal ancré et tronqué proprement.
- Tests ajoutés : `TimeUtil.hour` (départ, mi-service, repli 24 h, service nul),
  éclairage (`apply`, `step`, atmosphère unique), `WorldService.reset`,
  `new_game` direction vs observateur, aides d'engagement et confirmation de
  nouvelle partie dans l'interface.
- Vérifié en Studio : bouton « Nouvelle partie » visible pour la direction,
  écran de confirmation, puis toast « budget, parc et effectif réinitialisés »
  avec retour à 25 000 €, 3 engins et 0 urgence. Les aides affichent bien
  « Engin indisponible (En route). » et « Sélectionnez une intervention. ». La
  scène suit l'horloge (06:08 au petit matin, plus claire en milieu de service).

#### Sol, ciel et audio (2026-11-25)

- **Bord du sol masqué** : la dalle ne fait plus `3 × City.WIDTH` mais
  `City.WIDTH + 2 × City.OUTSKIRTS` (118 unités, 708 studs). Une **ceinture
  verte** de 9 unités l'entoure : chemin de gravier, haie basse et **double
  rangée d'arbres** plantée avec un RNG séparé (`seed + 977`) pour ne pas
  décaler la ville existante. La caméra ne voit plus la fin du sol sous
  l'horizon.
- **Ciel procédural** : `SceneService.buildSky` génère une voûte de
  `Config.SKY_STARS = 220` étoiles et une lune, positionnées par le RNG
  déterministe (`seed + 1301`). Aucun asset : tout est construit en code et
  éteint le jour par transparence.
- **Cycle jour/nuit** : `LightingService.daylight` calcule un facteur de jour
  (aube 5–7 h, crépuscule 19–21 h) puis module `Brightness`, `Ambient`,
  `OutdoorAmbient` et l'atmosphère. `applyScene` allume les `PointLight` des
  lampadaires et passe les vitres en `Neon` chaud la nuit.
- **Audio client** : `Controllers/AudioController` monte un `SoundGroup`,
  une ambiance continue, une **sirène à deux tons** (même souffle
  `action_falling.ogg` rejoué à 0,78 et 1,12), des alertes et des bips. Tous
  les sons viennent de `rbxasset://`, aucun upload. Le bouton **SON/MUET** de la
  barre supérieure coupe réellement le groupe et relance la sirène au retour du
  son si un engin reste engagé.
- Tests ajoutés : ceinture boisée hors de la ville, sources `rbxasset://`,
  sirène à deux tons, facteur de jour aux bornes, scène nocturne (étoiles, lune,
  lampadaires, vitres), `AudioController` (montage, ambiance, alerte, sirène,
  mute, démontage) et bascule du bouton **SON/MUET**.

### Corrigé

- **Menu principal refermé au démarrage.** `Échap` était lié au basculement du
  menu, mais Roblox/Studio envoie cette touche quand la fenêtre de jeu prend le
  focus : le menu s'ouvrait puis se refermait aussitôt. La touche est laissée au
  menu de la plateforme ; `M` et le bouton **Menu** ouvrent l'écran, et
  « Entrer en opération » le ferme. `Controller.toggleMenu` (devenu inutile) est
  supprimé et un test vérifie qu'`Échap` ne modifie plus l'état.
- **Mini-carte : trajet en polyligne.** La couche « Trajets » ne dessinait qu'un
  segment de `ax/az` à `bx/bz`, donc un vol d'oiseau à travers les îlots. Elle
  dessine désormais **un segment par tronçon de `route.points`** (repli sur le
  segment direct si la polyligne manque), avec trois tests d'interface associés.
  Vérifié en Studio : le trajet du VPC1 s'affiche en plusieurs segments alignés
  sur les rues.

### Modifié

- `Config.VERSION` passe à `0.3.0` ; les sauvegardes `0.2.0` et `0.1.0` sont
  rejetées comme incompatibles.
- La boucle d'arrivée en intégration avance jusqu'à l'état `onscene` au lieu de
  compter un nombre fixe de tics : un trajet routier est plus long qu'un trajet
  direct.

### Connu / non fait

- **Circulation et piétons**, modèles 3D détaillés et carrière : phases
  suivantes.
- Les nouveaux engins `VCH` et `VLOG` exigent la qualification `TECHNICIEN`,
  absente du roster initial : l'achat est possible, l'équipage reste à prévoir
  (même limitation que `VATELIER`).
- **Publication** : aucune, volontairement.

## [0.2.0] — 2026-11-19 — Phase 1 : ville, caméra isométrique et interface tactique

### Ajouté

- **Plan de ville partagé** `Shared/City` : grille déterministe (graine
  `Config.CITY_SEED = 20261117`) de cinq avenues et cinq rues, seize îlots,
  passages piétons, feux, lampadaires, arbres, bâtiments, deux espaces publics,
  cinq points d'intérêt (hôpital, commissariat, école, gare, industrie), la
  caserne et huit places de stationnement, cinq quartiers. Le plan n'est jamais
  transmis par le réseau : le serveur et chaque client le reconstruisent à
  l'identique.
- **Ville 3D** (`SceneService`) générée depuis ce plan, avec un sol étendu à
  trois fois l'emprise de la carte.
- **Caméra isométrique** (`CameraController`) : orbite 45°, inclinaison 36°,
  champ de vision 34°, distance 420 (bornes 160–760), déplacement borné,
  zoom par pas de 40, rotation par quarts de tour, focus, suivi d'engin,
  recentrage, `viewExtent` et `setViewport`.
- **Contrôle du temps** : `world.timeScale` restreint à
  `Config.TIME_SCALES = { 0, 1, 2, 4 }`, validé par le serveur et soumis à la
  permission `SET_TIME` ; action réseau `set_time_scale` ; le pas de simulation
  est mis à l'échelle et la pause est réelle.
- **Mini-carte tactique** (`UI/MiniMap`) en haut à droite : plan, marqueurs
  cliquables, cadre de visée, boutons de couches (`UNITÉS`, `URG.`, `SECT.`,
  `BÂTI.`, `ÉQUIPES`) et `UIScale` borné (0,55–1) avec `resize` : elle se
  réduit sur les fenêtres courtes au lieu de passer sous la barre.
- **Barre inférieure fixe** (`UI/BottomBar`) : catégories de moyens
  (INC/SAP/POL/TEC/LOG/CMD), groupes 1–6, pause et vitesses, horloge, budget,
  alertes, commandes contextuelles (engager, engager le groupe, rentrer, armer,
  suivre, centrer, fiche, matériel), équipage et matériel de l'unité.
- **Engins et urgences en 3D** (`UI/SceneView`) : un modèle par service,
  gyrophares en intervention, anneau de sélection, balises d'urgence,
  interpolation des positions.
- **Coque d'interface** (`UI/App`) : ville plein écran, mini-carte, barre,
  tiroir de panneaux, journal opérationnel et notifications.
- **Raccourcis** (`InputController`) : `1`–`6` (groupes ou panneaux), `WASD` et
  flèches, `+`/`-`, `Q`/`E`, `Espace`, `R`, `Ctrl+S`, molette et double-clic.
- Tests : **478 assertions** (95 unitaires, 122 intégration, 65 multijoueur,
  196 interface), 0 échec. Build : `build/ERS.rbxlx` (410 262 octets).

### Modifié

- `Config.VERSION` passe à `0.2.0` ; les sauvegardes `0.1.0` sont rejetées
  comme incompatibles, conformément à la règle de version.
- `Theme.sizes.drawerHeight` porté à 340 px (`Theme.sizes.tabsCompact = 152`).
- Les panneaux denses (interventions, véhicules, personnel) passent en **deux
  colonnes** — liste à gauche, fiche à droite — et leur détail devient un
  `ScrollingFrame`. Commandement, budget et postes défilent également.
- `UI/MapPanel` (ancienne carte 2D plein cadre) est **supprimé** : `MiniMap`
  le remplace entièrement.

### Corrigé

- **ZIndex** : le `ScreenGui` passe en `ZIndexBehavior = Enum.ZIndexBehavior
  .Sibling`. En mode `Global`, les enfants restés à `ZIndex = 1` étaient
  dessinés sous le fond de leur conteneur : la mini-carte et la barre
  inférieure apparaissaient vides. Le bricolage `raiseAbove` du menu a été
  supprimé : la hiérarchie suffit désormais.
- **Débordement du tiroir** : `ClipsDescendants = true` et panneaux défilants ;
  plus aucun contenu ne recouvre la barre inférieure.
- **Journal recouvert** : il est décalé à droite de la colonne d'onglets
  (`Position.X = tabsCompact + 16`), qui masquait les heures et les types.
- **Mini-carte sous la barre** : réduction automatique par `UIScale`.
- Doublures de test : `UIScale`, `ZIndexBehavior` et le rendu réconcilié sont
  couverts ; les contrôles de mise en page (colonnes, scroll, échelle)
  échouent désormais en headless si l'interface régresse.

### Connu / non fait

- **Git non installé** : aucun dépôt ni historique. Décision du 17/11 : tout
  reste local pour l'instant.
- **Publication** : aucune, volontairement.
- Réseau routier, modèles 3D détaillés, carrière et note de fin de service :
  phases suivantes.
- Le kit EM4/CSP-IRG fourni sert de **référence de logique** (scripts et
  données d'équilibrage) ; ses assets binaires restent la propriété de leurs
  auteurs et ne sont pas redistribués.

## [0.1.0] — 2026-11-17 — Phase 0 : fondations

### Ajouté

- Projet Rojo `EmergencyResponseSimulator` (`default.project.json`) mappant
  `ReplicatedStorage.Shared`, `ServerScriptService.ERS`, et
  `StarterPlayerScripts.ERSClient`.
- Contrat de développement `AGENTS.md` et configuration d'agent
  `opencode.json`.
- Couche partagée : `Config`, `Constants` (statuts, services, actions, rôles,
  types de journal, libellés de capacité), `Types`, et utilitaires `Result`,
  `MathX`, `Rng`, `TimeUtil`, `Signal`, `Navigation`, `Crew`, `Operations`.
- Catalogues : 26 types de véhicules, 15 qualifications, 18 équipements,
  24 interventions avec étapes, 7 rôles et permissions.
- Services serveur : `Budget`, `Permission`, `Personnel`, `Equipment`,
  `Vehicle`, `Dispatch`, `Incident`, `Command`, `World`, `Simulation`,
  `Snapshot`, `Save`, `Network`, `Scene`.
- `Bootstrap.server.luau` : monde, sauvegarde DataStore avec repli mémoire,
  scène, remotes, boucles de simulation et de snapshot, sauvegarde périodique,
  `BindToClose`.
- Interface tactique : thème, widgets, carte 2D, 7 panneaux (interventions,
  véhicules, personnel, matériel, commandement, budget, postes), menu
  principal, journal et notifications.
- Contrôleurs client : interface, réseau, caméra, entrées.
- Économie : budget initial, mobilisation, récompenses, pénalités, achats,
  réparation, usure.
- Commandement : groupes, secteurs, engagement groupé, bonus de coordination
  de 10 % réellement appliqué.
- Multijoueur : prise et attribution de postes, périmètres de services,
  observateur en lecture seule, anti-spam réseau.
- Sauvegarde versionnée, validation stricte, rejet des versions incompatibles
  et des entrées inconnues.
- Scène 3D de base générée en code : sol, routes, caserne, points d'intérêt,
  bâtiments décoratifs déterministes.
- Documentation : `docs/README.md`, `Architecture.md`, `Gameplay.md`,
  `DataModel.md`, `Changelog.md`, `data/README.md`, `assets/README.md`.
- Harnais `tools/check.ps1` : compilation Luau, quatre suites de tests,
  manifeste reproduisant l'arbre Rojo, sortie non nulle en cas d'échec.
- Tests : 384 assertions (95 unitaires, 109 intégration, 65 multijoueur,
  115 interface), 0 échec.
- Build Rojo : `build/ERS.rbxlx` (331 728 octets).

### Détails d'implémentation notables

- Le journal porte un identifiant monotone (`world.nextLogId`) pour une
  réconciliation d'interface sans clignotement.
- Le bonus de matériel est appliqué **une fois par type présent**, pas par
  unité.
- `Crew.autoSelect` privilégie le service du véhicule avant l'expérience pour
  éviter qu'un chef polyvalent vide la caserne.
- L'interface est testée en headless en cliquant réellement les boutons : les
  faux remotes appellent le vrai `NetworkService.handle`, donc une action sans
  effet serveur fait échouer le test.
- `Rng` est un LCG déterministe, injecté dans le monde ; aucune utilisation de
  `math.random` dans la simulation.

### Corrigé pendant la phase

- Chemin erroné d'un panneau créé hors du projet : fichier déplacé, dossier
  parasite supprimé.
- Test d'interface : le briefing est lu dans le catalogue, pas dans l'état
  serveur ; positions d'incident lues via `incident.position`.
- Rappel d'urgence : le test accepte `returning` ou `available` selon que le
  trajet de retour est déjà terminé.
- Encodage : tous les fichiers écrits en UTF-8 sans BOM ; le harnais copie les
  sources dans un chemin ASCII car le CLI Luau refuse les accents.

### Corrigé après la première vérification dans Studio

Ces défauts n'apparaissaient pas en headless : les doublures étaient plus
permissives que Roblox. Ils ont été trouvés en lançant `build/ERS.rbxlx` en F5.

- **Champs personnalisés sur des Instances** : `Widgets` écrivait `__enabled` et
  `__baseTransparency` sur des `TextButton`, ce que Roblox refuse
  (`__enabled is not a valid member of TextButton`). Le script client
  s'arrêtait avant de monter le réseau, d'où un écran figé sur
  « Synchronisation… » et `Remote event invocation queue exhausted`.
  Remplacé par `button.Active` et une table à clés faibles pour la transparence
  de repos.
- **Frontière réseau** : `NetworkService.handle` exigeait
  `type(player) == "table"`. Dans Roblox, un `Player` est une Instance : toutes
  les commandes réelles étaient refusées avec « Joueur invalide. ». Validation
  par `typeof(...) == "Instance"` et lecture défensive de `UserId`/`Name`, les
  tables restant acceptées pour les tests.
- **Hauteur des listes** : `IncidentPanel`, `VehiclePanel`, `PersonnelPanel` et
  `EquipmentPanel` passaient la fraction dans l'offset
  (`UDim2.new(1, 0, 0, 0.34)` = 0,34 pixel). Les listes existaient mais étaient
  invisibles ; la fraction est désormais portée par l'échelle.
- **Notifications** : elles recouvraient le panneau de droite. Elles sont
  désormais ancrées sur la carte et se retirent seules après huit secondes.
- **Menu assombri** : dans Roblox, le `ZIndex` est global à l'écran, pas relatif
  au parent. La carte du menu et tous ses enfants restaient à 1, donc sous le
  voile (`ZIndex = 40`), qui les recouvrait de 80 % de noir. La sous-arborescence
  de la carte est remontée juste au-dessus du voile, par profondeur. Un test
  vérifie désormais que la carte, les boutons de poste et « Entrer en
  opération » passent devant le voile.
- **Aide clavier** : `Échap` est d'abord capté par le menu Roblox ; `M` ouvre le
  menu depuis la fenêtre de jeu, et le bouton **Menu** reste la voie sûre.
- **Doublures de test** : toute écriture d'un champ `__xxx` inconnu sur une
  Instance déclenche maintenant une erreur, et `typeof` distingue les fausses
  Instances des tables. Ces deux garde-fous auraient attrapé les deux premiers
  défauts.
- Tests : 384 assertions (95 unitaires, 109 intégration, 65 multijoueur,
  115 interface), 0 échec. Build : `build/ERS.rbxlx` (331 728 octets).

### Connu / non fait

- **Git non installé** : aucun dépôt ni historique de commits. `.gitignore` est
  prêt ; `winget install --id Git.Git -e` puis `git init` restent à faire.
  Décision du 17/11 : tout reste local pour l'instant.
- **Publication** : aucune, volontairement.
- Carte complète, modèles 3D, carrière et note de fin de service : phases
  suivantes.
