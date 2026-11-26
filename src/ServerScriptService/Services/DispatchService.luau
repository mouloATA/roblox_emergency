--!strict
--[[
	DispatchService — engagement et suivi des véhicules (spec §11).

	Engager un véhicule :
	1. vérifie les droits et le périmètre du service ;
	2. vérifie l'équipage complet et l'état du véhicule ;
	3. débite le coût de mobilisation ;
	4. calcule le trajet, l'usure et le statut ;
	5. marque l'intervention comme prise en charge.

	Le retour est automatique après clôture, ou manuel via `recall`.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Utilities = Shared:WaitForChild("Utilities")
local Constants = require(Shared:WaitForChild("Constants"))
local Result = require(Utilities:WaitForChild("Result"))
local Crew = require(Utilities:WaitForChild("Crew"))
local MathX = require(Utilities:WaitForChild("MathX"))
local Navigation = require(Utilities:WaitForChild("Navigation"))
local Operations = require(Utilities:WaitForChild("Operations"))

local ServerScript = game:GetService("ServerScriptService"):WaitForChild("ERS")
local Services = ServerScript:WaitForChild("Services")
local PermissionService = require(Services:WaitForChild("PermissionService"))
local BudgetService = require(Services:WaitForChild("BudgetService"))
local VehicleService = require(Services:WaitForChild("VehicleService"))

local DispatchService = {}

-- Véhicules réellement sur les lieux d'une intervention.
function DispatchService.onSceneVehicles(world: any, incident: any): { any }
	local list = {}
	for vehicleId in pairs(incident.onScene) do
		local vehicle = world.vehicles[vehicleId]
		if vehicle and vehicle.status == Constants.VEHICLE_STATUS.ON_SCENE and vehicle.incidentId == incident.id then
			table.insert(list, vehicle)
		end
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

-- Engin déjà sur place : bascule immédiate sur les lieux.
function DispatchService.arriveOnScene(world: any, vehicle: any, incident: any): ()
	vehicle.status = Constants.VEHICLE_STATUS.ON_SCENE
	incident.onScene[vehicle.id] = true
	if incident.status == Constants.INCIDENT_STATUS.PENDING then
		incident.status = Constants.INCIDENT_STATUS.ACTIVE
	end
	Operations.log(world, Constants.LOG.INCIDENT, string.format(
		"%s est sur place (%s).",
		vehicle.callsign,
		incident.id
	))
end

function DispatchService.dispatch(world: any, actorId: number, vehicleId: number, incidentId: number): any
	local vehicle = world.vehicles[vehicleId]
	if not vehicle then
		return Result.err("Véhicule inconnu.")
	end
	local incident = world.incidents[incidentId]
	if not incident then
		return Result.err("Intervention inconnue.")
	end
	if incident.status ~= Constants.INCIDENT_STATUS.PENDING and incident.status ~= Constants.INCIDENT_STATUS.ACTIVE then
		return Result.err("Cette intervention est déjà clôturée.")
	end
	if incident.assigned[vehicle.id] then
		return Result.err("Ce véhicule est déjà engagé sur cette intervention.")
	end
	if not VehicleService.available(world, vehicle) then
		return Result.err("Le véhicule n'est pas disponible (statut ou état mécanique).")
	end

	local check = PermissionService.requireVehicle(world, actorId, Constants.ACTION.DISPATCH, vehicle)
	if not check.ok then
		return check
	end

	local readiness = Crew.readiness(world, vehicle)
	if not readiness.ok then
		return readiness
	end

	local typeDef = world.catalogs.vehicles.get(vehicle.typeId)
	if not typeDef then
		return Result.err("Type de véhicule inconnu.")
	end

	local spend = BudgetService.spend(world, typeDef.mobilizationCost, "Mobilisation " .. vehicle.callsign)
	if not spend.ok then
		return spend
	end

	incident.assigned[vehicle.id] = true
	incident.status = Constants.INCIDENT_STATUS.ACTIVE
	vehicle.incidentId = incident.id
	vehicle.status = Constants.VEHICLE_STATUS.DISPATCHED
	Operations.moveTo(world, vehicle, incident.position.x, incident.position.z, true)

	local directDistance = MathX.distance(vehicle.position.x, vehicle.position.z, incident.position.x, incident.position.z)
	local distance = vehicle.route and vehicle.route.length or directDistance
	VehicleService.wear(world, vehicle, distance)
	world.stats.dispatched += 1

	Operations.log(world, Constants.LOG.DISPATCH, string.format(
		"%s engagé sur %s (%s).",
		vehicle.callsign,
		world.catalogs.incidents.label(incident.typeId),
		incident.id
	))

	if directDistance <= world.config.ARRIVAL_RADIUS then
		DispatchService.arriveOnScene(world, vehicle, incident)
	end

	return Result.ok(string.format("%s part sur l'intervention.", vehicle.callsign), vehicle)
end

-- Rappel : le véhicule quitte les lieux et rentre au poste.
function DispatchService.recall(world: any, actorId: number, vehicleId: number): any
	local vehicle = world.vehicles[vehicleId]
	if not vehicle then
		return Result.err("Véhicule inconnu.")
	end
	local check = PermissionService.requireVehicle(world, actorId, Constants.ACTION.RECALL, vehicle)
	if not check.ok then
		return check
	end
	if vehicle.incidentId == nil then
		return Result.err("Ce véhicule n'est pas engagé.")
	end

	local incident = world.incidents[vehicle.incidentId]
	if incident then
		incident.assigned[vehicle.id] = nil
		incident.onScene[vehicle.id] = nil
	end
	Operations.release(world, vehicle)
	Operations.log(world, Constants.LOG.DISPATCH, vehicle.callsign .. " est rappelé.")
	return Result.ok(vehicle.callsign .. " rentre au poste.", vehicle)
end

-- Avance les trajets et les transitions d'arrivée.
function DispatchService.step(world: any, dt: number): ()
	local ids = {}
	for vehicleId in pairs(world.vehicles) do
		table.insert(ids, vehicleId)
	end
	table.sort(ids)

	for _, vehicleId in ipairs(ids) do
		local vehicle = world.vehicles[vehicleId]

		if vehicle.status == Constants.VEHICLE_STATUS.DISPATCHED then
			if Operations.stepRoute(world, vehicle) then
				local incident = vehicle.incidentId and world.incidents[vehicle.incidentId] or nil
				if incident and (incident.status == Constants.INCIDENT_STATUS.PENDING or incident.status == Constants.INCIDENT_STATUS.ACTIVE) then
					vehicle.position = { x = incident.position.x, z = incident.position.z }
					DispatchService.arriveOnScene(world, vehicle, incident)
				else
					Operations.release(world, vehicle)
				end
			end
		elseif vehicle.status == Constants.VEHICLE_STATUS.RETURNING then
			if Operations.stepRoute(world, vehicle) then
				Operations.arriveHome(world, vehicle)
				VehicleService.afterReturn(world, vehicle)
				Operations.log(world, Constants.LOG.INFO, vehicle.callsign .. " est de retour au poste.")
			end
		end
	end
end

-- Trajet restant d'un véhicule (pour l'interface).
function DispatchService.remainingTravel(world: any, vehicle: any): number
	if not vehicle.route then
		return 0
	end
	return Navigation.remaining(vehicle.route, world.time)
end

return DispatchService
