# Comparaison — Emergency 4, MOD CSP-IRG et ERS

Document de travail : ce que fait le jeu de référence, ce que fait ERS en
version `0.3.0`, et ce qui manque encore. Les assets binaires du kit ne sont
pas comparés : ils ne sont ni repris ni redistribués.

La version locale 0.4.0 et ses ajouts sont décrits dans le [guide de jeu](Gameplay.md) et le [journal des changements](Changelog.md).

## 1. Sources

| Source | Usage |
| --- | --- |
| `EM4_Roblox_Kit/01_ANALYSE/*` | architecture, rôles, missions, scripts, formats |
| `EM4_Roblox_Kit/02_DONNEES/*.json` | comptages et paramètres (unités, freeplay, campagne) |
| `EM4_Roblox_Kit/04_MOD_CSP_IRG/*` | contenu du mod (36 personnels, 113 véhicules) |
| `references/em4_base/` (local, ignoré par Git) | 134 scripts texte du jeu de base à consulter comme exemples de logique |
| `src/` et `tests/` d'ERS | couverture réelle, vérifiée par `tools/check.ps1` |
| Session Studio du 20–21/11/2026 | constats visuels et fonctionnels |

## 2. Contenu en chiffres

| Domaine | EM4 de base | MOD CSP-IRG | ERS 0.3.0 |
| --- | ---: | ---: | ---: |
| Types de personnel | 13 | 36 | 12 agents fixes + 23 qualifications |
| Types de véhicules | 29 | 113 | 34 |
| Équipements | 8 | 8 (réutilisés) | 24 |
| Interventions / événements | dizaines (`events.xml`) | scripts réécrits | 32 |
| Campagne | 20 missions + tutoriel + 3 spéciales | missions re-scriptées | 0 (freeplay seul) |
| Cartes | 35 | cartes françaises | 1 carte générée |
| Matériaux de feu | 151 | 151 | 0 |
| Scripts de commande | 103 | 103 réécrits | 13 actions réseau |
| Niveaux de personnel | 0 à 3 (améliorations) | idem | 0 |
| Score / rating / awards | oui (6 awards) | oui | non (compteurs `stats`) |
| Multijoueur | 4 joueurs, tours d'achat | idem | rôles + permissions, sans tours |

Le mod ajoute **149 unités** (36 personnels + 113 véhicules) ; la base en compte
50 (13 + 29 + 8). ERS couvre les **rôles** du mod, pas son volume : 23
qualifications (COS, SAPEUR, ARI via équipement, SAMU via MEDECIN/INFIRMIER,
CRS via POLICIER, GIGN via TIREUR_ELITE/NEGOCIATEUR/DEMINEUR, TEC via
TECHNICIEN…).

## 3. Boucle de jeu

| Étape | EM4 | ERS |
| --- | --- | --- |
| 1. Alerte | événement procédural ou script de mission | `IncidentService.spawn`, 32 catalogues, 6 en rotation |
| 2. Moyens | achat/deploy de véhicules **et** de personnels | 3 engins de départ, achats de véhicules, équipages |
| 3. Déplacement | pathfinding routier des véhicules **et** des personnels | pathfinding routier des véhicules uniquement |
| 4. Action | 103 commandes spatiales (éteindre, sauver, soigner, arrêter…) | étapes abstraites validées par les capacités présentes |
| 5. Résolution | objets/ victimes/ incendie réellement traités | `success` si capacités + matériel + qualifications suffisent |
| 6. Progression | budget, score, rating, awards, campagne | budget, compteurs, sauvegarde |

**Écart structurant** : EM4 est une simulation tactique spatiale ; ERS est pour
l'instant une simulation de **commandement et de moyens**. Les étapes
d'intervention sont des cases à cocher de capacités, pas des actions de terrain.
C'est le plus gros écart fonctionnel, avant même le contenu.

## 4. Systèmes : présent, partiel, absent

| Système EM4 | ERS 0.3.0 | État |
| --- | --- | --- |
| Graphe routier + trajets | `RoadNetwork` + `Navigation` + `Operations` | **livré** |
| Engins, équipages, matériel | catalogues + services + panneaux | **livré** |
| Groupes, secteurs, engagement groupé | `CommandService` + panneau | **livré** (bonus 10 %) |
| Alertes procédurales, délais, pénalités | `IncidentService` + `SimulationService` | **livré** |
| Sauvegarde versionnée | `SaveService` + DataStore | **livré** |
| Multijoueur par postes | `PermissionService` + réseau validé | **livré, autre modèle** |
| Commandes individuelles du personnel | — | **absent** |
| Simulation du feu (matériaux, propagation, fumée) | — | **absent** |
| Eau, lance, extinction progressive | bonus `fire` seulement | **absent** |
| Transport des victimes à l'hôpital | victimes comptées à la clôture | **absent** |
| Arrestations, garde à vue, poursuites | capacité `police` seulement | **absent** |
| Entrée dans les bâtiments, étages, civières | — | **absent** |
| Recrutement de personnel | roster fixe de 12 | **absent** |
| Revente de véhicules | achat seulement | **absent** |
| Améliorations niveau 0–3 | — | **absent** |
| Campagne, objectifs, triggers, cinématiques | — | **absent** |
| Score, rating, difficulté, awards | `world.stats` | **absent** |
| Cycle jour/nuit visuel | `ClockTime` + `Atmosphere` liés à l'horloge | **partiel** (pas de ciel étoilé ni d'éclairage public dynamique) |
| Audio, voix, radio | — | **absent** |
| Circulation, piétons | — | **absent** (Phase 3) |

