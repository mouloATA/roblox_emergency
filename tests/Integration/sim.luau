--!nonstrict
--[[
	Tests d'intégration — chaîne serveur complète, sans Studio :
	monde → équipages → alerte → engagement → arrivée → progression d'étapes →
	résolution → budget → snapshot → sauvegarde → rechargement.

	La simulation est avancée manuellement (dt fixe) pour être déterministe :
	aucune attente réelle, aucun aléa non maîtrisé.
]]

local passed = 0
local failed = 0

local function check(name, condition, detail)
	if condition then
		passed += 1
	else
		failed += 1
		print(string.format("  ECHEC  %s%s", name, detail and (" — " .. tostring(detail)) or ""))
	end
end

local function suite(title)
	print("")
	print("  " .. title)
end

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local Utilities = Shared:WaitForChild("Utilities")
local Catalogs = Shared:WaitForChild("Catalogs")
local Rng = require(Utilities:WaitForChild("Rng"))

local Vehicles = require(Catalogs:WaitForChild("Vehicles"))
local Qualifications = require(Catalogs:WaitForChild("Qualifications"))
local Equipment = require(Catalogs:WaitForChild("Equipment"))
local Incidents = require(Catalogs:WaitForChild("Incidents"))
local Permissions = require(Catalogs:WaitForChild("Permissions"))

local Services = game:GetService("ServerScriptService"):WaitForChild("ERS"):WaitForChild("Services")
local WorldService = require(Services:WaitForChild("WorldService"))
local PersonnelService = require(Services:WaitForChild("PersonnelService"))
local DispatchService = require(Services:WaitForChild("DispatchService"))
local IncidentService = require(Services:WaitForChild("IncidentService"))
local VehicleService = require(Services:WaitForChild("VehicleService"))
local CommandService = require(Services:WaitForChild("CommandService"))
local SimulationService = require(Services:WaitForChild("SimulationService"))
local SnapshotService = require(Services:WaitForChild("SnapshotService"))
local SaveService = require(Services:WaitForChild("SaveService"))
local PermissionService = require(Services:WaitForChild("PermissionService"))
local LightingService = require(Services:WaitForChild("LightingService"))
local NetworkService = require(Services:WaitForChild("NetworkService"))

local catalogs = {
	vehicles = Vehicles,
	qualifications = Qualifications,
	equipment = Equipment,
	incidents = Incidents,
	permissions = Permissions,
}

local function newWorld(seed)
	return WorldService.create(Config, catalogs, { seed = seed or 20260101 })
end

local function vehicleOfType(world, typeId)
	local ids = {}
	for id in pairs(world.vehicles) do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		if world.vehicles[id].typeId == typeId then
			return world.vehicles[id]
		end
	end
	return nil
end

local function crewAll(world, actorId)
	local crewed = {}
	for _, typeId in ipairs(Config.START_VEHICLES) do
		local vehicle = vehicleOfType(world, typeId)
		if vehicle then
			local result = PersonnelService.autoCrew(world, actorId, vehicle.id)
			crewed[typeId] = result
		end
	end
	return crewed
end

-- ─────────────────────────────────────────────────────────────
suite("Monde initial")
-- ─────────────────────────────────────────────────────────────
local world = newWorld(7)
local seeded = PermissionService.seed(world, 1, "DirectionTest")

