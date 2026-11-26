# Gameplay

## 1. Boucle de jeu

Vous dirigez le centre de secours de **Val-des-Secours**. Une partie dure un
service de **720 secondes réelles** (12 minutes) représentant **24 heures
simulées**, à partir de 06:00.

```text
alerte → lecture du briefing → composition des équipages → engagement
      → trajet → progression des étapes → résultat → retour → budget
```

Chaque décision est appliquée par le serveur. L'interface ne fait que refléter
l'état reçu.

## 2. État de départ

| Élément | Valeur |
| --- | --- |
| Budget | 25 000 € |
| Flotte | 1 FPT (incendie), 1 VSAV (secours), 1 VPC (commandement) |
| Effectif | 12 agents nommés, qualifications et grades variés |
| Stock | 6 ARI, 6 extincteurs, 6 tuyaux, 3 défibrillateurs, 4 sacs de secours, 2 brancards, 6 radios, 1 PC mobile, 4 balises, 2 cordes |
| Poste du premier joueur | Direction |

Le détail du personnel est dans `WorldService.startingPersonnel`. Les
qualifications couvrent l'incendie (SAPEUR, CHEF_AGRES), le secours à personne
(SECOURISTE, INFIRMIER, MEDECIN), la police (POLICIER, GENDARME), la conduite
et le commandement (COS, CHEF_GROUPE).

## 3. Alertes

- Première alerte après **10 s**, puis toutes les **55 s**.
- Au plus **2 interventions actives** à la fois. Une alerte supplémentaire est
  repoussée de 5 s.
- Rotation de départ, tirée au poids : `FEU_VEHICULE`, `ACCIDENT_VICTIME`,
  `FEU_HABITATION`, `MALAISE`, `ACCIDENT_DOMESTIQUE`, `VICTIME_INCONSCIENTE`.
  Elle reste jouable avec la flotte initiale ; le catalogue complet (32
  interventions) s'ouvre avec les achats et les phases suivantes.
- Une alerte est d'abord `pending`, avec une **date limite de prise en charge**
  définie par le catalogue. Dépasser cette date fait échouer l'intervention et
  applique la pénalité.
- La position est tirée sur la carte (0–100), à plus de 12 unités de la
  caserne et à 8 unités des autres interventions ouvertes.

Le journal reçoit chaque alerte avec son identifiant (`INC-001`, `INC-002`…) et
son secteur géographique (Nord/Sud-Est/Ouest).

## 4. Composition des équipages

Un véhicule ne part que si :

1. il est `available` et son état mécanique est **≥ 20 %** ;
2. son équipage atteint `crewRequired` ;
3. toutes les qualifications exigées par son type sont présentes **au moins
   une fois** dans l'équipage ;
4. l'acteur a le droit `dispatch` et le service du véhicule est dans son
   périmètre.

Le bouton **« Équipage auto »** sélectionne les membres :

- d'abord les titulaires des qualifications exigées par le véhicule ;
- puis les meilleurs disponibles, **en privilégiant le service du véhicule**
  avant l'expérience (un chef COS polyvalent ne vide pas la caserne) ;
- dans la limite de `min(crewRequired, seats)`.

Un membre déjà affecté, trop fatigué (≥ 85) ou en mauvaise santé est exclu.
L'affectation manuelle reste possible depuis le panneau Personnel.

## 5. Engagement et trajets

`dispatch` vérifie l'état, l'équipage, les droits, puis débite le **coût de
mobilisation** du type de véhicule. Ensuite :

```text
durée = TRAVEL_BASE + (longueur × TRAVEL_PER_UNIT) / vitesse
        × 0,75 si sirène
```

avec `TRAVEL_BASE = 4 s`, `TRAVEL_PER_UNIT = 0,8`, une vitesse minimale de
0,2 et une durée plancher de 0,1 s. **La longueur est celle du trajet routier**,
pas la distance à vol d'oiseau : l'engin quitte sa place, rejoint la chaussée
la plus proche, suit les avenues et les rues jusqu'au carrefour utile, puis
rejoint le point d'intervention. Le graphe est construit depuis `Shared/City`
(`RoadNetwork`) ; il est déterministe et identique côté serveur et côté client.

À l'arrivée (rayon 0,8 unité), le véhicule passe `onscene` et l'intervention
devient `active`. Un engin déjà sur place bascule immédiatement.

**Usure** : chaque engagement retire `1 + longueur/50` points, borné entre 1 et
6. Sous 20 % au retour, le véhicule est immobilisé à l'atelier.

