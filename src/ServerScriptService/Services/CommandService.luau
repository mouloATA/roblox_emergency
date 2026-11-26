--!strict
--[[
	CommandService — groupes, secteurs et engagement groupé (spec §11).

	Un groupe rassemble des véhicules ; un secteur est une zone circulaire de
	la carte. Quand un secteur couvre une intervention et que son groupe y est
	engagé, la coordination apporte un bonus de 10 % aux moyens présents.
	Le bonus est réellement appliqué dans `IncidentService`.
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
local DispatchService = require(Services:WaitForChild("DispatchService"))

local CommandService = {}

local MAX_GROUP_SIZE = 8
local MAX_GROUPS = 12
local MAX_SECTORS = 20

local function trim(text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

function CommandService.createGroup(world: any, actorId: number, name: string, service: string?): any
	local check = PermissionService.require(world, actorId, Constants.ACTION.COMMAND)
	if not check.ok then
		return check
	end
	local cleanName = trim(name or "")
	if #cleanName < 2 or #cleanName > 32 then
		return Result.err("Nom de groupe invalide (2 à 32 caractères).")
	end
	if service ~= nil and Constants.SERVICE_LABEL[service] == nil then
		return Result.err("Service de groupe inconnu.")
	end
	local count = 0
	for _ in pairs(world.groups) do
		count += 1
	end
	if count >= MAX_GROUPS then
		return Result.err("Nombre maximal de groupes atteint.")
	end

	local group = {
		id = world.nextGroupId,
		name = cleanName,
		service = service,
		vehicles = {},
		sectorId = nil,
		createdBy = actorId,
	}
	world.nextGroupId += 1
	world.groups[group.id] = group
	Operations.log(world, Constants.LOG.INFO, string.format("Groupe « %s » créé.", cleanName))
	return Result.ok(string.format("Groupe « %s » créé.", cleanName), group)
end

function CommandService.addUnit(world: any, actorId: number, groupId: number, vehicleId: number): any
	local check = PermissionService.require(world, actorId, Constants.ACTION.COMMAND)
	if not check.ok then
		return check
	end
	local group = world.groups[groupId]
	if not group then
		return Result.err("Groupe inconnu.")
	end
	local vehicle = world.vehicles[vehicleId]
	if not vehicle then
		return Result.err("Véhicule inconnu.")
	end
	if #group.vehicles >= MAX_GROUP_SIZE then
		return Result.err("Un groupe contient au maximum 8 véhicules.")
	end
	for _, otherGroup in pairs(world.groups) do
		for _, memberId in ipairs(otherGroup.vehicles) do
			if memberId == vehicleId then
				return Result.err("Ce véhicule appartient déjà au groupe « " .. otherGroup.name .. " ».")
			end
		end
	end
	if group.service then
		local typeDef = world.catalogs.vehicles.get(vehicle.typeId)
		if not typeDef or typeDef.service ~= group.service then
			return Result.err("Ce véhicule n'est pas du service du groupe.")
		end
	end

	table.insert(group.vehicles, vehicleId)
	Operations.log(world, Constants.LOG.INFO, string.format("%s rejoint le groupe « %s ».", vehicle.callsign, group.name))
	return Result.ok(string.format("%s ajouté au groupe « %s ».", vehicle.callsign, group.name), group)
end

function CommandService.removeUnit(world: any, actorId: number, groupId: number, vehicleId: number): any
	local check = PermissionService.require(world, actorId, Constants.ACTION.COMMAND)
	if not check.ok then
		return check
	end
	local group = world.groups[groupId]
	if not group then
		return Result.err("Groupe inconnu.")
	end
	for index, memberId in ipairs(group.vehicles) do
		if memberId == vehicleId then
			table.remove(group.vehicles, index)
			return Result.ok("Véhicule retiré du groupe.", group)
		end
	end
	return Result.err("Ce véhicule n'est pas dans le groupe.")
end

function CommandService.dissolve(world: any, actorId: number, groupId: number): any
	local check = PermissionService.require(world, actorId, Constants.ACTION.COMMAND)
	if not check.ok then
		return check
	end
	local group = world.groups[groupId]
	if not group then
		return Result.err("Groupe inconnu.")
	end
	for _, sector in pairs(world.sectors) do
		if sector.groupId == groupId then
			sector.groupId = nil
		end
	end
	world.groups[groupId] = nil
	Operations.log(world, Constants.LOG.INFO, string.format("Groupe « %s » dissous.", group.name))
	return Result.ok(string.format("Groupe « %s » dissous.", group.name))
end

-- Engage tous les véhicules disponibles du groupe sur une intervention.
function CommandService.dispatchGroup(world: any, actorId: number, groupId: number, incidentId: number): any
	local check = PermissionService.require(world, actorId, Constants.ACTION.COMMAND)
	if not check.ok then
		return check
	end
	local group = world.groups[groupId]
	if not group then
		return Result.err("Groupe inconnu.")
	end
	if #group.vehicles == 0 then
		return Result.err("Le groupe est vide.")
	end

	local sent = 0
	local failures = {}
	for _, vehicleId in ipairs(table.clone(group.vehicles)) do
		local result = DispatchService.dispatch(world, actorId, vehicleId, incidentId)
		if result.ok then
			sent += 1
		else
			local vehicle = world.vehicles[vehicleId]
			table.insert(failures, string.format("%s : %s", vehicle and vehicle.callsign or vehicleId, result.message))
		end
	end

	if sent == 0 then
		return Result.err("Aucun véhicule du groupe n'a pu partir. " .. table.concat(failures, " "))
	end
	local message = string.format("%d véhicule(s) du groupe « %s » engagé(s).", sent, group.name)
	if #failures > 0 then
		message ..= " Refus : " .. table.concat(failures, " ")
	end
	return Result.ok(message, { sent = sent, failures = failures })
end

function CommandService.createSector(world: any, actorId: number, name: string, x: number, z: number, radius: number): any
	local check = PermissionService.require(world, actorId, Constants.ACTION.COMMAND)
	if not check.ok then
		return check
	end
	local cleanName = trim(name or "")
	if #cleanName < 2 or #cleanName > 32 then
		return Result.err("Nom de secteur invalide (2 à 32 caractères).")
	end
	if type(x) ~= "number" or type(z) ~= "number" then
		return Result.err("Coordonnées invalides.")
	end
	if x < 0 or x > world.config.MAP_SIZE or z < 0 or z > world.config.MAP_SIZE then
		return Result.err("Le secteur doit rester sur la carte.")
	end
	if type(radius) ~= "number" or radius < 5 or radius > 40 then
		return Result.err("Rayon du secteur hors limites (5 à 40).")
	end
	local count = 0
	for _ in pairs(world.sectors) do
		count += 1
	end
	if count >= MAX_SECTORS then
		return Result.err("Nombre maximal de secteurs atteint.")
	end

	local sector = {
		id = world.nextSectorId,
		name = cleanName,
		x = x,
		z = z,
		radius = radius,
		groupId = nil,
		createdBy = actorId,
	}
	world.nextSectorId += 1
	world.sectors[sector.id] = sector
	Operations.log(world, Constants.LOG.INFO, string.format("Secteur « %s » créé.", cleanName))
	return Result.ok(string.format("Secteur « %s » créé.", cleanName), sector)
end

function CommandService.assignGroupToSector(world: any, actorId: number, sectorId: number, groupId: number): any
	local check = PermissionService.require(world, actorId, Constants.ACTION.COMMAND)
	if not check.ok then
		return check
	end
	local sector = world.sectors[sectorId]
	if not sector then
		return Result.err("Secteur inconnu.")
	end
	local group = world.groups[groupId]
	if not group then
		return Result.err("Groupe inconnu.")
	end
	if group.sectorId and group.sectorId ~= sectorId then
		local previous = world.sectors[group.sectorId]
		if previous then
			previous.groupId = nil
		end
	end
	if sector.groupId and sector.groupId ~= groupId then
		local previousGroup = world.groups[sector.groupId]
		if previousGroup then
			previousGroup.sectorId = nil
		end
	end
	sector.groupId = groupId
	group.sectorId = sectorId
	Operations.log(world, Constants.LOG.INFO, string.format("Groupe « %s » affecté au secteur « %s ».", group.name, sector.name))
	return Result.ok(string.format("Groupe « %s » affecté au secteur « %s ».", group.name, sector.name), sector)
end

-- Bonus de coordination : un secteur couvre l'intervention et son groupe est
-- sur place. Retourne un facteur additif (0 ou 0,1).
function CommandService.sectorBonus(world: any, incident: any): number
	for _, sector in pairs(world.sectors) do
		if sector.groupId then
			local group = world.groups[sector.groupId]
			if group and MathX.distance(sector.x, sector.z, incident.position.x, incident.position.z) <= sector.radius then
				for _, vehicleId in ipairs(group.vehicles) do
					local vehicle = world.vehicles[vehicleId]
					if
						vehicle
						and vehicle.incidentId == incident.id
						and vehicle.status == Constants.VEHICLE_STATUS.ON_SCENE
					then
						return 0.1
					end
				end
			end
		end
	end
	return 0
end

function CommandService.listGroups(world: any): { any }
	local list = {}
	for _, group in pairs(world.groups) do
		table.insert(list, group)
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

return CommandService
