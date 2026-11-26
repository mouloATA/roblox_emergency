--!nonstrict
--[[
	Tests d'interface headless — construction, rendu et actions réelles.

	L'interface est montée sur un vrai monde serveur. Les clics sur les boutons
	passent par le contrôleur réseau, puis par `NetworkService.handle` : une
	action d'interface qui n'a pas d'effet serveur échoue donc ici.

	On vérifie aussi que les boutons désactivés n'envoient rien, que les
	retours du serveur deviennent des notifications, et que les listes sont
	réconciliées (mêmes lignes réutilisées entre deux snapshots).
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

local function near(a, b, epsilon)
	return math.abs((a or 0) - (b or 0)) <= (epsilon or 0.001)
end

local function suite(title)
	print("")
	print("  " .. title)
end

local function click(button)
	if not button then
		error("Bouton introuvable")
	end
	button.MouseButton1Click:Fire()
end

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local City = require(Shared:WaitForChild("City"))
local Catalogs = Shared:WaitForChild("Catalogs")
local Vehicles = require(Catalogs:WaitForChild("Vehicles"))
local Qualifications = require(Catalogs:WaitForChild("Qualifications"))
local Equipment = require(Catalogs:WaitForChild("Equipment"))
local Incidents = require(Catalogs:WaitForChild("Incidents"))
local Permissions = require(Catalogs:WaitForChild("Permissions"))

local Services = game:GetService("ServerScriptService"):WaitForChild("ERS"):WaitForChild("Services")
local WorldService = require(Services:WaitForChild("WorldService"))
local IncidentService = require(Services:WaitForChild("IncidentService"))
local SnapshotService = require(Services:WaitForChild("SnapshotService"))
local NetworkService = require(Services:WaitForChild("NetworkService"))
local PermissionService = require(Services:WaitForChild("PermissionService"))

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local ERSClient = player:WaitForChild("PlayerScripts"):WaitForChild("ERSClient")

local App = require(ERSClient:WaitForChild("UI"):WaitForChild("App"))
local Widgets = require(ERSClient:WaitForChild("UI"):WaitForChild("Widgets"))
local Theme = require(ERSClient:WaitForChild("UI"):WaitForChild("Theme"))
local InterfaceController = require(ERSClient:WaitForChild("Controllers"):WaitForChild("InterfaceController"))
local NetworkController = require(ERSClient:WaitForChild("Controllers"):WaitForChild("NetworkController"))
local CameraController = require(ERSClient:WaitForChild("Controllers"):WaitForChild("CameraController"))
local InputController = require(ERSClient:WaitForChild("Controllers"):WaitForChild("InputController"))
local AudioController = require(ERSClient:WaitForChild("Controllers"):WaitForChild("AudioController"))
local EngagementHints = require(ERSClient:WaitForChild("UI"):WaitForChild("EngagementHints"))

local stubs = __env.stubs

-- ─────────────────────────────────────────────────────────────
-- Monde et faux réseau (qui appelle le vrai serveur)
-- ─────────────────────────────────────────────────────────────
local catalogs = {
	vehicles = Vehicles,
	qualifications = Qualifications,
	equipment = Equipment,
	incidents = Incidents,
	permissions = Permissions,
}

local world = WorldService.create(Config, catalogs, { seed = 20260214 })
world.alarmCountdown = 1e9
world.config.ACTION_COOLDOWN = 0 -- pas d'anti-spam entre deux clics de test

local snapshotSignal = stubs.newSignal()
local feedbackSignal = stubs.newSignal()
local actions = {}

local remotes = {
	command = {
		FireServer = function(_self, action, payload)
			table.insert(actions, { action = action, payload = payload })
			local result = NetworkService.handle(world, player, action, payload)
			feedbackSignal:Fire(result)
			if result.ok then
				snapshotSignal:Fire(SnapshotService.build(world))
			end
			return result
		end,
	},
	snapshot = { OnClientEvent = snapshotSignal },
	feedback = { OnClientEvent = feedbackSignal },
	request = {
		InvokeServer = function()
			NetworkService.handle(world, player, "request_snapshot", nil)
			return SnapshotService.build(world)
		end,
	},
}

local function lastAction()
	local entry = actions[#actions]
	return entry and entry.action or nil
end

local function countAction(name)
	local total = 0
	for _, entry in ipairs(actions) do
		if entry.action == name then
			total += 1
		end
	end
	return total
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

local controller = InterfaceController.new({ player = player, catalogs = catalogs })

-- Même montage que `Bootstrap.client` : caméra et scène 3D avant l'interface.
local camera = CameraController.new({ camera = stubs.camera })
camera:mount()
do
	stubs.camera.CameraType = Enum.CameraType.Custom
	camera:syncCamera(stubs.camera)
	check("vue tactique restaurée après apparition du personnage", stubs.camera.CameraType == Enum.CameraType.Scriptable
		and stubs.camera.FieldOfView == Config.CAMERA_FOV)
	local replacement = Instance.new("Camera")
	camera:syncCamera(replacement)
	check("remplacement de la caméra Roblox pris en charge", replacement.CameraType == Enum.CameraType.Scriptable
		and replacement.FieldOfView == Config.CAMERA_FOV)
	camera:syncCamera(stubs.camera)
end
local SceneView = require(ERSClient:WaitForChild("UI"):WaitForChild("SceneView"))
local scene = SceneView.new({ workspace = game:GetService("Workspace") })

local audio = AudioController.new({
	soundService = game:GetService("SoundService"),
	config = Config,
})
audio:mount()

local app = App.create(playerGui, {
	controller = controller,
	player = player,
	camera = camera,
	scene = scene,
	audio = audio,
})
controller:setRenderer(function(state, snapshot)
	app:render(state, snapshot)
end)
local network = NetworkController.new(controller, remotes)
network:mount()
network:requestSnapshot()

-- ─────────────────────────────────────────────────────────────
suite("Coque et premier snapshot")
-- ─────────────────────────────────────────────────────────────
check("ScreenGui créé", app.gui.Name == "ERS" and app.gui.Parent == playerGui)
check("en-tête sous les commandes natives de Roblox", app.gui.ScreenInsets == Enum.ScreenInsets.CoreUISafeInsets)
check("racine plein écran", app.gui:FindFirstChild("Racine") ~= nil)
check("huit onglets", (function()
	local count = 0
	for _ in pairs(app.tabs) do
		count += 1
	end
	return count == 8
end)())
check("huit panneaux", (function()
	local count = 0
	for _ in pairs(app.panels) do
		count += 1
	end
	return count == 8
end)())
check("premier joueur = direction", world.players[player.UserId].role == Constants.ROLE.DIRECTION)
check("rôle lu depuis le snapshot", controller:role() == Constants.ROLE.DIRECTION)
check("direction peut acheter", controller:can("buy_vehicle") == true)
check("direction couvre tous les services", controller:canService("medical") == true)
check("barre d'état renseignée", string.find(app.status.Text, "Direction", 1, true) ~= nil, app.status.Text)
check("budget affiché", string.find(app.status.Text, "25 000", 1, true) ~= nil, app.status.Text)
check("trois marqueurs véhicule", (function()
	local count = 0
	for _ in pairs(app.map.markers.vehicles.entries) do
		count += 1
	end
	return count == 3
end)())
check("journal initial alimenté", (function()
	local count = 0
	for _ in pairs(app.logRows.entries) do
		count += 1
	end
	return count >= 1
end)())
check("tiroir fermé au démarrage", app.drawer.Visible == false)
check("barre inférieure visible", app.bottom.root.Visible ~= false)
-- Le journal ne doit pas passer sous la colonne d'onglets, plus haute.
check("journal à droite de la colonne d'onglets",
	app.logPanel.Position.X.Offset >= Theme.sizes.tabsCompact + 8,
	tostring(app.logPanel.Position.X.Offset))

-- ─────────────────────────────────────────────────────────────
suite("Menu principal et prise de poste")
-- ─────────────────────────────────────────────────────────────
check("menu ouvert au démarrage", controller.state.menuOpen == true and app.menu.root.Visible == true)
-- Mode Sibling : les enfants passent toujours au-dessus de leur parent, quel
-- que soit leur ZIndex. C'est ce qui rend visibles le contenu de la mini-carte
-- et de la barre, dont les conteneurs portent un ZIndex élevé.
check("interface en mode ZIndex Sibling",
	app.gui.ZIndexBehavior == stubs.Enum.ZIndexBehavior.Sibling)
check("menu au-dessus de la barre et du tiroir",
	app.menu.root.ZIndex > app.bottom.root.ZIndex and app.menu.root.ZIndex > app.drawer.ZIndex,
	string.format("menu=%s barre=%s tiroir=%s",
		tostring(app.menu.root.ZIndex), tostring(app.bottom.root.ZIndex), tostring(app.drawer.ZIndex)))
check("carte et boutons du menu dans le voile",
	app.menu.card.Parent == app.menu.root
		and app.menu.enterButton.Parent ~= nil
		and app.menu.roleButtons[Constants.ROLE.DIRECTION].Parent ~= nil)
check("sept postes proposés", (function()
	local count = 0
	for _ in pairs(app.menu.roleButtons) do
		count += 1
	end
	return count == 7
end)())
check("nouvelle partie proposée à la direction", app.menu.newGameButton.Visible == true)

click(app.menu.roleButtons[Constants.ROLE.INCENDIE])
check("prise de poste incendie via le menu", world.players[player.UserId].role == Constants.ROLE.INCENDIE)
check("poste incendie reflété", controller:role() == Constants.ROLE.INCENDIE)
check("le bouton du poste tenu est désactivé",
	app.menu.roleButtons[Constants.ROLE.INCENDIE].Active == false)
check("incendie ne peut pas acheter", controller:can("buy_vehicle") == false)
check("nouvelle partie masquée hors direction", app.menu.newGameButton.Visible == false)

click(app.menu.roleButtons[Constants.ROLE.DIRECTION])
check("retour à la direction", world.players[player.UserId].role == Constants.ROLE.DIRECTION)
check("direction de nouveau autorisée", controller:can("buy_vehicle") == true)
check("nouvelle partie de nouveau proposée", app.menu.newGameButton.Visible == true)

click(app.menu.newGameButton)
check("confirmation de nouvelle partie ouverte", app.menu.confirmPanel.Visible == true)
click(Widgets.find(app.menu.confirmPanel, "Action_cancel_new_game"))
check("annulation referme la confirmation", app.menu.confirmPanel.Visible == false)
check("annulation ne ferme pas le menu", controller.state.menuOpen == true)

click(app.menu.enterButton)
check("entrée en opération ferme le menu", controller.state.menuOpen == false and app.menu.root.Visible == false)

-- ─────────────────────────────────────────────────────────────
suite("Équipage et engagement d'un engin")
-- ─────────────────────────────────────────────────────────────
local fpt = vehicleOfType("FPT")
local vsav = vehicleOfType("VSAV")
local vpc = vehicleOfType("VPC")

click(app.tabs.vehicles)
check("onglet véhicules actif", controller.state.tab == "vehicles")
click(app.panels.vehicles.rows.entries[fpt.id].instance)
check("sélection d'un véhicule par sa ligne", controller.state.vehicleId == fpt.id)

local crewButton = Widgets.find(app.panels.vehicles.root, "Action_auto_crew")
click(crewButton)
check("équipage automatique réellement appliqué", #world.vehicles[fpt.id].crew == 4, #world.vehicles[fpt.id].crew)
check("action auto_crew envoyée", lastAction() == "auto_crew")
check("équipage visible dans le snapshot", #controller:selectedVehicle().crew == 4)

local spawned = IncidentService.spawn(world, "FEU_VEHICULE", { x = 18, z = 40 })
check("urgence créée côté serveur", spawned.ok == true, spawned.message)
local incident = spawned.data
controller:applySnapshot(SnapshotService.build(world))

click(app.tabs.incidents)
click(app.panels.incidents.rows.entries[incident.id].instance)
check("sélection d'une urgence", controller.state.incidentId == incident.id)
check("briefing affiché", #Incidents.get("FEU_VEHICULE").briefing > 20)
check("bouton d'engagement actif", app.panels.incidents.dispatchButton.Active == true)

click(app.panels.incidents.dispatchButton)
check("engagement réellement appliqué", world.incidents[incident.id].status == Constants.INCIDENT_STATUS.ACTIVE)
check("véhicule en route côté serveur", world.vehicles[fpt.id].status == Constants.VEHICLE_STATUS.DISPATCHED)
check("action dispatch envoyée", lastAction() == "dispatch")
check("bouton d'engagement désactivé après départ", app.panels.incidents.dispatchButton.Active == false)
check("bouton de rappel actif", app.panels.incidents.recallButton.Active == true)

-- Le trajet est une polyligne routière : la mini-carte doit dessiner un
-- segment par tronçon, et non un vol d'oiseau jusqu'à la destination.
local routeView = app.map.routes.entries[fpt.id]
local routePoints = world.vehicles[fpt.id].route and world.vehicles[fpt.id].route.points
check("trajet routier en polyligne côté serveur", routePoints ~= nil and #routePoints >= 3,
	routePoints and #routePoints or 0)
check("mini-carte : un segment par tronçon", routeView ~= nil and #routeView.segments == #routePoints - 1,
	routeView and #routeView.segments or -1)
check("mini-carte : segments de trajet visibles", routeView.segments[1] ~= nil
	and routeView.segments[1].Visible == true)

click(app.panels.incidents.recallButton)
check("rappel réellement appliqué",
	world.vehicles[fpt.id].status == Constants.VEHICLE_STATUS.RETURNING
		or world.vehicles[fpt.id].status == Constants.VEHICLE_STATUS.AVAILABLE,
	world.vehicles[fpt.id].status)
check("urgence libérée du véhicule rappelé", world.incidents[incident.id].assigned[fpt.id] == nil)
check("action recall envoyée", lastAction() == "recall")

-- ─────────────────────────────────────────────────────────────
suite("Aides d'engagement")
-- ─────────────────────────────────────────────────────────────
-- Le module explique une situation synthétique : aucun état serveur requis.
local noVehicleHint = EngagementHints.engageHint(nil, incident, true, true, false)
check("sans engin : invite à en choisir un", noVehicleHint ~= nil
	and string.find(noVehicleHint, "Sélectionnez un engin", 1, true) ~= nil, noVehicleHint)

local noIncidentHint = EngagementHints.engageHint(fpt, nil, true, true, false)
check("sans urgence : invite à en choisir une", noIncidentHint ~= nil
	and string.find(noIncidentHint, "Sélectionnez une intervention", 1, true) ~= nil, noIncidentHint)

local busyHint = EngagementHints.engageHint(
	{ typeId = "FPT", status = Constants.VEHICLE_STATUS.DISPATCHED, crewCount = 4, crewRequired = 4 },
	incident, true, true, false)
check("engin en route : statut lisible", busyHint ~= nil
	and string.find(busyHint, "En route", 1, true) ~= nil, busyHint)

local crewHint = EngagementHints.engageHint(
	{ typeId = "FPT", status = Constants.VEHICLE_STATUS.AVAILABLE, crewCount = 2, crewRequired = 4 },
	incident, true, true, false)
check("équipage incomplet chiffré", crewHint ~= nil
	and string.find(crewHint, "Équipage incomplet (2/4)", 1, true) ~= nil, crewHint)

local scopeHint = EngagementHints.engageHint(fpt, incident, true, false, false)
check("hors périmètre expliqué", scopeHint ~= nil
	and string.find(scopeHint, "périmètre", 1, true) ~= nil, scopeHint)

local closedHint = EngagementHints.engageHint(fpt, incident, true, true, true)
check("intervention close refusée", closedHint ~= nil
	and string.find(closedHint, "clôturée", 1, true) ~= nil, closedHint)

local capabilityHint = EngagementHints.missingCapabilities(
	{ typeId = "VPC", status = Constants.VEHICLE_STATUS.AVAILABLE, crewCount = 2, crewRequired = 2 },
	{ requires = { fire = 2, rescue = 1 } })
check("capacités manquantes listées", capabilityHint ~= nil
	and string.find(capabilityHint, "Incendie 2", 1, true) ~= nil
	and string.find(capabilityHint, "Sauvetage 1", 1, true) ~= nil, capabilityHint)

check("aucune alerte quand tout est réuni", EngagementHints.engageHint(fpt, incident, true, true, false) == nil)

-- Le panneau Interventions affiche la même phrase sans engin sélectionné.
controller:select("vehicle", nil)
controller:applySnapshot(SnapshotService.build(world))
check("panneau urgence : aide sans engin", string.find(
	app.panels.incidents.engagementHint.Text, "Sélectionnez un engin", 1, true) ~= nil,
	app.panels.incidents.engagementHint.Text)

click(app.tabs.vehicles)
click(app.panels.vehicles.rows.entries[vpc.id].instance)
check("panneau véhicule : équipage incomplet",
	string.find(app.panels.vehicles.engagementHint.Text, "Équipage incomplet", 1, true) ~= nil,
	app.panels.vehicles.engagementHint.Text)
check("barre inférieure : aide contextuelle",
	string.find(app.bottom.commandHint.Text, "Équipage incomplet", 1, true) ~= nil,
	app.bottom.commandHint.Text)

click(app.tabs.vehicles)
click(app.panels.vehicles.rows.entries[vsav.id].instance)
click(Widgets.find(app.panels.vehicles.root, "Action_auto_crew"))
check("VSAV armé par l'interface", #world.vehicles[vsav.id].crew == 3, #world.vehicles[vsav.id].crew)

-- ─────────────────────────────────────────────────────────────
suite("Groupes, secteurs et engagement groupé")
-- ─────────────────────────────────────────────────────────────
click(app.tabs.command)
check("onglet commandement actif", controller.state.tab == "command")

app.panels.command.nameBox.Text = "Groupe Nord"
click(app.panels.command.createGroupButton)
check("groupe créé par l'interface", world.groups[1] ~= nil)
check("action create_group envoyée", lastAction() == "create_group")
local groupId = 1
check("ligne de groupe rendue", app.panels.command.groupRows.entries[groupId] ~= nil)

click(app.panels.command.groupRows.entries[groupId].instance)
check("groupe sélectionné", controller.state.groupId == groupId)

click(app.tabs.vehicles)
click(app.panels.vehicles.rows.entries[vsav.id].instance)
click(app.tabs.command)
click(Widgets.find(app.panels.command.root, "Action_add_to_group"))
check("engin ajouté au groupe", #world.groups[groupId].vehicles == 1
	and world.groups[groupId].vehicles[1] == vsav.id)

app.panels.command.sectorBox.Text = "Secteur Nord"
click(app.panels.command.sectorButton)
check("secteur créé", world.sectors[1] ~= nil)
check("secteur centré sur l'urgence choisie", world.sectors[1].x == 18 and world.sectors[1].z == 40)

click(app.panels.command.sectorRows.entries[1].assign)
check("groupe affecté au secteur", world.sectors[1].groupId == groupId)
check("lien réciproque groupe/secteur", world.groups[groupId].sectorId == 1)

click(app.panels.command.groupRows.entries[groupId].engage)
check("engagement groupé réellement appliqué", world.vehicles[vsav.id].status == Constants.VEHICLE_STATUS.DISPATCHED)
check("action dispatch_group envoyée", lastAction() == "dispatch_group")

click(app.panels.command.groupRows.entries[groupId].dissolve)
check("groupe dissous par l'interface", world.groups[groupId] == nil)

-- ─────────────────────────────────────────────────────────────
suite("Budget, achat et sauvegarde")
-- ─────────────────────────────────────────────────────────────
click(app.tabs.budget)
check("onglet budget actif", controller.state.tab == "budget")
check("solde affiché en euros", string.find(app.panels.budget.root:FindFirstChild("Solde").Text, "€", 1, true) ~= nil)

local function use(panel, name)
	local node = Widgets.find(panel, name)
	local ancestor = node
	while ancestor do
		assert(ancestor.Visible ~= false, name .. " masqué dans " .. ancestor.Name)
		if ancestor == panel then break end
		ancestor = ancestor.Parent
	end
	click(node)
end

local function pricesInOrder(list, descending)
	local displayed = {}
	for _, row in ipairs(list:GetChildren()) do
		local label = row:FindFirstChild("Cout")
		if label then
			local digits = label.Text:gsub("[^0-9]", "")
			displayed[row.LayoutOrder] = { price = assert(tonumber(digits)), id = row.Name }
		end
	end
	for i = 2, #displayed do
		local a, b = displayed[i - 1], displayed[i]
		if a.price == b.price and a.id >= b.id then return false end
		if descending and a.price < b.price or not descending and a.price > b.price then return false end
	end
	return #displayed >= 2
end

do
	local shop = app.panels.budget
	local catalogue = Widgets.find(shop.root, "Catalogue")
	check("véhicules du moins cher au plus cher à l’ouverture", pricesInOrder(catalogue, false))
	catalogue.CanvasPosition = Vector2.new(0, 180)
	use(shop.root, "TriPrix_desc")
	check("prix décroissants et retour au début du catalogue", pricesInOrder(catalogue, true) and catalogue.CanvasPosition.Y == 0)
	for _, service in ipairs({"fire","medical","police","technical","command","logistics"}) do
		use(shop.root, "ServiceAchat_" .. service)
		local exact = true
		for _, def in ipairs(Vehicles.list) do
			if (shop.rows.entries[def.id] ~= nil) ~= (service == def.service) then exact = false end
		end
		check("catalogue exact du service " .. service, exact)
		check("tri décroissant conservé dans le service " .. service, pricesInOrder(catalogue, true))
	end
	controller:openCategory("medical")
	use(app.panels.vehicles.root, "OuvrirCatalogue")
	check("achat depuis une flotte filtrée", controller.state.tab == "budget" and shop.rows.entries.VSAV and not shop.rows.entries.FPT)
	local originalBudget = world.budget
	world.budget = 0
	controller:applySnapshot(SnapshotService.build(world))
	check("motif d’achat affiché si le solde est insuffisant", not shop.rows.entries.VSAV.buy.Active
		and shop.rows.entries.VSAV.buy.Text == "Solde insuffisant")
	world.budget = originalBudget
	controller:applySnapshot(SnapshotService.build(world))
	local row = shop.rows.entries.VSAV.instance
	controller:applySnapshot(SnapshotService.build(world))
	check("filtre et ligne conservés après un snapshot", shop.rows.entries.VSAV.instance == row and not shop.rows.entries.FPT)
	check("prix décroissants après actualisation", pricesInOrder(catalogue, true))
	use(shop.root, "TriPrix_asc")
	check("retour aux prix croissants dans le même service", pricesInOrder(catalogue, false) and not shop.rows.entries.FPT)
	controller:openCategory("all")
	use(app.panels.vehicles.root, "OuvrirCatalogue")
end

local beforeBuy = world.budget
local fleetBefore = 0
for _ in pairs(world.vehicles) do
	fleetBefore += 1
end
click(app.panels.budget.rows.entries.VSAV.buy)
check("achat réellement débité", world.budget == beforeBuy - Vehicles.get("VSAV").cost, world.budget)
check("flotte agrandie", (function()
	local count = 0
	for _ in pairs(world.vehicles) do
		count += 1
	end
	return count == fleetBefore + 1
end)())
check("action buy_vehicle envoyée", lastAction() == "buy_vehicle")

world.saveRequested = false
use(app.panels.budget.root, "VueBudget_ledger")
check("finances affichées seules", Widgets.find(app.panels.budget.root, "Corps").Visible
	and not Widgets.find(app.panels.budget.root, "Catalogue").Visible)
use(app.panels.budget.root, "Action_save")
use(app.panels.budget.root, "VueBudget_shop")
check("sauvegarde demandée au serveur", world.saveRequested == true)
check("action save envoyée", lastAction() == "save")

-- ─────────────────────────────────────────────────────────────
suite("Postes, attribution et restrictions")
-- ─────────────────────────────────────────────────────────────
click(app.tabs.roles)
click(app.panels.roles.roleButtons[Constants.ROLE.INCENDIE])
check("changement de poste via le panneau", world.players[player.UserId].role == Constants.ROLE.INCENDIE)
check("rôle mis à jour dans le contrôleur", controller:role() == Constants.ROLE.INCENDIE)

click(app.tabs.budget)
check("achat interdit au poste incendie", app.panels.budget.rows.entries.VPC.buy.Active == false)
local beforeForbiddenBuy = #actions
click(app.panels.budget.rows.entries.VPC.buy)
check("bouton désactivé : aucune intention envoyée", #actions == beforeForbiddenBuy)

click(app.tabs.roles)
click(app.panels.roles.roleButtons[Constants.ROLE.DIRECTION])
check("direction reprise", world.players[player.UserId].role == Constants.ROLE.DIRECTION)

PermissionService.seed(world, 2, "Invité")
controller:applySnapshot(SnapshotService.build(world))
check("deuxième joueur visible", app.panels.roles.playerRows.entries[2] ~= nil)
click(app.panels.roles.playerRows.entries[2].instance)
check("joueur cible sélectionné", controller.state.userId == 2)
click(app.panels.roles.roleButtons[Constants.ROLE.POLICE])
check("attribution réelle par la direction", world.players[2].role == Constants.ROLE.POLICE)
check("action assign_role envoyée", lastAction() == "assign_role")

click(app.panels.roles.observerButton)
check("passage en observateur réel", world.players[player.UserId].role == Constants.ROLE.OBSERVATEUR)
check("observateur sans droit d'achat", controller:can("buy_vehicle") == false)

click(app.tabs.incidents)
check("observateur : engagement désactivé", app.panels.incidents.dispatchButton.Active == false)
check("observateur : rappel désactivé", app.panels.incidents.recallButton.Active == false)
local beforeObserverClick = #actions
click(app.panels.incidents.dispatchButton)
click(app.panels.incidents.recallButton)
check("observateur : aucun clic ne part", #actions == beforeObserverClick)

-- ─────────────────────────────────────────────────────────────
suite("Notifications et retours serveur")
-- ─────────────────────────────────────────────────────────────
controller:clearToasts()
controller:command("buy_vehicle", { typeId = "VSAV" })
check("refus serveur transformé en notification", #controller.toasts == 1, #controller.toasts)
local toast = controller.toasts[1]
check("message de refus explicite", toast and string.find(toast.message, "autorisée", 1, true) ~= nil,
	toast and toast.message)
check("notification marquée en échec", toast and toast.ok == false)
check("ligne de notification rendue", toast and app.toastRows.entries[toast.id] ~= nil)
if toast then
	click(app.toastRows.entries[toast.id].close)
end
check("notification fermée par son bouton", #controller.toasts == 0)

for index = 1, 5 do
	controller:toast("Message " .. index, true)
end
check("notifications plafonnées à trois", #controller.toasts == 3, #controller.toasts)
check("les plus anciennes sont retirées", controller.toasts[3].message == "Message 5")
controller:clearToasts()

-- ─────────────────────────────────────────────────────────────
suite("Carte, liste réconciliée et raccourcis")
-- ─────────────────────────────────────────────────────────────
controller:setTab("budget")
click(app.map.markers.incidents.entries[incident.id].instance)
check("marqueur d'urgence : sélection et onglet", controller.state.incidentId == incident.id
	and controller.state.tab == "incidents")

click(app.map.markers.vehicles.entries[fpt.id].instance)
check("marqueur véhicule : sélection et onglet", controller.state.vehicleId == fpt.id
	and controller.state.tab == "vehicles")

local snapshotNow = SnapshotService.build(world)
controller:applySnapshot(snapshotNow)
local firstLogId = snapshotNow.log[1].id
check("journal identifié", firstLogId ~= nil)
local logInstance = app.logRows.entries[firstLogId].instance
local vehicleInstance = app.panels.vehicles.rows.entries[vsav.id].instance
controller:applySnapshot(snapshotNow)
check("lignes de journal réutilisées", app.logRows.entries[firstLogId].instance == logInstance)
check("lignes de véhicule réutilisées", app.panels.vehicles.rows.entries[vsav.id].instance == vehicleInstance)

check("caméra scriptée", stubs.camera.CameraType == Enum.CameraType.Scriptable)

camera:focus(incident.position.x, incident.position.z)
check("caméra braquée sur l'urgence", camera.target.x == incident.position.x
	and camera.target.z == incident.position.z)

-- Position d'orbite : au-dessus de la cible, décalée par le lacet et le pitch.
local orbit = camera:position()
local pitch = math.rad(Config.CAMERA_PITCH)
local horizontal = camera.distance * math.cos(pitch)
check("caméra en orbite isométrique",
	near(orbit.X, incident.position.x * Config.WORLD_SCALE + math.sin(math.rad(camera.yaw)) * horizontal, 0.01)
	and near(orbit.Y, camera.distance * math.sin(pitch), 0.01)
	and near(orbit.Z, incident.position.z * Config.WORLD_SCALE + math.cos(math.rad(camera.yaw)) * horizontal, 0.01),
	string.format("position %.1f/%.1f/%.1f", orbit.X, orbit.Y, orbit.Z))

local baseDistance = camera.distance
camera:zoom(-Config.CAMERA_ZOOM_STEP)
check("zoom avant rapproche", camera.distance == baseDistance - Config.CAMERA_ZOOM_STEP)
camera:zoom(-100000)
check("zoom borné au minimum", camera.distance == Config.CAMERA_DISTANCE_MIN)
camera:zoom(100000)
check("zoom borné au maximum", camera.distance == Config.CAMERA_DISTANCE_MAX)
camera:reset()

local baseYaw = camera.yaw
camera:rotate(1)
check("rotation par pas de 45°", camera.yaw == (baseYaw + 45) % 360)
camera:rotate(-1)
check("rotation inverse 45°", camera.yaw == baseYaw)

camera:pan(Config.CAMERA_PAN_STEP, 0)
check("déplacement horizontal de la cible", camera.target.x == Config.HQ_X + Config.CAMERA_PAN_STEP)
camera:pan(-100000, 0)
check("déplacement borné à la marge", camera.target.x == -Config.CAMERA_MARGIN)

camera:follow("engin-test")
camera:track(30, 40)
check("suivi recale la cible", camera.target.x == 30 and camera.target.z == 40)
camera:focus(10, 10)
check("braquer arrête le suivi", camera.followId == nil)

local footprint = camera:viewExtent()
check("emprise visible positive", footprint.width > 0 and footprint.height > 0
	and footprint.width > footprint.height)

local input = InputController.new(controller, app, camera)
input:mount()
local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.Three }, false)
check("raccourci 3 : personnel", controller.state.tab == "personnel")
UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.Four }, true)
check("saisie texte ignorée", controller.state.tab == "personnel")
input:handleKey(Enum.KeyCode.Up)
check("flèche haut déplace la caméra", camera.target.z < incident.position.z)
input:handleKey(Enum.KeyCode.R)
check("R recentre la caméra", camera.target.z == Config.HQ_Z)
check("R réinitialise le zoom", camera.distance == Config.CAMERA_DISTANCE)

local beforeZoom = camera.distance
input:handleKey(Enum.KeyCode.Equal)
check("+ rapproche la caméra", camera.distance == beforeZoom - Config.CAMERA_ZOOM_STEP)
input:handleKey(Enum.KeyCode.Minus)
check("- éloigne la caméra", camera.distance == beforeZoom)
input:handleKey(Enum.KeyCode.Q)
check("Q pivote la caméra", camera.yaw == (Config.CAMERA_YAW + 315) % 360)
input:handleKey(Enum.KeyCode.E)
check("E repivote dans l'autre sens", camera.yaw == Config.CAMERA_YAW)

local beforePanX = camera.target.x
input:handleKey(Enum.KeyCode.D)
check("D déplace vers l'est", camera.target.x > beforePanX)
input:handleKey(Enum.KeyCode.A)
check("A revient vers l'ouest", near(camera.target.x, beforePanX))

local beforeWheel = camera.distance
UserInputService.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseWheel, Position = { Z = 1 } })
check("molette zoome", camera.distance < beforeWheel)

controller:clearToasts()
local baseScale = controller.snapshot.timeScale or 1
input:handleKey(Enum.KeyCode.Space)
check("observateur : Espace ne change pas le temps", controller.snapshot.timeScale == baseScale
	and #controller.toasts == 1)

-- Le réglage du temps exige un poste de commandement : on reprend la direction.
world.players[player.UserId].role = Constants.ROLE.DIRECTION
controller:applySnapshot(SnapshotService.build(world))
controller:clearToasts()
input:handleKey(Enum.KeyCode.Space)
check("Espace met en pause", controller.snapshot.timeScale == 0)
input:handleKey(Enum.KeyCode.Space)
check("Espace reprend la simulation", controller.snapshot.timeScale == baseScale)

input:handleKey(Enum.KeyCode.M)
check("M ouvre le menu", controller.state.menuOpen == true)
input:handleKey(Enum.KeyCode.Escape)
check("Échap laissé au menu Roblox", controller.state.menuOpen == true)
controller:setMenu(false)
check("le menu se ferme par le bouton", controller.state.menuOpen == false)

controller:clearToasts()
world.saveRequested = false
UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.LeftControl }, false)
input:handleKey(Enum.KeyCode.S)
check("Ctrl+S sauvegarde pour la direction", world.saveRequested == true)
check("action save envoyée", lastAction() == "save")
UserInputService.InputEnded:Fire({ KeyCode = Enum.KeyCode.LeftControl })

world.players[player.UserId].role = Constants.ROLE.OBSERVATEUR
controller:applySnapshot(SnapshotService.build(world))
controller:clearToasts()
world.saveRequested = false
UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.LeftControl }, false)
input:handleKey(Enum.KeyCode.S)
check("observateur : Ctrl+S ne sauvegarde pas", world.saveRequested == false)
check("observateur : refus expliqué", #controller.toasts == 1
	and string.find(controller.toasts[1].message, "sauvegarder", 1, true) ~= nil)
UserInputService.InputEnded:Fire({ KeyCode = Enum.KeyCode.LeftControl })
input:unmount()

-- ─────────────────────────────────────────────────────────────
suite("Plan de ville, mini-carte, scène et barre inférieure")
-- ─────────────────────────────────────────────────────────────
local planA = City.build(Config.CITY_SEED)
local planB = City.build(Config.CITY_SEED)
check("dix routes (5 avenues, 5 rues)", #planA.roads == 10)
check("seize îlots", #planA.blocks == 16)
check("six points d'intérêt dont l'église", #planA.pois == 6)
check("cinq quartiers", #planA.districts == 5)
check("deux espaces publics", #planA.parks == 2)
check("huit places de stationnement", #planA.bays == 8)

local barracksBlock = nil
for _, block in ipairs(planA.blocks) do
	if block.kind == "caserne" then
		barracksBlock = block
	end
end
check("bloc de caserne repéré", barracksBlock ~= nil)
check("caserne autour du point de départ", barracksBlock ~= nil
	and Config.HQ_X > barracksBlock.x0 and Config.HQ_X < barracksBlock.x1
	and Config.HQ_Z > barracksBlock.z0 and Config.HQ_Z < barracksBlock.z1)

check("plan reproductible", #planA.buildings == #planB.buildings
	and #planA.trees == #planB.trees
	and planA.buildings[1].x0 == planB.buildings[1].x0
	and planA.buildings[1].facadeName == planB.buildings[1].facadeName)

local inside = true
for _, item in ipairs(planA.roads) do
	if item.axis == "avenue" then
		inside = inside and item.x > 0 and item.x < City.WIDTH
	else
		inside = inside and item.z > 0 and item.z < City.WIDTH
	end
end
check("voirie dans les limites de la carte", inside)
check("stationnement cyclique", City.bayPosition(planA, 1).id == 1
	and City.bayPosition(planA, 9).id == 1
	and City.bayPosition(planA, 8).id == 8)

-- Mini-carte : elle lit le même plan que le serveur.
check("mini-carte issue du plan partagé", app.map.plan ~= nil and #app.map.plan.roads == 10)
check("marqueur de véhicule sur la carte", app.map.markers.vehicles.entries[fpt.id] ~= nil)
check("marqueur d'urgence sur la carte", app.map.markers.incidents.entries[incident.id] ~= nil)

controller:applySnapshot(SnapshotService.build(world))
check("cadre de visée affiché", app.map.viewFrame.Visible == true)

-- La carte se réduit sur les fenêtres courtes au lieu de passer sous la barre.
check("mini-carte à l'échelle sur grand écran", (function()
	app.gui.AbsoluteSize = Vector2.new(1356, 888)
	app:render(controller.state, controller.snapshot)
	return app.map.root.Size.X.Offset == Theme.sizes.minimapWidth
end)())
check("mini-carte réduite sur fenêtre courte", (function()
	app.gui.AbsoluteSize = Vector2.new(900, 560)
	app:render(controller.state, controller.snapshot)
	return app.map.root.Size.Y.Offset <= 560 - Theme.sizes.topBar - Theme.sizes.bar - 24
		and app.map.root.Size.X.Offset < Theme.sizes.minimapWidth
		and app.map.layerButtons.personnel.TextSize >= 12
end)())
do
	-- Résout les UDim2, l'ancrage, le padding et l'UIScale de l'arbre monté.
	-- Les doublures ne calculent pas AbsoluteSize pour les descendants.
	local function bounds(node, width, height)
		if node == app.gui then return {x=0, y=0, w=width, h=height, zoom=1} end
		if node == app.topGui then return {x=168, y=-58, w=width-168, h=58, zoom=1} end
		local p = bounds(node.Parent, width, height)
		local x, y, w, h = p.x, p.y, p.w, p.h
		local pad = node.Parent:FindFirstChildOfClass("UIPadding")
		if pad then
			x += p.zoom * pad.PaddingLeft.Offset
			y += p.zoom * pad.PaddingTop.Offset
			w -= p.zoom * (pad.PaddingLeft.Offset + pad.PaddingRight.Offset)
			h -= p.zoom * (pad.PaddingTop.Offset + pad.PaddingBottom.Offset)
		end
		local size, pos = node.Size, node.Position
		local scale = node:FindFirstChildOfClass("UIScale")
		local own = scale and scale.Scale or 1
		local nw = (size.X.Scale * w + size.X.Offset * p.zoom) * own
		local nh = (size.Y.Scale * h + size.Y.Offset * p.zoom) * own
		return {x=x + pos.X.Scale*w + pos.X.Offset*p.zoom - nw*node.AnchorPoint.X,
			y=y + pos.Y.Scale*h + pos.Y.Offset*p.zoom - nh*node.AnchorPoint.Y,
			w=nw, h=nh, zoom=p.zoom*own}
	end
	-- Le tiroir de flotte s'ouvre depuis la colonne et depuis les catégories du pupitre.
	-- Vérifie le passage direct d'un onglet à l'autre dans les deux cas.
	for _, resolution in ipairs({{1904,794},{1904,734},{1024,768},{900,560},{812,600},{560,700},{2560,1440}}) do
		local w, h = resolution[1], resolution[2]
		local suffix = string.format(" %d × %d", w, h)
		app.gui.AbsoluteSize = Vector2.new(w,h)
		controller:render()
		local nav = bounds(Widgets.find(app.root, "Onglets"), w, h)
		local function accessible(id)
			local box = bounds(app.drawer, w, h)
			return app.drawer.Visible and app.panels[id].root.Visible and box.w > 0
				and box.x >= nav.x + nav.w + 1 and box.x + box.w <= w
				and box.y + box.h < bounds(app.bottom.root, w, h).y
		end
		controller:openCategory("medical")
		check("flotte filtrée à droite du menu" .. suffix, accessible("vehicles"))
		local viewport = Widgets.find(app.drawer, "FenetreTiroir")
		local viewportWidth = bounds(viewport, w, h).w
		local content = bounds(Widgets.find(viewport, "ContenuTiroir"), w, h)
		check("commandes de flotte accessibles dans le tiroir" .. suffix,
			viewport.ClipsDescendants and viewport.ScrollingDirection == Enum.ScrollingDirection.X
			and viewport.ScrollingEnabled == (content.w > viewportWidth + 0.01)
			and content.w >= 800 and near(viewport.CanvasSize.X.Offset * content.zoom, content.w))
		if viewport.ScrollingEnabled then
			viewport.CanvasPosition = Vector2.new(120, 0)
			controller:render()
			check("lecture conservée dans la flotte" .. suffix, viewport.CanvasPosition.X == 120)
			click(app.tabs.missions)
			check("nouvel onglet affiché depuis le début" .. suffix, viewport.CanvasPosition.X == 0)
		end
		for _, id in ipairs({"vehicles","incidents","command","missions","roles","budget","equipment","personnel"}) do
			click(app.tabs[id])
			check("navigation latérale accessible dans " .. id .. suffix, accessible(id))
		end
		controller:closeDrawer()
	end
	for _, resolution in ipairs({{1024,768},{1280,720},{1920,1080},{2560,1440}}) do
		local w, h = resolution[1], resolution[2]
		local suffix = string.format(" %d × %d", w, h)
		app.gui.AbsoluteSize = Vector2.new(w,h)
		app:render(controller.state, controller.snapshot)
		local function rect(node) return bounds(node,w,h) end
		local function inside(a,b)
			return a.x+0.01 >= b.x and a.y+0.01 >= b.y and a.x+a.w <= b.x+b.w+0.01 and a.y+a.h <= b.y+b.h+0.01
		end
		local mapBox, journal, radio = rect(app.map.root), rect(app.logPanel), rect(app.radioPanel)
		local tab = rect(Widgets.find(app.root,"Onglets"))
		local bottom = rect(app.bottom.root)
		local screen = rect(app.root)
		check("HUD plein écran" .. suffix, near(screen.w,w) and near(screen.h,h))
		check("carte au-dessus des commandes" .. suffix, inside(mapBox,screen) and mapBox.y+mapBox.h < bottom.y)
		check("onglets et radio dégagés" .. suffix, tab.x+tab.w < radio.x and radio.x+radio.w < mapBox.x)
		check("journal et carte distincts" .. suffix, journal.x+journal.w < mapBox.x and tab.x+tab.w < journal.x)
		check("journal au-dessus des commandes" .. suffix, journal.y+journal.h < bottom.y)
		controller:setTab("budget")
		local drawer = rect(app.drawer)
		local catalogue = rect(Widgets.find(app.panels.budget.root, "Catalogue"))
		check("achats dégagés de la navigation et du pupitre" .. suffix,
			drawer.x > tab.x + tab.w and drawer.y + drawer.h < bottom.y and inside(catalogue, drawer) and catalogue.h > 175)
		local filters = rect(Widgets.find(app.panels.budget.root, "ServiceAchat"))
		local balance = rect(Widgets.find(app.panels.budget.root, "Solde"))
		local modes = rect(Widgets.find(app.panels.budget.root, "VueBudget"))
		check("filtres et solde dégagés du catalogue" .. suffix, filters.y + filters.h < catalogue.y and modes.x + modes.w <= balance.x)
		controller:toast("Véhicule acheté.", true)
		check("confirmation lisible au-dessus des contrôles" .. suffix, Widgets.find(app.drawer, "RetourAction").Visible
			and not Widgets.find(app.root, "Notifications").Visible and rect(Widgets.find(app.drawer,"RetourAction")).y < modes.y)
		controller:clearToasts()
		controller:closeDrawer()
		local previousRight = -1
		for _, name in ipairs({"Moyens","GroupesTemps","CommandesContextuelles","Personnel"}) do
			local panel = Widgets.find(app.bottom.root,name)
			local box = rect(panel)
			check("pupitre " .. name .. suffix, inside(box,bottom) and box.x>previousRight and box.w>140)
			previousRight = box.x+box.w
			for _, button in ipairs(panel:GetChildren()) do
				if button.ClassName == "TextButton" then
					local boxButton = rect(button)
					check("commande " .. button.Name .. suffix, inside(boxButton,box) and boxButton.w >= 22)
				end
			end
		end
		check("barre à côté des commandes Roblox" .. suffix,
			app.topGui.ScreenInsets == Enum.ScreenInsets.TopbarSafeInsets
			and rect(app.topBar).x > 168 and rect(app.topBar).y >= -58
			and rect(app.topBar).y + rect(app.topBar).h <= 0)
		local minFont = math.huge
		for _, node in ipairs(app.root:GetDescendants()) do
			if (node.ClassName == "TextLabel" or node.ClassName == "TextButton") and node.Text ~= "" then
				minFont = math.min(minFont,node.TextSize*rect(node).zoom)
			end
		end
		check("polices effectives >= 12 px" .. suffix, minFont >= 12, minFont)
		check("transmission radio sur deux lignes" .. suffix, rect(app.radioPanel).h >= 2*13*screen.zoom
			and Widgets.find(app.radioPanel,"Transmission").TextWrapped)
	end
end
do
	local roster = app.panels.personnel.root
	controller:setTab("personnel")
	for _, viewport in ipairs({{812, 600}, {560, 700}}) do
		app.gui.AbsoluteSize = Vector2.new(viewport[1], viewport[2])
		controller:render()
		local columns = Widgets.find(roster, "ColonneDetail").Position
		check("espace de gestion exploitable en fenêtre de " .. viewport[1],
			app.drawer.Position.X.Offset >= Theme.sizes.tabsCompact + 16 and app.drawer.Size.Y.Offset >= 320
			and (columns.Y.Scale > 0) == (viewport[1] - app.drawer.Position.X.Offset - 32 < 620))
	end
	controller:closeDrawer()
end
app.gui.AbsoluteSize = Vector2.new(1356, 888)
app:render(controller.state, controller.snapshot)

click(app.map.layerButtons.units)
check("couche unités masquée", controller.state.layers.units == false)
check("marqueurs d'engins masqués", app.map.markers.vehicles.entries[fpt.id].instance.Visible == false)
click(app.map.layerButtons.units)
check("couche unités rétablie", controller.state.layers.units == true
	and app.map.markers.vehicles.entries[fpt.id].instance.Visible == true)

click(app.map.layerButtons.buildings)
check("couche bâtiments désactivable", controller.state.layers.buildings == false)
click(app.map.layerButtons.buildings)
check("couche bâtiments réactivée", controller.state.layers.buildings == true)

-- Scène 3D : engins et urgences générés par code.
controller:select("vehicle", vsav.id)
controller:applySnapshot(SnapshotService.build(world))
local vsavView = app.scene.vehicles.entries[vsav.id]
check("engin 3D créé", vsavView ~= nil and vsavView.body ~= nil and vsavView.light ~= nil)
check("anneau vert sur l'engin sélectionné", vsavView ~= nil and vsavView.ring.Transparency == 0.55)
check("urgence 3D créée", app.scene.incidents.entries[incident.id] ~= nil)
local beacon = app.scene.incidents.entries[incident.id].beacon
check("balise au-dessus du sol", beacon ~= nil and beacon.Position.Y > 0)

do
	local workspace = game:GetService("Workspace")
	local cityScene = require(Services:WaitForChild("SceneService")).build(Config, workspace)
	local buildings = cityScene:FindFirstChild("Batiments")
	check("église et hôpital reconnaissables en 3D", buildings:FindFirstChild("Clocher") ~= nil
		and buildings:FindFirstChild("ToitNef") ~= nil and buildings:FindFirstChild("AuventUrgences") ~= nil)
	check("immeubles et caserne détaillés", buildings:FindFirstChild("Balcon") ~= nil
		and cityScene:FindFirstChild("Caserne"):FindFirstChild("TourDeSechage") ~= nil)
	check("portes arrière du VSAV", vsavView.folder:FindFirstChild("PortesSanitaires") ~= nil)
	local models = require(ERSClient:WaitForChild("UI"):WaitForChild("StreetModels"))
	local marker = { EPA = "Echelon", BEA = "Nacelle", CCGC = "Citerne", MOTO = "Guidon", VPC = "MatRadio" }
	for _, definition in ipairs(Vehicles.list) do
		local built = models.vehicle(workspace, "Essai", definition.id, definition.service)
		check("carrosserie " .. definition.id, built.body and built.light and built.model:FindFirstChild("Pneu")
			and (not marker[definition.id] or built.model:FindFirstChild(marker[definition.id]) ~= nil))
		built.model:Destroy()
	end
	local traffic = require(ERSClient:WaitForChild("UI"):WaitForChild("StreetTraffic"))
	local state = scene.traffic
	local cars, walkers = 0, 0
	for _, actor in ipairs(state.actors) do
		if actor.walking then walkers += 1 else cars += 1 end
		local x1, z1 = traffic.sample(actor.route, 0)
		local x2, z2 = traffic.sample(actor.route, actor.route.duration)
		check("continuité du parcours civil", near(x1, x2) and near(z1, z2))
	end
	check("population de la ville", cars == 8 and walkers == 8)
	local route = state.actors[1].route
	local section = route.sections[1]
	check("départ sur la voie de droite", section.z > City.STREETS[1] and section.z < City.STREETS[1] + City.ROAD_HALF)
	local stopTime = section.run - 3 / section.v
	local xa, za = traffic.sample(route, stopTime)
	local xb, zb = traffic.sample(route, stopTime + section.pause * 0.5)
	check("arrêt avant le carrefour", near(xa, xb) and near(za, zb))
	traffic.sync(state, {time = 12, timeScale = 1})
	traffic.step(state, 0.2)
	local previous = state.actors[1].model.WorldPivot.Position
	traffic.step(state, 0.5)
	local moved = state.actors[1].model.WorldPivot.Position
	check("voiture en mouvement", moved.X ~= previous.X or moved.Z ~= previous.Z)
	traffic.sync(state, {time = 12.7, timeScale = 0})
	traffic.step(state, 0.1)
	local frozen = state.actors[1].model.WorldPivot
	traffic.step(state, 0.5)
	check("circulation suspendue en pause", state.actors[1].model.WorldPivot == frozen)
	local fake = {id = 999, x = 9, z = 15, status = Constants.INCIDENT_STATUS.ACTIVE,
		fireCells = {{x = 9, z = 15, heat = 60, burning = true}}}
	scene:update({incidents = {fake}, vehicles = {}})
	local visual = scene.incidents.entries[999]
	check("foyer actif dessiné", visual.cells[1] ~= nil and visual.cells[1].fire.Size > 3)
	fake.fireCells[1].burning = false
	scene:update({incidents = {fake}, vehicles = {}})
	check("foyer éteint retiré", next(visual.cells) == nil)
	controller:applySnapshot(SnapshotService.build(world))
	vsavView = scene.vehicles.entries[vsav.id]
	cityScene:Destroy()
end

local firstX = vsavView.x
vsavView.targetX = firstX + 10
scene:step(0.5)
check("interpolation vers la cible", vsavView.x > firstX and vsavView.x <= firstX + 10)

controller:select("vehicle", fpt.id)
controller:applySnapshot(SnapshotService.build(world))
check("anneau retiré des engins non sélectionnés", vsavView.ring.Transparency == 1
	and app.scene.vehicles.entries[fpt.id].ring.Transparency == 0.55)

-- Barre inférieure : compteurs réels par service.
local fireCount = 0
for _, vehicle in ipairs(controller.snapshot.vehicles or {}) do
	if vehicle.service == "fire" then
		fireCount += 1
	end
end
check("compteur incendie de la barre", tonumber(app.bottom.categories.fire.count.Text) == fireCount)

click(app.bottom.categories.medical.instance)
check("catégorie SAP ouvre le tiroir filtré", controller.state.drawer == "vehicles"
	and controller.state.category == "medical")
click(app.tabs.incidents)

check("aucun groupe après dissolution", #(controller.snapshot.groups or {}) == 0)
controller:clearToasts()
click(app.bottom.groups[1])
check("groupe absent signalé", #controller.toasts == 1
	and string.find(controller.toasts[1].message, "Aucun groupe", 1, true) ~= nil)

-- Vitesse : refusée à l'observateur, acceptée à la direction.
controller:clearToasts()
local scaleBefore = controller.snapshot.timeScale
click(app.bottom.time.speeds[2])
check("observateur : vitesse refusée", controller.snapshot.timeScale == scaleBefore
	and #controller.toasts == 1)

world.players[player.UserId].role = Constants.ROLE.DIRECTION
controller:applySnapshot(SnapshotService.build(world))
click(app.bottom.time.speeds[2])
check("vitesse ×2 validée par le serveur", controller.snapshot.timeScale == 2)
click(app.bottom.time.speeds[1])
check("retour à la vitesse normale", controller.snapshot.timeScale == 1)
click(app.bottom.time.pause)
check("bouton pause accepté", controller.snapshot.timeScale == 0)
click(app.bottom.time.pause)
check("bouton pause reprend", controller.snapshot.timeScale == 1)

-- Commandes contextuelles : elles n'agissent que sur une sélection réelle.
controller:select("vehicle", vsav.id)
controller:select("incident", incident.id)
controller:applySnapshot(SnapshotService.build(world))
check("contexte de commande renseigné", string.find(app.bottom.commandContext.Text, vsav.callsign, 1, true) ~= nil)
check("bouton CENTRER actif", app.bottom.commands.center.Active == true)

click(app.bottom.commands.follow)
check("SUIVRE active le suivi caméra", camera.followId == vsav.id)
click(app.bottom.commands.follow)
check("SUIVRE désactive le suivi", camera.followId == nil)

click(app.bottom.commands.sheet)
check("FICHE ouvre l'onglet véhicules", controller.state.tab == "vehicles")

-- Sans engin sélectionné, CENTRER se rabat sur l'urgence sélectionnée.
controller:select("vehicle", nil)
controller:applySnapshot(SnapshotService.build(world))
camera:focus(0, 0)
click(app.bottom.commands.center)
check("CENTRER braque la caméra sur l'incident",
	near(camera.target.x, incident.position.x) and near(camera.target.z, incident.position.z))

-- Panneau personnel : il reprend l'équipage de l'engin sélectionné.
controller:select("vehicle", vsav.id)
controller:applySnapshot(SnapshotService.build(world))
check("panneau personnel nomme l'engin",
	string.find(app.bottom.crew.unitLabel.Text, vsav.callsign, 1, true) ~= nil)
check("membres de l'équipage listés", app.bottom.crew.crewRows[1].Text ~= "")

-- ─────────────────────────────────────────────────────────────
suite("Mise en page des listes")
-- ─────────────────────────────────────────────────────────────
-- Une taille `UDim2.new(1, 0, 0, 0.34)` donne 0,34 pixel de haut : la liste
-- existe mais reste invisible. La hauteur doit être portée par l'échelle.
local lists = {
	{ label = "interventions", panel = app.panels.incidents, name = "Liste" },
	{ label = "véhicules", panel = app.panels.vehicles, name = "Liste" },
	{ label = "personnel", panel = app.panels.personnel, name = "Liste" },
	{ label = "matériel", panel = app.panels.equipment, name = "Stock" },
}
for _, entry in ipairs(lists) do
	local scroller = Widgets.find(entry.panel.root, entry.name)
	local height = scroller and scroller.Size.Y or nil
	check("liste " .. entry.label .. " présente", scroller ~= nil)
	check("liste " .. entry.label .. " dimensionnée", height ~= nil and height.Scale > 0.2,
		height and tostring(height.Scale))
	check("liste " .. entry.label .. " sans hauteur en pixels", height ~= nil and math.abs(height.Offset) < 40,
		height and tostring(height.Offset))
end

-- Le tiroir est large mais peu haut : ses panneaux doivent défiler à
-- l'intérieur au lieu de déborder sur la barre inférieure.
check("tiroir qui coupe ses descendants", app.drawer.ClipsDescendants == true)
check("tiroir assez haut pour les fiches", Theme.sizes.drawerHeight >= 320)
for _, entry in ipairs({
	{ label = "interventions", panel = app.panels.incidents },
	{ label = "véhicules", panel = app.panels.vehicles },
	{ label = "personnel", panel = app.panels.personnel },
}) do
	local detail = Widgets.find(entry.panel.root, "Detail")
	check("détail " .. entry.label .. " défilable",
		detail ~= nil and detail.ClassName == "ScrollingFrame")
end
for _, entry in ipairs({
	{ label = "commandement", panel = app.panels.command },
	{ label = "budget", panel = app.panels.budget },
	{ label = "postes", panel = app.panels.roles },
}) do
	local body = Widgets.find(entry.panel.root, "Corps")
	check("corps " .. entry.label .. " défilable",
		body ~= nil and body.ClassName == "ScrollingFrame")
end

-- ─────────────────────────────────────────────────────────────
suite("Nouvelle partie depuis le menu")
-- ─────────────────────────────────────────────────────────────
world.players[player.UserId].role = Constants.ROLE.DIRECTION
controller:setMenu(true)
controller:applySnapshot(SnapshotService.build(world))
check("bouton nouvelle partie visible pour la direction", app.menu.newGameButton.Visible == true)

world.budget = 4321
world.time = 77
click(app.menu.newGameButton)
check("confirmation demandée", app.menu.confirmPanel.Visible == true)
click(Widgets.find(app.menu.confirmPanel, "Action_cancel_new_game"))
check("annulation sans effet sur la partie", world.budget == 4321 and world.time == 77)

click(app.menu.newGameButton)
click(Widgets.find(app.menu.confirmPanel, "Action_confirm_new_game"))
check("nouvelle partie appliquée par le serveur", world.budget == Config.START_BUDGET and world.time == 0,
	string.format("budget=%s temps=%s", tostring(world.budget), tostring(world.time)))
check("action new_game envoyée", lastAction() == "new_game")
check("menu refermé après confirmation", controller.state.menuOpen == false)

do
	click(app.tabs.personnel)
	local panel = app.panels.personnel.root
	use(panel, "VuePersonnel_recruit")
	local offers = Widgets.find(panel, "Offres")
	check("recrutement par tarif croissant à l’ouverture", pricesInOrder(offers, false))
	use(panel, "TriPrix_desc")
	check("recrutement par tarif décroissant", pricesInOrder(offers, true))
	use(panel, "ServicePersonnel_medical")
	check("recrutement médical trié par tarif décroissant", pricesInOrder(offers, true) and not Widgets.find(offers, "Offre_technician"))
	use(panel, "TriPrix_asc")
	check("recrutement médical trié par tarif croissant", pricesInOrder(offers, false))
	use(panel, "ServicePersonnel_technical")
	check("le recrutement technique isole le technicien", Widgets.find(panel, "Offre_technician") and not Widgets.find(panel, "Offre_doctor"))
	local offer = Widgets.find(panel, "Offre_technician")
	local id = world.nextPersonnelId
	local before = world.budget
	check("tarif du recrutement affiché", string.find(offer:FindFirstChild("Cout").Text, "1 400", 1, true) ~= nil)
	use(panel, "Action_recruit_technician")
	check("recrutement par le panneau", lastAction() == "recruit_personnel" and world.personnel[id] ~= nil)
	use(panel, "VuePersonnel_roster")
	check("effectif filtré et fiche séparée des offres", Widgets.find(panel, "Garde").Visible and not Widgets.find(panel, "Offres").Visible)
	use(panel, "PersonnelLigne_" .. id)
	use(panel, "ServicePersonnel_medical")
	check("la fiche ne montre pas un agent d’un autre service", not Widgets.find(panel, "Action_train_personnel").Visible)
	use(panel, "ServicePersonnel_technical")
	local training = Widgets.find(panel, "Action_train_personnel")
	click(training)
	check("formation depuis la fiche", lastAction() == "train_personnel" and world.personnel[id].level == 1)
	click(Widgets.find(panel, "Action_transfer_personnel"))
	check("cession depuis la fiche", lastAction() == "transfer_personnel"
		and world.personnel[id] == nil and world.budget == before - 1400 - 500 + 700)
	click(app.tabs.budget)
	check("inflation répercutée sur le catalogue", Widgets.find(app.panels.budget.root, "Achat_VSAV")
		:FindFirstChild("Cout").Text == Theme.money(Vehicles.get("VSAV").cost + 30))
	click(app.tabs.personnel)
	use(panel, "ServicePersonnel_fire")
	local sapeur
	for _, person in ipairs(controller.snapshot.personnel) do
		if person.service == "fire" and not person.vehicleId then sapeur = person break end
	end
	use(panel, "PersonnelLigne_" .. sapeur.id)
	controller:select("vehicle", nil)
	use(panel, "Action_assign_personnel")
	local pumpId = vehicleOfType("FPT").id
	check("choix des affectations admissibles", Widgets.find(panel, "ChoixAffectation").Visible
		and not Widgets.find(panel, "Affecter_" .. vehicleOfType("VSAV").id))
	use(panel, "Affecter_" .. pumpId)
	check("affectation réelle depuis la fiche", world.personnel[sapeur.id].vehicleId == pumpId and Widgets.find(panel, "Detail").Visible)
	use(panel, "Action_unassign_personnel")
	check("retrait depuis la même fiche", world.personnel[sapeur.id].vehicleId == nil)
	local store = app.panels.equipment.root
	click(app.tabs.equipment)
	controller:select("vehicle", nil)
	use(store, "FamilleMateriel_medical")
	check("le magasin filtre par usage", Widgets.find(store, "Stock_SAC_SECOURS") and not Widgets.find(store, "Stock_TUYAU"))
	use(store, "Action_installer_SAC_SECOURS")
	check("choix d’un engin depuis le rayon", Widgets.find(store, "Engins").Visible)
	local pump = vehicleOfType("FPT")
	use(store, "Choisir_" .. pump.id)
	check("retour au rayon avec le véhicule choisi", Widgets.find(store, "Stock").Visible and controller.state.vehicleId == pump.id)
	-- Le PC mobile initial est embarqué dans le VPC. Le déposer rend l’offre visible.
	use(store, "VueMateriel_fleet")
	use(store, "Choisir_" .. vehicleOfType("VPC").id)
	use(store, "VueMateriel_loaded")
	use(store, "Action_deposer_PC_MOBILE")
	use(store, "VueMateriel_fleet")
	use(store, "Choisir_" .. pump.id)
	use(store, "VueMateriel_stock")
	use(store, "FamilleMateriel_support")
	local pc = Widgets.find(store, "Action_installer_PC_MOBILE")
	check("le matériel incompatible est identifié avant l’installation", pc ~= nil and not pc.Active and pc.Text == "Incompatible")
	use(store, "FamilleMateriel_medical")
	local stock = world.equipmentStock.SAC_SECOURS
	use(store, "Action_installer_SAC_SECOURS")
	check("installation depuis la catégorie médicale", world.equipmentStock.SAC_SECOURS == stock - 1)
	use(store, "VueMateriel_loaded")
	use(store, "Action_deposer_SAC_SECOURS")
	check("dépose depuis la vue embarquée", world.equipmentStock.SAC_SECOURS == stock)
	use(store, "VueMateriel_stock")
	use(store, "FamilleMateriel_security")
	check("rayon vide expliqué", Widgets.find(store, "Vide").Visible)
	click(app.tabs.budget)
	local alternate = {UserId = 17831, Name = "Relève"}
	NetworkService.handle(world, alternate, "claim_role", {role = Constants.ROLE.COMMANDEMENT})
	controller:applySnapshot(SnapshotService.build(world))
	local pass = Widgets.find(app.panels.budget.root, "Action_pass_purchase_turn")
	check("bouton de passage proposé au titulaire", pass.Active and pass.Visible)
	click(pass)
	check("passage de tour depuis le budget", lastAction() == "pass_purchase_turn"
		and world.purchaseTurn.owner == alternate.UserId and not app.panels.budget.rows.entries.VSAV.buy.Active)
	world.players[alternate.UserId].connected = false
end

world.players[player.UserId].role = Constants.ROLE.OBSERVATEUR
controller:applySnapshot(SnapshotService.build(world))
check("observateur sans nouvelle partie", app.menu.newGameButton.Visible == false)

-- ─────────────────────────────────────────────────────────────
suite("Audio de l'interface")
-- ─────────────────────────────────────────────────────────────
-- Sonde isolée : elle ne partage ni dossier ni groupe avec le client monté,
-- pour vérifier chaque transition sans dépendre des snapshots précédents.
local probeService = Instance.new("SoundService")
local probe = AudioController.new({ soundService = probeService, config = Config })
probe:mount()

check("dossier audio monté", probeService:FindFirstChild("ERS_Audio") ~= nil)
check("groupe audio unique", (function()
	local count = 0
	local folder = probeService:FindFirstChild("ERS_Audio")
	for _, child in ipairs(folder:GetChildren()) do
		if child.ClassName == "SoundGroup" then
			count += 1
		end
	end
	return count == 1
end)())
check("ambiance lancée", probe.ambience ~= nil and probe.ambience.Playing == true)
check("sons fournis par le client", string.sub(probe.ambience.SoundId, 1, 11) == "rbxasset://")
check("clic joué", probe:play("click") == true and probe.cueSounds.click.Playing == true)
check("bruit inconnu ignoré", probe:play("inconnu") == false)

-- Alerte : le premier snapshot ne sonne pas, un nouvel incident si.
probe:update({
	incidents = { { id = 1, status = Constants.INCIDENT_STATUS.PENDING } },
	vehicles = {},
})
check("premier snapshot silencieux", probe.cueSounds.alert == nil)
probe:update({
	incidents = {
		{ id = 1, status = Constants.INCIDENT_STATUS.PENDING },
		{ id = 2, status = Constants.INCIDENT_STATUS.ACTIVE },
	},
	vehicles = {},
})
check("alerte sur nouvelle urgence", probe.cueSounds.alert ~= nil
	and probe.cueSounds.alert.Playing == true)

-- Sirène : elle suit l'engagement réel des engins et alterne deux tons.
probe:update({
	incidents = {},
	vehicles = { { id = 1, status = Constants.VEHICLE_STATUS.DISPATCHED } },
})
check("sirène au départ d'un engin", probe.sirenActive == true
	and probe.siren ~= nil and probe.siren.Playing == true)
check("sirène enregistrée à sa vitesse native", probe.siren.SoundId == Config.AUDIO_SIREN
	and probe.siren.PlaybackSpeed == 1 and probe.siren.Looped)
check("annonce vocale de la centrale", probe.voice.IsPlaying and probe.voice.VoiceId == "402"
	and string.find(probe.radioCaption, "Centre 112", 1, true) ~= nil)
probe:update({ incidents = {}, vehicles = {} })
check("sirène coupée au retour", probe.sirenActive == false and probe.siren.Playing == false)

probe:update({ incidents = {}, vehicles = { { id = 1, status = Constants.VEHICLE_STATUS.ON_SCENE } } })
check("sirène éteinte sur les lieux", probe.siren.Playing == false)

-- Coupure : le groupe tombe à zéro, la sirène s'arrête et les bruits sont
-- refusés. Le retour du son relance la sirène si un engin est engagé.
probe:update({
	incidents = {},
	vehicles = { { id = 1, status = Constants.VEHICLE_STATUS.DISPATCHED } },
})
probe:setMuted(true)
check("mute coupe le groupe", probe.group.Volume == 0)
check("mute arrête la sirène", probe.siren.Playing == false and probe.sirenActive == false)
check("mute bloque les bruits", probe:play("click") == false)
check("radio coupée en mute", probe.voice.Volume == 0 and not probe.voice.IsPlaying)
probe:setMuted(false)
check("son rétabli", probe.group.Volume == 1)
check("sirène relancée si engin engagé", probe.siren.Playing == true)

probe:unmount()
check("dossier audio retiré", probeService:FindFirstChild("ERS_Audio") == nil)
check("sons oubliés au démontage", probe.ambience == nil and next(probe.cueSounds) == nil)

-- Bouton de la barre supérieure : il coupe réellement le groupe du client.
check("bouton SON visible", app.audioButton ~= nil and app.audioButton.Visible == true)
check("son actif au départ", app.audioButton.Text == "SON" and audio.muted == false)
click(app.audioButton)
check("bouton passe en MUET", app.audioButton.Text == "MUET" and audio.muted == true)
check("groupe de l'interface coupé", audio.group.Volume == 0)
click(app.audioButton)
check("bouton revient à SON", app.audioButton.Text == "SON" and audio.muted == false)
check("groupe de l'interface rétabli", audio.group.Volume == 1)

-- ─────────────────────────────────────────────────────────────
suite("Ordres de terrain depuis le panneau Interventions")
do
	controller:command("claim_role", { role = Constants.ROLE.DIRECTION })
	local testFpt = vehicleOfType("FPT")
	local assignment = IncidentService.spawn(world, "FEU_VEHICULE", testFpt.home).data
	controller:applySnapshot(SnapshotService.build(world))
	controller:select("vehicle", testFpt.id)
	controller:select("incident", assignment.id)
	controller:command("auto_crew", {vehicleId = testFpt.id})
	click(app.panels.incidents.dispatchButton)
	local orders = app.panels.incidents.orderButtons
	check("extinction proposée à l'arrivée de l'équipe", orders.extinguish.Visible and orders.extinguish.Active)
	click(orders.extinguish)
	check("le clic affecte l'équipe à l'extinction", lastAction() == "field_order" and testFpt.fieldOrder == "extinguish")
	click(orders.hold)
	check("changement d'ordre en réserve", testFpt.fieldOrder == "hold" and not orders.hold.Active)
	check("désincarcération masquée sans victime piégée", not orders.extricate.Visible)
end

suite("Intégrité du monde après les actions d'interface")
do
	click(app.tabs.missions)
	local panel = app.panels.missions
	check("panneau Missions ouvert", controller.state.tab == "missions" and panel.root.Visible)
	check("score initial lisible", string.find(panel.summary.Text, "Score 0", 1, true) ~= nil)
	click(panel.buttons.eglise)
	check("lancement de l’église relié au serveur", lastAction() == "start_mission" and world.mission.id == "eglise")
	check("objectifs et disponibilité actualisés", panel.links[1].Active and not panel.links[2].Active and not panel.buttons.route.Active)
	click(panel.links[1])
	check("objectif ouvre la fiche de son intervention", controller.state.tab == "incidents"
		and controller:selectedIncident().id == world.mission.incidentIds[1])
end
-- ─────────────────────────────────────────────────────────────
local finalSnapshot = SnapshotService.build(world)
check("snapshot final sérialisable", SnapshotService.isSerializable(finalSnapshot) == true)
check("budget cohérent", type(world.budget) == "number" and world.budget == world.budget)
check("aucune action inventée", (function()
	local known = NetworkService.actions
	for _, entry in ipairs(actions) do
		if known[entry.action] == nil then
			return false
		end
	end
	return true
end)())
check("journal borné", #finalSnapshot.log <= Config.SNAPSHOT_LOG_LIMIT)
check("interface toujours construite", app.root ~= nil and app.status.Text ~= "")
check("tous les panneaux ont un parent", (function()
	for _, panel in pairs(app.panels) do
		if panel.root.Parent == nil then
			return false
		end
	end
	return true
end)())

-- ─────────────────────────────────────────────────────────────
print("")
do
	controller:closeDrawer()
	app.gui.AbsoluteSize = Vector2.new(1904, 900)
	controller:render()
	click(Widgets.find(app.topBar, "PersonnaliserHUD"))
	local inputs = game:GetService("UserInputService")
	local function drag(panel, dx, dy)
		local input = {UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(500,500,0)}
		Widgets.find(panel, "Redimensionner").InputBegan:Fire(input)
		inputs.InputChanged:Fire({UserInputType = Enum.UserInputType.MouseMovement, Position = Vector3.new(500+dx,500+dy,0)})
		inputs.InputEnded:Fire(input)
	end
	local before = app.map.root.Size.X.Offset
	drag(app.map.root, -90, 90)
	check("carte agrandie par sa poignée", app.map.root.Size.X.Offset > before)
	local resized = app.map.root.Size.X.Offset
	controller:applySnapshot(SnapshotService.build(world))
	check("taille carte conservée entre snapshots", app.map.root.Size.X.Offset == resized)
	drag(app.logPanel, -150, -100)
	check("journal redimensionné dans les deux axes", app.logPanel.Size.X.Offset < 720 and app.logPanel.Size.Y.Offset == 242)
	drag(app.map.root, -10000, 10000)
	check("carte bornée au-dessus du pupitre", app.map.root.Size.Y.Offset <= 900 - Theme.sizes.topBar - Theme.sizes.bar - 24)
	local size = app.logPanel.Size.Y.Offset
	inputs.InputChanged:Fire({UserInputType = Enum.UserInputType.MouseMovement, Position = Vector3.new(1,1,0)})
	check("relâcher la souris termine le redimensionnement", app.logPanel.Size.Y.Offset == size)
end
do
	local inputs = game:GetService("UserInputService")
	local entry = app.editor.entries.journal
	local down = { UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(400,400,0) }
	entry.overlay:FindFirstChild("Deplacer").InputBegan:Fire(down)
	inputs.InputChanged:Fire({UserInputType = Enum.UserInputType.MouseMovement, Position = Vector3.new(500,300,0)})
	inputs.InputEnded:Fire(down)
	check("déplacement enregistré pour le journal", app.editor.layout.journal ~= nil)
	local x = app.logPanel.Position.X.Offset
	controller:render()
	check("position personnalisée conservée au rendu", app.logPanel.Position.X.Offset == x)
	entry.overlay:FindFirstChild("Taille").InputBegan:Fire(down)
	inputs.InputChanged:Fire({UserInputType = Enum.UserInputType.MouseMovement, Position = Vector3.new(490,440,0)})
	inputs.InputEnded:Fire(down)
	check("échelle du panneau modifiée avec la poignée", app.editor.layout.journal.scale > 1)
	app.gui.AbsoluteSize = Vector2.new(812,600)
	controller:render()
	check("panneau personnalisé contenu après réduction de la fenêtre",
		app.logPanel.Position.X.Offset + entry.w <= app.editor.width + 0.01
		and app.logPanel.Position.Y.Offset + entry.h <= app.editor.height + 0.01)
	app.gui.AbsoluteSize = Vector2.new(1904,900)
	controller:render()
	x = app.logPanel.Position.X.Offset
	click(Widgets.find(app.topBar, "PersonnaliserHUD"))
	check("cadenas masque les poignées", not entry.overlay.Visible and not Widgets.find(app.logPanel,"Redimensionner").Visible)
	entry.overlay:FindFirstChild("Deplacer").InputBegan:Fire(down)
	inputs.InputChanged:Fire({UserInputType = Enum.UserInputType.MouseMovement, Position = Vector3.new(1000,900,0)})
	check("cadenas interdit les déplacements", app.logPanel.Position.X.Offset == x)
	click(Widgets.find(app.topBar, "PersonnaliserHUD"))
	click(Widgets.find(app.topBar, "ReinitialiserHUD"))
	check("réinitialisation de la disposition", next(app.editor.layout) == nil and app.map.root.Size.X.Offset == Theme.sizes.minimapWidth)
	click(Widgets.find(app.topBar, "PersonnaliserHUD"))
	local service = require(game:GetService("ServerScriptService"):WaitForChild("ERS"):WaitForChild("Services"):WaitForChild("HudPreferenceService"))
	local saved = {}
	local store = { GetAsync = function(_,key) return saved[key] end, SetAsync = function(_,key,value) saved[key] = value end }
	local handle = service.new(store)
	local layout = { journal = {x=0.2,y=0.4,scale=0.8} }
	check("préférence sauvegardée sous le joueur authentifié", handle({UserId=123},layout).persistent and saved["123"].journal.x==0.2)
	check("préférence restaurée dans une nouvelle session", service.new(store)({UserId=123},nil).layout.journal.scale==0.8)
	check("préférences isolées par joueur", next(handle({UserId=124},nil).layout)==nil)
	check("coordonnées invalides refusées", not handle({UserId=125},{journal={x=math.huge,y=0,scale=1}}).ok)
	check("panneaux inconnus refusés", service.validate({alien={x=0,y=0,scale=1}})==nil)
	check("repli local explicite sans DataStore", service.new(nil)({UserId=126},layout).persistent==false)
end
do
	controller:setMenu(false)
	controller:closeDrawer()
	camera:reset()
	camera:setViewport(1280,720)
	local controls = InputController.new(controller, app, camera)
	controls:mount()
	local inputs = game:GetService("UserInputService")
	local key = {KeyCode=Enum.KeyCode.Right, UserInputType=Enum.UserInputType.Keyboard}
	inputs.InputBegan:Fire(key,false)
	local x = camera.target.x
	for _=1,30 do controls:step(1/60) end
	check("flèche maintenue déplace en continu", camera.target.x > x)
	inputs.InputEnded:Fire(key)
	for _=1,60 do controls:step(1/60) end
	x = camera.target.x
	for _=1,60 do controls:step(1/60) end
	check("relâcher une flèche termine le mouvement", near(x,camera.target.x,0.01))
	inputs.InputBegan:Fire(key,false)
	inputs.WindowFocusReleased:Fire()
	x = camera.target.x
	controls:step(0.05)
	check("perte de focus annule les touches maintenues", camera.target.x == x)
	local down = {UserInputType=Enum.UserInputType.MouseButton1,Position=Vector3.new(500,300,0)}
	inputs.InputBegan:Fire(down,false)
	inputs.InputChanged:Fire({UserInputType=Enum.UserInputType.MouseMovement,Position=Vector3.new(600,300,0)},false)
	inputs.InputEnded:Fire(down)
	check("glisser la vue déplace la caméra et annule le double-clic", camera.target.x < x and controls.lastClick == nil)
	local query = playerGui.GetGuiObjectsAtPosition
	playerGui.GetGuiObjectsAtPosition = function() return {app.logPanel} end
	x = camera.target.x
	local distance = camera.distance
	inputs.InputBegan:Fire(down,false)
	inputs.InputChanged:Fire({UserInputType=Enum.UserInputType.MouseMovement,Position=Vector3.new(700,300,0)},false)
	inputs.InputChanged:Fire({UserInputType=Enum.UserInputType.MouseWheel,Position=Vector3.new(700,300,1)},false)
	inputs.InputEnded:Fire(down)
	check("journal sous la souris bloque glissement et zoom", camera.target.x == x and camera.distance == distance)
	playerGui.GetGuiObjectsAtPosition = query
	local host = Widgets.find(app.map.root,"Zone")
	host.AbsolutePosition = Vector2.new(100,100)
	host.AbsoluteSize = Vector2.new(200,200)
	Widgets.find(app.map.root,"NaviguerCarte").MouseButton1Down:Fire(150,250)
	check("clic dans le fond de carte recentre à la position choisie", near(camera.target.x,25) and near(camera.target.z,75))
	local start = camera.display.x
	camera:focus(90,50)
	camera:step(1/60)
	check("transition caméra progressive", camera.display.x > start and camera.display.x < 90)
	for _=1,120 do camera:step(1/60) end
	check("transition converge vers le point choisi", near(camera.display.x,90,0.001))
	controls:unmount()
end
print(string.format("  Interface : %d réussite(s), %d échec(s)", passed, failed))
if failed > 0 then
	error(string.format("%d test(s) d'interface en échec", failed))
end
