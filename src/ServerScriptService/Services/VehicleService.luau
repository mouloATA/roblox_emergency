--!strict
--[[
	VehicleService — flotte, achat, disponibilité et entretien (spec §6).

	Un véhicule a une position, un équipage stable, du matériel et un état
	mécanique. Il ne peut partir que s'il est au poste, en état de rouler, avec
	un équipage complet — les contrôles d'équipage vivent dans `Crew`.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Utilities = Shared:WaitForChild("Utilities")
local Constants = require(Shared:WaitForChild("Constants"))
local Result = require(Utilities:WaitForChild("Result"))
local MathX = require(Utilities:WaitForChild("MathX"))
local Operations = require(Utilities:WaitForChild("Operations"))

local ServerScript = game:GetService("ServerScriptService"):WaitForChild("ERS")
local Services = ServerScript:WaitForChild("Services")
local PermissionService = require(Services:WaitForChild("PermissionService"))
local BudgetService = require(Services:WaitForChild("BudgetService"))

local VehicleService = {}

local MIN_CONDITION = 20

local function callsignTaken(world: any, callsign: string): boolean
	for _, vehicle in pairs(world.vehicles) do
		if vehicle.callsign == callsign then
			return true
		end
	end
	return false
end

-- Génère un indicatif unique du type "VSAV 2".
function VehicleService.nextCallsign(world: any, typeDef: any): string
	local index = 1
	while callsignTaken(world, string.format("%s %d", typeDef.id, index)) do
		index += 1
	end
	return string.format("%s %d", typeDef.id, index)
end

-- Emplacement de stationnement au poste (évite que les engins se superposent).
function VehicleService.homePosition(world: any): { x: number, z: number }
	local index = 0
	for _ in pairs(world.vehicles) do
		index += 1
	end
	local column = index % 4
	local row = math.floor(index / 4)
	return {
		x = MathX.clamp(world.config.HQ_X + column * 2.4, 3, 97),
		z = MathX.clamp(world.config.HQ_Z + row * 2.4, 3, 97),
	}
end

-- Création interne : installe le matériel par défaut dans la limite du stock.
function VehicleService.create(world: any, typeId: string, callsign: string?): any
	local typeDef = world.catalogs.vehicles.get(typeId)
	if not typeDef then
		return Result.err("Type de véhicule inconnu.")
	end
	local finalCallsign = callsign or VehicleService.nextCallsign(world, typeDef)
	if callsignTaken(world, finalCallsign) then
		return Result.err("Indicatif déjà utilisé.")
	end

	local home = VehicleService.homePosition(world)
	local vehicle = {
		id = world.nextVehicleId,
		typeId = typeId,
		callsign = finalCallsign,
		status = Constants.VEHICLE_STATUS.AVAILABLE,
		condition = 100,
		position = { x = home.x, z = home.z },
		home = home,
		crew = {},
		equipment = {},
		incidentId = nil,
		route = nil,
		repairRemaining = 0,
	}
	world.nextVehicleId += 1
	world.vehicles[vehicle.id] = vehicle

	for _, entry in ipairs(typeDef.defaultEquipment) do
		local available = world.equipmentStock[entry.id] or 0
		local amount = math.min(entry.quantity, available)
		if amount > 0 then
			world.equipmentStock[entry.id] = available - amount
			vehicle.equipment[entry.id] = amount
		end
	end

	return Result.ok(finalCallsign .. " mis en service.", vehicle)
end

function VehicleService.buy(world: any, actorId: number, typeId: string): any
	local check = PermissionService.require(world, actorId, Constants.ACTION.BUY_VEHICLE)
	if not check.ok then
		return check
	end
	local typeDef = world.catalogs.vehicles.get(typeId)
	if not typeDef then
		return Result.err("Type de véhicule inconnu.")
	end
	local count = 0
	for _ in pairs(world.vehicles) do
		count += 1
	end
	if count >= world.config.MAX_FLEET then
		return Result.err(string.format("Parc complet : %d véhicules maximum.", world.config.MAX_FLEET))
	end
	if not BudgetService.canAfford(world, typeDef.cost) then
		return Result.err(string.format("Budget insuffisant : %d € requis.", typeDef.cost))
	end

	local spend = BudgetService.spend(world, typeDef.cost, "Achat " .. typeDef.name)
	if not spend.ok then
		return spend
	end

	local created = VehicleService.create(world, typeId)
	if not created.ok then
		-- Rembourse l'achat si la création échoue : aucune perte silencieuse.
		BudgetService.earn(world, typeDef.cost, "Remboursement achat " .. typeDef.name)
		return created
	end

	Operations.log(world, Constants.LOG.MONEY, string.format(
		"Achat de %s (%d €).",
		created.data.callsign,
		typeDef.cost
	))
	return created
end

function VehicleService.available(world: any, vehicle: any): boolean
	return vehicle.status == Constants.VEHICLE_STATUS.AVAILABLE and vehicle.condition >= MIN_CONDITION
end

-- Usure après un engagement ; ne descend jamais sous 1 %.
function VehicleService.wear(world: any, vehicle: any, distance: number): ()
	local loss = MathX.clamp(1 + distance / 50, 1, 6)
	vehicle.condition = math.max(1, vehicle.condition - loss)
end

-- Réparation : dépense immédiate, immobilisation temporisée.
function VehicleService.repair(world: any, actorId: number, vehicleId: number): any
	local vehicle = world.vehicles[vehicleId]
	if not vehicle then
		return Result.err("Véhicule inconnu.")
	end
	local check = PermissionService.requireVehicle(world, actorId, Constants.ACTION.REPAIR, vehicle)
	if not check.ok then
		return check
	end
	if vehicle.status ~= Constants.VEHICLE_STATUS.AVAILABLE then
		return Result.err("Le véhicule doit être au poste pour partir à l'atelier.")
	end
	if vehicle.condition >= 100 then
		return Result.err("Le véhicule est déjà en parfait état.")
	end

	local missing = 100 - vehicle.condition
	local cost = math.ceil(missing * world.config.REPAIR_COST_PER_POINT)
	if not BudgetService.canAfford(world, cost) then
		return Result.err(string.format("Réparation impossible : %d € requis.", cost))
	end
	local spend = BudgetService.spend(world, cost, "Réparation " .. vehicle.callsign)
	if not spend.ok then
		return spend
	end

	vehicle.status = Constants.VEHICLE_STATUS.MAINTENANCE
	vehicle.repairRemaining = missing * world.config.REPAIR_SECONDS_PER_POINT
	vehicle.route = nil
	vehicle.incidentId = nil
	Operations.log(world, Constants.LOG.MONEY, string.format(
		"%s part à l'atelier (%d €, %s).",
		vehicle.callsign,
		cost,
		math.ceil(vehicle.repairRemaining) .. " s"
	))
	return Result.ok(string.format("%s en réparation pour %d €.", vehicle.callsign, cost), vehicle)
end

-- Avance les réparations.
function VehicleService.stepRepair(world: any, dt: number): ()
	for _, vehicle in pairs(world.vehicles) do
		if vehicle.status == Constants.VEHICLE_STATUS.MAINTENANCE then
			vehicle.repairRemaining -= dt
			if vehicle.repairRemaining <= 0 then
				vehicle.repairRemaining = 0
				vehicle.condition = 100
				vehicle.status = Constants.VEHICLE_STATUS.AVAILABLE
				Operations.log(world, Constants.LOG.SUCCESS, vehicle.callsign .. " est de nouveau opérationnel.")
			end
		end
	end
end

-- Un véhicule qui rentre avec un état critique est immobilisé.
function VehicleService.afterReturn(world: any, vehicle: any): ()
	if vehicle.condition < MIN_CONDITION then
		vehicle.status = Constants.VEHICLE_STATUS.MAINTENANCE
		vehicle.repairRemaining = (100 - vehicle.condition) * world.config.REPAIR_SECONDS_PER_POINT
		Operations.log(world, Constants.LOG.FAILURE, string.format(
			"%s est immobilisé (état %.0f %%) : réparation nécessaire.",
			vehicle.callsign,
			vehicle.condition
		))
	end
end

function VehicleService.summary(world: any): any
	local summary = {
		total = 0,
		available = 0,
		dispatched = 0,
		onScene = 0,
		returning = 0,
		maintenance = 0,
	}
	for _, vehicle in pairs(world.vehicles) do
		summary.total += 1
		if vehicle.status == Constants.VEHICLE_STATUS.AVAILABLE then
			summary.available += 1
		elseif vehicle.status == Constants.VEHICLE_STATUS.DISPATCHED then
			summary.dispatched += 1
		elseif vehicle.status == Constants.VEHICLE_STATUS.ON_SCENE then
			summary.onScene += 1
		elseif vehicle.status == Constants.VEHICLE_STATUS.RETURNING then
			summary.returning += 1
		elseif vehicle.status == Constants.VEHICLE_STATUS.MAINTENANCE then
			summary.maintenance += 1
		end
	end
	return summary
end

return VehicleService