**Rappel** : `recall` sort le véhicule de l'intervention, le passe `returning`
puis `available`. Le retour suit lui aussi le réseau routier et reste
automatique à la clôture de l'intervention.

## 6. Déroulé d'une intervention

Chaque type du catalogue `Incidents` contient :

- `requires` : capacités cumulées exigées globalement (`fire`, `rescue`,
  `medical`, `police`, `command`, `technical`) ;
- `steps` : étapes ordonnées, chacune avec son besoin et sa durée ;
- `equipment` : matériel devant être présent sur au moins un engin sur place ;
- `qualifications` : qualifications devant être présentes dans les équipages ;
- `responseDeadline`, `victims`, `reward`, `penalty`, `severity`, `weight`.

### Progression

À chaque tic, on cumule la puissance des véhicules **sur place** :

```text
puissance = somme des capabilities du type
          + bonus du matériel installé (une fois par type présent, quel que soit le nombre)
          × (1 + bonus de secteur)
```

Le bonus de secteur vaut **+10 %** si un secteur couvre l'intervention et
qu'un engin de son groupe y est réellement sur place.

Pour l'étape courante, chaque capacité est comparée à son besoin. Si toutes
sont couvertes, la progression avance à la vitesse
`0,6 + 0,4 × ratio` (ratio minimal de couverture, plafonné à 1). Sinon
`underpoweredFor` augmente.

### Issues

