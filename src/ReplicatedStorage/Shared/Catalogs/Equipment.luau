--!strict
--[[
	Equipment — catalogue du matériel embarqué.

	Chaque équipement appartient à une catégorie, est compatible avec certains
	services, pèse un certain poids et apporte un bonus de capacité. Les bonus
	servent réellement au calcul des moyens sur une intervention : ils ne sont
	pas décoratifs.
]]

local Equipment = {}

Equipment.list = {
	{
		id = "ARI",
		name = "Appareil respiratoire isolant",
		category = "protection",
		services = { "fire" },
		weight = 8,
		cost = 900,
		bonus = { fire = 1 },
		description = "Protection contre les fumées ; indispensable en milieu enfumé.",
	},
	{
		id = "EXTINCTEUR",
		name = "Extincteur portatif",
		category = "extinction",
		services = { "fire", "technical" },
		weight = 3,
		cost = 120,
		bonus = { fire = 1 },
		description = "Attaque rapide d'un départ de feu.",
	},
	{
		id = "TUYAU",
		name = "Tuyau et lance",
		category = "extinction",
		services = { "fire" },
		weight = 5,
		cost = 250,
		bonus = { fire = 1 },
		description = "Établissement d'une lance sur une borne incendie.",
	},
	{
		id = "CISAILLE",
		name = "Cisaille hydraulique",
		category = "extrication",
		services = { "fire" },
		weight = 7,
		cost = 1400,
		bonus = { rescue = 1 },
		description = "Découpe les tôles lors d'une désincarcération.",
	},
	{
		id = "ECARTEUR",
		name = "Écarteur hydraulique",
		category = "extrication",
		services = { "fire" },
		weight = 7,
		cost = 1500,
		bonus = { rescue = 1 },
		description = "Écarte les structures pour dégager une victime.",
	},
	{
		id = "CORDE",
		name = "Cordage et harnais",
		category = "rescue",
		services = { "fire", "medical", "technical" },
		weight = 4,
		cost = 350,
		bonus = { rescue = 1 },
		description = "Sauvetage en hauteur ou en excavation.",
	},
	{
		id = "MATELAS",
		name = "Matelas de sauvetage",
		category = "rescue",
		services = { "fire" },
		weight = 6,
		cost = 600,
		bonus = { rescue = 1 },
		description = "Réception d'une personne lors d'un saut contrôlé.",
	},
	{
		id = "DEFIB",
		name = "Défibrillateur",
		category = "medical",
		services = { "medical", "fire" },
		weight = 3,
		cost = 1100,
		bonus = { medical = 1 },
		description = "Réanimation d'un arrêt cardio-respiratoire.",
	},
	{
		id = "SAC_SECOURS",
		name = "Sac de secours",
		category = "medical",
		services = { "medical", "fire" },
		weight = 4,
		cost = 300,
		bonus = { medical = 1 },
		description = "Matériel de premiers secours et pansements.",
	},
	{
		id = "BRANCARD",
		name = "Brancard",
		category = "medical",
		services = { "medical" },
		weight = 9,
		cost = 450,
		bonus = { medical = 1 },
		description = "Conditionnement et évacuation d'une victime.",
	},
	{
		id = "OXYGENE",
		name = "Bouteille d'oxygène",
		category = "medical",
		services = { "medical", "fire" },
		weight = 5,
		cost = 500,
		bonus = { medical = 1 },
		description = "Oxygénothérapie sur les lieux.",
	},
	{
		id = "CAMERA_THERMIQUE",
		name = "Caméra thermique",
		category = "recon",
		services = { "fire" },
		weight = 2,
		cost = 800,
		bonus = { fire = 1 },
		description = "Détection des points chauds et des victimes.",
	},
	{
		id = "COMBINAISON",
		name = "Combinaison de protection chimique",
		category = "protection",
		services = { "fire", "technical" },
		weight = 6,
		cost = 1600,
		bonus = { rescue = 1 },
		description = "Intervention en ambiance contaminée.",
	},
	{
		id = "RADIO",
		name = "Poste radio",
		category = "radio",
		services = { "fire", "medical", "police", "technical", "command" },
		weight = 1,
		cost = 200,
		bonus = { command = 1 },
		description = "Transmission entre le PC et les engins.",
	},
	{
		id = "PC_MOBILE",
		name = "Poste de commandement mobile",
		category = "command",
		services = { "command" },
		weight = 10,
		cost = 2200,
		bonus = { command = 1 },
		description = "Coordination de plusieurs groupes sur un secteur.",
	},
	{
		id = "BALISE",
		name = "Balisage et cônes",
		category = "logistics",
		services = { "fire", "police", "technical" },
		weight = 3,
		cost = 150,
		bonus = { police = 1 },
		description = "Protection du périmètre et déviation de la circulation.",
	},
	{
		id = "GROUPE_ELECTRO",
		name = "Groupe électrogène",
		category = "logistics",
		services = { "technical" },
		weight = 8,
		cost = 1200,
		bonus = { technical = 1 },
		description = "Alimentation d'un chantier ou d'un PC de fortune.",
	},
	{
		id = "LEVAGE",
		name = "Matériel de levage",
		category = "logistics",
		services = { "technical", "fire" },
		weight = 9,
		cost = 1900,
		bonus = { rescue = 1 },
		description = "Soulèvement de charge ou dégagement d'une victime.",
	},
	{
		id = "TRONCONNEUSE",
		name = "Tronçonneuse",
		category = "extrication",
		services = { "fire" },
		weight = 6,
		cost = 900,
		bonus = { rescue = 1 },
		description = "Ouverture d'une toiture ou dégagement d'un obstacle.",
	},
	{
		id = "HACHE",
		name = "Hache d'effraction",
		category = "extrication",
		services = { "fire" },
		weight = 3,
		cost = 200,
		bonus = { rescue = 1 },
		description = "Effraction d'une porte et déblaiement léger.",
	},
	{
		id = "TAPIS_SAUT",
		name = "Tapis de saut",
		category = "rescue",
		services = { "fire" },
		weight = 8,
		cost = 1200,
		bonus = { rescue = 1 },
		description = "Réception d'une personne qui saute d'un étage.",
	},
	{
		id = "GRENADE_FLASH",
		name = "Grenade assourdissante",
		category = "intervention",
		services = { "police" },
		weight = 1,
		cost = 350,
		bonus = { police = 1 },
		description = "Neutralisation temporaire lors d'une interpellation à risque.",
	},
	{
		id = "BARRAGE",
		name = "Barrage routier",
		category = "intervention",
		services = { "police" },
		weight = 4,
		cost = 400,
		bonus = { police = 1 },
		description = "Fermeture d'un axe et protection d'un dispositif.",
	},
	{
		id = "POMPE",
		name = "Pompe d'épuisement",
		category = "logistics",
		services = { "technical", "fire" },
		weight = 8,
		cost = 1300,
		bonus = { technical = 1 },
		description = "Vidange d'un local inondé ou d'une fouille.",
	},
}

Equipment.map = {}
for _, equipment in ipairs(Equipment.list) do
	Equipment.map[equipment.id] = equipment
end

function Equipment.get(id: string): any?
	return Equipment.map[id]
end

function Equipment.exists(id: string): boolean
	return Equipment.map[id] ~= nil
end

function Equipment.label(id: string): string
	local equipment = Equipment.map[id]
	return equipment and equipment.name or id
end

return Equipment
