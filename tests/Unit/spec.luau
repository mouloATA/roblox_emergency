--!nonstrict
--[[
	Tests unitaires — mathématiques, générateur, horloge, catalogue, budget,
	équipages et matrice de permissions.

	Aucun service serveur n'est monté ici : on teste les modules purs et les
	règles partagées. Les assertions portent sur des valeurs vérifiables, pas
	sur des effets visuels.
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

local MathX = require(Utilities:WaitForChild("MathX"))
local Rng = require(Utilities:WaitForChild("Rng"))
local TimeUtil = require(Utilities:WaitForChild("TimeUtil"))
local Result = require(Utilities:WaitForChild("Result"))
local Crew = require(Utilities:WaitForChild("Crew"))
local Navigation = require(Utilities:WaitForChild("Navigation"))
local RoadNetwork = require(Utilities:WaitForChild("RoadNetwork"))
local City = require(Shared:WaitForChild("City"))

local Vehicles = require(Catalogs:WaitForChild("Vehicles"))
local Qualifications = require(Catalogs:WaitForChild("Qualifications"))
local Equipment = require(Catalogs:WaitForChild("Equipment"))
local Incidents = require(Catalogs:WaitForChild("Incidents"))
local Permissions = require(Catalogs:WaitForChild("Permissions"))

local BudgetService = require(game:GetService("ServerScriptService"):WaitForChild("ERS"):WaitForChild("Services"):WaitForChild("BudgetService"))

-- ─────────────────────────────────────────────────────────────
suite("MathX")
-- ─────────────────────────────────────────────────────────────
check("clamp borne basse", MathX.clamp(-5, 0, 10) == 0)
check("clamp borne haute", MathX.clamp(50, 0, 10) == 10)
check("clamp valeur médiane", MathX.clamp(4, 0, 10) == 4)
check("round positif", MathX.round(2.5) == 3)
check("round négatif", MathX.round(-2.5) == -3)
check("lerp", MathX.lerp(10, 20, 0.25) == 12.5)
check("distance 3-4-5", MathX.distance(0, 0, 3, 4) == 5)
check("ratio besoin nul", MathX.ratio(0, 0) == 1)
check("ratio partiel", math.abs(MathX.ratio(2, 4) - 0.5) < 1e-9)
check("somme", MathX.sum({ a = 1, b = 2, c = 3 }) == 6)

-- ─────────────────────────────────────────────────────────────
suite("Réseau routier et navigation")
-- ─────────────────────────────────────────────────────────────
local cityPlan = City.build(Config.CITY_SEED)
local network = RoadNetwork.build(cityPlan)
check("graphe : 25 carrefours", #network.nodes == 25, #network.nodes)
check("graphe : 40 tronçons", #network.edges == 40, #network.edges)
check("graphe utilisable", RoadNetwork.usable(network) == true)

local from = { x = Config.HQ_X, z = Config.HQ_Z }
local to = { x = 62, z = 84 }
local points = RoadNetwork.path(network, from, to)
check("trajet : polyligne", #points >= 3, #points)
check("trajet : départ conservé", points[1].x == from.x and points[1].z == from.z)
check("trajet : arrivée conservée", points[#points].x == to.x and points[#points].z == to.z)

local onRoad = true
for index = 2, #points - 1 do
	local point = points[index]
	local onAvenue = false
	for _, avenue in ipairs(network.avenues) do
		if math.abs(point.x - avenue) < 0.01 then
			onAvenue = true
		end
	end
	local onStreet = false
	for _, street in ipairs(network.streets) do
		if math.abs(point.z - street) < 0.01 then
			onStreet = true
		end
	end
	if not onAvenue and not onStreet then
		onRoad = false
	end
end
check("trajet : points intermédiaires sur la chaussée", onRoad)

local _, pathLength = Navigation.measure(points)
check("trajet : plus long que le vol d'oiseau", pathLength > MathX.distance(from.x, from.z, to.x, to.z))
local _, againLength = Navigation.measure(RoadNetwork.path(network, from, to))
check("trajet : déterministe", math.abs(pathLength - againLength) < 1e-9)

local sameEdge = RoadNetwork.path(network, { x = 7, z = 55 }, { x = 7, z = 60 })
local _, sameEdgeLength = Navigation.measure(sameEdge)
check("trajet : même tronçon", math.abs(sameEdgeLength - 5) < 1e-9, sameEdgeLength)

local route = Navigation.route(Config, from, to, 2, 10, true, points)
check("route : longueur mesurée", math.abs(route.length - pathLength) < 1e-9)
check("route : durée positive", route.duration > 0)
local routeStart = Navigation.position(route, 10)
check("route : position de départ", math.abs(routeStart.x - from.x) < 1e-6 and math.abs(routeStart.z - from.z) < 1e-6)
local routeEnd = Navigation.position(route, 10 + route.duration)
check("route : position d'arrivée", math.abs(routeEnd.x - to.x) < 1e-6 and math.abs(routeEnd.z - to.z) < 1e-6)
check("route : arrivée signalée", Navigation.arrived(route, 10 + route.duration) == true)
check("route : trajet restant borné", Navigation.remaining(route, 10) <= route.duration + 1e-9)

local direct = Navigation.route(Config, { x = 0, z = 0 }, { x = 3, z = 4 }, 2, 0, false)
check("route directe de repli", direct.length == 5 and direct.points == nil)

-- ─────────────────────────────────────────────────────────────
suite("Rng déterministe")
-- ─────────────────────────────────────────────────────────────
local rngA = Rng.new(1234)
local rngB = Rng.new(1234)
local sameSequence = true
for _ = 1, 20 do
	if rngA:next() ~= rngB:next() then
		sameSequence = false
	end
end
check("même graine = même séquence", sameSequence)

local rngC = Rng.new(1234)
local rngD = Rng.new(9999)
check("graines différentes = séquences différentes", rngC:next() ~= rngD:next())

local rngRange = Rng.new(77)
local inRange = true
for _ = 1, 200 do
	local value = rngRange:integer(3, 7)
	if value < 3 or value > 7 or value % 1 ~= 0 then
		inRange = false
	end
end
check("integer respecte les bornes", inRange)

local rngPick = Rng.new(5)
check("pick vide renvoie nil", rngPick:pick({}) == nil)
check("pick renvoie un élément", rngPick:pick({ "a", "b", "c" }) ~= nil)
local always = rngPick:weighted({ "seul" }, function()
	return 1
end)
check("weighted poids unique", always == "seul")
local zeroWeights = rngPick:weighted({ "x", "y" }, function()
	return 0
end)
check("weighted poids nuls reste défini", zeroWeights ~= nil)

-- ─────────────────────────────────────────────────────────────
suite("Horloge")
-- ─────────────────────────────────────────────────────────────
check("format minuit + décalage", TimeUtil.format(0, 6) == "06:00")
check("format 1 h", TimeUtil.format(3600, 0) == "01:00")
check("format 25 h revient à 01:00", TimeUtil.format(25 * 3600, 0) == "01:00")
check("durée < 1 min", TimeUtil.duration(42) == "42s")
check("durée en minutes", TimeUtil.duration(80) == "1 min 20s")

local fakeWorld = { time = 0, config = { SHIFT_SECONDS = 720, SHIFT_START_HOUR = 6 } }
check("horloge de service 06:00", TimeUtil.clock(fakeWorld) == "06:00")
fakeWorld.time = 360
check("horloge de service 18:00", TimeUtil.clock(fakeWorld) == "18:00")

-- L'éclairage a besoin d'une heure décimale, pas d'une chaîne.
fakeWorld.time = 0
check("heure de départ 06:00", TimeUtil.hour(fakeWorld) == 6)
fakeWorld.time = 360
check("mi-service 18:00", TimeUtil.hour(fakeWorld) == 18)
fakeWorld.time = 180
check("quart de service 12:00", TimeUtil.hour(fakeWorld) == 12)
fakeWorld.time = 720
check("un service complet revient à 06:00", TimeUtil.hour(fakeWorld) == 6)
fakeWorld.time = 900
check("heure suivante repliée sur 24 h", math.abs(TimeUtil.hour(fakeWorld) - 12) < 1e-9)
fakeWorld.time = 120
check("heure fractionnaire conservée", math.abs(TimeUtil.hour(fakeWorld) - 10) < 1e-9)

-- Un service nul ne doit pas diviser par zéro.
local brokenWorld = { time = 60, config = { SHIFT_SECONDS = 0, SHIFT_START_HOUR = 6 } }
check("service de durée nulle protégé", math.abs(TimeUtil.hour(brokenWorld) - 6) < 1e-9,
	TimeUtil.hour(brokenWorld))

-- ─────────────────────────────────────────────────────────────
suite("Result")
-- ─────────────────────────────────────────────────────────────
check("ok() est vrai", Result.ok("fait").ok == true)
check("err() est faux", Result.err("refus").ok == false)
check("message conservé", Result.err("refus précis").message == "refus précis")
check("isOk", Result.isOk(Result.ok()) == true and Result.isOk(Result.err()) == false)
check("isOk(nil) est faux", Result.isOk(nil) == false)

-- ─────────────────────────────────────────────────────────────
suite("Intégrité des catalogues")
-- ─────────────────────────────────────────────────────────────
local capabilityKeys = { fire = true, rescue = true, medical = true, police = true, command = true, technical = true }

local vehicleIds = {}
local vehicleErrors = 0
for _, def in ipairs(Vehicles.list) do
	if vehicleIds[def.id] then
		vehicleErrors += 1
	end
	vehicleIds[def.id] = true

	if Constants.SERVICE_LABEL[def.service] == nil then
		vehicleErrors += 1
	end
	if def.crewRequired > def.seats then
		vehicleErrors += 1
	end
	if def.crewRequired < 1 or def.seats < 1 then
		vehicleErrors += 1
	end
	if def.driverRequired ~= true then
		vehicleErrors += 1
	end
	if #def.qualifications == 0 then
		vehicleErrors += 1
	end
	for _, qualificationId in ipairs(def.qualifications) do
		if not Qualifications.exists(qualificationId) then
			vehicleErrors += 1
		end
	end
	for _, entry in ipairs(def.defaultEquipment) do
		if not Equipment.exists(entry.id) or entry.quantity < 1 then
			vehicleErrors += 1
		end
	end
	local capabilityCount = 0
	for key, value in pairs(def.capabilities) do
		if not capabilityKeys[key] or value <= 0 then
			vehicleErrors += 1
		end
		capabilityCount += 1
	end
	if capabilityCount == 0 then
		vehicleErrors += 1
	end
	if def.cost <= 0 or def.mobilizationCost <= 0 then
		vehicleErrors += 1
	end
	if #Vehicles.orderInService(def.service) == 0 then
		vehicleErrors += 1
	end
end
check("véhicules : 34 types", #Vehicles.list == 34, #Vehicles.list)
check("véhicules : aucun doublon / champ invalide", vehicleErrors == 0, vehicleErrors)
check("véhicules : lookup et libellé", Vehicles.label("FPT") == "Fourgon Pompe Tonne")
check("véhicules : type inconnu", Vehicles.exists("INCONNU") == false)

local incidentErrors = 0
local incidentIds = {}
for _, def in ipairs(Incidents.list) do
	if incidentIds[def.id] then
		incidentErrors += 1
	end
	incidentIds[def.id] = true

	if Constants.SERVICE_LABEL[def.service] == nil then
		incidentErrors += 1
	end
	if def.severity < 1 or def.severity > 3 then
		incidentErrors += 1
	end
	if #def.steps == 0 then
		incidentErrors += 1
	end
	for _, step in ipairs(def.steps) do
		if step.seconds <= 0 or #step.label == 0 then
			incidentErrors += 1
		end
		local requirements = 0
		for key, value in pairs(step.requires) do
			if not capabilityKeys[key] or value <= 0 then
				incidentErrors += 1
			end
			requirements += 1
		end
		if requirements == 0 then
			incidentErrors += 1
		end
	end
	local globalRequirements = 0
	for key, value in pairs(def.requires) do
		if not capabilityKeys[key] or value <= 0 then
			incidentErrors += 1
		end
		globalRequirements += 1
	end
	if globalRequirements == 0 then
		incidentErrors += 1
	end
	for _, equipmentId in ipairs(def.equipment) do
		if not Equipment.exists(equipmentId) then
			incidentErrors += 1
		end
	end
	for _, qualificationId in ipairs(def.qualifications) do
		if not Qualifications.exists(qualificationId) then
			incidentErrors += 1
		end
	end
	if def.responseDeadline < 60 or def.reward <= 0 or def.penalty <= 0 or def.weight <= 0 then
		incidentErrors += 1
	end
	if #def.briefing < 20 then
		incidentErrors += 1
	end
end
check("interventions : 32 scénarios", #Incidents.list == 32, #Incidents.list)
check("interventions : aucun doublon / champ invalide", incidentErrors == 0, incidentErrors)
check("interventions : libellé", Incidents.label("FEU_HABITATION") == "Feu d'habitation")

-- Chaque capacité exigée doit être fournie par au moins un type d'engin :
-- aucune intervention ne doit être impossible par construction.
local providedCapabilities = {}
for _, def in ipairs(Vehicles.list) do
	for key in pairs(def.capabilities) do
		providedCapabilities[key] = true
	end
end
local unsupportedRequirements = {}
local function auditRequires(incidentId, requires, scope)
	for key in pairs(requires) do
		if not providedCapabilities[key] then
			table.insert(unsupportedRequirements, incidentId .. "." .. scope .. "." .. key)
		end
	end
end
for _, def in ipairs(Incidents.list) do
	auditRequires(def.id, def.requires, "global")
	for index, step in ipairs(def.steps) do
		auditRequires(def.id, step.requires, "etape" .. index)
	end
end
check("interventions : capacités fournies par le catalogue", #unsupportedRequirements == 0,
	table.concat(unsupportedRequirements, ", "))

local equipmentErrors = 0
for _, def in ipairs(Equipment.list) do
	if #def.services == 0 then
		equipmentErrors += 1
	end
	for _, service in ipairs(def.services) do
		if Constants.SERVICE_LABEL[service] == nil then
			equipmentErrors += 1
		end
	end
	for key, value in pairs(def.bonus) do
		if not capabilityKeys[key] or value <= 0 then
			equipmentErrors += 1
		end
	end
	if def.weight <= 0 or def.cost <= 0 then
		equipmentErrors += 1
	end
end
check("matériel : 24 références", #Equipment.list == 24, #Equipment.list)
check("matériel : aucun champ invalide", equipmentErrors == 0, equipmentErrors)

local qualificationIds = {}
local qualificationErrors = 0
for _, def in ipairs(Qualifications.list) do
	if qualificationIds[def.id] then
		qualificationErrors += 1
	end
	qualificationIds[def.id] = true
	if #def.name == 0 or #def.description == 0 then
		qualificationErrors += 1
	end
end
check("qualifications : 23 références", #Qualifications.list == 23, #Qualifications.list)
check("qualifications : aucun doublon", qualificationErrors == 0)

-- ─────────────────────────────────────────────────────────────
suite("Réglages et données de départ")
-- ─────────────────────────────────────────────────────────────
check("version renseignée", Config.VERSION == "0.3.0")
check("budget de départ positif", Config.START_BUDGET > 0)
check("cadence de simulation", Config.TICK_RATE > 0 and Config.SNAPSHOT_RATE > 0)
check("plafond d'interventions", Config.MAX_ACTIVE_INCIDENTS >= 1)

local startVehiclesOk = true
for _, typeId in ipairs(Config.START_VEHICLES) do
	if not Vehicles.exists(typeId) then
		startVehiclesOk = false
	end
end
check("flotte de départ valide", startVehiclesOk)

local startEquipmentOk = true
for equipmentId in pairs(Config.START_EQUIPMENT) do
	if not Equipment.exists(equipmentId) then
		startEquipmentOk = false
	end
end
check("stock de départ valide", startEquipmentOk)

local scenariosOk = true
for _, incidentId in ipairs(Config.PROTOTYPE_SCENARIOS) do
	if not Incidents.exists(incidentId) then
		scenariosOk = false
	end
end
check("scénarios du prototype valides", scenariosOk)

-- Ceinture boisée : elle masque le bord du sol depuis la caméra.
local beltTrees = 0
for _, tree in ipairs(cityPlan.trees) do
	if tree.x < 0 or tree.x > City.WIDTH or tree.z < 0 or tree.z > City.WIDTH then
		beltTrees += 1
	end
end
check("ceinture boisée plantée", beltTrees > 20, beltTrees)

check("sons fournis par le client", string.sub(Config.AUDIO_AMBIENCE, 1, 11) == "rbxasset://"
	and string.sub(Config.AUDIO_SIREN, 1, 11) == "rbxasset://")
check("sirène à deux tons", #Config.AUDIO_SIREN_SPEEDS == 2
	and Config.AUDIO_SIREN_SPEEDS[1] ~= Config.AUDIO_SIREN_SPEEDS[2])
check("ciel procédural configuré", Config.SKY_RADIUS > 0 and Config.SKY_STARS > 0)

-- ─────────────────────────────────────────────────────────────
suite("Budget")
-- ─────────────────────────────────────────────────────────────
local function budgetWorld()
	return {
		budget = 1000,
		transactions = {},
		stats = { spent = 0, earned = 0 },
		time = 0,
		config = { TRANSACTION_LIMIT = 5 },
	}
end

local bw = budgetWorld()
check("dépense autorisée", BudgetService.spend(bw, 300, "test").ok == true)
check("solde après dépense", bw.budget == 700)
check("cumul des dépenses", bw.stats.spent == 300)
check("écriture enregistrée", #bw.transactions == 1 and bw.transactions[1].amount == -300)
check("dépense refusée", BudgetService.spend(bw, 1000, "test").ok == false)
check("solde inchangé après refus", bw.budget == 700)
check("canAfford vrai", BudgetService.canAfford(bw, 700) == true)
check("canAfford faux", BudgetService.canAfford(bw, 701) == false)

check("pénalité appliquée", BudgetService.penalty(bw, 2000, "sanction").ok == true)
check("solde négatif autorisé", bw.budget == -1300)
check("recette", BudgetService.earn(bw, 500, "règlement").ok == true)
check("solde après recette", bw.budget == -800)
check("cumul des recettes", bw.stats.earned == 500)

local capped = budgetWorld()
for _ = 1, 12 do
	BudgetService.spend(capped, 1, "micro")
end
check("journal des écritures plafonné", #capped.transactions == 5, #capped.transactions)

local summary = BudgetService.summary(capped)
check("résumé du budget cohérent", summary.spent == 12 and summary.balance == capped.budget)

-- ─────────────────────────────────────────────────────────────
suite("Équipages")
-- ─────────────────────────────────────────────────────────────
local function person(id, service, qualifications, experience)
	return {
		id = id,
		name = "Membre " .. id,
		grade = "Sapeur",
		service = service,
		qualifications = qualifications,
		experience = experience or 10,
		fatigue = 0,
		health = 100,
		status = Constants.VEHICLE_STATUS.AVAILABLE,
		vehicleId = nil,
	}
end

local mini = {
	config = { REST_FATIGUE = 85, MIN_HEALTH = 1 },
	catalogs = {
		vehicles = Vehicles,
		qualifications = Qualifications,
		equipment = Equipment,
		incidents = Incidents,
		permissions = Permissions,
	},
	vehicles = {},
	personnel = {},
}
mini.personnel[1] = person(1, "fire", { SAPEUR = true, CONDUCTEUR = true, CHEF_AGRES = true }, 50)
mini.personnel[2] = person(2, "fire", { SAPEUR = true }, 30)
mini.personnel[3] = person(3, "fire", { SAPEUR = true, SECOURISTE = true }, 20)
mini.personnel[4] = person(4, "medical", { SECOURISTE = true, CONDUCTEUR = true }, 40)
mini.personnel[5] = person(5, "fire", { SAPEUR = true }, 10)
mini.personnel[6] = person(6, "fire", { SAPEUR = true }, 5)

local fpt = {
	id = 1,
	typeId = "FPT",
	callsign = "FPT 1",
	status = Constants.VEHICLE_STATUS.AVAILABLE,
	condition = 100,
	crew = {},
	equipment = {},
	position = { x = 10, z = 10 },
	home = { x = 10, z = 10 },
}
mini.vehicles[1] = fpt

check("affectation compatible", Crew.canAssign(mini, mini.personnel[2], fpt).ok == true)
check("affectation incompatible (service)", Crew.canAssign(mini, mini.personnel[4], fpt).ok == false)

mini.personnel[2].fatigue = 90
check("affectation refusée si fatigué", Crew.canAssign(mini, mini.personnel[2], fpt).ok == false)
mini.personnel[2].fatigue = 0

mini.personnel[5].vehicleId = 1
check("affectation refusée si déjà affecté", Crew.canAssign(mini, mini.personnel[5], fpt).ok == false)
mini.personnel[5].vehicleId = nil

local readinessEmpty = Crew.readiness(mini, fpt)
check("équipage vide non prêt", readinessEmpty.ok == false and readinessEmpty.data.seatsShort == 4)

local selected = Crew.autoSelect(mini, fpt)
check("sélection automatique limitée aux disponibles", #selected == 4, #selected)
local selectedMap = {}
for _, id in ipairs(selected) do
	selectedMap[id] = true
end
check("sélection inclut le conducteur", selectedMap[1] == true)
check("sélection n'inclut pas un autre service", selectedMap[4] == nil)

for _, id in ipairs(selected) do
	Crew.assign(mini, mini.personnel[id], fpt)
end
check("équipage affecté", #fpt.crew == 4)
check("équipage prêt", Crew.readiness(mini, fpt).ok == true)

local power = Crew.power(mini, fpt)
check("puissance incendie de base", power.fire == 3)
check("puissance sauvetage de base", power.rescue == 2)

fpt.equipment.ARI = 2
check("bonus matériel appliqué une fois", Crew.power(mini, fpt).fire == 4)

local total = Crew.totalPower(mini, { fpt })
check("puissance cumulée", total.fire == 4)

local equipmentOk = Crew.hasRequiredEquipment(mini, { typeId = "FEU_VEHICULE" }, { fpt })
check("matériel requis absent", equipmentOk == false)
fpt.equipment.EXTINCTEUR = 1
check("matériel requis présent", Crew.hasRequiredEquipment(mini, { typeId = "FEU_VEHICULE" }, { fpt }) == true)

local qualificationsOk = Crew.hasRequiredQualifications(mini, { typeId = "FEU_VEHICULE" }, { fpt })
check("qualification requise présente", qualificationsOk == true)

-- Désaffectation
local member = Crew.members(mini, fpt)[1]
local beforeCount = #fpt.crew
Crew.unassign(mini, member)
check("désaffectation réduit l'équipage", #fpt.crew == beforeCount - 1)
check("membre libéré", member.vehicleId == nil)

-- ─────────────────────────────────────────────────────────────
suite("Permissions")
-- ─────────────────────────────────────────────────────────────
check("direction existe", Permissions.exists(Constants.ROLE.DIRECTION))
check("poste inconnu", Permissions.exists("inconnu") == false)
check("direction peut tout", Permissions.can(Constants.ROLE.DIRECTION, Constants.ACTION.SAVE) == true)
check("observateur lecture seule", Permissions.can(Constants.ROLE.OBSERVATEUR, Constants.ACTION.VIEW) == true)
check("observateur ne peut pas engager", Permissions.can(Constants.ROLE.OBSERVATEUR, Constants.ACTION.DISPATCH) == false)
check("incendie limité au feu", Permissions.canService(Constants.ROLE.INCENDIE, "fire") == true)
check("incendie exclut le secours", Permissions.canService(Constants.ROLE.INCENDIE, "medical") == false)
check("secours limité au médical", Permissions.canService(Constants.ROLE.SECOURS, "medical") == true)
check("police limitée à la police", Permissions.canService(Constants.ROLE.POLICE, "police") == true)
check("commandement : tous services", Permissions.serviceScope(Constants.ROLE.COMMANDEMENT) == nil)
check("direction : tous services", Permissions.serviceScope(Constants.ROLE.DIRECTION) == nil)
check("observateur : aucun service", Permissions.canService(Constants.ROLE.OBSERVATEUR, "fire") == false)
check("incendie ne peut pas acheter", Permissions.can(Constants.ROLE.INCENDIE, Constants.ACTION.BUY_VEHICLE) == false)
check("logistique peut réparer", Permissions.can(Constants.ROLE.LOGISTIQUE, Constants.ACTION.REPAIR) == true)

-- ─────────────────────────────────────────────────────────────
print("")
print(string.format("  Unitaires : %d réussite(s), %d échec(s)", passed, failed))
if failed > 0 then
	error(string.format("%d test(s) unitaire(s) en échec", failed))
end
