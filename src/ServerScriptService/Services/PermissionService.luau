--!strict
--[[
	PermissionService — rôles, affectation et contrôles d'accès (spec §12.3).

	Le serveur ne fait jamais confiance au client : tout identifiant d'acteur
	vient de `Player.UserId`, et chaque action est vérifiée ici avant d'atteindre
	un service métier.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Utilities = Shared:WaitForChild("Utilities")
local Constants = require(Shared:WaitForChild("Constants"))
local Result = require(Utilities:WaitForChild("Result"))
local Permissions = require(Shared:WaitForChild("Catalogs"):WaitForChild("Permissions"))

local PermissionService = {}

function PermissionService.roleOf(world: any, userId: number): string
	local player = world.players[userId]
	return player and player.role or Constants.ROLE.OBSERVATEUR
end

function PermissionService.playerOf(world: any, userId: number): any?
	return world.players[userId]
end

local function roleHolder(world: any, role: string, exceptUserId: number?): any?
	for _, player in pairs(world.players) do
		if player.role == role and player.userId ~= exceptUserId then
			return player
		end
	end
	return nil
end

-- Crée ou met à jour la fiche d'un joueur qui rejoint la partie.
-- Le premier joueur reçoit la direction ; les suivants sont observateurs
-- jusqu'à ce qu'ils choisissent un poste libre.
function PermissionService.seed(world: any, userId: number, name: string): any
	local existing = world.players[userId]
	if existing then
		existing.name = name
		return Result.ok("Joueur reconnecté.", existing)
	end

	local role = Constants.ROLE.OBSERVATEUR
	if roleHolder(world, Constants.ROLE.DIRECTION) == nil then
		role = Constants.ROLE.DIRECTION
	end

	local player = {
		userId = userId,
		name = name,
		role = role,
		joinedAt = world.time,
		lastAction = -math.huge,
		connected = true,
	}
	world.players[userId] = player
	return Result.ok("Joueur enregistré.", player)
end

-- Un joueur choisit un poste libre. La direction ne se prend que si elle est
-- vacante ; les autres postes sont uniques.
function PermissionService.claim(world: any, userId: number, role: string): any
	local player = world.players[userId]
	if not player then
		return Result.err("Joueur inconnu.")
	end
	if not Permissions.exists(role) then
		return Result.err("Poste inconnu.")
	end
	if role ~= Constants.ROLE.OBSERVATEUR then
		local holder = roleHolder(world, role, userId)
		if holder then
			return Result.err(string.format("Le poste « %s » est déjà tenu par %s.", Permissions.label(role), holder.name))
		end
	end
	player.role = role
	return Result.ok(string.format("Poste : %s.", Permissions.label(role)), player)
end

-- La direction attribue un poste à un autre joueur.
function PermissionService.assignRole(world: any, actorId: number, targetId: number, role: string): any
	local check = PermissionService.require(world, actorId, Constants.ACTION.ROLES)
	if not check.ok then
		return check
	end
	if not Permissions.exists(role) then
		return Result.err("Poste inconnu.")
	end
	if role == Constants.ROLE.DIRECTION then
		return Result.err("La direction ne se transfère pas : elle revient au premier connecté.")
	end
	local target = world.players[targetId]
	if not target then
		return Result.err("Joueur cible inconnu.")
	end
	local holder = roleHolder(world, role, targetId)
	if holder then
		return Result.err(string.format("Le poste « %s » est déjà tenu par %s.", Permissions.label(role), holder.name))
	end
	target.role = role
	return Result.ok(string.format("%s reçoit le poste « %s ».", target.name, Permissions.label(role)), target)
end

-- Contrôle brut : le rôle possède-t-il l'action ?
function PermissionService.can(world: any, userId: number, action: string): boolean
	local role = PermissionService.roleOf(world, userId)
	return Permissions.can(role, action)
end

-- Contrôle métier : action + périmètre du service du véhicule.
function PermissionService.canVehicle(world: any, userId: number, action: string, vehicle: any): boolean
	if not PermissionService.can(world, userId, action) then
		return false
	end
	local typeDef = world.catalogs.vehicles.get(vehicle.typeId)
	if not typeDef then
		return false
	end
	local role = PermissionService.roleOf(world, userId)
	return Permissions.canService(role, typeDef.service)
end

-- Renvoie un Result explicite pour l'interface.
function PermissionService.require(world: any, userId: number, action: string): any
	local player = world.players[userId]
	if not player then
		return Result.err("Joueur inconnu.")
	end
	if not PermissionService.can(world, userId, action) then
		return Result.err("Action non autorisée pour votre poste.")
	end
	return Result.ok()
end

function PermissionService.requireVehicle(world: any, userId: number, action: string, vehicle: any): any
	local check = PermissionService.require(world, userId, action)
	if not check.ok then
		return check
	end
	if not PermissionService.canVehicle(world, userId, action, vehicle) then
		return Result.err("Ce véhicule n'est pas dans votre périmètre.")
	end
	return Result.ok()
end

function PermissionService.rolesSummary(world: any): { any }
	local list = {}
	for _, player in pairs(world.players) do
		table.insert(list, {
			userId = player.userId,
			name = player.name,
			role = player.role,
			roleLabel = Permissions.label(player.role),
		})
	end
	table.sort(list, function(a, b)
		return a.userId < b.userId
	end)
	return list
end

return PermissionService
