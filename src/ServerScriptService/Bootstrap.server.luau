--!strict
--[[
	Bootstrap serveur — point d'entrée unique.

	Il assemble le monde, tente de charger la sauvegarde, construit la scène,
	branche le réseau puis lance la boucle de simulation. Aucune logique métier
	ici : tout est délégué aux services.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local Operations = require(Shared:WaitForChild("Utilities"):WaitForChild("Operations"))
local Catalogs = Shared:WaitForChild("Catalogs")

local catalogs = {
	vehicles = require(Catalogs:WaitForChild("Vehicles")),
	qualifications = require(Catalogs:WaitForChild("Qualifications")),
	equipment = require(Catalogs:WaitForChild("Equipment")),
	incidents = require(Catalogs:WaitForChild("Incidents")),
	permissions = require(Catalogs:WaitForChild("Permissions")),
}

local ServerScript = game:GetService("ServerScriptService"):WaitForChild("ERS")
local Services = ServerScript:WaitForChild("Services")
local WorldService = require(Services:WaitForChild("WorldService"))
local SimulationService = require(Services:WaitForChild("SimulationService"))
local NetworkService = require(Services:WaitForChild("NetworkService"))
local SaveService = require(Services:WaitForChild("SaveService"))
local SceneService = require(Services:WaitForChild("SceneService"))
local LightingService = require(Services:WaitForChild("LightingService"))

local world = WorldService.create(Config, catalogs, { seed = os.time() })

local scene = SceneService.build(Config, workspace)
LightingService.apply(game:GetService("Lighting"), world, scene)

-- ─────────────────────────────────────────────────────────────
-- Sauvegarde (DataStore si disponible, mémoire sinon)
-- ─────────────────────────────────────────────────────────────
local store = SaveService.createMemoryStore()
local persistenceEnabled = false

local okStore, dataStore = pcall(function()
	return DataStoreService:GetDataStore(Config.SAVE_STORE)
end)

if okStore and dataStore then
	local persistentStore = SaveService.dataStoreAdapter(dataStore)
	local loaded = SaveService.load(world, persistentStore)
	if loaded.ok or (loaded.data and loaded.data.empty) then
		store = persistentStore
		persistenceEnabled = true
		local message = loaded.ok and "Progression restaurée depuis le DataStore." or "Début d’une nouvelle garde."
		Operations.log(world, Constants.LOG.SYSTEM, message)
	else
		Operations.log(world, Constants.LOG.FAILURE, loaded.message .. " Cette garde utilise la mémoire locale.")
	end
else
	Operations.log(world, Constants.LOG.FAILURE, "DataStore indisponible : partie non persistante.")
end

-- ─────────────────────────────────────────────────────────────
-- Réseau
-- ─────────────────────────────────────────────────────────────
local remotes = NetworkService.createRemotes(ReplicatedStorage)
local network = NetworkService.mount(world, remotes)
require(Services:WaitForChild("HudPreferenceService")).mount(remotes.folder)

-- Les joueurs déjà présents au moment du montage (Studio / hot reload).
for _, player in ipairs(Players:GetPlayers()) do
	local seeded = require(Services:WaitForChild("PermissionService")).seed(world, player.UserId, player.Name)
	world.players[player.UserId].connected = true
	network.sendSnapshot(player)
	if seeded.ok then
		remotes.feedback:FireClient(player, seeded)
	end
end

-- ─────────────────────────────────────────────────────────────
-- Boucles
-- ─────────────────────────────────────────────────────────────
task.spawn(function()
	local previous = os.clock()
	while true do
		task.wait(1 / Config.TICK_RATE)
		local now = os.clock()
		local dt = math.min(now - previous, 2)
		previous = now
		local ok, err = pcall(SimulationService.step, world, dt)
		if not ok then
			warn("[ERS] Simulation : " .. tostring(err))
			Operations.log(world, Constants.LOG.FAILURE, "Erreur de simulation : " .. tostring(err))
		end
		pcall(LightingService.step, world, nil, scene)
	end
end)

task.spawn(function()
	while true do
		task.wait(1 / Config.SNAPSHOT_RATE)
		local ok, err = pcall(network.broadcast)
		if not ok then
			warn("[ERS] Snapshot : " .. tostring(err))
		end
	end
end)

task.spawn(function()
	local elapsed = 0
	while true do
		task.wait(1)
		elapsed += 1
		if world.saveRequested or (persistenceEnabled and elapsed >= Config.SAVE_INTERVAL) then
			world.saveRequested = false
			elapsed = 0
			local saved = SaveService.save(world, store)
			if saved.ok then
				Operations.log(world, Constants.LOG.SYSTEM, "Sauvegarde effectuée.")
			else
				Operations.log(world, Constants.LOG.FAILURE, saved.message)
			end
		end
	end
end)

game:BindToClose(function()
	if persistenceEnabled then
		SaveService.save(world, store)
	end
end)
