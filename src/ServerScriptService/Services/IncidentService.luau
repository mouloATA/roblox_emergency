--!strict
--[[
	IncidentService — cycle de vie des interventions (spec §10).

	Une alerte est d'abord `pending` : elle a une date limite de prise en
	charge. Le premier engagement la passe en `active`. Ensuite, chaque étape du
	catalogue ne progresse que si les moyens présents couvrent son besoin.
	À la fin, le résultat dépend des moyens globaux, du matériel et des
	qualifications réellement présents.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Utilities = Shared:WaitForChild("Utilities")
local Constants = require(Shared:WaitForChild("Constants"))
local Result = require(Utilities:WaitForChild("Result"))
local Crew = require(Utilities:WaitForChild("Crew"))
local MathX = require(Utilities:WaitForChild("MathX"))
local Operations = require(Utilities:WaitForChild("Operations"))

local ServerScript = game:GetService("ServerScriptService"):WaitForChild("ERS")
local Services = ServerScript:WaitForChild("Services")
local BudgetService = require(Services:WaitForChild("BudgetService"))
local CommandService = require(Services:WaitForChild("CommandService"))

local FieldService = require(Services:WaitForChild("FieldService"))
local FireService = require(Services:WaitForChild("FireService"))
local HospitalService = require(Services:WaitForChild("HospitalService"))
local ProgressionService = require(Services:WaitForChild("ProgressionService"))

local IncidentService = {}

function IncidentService.zoneLabel(x: number, z: number): string
	local northSouth = if z < 50 then "Nord" else "Sud"
	local eastWest = if x < 50 then "Ouest" else "Est"
	return northSouth .. "-" .. eastWest
end

-- Crée une alerte. `position` est optionnelle (scénario prédéfini).
function IncidentService.spawn(world: any, typeId: string, position: any?): any
	local typeDef = world.catalogs.incidents.get(typeId)
	if not typeDef then
		return Result.err("Type d'intervention inconnu.")
	end
	if IncidentService.activeCount(world) >= world.config.MAX_ACTIVE_INCIDENTS then
		return Result.err("Trop d'interventions en cours.")
	end

	local point = position
	if not point then
		local size = world.config.MAP_SIZE
		for _ = 1, 20 do
			local x = world.rng:integer(8, size - 8)
			local z = world.rng:integer(8, size - 8)
			local distanceHQ = MathX.distance(x, z, world.config.HQ_X, world.config.HQ_Z)
			local clear = distanceHQ > 12
			if clear then
				for _, other in pairs(world.incidents) do
					if other.status ~= Constants.INCIDENT_STATUS.RESOLVED and other.status ~= Constants.INCIDENT_STATUS.FAILED then
						if MathX.distance(x, z, other.position.x, other.position.z) < 8 then
							clear = false
							break
						end
					end
				end
			end
			if clear then
				point = { x = x, z = z }
				break
			end
		end
		if not point then
			point = { x = world.rng:integer(8, size - 8), z = world.rng:integer(8, size - 8) }
		end
	end

	local incident = {
		id = "INC-" .. string.format("%03d", world.nextIncidentId),
		typeId = typeId,
		status = Constants.INCIDENT_STATUS.PENDING,
		severity = typeDef.severity,
		position = { x = point.x, z = point.z },
		createdAt = world.time,
		deadline = world.time + typeDef.responseDeadline,
		assigned = {},
		onScene = {},
		stepIndex = 1,
		stepProgress = 0,
		underpoweredFor = 0,
		emptyFor = 0,
		victims = typeDef.victims,
		savedVictims = 0,
		closedAt = nil,
		outcome = nil,
	}
	incident.inTransit = 0
	FieldService.prepare(incident, typeDef)
	world.nextIncidentId += 1
	world.incidents[incident.id] = incident
	world.spawnedIncidents += 1

	Operations.log(world, Constants.LOG.INCIDENT, string.format(
		"Alerte %s : %s (%s).",
		incident.id,
		typeDef.name,
		IncidentService.zoneLabel(point.x, point.z)
	))

	return Result.ok(typeDef.name, incident)
end

-- Tire une alerte dans les scénarios de la Phase 0 (prototype).
function IncidentService.spawnRandom(world: any): any
	local candidates = {}
	for _, typeId in ipairs(world.config.PROTOTYPE_SCENARIOS) do
		local typeDef = world.catalogs.incidents.get(typeId)
		if typeDef then
			table.insert(candidates, typeDef)
		end
	end
	if #candidates == 0 then
		return Result.err("Aucun scénario configuré.")
	end

	local picked = world.rng:weighted(candidates, function(typeDef)
		return typeDef.weight
	end)
	if not picked then
		return Result.err("Tirage impossible.")
	end
	return IncidentService.spawn(world, picked.id)
end

function IncidentService.activeCount(world: any): number
	local count = 0
	for _, incident in pairs(world.incidents) do
		if incident.status == Constants.INCIDENT_STATUS.PENDING or incident.status == Constants.INCIDENT_STATUS.ACTIVE then
			count += 1
		end
	end
	return count
end

-- Libère tous les véhicules engagés sur l'intervention.
function IncidentService.releaseVehicles(world: any, incident: any): ()
	for vehicleId in pairs(incident.assigned) do
		local vehicle = world.vehicles[vehicleId]
		if vehicle and vehicle.incidentId == incident.id then
			vehicle.patients, vehicle.handoverAt = 0, nil
			vehicle.incidentId = nil
			Operations.release(world, vehicle)
		end
	end
	table.clear(incident.assigned)
	table.clear(incident.onScene)
end

-- Échec : pénalité budgétaire et libération des moyens.
function IncidentService.fail(world: any, incident: any, reason: string): ()
	if incident.closedAt ~= nil then return end
	local typeDef = world.catalogs.incidents.get(incident.typeId)
	if not typeDef then
		return
	end
	BudgetService.penalty(world, typeDef.penalty, "Intervention échouée : " .. typeDef.name)
	world.stats.failed += 1
	incident.status = Constants.INCIDENT_STATUS.FAILED
	incident.outcome = reason
	incident.closedAt = world.time
	ProgressionService.record(world, incident)
	IncidentService.releaseVehicles(world, incident)
	Operations.log(world, Constants.LOG.FAILURE, string.format(
		"%s échouée : %s (−%d €).",
		incident.id,
		reason,
		typeDef.penalty
	))
end

-- Réussite (pleine ou dégradée).
function IncidentService.resolve(world: any, incident: any, degraded: boolean, reason: string): ()
	if incident.closedAt ~= nil then return end
	local typeDef = world.catalogs.incidents.get(incident.typeId)
	if not typeDef then
		return
	end
	local factor = degraded and 0.5 or 1
	local amount = math.floor(typeDef.reward * factor)
	local saved = incident.savedVictims

	BudgetService.earn(world, amount, "Intervention réussie : " .. typeDef.name)
	if degraded then
		world.stats.degraded += 1
	else
		world.stats.resolved += 1
	end

	incident.status = Constants.INCIDENT_STATUS.RESOLVED
	incident.outcome = degraded and "degraded" or "success"
	incident.closedAt = world.time
	ProgressionService.record(world, incident)
	IncidentService.releaseVehicles(world, incident)
	Operations.log(world, Constants.LOG.SUCCESS, string.format(
		"%s terminée (%s) : +%d €, %d victime(s) prise(s) en charge.",
		incident.id,
		reason,
		amount,
		saved
	))
end

-- Vérifie si un ensemble de moyens couvre un besoin ; retourne aussi le
-- rapport minimal (0 si un besoin manque).
local function coverage(power: any, requires: any, multiplier: number): (boolean, number)
	local met = true
	local worst = 1
	for capability, need in pairs(requires) do
		local have = (power[capability] or 0) * multiplier
		local ratio = MathX.ratio(have, need)
		if ratio < 1 then
			met = false
		end
		if ratio < worst then
			worst = ratio
		end
	end
	return met, worst
end

-- Fait avancer une intervention active.
function IncidentService.stepIncident(world: any, incident: any, dt: number): ()
	local typeDef = world.catalogs.incidents.get(incident.typeId)
	if not typeDef then
		return
	end

	if incident.closedAt ~= nil then return end
	if not incident.evacuating and #incident.fireCells > 0 then
		FireService.step(incident, dt)
		local burning, spent = FireService.count(incident)
		if burning == 0 and spent == #incident.fireCells then
			IncidentService.fail(world, incident, "propagation à tous les foyers")
			return
		end
	end

	if incident.status == Constants.INCIDENT_STATUS.PENDING then
		if world.time > incident.deadline then
			IncidentService.fail(world, incident, "délai de prise en charge dépassé")
		end
		return
	end

	if incident.status ~= Constants.INCIDENT_STATUS.ACTIVE then
		return
	end

	if incident.evacuating then
		if incident.savedVictims == incident.victims then
			IncidentService.resolve(world, incident, incident.degraded, "transmission des victimes aux urgences")
			return
		end
		local transportActive = HospitalService.load(world, incident)
		for id in pairs(incident.assigned) do
			local vehicle = world.vehicles[id]
			if vehicle and vehicle.status == Constants.VEHICLE_STATUS.DISPATCHED and HospitalService.capacity(world, vehicle) > 0 then
				transportActive = true
			end
		end
		incident.underpoweredFor = if transportActive then 0 else incident.underpoweredFor + dt
		if incident.underpoweredFor > world.config.UNDERPOWER_FAIL_SECONDS then
			IncidentService.fail(world, incident, "victimes en attente de transport sanitaire")
		end
		return
	end

	local vehicles = {}
	for vehicleId in pairs(incident.onScene) do
		local vehicle = world.vehicles[vehicleId]
		if vehicle and vehicle.status == Constants.VEHICLE_STATUS.ON_SCENE and vehicle.incidentId == incident.id then
			table.insert(vehicles, vehicle)
		end
	end

	if #vehicles == 0 then
		local assigned = next(incident.assigned)
		if assigned == nil then
			incident.emptyFor += dt
		else
			incident.emptyFor = 0
		end
		if incident.emptyFor > world.config.UNDERPOWER_FAIL_SECONDS then
			IncidentService.fail(world, incident, "aucun moyen resté sur place")
		end
		return
	end
	incident.emptyFor = 0

	-- Tous les moyens arrivent-ils à couvrir le besoin de l'étape courante ?
	local step = typeDef.steps[incident.stepIndex]
	table.sort(vehicles, function(a, b) return a.id < b.id end)
	local support, working, fraction, anyWork = FieldService.work(world, incident, vehicles, step, dt)
	local power = Crew.totalPower(world, support)
	local bonus = CommandService.sectorBonus(world, incident)
	local multiplier = 1 + bonus

	if step and fraction >= 0 then
		if fraction >= 1 then
			incident.stepIndex += 1
			incident.stepProgress, incident.underpoweredFor = 0, 0
		elseif working then
			incident.stepProgress = fraction * step.seconds
			incident.underpoweredFor = 0
		else
			incident.underpoweredFor = if anyWork then 0 else incident.underpoweredFor + dt
			if incident.underpoweredFor > world.config.UNDERPOWER_FAIL_SECONDS then
				IncidentService.fail(world, incident, "aucune équipe opérationnelle pour « " .. step.label .. " »")
			end
		end
		return
	end

	if step then
		local met, ratio = coverage(power, step.requires, multiplier)
		if met then
			local speed = 0.6 + 0.4 * math.min(1, ratio)
			incident.stepProgress += dt * speed
			incident.underpoweredFor = 0
			if incident.stepProgress >= step.seconds then
				incident.stepIndex += 1
				incident.stepProgress = 0
			end
		else
			incident.underpoweredFor = if anyWork then 0 else incident.underpoweredFor + dt
			if incident.underpoweredFor > world.config.UNDERPOWER_FAIL_SECONDS then
				IncidentService.fail(world, incident, "moyens insuffisants pour l'étape « " .. step.label .. " »")
				return
			end
		end
		return
	end

	-- Toutes les étapes sont terminées : vérification des moyens globaux.
	local globalMet = coverage(power, typeDef.requires, multiplier)
	if not globalMet then
		incident.underpoweredFor += dt
		if incident.underpoweredFor > world.config.UNDERPOWER_FAIL_SECONDS then
			IncidentService.fail(world, incident, "moyens globaux insuffisants")
		end
		return
	end
	incident.underpoweredFor = 0

	local equipmentOk, missingEquipment = Crew.hasRequiredEquipment(world, incident, vehicles)
	local qualificationsOk, missingQualifications = Crew.hasRequiredQualifications(world, incident, vehicles)

	local _, damage = FireService.count(incident)
	local degraded = not equipmentOk or not qualificationsOk or damage > 0
	if incident.victims > 0 then
		incident.evacuating, incident.degraded = true, degraded
		HospitalService.load(world, incident)
		return
	end

	if not degraded then
		IncidentService.resolve(world, incident, false, "moyens complets" .. (bonus > 0 and ", secteur coordonné" or ""))
		return
	end

	local missing = {}
	if damage > 0 then table.insert(missing, "zone brûlée") end
	for _, equipmentId in ipairs(missingEquipment) do
		table.insert(missing, world.catalogs.equipment.label(equipmentId))
	end
	for _, qualificationId in ipairs(missingQualifications) do
		table.insert(missing, world.catalogs.qualifications.label(qualificationId))
	end
	IncidentService.resolve(world, incident, true, "bilan dégradé : " .. table.concat(missing, ", "))
end

function IncidentService.step(world: any, dt: number): ()
	local ids = {}
	for incidentId in pairs(world.incidents) do
		table.insert(ids, incidentId)
	end
	table.sort(ids)
	for _, incidentId in ipairs(ids) do
		IncidentService.stepIncident(world, world.incidents[incidentId], dt)
	end
end

function IncidentService.summary(world: any): any
	local summary = {
		pending = 0,
		active = 0,
		resolved = 0,
		failed = 0,
	}
	for _, incident in pairs(world.incidents) do
		if incident.status == Constants.INCIDENT_STATUS.PENDING then
			summary.pending += 1
		elseif incident.status == Constants.INCIDENT_STATUS.ACTIVE then
			summary.active += 1
		elseif incident.status == Constants.INCIDENT_STATUS.RESOLVED then
			summary.resolved += 1
		elseif incident.status == Constants.INCIDENT_STATUS.FAILED then
			summary.failed += 1
		end
	end
	return summary
end

return IncidentService
