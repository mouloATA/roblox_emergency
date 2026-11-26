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
check("personnel affecté comptabilisé", SaveService.count(world.personnel) == 12)

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
local saved = SaveService.save(world, store)
check("sauvegarde réussie", saved.ok == true, saved.message)

local reloaded = newWorld(99)
local loaded = SaveService.load(reloaded, store)
check("chargement réussi", loaded.ok == true, loaded.message)
check("budget restauré", reloaded.budget == world.budget, reloaded.budget)
check("flotte restaurée", SaveService.count(reloaded.vehicles) == 3, SaveService.count(reloaded.vehicles))
check("effectif restauré", SaveService.count(reloaded.personnel) == 12, SaveService.count(reloaded.personnel))
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
print(string.format("  Intégration : %d réussite(s), %d échec(s)", passed, failed))
if failed > 0 then
	error(string.format("%d test(s) d'intégration en échec", failed))
end