| Situation | Résultat |
| --- | --- |
| Toutes les étapes terminées, moyens globaux couverts, matériel et qualifications présents | **Succès complet** : récompense pleine, toutes les victimes prises en charge |
| Étapes terminées mais matériel ou qualification manquant | **Succès dégradé** : 50 % de la récompense, moitié des victimes |
| Date limite dépassée avant le premier engagement | **Échec** : pénalité |
| Aucun véhicule engagé (plus rien d'assigné) pendant 60 s | **Échec** : « aucun moyen resté sur place » |
| Étape non couverte pendant 60 s | **Échec** : moyens insuffisants pour l'étape |
| Moyens globaux insuffisants après les étapes | **Échec** |

Un échec libère tous les véhicules engagés, applique la pénalité (le budget
peut devenir négatif : c'est un état de jeu assumé) et alimente
`stats.failed`.

## 7. Économie

| Flux | Règle |
| --- | --- |
| Dotation initiale | 25 000 € |
| Mobilisation | coût du type de véhicule, **non remboursé** |
| Réussite | `reward` du catalogue, ou 50 % si dégradé |
| Échec | `penalty` du catalogue, appliquée même sans solde suffisant |
| Achat | prix du catalogue, refusé si parc complet (40) ou solde insuffisant ; remboursé si la création échoue |
| Réparation | `12 € × points manquants`, immobilisation `1,5 s × points manquants` |

Chaque mouvement est enregistré dans `world.transactions` (120 dernières) et
les opérations d'argent apparaissent dans « Dernières opérations » du panneau
Budget. `spent` et `earned` sont cumulés dans `stats`.

## 8. Matériel

Le stock est global (`world.equipmentStock`) et le matériel installé appartient
au véhicule. Installer déplace le stock vers l'engin ; retirer fait l'inverse.
Les deux sont refusés si la quantité demandée dépasse le stock ou
l'emplacement disponible.

Le matériel installé compte dans la puissance de l'engin via son `bonus` de
capacité. **Le bonus est appliqué une fois par type présent**, pas multiplié
par la quantité : trois extincteurs ne valent pas trois fois l'extincteur.

Le matériel exigé par une intervention doit être présent sur **au moins un
engin sur place** au moment de la conclusion.

## 9. Personnel et fatigue

| Situation | Effet |
| --- | --- |
| En intervention | +0,05 fatigue/s |
| Affecté à un engin, hors intervention | +0,01 fatigue/s |
| Non affecté | −0,10 fatigue/s |

Un agent à **85 de fatigue** ne peut plus être affecté ; il doit se reposer.
La santé sous 1 le rend indisponible. La fatigue et la santé sont sauvegardées.

## 10. Commandement

- **Groupe** : nom, service optionnel, liste de véhicules. Un véhicule ne peut
  appartenir qu'à un groupe à la fois.
- **Secteur** : nom, centre `(x, z)`, rayon. Un secteur peut être affecté à un
  groupe ; l'affectation est réciproque (`sector.groupId` et `group.sectorId`).
- **Engagement groupé** : engage tous les véhicules disponibles du groupe sur
  une intervention, en appliquant les mêmes contrôles qu'un engagement
  individuel. Un véhicule refusé n'interrompt pas les autres ; le bilan est
  renvoyé dans le message.
- **Bonus** : +10 % de moyens si un secteur couvre l'intervention et qu'un
  engin de son groupe est sur place.

La dissolution d'un groupe libère ses secteurs. Aucun bonus n'est appliqué si
le groupe n'a pas d'engin réellement sur les lieux.

## 11. Rôles et coopération

| Rôle | Actions | Périmètre |
| --- | --- | --- |
| **Direction** | toutes, y compris budget, achats, rôles, sauvegarde | tous services |
| **Commandement** | voir, engager, rappeler, affecter, équiper, réparer, commander | tous services |
| **Incendie** | voir, engager, rappeler, affecter, équiper | incendie |
| **Secours** | voir, engager, rappeler, affecter, équiper | secours |
| **Police** | voir, engager, rappeler, affecter, équiper | police |
| **Logistique** | voir, engager, rappeler, affecter, équiper, réparer | technique, logistique, commandement |
| **Observateur** | voir | aucun |

Le premier joueur connecté devient **Direction**. Un joueur peut prendre un
poste libre (`claim_role`). La Direction peut attribuer un poste à un autre
joueur (`assign_role`) ; elle ne peut pas confisquer la Direction, et un poste
déjà tenu est refusé.

Le périmètre est vérifié **côté serveur** à chaque engagement : un rôle
Incendie ne peut pas engager un VSAV, même en forgeant la requête.

## 12. Fin de service

À 720 s, `world.finished = true` :

- plus aucune alerte n'est générée ;
- une sauvegarde est demandée ;
- le journal annonce la relève ;
- les interventions en cours continuent d'évoluer.

Les indicateurs disponibles dans le snapshot sont : interventions résolues,
dégradées, échouées, victimes prises en charge, dépenses, recettes, budget.
Il n'y a pas encore de note de fin de service ni de progression de carrière :
ces éléments relèvent des phases suivantes.

## 13. Caméra, temps et mini-carte

**Caméra isométrique.** La caméra est scriptée, jamais libre : orbite
`yaw = 45°`, inclinaison `pitch = 36°`, champ de vision `34°`, distance
`420` studs (bornes `160–760`). `WASD`/flèches déplacent la cible sur le plan,
`+`/`-` zooment par pas de 40, `Q`/`E` pivotent par quarts de tour, `R`
recentre sur la caserne, un double-clic recentre sur l'unité sélectionnée.
Le déplacement est borné à l'emprise de la carte ; il reste **local** et ne
produit aucun message réseau.

**Temps simulé.** `world.timeScale` ne peut prendre que les valeurs de
`Config.TIME_SCALES = { 0, 1, 2, 4 }` (`0` = pause). Le client n'envoie qu'une
intention `set_time_scale` ; le serveur vérifie la valeur **et** la permission
`SET_TIME` (direction, commandement) avant de l'appliquer. La pause et les
boutons `×1`, `×2`, `×4` de la barre inférieure passent tous par ce chemin :
un refus devient une notification, jamais un changement local.

**Mini-carte.** Elle est reconstruite depuis `Shared/City` — le client ne reçoit
aucune géométrie. Elle affiche les engins, les urgences et les secteurs du
snapshot, ainsi qu'un cadre de visée qui correspond exactement à ce que voit la
caméra (`CameraController.viewExtent`). Les boutons `UNITÉS`, `URG.`, `SECT.`,
`BÂTI.` et `ÉQUIPES` masquent ou affichent réellement les marqueurs
correspondants. Cliquer un marqueur sélectionne l'élément, ouvre le panneau
associé et braque la caméra sur sa position.

## 14. Commandes

Voir [README.md](README.md#commandes-en-jeu). Les raccourcis ne modifient que
l'état local ou envoient une intention déjà autorisée ; `S` est refusé côté
client **et** côté serveur pour un poste sans droit de sauvegarde.

## 15. Ce qui n'est pas encore implémenté

- Modèles 3D détaillés des engins et des personnages, circulation et piétons
  (Phase 3 : la ville est une grille déterministe générée en code).
- Carrière, grades évolutifs, progression de statistiques.
- Météo, cycles jour/nuit visuels, foule, blessés individuels.
- Notes de fin de service et classements.
- Publication : aucune.
