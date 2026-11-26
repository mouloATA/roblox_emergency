--!strict
--[[
	EquipmentService — inventaire et installation du matériel (spec §8).

	Le stock est global ; le matériel installé appartient à un véhicule et
	compte dans sa capacité (unités et poids). Les bonus de capacité apportés
	par le matériel sont calculés par `Crew.power`, pas ici.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Utilities = Shared:WaitForChild("Utilities")
local Constants = require(Shared:WaitForChild("Constants"))
local Result = require(Utilities:WaitForChild("Result"))
local Operations = require(Utilities:WaitForChild("Operations"))

local ServerScript = game:GetService("ServerScriptService"):WaitForChild("ERS")
local Services = ServerScript:WaitForChild("Services")
local PermissionService = require(Services:WaitForChild("PermissionService"))

local EquipmentService = {}

function EquipmentService.stock(world: any): { any }
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

function EquipmentService.installed(world: any, vehicle: any): { any }
	local list = {}
	for equipmentId, quantity in pairs(vehicle.equipment) do
		if quantity > 0 then
			local equipment = world.catalogs.equipment.get(equipmentId)
			table.insert(list, {
				id = equipmentId,
				name = equipment and equipment.name or equipmentId,
				quantity = quantity,
			})
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

function EquipmentService.usedUnits(world: any, vehicle: any): number
	local total = 0
	for _, quantity in pairs(vehicle.equipment) do
		total += quantity
	end
	return total
end

-- Poids total du matériel embarqué (kg simulés).
function EquipmentService.usedWeight(world: any, vehicle: any): number
	local total = 0
	for equipmentId, quantity in pairs(vehicle.equipment) do
		local equipment = world.catalogs.equipment.get(equipmentId)
		if equipment then
			total += equipment.weight * quantity
		end
	end
	return total
end

function EquipmentService.compatible(world: any, vehicle: any, equipment: any): boolean
	local typeDef = world.catalogs.vehicles.get(vehicle.typeId)
	if not typeDef then
		return false
	end
	for _, service in ipairs(equipment.services) do
		if service == typeDef.service then
			return true
		end
	end
	return false
end

-- Installe du matériel du stock sur un véhicule au poste.
function EquipmentService.install(world: any, actorId: number, vehicleId: number, equipmentId: string, quantity: number): any
	local vehicle = world.vehicles[vehicleId]
	if not vehicle then
		return Result.err("Véhicule inconnu.")
	end
	local equipment = world.catalogs.equipment.get(equipmentId)
	if not equipment then
		return Result.err("Matériel inconnu.")
	end

	local check = PermissionService.requireVehicle(world, actorId, Constants.ACTION.EQUIPMENT, vehicle)
	if not check.ok then
		return check
	end
	if vehicle.status ~= Constants.VEHICLE_STATUS.AVAILABLE then
		return Result.err("Le véhicule doit être au poste pour être équipé.")
	end

	local amount = math.floor(quantity)
	if amount < 1 or amount > 99 then
		return Result.err("Quantité invalide.")
	end
	if not EquipmentService.compatible(world, vehicle, equipment) then
		return Result.err("Matériel incompatible avec ce véhicule.")
	end

	local available = world.equipmentStock[equipmentId] or 0
	if available < amount then
		return Result.err(string.format("Stock insuffisant : %d disponible(s).", available))
	end

	local typeDef = world.catalogs.vehicles.get(vehicle.typeId)
	local units = EquipmentService.usedUnits(world, vehicle)
	local weight = EquipmentService.usedWeight(world, vehicle)
	if units + amount > typeDef.equipmentSlots then
		return Result.err(string.format("Capacité d'emport dépassée : %d emplacements.", typeDef.equipmentSlots))
	end
	if weight + equipment.weight * amount > typeDef.capacity then
		return Result.err(string.format("Limite de poids dépassée : %.0f kg.", typeDef.capacity))
	end

	world.equipmentStock[equipmentId] = available - amount
	vehicle.equipment[equipmentId] = (vehicle.equipment[equipmentId] or 0) + amount
	Operations.log(world, Constants.LOG.INFO, string.format(
		"%s : installation de %d × %s.",
		vehicle.callsign,
		amount,
		equipment.name
	))
	return Result.ok(string.format("%d × %s installé(s) sur %s.", amount, equipment.name, vehicle.callsign))
end

-- Retire du matériel d'un véhicule et le remet en stock.
function EquipmentService.uninstall(world: any, actorId: number, vehicleId: number, equipmentId: string, quantity: number): any
	local vehicle = world.vehicles[vehicleId]
	if not vehicle then
		return Result.err("Véhicule inconnu.")
	end
	local equipment = world.catalogs.equipment.get(equipmentId)
	if not equipment then
		return Result.err("Matériel inconnu.")
	end

	local check = PermissionService.requireVehicle(world, actorId, Constants.ACTION.EQUIPMENT, vehicle)
	if not check.ok then
		return check
	end
	if vehicle.status ~= Constants.VEHICLE_STATUS.AVAILABLE then
		return Result.err("Le véhicule doit être au poste pour être modifié.")
	end

	local amount = math.floor(quantity)
	if amount < 1 or amount > 99 then
		return Result.err("Quantité invalide.")
	end
	local installed = vehicle.equipment[equipmentId] or 0
	if installed < amount then
		return Result.err(string.format("Seulement %d installé(s).", installed))
	end

	vehicle.equipment[equipmentId] = installed - amount
	if vehicle.equipment[equipmentId] <= 0 then
		vehicle.equipment[equipmentId] = nil
	end
	world.equipmentStock[equipmentId] = (world.equipmentStock[equipmentId] or 0) + amount
	Operations.log(world, Constants.LOG.INFO, string.format(
		"%s : dépose de %d × %s.",
		vehicle.callsign,
		amount,
		equipment.name
	))
	return Result.ok(string.format("%d × %s remis en stock.", amount, equipment.name))
end

-- Consomme une unité (utilisée par les interventions qui consomment du soin).
function EquipmentService.consume(world: any, vehicle: any, equipmentId: string, quantity: number): boolean
	local amount = math.max(1, math.floor(quantity))
	local installed = vehicle.equipment[equipmentId] or 0
	if installed < amount then
		return false
	end
	vehicle.equipment[equipmentId] = installed - amount
	if vehicle.equipment[equipmentId] <= 0 then
		vehicle.equipment[equipmentId] = nil
	end
	return true
end

return EquipmentService
