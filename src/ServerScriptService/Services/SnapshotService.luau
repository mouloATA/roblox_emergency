--!strict
--[[
	SnapshotService — état sérialisable envoyé aux clients.

	Un snapshot ne contient que des tables simples (nombres, chaînes, booléens,
	tableaux, dictionnaires) : ni fonction, ni Instance, ni métatable. C'est ce
	qui garantit qu'il traverse RemoteEvent sans erreur et que les tests peuvent
	le vérifier hors Studio.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Utilities = Shared:WaitForChild("Utilities")
local Constants = require(Shared:WaitForChild("Constants"))
local TimeUtil = require(Utilities:WaitForChild("TimeUtil"))
local Permissions = require(Shared:WaitForChild("Catalogs"):WaitForChild("Permissions"))

local SnapshotService = {}

-- Vérifie récursivement qu'une valeur est sérialisable par Roblox.
function SnapshotService.isSerializable(value: any, seen: any?, depth: number?): boolean
	local level = depth or 0
	if level > 12 then
		return false
	end

	local valueType = type(value)
	if valueType == "nil" or valueType == "boolean" or valueType == "string" then
		return true
	end
	if valueType == "number" then
		return value == value and value ~= math.huge and value ~= -math.huge
	end
	if valueType ~= "table" then
		return false
	end
	if getmetatable(value) ~= nil then
		return false
	end

	local visited = seen or {}
	if visited[value] then
		return false
	end
	visited[value] = true

	for key, child in pairs(value) do
		local keyType = type(key)
		if keyType ~= "string" and keyType ~= "number" then
			visited[value] = nil
			return false
		end
		if not SnapshotService.isSerializable(child, visited, level + 1) then
			visited[value] = nil
			return false
		end
	end

	visited[value] = nil
	return true
end

local function copyTable(source: any): any
	local copy = {}
	for key, value in pairs(source) do
		copy[key] = value
	end
	return copy
end

local function qualificationLabels(world: any, person: any): { string }
	local labels = {}
	for qualificationId in pairs(person.qualifications) do
		table.insert(labels, world.catalogs.qualifications.label(qualificationId))
	end
	table.sort(labels)
	return labels
end

local function crewNames(world: any, vehicle: any): { string }
	local names = {}
	for _, personId in ipairs(vehicle.crew) do
		local person = world.personnel[personId]
		if person then
			table.insert(names, person.name)
		end
	end
	return names
end

local function equipmentList(world: any, vehicle: any): { any }
	local list = {}
	for equipmentId, quantity in pairs(vehicle.equipment) do
		if quantity > 0 then
			table.insert(list, {
				id = equipmentId,
				name = world.catalogs.equipment.label(equipmentId),
				quantity = quantity,
			})
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

local function stockList(world: any): { any }
	local list = {}
	for equipmentId, quantity in pairs(world.equipmentStock) do
		if quantity > 0 then
			table.insert(list, {
				id = equipmentId,
				name = world.catalogs.equipment.label(equipmentId),
				quantity = quantity,
			})
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

local function sortedIds(map: any): { any }
	local ids = {}
	for id in pairs(map) do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return ids
end

function SnapshotService.build(world: any): any
	local vehicles = {}
	for _, vehicleId in ipairs(sortedIds(world.vehicles)) do
		local vehicle = world.vehicles[vehicleId]
		local typeDef = world.catalogs.vehicles.get(vehicle.typeId)
		table.insert(vehicles, {
			id = vehicle.id,
			typeId = vehicle.typeId,
			name = typeDef and typeDef.name or vehicle.typeId,
			callsign = vehicle.callsign,
			service = typeDef and typeDef.service or "unknown",
			status = vehicle.status,
			condition = vehicle.condition,
			x = vehicle.position.x,
			z = vehicle.position.z,
			crew = crewNames(world, vehicle),
			crewCount = #vehicle.crew,
			crewRequired = typeDef and typeDef.crewRequired or 0,
			equipment = equipmentList(world, vehicle),
			incidentId = vehicle.incidentId,
			route = vehicle.route and copyTable(vehicle.route) or nil,
			repairRemaining = vehicle.repairRemaining,
		})
	end

	local personnel = {}
	for _, personId in ipairs(sortedIds(world.personnel)) do
		local person = world.personnel[personId]
		table.insert(personnel, {
			id = person.id,
			name = person.name,
			grade = person.grade,
			service = person.service,
			status = person.status,
			vehicleId = person.vehicleId,
			fatigue = person.fatigue,
			health = person.health,
			experience = person.experience,
			qualifications = qualificationLabels(world, person),
		})
	end

	local incidents = {}
	for _, incidentId in ipairs(sortedIds(world.incidents)) do
		local incident = world.incidents[incidentId]
		local typeDef = world.catalogs.incidents.get(incident.typeId)
		local step = typeDef and typeDef.steps[incident.stepIndex] or nil
		local assigned = {}
		for vehicleId in pairs(incident.assigned) do
			table.insert(assigned, vehicleId)
		end
		table.sort(assigned)
		local onScene = {}
		for vehicleId in pairs(incident.onScene) do
			table.insert(onScene, vehicleId)
		end
		table.sort(onScene)

		table.insert(incidents, {
			id = incident.id,
			typeId = incident.typeId,
			name = typeDef and typeDef.name or incident.typeId,
			briefing = typeDef and typeDef.briefing or "",
			service = typeDef and typeDef.service or "unknown",
			severity = incident.severity,
			status = incident.status,
			x = incident.position.x,
			z = incident.position.z,
			victims = incident.victims,
			savedVictims = incident.savedVictims,
			stepIndex = incident.stepIndex,
			stepCount = typeDef and #typeDef.steps or 0,
			stepLabel = step and step.label or "Clôture",
			stepProgress = incident.stepProgress,
			stepSeconds = step and step.seconds or 0,
			deadlineIn = math.max(0, incident.deadline - world.time),
			assigned = assigned,
			onScene = onScene,
			requires = typeDef and copyTable(typeDef.requires) or {},
			equipment = typeDef and table.clone(typeDef.equipment) or {},
			qualifications = typeDef and table.clone(typeDef.qualifications) or {},
			outcome = incident.outcome,
		})
	end

	local groups = {}
	for _, groupId in ipairs(sortedIds(world.groups)) do
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
	for _, sectorId in ipairs(sortedIds(world.sectors)) do
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

	local roleLabels = {}
	for roleId, role in pairs(Permissions.roles) do
		roleLabels[roleId] = role.label
	end

	local players = {}
	for _, player in pairs(world.players) do
		table.insert(players, {
			userId = player.userId,
			name = player.name,
			role = player.role,
			roleLabel = roleLabels[player.role] or player.role,
			connected = player.connected ~= false,
		})
	end
	table.sort(players, function(a, b)
		return a.userId < b.userId
	end)

	local log = {}
	for index = 1, math.min(#world.log, world.config.SNAPSHOT_LOG_LIMIT) do
		table.insert(log, copyTable(world.log[index]))
	end

	local alerts = 0
	for _, incident in pairs(world.incidents) do
		if incident.status == Constants.INCIDENT_STATUS.PENDING or incident.status == Constants.INCIDENT_STATUS.ACTIVE then
			alerts += 1
		end
	end

	return {
		version = world.version,
		time = world.time,
		timeScale = world.timeScale or 1,
		paused = (world.timeScale or 1) == 0,
		clock = TimeUtil.clock(world),
		budget = world.budget,
		spent = world.stats.spent,
		earned = world.stats.earned,
		finished = world.finished,
		players = players,
		vehicles = vehicles,
		personnel = personnel,
		incidents = incidents,
		groups = groups,
		sectors = sectors,
		stock = stockList(world),
		log = log,
		stats = copyTable(world.stats),
		alerts = alerts,
	}
end

return SnapshotService
