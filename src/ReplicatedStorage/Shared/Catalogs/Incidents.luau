--!strict
--[[
	Incidents — catalogue des interventions (spec §10).

	Chaque intervention a :
	- des moyens globaux requis (`requires` : capacités cumulées) ;
	- des étapes ordonnées (`steps`) avec leur propre besoin ;
	- du matériel et des qualifications exigés ;
	- une date limite de prise en charge, des victimes, un gain et une pénalité.

	Les étapes rendent le déroulé réel : reconnaissance, protection, sauvetage,
	attaque, déblaiement… Une étape ne progresse que si les moyens présents
	sur place couvrent son besoin.
]]

local Incidents = {}

local function step(id: string, label: string, requires: any, seconds: number): any
	return {
		id = id,
		label = label,
		requires = requires,
		seconds = seconds,
	}
end

Incidents.list = {
	-- ═══════════════════ INCENDIES ═══════════════════
	{
		id = "FEU_VEHICULE",
		name = "Feu de véhicule",
		service = "fire",
		severity = 1,
		requires = { fire = 1 },
		equipment = { "EXTINCTEUR" },
		qualifications = { "SAPEUR" },
		steps = {
			step("protection", "Protection et balisage", { fire = 1 }, 4),
			step("extinction", "Extinction du véhicule", { fire = 2 }, 12),
			step("reconnaissance", "Reconnaissance du point chaud", { fire = 1 }, 4),
		},
		responseDeadline = 75,
		victims = 0,
		reward = 350,
		penalty = 180,
		weight = 12,
		briefing = "Un véhicule est en feu sur la chaussée. Le conducteur a pu sortir. "
			.. "Sécurisez la zone, éteignez le foyer et vérifiez l'absence de point chaud.",
	},
	{
		id = "FEU_HABITATION",
		name = "Feu d'habitation",
		service = "fire",
		severity = 3,
		requires = { fire = 4, rescue = 2, medical = 2 },
		equipment = { "ARI" },
		qualifications = { "CHEF_AGRES" },
		steps = {
			step("reconnaissance", "Reconnaissance et protection", { fire = 2 }, 6),
			step("sauvetage", "Sauvetage des occupants", { rescue = 2 }, 12),
			step("attaque", "Attaque du feu", { fire = 4 }, 18),
			step("deblaiement", "Déblaiement et surveillance", { fire = 1 }, 8),
		},
		responseDeadline = 120,
		victims = 3,
		reward = 1500,
		penalty = 800,
		weight = 7,
		briefing = "Fumée épaisse au premier étage d'une maison. Des occupants sont "
			.. "signalés à l'intérieur. Engagez un engin incendie et un véhicule de secours.",
	},
	{
		id = "FEU_APPARTEMENT",
		name = "Feu d'appartement",
		service = "fire",
		severity = 2,
		requires = { fire = 3, rescue = 1, medical = 1 },
		equipment = { "ARI" },
		qualifications = { "CHEF_AGRES" },
		steps = {
			step("reconnaissance", "Reconnaissance en étage", { fire = 2 }, 5),
			step("attaque", "Attaque du feu", { fire = 3 }, 14),
			step("ventilation", "Ventilation et contrôle", { fire = 1 }, 6),
		},
		responseDeadline = 95,
		victims = 1,
		reward = 900,
		penalty = 480,
		weight = 9,
		briefing = "Un appartement au troisième étage dégage une fumée noire. "
			.. "Les voisins indiquent qu'une personne âgée vit seule au logement.",
	},
	{
		id = "FEU_COMMERCE",
		name = "Incendie de commerce",
		service = "fire",
		severity = 2,
		requires = { fire = 3, rescue = 1, medical = 1 },
		equipment = { "ARI" },
		qualifications = { "CHEF_AGRES" },
		steps = {
			step("protection", "Protection des façades", { fire = 2 }, 6),
			step("attaque", "Attaque du feu", { fire = 3 }, 16),
			step("reconnaissance", "Reconnaissance des réserves", { fire = 1 }, 6),
		},
		responseDeadline = 95,
		victims = 0,
		reward = 1000,
		penalty = 520,
		weight = 7,
		briefing = "L'alarme incendie d'un commerce est confirmée par un riverain. "
			.. "De la fumée sort de la réserve. Le personnel est évacué.",
	},
	{
		id = "FEU_INDUSTRIE",
		name = "Incendie industriel",
		service = "fire",
		severity = 3,
		requires = { fire = 5, rescue = 3, medical = 2, technical = 1 },
		equipment = { "ARI", "COMBINAISON" },
		qualifications = { "CHEF_AGRES", "TECHNICIEN" },
		steps = {
			step("securisation", "Sécurisation du site", { fire = 2, technical = 1 }, 8),
			step("sauvetage", "Évacuation des ateliers", { rescue = 3 }, 14),
			step("attaque", "Attaque et refroidissement", { fire = 5 }, 22),
			step("decontamination", "Contrôle des effluents", { technical = 1 }, 10),
		},
		responseDeadline = 140,
		victims = 4,
		reward = 2600,
		penalty = 1400,
		weight = 4,
		briefing = "Départ de feu dans un atelier chimique. Le site demande une "
			.. "reconnaissance des produits stockés et un contrôle des effluents.",
	},
	{
		id = "FEU_FORET",
		name = "Feu de végétation",
		service = "fire",
		severity = 3,
		requires = { fire = 4, rescue = 1 },
		equipment = { "TUYAU" },
		qualifications = { "SAPEUR" },
		steps = {
			step("estimation", "Estimation du front", { fire = 2 }, 6),
			step("attaque", "Attaque des lisières", { fire = 4 }, 20),
			step("noyage", "Noyage et surveillance", { fire = 2 }, 10),
		},
		responseDeadline = 130,
		victims = 0,
		reward = 1300,
		penalty = 700,
		weight = 5,
		briefing = "Un départ de feu en lisière de forêt progresse vers des habitations. "
			.. "Engagez un moyen autonome en eau.",
	},

	-- ═══════════════════ SECOURS À PERSONNE ═══════════════════
	{
		id = "MALAISE",
		name = "Malaise sur la voie publique",
		service = "medical",
		severity = 1,
		requires = { medical = 1 },
		equipment = { "SAC_SECOURS" },
		qualifications = { "SECOURISTE" },
		steps = {
			step("evaluation", "Évaluation de la victime", { medical = 1 }, 8),
			step("soins", "Soins et surveillance", { medical = 1 }, 10),
		},
		responseDeadline = 80,
		victims = 1,
		reward = 280,
		penalty = 150,
		weight = 13,
		briefing = "Une personne est prise d'un malaise sur un trottoir. Elle est "
			.. "consciente mais pâle. Un témoin est resté à ses côtés.",
	},
	{
		id = "ARRET_CARDIAQUE",
		name = "Arrêt cardio-respiratoire",
		service = "medical",
		severity = 3,
		requires = { medical = 2 },
		equipment = { "DEFIB" },
		qualifications = { "SECOURISTE" },
		steps = {
			step("reanimation", "Réanimation et défibrillation", { medical = 2 }, 12),
			step("stabilisation", "Stabilisation", { medical = 2 }, 10),
			step("evacuation", "Évacuation médicalisée", { medical = 1 }, 8),
		},
		responseDeadline = 70,
		victims = 1,
		reward = 950,
		penalty = 600,
		weight = 8,
		briefing = "Un homme s'est effondré en pleine rue. Un témoin pratique un "
			.. "massage cardiaque. Un défibrillateur est indispensable.",
	},
	{
		id = "ACCIDENT_DOMESTIQUE",
		name = "Accident domestique",
		service = "medical",
		severity = 1,
		requires = { medical = 1 },
		equipment = { "SAC_SECOURS" },
		qualifications = { "SECOURISTE" },
		steps = {
			step("evaluation", "Bilan et immobilisation", { medical = 1 }, 10),
			step("evacuation", "Évacuation", { medical = 1 }, 8),
		},
		responseDeadline = 85,
		victims = 1,
		reward = 300,
		penalty = 160,
		weight = 10,
		briefing = "Une personne est tombée dans son escalier. Elle se plaint de "
			.. "douleurs à la jambe et ne peut plus se relever.",
	},
	{
		id = "VICTIME_INCONSCIENTE",
		name = "Victime inconsciente",
		service = "medical",
		severity = 2,
		requires = { medical = 2 },
		equipment = { "OXYGENE" },
		qualifications = { "SECOURISTE" },
		steps = {
			step("evaluation", "Bilan vital", { medical = 1 }, 8),
			step("oxygenation", "Oxygénothérapie", { medical = 2 }, 10),
			step("evacuation", "Conditionnement", { medical = 1 }, 8),
		},
		responseDeadline = 85,
		victims = 1,
		reward = 520,
		penalty = 300,
		weight = 9,
		briefing = "Une personne a été retrouvée inconsciente dans un jardin. "
			.. "La respiration est présente mais irrégulière.",
	},

	-- ═══════════════════ ACCIDENTS ═══════════════════
	{
		id = "ACCIDENT_VICTIME",
		name = "Accident de circulation avec victime",
		service = "medical",
		severity = 2,
		requires = { rescue = 1, medical = 2 },
		equipment = { "SAC_SECOURS" },
		qualifications = { "SECOURISTE" },
		steps = {
			step("protection", "Protection de la zone", { rescue = 1 }, 4),
			step("evaluation", "Évaluation des victimes", { medical = 2 }, 8),
			step("evacuation", "Évacuation", { medical = 2 }, 12),
		},
		responseDeadline = 90,
		victims = 2,
		reward = 700,
		penalty = 350,
		weight = 11,
		briefing = "Deux véhicules se sont percutés à une intersection. Une "
			.. "personne est bloquée côté passager, une autre est indemne.",
	},
	{
		id = "ACCIDENT_CIRCULATION",
		name = "Accident de circulation",
		service = "medical",
		severity = 2,
		requires = { rescue = 2, medical = 1, police = 1 },
		equipment = { "SAC_SECOURS", "BALISE" },
		qualifications = { "SECOURISTE" },
		steps = {
			step("protection", "Balisage et déviation", { police = 1 }, 6),
			step("desincarceration", "Dégagement de la victime", { rescue = 2 }, 12),
			step("soins", "Soins sur place", { medical = 1 }, 8),
		},
		responseDeadline = 95,
		victims = 2,
		reward = 850,
		penalty = 420,
		weight = 8,
		briefing = "Collision sur une route départementale. La circulation est "
			.. "bloquée dans les deux sens et une victime est incarcérée.",
	},
	{
		id = "CARAMBOLAGE",
		name = "Carambolage",
		service = "medical",
		severity = 3,
		requires = { rescue = 4, medical = 3, police = 2 },
		equipment = { "SAC_SECOURS", "BALISE" },
		qualifications = { "SECOURISTE", "CHEF_AGRES" },
		steps = {
			step("protection", "Fermeture et balisage", { police = 2 }, 8),
			step("triage", "Triage des victimes", { medical = 2 }, 10),
			step("desincarceration", "Désincarcérations", { rescue = 4 }, 18),
			step("evacuation", "Évacuations multiples", { medical = 3 }, 14),
		},
		responseDeadline = 130,
		victims = 6,
		reward = 2400,
		penalty = 1200,
		weight = 3,
		briefing = "Plusieurs véhicules sont impliqués sur l'autoroute. Plusieurs "
			.. "victimes sont signalées, dont deux incarcérées. Prévoir un triage.",
	},
	{
		id = "DESINCARCERATION",
		name = "Désincarcération",
		service = "fire",
		severity = 3,
		requires = { rescue = 3, medical = 2, police = 1 },
		equipment = { "CISAILLE", "SAC_SECOURS" },
		qualifications = { "CHEF_AGRES", "SECOURISTE" },
		steps = {
			step("protection", "Protection et calage", { police = 1 }, 5),
			step("decoupe", "Découpe de la carrosserie", { rescue = 3 }, 16),
			step("soins", "Soins et extraction", { medical = 2 }, 10),
		},
		responseDeadline = 110,
		victims = 2,
		reward = 1500,
		penalty = 800,
		weight = 5,
		briefing = "Un véhicule est encastré contre un arbre. Le conducteur est "
			.. "conscient mais prisonnier de l'habitacle.",
	},
	{
		id = "EFFONDREMENT",
		name = "Effondrement de structure",
		service = "fire",
		severity = 3,
		requires = { fire = 2, rescue = 4, medical = 2, technical = 2 },
		equipment = { "CORDE", "LEVAGE" },
		qualifications = { "CHEF_AGRES", "TECHNICIEN" },
		steps = {
			step("securisation", "Sécurisation de la zone", { rescue = 2 }, 8),
			step("reconnaissance", "Reconnaissance des décombres", { technical = 2 }, 10),
			step("levage", "Levage et dégagement", { rescue = 4 }, 20),
			step("soins", "Prise en charge des victimes", { medical = 2 }, 10),
		},
		responseDeadline = 140,
		victims = 4,
		reward = 2800,
		penalty = 1500,
		weight = 3,
		briefing = "Un plancher s'est effondré dans un bâtiment en travaux. "
			.. "Des ouvriers sont bloqués sous les gravats.",
	},
	{
		id = "ACCIDENT_INDUSTRIEL",
		name = "Accident industriel",
		service = "technical",
		severity = 3,
		requires = { fire = 2, rescue = 2, medical = 2, technical = 2 },
		equipment = { "COMBINAISON" },
		qualifications = { "TECHNICIEN" },
		steps = {
			step("securisation", "Coupure des énergies", { technical = 2 }, 8),
			step("sauvetage", "Dégagement des victimes", { rescue = 2 }, 14),
			step("soins", "Soins sur place", { medical = 2 }, 10),
			step("controle", "Contrôle du risque", { fire = 2 }, 8),
		},
		responseDeadline = 140,
		victims = 3,
		reward = 2500,
		penalty = 1300,
		weight = 3,
		briefing = "Un ouvrier est coincé dans une machine. Le site signale une "
			.. "fuite de produit et demande une coupure des énergies.",
	},

	-- ═══════════════════ POLICE ═══════════════════
	{
		id = "SECURISATION",
		name = "Sécurisation de périmètre",
		service = "police",
		severity = 1,
		requires = { police = 1 },
		equipment = { "BALISE" },
		qualifications = { "POLICIER" },
		steps = {
			step("mise_en_place", "Mise en place du dispositif", { police = 1 }, 10),
			step("surveillance", "Surveillance", { police = 1 }, 15),
		},
		responseDeadline = 90,
		victims = 0,
		reward = 260,
		penalty = 140,
		weight = 9,
		briefing = "Un périmètre doit être tenu autour d'un bâtiment dangereux. "
			.. "Empêchez l'accès aux riverains.",
	},
	{
		id = "CIRCULATION",
		name = "Régulation de la circulation",
		service = "police",
		severity = 1,
		requires = { police = 1 },
		equipment = { "BALISE" },
		qualifications = { "POLICIER" },
		steps = {
			step("deviation", "Mise en place de la déviation", { police = 1 }, 8),
			step("regulation", "Régulation", { police = 1 }, 12),
		},
		responseDeadline = 85,
		victims = 0,
		reward = 220,
		penalty = 120,
		weight = 9,
		briefing = "Un carrefour est bloqué par un poids lourd en panne. "
			.. "La circulation doit être régulée avant la sortie des écoles.",
	},
	{
		id = "RECHERCHE_PERSONNE",
		name = "Recherche de personne",
		service = "police",
		severity = 2,
		requires = { police = 2 },
		equipment = { "RADIO" },
		qualifications = { "POLICIER" },
		steps = {
			step("ratissage", "Ratissage du quartier", { police = 2 }, 16),
			step("verification", "Vérification des signalements", { police = 1 }, 10),
		},
		responseDeadline = 120,
		victims = 0,
		reward = 600,
		penalty = 320,
		weight = 6,
		briefing = "Un adolescent n'est pas rentré du collège. La famille est "
			.. "inquiète et demande des recherches dans le quartier.",
	},
	{
		id = "PERIMETRE",
		name = "Dispositif de maintien de l'ordre",
		service = "police",
		severity = 2,
		requires = { police = 3 },
		equipment = { "BALISE", "RADIO" },
		qualifications = { "POLICIER" },
		steps = {
			step("deploiement", "Déploiement du dispositif", { police = 2 }, 12),
			step("maintien", "Maintien du dispositif", { police = 3 }, 18),
		},
		responseDeadline = 110,
		victims = 0,
		reward = 750,
		penalty = 400,
		weight = 4,
		briefing = "Un rassemblement dégénère devant la mairie. Un dispositif "
			.. "de sécurité doit être déployé pour protéger les bâtiments.",
	},

	-- ═══════════════════ RISQUES ET TECHNIQUE ═══════════════════
	{
		id = "POLLUTION",
		name = "Pollution de cours d'eau",
		service = "technical",
		severity = 2,
		requires = { technical = 2 },
		equipment = { "COMBINAISON" },
		qualifications = { "TECHNICIEN" },
		steps = {
			step("reconnaissance", "Reconnaissance de la pollution", { technical = 1 }, 8),
			step("confinement", "Confinement du produit", { technical = 2 }, 16),
			step("controle", "Prélèvements et contrôle", { technical = 1 }, 8),
		},
		responseDeadline = 120,
		victims = 0,
		reward = 800,
		penalty = 450,
		weight = 4,
		briefing = "Une irisation est signalée sur un ruisseau en aval d'une zone "
			.. "artisanale. Identifiez la source et confinez la pollution.",
	},
	{
		id = "RISQUE_CHIMIQUE",
		name = "Fuite de produit chimique",
		service = "technical",
		severity = 3,
		requires = { fire = 2, rescue = 2, medical = 1, technical = 2 },
		equipment = { "COMBINAISON" },
		qualifications = { "TECHNICIEN", "CHEF_AGRES" },
		steps = {
			step("securisation", "Périmètre et vent", { technical = 1 }, 8),
			step("reconnaissance", "Reconnaissance sous protection", { technical = 2 }, 10),
			step("colmatage", "Colmatage de la fuite", { technical = 2 }, 16),
			step("decontamination", "Décontamination", { fire = 2 }, 10),
		},
		responseDeadline = 140,
		victims = 2,
		reward = 2400,
		penalty = 1300,
		weight = 3,
		briefing = "Un fût percé libère un produit irritant dans un local technique. "
			.. "Deux employés se plaignent de difficultés respiratoires.",
	},
	{
		id = "INONDATION",
		name = "Inondation de sous-sol",
		service = "technical",
		severity = 2,
		requires = { technical = 3 },
		equipment = { "GROUPE_ELECTRO" },
		qualifications = { "TECHNICIEN" },
		steps = {
			step("coupure", "Coupure des réseaux", { technical = 2 }, 8),
			step("pompage", "Pompage", { technical = 3 }, 20),
			step("controle", "Contrôle des locaux", { technical = 1 }, 6),
		},
		responseDeadline = 130,
		victims = 0,
		reward = 900,
		penalty = 500,
		weight = 4,
		briefing = "Un parking souterrain est inondé après une rupture de canalisation. "
			.. "Plusieurs véhicules sont menacés.",
	},
	{
		id = "TEMPETE",
		name = "Dégâts de tempête",
		service = "technical",
		severity = 3,
		requires = { technical = 3, rescue = 2 },
		equipment = { "LEVAGE" },
		qualifications = { "TECHNICIEN" },
		steps = {
			step("securisation", "Sécurisation des accès", { technical = 2 }, 10),
			step("deblaiement", "Dégagement de la chaussée", { technical = 3 }, 18),
			step("verification", "Vérification des structures", { rescue = 1 }, 8),
		},
		responseDeadline = 140,
		victims = 1,
		reward = 1400,
		penalty = 750,
		weight = 4,
		briefing = "Un arbre est tombé sur la chaussée et endommage une toiture. "
			.. "La route est coupée, une habitation doit être mise en sécurité.",
	},

	-- ═══════════════════ RISQUES COLLECTIFS ═══════════════════
	{
		id = "FUITE_GAZ",
		name = "Fuite de gaz",
		service = "technical",
		severity = 3,
		requires = { fire = 2, technical = 2, police = 1 },
		equipment = { "COMBINAISON" },
		qualifications = { "TECHNICIEN", "SAPEUR" },
		steps = {
			step("perimetre", "Périmètre et coupure", { technical = 1 }, 8),
			step("reconnaissance", "Reconnaissance sous protection", { technical = 2 }, 10),
			step("colmatage", "Colmatage de la fuite", { technical = 2 }, 16),
			step("ventilation", "Ventilation des locaux", { fire = 2 }, 8),
		},
		responseDeadline = 130,
		victims = 0,
		reward = 1800,
		penalty = 950,
		weight = 5,
		briefing = "Une odeur de gaz est signalée dans une cave. Les habitants sont "
			.. "évacués et la rue doit être fermée le temps de la coupure.",
	},
	{
		id = "FEU_ELECTRIQUE",
		name = "Feu d'origine électrique",
		service = "fire",
		severity = 2,
		requires = { fire = 2, technical = 1 },
		equipment = { "EXTINCTEUR" },
		qualifications = { "SAPEUR", "TECHNICIEN" },
		steps = {
			step("coupure", "Coupure de l'alimentation", { technical = 1 }, 6),
			step("extinction", "Extinction du tableau", { fire = 2 }, 12),
			step("controle", "Contrôle des points chauds", { fire = 1 }, 6),
		},
		responseDeadline = 95,
		victims = 0,
		reward = 800,
		penalty = 420,
		weight = 8,
		briefing = "Un tableau électrique dégage une fumée âcre dans un local "
			.. "technique. L'alimentation doit être coupée avant toute attaque.",
	},
	{
		id = "PRISE_OTAGE",
		name = "Prise d'otage",
		service = "police",
		severity = 3,
		requires = { police = 4, command = 1 },
		equipment = { "RADIO", "GRENADE_FLASH" },
		qualifications = { "NEGOCIATEUR", "TIREUR_ELITE" },
		steps = {
			step("perimetre", "Périmètre et évacuation", { police = 3 }, 10),
			step("negociation", "Négociation", { police = 1, command = 1 }, 16),
			step("intervention", "Intervention", { police = 4 }, 12),
		},
		responseDeadline = 140,
		victims = 2,
		reward = 3000,
		penalty = 1800,
		weight = 2,
		briefing = "Un individu retranché retient deux personnes dans un commerce. "
			.. "Un négociateur et un tireur d'élite sont demandés sur place.",
	},
	{
		id = "EMEUTE",
		name = "Émeute urbaine",
		service = "police",
		severity = 3,
		requires = { police = 4 },
		equipment = { "BARRAGE", "GRENADE_FLASH" },
		qualifications = { "POLICIER" },
		steps = {
			step("deploiement", "Déploiement du dispositif", { police = 3 }, 10),
			step("maintien", "Maintien de la zone", { police = 4 }, 20),
			step("degagement", "Dégagement de la chaussée", { police = 3 }, 10),
		},
		responseDeadline = 130,
		victims = 1,
		reward = 2200,
		penalty = 1200,
		weight = 3,
		briefing = "Des groupes affrontent les forces de l'ordre devant un centre "
			.. "commercial. Des barrages et un dispositif mobile sont nécessaires.",
	},
	{
		id = "COLIS_SUSPECT",
		name = "Colis suspect",
		service = "police",
		severity = 3,
		requires = { police = 2, technical = 1 },
		equipment = { "BALISE", "RADIO" },
		qualifications = { "DEMINEUR", "POLICIER" },
		steps = {
			step("perimetre", "Périmètre de sécurité", { police = 2 }, 8),
			step("examen", "Examen de l'engin", { technical = 1 }, 12),
			step("neutralisation", "Neutralisation", { technical = 1 }, 10),
		},
		responseDeadline = 120,
		victims = 0,
		reward = 1600,
		penalty = 900,
		weight = 3,
		briefing = "Un bagage abandonné bloque l'accès à la gare. Le périmètre est "
			.. "tenu en attendant l'examen par un démineur.",
	},
	{
		id = "NOYADE",
		name = "Noyade",
		service = "medical",
		severity = 3,
		requires = { rescue = 2, medical = 2 },
		equipment = { "CORDE", "OXYGENE" },
		qualifications = { "PLONGEUR", "SECOURISTE" },
		steps = {
			step("sauvetage", "Sauvetage aquatique", { rescue = 2 }, 12),
			step("reanimation", "Réanimation", { medical = 2 }, 12),
			step("evacuation", "Évacuation médicalisée", { medical = 1 }, 8),
		},
		responseDeadline = 90,
		victims = 1,
		reward = 1500,
		penalty = 900,
		weight = 4,
		briefing = "Un baigneur a disparu sous la surface au bord du canal. "
			.. "Un plongeur et un moyen médicalisé sont engagés.",
	},
	{
		id = "ACCIDENT_PIETON",
		name = "Accident de piéton",
		service = "medical",
		severity = 2,
		requires = { rescue = 1, medical = 2, police = 1 },
		equipment = { "SAC_SECOURS", "BALISE" },
		qualifications = { "SECOURISTE", "POLICIER" },
		steps = {
			step("protection", "Protection du carrefour", { police = 1 }, 5),
			step("bilan", "Bilan et immobilisation", { medical = 2 }, 8),
			step("evacuation", "Évacuation", { medical = 2 }, 10),
		},
		responseDeadline = 90,
		victims = 1,
		reward = 700,
		penalty = 380,
		weight = 7,
		briefing = "Un piéton a été renversé sur un passage protégé. Il est "
			.. "conscient mais ne peut pas se relever.",
	},
	{
		id = "SEISME",
		name = "Séisme et effondrements",
		service = "fire",
		severity = 3,
		requires = { fire = 2, rescue = 4, medical = 3, police = 2, technical = 3 },
		equipment = { "LEVAGE", "CORDE" },
		qualifications = { "CHEF_AGRES", "TECHNICIEN", "SECOURISTE" },
		steps = {
			step("securisation", "Sécurisation des accès", { rescue = 2, police = 2 }, 8),
			step("triage", "Triage des victimes", { medical = 3 }, 10),
			step("deblaiement", "Déblaiement des décombres", { technical = 3 }, 20),
			step("sauvetage", "Extraction des victimes", { rescue = 4 }, 18),
			step("soins", "Prise en charge médicale", { medical = 2 }, 10),
		},
		responseDeadline = 160,
		victims = 8,
		reward = 5000,
		penalty = 3000,
		weight = 1,
		briefing = "Une secousse a fait s'effondrer deux immeubles du centre. "
			.. "Plusieurs victimes sont bloquées et les secours doivent se coordonner.",
	},
}

Incidents.map = {}
for _, incident in ipairs(Incidents.list) do
	Incidents.map[incident.id] = incident
end

function Incidents.get(id: string): any?
	return Incidents.map[id]
end

function Incidents.exists(id: string): boolean
	return Incidents.map[id] ~= nil
end

function Incidents.label(id: string): string
	local incident = Incidents.map[id]
	return incident and incident.name or id
end

-- Poids de tirage : les interventions graves restent plus rares.
function Incidents.weight(incident: any): number
	return incident.weight
end

return Incidents