check("premier joueur reçoit la direction", seeded.ok and world.players[1].role == Constants.ROLE.DIRECTION)
check("budget initial", world.budget == Config.START_BUDGET, world.budget)
check("flotte de départ", SaveService.count(world.vehicles) == 3, SaveService.count(world.vehicles))
check("effectif de départ", SaveService.count(world.personnel) == Config.START_PERSONNEL, SaveService.count(world.personnel))
check("journal initial non vide", #world.log >= 1)
check("aucune intervention au départ", SaveService.count(world.incidents) == 0)
check("compteur d'alertes à zéro", world.spawnedIncidents == 0)

local fpt = vehicleOfType(world, "FPT")
local vsav = vehicleOfType(world, "VSAV")
local vpc = vehicleOfType(world, "VPC")
check("FPT présent", fpt ~= nil)
check("VSAV présent", vsav ~= nil)
check("VPC présent", vpc ~= nil)
check("indicatifs uniques", fpt.callsign == "FPT 1" and vsav.callsign == "VSAV 1" and vpc.callsign == "VPC 1")
check("matériel par défaut installé", (fpt.equipment.ARI or 0) == 4 and (vsav.equipment.DEFIB or 0) == 1)
check("stock décrémenté", world.equipmentStock.ARI == 2, world.equipmentStock.ARI)
check("stock épuisé non négatif", (world.equipmentStock.PC_MOBILE or 0) == 0, world.equipmentStock.PC_MOBILE)
check("équipages vides au départ", #fpt.crew == 0)

-- ─────────────────────────────────────────────────────────────
suite("Composition des équipages")
-- ─────────────────────────────────────────────────────────────
local crewed = crewAll(world, 1)
check("FPT armé", crewed.FPT.ok == true, crewed.FPT.message)
check("VSAV armé", crewed.VSAV.ok == true, crewed.VSAV.message)
check("VPC armé", crewed.VPC.ok == true, crewed.VPC.message)
check("FPT : 4 membres", #fpt.crew == 4, #fpt.crew)
check("VSAV : 3 membres", #vsav.crew == 3, #vsav.crew)
check("VPC : 1 membre", #vpc.crew == 1, #vpc.crew)
check("personnel affecté comptabilisé", SaveService.count(world.personnel) == Config.START_PERSONNEL)

local already = PersonnelService.autoCrew(world, 1, fpt.id)
check("rééquipage refusé si complet", already.ok == false)

-- ─────────────────────────────────────────────────────────────
suite("Alerte, engagement et résolution")
-- ─────────────────────────────────────────────────────────────
world.alarmCountdown = 1e9 -- fige les alertes automatiques pendant le scénario

local spawned = IncidentService.spawn(world, "FEU_VEHICULE", { x = Config.HQ_X + 4, z = Config.HQ_Z + 4 })
check("alerte créée", spawned.ok == true and world.incidents["INC-001"] ~= nil)
local incident = world.incidents["INC-001"]
check("alerte en attente", incident.status == Constants.INCIDENT_STATUS.PENDING)
check("échéance fixée", incident.deadline == incident.createdAt + Incidents.get("FEU_VEHICULE").responseDeadline)

local beforeBudget = world.budget
local dispatched = DispatchService.dispatch(world, 1, fpt.id, incident.id)
check("engagement accepté", dispatched.ok == true, dispatched.message)
check("mobilisation facturée", world.budget == beforeBudget - Vehicles.get("FPT").mobilizationCost, world.budget)
check("véhicule en route", fpt.status == Constants.VEHICLE_STATUS.DISPATCHED)
check("intervention active", incident.status == Constants.INCIDENT_STATUS.ACTIVE)
check("véhicule inscrit sur l'intervention", incident.assigned[fpt.id] == true)

local doubleDispatch = DispatchService.dispatch(world, 1, fpt.id, incident.id)
check("double engagement refusé", doubleDispatch.ok == false)

for _ = 1, 40 do
	SimulationService.step(world, 1)
	if fpt.status == Constants.VEHICLE_STATUS.ON_SCENE then
		break
	end
end
check("véhicule sur place", fpt.status == Constants.VEHICLE_STATUS.ON_SCENE, fpt.status)
check("moyens sur place enregistrés", incident.onScene[fpt.id] == true)
check("intervention active pendant les étapes", incident.status == Constants.INCIDENT_STATUS.ACTIVE, incident.status)

for _ = 1, 60 do
	SimulationService.step(world, 1)
end
check("intervention terminée", incident.status == Constants.INCIDENT_STATUS.RESOLVED, incident.status)
check("résultat plein", incident.outcome == "success", incident.outcome)
check("récompense créditée", world.budget == beforeBudget - 120 + 350, world.budget)
check("victimes non applicables", incident.savedVictims == 0)
check("statistique de résolution", world.stats.resolved == 1, world.stats.resolved)
check("véhicule libéré", incident.assigned[fpt.id] == nil and incident.onScene[fpt.id] == nil)
check("véhicule rentre ou est rentré", fpt.status == Constants.VEHICLE_STATUS.RETURNING
	or fpt.status == Constants.VEHICLE_STATUS.AVAILABLE, fpt.status)
check("état mécanique usé", fpt.condition < 100 and fpt.condition >= 1, fpt.condition)

for _ = 1, 40 do
	SimulationService.step(world, 1)
end
check("retour au poste", fpt.status == Constants.VEHICLE_STATUS.AVAILABLE, fpt.status)
check("équipage conservé au retour", #fpt.crew == 4, #fpt.crew)

-- ─────────────────────────────────────────────────────────────
suite("Snapshot sérialisable")
-- ─────────────────────────────────────────────────────────────
local snapshot = SnapshotService.build(world)
check("snapshot sérialisable", SnapshotService.isSerializable(snapshot) == true)
check("snapshot : 3 véhicules", #snapshot.vehicles == 3, #snapshot.vehicles)
check("snapshot : horloge", type(snapshot.clock) == "string" and #snapshot.clock == 5)
check("snapshot : joueurs", #snapshot.players == 1 and snapshot.players[1].roleLabel == "Direction")
check("snapshot : intervention close", #snapshot.incidents == 1 and snapshot.incidents[1].status == "resolved")
check("snapshot : équipage nommé", #snapshot.vehicles[1].crew > 0 or #snapshot.vehicles[2].crew > 0 or #snapshot.vehicles[3].crew > 0)
check("snapshot : matériel lisible", #snapshot.vehicles[1].equipment >= 1)
check("snapshot : stock lisible", #snapshot.stock >= 1)
check("snapshot : journal borné", #snapshot.log <= Config.SNAPSHOT_LOG_LIMIT)
check("snapshot : pas de fonction", snapshot.vehicles[1].route == nil or type(snapshot.vehicles[1].route) == "table")

local dirty = SnapshotService.build(world)
dirty.vehicles[1].crew = function() end
check("détecte une fonction", SnapshotService.isSerializable(dirty) == false)

local cyclic = {}
cyclic.self = cyclic
check("détecte une référence circulaire", SnapshotService.isSerializable(cyclic) == false)

-- ─────────────────────────────────────────────────────────────
suite("Sauvegarde et rechargement")
-- ─────────────────────────────────────────────────────────────
local store = SaveService.createMemoryStore()
local offline = SaveService.dataStoreAdapter({
	GetAsync = function() error("indisponible") end,
	SetAsync = function() error("indisponible") end,
})
local unavailable = SaveService.load(world, offline)
check("erreur de lecture distincte d’une première garde", not unavailable.ok and unavailable.data == nil
	and SaveService.load(world, store).data.empty)
check("refus du DataStore signalé au joueur", not SaveService.save(world, offline).ok)
local saved = SaveService.save(world, store)
check("sauvegarde réussie", saved.ok == true, saved.message)

local reloaded = newWorld(99)
local loaded = SaveService.load(reloaded, store)
check("chargement réussi", loaded.ok == true, loaded.message)
check("budget restauré", reloaded.budget == world.budget, reloaded.budget)
check("flotte restaurée", SaveService.count(reloaded.vehicles) == 3, SaveService.count(reloaded.vehicles))
check("effectif restauré", SaveService.count(reloaded.personnel) == Config.START_PERSONNEL, SaveService.count(reloaded.personnel))
check("équipage restauré", #vehicleOfType(reloaded, "FPT").crew == 4, #vehicleOfType(reloaded, "FPT").crew)
check("matériel restauré", (vehicleOfType(reloaded, "FPT").equipment.ARI or 0) == 4)
check("stock restauré", (reloaded.equipmentStock.ARI or 0) == (world.equipmentStock.ARI or 0))
check("aucune intervention restaurée", SaveService.count(reloaded.incidents) == 0)
check("prochain identifiant véhicule", reloaded.nextVehicleId == 4, reloaded.nextVehicleId)

local emptyLoad = SaveService.load(newWorld(5), SaveService.createMemoryStore())
check("chargement vide signalé", emptyLoad.ok == false)

local badVersion = SaveService.deserialize(newWorld(5), { version = "0.0.0" })
check("version incompatible refusée", badVersion.ok == false)

local tolerantWorld = newWorld(5)
local invalid = SaveService.deserialize(tolerantWorld, {
	version = Config.VERSION,
	budget = 1234,
	vehicles = { { id = 1, typeId = "TYPE_SUPPRIME", callsign = "X" } },
	personnel = { { id = 1, name = "Fantôme", qualifications = { "QUALIFICATION_SUPPRIMEE" } } },
})
check("sauvegarde partiellement invalide acceptée", invalid.ok == true, invalid.message)
check("entrées inconnues comptées", type(invalid.data) == "table" and invalid.data.ignored >= 1)
check("aucun véhicule inconnu injecté", SaveService.count(tolerantWorld.vehicles) == 0)
check("aucun membre inconnu injecté", SaveService.count(tolerantWorld.personnel) == 0)
check("budget valide conservé", tolerantWorld.budget == 1234, tolerantWorld.budget)
check("monde toujours sérialisable", SnapshotService.isSerializable(SnapshotService.build(tolerantWorld)) == true)

-- ─────────────────────────────────────────────────────────────
suite("Atelier, achat et pénalité")
-- ─────────────────────────────────────────────────────────────
PermissionService.seed(reloaded, 1, "DirectionTest")
local reloadedVsav = vehicleOfType(reloaded, "VSAV")
reloadedVsav.condition = 50
local budgetBeforeRepair = reloaded.budget
local repair = VehicleService.repair(reloaded, 1, reloadedVsav.id)
check("réparation acceptée", repair.ok == true, repair.message)
check("réparation facturée", reloaded.budget == budgetBeforeRepair - 600, reloaded.budget)
check("véhicule à l'atelier", reloadedVsav.status == Constants.VEHICLE_STATUS.MAINTENANCE)
for _ = 1, 80 do
	VehicleService.stepRepair(reloaded, 1)
end
check("réparation terminée", reloadedVsav.condition == 100 and reloadedVsav.status == Constants.VEHICLE_STATUS.AVAILABLE)

local budgetBeforeBuy = reloaded.budget
local purchase = VehicleService.buy(reloaded, 1, "VSAV")
check("achat accepté", purchase.ok == true, purchase.message)
check("achat débité", reloaded.budget == budgetBeforeBuy - Vehicles.get("VSAV").cost, reloaded.budget)
check("nouvel indicatif", purchase.data.callsign == "VSAV 2", purchase.data.callsign)
check("flotte agrandie", SaveService.count(reloaded.vehicles) == 4)
check("type inconnu refusé", VehicleService.buy(reloaded, 1, "SOUCOUPE_VOLANTE").ok == false)

local penaltyWorld = newWorld(3)
PermissionService.seed(penaltyWorld, 1, "DirectionTest")
local doomed = IncidentService.spawn(penaltyWorld, "FEU_VEHICULE", { x = 60, z = 40 })
local doomedIncident = doomed.data
penaltyWorld.time = doomedIncident.deadline + 1
IncidentService.step(penaltyWorld, 0)
check("intervention échouée hors délai", doomedIncident.status == Constants.INCIDENT_STATUS.FAILED)
check("pénalité appliquée", penaltyWorld.budget == Config.START_BUDGET - Incidents.get("FEU_VEHICULE").penalty, penaltyWorld.budget)
check("statistique d'échec", penaltyWorld.stats.failed == 1)

-- ─────────────────────────────────────────────────────────────
suite("Terrain, propagation et évacuation sanitaire")
do
	local FireService = require(Services:WaitForChild("FireService"))
	local FieldService = require(Services:WaitForChild("FieldService"))
	local HospitalService = require(Services:WaitForChild("HospitalService"))
	local function fixture(typeId, vehicleType)
		local w = newWorld(81)
		w.alarmCountdown = 1e6
		PermissionService.seed(w, 1, "Direction")
		PermissionService.seed(w, 2, "Observateur")
		local v = vehicleOfType(w, vehicleType)
		PersonnelService.autoCrew(w, 1, v.id)
		local i = IncidentService.spawn(w, typeId, v.home).data
		DispatchService.dispatch(w, 1, v.id, i.id)
		return w, i, v
	end
	local w, i, v = fixture("FEU_FORET", "FPT")
	check("ordre d'un observateur refusé", not FieldService.giveOrder(w, 2, v.id, i.id, "hold").ok)
	check("ordre lié à la bonne alerte", not FieldService.giveOrder(w, 1, v.id, "INC-099", "hold").ok)
	check("équipage mis en réserve", FieldService.giveOrder(w, 1, v.id, i.id, "hold").ok)
	for _ = 1, 12 do SimulationService.step(w, 1) end
	check("le front gagne les végétaux voisins", FireService.count(i) > 1)
	check("la réserve ne réalise pas l'étape", i.stepIndex == 1 and i.stepProgress == 0 and i.waterUsed == 0)
	check("un ordre incompatible est refusé", not FieldService.giveOrder(w, 1, v.id, i.id, "extricate").ok)
	check("le FPT attaque le front avant la fin de la reconnaissance", FieldService.giveOrder(w, 1, v.id, i.id, "extinguish").ok)
	local before = v.water
	SimulationService.step(w, 1)
	check("le jet puise dans la cuve", i.waterUsed > 0 and math.abs(i.waterUsed - (before - v.water)) < 0.001)
	check("la simulation en pause fige le feu et l'eau", (function()
		w.timeScale = 0
		local used, heat = i.waterUsed, i.fireCells[1].heat
		SimulationService.step(w, 5)
		w.timeScale = 1
		return i.waterUsed == used and i.fireCells[1].heat == heat
	end)())
	for _ = 1, 115 do SimulationService.step(w, 1) end
	check("extinction du front et clôture", i.status == Constants.INCIDENT_STATUS.RESOLVED and FireService.count(i) == 0, i.status .. " / " .. tostring(i.outcome) .. " / " .. i.waterUsed .. " L")
	local slow = {position = {x = 50, z = 50}}
	FireService.ignite(slow, Incidents.get("FEU_VEHICULE"))
	for _ = 1, 12 do FireService.step(slow, 1) end
	check("combustible synthétique moins vite propagé", FireService.count(slow) == 1)
	local burnt, burnIncident, burnVehicle = fixture("FEU_FORET", "FPT")
	FieldService.giveOrder(burnt, 1, burnVehicle.id, burnIncident.id, "hold")
	for _ = 1, 180 do FireService.step(burnIncident, 1) end
	SimulationService.step(burnt, 1)
	check("foyers consumés sans secours, intervention perdue", burnIncident.status == Constants.INCIDENT_STATUS.FAILED)

	local wr, ir, vr = fixture("FEU_HABITATION", "FPT")
	check("équipe de sauvetage engagée", FieldService.giveOrder(wr, 1, vr.id, ir.id, "rescue").ok)
	for _ = 1, 14 do SimulationService.step(wr, 1) end
	check("occupants sortis avant l'attaque", ir.rescued == ir.victims and ir.waterUsed == 0)
	local wx, ix, vx = fixture("DESINCARCERATION", "FPT")
	check("équipe de découpe équipée", FieldService.giveOrder(wx, 1, vx.id, ix.id, "extricate").ok)
	for _ = 1, 15 do SimulationService.step(wx, 1) end
	check("victimes effectivement désincarcérées", ix.extricated == ix.victims and ix.savedVictims == 0)
	local wm, im, vm = fixture("ACCIDENT_VICTIME", "VSAV")
	check("VSAV une civière, FPT aucune", HospitalService.capacity(wm, vm) == 1 and HospitalService.capacity(wm, vehicleOfType(wm, "FPT")) == 0)
	local trips, handovers, lastStatus, firstAdmission, observedTransit, delayed, noRecall = 0, 0, vm.status, nil, false, false, false
	local earlyAdmission = false
	for _ = 1, 270 do
		SimulationService.step(wm, 1)
		if vm.status ~= lastStatus and vm.status == Constants.VEHICLE_STATUS.TRANSPORTING then
			trips += 1
			observedTransit = vm.patients == 1 and im.inTransit == 1 and vm.route ~= nil and #vm.route.points >= 2
			noRecall = not DispatchService.recall(wm, 1, vm.id).ok
			local entrance = nil
			for _, site in ipairs(wm.cityPlan.buildings) do
				if site.facadeName == "hopital" then entrance = site end
			end
			check("destination à l'entrée de l'hôpital", entrance and math.abs(vm.route.bz - entrance.z1 - 0.6) < 0.001)
		elseif vm.status ~= lastStatus and vm.status == Constants.VEHICLE_STATUS.HANDOVER then
			handovers += 1
			delayed = vm.handoverAt > wm.time and im.savedVictims < handovers
			if handovers == 1 then firstAdmission = vm.handoverAt end
		end
		if firstAdmission and wm.time < firstAdmission and im.savedVictims > 0 then earlyAdmission = true end
		lastStatus = vm.status
		if im.closedAt then break end
	end
	check("aucune admission anticipée", not earlyAdmission)
	check("rotations avec une seule ambulance", trips == 2 and handovers == 2, trips)
	check("victimes et trajet du transport visibles", observedTransit and delayed)
	check("rappel interdit avec victime à bord", noRecall)
	check("bilan basé sur les admissions effectives", im.savedVictims == 2 and wm.stats.savedVictims == 2 and im.outcome == "success", im.status)
	local partial, mixed, ambulance = fixture("ACCIDENT_VICTIME", "VSAV")
	for _ = 1, 180 do
		SimulationService.step(partial, 1)
		if mixed.savedVictims == 1 then break end
	end
	check("rappel autorisé sur la rotation à vide", DispatchService.recall(partial, 1, ambulance.id).ok)
	for _ = 1, 100 do SimulationService.step(partial, 1) end
	check("l'admission reste acquise lors d'un échec partiel", mixed.status == Constants.INCIDENT_STATUS.FAILED
		and mixed.savedVictims == 1 and partial.stats.savedVictims == 1 and partial.stats.civilianLosses == 1)
	local historic = SaveService.serialize(wm)
	historic.fieldInventoryVersion = nil
	historic.equipmentStock.CISAILLE = nil
	for _, oldVehicle in ipairs(historic.vehicles) do oldVehicle.equipment.CISAILLE = nil end
	local oldWorld = newWorld(12)
	SaveService.deserialize(oldWorld, historic)
	check("stock de découpe disponible après migration", oldWorld.equipmentStock.CISAILLE == Config.START_EQUIPMENT.CISAILLE)
	local wl, il, vl = fixture("MALAISE", "VSAV")
	vl.equipment.BRANCARD = nil
	for _ = 1, 140 do SimulationService.step(wl, 1) end
	check("absence de brancard : délai d'évacuation dépassé", il.status == Constants.INCIDENT_STATUS.FAILED and il.savedVictims == 0)
end

suite("Commandement")
-- ─────────────────────────────────────────────────────────────
local groupResult = CommandService.createGroup(world, 1, "Groupe Incendie", "fire")
check("groupe créé", groupResult.ok == true, groupResult.message)
local group = groupResult.data
check("groupe vide", #group.vehicles == 0)
check("ajout du FPT au groupe", CommandService.addUnit(world, 1, group.id, fpt.id).ok == true)
check("ajout en double refusé", CommandService.addUnit(world, 1, group.id, fpt.id).ok == false)
check("groupe de service refuse un autre service",
	CommandService.addUnit(world, 1, group.id, vsav.id).ok == false)

local sectorResult = CommandService.createSector(world, 1, "Secteur Nord", 50, 40, 20)
check("secteur créé", sectorResult.ok == true, sectorResult.message)
check("affectation groupe/secteur", CommandService.assignGroupToSector(world, 1, sectorResult.data.id, group.id).ok == true)
check("lien réciproque", group.sectorId == sectorResult.data.id and world.sectors[sectorResult.data.id].groupId == group.id)
check("bonus nul sans présence sur place", CommandService.sectorBonus(world, incident) == 0)
check("secteur hors carte refusé", CommandService.createSector(world, 1, "Hors carte", 120, 50, 20).ok == false)
check("rayon hors limites refusé", CommandService.createSector(world, 1, "Trop grand", 50, 50, 90).ok == false)
check("engagement de groupe sur intervention close refusé",
	CommandService.dispatchGroup(world, 1, group.id, incident.id).ok == false)
check("dissolution du groupe", CommandService.dissolve(world, 1, group.id).ok == true)
check("groupe supprimé", CommandService.listGroups(world) == nil or #CommandService.listGroups(world) == 0)
check("secteur détaché", world.sectors[sectorResult.data.id].groupId == nil)

-- ─────────────────────────────────────────────────────────────
suite("Boucle de simulation")
-- ─────────────────────────────────────────────────────────────
local loopWorld = newWorld(11)
PermissionService.seed(loopWorld, 1, "DirectionTest")
for _ = 1, 9 do
	SimulationService.step(loopWorld, 1)
end
check("temps avancé", math.abs(loopWorld.time - 9) < 1e-9, loopWorld.time)
check("aucune alerte avant le délai", SaveService.count(loopWorld.incidents) == 0, SaveService.count(loopWorld.incidents))

SimulationService.step(loopWorld, 1)
check("première alerte déclenchée", SaveService.count(loopWorld.incidents) == 1, SaveService.count(loopWorld.incidents))
local loopIncidentType = nil
for _, entry in pairs(loopWorld.incidents) do
	loopIncidentType = entry.typeId
end
local prototype = false
for _, typeId in ipairs(Config.PROTOTYPE_SCENARIOS) do
	if typeId == loopIncidentType then
		prototype = true
	end
end
check("alerte issue des scénarios du prototype", prototype, loopIncidentType)

local shiftWorld = newWorld(12)
shiftWorld.time = Config.SHIFT_SECONDS - 1
SimulationService.step(shiftWorld, 1)
check("fin de service détectée", shiftWorld.finished == true)
check("sauvegarde demandée en fin de service", shiftWorld.saveRequested == true)

local alarmWorld = newWorld(13)
alarmWorld.alarmCountdown = 1e9
SimulationService.step(alarmWorld, 2)
check("pas d'alerte quand le compteur est gelé", SaveService.count(alarmWorld.incidents) == 0)

-- ─────────────────────────────────────────────────────────────
suite("Temps simulé : pause et accélération")
-- ─────────────────────────────────────────────────────────────
local timeWorld = newWorld(14)
PermissionService.seed(timeWorld, 1, "DirectionTest")
PermissionService.seed(timeWorld, 2, "Invité")

check("vitesse initiale ×1", SimulationService.timeScale(timeWorld) == 1)
check("pause acceptée", SimulationService.setTimeScale(timeWorld, 1, 0).ok == true
	and timeWorld.timeScale == 0)
local frozen = timeWorld.time
SimulationService.step(timeWorld, 5)
check("pause : temps figé", math.abs(timeWorld.time - frozen) < 1e-9, timeWorld.time)

check("reprise ×1", SimulationService.setTimeScale(timeWorld, 1, 1).ok == true)
SimulationService.step(timeWorld, 2)
check("temps avance du pas réel", math.abs(timeWorld.time - (frozen + 2)) < 1e-9, timeWorld.time - frozen)

check("×2 accepté", SimulationService.setTimeScale(timeWorld, 1, 2).ok == true)
SimulationService.step(timeWorld, 2)
check("temps doublé à ×2", math.abs(timeWorld.time - (frozen + 6)) < 1e-9, timeWorld.time - frozen)

check("×4 accepté", SimulationService.setTimeScale(timeWorld, 1, 4).ok == true)
check("vitesse hors barème refusée", SimulationService.setTimeScale(timeWorld, 1, 3).ok == false
	and timeWorld.timeScale == 4)
check("vitesse non numérique refusée", SimulationService.setTimeScale(timeWorld, 1, "2").ok == false
	and timeWorld.timeScale == 4)
check("observateur sans droit sur le temps", SimulationService.setTimeScale(timeWorld, 2, 0).ok == false
	and timeWorld.timeScale == 4)
check("état non modifié par un refus", timeWorld.timeScale == 4)
SimulationService.setTimeScale(timeWorld, 1, 1)
check("retour à ×1 après les tests", timeWorld.timeScale == 1)

-- ─────────────────────────────────────────────────────────────
suite("Éclairage lié à l'horloge")
-- ─────────────────────────────────────────────────────────────
local lightingWorld = newWorld(21)
local fakeLighting = Instance.new("Lighting")

local hour = LightingService.apply(fakeLighting, lightingWorld)
check("éclairage appliqué à 06:00", math.abs(hour - 6) < 1e-9, hour)
check("ClockTime suit l'heure simulée", math.abs(fakeLighting.ClockTime - 6) < 1e-9, fakeLighting.ClockTime)
check("heure mémorisée dans le monde", math.abs(lightingWorld.lightingHour - 6) < 1e-9)
check("latitude appliquée", fakeLighting.GeographicLatitude == Config.LIGHTING_LATITUDE)

local atmosphere = fakeLighting:FindFirstChild("ERS_Atmosphere")
check("atmosphère créée", atmosphere ~= nil and atmosphere.ClassName == "Atmosphere")
check("densité d'atmosphère configurée", atmosphere ~= nil
	and math.abs(atmosphere.Density - Config.LIGHTING_ATMOSPHERE_DENSITY) < 1e-9)

check("pas de réécriture à heure identique", LightingService.step(lightingWorld, fakeLighting) == false)
lightingWorld.time = 180
check("réécriture quand l'heure change", LightingService.step(lightingWorld, fakeLighting) == true)
check("ClockTime à mi-service", math.abs(fakeLighting.ClockTime - 12) < 1e-9, fakeLighting.ClockTime)

-- Sans service injecté, `step` écrit sur le Lighting réel du jeu.
lightingWorld.time = 360
check("step sans argument utilise Lighting", LightingService.step(lightingWorld) == true)
check("Lighting du jeu mis à jour",
	math.abs(game:GetService("Lighting").ClockTime - 18) < 1e-9,
	game:GetService("Lighting").ClockTime)
check("une seule atmosphère", (function()
	local count = 0
	for _, child in ipairs(fakeLighting:GetChildren()) do
		if child.ClassName == "Atmosphere" then
			count += 1
		end
	end
	return count == 1
end)())

-- Cycle jour/nuit : facteur, étoiles, lune, lampadaires et vitres.
check("facteur de jour à midi", LightingService.daylight(12, Config) == 1)
check("facteur de jour à l'aube", math.abs(LightingService.daylight(6, Config) - 0.5) < 1e-9)
check("facteur de nuit à 22 h", LightingService.daylight(22, Config) == 0)

local fakeScene = Instance.new("Folder")
fakeScene.Name = "ERS_Scene"
local fakeSky = Instance.new("Folder")
fakeSky.Name = "Ciel"
fakeSky.Parent = fakeScene
local star = Instance.new("Part")
star.Name = "Etoile_1"
star.Transparency = 1
star.Parent = fakeSky
local moon = Instance.new("Part")
moon.Name = "Lune"
moon.Transparency = 1
moon.Parent = fakeSky
local fakeFurniture = Instance.new("Folder")
fakeFurniture.Name = "Mobilier"
fakeFurniture.Parent = fakeScene
local lamp = Instance.new("Part")
lamp.Name = "Lampe_1"
lamp.Parent = fakeFurniture
local glow = Instance.new("PointLight")
glow.Name = "Eclairage"
glow.Enabled = false
glow.Parent = lamp
local fakeBuildings = Instance.new("Folder")
fakeBuildings.Name = "Batiments"
fakeBuildings.Parent = fakeScene
local window = Instance.new("Part")
window.Name = "Vitre_S_1_0"
window.Material = Enum.Material.Glass
window.Transparency = 0.15
window.Parent = fakeBuildings

lightingWorld.time = 180 -- 12 h
LightingService.apply(fakeLighting, lightingWorld, fakeScene)
check("scène mémorisée pour les tics suivants", lightingWorld.scene == fakeScene)
check("étoiles éteintes le jour", star.Transparency >= 0.99)
check("lune éteinte le jour", moon.Transparency >= 0.99)
check("lampadaires éteints le jour", glow.Enabled == false)
check("vitres en verre le jour", window.Material == Enum.Material.Glass)
check("nuit nulle à midi", lightingWorld.lightingNight == 0)

lightingWorld.time = 480 -- 22 h
LightingService.apply(fakeLighting, lightingWorld)
check("étoiles allumées la nuit", star.Transparency < 0.5, star.Transparency)
check("lune visible la nuit", moon.Transparency < 0.2, moon.Transparency)
check("lampadaires allumés la nuit", glow.Enabled == true)
check("fenêtres éclairées la nuit", window.Material == Enum.Material.Neon)
check("nuit complète mémorisée", lightingWorld.lightingNight > 0.9, lightingWorld.lightingNight)
check("ambiance nocturne plus sombre", fakeLighting.Brightness < Config.LIGHTING_BRIGHTNESS)

-- ─────────────────────────────────────────────────────────────
suite("Nouvelle partie")
-- ─────────────────────────────────────────────────────────────
local resetWorld = newWorld(22)
PermissionService.seed(resetWorld, 1, "DirectionTest")
PermissionService.seed(resetWorld, 2, "Invité")

-- On salit la partie : budget, temps, alerte et flotte achetée.
resetWorld.budget = 20000
resetWorld.time = 99
resetWorld.timeScale = 4
local bought = VehicleService.buy(resetWorld, 1, "VSAV")
check("achat préalable pour le test", bought.ok == true, bought.message)
local fleetBeforeReset = SaveService.count(resetWorld.vehicles)
local budgetBeforeReset = resetWorld.budget
IncidentService.spawn(resetWorld, "FEU_VEHICULE", { x = 18, z = 40 })
resetWorld.saveRequested = false

local denied = NetworkService.handle(resetWorld, { UserId = 2, Name = "Invité" }, "new_game", {})
check("nouvelle partie refusée à l'observateur", denied.ok == false, denied.message)
check("refus sans effet sur le budget", resetWorld.budget == budgetBeforeReset)
check("refus sans effet sur la flotte", SaveService.count(resetWorld.vehicles) == fleetBeforeReset)

local accepted = NetworkService.handle(resetWorld, { UserId = 1, Name = "DirectionTest" }, "new_game", {})
check("nouvelle partie acceptée à la direction", accepted.ok == true, accepted.message)
check("budget réinitialisé", resetWorld.budget == Config.START_BUDGET, resetWorld.budget)
check("flotte de départ restaurée", SaveService.count(resetWorld.vehicles) == #Config.START_VEHICLES)
check("effectif de départ restauré", SaveService.count(resetWorld.personnel) == Config.START_PERSONNEL)
check("interventions effacées", SaveService.count(resetWorld.incidents) == 0)
check("groupes et secteurs effacés", SaveService.count(resetWorld.groups) == 0
	and SaveService.count(resetWorld.sectors) == 0)
check("horloge remise à zéro", resetWorld.time == 0 and resetWorld.timeScale == 1)
check("compteur d'alertes remis à zéro", resetWorld.spawnedIncidents == 0)
check("progression sauvegardée remplacée", resetWorld.saveRequested == true)
check("postes en ligne conservés", resetWorld.players[1] ~= nil and resetWorld.players[2] ~= nil)
check("direction toujours en place", resetWorld.players[1].role == Constants.ROLE.DIRECTION)
check("journal de nouvelle partie", (function()
	for _, entry in ipairs(resetWorld.log) do
		if string.find(entry.message, "Nouvelle partie", 1, true) then
			return true
		end
	end
	return false
end)())
check("identifiants repartis du début", resetWorld.nextVehicleId == #Config.START_VEHICLES + 1
	and resetWorld.nextIncidentId == 1)
check("éclairage recalculé après remise à zéro", LightingService.step(resetWorld, fakeLighting) == true
	and math.abs(fakeLighting.ClockTime - Config.SHIFT_START_HOUR) < 1e-9)

-- ─────────────────────────────────────────────────────────────
print("")
do
	suite("Missions jouées et bilans de service")
	local Missions = require(Catalogs:WaitForChild("Missions"))
	local ProgressionService = require(Services:WaitForChild("ProgressionService"))
	local EquipmentService = require(Services:WaitForChild("EquipmentService"))
	for _, def in ipairs(Missions.list) do
		local w = newWorld(21)
		local actor = {UserId = 101, Name = "Direction"}
		PermissionService.seed(w, actor.UserId, actor.Name)
		crewAll(w, actor.UserId)
		local function start(id)
			w.players[actor.UserId].lastAction = -math.huge
			return NetworkService.handle(w, actor, "start_mission", {missionId = id})
		end
		check(def.id .. " · identifiant réseau refusé", not start({}).ok and not start("inconnu").ok)
		check(def.id .. " · lancement depuis la commande réseau", start(def.id).ok)
		check(def.id .. " · pas de deuxième mission simultanée", not start(def.id).ok)
		local mission = w.mission
		local first = w.incidents[mission.incidentIds[1]]
		local initial = SnapshotService.build(w)
		check(def.id .. " · objectif secondaire à découvrir", initial.mission.objectives[2].status == "locked")
		local fpt, ambulance, command = vehicleOfType(w, "FPT"), vehicleOfType(w, "VSAV"), vehicleOfType(w, "VPC")
		if def.id == "eglise" then
			check("sac de secours installé dans le fourgon", EquipmentService.install(w, actor.UserId, fpt.id, "SAC_SECOURS", 1).ok)
		end
		check(def.id .. " · premier départ", DispatchService.dispatch(w, actor.UserId, fpt.id, first.id).ok)
		if def.id == "route" then
			check("route · balisage", DispatchService.dispatch(w, actor.UserId, command.id, first.id).ok)
			check("route · secours médical", DispatchService.dispatch(w, actor.UserId, ambulance.id, first.id).ok)
		end
		local secondSent, triggerTime = false, nil
		for _ = 1, 500 do
			SimulationService.step(w, 1)
			local secondary = w.incidents[mission.incidentIds[2]]
			if secondary and not triggerTime then triggerTime = w.time end
			if secondary and not secondSent then
				if def.id == "route" then
					if first.evacuating and fpt.status == Constants.VEHICLE_STATUS.ON_SCENE then
						DispatchService.recall(w, actor.UserId, fpt.id)
					end
					if fpt.status == Constants.VEHICLE_STATUS.AVAILABLE then
						secondSent = DispatchService.dispatch(w, actor.UserId, fpt.id, secondary.id).ok
					end
				else
					secondSent = DispatchService.dispatch(w, actor.UserId, ambulance.id, secondary.id).ok
				end
			end
			if mission.status ~= "active" then break end
		end
		check(def.id .. " · déclenchement de terrain et arrivée de renforts", secondSent and triggerTime > 0)
		if def.trigger == "radio" then check("forêt · horaire radio respecté", triggerTime == def.delay) end
		check(def.id .. " · deux alertes de mission, aucun appel libre intercalé", w.spawnedIncidents == 2)
		local snap = SnapshotService.build(w)
		local second = w.incidents[mission.incidentIds[2]]
		check(def.id .. " · les deux objectifs aboutissent", mission.status == "completed", tostring(first.outcome) .. " / " .. tostring(second and second.outcome))
		check(def.id .. " · bulletin calculé", snap.progression.score > 0 and snap.progression.rating > 0)
		check(def.id .. " · toutes les victimes transportées", w.stats.savedVictims > 0 and snap.progression.civilianLosses == 0)
		check(def.id .. " · objectifs sérialisables", SnapshotService.isSerializable(snap) and snap.mission.objectives[2].status == "resolved")
		local fresh = newWorld(22)
		SaveService.deserialize(fresh, SaveService.serialize(w))
		check(def.id .. " · réussite et score rechargés sans mission fantôme", fresh.stats["mission_" .. def.id] == 1
			and fresh.stats.score == w.stats.score and fresh.mission == nil)
	end

	local w = newWorld(23)
	do
		local service = require(Services:WaitForChild("MissionService"))
		local observer = {UserId = 44, Name = "Observateur"}
		PermissionService.seed(w, 43, "Directrice")
		PermissionService.seed(w, observer.UserId, observer.Name)
		check("lancement refusé à un observateur", not NetworkService.handle(w, observer, "start_mission", {missionId = "route"}).ok)
		local first = IncidentService.spawn(w, "MALAISE", {x = 40, z = 40}).data
		check("mission coexiste avec un appel antérieur", service.start(w, 43, "foret").ok)
		w.time = 35
		service.step(w)
		check("déclencheur retardé quand les deux places sont occupées", #w.mission.incidentIds == 1 and w.spawnedIncidents == 2)
		IncidentService.fail(w, first, "fin de l’appel libre")
		service.step(w)
		check("déclencheur publié dès qu'une place se libère", #w.mission.incidentIds == 2 and w.spawnedIncidents == 3)
		WorldService.reset(w)
		check("nouvelle partie libère les objectifs", w.mission == nil and next(w.incidents) == nil)
		service.start(w, 43, "eglise")
		local untouched = w.incidents[w.mission.incidentIds[1]]
		IncidentService.fail(w, untouched, "délai dépassé")
		service.step(w)
		check("échec précoce annule les objectifs non déclenchés", w.mission.status == "failed"
			and service.snapshot(w).objectives[2].status == "cancelled")
		WorldService.reset(w)
	end
	local lost = IncidentService.spawn(w, "MALAISE", {x = 20, z = 45}).data
	IncidentService.fail(w, lost, "délai dépassé")
	local report = ProgressionService.snapshot(w)
	check("échec · pénalité civile séparée", report.civilianLosses == 1 and report.civilianPenalty == Config.SCORE_CIVILIAN_LOSS
		and report.rating == 0 and report.score == -Config.SCORE_FAILURE - Config.SCORE_CIVILIAN_LOSS)
	ProgressionService.record(w, lost)
	check("bilan idempotent", w.stats.ratedCalls == 1)
	for i = 1, 5 do
		local incident = IncidentService.spawn(w, "ACCIDENT_CIRCULATION", {x = 49, z = 49}).data
		incident.savedVictims, incident.waterUsed, incident.extricated = 2, 40, 2
		incident.canineSearch, incident.rescued = true, 2
		ProgressionService.arrive(w, incident, vehicleOfType(w, "FPT"))
		ProgressionService.arrive(w, incident, vehicleOfType(w, "VSAV"))
		ProgressionService.arrive(w, incident, {typeId = "VL_POLICE"})
		ProgressionService.arrive(w, incident, {typeId = "VATELIER"})
		IncidentService.resolve(w, incident, false, "bilan du test")
	end
	report = ProgressionService.snapshot(w)
	for _, award in ipairs(report.awards) do
		check("distinction attribuée · " .. award.name, award.earned and award.current == award.target)
	end
	check("évaluation moyenne sur tous les bilans", report.rating == 83 and #report.awards == 6)
	local fresh = newWorld(24)
	SaveService.deserialize(fresh, SaveService.serialize(w))
	check("distinctions permanentes", ProgressionService.snapshot(fresh).awards[6].earned)
	local legacy = SaveService.serialize(w)
	legacy.stats = {resolved = 1, savedVictims = 0}
	SaveService.deserialize(fresh, legacy)
	local restored = ProgressionService.snapshot(fresh)
	check("ancienne sauvegarde · bulletin neuf et parcours conservé", restored.rating == nil and restored.score == 0
		and not restored.awards[6].earned and fresh.stats.resolved == 1)
end
do
	suite("Équipages techniques et gestion du personnel")
	local crewUtil = require(Utilities:WaitForChild("Crew"))
	for _, typeId in ipairs({"VCH", "VLOG", "VATELIER"}) do
		local caserne = newWorld(77)
		PermissionService.seed(caserne, 1, "Direction")
		local hire = PersonnelService.recruit(caserne, 1, "technician")
		local van = VehicleService.create(caserne, typeId).data
		local crew = PersonnelService.autoCrew(caserne, 1, van.id)
		check(typeId .. " armé par la caserne", hire.ok and crew.ok and crewUtil.readiness(caserne, van).ok)
		check(typeId .. " équipage protégé", not PersonnelService.transfer(caserne, 1, van.crew[1]).ok)
	end
	local caserne = newWorld(78)
	PermissionService.seed(caserne, 1, "Direction")
	local tech = PersonnelService.recruit(caserne, 1, "technician").data
	PersonnelService.train(caserne, 1, tech.id)
	local van = VehicleService.create(caserne, "VATELIER").data
	PersonnelService.assign(caserne, 1, tech.id, van.id)
	van.status = Constants.VEHICLE_STATUS.ON_SCENE
	PersonnelService.stepFatigue(caserne, 10)
	check("effet mesurable de la formation", math.abs(tech.fatigue - 9 * Config.FATIGUE_PER_SECOND) < 0.001)
	local saved = SaveService.serialize(caserne)
	local rebuilt = newWorld(79)
	check("niveau et prix payé restaurés", SaveService.deserialize(rebuilt, saved).ok
		and rebuilt.personnel[tech.id].level == 1 and rebuilt.personnel[tech.id].hireCost == tech.hireCost)
	check("inflation restaurée", SnapshotService.build(rebuilt).purchase.surcharge == 30)
	for _, p in ipairs(saved.personnel) do p.level = nil; p.hireCost = nil end
	saved.version = "0.3.0"
	saved.stats.purchases = nil
	check("ancien format accepté", SaveService.deserialize(rebuilt, saved).ok
		and rebuilt.personnel[tech.id].level == 0 and rebuilt.personnel[tech.id].hireCost == 1200
		and SnapshotService.build(rebuilt).purchase.surcharge == 0)
end

do
	suite("Relève du soir sur la ville construite")
	local SceneService = require(Services:WaitForChild("SceneService"))
	local shift = newWorld(188)
	shift.alarmCountdown = 1e9
	PermissionService.seed(shift, 1, "Direction")
	local scene = SceneService.build(Config, Instance.new("Folder"))
	local lighting = Instance.new("Lighting")
	LightingService.apply(lighting, shift, scene)
	SimulationService.setTimeScale(shift, 1, 4)
	local star = scene:FindFirstChild("Ciel"):FindFirstChild("Etoile_1")
	local moon = scene:FindFirstChild("Ciel"):FindFirstChild("Lune")
	local lamp = scene:FindFirstChild("Mobilier"):FindFirstChild("Lampe_1"):FindFirstChild("Eclairage")
	local windows = {}
	for _, part in ipairs(scene:FindFirstChild("Batiments"):GetChildren()) do
		if string.sub(part.Name, 1, 5) == "Vitre" then table.insert(windows, part) end
	end
	local function reach(hour)
		local target = (hour - Config.SHIFT_START_HOUR) * Config.SHIFT_SECONDS / 24
		while shift.time < target do
			SimulationService.step(shift, math.min(1, (target - shift.time) / 4))
			LightingService.step(shift, lighting, scene)
		end
	end
	reach(19)
	check("ville à 19 h en simulation accélérée", lighting.ClockTime == 19 and not lamp.Enabled and #windows > 0)
	reach(20)
	local twilight = moon.Transparency
	check("lumières et ciel au crépuscule", lamp.Enabled and twilight > 0.05 and twilight < 1 and star.Transparency < 1)
	reach(21)
	local lit = 0
	for _, pane in ipairs(windows) do
		if pane.Material == Enum.Material.Neon then lit += 1 end
	end
	check("ville à 21 h, lune, étoiles, vitrages et lampadaires", lighting.ClockTime == 21
		and moon.Transparency < twilight and star.Transparency < 0.2 and lamp.Enabled and lit == #windows)
	scene:Destroy()
end

print(string.format("  Intégration : %d réussite(s), %d échec(s)", passed, failed))
if failed > 0 then
	error(string.format("%d test(s) d'intégration en échec", failed))
end
