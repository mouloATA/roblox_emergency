--!strict
--[[
	Crew — règles d'équipage et de moyens.

	Ce module ne modifie que les tables `world` ; il ne dépend d'aucun service.
	Les qualifications requises par un type de véhicule sont interprétées comme
	« au moins un membre possède cette qualification ». Le conducteur est
	obligatoire si `driverRequired` est vrai.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Utilities = Shared:WaitForChild("Utilities")
local Result = require(Utilities:WaitForChild("Result"))
local Constants = require(Shared:WaitForChild("Constants"))

local Crew = {}

local function typeDefOf(world: any, vehicle: any): any
	return world.catalogs.vehicles.get(vehicle.typeId)
end

-- Un membre peut-il monter dans ce type de véhicule ?
function Crew.serviceCompatible(person: any, typeDef: any): boolean
	if person.service == typeDef.service then
		return true
	end
	if person.qualifications.COS then
		return true
	end
	if typeDef.service == Constants.SERVICE.COMMAND then
		return person.qualifications.CHEF_GROUPE == true or person.qualifications.CHEF_AGRES == true
	end
	return false
end

-- Vérifie qu'une affectation est autorisée, sans la réaliser.
function Crew.canAssign(world: any, person: any, vehicle: any): any
	local typeDef = typeDefOf(world, vehicle)
	if not typeDef then
		return Result.err("Type de véhicule inconnu.")
	end
	if person.status ~= Constants.VEHICLE_STATUS.AVAILABLE or person.vehicleId ~= nil then
		return Result.err(person.name .. " est déjà affecté.")
	end
	if person.fatigue >= world.config.REST_FATIGUE then
		return Result.err(person.name .. " est trop fatigué pour partir.")
	end
	if person.health <= world.config.MIN_HEALTH then
		return Result.err(person.name .. " est indisponible (santé).")
	end
	if vehicle.status ~= Constants.VEHICLE_STATUS.AVAILABLE then
		return Result.err("Le véhicule n'est pas au poste.")
	end
	if #vehicle.crew >= typeDef.seats then
		return Result.err("Le véhicule est complet.")
	end
	if not Crew.serviceCompatible(person, typeDef) then
		return Result.err(person.name .. " n'est pas qualifié pour ce service.")
	end
	return Result.ok()
end

-- Affecte réellement un membre (après validation).
function Crew.assign(world: any, person: any, vehicle: any): ()
	person.vehicleId = vehicle.id
	person.status = Constants.VEHICLE_STATUS.AVAILABLE
	table.insert(vehicle.crew, person.id)
end

-- Retire un membre de son véhicule.
function Crew.unassign(world: any, person: any): ()
	if person.vehicleId == nil then
		return
	end
	local vehicle = world.vehicles[person.vehicleId]
	if vehicle then
		for index, personId in ipairs(vehicle.crew) do
			if personId == person.id then
				table.remove(vehicle.crew, index)
				break
			end
		end
	end
	person.vehicleId = nil
	person.status = Constants.VEHICLE_STATUS.AVAILABLE
end

-- Membres d'un véhicule, dans l'ordre d'affectation.
function Crew.members(world: any, vehicle: any): { any }
	local members = {}
	for _, personId in ipairs(vehicle.crew) do
		local person = world.personnel[personId]
		if person then
			table.insert(members, person)
		end
	end
	return members
end

-- Qualifications manquantes pour armer complètement le véhicule.
function Crew.missingQualifications(world: any, vehicle: any): { string }
	local typeDef = typeDefOf(world, vehicle)
	if not typeDef then
		return {}
	end
	local members = Crew.members(world, vehicle)
	local missing = {}
	for _, qualificationId in ipairs(typeDef.qualifications) do
		local found = false
		for _, person in ipairs(members) do
			if person.qualifications[qualificationId] then
				found = true
				break
			end
		end
		if not found then
			table.insert(missing, qualificationId)
		end
	end
	return missing
end

-- Le véhicule peut-il partir ? Retourne un Result + les détails.
function Crew.readiness(world: any, vehicle: any): any
	local typeDef = typeDefOf(world, vehicle)
	if not typeDef then
		return Result.err("Type de véhicule inconnu.")
	end
	if #vehicle.crew < typeDef.crewRequired then
		return Result.err(
			string.format("Équipage incomplet (%d/%d).", #vehicle.crew, typeDef.crewRequired),
			{ missingQualifications = {}, seatsShort = typeDef.crewRequired - #vehicle.crew }
		)
	end

	local missing = Crew.missingQualifications(world, vehicle)
	if #missing > 0 then
		local labels = {}
		for _, qualificationId in ipairs(missing) do
			table.insert(labels, world.catalogs.qualifications.label(qualificationId))
		end
		return Result.err("Qualifications manquantes : " .. table.concat(labels, ", ") .. ".", {
			missingQualifications = missing,
			seatsShort = 0,
		})
	end

	return Result.ok("Équipage complet.")
end

-- Puissance d'un véhicule sur une intervention (base + équipements installés).
function Crew.power(world: any, vehicle: any): { [string]: number }
	local typeDef = typeDefOf(world, vehicle)
	local power = {}
	if not typeDef then
		return power
	end
	for capability, value in pairs(typeDef.capabilities) do
		power[capability] = (power[capability] or 0) + value
	end
	for equipmentId, quantity in pairs(vehicle.equipment) do
		if quantity > 0 then
			local equipment = world.catalogs.equipment.get(equipmentId)
			if equipment then
				for capability, value in pairs(equipment.bonus) do
					power[capability] = (power[capability] or 0) + value
				end
			end
		end
	end
	return power
end

-- Puissance cumulée d'une liste de véhicules.
function Crew.totalPower(world: any, vehicles: { any }): { [string]: number }
	local total = {}
	for _, vehicle in ipairs(vehicles) do
		for capability, value in pairs(Crew.power(world, vehicle)) do
			total[capability] = (total[capability] or 0) + value
		end
	end
	return total
end

-- Tous les équipements requis par l'intervention sont-ils présents ?
function Crew.hasRequiredEquipment(world: any, incident: any, vehicles: { any }): (boolean, { string })
	local typeDef = world.catalogs.incidents.get(incident.typeId)
	if not typeDef then
		return false, {}
	end
	local missing = {}
	for _, equipmentId in ipairs(typeDef.equipment) do
		local found = false
		for _, vehicle in ipairs(vehicles) do
			if (vehicle.equipment[equipmentId] or 0) > 0 then
				found = true
				break
			end
		end
		if not found then
			table.insert(missing, equipmentId)
		end
	end
	return #missing == 0, missing
end

-- Les qualifications exigées par l'intervention sont-elles présentes ?
function Crew.hasRequiredQualifications(world: any, incident: any, vehicles: { any }): (boolean, { string })
	local typeDef = world.catalogs.incidents.get(incident.typeId)
	if not typeDef then
		return false, {}
	end
	local missing = {}
	for _, qualificationId in ipairs(typeDef.qualifications) do
		local found = false
		for _, vehicle in ipairs(vehicles) do
			for _, person in ipairs(Crew.members(world, vehicle)) do
				if person.qualifications[qualificationId] then
					found = true
					break
				end
			end
			if found then
				break
			end
		end
		if not found then
			table.insert(missing, qualificationId)
		end
	end
	return #missing == 0, missing
end

-- Sélection automatique d'un équipage complet et qualifié.
-- Retourne les identifiants choisis ; l'appelant les affecte.
function Crew.autoSelect(world: any, vehicle: any, preferredQualifications: { string }?): { number }
	local typeDef = typeDefOf(world, vehicle)
	if not typeDef then
		return {}
	end

	local target = math.min(typeDef.crewRequired, typeDef.seats)
	local candidates = {}
	for _, person in pairs(world.personnel) do
		if
			person.status == Constants.VEHICLE_STATUS.AVAILABLE
			and person.vehicleId == nil
			and person.fatigue < world.config.REST_FATIGUE
			and person.health > world.config.MIN_HEALTH
			and Crew.serviceCompatible(person, typeDef)
		then
			table.insert(candidates, person)
		end
	end
	table.sort(candidates, function(a, b)
		-- Priorité au service du véhicule : un chef COS polyvalent ne doit pas
		-- vider la caserne au détriment des spécialistes du service concerné.
		local aOwn = a.service == typeDef.service
		local bOwn = b.service == typeDef.service
		if aOwn ~= bOwn then
			return aOwn
		end
		if a.experience ~= b.experience then
			return a.experience > b.experience
		end
		if a.fatigue ~= b.fatigue then
			return a.fatigue < b.fatigue
		end
		return a.id < b.id
	end)

	local chosen = {}
	local used = {}
	local function take(predicate: ((any) -> boolean)?): any?
		for _, person in ipairs(candidates) do
			if not used[person.id] and (predicate == nil or predicate(person)) then
				used[person.id] = true
				table.insert(chosen, person.id)
				return person
			end
		end
		return nil
	end

	for _, qualificationId in ipairs(typeDef.qualifications) do
		take(function(person)
			return person.qualifications[qualificationId] == true
		end)
	end

	if preferredQualifications then
		for _, qualificationId in ipairs(preferredQualifications) do
			take(function(person)
				return person.qualifications[qualificationId] == true
			end)
		end
	end

	while #chosen < target do
		if take(nil) == nil then
			break
		end
	end

	return chosen
end

-- Étiquette lisible d'une qualification.
function Crew.qualificationLabel(world: any, qualificationId: string): string
	return world.catalogs.qualifications.label(qualificationId)
end

return Crew
