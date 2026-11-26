--!strict
--[[
	Permissions — matrice des rôles multijoueur (spec §12.3).

	Un rôle donne un ensemble d'actions et un périmètre de services. La
	direction voit tout ; un rôle métier ne peut engager que les véhicules de
	son service. Les contrôles sont faits côté serveur, jamais côté client.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local A = Constants.ACTION

local Permissions = {}

Permissions.roles = {
	[Constants.ROLE.DIRECTION] = {
		label = "Direction",
		description = "Gestion globale : budget, flotte, personnel, rôles et interventions.",
		actions = "all",
		services = "all",
	},
	[Constants.ROLE.COMMANDEMENT] = {
		label = "Commandement",
		description = "Engage tous les services, coordonne les secteurs et partage les tours d’achat.",
		actions = {
			[A.VIEW] = true,
			[A.DISPATCH] = true,
			[A.RECALL] = true,
			[A.ASSIGN_PERSONNEL] = true,
			[A.EQUIPMENT] = true,
			[A.REPAIR] = true,
			[A.COMMAND] = true,
			[A.BUY_VEHICLE] = true,
			[A.SET_TIME] = true,
			[A.START_MISSION] = true,
		},
		services = "all",
	},
	[Constants.ROLE.INCENDIE] = {
		label = "Incendie",
		description = "Engage et équipe les véhicules incendie.",
		actions = {
			[A.VIEW] = true,
			[A.DISPATCH] = true,
			[A.RECALL] = true,
			[A.ASSIGN_PERSONNEL] = true,
			[A.EQUIPMENT] = true,
		},
		services = { fire = true },
	},
	[Constants.ROLE.SECOURS] = {
		label = "Secours",
		description = "Engage les véhicules de secours à personne.",
		actions = {
			[A.VIEW] = true,
			[A.DISPATCH] = true,
			[A.RECALL] = true,
			[A.ASSIGN_PERSONNEL] = true,
			[A.EQUIPMENT] = true,
		},
		services = { medical = true },
	},
	[Constants.ROLE.POLICE] = {
		label = "Police",
		description = "Sécurise, régule la circulation et engage les véhicules de police.",
		actions = {
			[A.VIEW] = true,
			[A.DISPATCH] = true,
			[A.RECALL] = true,
			[A.ASSIGN_PERSONNEL] = true,
			[A.EQUIPMENT] = true,
		},
		services = { police = true },
	},
	[Constants.ROLE.LOGISTIQUE] = {
		label = "Logistique",
		description = "Équipe et répare les véhicules techniques et de soutien.",
		actions = {
			[A.VIEW] = true,
			[A.DISPATCH] = true,
			[A.RECALL] = true,
			[A.ASSIGN_PERSONNEL] = true,
			[A.EQUIPMENT] = true,
			[A.REPAIR] = true,
		},
		services = { technical = true, logistics = true, command = true },
	},
	[Constants.ROLE.OBSERVATEUR] = {
		label = "Observateur",
		description = "Lecture seule : suit l'opération sans modifier l'état.",
		actions = {
			[A.VIEW] = true,
		},
		services = {},
	},
}

function Permissions.exists(roleId: string): boolean
	return Permissions.roles[roleId] ~= nil
end

function Permissions.label(roleId: string): string
	local role = Permissions.roles[roleId]
	return role and role.label or roleId
end

function Permissions.can(roleId: string, action: string): boolean
	local role = Permissions.roles[roleId]
	if not role then
		return false
	end
	if role.actions == "all" then
		return true
	end
	return role.actions[action] == true
end

-- Périmètre de services ; `nil` signifie « tous ».
function Permissions.serviceScope(roleId: string): { [string]: boolean }?
	local role = Permissions.roles[roleId]
	if not role then
		return {}
	end
	if role.services == "all" then
		return nil
	end
	return role.services
end

function Permissions.canService(roleId: string, service: string): boolean
	local scope = Permissions.serviceScope(roleId)
	if scope == nil then
		return true
	end
	return scope[service] == true
end

return Permissions
