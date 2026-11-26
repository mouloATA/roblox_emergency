--!strict
-- Un ordre est porté par un équipage. Il mobilise cet équipage jusqu'au résultat ou au contre-ordre.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Utilities = Shared:WaitForChild("Utilities")
local Crew = require(Utilities:WaitForChild("Crew"))
local Result = require(Utilities:WaitForChild("Result"))
local Operations = require(Utilities:WaitForChild("Operations"))
local Services = game:GetService("ServerScriptService"):WaitForChild("ERS"):WaitForChild("Services")
local FireService = require(Services:WaitForChild("FireService"))
local PermissionService = require(Services:WaitForChild("PermissionService"))

local FieldService = {}
local ORDER = Constants.FIELD_ORDER
local STEPS = {
	attaque = ORDER.EXTINGUISH, extinction = ORDER.EXTINGUISH, sauvetage = ORDER.RESCUE,
	desincarceration = ORDER.EXTRICATE, decoupe = ORDER.EXTRICATE,
}

-- Traduit l'étape du catalogue en intervention physique, le cas échéant.
function FieldService.actionForStep(step: any): string?
	return step and STEPS[step.id]
end

-- Prépare les cibles des équipes à partir du déroulé du catalogue.
function FieldService.prepare(incident: any, definition: any): ()
	FireService.ignite(incident, definition)
	incident.rescueTarget, incident.extricationTarget = 0, 0
	incident.rescueWork, incident.extricationWork = 0, 0
	incident.rescued, incident.extricated = 0, 0
	for _, step in ipairs(definition.steps) do
		if STEPS[step.id] == ORDER.RESCUE then incident.rescueTarget = incident.victims end
		if STEPS[step.id] == ORDER.EXTRICATE then incident.extricationTarget = incident.victims end
	end
end

local function canWork(world: any, vehicle: any, incident: any, order: string): boolean
	if order == ORDER.AUTO or order == ORDER.HOLD then return true end
	local power = Crew.power(world, vehicle)
	if order == ORDER.EXTINGUISH then
		return FireService.count(incident) > 0 and (vehicle.water or 0) > 0 and (power.fire or 0) > 0
	elseif order == ORDER.EXTRICATE then
		return incident.extricated < incident.extricationTarget and (power.rescue or 0) > 0
			and ((vehicle.equipment.CISAILLE or 0) > 0 or (vehicle.equipment.ECARTEUR or 0) > 0)
	elseif order == ORDER.RESCUE then
		return incident.rescued < incident.rescueTarget and (power.rescue or 0) > 0
	end
	return false
end

-- Indique au CTA les ordres actuellement réalisables par cet équipage.
function FieldService.choices(world: any, vehicle: any): { string }
	local list = {}
	local incident = world.incidents[vehicle.incidentId]
	if vehicle.status == Constants.VEHICLE_STATUS.ON_SCENE and incident then
		for _, order in ipairs({ORDER.AUTO, ORDER.HOLD, ORDER.EXTINGUISH, ORDER.RESCUE, ORDER.EXTRICATE}) do
			if (not incident.evacuating or order == ORDER.AUTO or order == ORDER.HOLD)
				and canWork(world, vehicle, incident, order) then table.insert(list, order) end
		end
	end
	return list
end

-- Valide le poste, l'intervention visée, l'équipage et son matériel avant de changer l'ordre.
function FieldService.giveOrder(world: any, actorId: number, vehicleId: number, incidentId: string, order: string): any
	local vehicle = world.vehicles[vehicleId]
	if not vehicle or vehicle.incidentId ~= incidentId then return Result.err("Équipage absent de cette intervention.") end
	local permission = PermissionService.requireVehicle(world, actorId, Constants.ACTION.DISPATCH, vehicle)
	if not permission.ok then return permission end
	if not table.find(FieldService.choices(world, vehicle), order) then
		return Result.err("Ordre indisponible pour cet équipage, sa position ou son matériel.")
	end
	vehicle.fieldOrder = order
	local message = vehicle.callsign .. " · " .. Constants.FIELD_LABEL[order]
	Operations.log(world, Constants.LOG.DISPATCH, message)
	return Result.ok(message)
end

-- Fait agir chaque équipe sur sa cible. Les équipes en réserve ou occupées ne couvrent pas les autres étapes.
function FieldService.work(world: any, incident: any, vehicles: { any }, step: any, dt: number): ({ any }, boolean, number, boolean)
	local target = FieldService.actionForStep(step)
	local support = {}
	local didWork, anyWork = false, false
	for _, vehicle in ipairs(vehicles) do
		local order = vehicle.fieldOrder or ORDER.AUTO
		if order ~= ORDER.AUTO and order ~= ORDER.HOLD and not canWork(world, vehicle, incident, order) then
			vehicle.fieldOrder, order = ORDER.AUTO, ORDER.AUTO
		end
		local action = if order == ORDER.AUTO then target else order
		vehicle.fieldActivity = nil
		if action == nil or action == target then table.insert(support, vehicle) end
		if not action or action == ORDER.HOLD or not canWork(world, vehicle, incident, action) then continue end
		vehicle.fieldActivity = action
		local power = Crew.power(world, vehicle)
		if action == ORDER.EXTINGUISH then
			local used = FireService.applyWater(incident, math.min(vehicle.water, dt * (2 + power.fire)))
			vehicle.water -= used
		elseif action == ORDER.EXTRICATE then
			incident.extricationWork = math.min(incident.extricationTarget, incident.extricationWork + dt * power.rescue / 15)
			incident.extricated = math.floor(incident.extricationWork)
		elseif action == ORDER.RESCUE then
			if not incident.canineSearch then
				for _, member in ipairs(Crew.members(world, vehicle)) do
					if member.qualifications.MAITRE_CHIEN then
						incident.canineSearch = true
						break
					end
				end
			end
			incident.rescueWork = math.min(incident.rescueTarget, incident.rescueWork + dt * power.rescue / 10)
			incident.rescued = math.floor(incident.rescueWork)
		end
		anyWork = true
		if action == target then didWork = true end
	end
	if target == ORDER.EXTINGUISH then
		local heat = 0
		for _, cell in ipairs(incident.fireCells) do
			if cell.burning then heat += cell.heat end
		end
		local fraction = if heat == 0 then 1 else incident.waterUsed / (incident.waterUsed + heat)
		return support, didWork, fraction, anyWork
	elseif target == ORDER.RESCUE then
		return support, didWork, if incident.rescueTarget == 0 then 1 else incident.rescueWork / incident.rescueTarget, anyWork
	elseif target == ORDER.EXTRICATE then
		return support, didWork, if incident.extricationTarget == 0 then 1 else incident.extricationWork / incident.extricationTarget, anyWork
	end
	return support, false, -1, anyWork
end

return FieldService
