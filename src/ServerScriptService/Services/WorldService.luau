--!strict
--[[
	WorldService — construit l'état initial d'une partie.

	Un « monde » est la seule source de vérité d'un serveur : budget, flotte,
	personnels, stock, interventions, groupes, joueurs. Les services ne stockent
	rien en dehors de cette table, ce qui rend la sauvegarde et les tests
	simples et déterministes.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Utilities = Shared:WaitForChild("Utilities")
local City = require(Shared:WaitForChild("City"))
local Constants = require(Shared:WaitForChild("Constants"))
local Operations = require(Utilities:WaitForChild("Operations"))
local RoadNetwork = require(Utilities:WaitForChild("RoadNetwork"))
local Rng = require(Utilities:WaitForChild("Rng"))

local ServerScript = game:GetService("ServerScriptService"):WaitForChild("ERS")
local Services = ServerScript:WaitForChild("Services")
local PersonnelService = require(Services:WaitForChild("PersonnelService"))
local VehicleService = require(Services:WaitForChild("VehicleService"))

local WorldService = {}

-- Effectif du prototype : qualifications et grades variés pour couvrir
-- l'incendie, le secours à personne et le commandement.
WorldService.startingPersonnel = {
	{
		name = "Capitaine Marchand",
		grade = "Capitaine",
		service = "command",
		experience = 95,
		qualifications = { COS = true, CHEF_GROUPE = true, CONDUCTEUR = true, SAPEUR = true },
	},
	{
		name = "Lieutenant Perrin",
		grade = "Lieutenant",
		service = "fire",
		experience = 82,
		qualifications = { CHEF_AGRES = true, CHEF_GROUPE = true, CONDUCTEUR = true, SAPEUR = true },
	},
	{
		name = "Sergent-chef Aubry",
		grade = "Sergent-chef",
		service = "fire",
		experience = 70,
		qualifications = { CHEF_AGRES = true, CONDUCTEUR = true, SAPEUR = true },
	},
	{
		name = "Caporal-chef Vidal",
		grade = "Caporal-chef",
		service = "fire",
		experience = 55,
		qualifications = { SAPEUR = true, CONDUCTEUR = true, SECOURISTE = true },
	},
	{
		name = "Sapeur Morel",
		grade = "Sapeur",
		service = "fire",
		experience = 40,
		qualifications = { SAPEUR = true, SECOURISTE = true, CONDUCTEUR = true },
	},
	{
		name = "Sapeur Lambert",
		grade = "Sapeur",
		service = "fire",
		experience = 35,
		qualifications = { SAPEUR = true, SECOURISTE = true },
	},
	{
		name = "Sapeur Fontaine",
		grade = "Sapeur",
		service = "fire",
		experience = 30,
		qualifications = { SAPEUR = true, CONDUCTEUR = true },
	},
	{
		name = "Médecin-chef Lemoine",
		grade = "Médecin-chef",
		service = "medical",
		experience = 88,
		qualifications = { MEDECIN = true, SECOURISTE = true, CONDUCTEUR = true },
	},
	{
		name = "Infirmier Gauthier",
		grade = "Infirmier",
		service = "medical",
		experience = 60,
		qualifications = { INFIRMIER = true, SECOURISTE = true, CONDUCTEUR = true },
	},
	{
		name = "Major Blanchard",
		grade = "Major",
		service = "medical",
		experience = 68,
		qualifications = { SECOURISTE = true, CHEF_AGRES = true, CONDUCTEUR = true },
	},
	{
		name = "Gardien Renault",
		grade = "Gardien",
		service = "police",
		experience = 45,
		qualifications = { POLICIER = true, CONDUCTEUR = true },
	},
	{
		name = "Brigadier Faure",
		grade = "Brigadier",
		service = "police",
		experience = 52,
		qualifications = { POLICIER = true, GENDARME = true, CONDUCTEUR = true },
	},
	{
		name = "Technicien Delmas",
		grade = "Technicien",
		service = "technical",
		qualifications = { TECHNICIEN = true, CONDUCTEUR = true },
	},
}

-- Crée le parc, l'effectif et le stock de départ dans un monde déjà initialisé.
local function populate(world: any): ()
	for equipmentId, quantity in pairs(world.config.START_EQUIPMENT) do
		world.equipmentStock[equipmentId] = quantity
	end

	for _, typeId in ipairs(world.config.START_VEHICLES) do
		local created = VehicleService.create(world, typeId)
		if not created.ok then
			Operations.log(world, Constants.LOG.FAILURE, "Véhicule de départ impossible : " .. created.message)
		end
	end

	for _, data in ipairs(WorldService.startingPersonnel) do
		local created = PersonnelService.create(world, data)
		if not created.ok then
			Operations.log(world, Constants.LOG.FAILURE, "Recrutement impossible : " .. created.message)
		end
	end
end

-- Crée un monde complet. `options.seed` rend la partie reproductible (tests).
function WorldService.create(config: any, catalogs: any, options: any?): any
	options = options or {}
	local world = {
		version = config.VERSION,
		config = config,
		catalogs = catalogs,

		budget = config.START_BUDGET,
		transactions = {},

		vehicles = {},
		personnel = {},
		equipmentStock = {},
		incidents = {},
		groups = {},
		sectors = {},
		players = {},
		log = {},

		time = 0,
		timeScale = 1,
		alarmCountdown = config.FIRST_ALERT_DELAY,
		spawnedIncidents = 0,
		finished = false,
		saveRequested = false,

		nextVehicleId = 1,
		nextPersonnelId = 1,
		nextIncidentId = 1,
		nextGroupId = 1,
		nextSectorId = 1,
		nextLogId = 1,

		rng = Rng.new(options.seed or os.time()),

		-- Plan de ville et graphe routier : mêmes données pures que côté client,
		-- jamais sérialisées dans la sauvegarde ni dans le snapshot.
		cityPlan = City.build(config.CITY_SEED),
		roadNetwork = nil,

		stats = {
			dispatched = 0,
			resolved = 0,
			degraded = 0,
			failed = 0,
			savedVictims = 0,
			spent = 0,
			earned = 0,
		},
	}

	world.roadNetwork = RoadNetwork.build(world.cityPlan)
	populate(world)

	Operations.log(world, Constants.LOG.SYSTEM, string.format(
		"Service ouvert à %s — budget initial %d €.",
		string.format("%02d:00", config.SHIFT_START_HOUR),
		config.START_BUDGET
	))

	return world
end

--[[
	Remet le monde dans son état de départ, sans changer de serveur.

	Les joueurs connectés et leurs postes sont conservés : une nouvelle partie
	ne doit pas éjecter l'équipe. Tout le reste (budget, parc, effectif, stock,
	interventions, groupes, secteurs, statistiques, horloge) repart de zéro.
	La prochaine sauvegarde écrasera l'ancienne progression.
]]
function WorldService.reset(world: any, options: any?): any
	options = options or {}

	world.budget = world.config.START_BUDGET
	world.purchaseTurn = nil
	table.clear(world.transactions)
	table.clear(world.vehicles)
	table.clear(world.personnel)
	table.clear(world.equipmentStock)
	table.clear(world.incidents)
	table.clear(world.groups)
	table.clear(world.sectors)
	table.clear(world.log)

	world.time = 0
	world.timeScale = 1
	world.alarmCountdown = world.config.FIRST_ALERT_DELAY
	world.spawnedIncidents = 0
	world.finished = false
	world.saveRequested = true
	world.lightingHour = nil
	world.mission = nil

	world.nextVehicleId = 1
	world.nextPersonnelId = 1
	world.nextIncidentId = 1
	world.nextGroupId = 1
	world.nextSectorId = 1
	world.nextLogId = 1

	world.rng = Rng.new(options.seed or os.time())
	world.roadNetwork = RoadNetwork.build(world.cityPlan)

	for key in pairs(world.stats) do
		world.stats[key] = 0
	end

	populate(world)
	Operations.log(world, Constants.LOG.SYSTEM, string.format(
		"Nouvelle partie : service ouvert à %s — budget initial %d €.",
		string.format("%02d:00", world.config.SHIFT_START_HOUR),
		world.config.START_BUDGET
	))

	return world
end

-- Nombre de membres par service (diagnostic et interface).
function WorldService.countPersonnel(world: any): { [string]: number }
	local counts = {}
	for _, person in pairs(world.personnel) do
		counts[person.service] = (counts[person.service] or 0) + 1
	end
	return counts
end

return WorldService
