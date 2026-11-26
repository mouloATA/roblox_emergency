--!strict
--[[
	SaveService — persistance des données permanentes (spec §14).

	Ce qui est sauvegardé : budget, statistiques, flotte possédée, effectifs,
	qualifications, stock, groupes et secteurs.
	Ce qui ne l'est pas : interventions en cours, trajets, positions, joueurs
	connectés — ce sont des données de session.

	Le stockage est injectable (`store.get` / `store.set`) pour être testé sans
	DataStore. Aucune erreur de stockage ne doit faire planter la partie.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Utilities = Shared:WaitForChild("Utilities")
local Constants = require(Shared:WaitForChild("Constants"))
local Result = require(Utilities:WaitForChild("Result"))
local Crew = require(Utilities:WaitForChild("Crew"))
local Operations = require(Utilities:WaitForChild("Operations"))

local ServerScript = game:GetService("ServerScriptService"):WaitForChild("ERS")
local Services = ServerScript:WaitForChild("Services")
local VehicleService = require(Services:WaitForChild("VehicleService"))

local SaveService = {}

function SaveService.count(map: any): number
	local total = 0
	for _ in pairs(map) do
		total += 1
	end
	return total
end

local function copyMap(source: any): any
	local copy = {}
	for key, value in pairs(source) do
		copy[key] = value
	end
	return copy
end

local function sortedPairs(map: any): { any }
	local ids = {}
	for id in pairs(map) do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return ids
end

-- Produit une table JSON-compatible (aucune Instance, aucune fonction).
function SaveService.serialize(world: any): any
	local vehicles = {}
	for _, vehicleId in ipairs(sortedPairs(world.vehicles)) do
		local vehicle = world.vehicles[vehicleId]
		local crew = {}
		for _, personId in ipairs(vehicle.crew) do
			table.insert(crew, personId)
		end
		table.insert(vehicles, {
			id = vehicle.id,
			typeId = vehicle.typeId,
			callsign = vehicle.callsign,
			condition = vehicle.condition,
			equipment = copyMap(vehicle.equipment),
			crew = crew,
		})
	end

	local personnel = {}
	for _, personId in ipairs(sortedPairs(world.personnel)) do
		local person = world.personnel[personId]
		local qualifications = {}
		for qualificationId, owned in pairs(person.qualifications) do
			if owned then
				table.insert(qualifications, qualificationId)
			end
		end
		table.sort(qualifications)
		table.insert(personnel, {
			id = person.id,
			name = person.name,
			grade = person.grade,
			service = person.service,
			qualifications = qualifications,
			experience = person.experience,
			level = person.level or 0,
			hireCost = person.hireCost or 1200,
			fatigue = person.fatigue,
			health = person.health,
		})
	end

	local groups = {}
	for _, groupId in ipairs(sortedPairs(world.groups)) do
		local group = world.groups[groupId]
		table.insert(groups, {
			id = group.id,
			name = group.name,
			service = group.service,
			vehicles = table.clone(group.vehicles),
			sectorId = group.sectorId,
		})
	end

	local sectors = {}
	for _, sectorId in ipairs(sortedPairs(world.sectors)) do
		local sector = world.sectors[sectorId]
		table.insert(sectors, {
			id = sector.id,
			name = sector.name,
			x = sector.x,
			z = sector.z,
			radius = sector.radius,
			groupId = sector.groupId,
		})
	end

	return {
		version = world.version,
		savedAt = os.time(),
		budget = world.budget,
		stats = copyMap(world.stats),
		equipmentStock = copyMap(world.equipmentStock),
		fieldInventoryVersion = 1,
		vehicles = vehicles,
		personnel = personnel,
		groups = groups,
		sectors = sectors,
	}
end

local function validNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Reconstruit l'état permanent à partir d'une sauvegarde.
-- Les données inconnues (type supprimé, qualification retirée) sont ignorées
-- et signalées, jamais injectées telles quelles.
function SaveService.deserialize(world: any, data: any): any
	if type(data) ~= "table" then
		return Result.err("Sauvegarde illisible.")
	end
	local previousFormat = world.version == "0.4.0" and data.version == "0.3.0"
	if data.version ~= world.version and not previousFormat then
		return Result.err(string.format("Version de sauvegarde incompatible (%s).", tostring(data.version)))
	end

	local ignored = 0

	-- Personnel
	local personnelMap = {}
	local personnelList = {}
	for _, entry in ipairs(data.personnel or {}) do
		if type(entry) == "table" and validNumber(entry.id) and type(entry.name) == "string" then
			local qualifications = {}
			for _, qualificationId in ipairs(entry.qualifications or {}) do
				if world.catalogs.qualifications.exists(qualificationId) then
					qualifications[qualificationId] = true
				else
					ignored += 1
				end
			end
			if next(qualifications) ~= nil then
				personnelMap[entry.id] = {
					id = entry.id,
					name = entry.name,
					grade = entry.grade or "Sapeur",
					service = entry.service or "fire",
					qualifications = qualifications,
					level = validNumber(entry.level) and math.clamp(math.floor(entry.level), 0, 3) or 0,
					hireCost = validNumber(entry.hireCost) and math.max(0, math.floor(entry.hireCost)) or 1200,
					experience = validNumber(entry.experience) and entry.experience or 0,
					fatigue = validNumber(entry.fatigue) and math.clamp(entry.fatigue, 0, world.config.MAX_FATIGUE) or 0,
					health = validNumber(entry.health) and math.clamp(entry.health, 0, 100) or 100,
					status = Constants.VEHICLE_STATUS.AVAILABLE,
					vehicleId = nil,
				}
				table.insert(personnelList, entry)
			else
				ignored += 1
			end
		else
			ignored += 1
		end
	end

	-- Véhicules
	local vehicleMap = {}
	for _, entry in ipairs(data.vehicles or {}) do
		local typeDef = type(entry) == "table" and world.catalogs.vehicles.get(tostring(entry.typeId)) or nil
		if typeDef and validNumber(entry.id) and type(entry.callsign) == "string" then
			local equipment = {}
			for equipmentId, quantity in pairs(entry.equipment or {}) do
				if world.catalogs.equipment.exists(equipmentId) and validNumber(quantity) and quantity > 0 then
					equipment[equipmentId] = math.floor(quantity)
				else
					ignored += 1
				end
			end
			local home = VehicleService.homePosition({ vehicles = vehicleMap, config = world.config })
			vehicleMap[entry.id] = {
				id = entry.id,
				typeId = typeDef.id,
				callsign = entry.callsign,
				status = Constants.VEHICLE_STATUS.AVAILABLE,
				condition = validNumber(entry.condition) and math.clamp(entry.condition, 1, 100) or 100,
				position = { x = home.x, z = home.z },
				home = home,
				crew = {},
				equipment = equipment,
				incidentId = nil,
				route = nil,
				repairRemaining = 0,
			}
		else
			ignored += 1
		end
	end

	-- Équipages (deuxième passe : les deux maps existent)
	for _, entry in ipairs(data.vehicles or {}) do
		local vehicle = type(entry) == "table" and vehicleMap[entry.id] or nil
		if vehicle then
			for _, personId in ipairs(entry.crew or {}) do
				local person = personnelMap[personId]
				if person then
					local allowed = Crew.canAssign(world, person, vehicle)
					if allowed.ok then
						Crew.assign(world, person, vehicle)
					else
						ignored += 1
					end
				end
			end
		end
	end

	-- Groupes et secteurs
	local groupMap = {}
	for _, entry in ipairs(data.groups or {}) do
		if type(entry) == "table" and validNumber(entry.id) and type(entry.name) == "string" then
			local members = {}
			for _, vehicleId in ipairs(entry.vehicles or {}) do
				if vehicleMap[vehicleId] then
					table.insert(members, vehicleId)
				else
					ignored += 1
				end
			end
			groupMap[entry.id] = {
				id = entry.id,
				name = entry.name,
				service = entry.service,
				vehicles = members,
				sectorId = nil,
				createdBy = 0,
			}
		else
			ignored += 1
		end
	end

	local sectorMap = {}
	for _, entry in ipairs(data.sectors or {}) do
		if
			type(entry) == "table"
			and validNumber(entry.id)
			and type(entry.name) == "string"
			and validNumber(entry.x)
			and validNumber(entry.z)
			and validNumber(entry.radius)
		then
			sectorMap[entry.id] = {
				id = entry.id,
				name = entry.name,
				x = entry.x,
				z = entry.z,
				radius = entry.radius,
				groupId = nil,
				createdBy = 0,
			}
		else
			ignored += 1
		end
	end

	-- Liens secteur ↔ groupe, uniquement si les deux existent encore.
	for _, entry in ipairs(data.groups or {}) do
		local group = type(entry) == "table" and groupMap[entry.id] or nil
		if group then
			local sector = validNumber(entry.sectorId) and sectorMap[entry.sectorId] or nil
			if sector and sector.groupId == nil then
				group.sectorId = sector.id
				sector.groupId = group.id
			end
		end
	end

	-- Application atomique (après validation complète)
	world.personnel = personnelMap
	world.vehicles = vehicleMap
	world.groups = groupMap
	world.sectors = sectorMap
	world.incidents = {}
	world.mission = nil
	world.transactions = {}
	world.purchaseTurn = nil
	world.equipmentStock = {}

	for equipmentId, quantity in pairs(data.equipmentStock or {}) do
		if world.catalogs.equipment.exists(equipmentId) and validNumber(quantity) and quantity > 0 then
			world.equipmentStock[equipmentId] = math.floor(quantity)
		end
	end

	-- Les anciennes parties ne disposaient d'aucun outil de découpe dans leur stock initial.
	if data.fieldInventoryVersion == nil then
		for _, id in ipairs({ "CISAILLE", "ECARTEUR" }) do
			local owned = world.equipmentStock[id] or 0
			for _, vehicle in pairs(vehicleMap) do owned += vehicle.equipment[id] or 0 end
			if owned == 0 then world.equipmentStock[id] = world.config.START_EQUIPMENT[id] end
		end
	end

	world.budget = validNumber(data.budget) and math.floor(data.budget) or 0
	for key in pairs(world.stats) do
		world.stats[key] = 0
	end
	for key, value in pairs(data.stats or {}) do
		if validNumber(value) then
			world.stats[key] = value
		end
	end

	world.nextPersonnelId = 1
	for personId in pairs(world.personnel) do
		world.nextPersonnelId = math.max(world.nextPersonnelId, personId + 1)
	end
	world.nextVehicleId = 1
	for vehicleId in pairs(world.vehicles) do
		world.nextVehicleId = math.max(world.nextVehicleId, vehicleId + 1)
	end
	world.nextGroupId = 1
	for groupId in pairs(world.groups) do
		world.nextGroupId = math.max(world.nextGroupId, groupId + 1)
	end
	world.nextSectorId = 1
	for sectorId in pairs(world.sectors) do
		world.nextSectorId = math.max(world.nextSectorId, sectorId + 1)
	end
	world.nextIncidentId = 1
	world.spawnedIncidents = 0
	world.alarmCountdown = world.config.FIRST_ALERT_DELAY

	Operations.log(world, Constants.LOG.SYSTEM, string.format(
		"Sauvegarde chargée : %d véhicule(s), %d membre(s)%s.",
		SaveService.count(world.vehicles),
		SaveService.count(world.personnel),
		ignored > 0 and string.format(", %d entrée(s) ignorée(s)", ignored) or ""
	))

	return Result.ok("Sauvegarde chargée.", { ignored = ignored })
end

function SaveService.save(world: any, store: any): any
	if not store or type(store.set) ~= "function" then
		return Result.err("Aucun stockage disponible.")
	end
	local payload = SaveService.serialize(world)
	local lastError = "erreur inconnue"
	for _ = 1, world.config.SAVE_RETRIES do
		local ok, written, detail = pcall(store.set, world.config.SAVE_KEY, payload)
		if ok and written ~= false then
			return Result.ok("Sauvegarde effectuée.")
		end
		lastError = tostring(if ok then detail else written)
	end
	return Result.err("Sauvegarde impossible : " .. lastError)
end

function SaveService.load(world: any, store: any): any
	if not store or type(store.get) ~= "function" then
		return Result.err("Aucun stockage disponible.")
	end
	local ok, data = pcall(store.get, world.config.SAVE_KEY)
	if not ok then
		return Result.err("Lecture impossible : " .. tostring(data))
	end
	if data == nil then
		return Result.err("Aucune sauvegarde existante.", { empty = true })
	end
	return SaveService.deserialize(world, data)
end

-- Stockage mémoire : tests, et repli quand DataStore est indisponible.
function SaveService.createMemoryStore(): any
	local data = {}
	return {
		get = function(key: string): any
			return data[key]
		end,
		set = function(key: string, value: any): boolean
			data[key] = value
			return true
		end,
		clear = function(): ()
			table.clear(data)
		end,
	}
end

-- Adapte un DataStore Roblox à l'interface get/set, sans propager d'erreur.
function SaveService.dataStoreAdapter(dataStore: any): any
	return {
		get = function(key: string): any
			return dataStore:GetAsync(key)
		end,
		set = function(key: string, value: any): (boolean, string?)
			local ok, err = pcall(dataStore.SetAsync, dataStore, key, value)
			if ok then
				return true
			end
			return false, tostring(err)
		end,
	}
end

return SaveService