## 5. Problèmes constatés en test

### 5.1 Mini-carte : trajet dessiné en ligne droite — corrigé

`UI/MiniMap.luau` (couche « Trajets ») n'utilisait que `route.ax/az` et
`route.bx/bz` : un seul segment rectiligne. Depuis la Phase 2, le véhicule suit
une **polyligne** (`route.points`), mais la carte ignorait ces points : elle
montrait un trajet qui traversait les îlots alors que l'engin suivait les rues.

Correction livrée : un conteneur par engin, puis **un segment par couple de
points consécutifs** de `route.points` (repli sur `ax/az → bx/bz` si absent).
Trois tests d'interface vérifient la polyligne serveur, le nombre de segments
(`#points - 1`) et leur visibilité. Aucun changement serveur n'a été nécessaire.
Vérifié en Studio : le trajet du VPC1 apparaît en plusieurs segments alignés sur
les rues, depuis la caserne jusqu'à l'urgence.

### 5.2 Éclairage et sol — corrigé en partie

- `Config.GROUND_COLOR` est passé de `46,54,48` à `96,108,86` : le sol ne se
  confond plus avec le vide noir.
- `LightingService` relie désormais `Lighting.ClockTime` à `world.time` et
  installe une `Atmosphere` légère ; l'heure affichée n'est plus purement
  textuelle. Vérifié par des tests d'intégration (`apply`, `step`, atmosphère
  unique).
- Le sol fait toujours `3 ×` l'emprise de la carte : son bord reste visible.
  Réduire ce débordement ou ajouter un ciel reste à faire.

### 5.3 Actions sans retour visible — corrigé

Le module `UI/EngagementHints` affiche une phrase contextuelle sous les boutons
d'engagement des panneaux Véhicules et Interventions et dans la barre inférieure.
Elle nomme la cause exacte : aucune intervention ou aucun engin sélectionné,
hors périmètre du poste, engin indisponible (avec son statut), équipage incomplet
(`2/4`), intervention clôturée. Les capacités manquantes de l'engin choisi sont
listées séparément, sans bloquer l'engagement. Un clic sur un bouton encore actif
produit un toast explicite au lieu d'un silence.

### 5.4 Pas de « nouvelle partie » — corrigé

L'action réseau `new_game` est réservée à la direction. `WorldService.reset`
remet budget, parc, effectif, stock, interventions, groupes, secteurs,
statistiques et horloge à leur état de départ, **conserve les postes en ligne**
et demande le remplacement de la sauvegarde. Le menu propose « Nouvelle partie »
uniquement pour la direction, avec un écran de confirmation ; l'annulation ne
touche à rien. Vérifié en intégration (direction acceptée, observateur refusé) et
dans l'interface (visibilité, confirmation, effet serveur).

### 5.5 Temps affiché ambigu

L'horloge avance de **2 minutes simulées par seconde réelle**
(`SHIFT_SECONDS = 720` pour 24 h). Les délais d'intervention sont affichés en
secondes réelles (`0:42`). Les deux échelles cohabitent sans explication : le
joueur voit midi avancer très vite alors qu'il ne lui reste que 42 s.

### 5.6 Engagement d'un moyen inadapté

Envoyer le VPC (police) sur un feu est accepté, puis échoue faute de moyens.
EM4 permet aussi l'erreur, mais affiche les moyens requis. ERS les affiche
(`Moyens requis : Incendie 1`) sans avertissement au départ. Une confirmation
ou un badge « moyen inadapté » éviterait une pénalité incompréhensible.

### 5.7 Équipages incomplets

`VCH` et `VLOG` exigent `TECHNICIEN`, absent du roster initial : achat possible,
équipage impossible. Même limitation que `VATELIER`. Il manque au minimum un
technicien de départ ou un recrutement.

### 5.8 Points d'intérêt décoratifs

Hôpital, commissariat, école, gare et zone industrielle sont construits et
étiquetés, mais n'ont aucun rôle de gameplay. L'hôpital est le plus visible :
aucun transport de victime n'y aboutit.

### 5.9 Lisibilité — corrigé en partie

- Le titre de la fiche véhicule passe sur deux lignes (`TextWrapped`) au lieu
  d'être tronqué.
