--!strict
--[[
	EngagementHints — explique, côté client, pourquoi un engagement est bloqué.

	Les boutons sont désactivés quand l'action est manifestement impossible ;
	sans texte, le joueur ne sait pas ce qui manque. Ce module produit une
	phrase courte et stable, réutilisée par les trois endroits qui engagent un
	engin (barre inférieure, panneau Interventions, panneau Véhicules).

	Ce n'est qu'une aide à la lecture : la décision finale reste celle du
	serveur, qui revérifie tout.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Catalogs = Shared:WaitForChild("Catalogs")
local Vehicles = require(Catalogs:WaitForChild("Vehicles"))

local EngagementHints = {}

local function statusLabel(status: string?): string
	return Constants.STATUS_LABEL[status or ""] or (status or "?")
end

--[[
	Raison qui empêche l'engagement, ou `nil` si tout est réuni.

	`canDispatch` et `inScope` viennent du contrôleur (permissions affichées) ;
	`closed` indique une intervention terminée ou échouée.
]]
function EngagementHints.dispatchBlocker(
	vehicle: any,
	incident: any,
	canDispatch: boolean?,
	inScope: boolean?,
	closed: boolean?
): string?
	if not vehicle and not incident then
		return "Sélectionnez un engin et une intervention."
	end
	if not incident then
		return "Sélectionnez une intervention."
	end
	if closed then
		return "Intervention clôturée : aucun engagement possible."
	end
	if not vehicle then
		return "Sélectionnez un engin."
	end
	if inScope == false then
		return "Hors périmètre de votre poste."
	end
	if canDispatch == false then
		return "Votre poste ne peut pas engager."
	end
	if vehicle.status ~= Constants.VEHICLE_STATUS.AVAILABLE then
		return string.format("Engin indisponible (%s).", statusLabel(vehicle.status))
	end
	if (vehicle.crewCount or 0) < (vehicle.crewRequired or 0) then
		return string.format(
			"Équipage incomplet (%d/%d) : armez l'engin.",
			vehicle.crewCount or 0,
			vehicle.crewRequired or 0
		)
	end
	return nil
end

-- Capacités de l'engin inférieures à ce que l'intervention demande, par
-- exemple un VPC (police) envoyé sur un accident nécessitant secours.
function EngagementHints.missingCapabilities(vehicle: any, incident: any): string?
	if not vehicle or not incident then
		return nil
	end
	local typeDef = Vehicles.get(vehicle.typeId)
	local requires = incident.requires
	if not typeDef or not requires then
		return nil
	end

	local entries = {}
	for capability, required in pairs(requires) do
		local provided = (typeDef.capabilities or {})[capability] or 0
		if provided < required then
			table.insert(entries, {
				key = capability,
				text = string.format(
					"%s %d",
					Constants.CAPABILITY_LABEL[capability] or capability,
					required
				),
			})
		end
	end
	if #entries == 0 then
		return nil
	end

	table.sort(entries, function(a, b)
		return a.key < b.key
	end)
	local parts = {}
	for _, entry in ipairs(entries) do
		table.insert(parts, entry.text)
	end
	return table.concat(parts, " · ")
end

--[[
	Phrase affichée sous les commandes.

	1. bloqueur réel s'il existe ;
	2. sinon, avertissement quand l'engin ne couvre pas les moyens requis
	   (l'engagement reste possible : d'autres moyens peuvent compléter).
]]
function EngagementHints.engageHint(
	vehicle: any,
	incident: any,
	canDispatch: boolean?,
	inScope: boolean?,
	closed: boolean?
): string?
	local blocker = EngagementHints.dispatchBlocker(vehicle, incident, canDispatch, inScope, closed)
	if blocker then
		return blocker
	end
	local missing = EngagementHints.missingCapabilities(vehicle, incident)
	if missing then
		return "⚠ Capacités manquantes sur cet engin : " .. missing .. "."
	end
	return nil
end

return EngagementHints
