--!nonstrict
--[[
	Tests multijoueur — rôles, périmètres de service, validation réseau.

	Tout passe par `NetworkService.handle`, c'est-à-dire exactement par la
	frontière utilisée par les RemoteEvents. On vérifie que le serveur refuse
	une intention non autorisée, mal formée ou spamée, et qu'il ne se contente
	pas de « faire confiance » au client.
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
local Catalogs = Shared:WaitForChild("Catalogs")
local Vehicles = require(Catalogs:WaitForChild("Vehicles"))
local Qualifications = require(Catalogs:WaitForChild("Qualifications"))
local Equipment = require(Catalogs:WaitForChild("Equipment"))
local Incidents = require(Catalogs:WaitForChild("Incidents"))
local Permissions = require(Catalogs:WaitForChild("Permissions"))

local Services = game:GetService("ServerScriptService"):WaitForChild("ERS"):WaitForChild("Services")
local WorldService = require(Services:WaitForChild("WorldService"))
local NetworkService = require(Services:WaitForChild("NetworkService"))
local PermissionService = require(Services:WaitForChild("PermissionService"))
local IncidentService = require(Services:WaitForChild("IncidentService"))
local SnapshotService = require(Services:WaitForChild("SnapshotService"))

local catalogs = {
	vehicles = Vehicles,
	qualifications = Qualifications,
	equipment = Equipment,
	incidents = Incidents,
	permissions = Permissions,
}

local world = WorldService.create(Config, catalogs, { seed = 4242 })
world.alarmCountdown = 1e9

local chief = { UserId = 1001, Name = "Chef" }
local firefighter = { UserId = 1002, Name = "Pompier" }
local observer = { UserId = 1003, Name = "Observateur" }

-- Réinitialise l'anti-spam avant chaque appel volontaire.
local function send(player, action, payload)
	local record = world.players[player.UserId]
	if record then
		record.lastAction = -math.huge
	end
	return NetworkService.handle(world, player, action, payload)
end

local function vehicleOfType(typeId)
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

-- ─────────────────────────────────────────────────────────────
suite("Enregistrement et prise de poste")
-- ─────────────────────────────────────────────────────────────
local hello = send(chief, "request_snapshot", nil)
check("premier appel enregistre le joueur", hello.ok == true, hello.message)
check("premier joueur = direction", world.players[1001].role == Constants.ROLE.DIRECTION)
check("fiche joueur créée", world.players[1001].name == "Chef")

local claimFire = send(firefighter, "claim_role", { role = Constants.ROLE.INCENDIE })
check("prise du poste incendie", claimFire.ok == true, claimFire.message)
check("poste affecté", world.players[1002].role == Constants.ROLE.INCENDIE)

local claimConflict = send(observer, "claim_role", { role = Constants.ROLE.INCENDIE })
check("poste déjà tenu refusé", claimConflict.ok == false)
check("message explicite", string.find(claimConflict.message, "déjà tenu") ~= nil, claimConflict.message)

local claimMedical = send(observer, "claim_role", { role = Constants.ROLE.SECOURS })
check("changement de poste autorisé", claimMedical.ok == true, claimMedical.message)
check("poste mis à jour", world.players[1003].role == Constants.ROLE.SECOURS)

local claimUnknown = send(observer, "claim_role", { role = "astronaute" })
check("poste inconnu refusé", claimUnknown.ok == false)

local claimInvalid = send(observer, "claim_role", { role = 42 })
check("poste mal formé refusé", claimInvalid.ok == false)

-- ─────────────────────────────────────────────────────────────
suite("Attribution par la direction")
-- ─────────────────────────────────────────────────────────────
local assignTaken = send(chief, "assign_role", { userId = 1003, role = Constants.ROLE.INCENDIE })
check("attribution d'un poste déjà tenu refusée", assignTaken.ok == false)

local assignObserver = send(chief, "assign_role", { userId = 1003, role = Constants.ROLE.OBSERVATEUR })
check("direction peut attribuer un poste", assignObserver.ok == true, assignObserver.message)
check("cible mise à jour", world.players[1003].role == Constants.ROLE.OBSERVATEUR)

local stealDirection = send(chief, "assign_role", { userId = 1002, role = Constants.ROLE.DIRECTION })
check("direction non transférable", stealDirection.ok == false)

local unauthorizedAssign = send(firefighter, "assign_role", { userId = 1003, role = Constants.ROLE.POLICE })
check("attribution sans droit refusée", unauthorizedAssign.ok == false)
check("la cible n'a pas changé", world.players[1003].role == Constants.ROLE.OBSERVATEUR)

-- ─────────────────────────────────────────────────────────────
suite("Périmètre des services")
-- ─────────────────────────────────────────────────────────────
local fpt = vehicleOfType("FPT")
local vsav = vehicleOfType("VSAV")

local crewFire = send(firefighter, "auto_crew", { vehicleId = fpt.id })
check("incendie peut armer un FPT", crewFire.ok == true, crewFire.message)
check("FPT armé côté serveur", #fpt.crew >= 1)

local crewMedical = send(firefighter, "auto_crew", { vehicleId = vsav.id })
check("incendie ne peut pas armer un VSAV", crewMedical.ok == false)
check("message de périmètre", string.find(crewMedical.message, "périmètre") ~= nil, crewMedical.message)

local alert = IncidentService.spawn(world, "FEU_VEHICULE", { x = 78, z = 22 })
check("intervention de test créée", alert.ok == true, alert.message)
local incident = alert.data

local dispatchFire = send(firefighter, "dispatch", { vehicleId = fpt.id, incidentId = incident.id })
check("incendie peut engager un FPT", dispatchFire.ok == true, dispatchFire.message)
check("véhicule réellement engagé", fpt.status == Constants.VEHICLE_STATUS.DISPATCHED)

local dispatchMedical = send(firefighter, "dispatch", { vehicleId = vsav.id, incidentId = incident.id })
check("incendie ne peut pas engager un VSAV", dispatchMedical.ok == false)

local recallOutOfScope = send(firefighter, "recall", { vehicleId = vsav.id })
check("rappel hors périmètre refusé", recallOutOfScope.ok == false)

local equipOutOfScope = send(firefighter, "install_equipment", { vehicleId = vsav.id, equipmentId = "DEFIB", quantity = 1 })
check("installation hors périmètre refusée", equipOutOfScope.ok == false)

-- ─────────────────────────────────────────────────────────────
suite("Observateur et actions sensibles")
-- ─────────────────────────────────────────────────────────────
local observerDispatch = send(observer, "dispatch", { vehicleId = vsav.id, incidentId = incident.id })
check("observateur ne peut pas engager", observerDispatch.ok == false)
check("message d'action non autorisée", string.find(observerDispatch.message, "autorisée") ~= nil, observerDispatch.message)

local observerBuy = send(observer, "buy_vehicle", { typeId = "VSAV" })
check("observateur ne peut pas acheter", observerBuy.ok == false)

local observerSave = send(observer, "save", nil)
check("observateur ne peut pas sauvegarder", observerSave.ok == false)

local observerNewGame = send(observer, "new_game", nil)
check("observateur ne peut pas relancer une partie", observerNewGame.ok == false)
check("refus sans effet sur la partie", world.time >= 0 and world.budget > 0)

local observerGroup = send(observer, "create_group", { name = "Groupe", service = "fire" })
check("observateur ne peut pas commander", observerGroup.ok == false)

local firefighterBuy = send(firefighter, "buy_vehicle", { typeId = "VSAV" })
check("incendie ne peut pas acheter", firefighterBuy.ok == false)

local chiefSave = send(chief, "save", nil)
check("direction peut sauvegarder", chiefSave.ok == true)
check("sauvegarde réellement demandée", world.saveRequested == true)

-- ─────────────────────────────────────────────────────────────
suite("Validation des charges utiles")
-- ─────────────────────────────────────────────────────────────
local badVehicleId = send(chief, "dispatch", { vehicleId = "1", incidentId = incident.id })
check("identifiant véhicule textuel refusé", badVehicleId.ok == false)
check("message de validation", string.find(badVehicleId.message, "invalide") ~= nil, badVehicleId.message)

local badIncident = send(chief, "dispatch", { vehicleId = fpt.id, incidentId = 12 })
check("identifiant intervention non textuel refusé", badIncident.ok == false)

local badQuantity = send(chief, "install_equipment", { vehicleId = fpt.id, equipmentId = "ARI", quantity = 0 })
check("quantité nulle refusée", badQuantity.ok == false)

local badTypeId = send(chief, "buy_vehicle", { typeId = 42 })
check("type de véhicule non textuel refusé", badTypeId.ok == false)

local badSector = send(chief, "create_sector", { name = "Secteur", x = "loin", z = 10, radius = 20 })
check("coordonnées non numériques refusées", badSector.ok == false)

local unknownAction = send(chief, "lancer_fusee", nil)
check("action inconnue refusée", unknownAction.ok == false)
check("message d'action inconnue", string.find(unknownAction.message, "inconnue") ~= nil, unknownAction.message)

local noPlayer = NetworkService.handle(world, nil, "dispatch", {})
check("joueur absent refusé", noPlayer.ok == false)
local badPlayer = NetworkService.handle(world, { UserId = "1001", Name = "X" }, "dispatch", {})
check("joueur mal formé refusé", badPlayer.ok == false)
local badPayload = NetworkService.handle(world, chief, "dispatch", "payload")
check("charge utile non tabulaire refusée", badPayload.ok == false)

-- En jeu, l'acteur est une Instance (`Player`), pas une table : la frontière
-- doit l'accepter sans exiger `type(player) == "table"`. Monde séparé pour ne
-- pas fausser les effectifs du monde principal.
local instanceWorld = WorldService.create(Config, catalogs, { seed = 777 })
instanceWorld.alarmCountdown = 1e9
local instancePlayer = Instance.new("Player")
instancePlayer.UserId = 2001
instancePlayer.Name = "JoueurInstance"
local fromInstance = NetworkService.handle(instanceWorld, instancePlayer, "request_snapshot", nil)
check("joueur Instance accepté", fromInstance.ok == true, fromInstance.message)
local notAPlayer = Instance.new("Folder")
notAPlayer.Name = "PasUnJoueur"
notAPlayer.UserId = 2002
local fromFolder = NetworkService.handle(instanceWorld, notAPlayer, "request_snapshot", nil)
check("Instance non-Player refusée", fromFolder.ok == false)

-- ─────────────────────────────────────────────────────────────
suite("Anti-spam")
-- ─────────────────────────────────────────────────────────────
world.players[1001].lastAction = os.clock()
local spam = NetworkService.handle(world, chief, "request_snapshot", nil)
check("deuxième action instantanée refusée", spam.ok == false, spam.message)
check("message anti-spam", string.find(spam.message, "Trop d'actions") ~= nil, spam.message)

world.players[1001].lastAction = -math.huge
local afterSpam = NetworkService.handle(world, chief, "request_snapshot", nil)
check("action autorisée après le délai", afterSpam.ok == true)

-- ─────────────────────────────────────────────────────────────
suite("Commandement réseau et cohérence")
-- ─────────────────────────────────────────────────────────────
local group = send(chief, "create_group", { name = "Groupe Feu", service = "fire" })
check("création de groupe via le réseau", group.ok == true, group.message)
local groupId = group.data.id
check("ajout d'un véhicule au groupe", send(chief, "add_to_group", { groupId = groupId, vehicleId = fpt.id }).ok == true)
check("ajout par un non-commandant refusé", send(firefighter, "add_to_group", { groupId = groupId, vehicleId = fpt.id }).ok == false)

local groupDispatch = send(chief, "dispatch_group", { groupId = groupId, incidentId = incident.id })
check("groupe déjà engagé : refus explicite", groupDispatch.ok == false, groupDispatch.message)

local purchase = send(chief, "buy_vehicle", { typeId = "VPC" })
check("achat réel via le réseau", purchase.ok == true, purchase.message)
check("budget débité", world.budget < Config.START_BUDGET)

local snapshot = SnapshotService.build(world)
check("snapshot multijoueur sérialisable", SnapshotService.isSerializable(snapshot) == true)
check("trois joueurs dans le snapshot", #snapshot.players == 3, #snapshot.players)
local roles = {}
for _, entry in ipairs(snapshot.players) do
	roles[entry.userId] = entry.role
end
check("rôles cohérents dans le snapshot", roles[1001] == Constants.ROLE.DIRECTION and roles[1002] == Constants.ROLE.INCENDIE)
check("libellés de rôle fournis", snapshot.players[1].roleLabel ~= nil)

-- Chaque joueur reçoit sa propre vision : le snapshot ne dépend pas du joueur,
-- mais les actions sont filtrées par PermissionService.
check("permissions direction complètes", PermissionService.can(world, 1001, Constants.ACTION.BUY_VEHICLE) == true)
check("permissions incendie restreintes", PermissionService.can(world, 1002, Constants.ACTION.BUY_VEHICLE) == false)
check("périmètre incendie", PermissionService.canVehicle(world, 1002, Constants.ACTION.DISPATCH, fpt) == true
	and PermissionService.canVehicle(world, 1002, Constants.ACTION.DISPATCH, vsav) == false)
check("périmètre observateur", PermissionService.canVehicle(world, 1003, Constants.ACTION.DISPATCH, fpt) == false)

-- ─────────────────────────────────────────────────────────────
print("")
do
	suite("Tours d'achat, formation et budget partagé")
	local second = {UserId = 1004, Name = "Commandement"}
	check("commandement prend un tour", send(second, "claim_role", {role = Constants.ROLE.COMMANDEMENT}).ok)
	local turn = SnapshotService.build(world).purchase
	check("direction en premier", turn.owner == chief.UserId and turn.count == 2)
	local initial = world.budget
	check("achat hors tour refusé", not send(second, "recruit_personnel", {profileId = "technician"}).ok)
	check("profil invalide refusé", not send(chief, "recruit_personnel", {profileId = {}}).ok)
	check("aucun débit sur refus", world.budget == initial and world.purchaseTurn.owner == chief.UserId)
	local hire = send(chief, "recruit_personnel", {profileId = "technician", price = 0})
	check("technicien recruté au prix serveur", hire.ok and hire.data.qualifications.TECHNICIEN
		and world.budget == initial - (1400 + turn.surcharge))
	turn = SnapshotService.build(world).purchase
	check("tour suivant et hausse effective", turn.owner == second.UserId and turn.surcharge == 60)
	check("direction ne peut doubler son tour", not send(chief, "buy_vehicle", {typeId = "VSAV"}).ok)
	check("observateur ne peut passer", not send(observer, "pass_purchase_turn", {}).ok)
	local personId = hire.data.id
	check("formation niveau 1", send(second, "train_personnel", {personId = personId}).ok and hire.data.level == 1)
	check("formation niveau 2", send(chief, "train_personnel", {personId = personId}).ok and hire.data.level == 2)
	check("formation niveau 3", send(second, "train_personnel", {personId = personId}).ok and hire.data.level == 3)
	local before = world.budget
	check("niveau plafond sans débit ni rotation", not send(chief, "train_personnel", {personId = personId}).ok
		and world.budget == before and world.purchaseTurn.owner == chief.UserId)
	check("passage manuel", send(chief, "pass_purchase_turn", {}).ok and world.purchaseTurn.owner == second.UserId)
	world.purchaseTurn.untilClock = os.clock() - 1
	check("passage à l'expiration", SnapshotService.build(world).purchase.owner == chief.UserId)
	world.players[chief.UserId].connected = false
	check("déconnexion du titulaire libère le tour", SnapshotService.build(world).purchase.owner == second.UserId)
	check("revente à moitié du prix payé", send(second, "transfer_personnel", {personId = personId}).ok
		and not world.personnel[personId] and world.budget == before + math.floor(hire.data.hireCost / 2))
	check("double cession refusée", not send(second, "transfer_personnel", {personId = personId}).ok)
end

print(string.format("  Multijoueur : %d réussite(s), %d échec(s)", passed, failed))
if failed > 0 then
	error(string.format("%d test(s) multijoueur en échec", failed))
end