- Les boutons d'action de la fiche véhicule sont agrandis (96/92/120/96 × 34).
- Le journal est ancré, ses lignes sont tronquées proprement (`TextTruncate`) et
  l'aide de la barre inférieure est agrandie à 9 px.
- La mini-carte conserve des libellés à 9 px : la lisibilité en 1080p reste à
  surveiller, mais aucun texte n'est plus coupé sans indication.

### 5.10 Robustesse de la session Studio

La session de test a consommé jusqu'à ~3,6 Go (log Studio), puis s'est fermée
proprement. Aucune erreur de script n'a été relevée dans le log ; la fermeture
n'est pas attribuée au jeu, mais la consommation mémoire mérite une surveillance
lors des longues sessions (snapshots 4 Hz, journal 120 entrées, scène statique).

## 6. Écarts d'équilibrage

| Paramètre | EM4 freeplay | ERS 0.3.0 |
| --- | ---: | ---: |
| Budget initial | 75 000 | 25 000 |
| Budget maximum | 160 000 | pas de plafond explicite |
| Gain de référence | 30 000 | récompenses 300–5 000 |
| Achat | `BuyFactor` 10 | coûts fixes 8 000–34 000 |
| Revente | 50 % | aucune |
| Inflation des escouades | +30 | aucune |
| Premier événement | 5 s | 10 s |
| Intervalle entre événements | 30 s min | 55 s |
| Événements actifs | non plafonné explicitement | 2 |
| Début de service | 7:30 | 6:00 |
| Échelle de temps | `TimeSpeedFactor` 1 | 0 / 1 / 2 / 4 |
| Difficulté | rating 20/30/45, abandon à 550 | délais + pénalités fixes |
| Score | 500/min + pénalités | aucun score |
| Awards | 6 | aucun |

ERS est donc plus **petit, plus court et plus lisible** : une partie de 12
minutes, 2 urgences, des moyens limités. Ce n'est pas un défaut en soi, mais
c'est une différence de promesse : EM4 est une simulation longue, ERS est une
session tactique courte.

## 7. Ce qu'ERS fait mieux (à conserver)

- **Serveur autoritaire** de bout en bout, validé par 609 assertions.
- **Déterminisme** : graine, RNG local, tri des identifiants, aucun
  `math.random` dans la simulation.
- **Zéro asset propriétaire** : ville, engins et interface générés en code.
- **Interface française lisible** : sept panneaux, mini-carte, barre fixe,
  journal, notifications, permissions.
- **Traçabilité** : chaque action réseau a un handler, une validation et un
  test ; aucune fonction décorative.
- **Sauvegarde tolérante** : entrées inconnues ignorées, version stricte.

## 8. Priorités proposées

### P0 — corriger ce qui est visible

1. ~~Tracé de la mini-carte sur `route.points`.~~ **fait** en 0.3.0.
2. ~~Éclairage : sol plus clair, `ClockTime` lié à `world.time`, atmosphère.~~
   **fait** (`LightingService`, sol éclairci, bord du sol masqué par une
   ceinture boisée, ciel étoilé la nuit).
3. ~~Retour explicite quand « Engager » est impossible.~~ **fait**
   (`EngagementHints`).
4. ~~« Nouvelle partie » (effacement de la sauvegarde) depuis le menu.~~ **fait**
   (`new_game` réservé à la direction, confirmation).
5. ~~Troncature des titres et taille des boutons.~~ **fait** (titres sur deux
   lignes, boutons agrandis, journal tronqué).
6. ~~Ambiance sonore : sirènes, alertes, coupure du son.~~ **fait**
   (`AudioController`, bouton **SON/MUET**, sons `rbxasset://` uniquement).

### P1 — combler les manques de gameplay

1. Recrutement de personnel (au moins un technicien) et revente.
2. Transport des victimes vers l'hôpital (capacité, trajet, délai).
3. Actions de terrain simplifiées par équipe (extinction, sauvetage,
   désincarcération) au lieu d'un simple compteur.
4. Simulation de feu minimale : matériaux, inflammation, propagation,
   extinction à l'eau.

### P2 — contenu et progression

1. Score, rating, pénalités civiles, 6 awards.
2. ~~Cycle jour/nuit visuel et audio (sirènes, radio).~~ **fait** pour le
   visuel et les sirènes ; radio et voix restent à faire.
3. 2–3 missions scénarisées (église, accident routier, forêt) avec objectifs
   et triggers, sans porter les 20 missions.

### P3 — confort

1. Tours d'achat multijoueur, améliorations 0–3, inflation.
2. Circulation et piétons.

## 9. Conclusion

ERS 0.3.0 tient sa promesse technique : boucle complète, serveur autoritaire,
réseau routier réel, catalogues enrichis, tests verts. Il lui manque la couche
qui fait la profondeur d'EM4 : **les actions spatiales** (personnel, feu,
victimes) et la **progression** (score, campagne, recrutement). Les prochaines
phases doivent être choisies en fonction de cette différence, pas du volume de
catalogues.
