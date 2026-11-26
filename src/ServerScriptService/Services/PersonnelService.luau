--!strict
--[[
	PersonnelService — effectifs, affectations et fatigue (spec §7).

	Un membre n'a qu'une affectation. Les règles d'équipage vivent dans
	`Shared/Utilities/Crew` ; ce service ajoute les permissions, le journal et
	la progression de fatigue.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Utilities = Shared:WaitForChild("Utilities")
local Constants = require(Shared:WaitForChild("Constants"))
local Result = require(Utilities:WaitForChild("Result"))
local Crew = require(Utilities:WaitForChild("Crew"))
local Operations = require(Utilities:WaitForChild("Operations"))

local ServerScript = game:GetService("ServerScriptService"):WaitForChild("ERS")
local Services = ServerScript:WaitForChild("Services")
local PermissionService = require(Services:WaitForChild("PermissionService"))

local BudgetService = require(Services:WaitForChild("BudgetService"))
local PurchaseService = require(Services:WaitForChild("PurchaseService"))
local Recruitment = require(Shared:WaitForChild("Catalogs"):WaitForChild("Recruitment"))

local PersonnelService = {}

local VALID_SERVICES = {
	fire = true,
	medical = true,
	police = true,
	technical = true,
	logistics = true,
	command = true,
}

-- Création interne (monde initial, recrutement futur). Aucune permission :
-- l'appelant décide du contexte.
function PersonnelService.create(world: any, data: any): any
	if type(data.name) ~= "string" or #data.name < 2 then
		return Result.err("Nom invalide.")
	end
	if not VALID_SERVICES[data.service] then
		return Result.err("Service invalide.")
	end

	local qualifications = {}
	for qualificationId in pairs(data.qualifications or {}) do
		if not world.catalogs.qualifications.exists(qualificationId) then
			return Result.err("Qualification inconnue : " .. tostring(qualificationId))
		end
		qualifications[qualificationId] = true
	end

	if next(qualifications) == nil then
		return Result.err("Un membre doit posséder au moins une qualification.")
	end

	local person = {
		id = world.nextPersonnelId,
		name = data.name,
		grade = data.grade or "Sapeur",
		service = data.service,
		qualifications = qualifications,
		experience = data.experience or 0,
		level = 0,
		hireCost = data.hireCost or 1200,
		fatigue = data.fatigue or 0,
		health = data.health or 100,
		status = Constants.VEHICLE_STATUS.AVAILABLE,
		vehicleId = nil,
	}
	world.nextPersonnelId += 1
	world.personnel[person.id] = person
	return Result.ok(person.name .. " intègre le service.", person)
end

-- Recrute un membre qualifié sur le budget commun.
function PersonnelService.recruit(world: any, actorId: number, profileId: string): any
	local check = PurchaseService.check(world, actorId)
	if not check.ok then return check end
	local profile = Recruitment.byId[profileId]
	if not profile then return Result.err("Profil inconnu.") end
	local count = 0
	for _ in pairs(world.personnel) do count += 1 end
	if count >= Recruitment.maxPersonnel then return Result.err("Effectif complet.") end
	local price = PurchaseService.price(world, profile.cost)
	if not BudgetService.canAfford(world, price) then return Result.err("Budget insuffisant.") end
	local data = table.clone(profile)
	data.name = string.format("%s %d", profile.grade, world.nextPersonnelId)
	data.hireCost = price
	local created = PersonnelService.create(world, data)
	if not created.ok then return created end
	BudgetService.spend(world, price, "Recrutement de " .. data.name)
	PurchaseService.advance(world, actorId, true)
	Operations.log(world, Constants.LOG.MONEY, created.message)
	return created
end

local function availableForTransfer(world: any, actorId: number, personId: number): any
	local check = PurchaseService.check(world, actorId)
	if not check.ok then return check end
	local person = world.personnel[personId]
	if not person then return Result.err("Membre inconnu.") end
	if person.vehicleId then return Result.err("Retirez d’abord ce membre de son équipage.") end
	return Result.ok("", person)
end

-- Transfère un membre libre à un autre centre et crédite son indemnité.
function PersonnelService.transfer(world: any, actorId: number, personId: number): any
	local available = availableForTransfer(world, actorId, personId)
	if not available.ok then return available end
	local person = available.data
	local result = BudgetService.earn(world, Recruitment.transferValue(person), "Transfert de " .. person.name)
	world.personnel[personId] = nil
	PurchaseService.advance(world, actorId, false)
	Operations.log(world, Constants.LOG.MONEY, result.message)
	return result
end

-- Forme un membre libre ; chaque niveau réduit sa fatigue en intervention de 10 %.
function PersonnelService.train(world: any, actorId: number, personId: number): any
	local available = availableForTransfer(world, actorId, personId)
	if not available.ok then return available end
	local person = available.data
	local level = person.level or 0
	if level >= Recruitment.maxLevel then return Result.err("Formation maximale atteinte.") end
	local payment = BudgetService.spend(world, Recruitment.trainingCost(level), "Formation de " .. person.name)
	if not payment.ok then return payment end
	person.level = level + 1
	PurchaseService.advance(world, actorId, false)
	local message = string.format("%s passe au niveau %d.", person.name, person.level)
	Operations.log(world, Constants.LOG.MONEY, message)
	return Result.ok(message)
end

-- Affecte un membre à un équipage disponible.
function PersonnelService.assign(world: any, actorId: number, personId: number, vehicleId: number): any
	local person = world.personnel[personId]
	if not person then
		return Result.err("Membre inconnu.")
	end
	local vehicle = world.vehicles[vehicleId]
	if not vehicle then
		return Result.err("Véhicule inconnu.")
	end

	local check = PermissionService.requireVehicle(world, actorId, Constants.ACTION.ASSIGN_PERSONNEL, vehicle)
	if not check.ok then
		return check
	end

	local allowed = Crew.canAssign(world, person, vehicle)
	if not allowed.ok then
		return allowed
	end

	Crew.assign(world, person, vehicle)
	Operations.log(world, Constants.LOG.INFO, string.format("%s rejoint %s.", person.name, vehicle.callsign))
	return Result.ok(string.format("%s rejoint %s.", person.name, vehicle.callsign), person)
end

function PersonnelService.unassign(world: any, actorId: number, personId: number): any
	local person = world.personnel[personId]
	if not person then
		return Result.err("Membre inconnu.")
	end
	if person.vehicleId == nil then
		return Result.err(person.name .. " n'est affecté à aucun véhicule.")
	end
	local vehicle = world.vehicles[person.vehicleId]
	if not vehicle then
		return Result.err("Véhicule d'affectation introuvable.")
	end
	if vehicle.status ~= Constants.VEHICLE_STATUS.AVAILABLE then
		return Result.err("Impossible de modifier l'équipage en dehors du poste.")
	end

	local check = PermissionService.requireVehicle(world, actorId, Constants.ACTION.ASSIGN_PERSONNEL, vehicle)
	if not check.ok then
		return check
	end

	Crew.unassign(world, person)
	Operations.log(world, Constants.LOG.INFO, string.format("%s quitte %s.", person.name, vehicle.callsign))
	return Result.ok(string.format("%s quitte %s.", person.name, vehicle.callsign), person)
end

-- Compose automatiquement un équipage avec les disponibilités du service.
function PersonnelService.autoCrew(world: any, actorId: number, vehicleId: number): any
	local vehicle = world.vehicles[vehicleId]
	if not vehicle then
		return Result.err("Véhicule inconnu.")
	end
	local check = PermissionService.requireVehicle(world, actorId, Constants.ACTION.ASSIGN_PERSONNEL, vehicle)
	if not check.ok then
		return check
	end
	if vehicle.status ~= Constants.VEHICLE_STATUS.AVAILABLE then
		return Result.err("Le véhicule n'est pas au poste.")
	end

	local typeDef = world.catalogs.vehicles.get(vehicle.typeId)
	if not typeDef then
		return Result.err("Type de véhicule inconnu.")
	end

	local readiness = Crew.readiness(world, vehicle)
	if readiness.ok and #vehicle.crew >= typeDef.crewRequired then
		return Result.err("L'équipage est déjà complet.")
	end

	local candidates = Crew.autoSelect(world, vehicle)
	local assigned = 0
	for _, personId in ipairs(candidates) do
		local person = world.personnel[personId]
		if person then
			local allowed = Crew.canAssign(world, person, vehicle)
			if allowed.ok then
				Crew.assign(world, person, vehicle)
				assigned += 1
			end
		end
	end

	if assigned == 0 then
		return Result.err("Aucun membre disponible pour ce véhicule.")
	end

	local after = Crew.readiness(world, vehicle)
	local message = string.format("%d membre(s) affecté(s) à %s.", assigned, vehicle.callsign)
	if not after.ok then
		message ..= " " .. after.message
	end
	Operations.log(world, Constants.LOG.INFO, message)
	return Result.ok(message, { assigned = assigned, ready = after.ok, readiness = after })
end

-- Fatigue et récupération.
function PersonnelService.stepFatigue(world: any, dt: number): ()
	for _, person in pairs(world.personnel) do
		local vehicle = person.vehicleId and world.vehicles[person.vehicleId] or nil
		local onOperation = vehicle
			and (vehicle.status == Constants.VEHICLE_STATUS.DISPATCHED or vehicle.status == Constants.VEHICLE_STATUS.ON_SCENE
				or vehicle.status == Constants.VEHICLE_STATUS.TRANSPORTING or vehicle.status == Constants.VEHICLE_STATUS.HANDOVER)

		if onOperation then
			person.fatigue += world.config.FATIGUE_PER_SECOND * dt * (1 - 0.1 * (person.level or 0))
		elseif vehicle then
			person.fatigue += world.config.FATIGUE_ASSIGNED * dt
		else
			person.fatigue -= world.config.FATIGUE_RECOVERY * dt
		end
		person.fatigue = math.clamp(person.fatigue, 0, world.config.MAX_FATIGUE)
	end
end

function PersonnelService.roster(world: any): { any }
	local list = {}
	for _, person in pairs(world.personnel) do
		table.insert(list, person)
	end
	table.sort(list, function(a, b)
		if a.service ~= b.service then
			return a.service < b.service
		end
		return a.id < b.id
	end)
	return list
end

function PersonnelService.available(world: any): { any }
	local list = {}
	for _, person in ipairs(PersonnelService.roster(world)) do
		if person.vehicleId == nil and person.fatigue < world.config.REST_FATIGUE then
			table.insert(list, person)
		end
	end
	return list
end

function PersonnelService.qualificationLabels(world: any, person: any): { string }
	local labels = {}
	for qualificationId in pairs(person.qualifications) do
		table.insert(labels, world.catalogs.qualifications.label(qualificationId))
	end
	table.sort(labels)
	return labels
end

return PersonnelService
