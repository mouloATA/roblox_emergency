--!strict
--[[
	Operations — mutations de bas niveau partagées par les services.

	Centraliser ces mutations évite que DispatchService, IncidentService et
	VehicleService écrivent des états différents. Ce module ne décide de rien :
	il applique un déplacement, un retour, un journal.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Utilities = Shared:WaitForChild("Utilities")
local Constants = require(Shared:WaitForChild("Constants"))
local TimeUtil = require(Utilities:WaitForChild("TimeUtil"))
local Navigation = require(Utilities:WaitForChild("Navigation"))
local RoadNetwork = require(Utilities:WaitForChild("RoadNetwork"))
local MathX = require(Utilities:WaitForChild("MathX"))

local Operations = {}

-- Ajoute une entrée en tête du journal (la plus récente d'abord).
-- Chaque entrée reçoit un identifiant monotone : l'interface peut ainsi
-- réconcilier ses lignes sans les reconstruire à chaque snapshot.
function Operations.log(world: any, kind: string, message: string): ()
	local id = world.nextLogId or 1
	world.nextLogId = id + 1
	table.insert(world.log, 1, {
		id = id,
		time = world.time,
		clock = TimeUtil.clock(world),
		kind = kind,
		message = message,
	})
	while #world.log > world.config.LOG_LIMIT do
		table.remove(world.log)
	end
end

-- Nom lisible d'un véhicule ("FPT 1 — Fourgon Pompe Tonne").
function Operations.vehicleLabel(world: any, vehicle: any): string
	local typeDef = world.catalogs.vehicles.get(vehicle.typeId)
	return string.format("%s — %s", vehicle.callsign, typeDef and typeDef.name or vehicle.typeId)
end

-- Déplace un véhicule vers un point ; `siren` réduit le temps de trajet.
-- Le trajet suit le réseau routier du monde quand il est disponible.
function Operations.moveTo(world: any, vehicle: any, x: number, z: number, siren: boolean?): ()
	local typeDef = world.catalogs.vehicles.get(vehicle.typeId)
	if not typeDef then
		return
	end
	local path = RoadNetwork.path(world.roadNetwork, vehicle.position, { x = x, z = z })
	vehicle.route = Navigation.route(world.config, vehicle.position, { x = x, z = z }, typeDef.speed, world.time, siren, path)
end

-- Termine une intervention pour un véhicule : il rentre au poste.
function Operations.release(world: any, vehicle: any): ()
	if vehicle.status == Constants.VEHICLE_STATUS.MAINTENANCE then
		return
	end
	vehicle.incidentId = nil
	local distance = MathX.distance(vehicle.position.x, vehicle.position.z, vehicle.home.x, vehicle.home.z)
	if distance <= world.config.ARRIVAL_RADIUS then
		Operations.arriveHome(world, vehicle)
		return
	end
	vehicle.status = Constants.VEHICLE_STATUS.RETURNING
	local typeDef = world.catalogs.vehicles.get(vehicle.typeId)
	local speed = (typeDef and typeDef.speed or 1.5) * world.config.RETURN_FACTOR
	local path = RoadNetwork.path(world.roadNetwork, vehicle.position, vehicle.home)
	vehicle.route = Navigation.route(world.config, vehicle.position, vehicle.home, speed, world.time, false, path)
end

-- Le véhicule est arrivé au poste : disponible, équipage conservé.
function Operations.arriveHome(world: any, vehicle: any): ()
	vehicle.status = Constants.VEHICLE_STATUS.AVAILABLE
	vehicle.route = nil
	vehicle.incidentId = nil
	vehicle.position = { x = vehicle.home.x, z = vehicle.home.z }
end

-- Met à jour la position d'un véhicule en route.
function Operations.stepRoute(world: any, vehicle: any): boolean
	if not vehicle.route then
		return false
	end
	local position = Navigation.position(vehicle.route, world.time)
	vehicle.position = position
	if Navigation.arrived(vehicle.route, world.time) then
		return true
	end
	return false
end

return Operations
