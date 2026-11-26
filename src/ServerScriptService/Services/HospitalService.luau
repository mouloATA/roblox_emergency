--!strict
-- Navettes entre le sinistre et l'entrée de l'hôpital de la ville.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Operations = require(Shared:WaitForChild("Utilities"):WaitForChild("Operations"))
local HospitalService = {}
local STATUS = Constants.VEHICLE_STATUS
local HANDOVER_SECONDS = 8

-- Le véhicule doit disposer à la fois d'une place sanitaire et d'un brancard installé.
function HospitalService.capacity(world: any, vehicle: any): number
	local definition = world.catalogs.vehicles.get(vehicle.typeId)
	return math.min(definition and definition.patientCapacity or 0, vehicle.equipment.BRANCARD or 0)
end

local function hospitalEntrance(world: any): any
	for _, building in ipairs(world.cityPlan.buildings) do
		if building.facadeName == "hopital" then
			return { x = (building.x0 + building.x1) / 2, z = building.z1 + 0.6 }
		end
	end
	return nil
end

-- Réserve les places et charge chaque ambulance ; les victimes en transit ne peuvent pas être embarquées deux fois.
function HospitalService.load(world: any, incident: any): boolean
	local entrance = hospitalEntrance(world)
	if not entrance then return false end
	local ids = {}
	for id in pairs(incident.onScene) do table.insert(ids, id) end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local vehicle = world.vehicles[id]
		local waiting = incident.victims - incident.savedVictims - incident.inTransit
		if waiting <= 0 then break end
		if not vehicle or vehicle.status ~= STATUS.ON_SCENE or vehicle.fieldOrder == Constants.FIELD_ORDER.HOLD then continue end
		local patients = math.min(waiting, HospitalService.capacity(world, vehicle))
		if patients > 0 then
			vehicle.patients, vehicle.status = patients, STATUS.TRANSPORTING
			vehicle.fieldActivity = nil
			incident.inTransit += patients
			incident.onScene[id] = nil
			Operations.moveTo(world, vehicle, entrance.x, entrance.z, true)
			Operations.log(world, Constants.LOG.DISPATCH, string.format("%s part vers les urgences avec %d victime(s).", vehicle.callsign, patients))
		end
	end
	return incident.inTransit > 0
end

-- Parcourt la route, transmet les victimes aux urgences puis organise les rotations restantes.
function HospitalService.stepVehicle(world: any, vehicle: any): ()
	local incident = world.incidents[vehicle.incidentId]
	if not incident then return end
	if vehicle.status == STATUS.TRANSPORTING then
		if Operations.stepRoute(world, vehicle) then
			vehicle.status = STATUS.HANDOVER
			vehicle.handoverAt = world.time + HANDOVER_SECONDS
			vehicle.route = nil
		end
		return
	end
	if world.time < vehicle.handoverAt then return end
	local admitted = vehicle.patients
	incident.inTransit -= admitted
	incident.savedVictims += admitted
	world.stats.savedVictims += admitted
	vehicle.patients, vehicle.handoverAt = 0, nil
	Operations.log(world, Constants.LOG.SUCCESS, string.format("Urgences · %d victime(s) admise(s) par %s.", admitted, vehicle.callsign))
	if incident.savedVictims + incident.inTransit < incident.victims then
		vehicle.status = STATUS.DISPATCHED
		Operations.moveTo(world, vehicle, incident.position.x, incident.position.z, false)
	else
		incident.assigned[vehicle.id] = nil
		Operations.release(world, vehicle)
	end
end

return HospitalService
