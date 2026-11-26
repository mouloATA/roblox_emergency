--!strict
--[[
	App — coque de l'interface tactique.

	La ville 3D occupe tout l'écran ; l'interface se superpose en trois zones
	fixes, comme dans Emergency 4 :
	- mini-carte encadrée en haut à droite ;
	- barre inférieure de gestion et de commandes ;
	- colonne compacte des panneaux à gauche.

	Le tiroir de panneaux s'ouvre juste au-dessus de la barre inférieure. Il ne
	contient que des données du snapshot serveur : aucun écran ne décide d'un
	résultat de jeu.

	Les lignes de journal et les notifications sont réconciliées par identifiant
	pour ne pas clignoter à chaque snapshot.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))

local UI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ERSClient"):WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))
local MiniMap = require(UI:WaitForChild("MiniMap"))
local BottomBar = require(UI:WaitForChild("BottomBar"))
local IncidentPanel = require(UI:WaitForChild("IncidentPanel"))
local VehiclePanel = require(UI:WaitForChild("VehiclePanel"))
local PersonnelPanel = require(UI:WaitForChild("PersonnelPanel"))
local EquipmentPanel = require(UI:WaitForChild("EquipmentPanel"))
local CommandPanel = require(UI:WaitForChild("CommandPanel"))
local BudgetPanel = require(UI:WaitForChild("BudgetPanel"))
local MultiplayerPanel = require(UI:WaitForChild("MultiplayerPanel"))
local MissionPanel = require(UI:WaitForChild("MissionPanel"))
local MainMenu = require(UI:WaitForChild("MainMenu"))
local HudEditor = require(UI:WaitForChild("HudEditor"))

local App = {}

App.tabs = {
	{ id = "incidents", label = "Interventions", key = "1", group = "Opérations" },
	{ id = "missions", label = "Missions", key = "8" },
	{ id = "command", label = "Commandement", key = "5" },
	{ id = "vehicles", label = "Flotte", key = "2", group = "Caserne" },
	{ id = "budget", label = "Achats et finances", key = "6" },
	{ id = "personnel", label = "Personnel", key = "3" },
	{ id = "equipment", label = "Matériel", key = "4" },
	{ id = "roles", label = "Postes", key = "7", group = "Coordination" },
}

local function logColor(kind: string): any
	if kind == Constants.LOG.SUCCESS then
		return Theme.colors.success
	elseif kind == Constants.LOG.FAILURE then
		return Theme.colors.danger
	elseif kind == Constants.LOG.MONEY then
		return Theme.colors.warning
	elseif kind == Constants.LOG.DISPATCH then
		return Theme.colors.info
	elseif kind == Constants.LOG.INCIDENT then
		return Theme.colors.accent
	end
	return Theme.colors.textDim
end

local function tabLabel(id: string): string
	for _, tab in ipairs(App.tabs) do
		if tab.id == id then
			return tab.label
		end
	end
	return id
end

function App.create(parent: any, context: any): any
	local controller = context.controller
	local player = context.player
	local audio = context.audio

	local gui = Instance.new("ScreenGui")
	gui.Name = "ERS"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 10
	-- Mode Sibling obligatoire : en mode Global, un enfant resté au ZIndex 1
	-- passe sous le fond de son conteneur (barre, tiroir, mini-carte). Ici les
	-- enfants sont toujours dessinés au-dessus de leur parent et le ZIndex ne
	-- classe plus que les frères (barre, tiroir, notifications, menu).
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = parent

	-- Racine transparente : la vue 3D reste visible entre les panneaux.
	local root = Widgets.frame(gui, "Racine", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	local hudScale = Instance.new("UIScale")
	hudScale.Name, hudScale.Scale, hudScale.Parent = "EchelleHUD", 1, root

	-- ── Barre supérieure ──────────────────────────────────────
	local topGui = Instance.new("ScreenGui")
	topGui.Name = "ERSTopbar"
	topGui.ResetOnSpawn = false
	topGui.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
	topGui.DisplayOrder = gui.DisplayOrder
	topGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	topGui.Parent = parent
	local topBar = Widgets.frame(topGui, "BarreSuperieure", {
		BackgroundColor3 = Theme.colors.panelDark,
		BackgroundTransparency = 0.08,
		Position = UDim2.new(0, 8, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(1, -16, 0, Theme.sizes.topBar),
		ZIndex = 10,
	})
	Widgets.stroke(topBar, Theme.colors.steel, 1)

	local brand = Widgets.label(topBar, "Marque", "ERS", {
		Position = UDim2.fromOffset(14, 7),
		Size = UDim2.fromOffset(46, 22),
		TextSize = 20,
		Font = Theme.fonts.bold,
		TextColor3 = Theme.colors.accent,
	})
	local brandName = Widgets.label(topBar, "Nom", Config.GAME_NAME, {
		Position = UDim2.fromOffset(58, 6),
		Size = UDim2.fromOffset(213, 18),
		TextSize = Theme.text.small,
		Font = Theme.fonts.bold,
	})
	local city = Widgets.label(topBar, "Ville", string.format("%s · centre 112", Config.CITY_NAME), {
		Position = UDim2.fromOffset(58, 25),
		Size = UDim2.fromOffset(213, 15),
		TextSize = 9,
		TextColor3 = Theme.colors.textMuted,
	})

	local status = Widgets.label(topBar, "Statut", "Synchronisation…", {
		Position = UDim2.new(0, 278, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(1, -478, 0, 22),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextSize = Theme.text.small,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.fonts.mono,
		TextColor3 = Theme.colors.textDim,
	})

	local menuButton = Widgets.button(topBar, "Action_menu", "Menu", function()
		if audio then
			audio:play("click")
		end
		controller:setMenu(true)
	end, {
		Position = UDim2.new(1, -96, 0, 7),
		Size = UDim2.fromOffset(84, 30),
		TextSize = Theme.text.small,
		BackgroundColor3 = Theme.colors.panel,
	})

	local audioButton
	audioButton = Widgets.button(topBar, "Action_son", "SON", function()
		if not audio then
			return
		end
		local muted = audio:toggleMuted()
		audioButton.Text = muted and "MUET" or "SON"
		audioButton.TextColor3 = muted and Theme.colors.textMuted or Theme.colors.active
		audio:play("click")
	end, {
		Position = UDim2.new(1, -188, 0, 7),
		Size = UDim2.fromOffset(84, 30),
		TextSize = Theme.text.small,
		BackgroundColor3 = Theme.colors.panel,
	})
	audioButton.TextColor3 = Theme.colors.active
	audioButton.Visible = audio ~= nil

	-- Roblox recalcule cette zone quand les bulles natives ou la fenêtre changent.
	local function resizeTopbar()
		local width = topGui.AbsoluteSize.X - 16
		local compact = width < 780
		brandName.Visible = not compact
		city.Visible = not compact
		status.Position = UDim2.new(0, compact and 64 or 278, 0.5, 0)
		status.Size = UDim2.new(1, compact and -410 or -624, 0, 22)
		status.Visible = width >= 540
	end
	topGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(resizeTopbar)
	resizeTopbar()

	-- ── Colonne des panneaux ──────────────────────────────────
	local tabColumn = Widgets.frame(root, "Onglets", {
		BackgroundColor3 = Theme.colors.panelDark,
		BackgroundTransparency = 0.08,
		Position = UDim2.fromOffset(8, Theme.sizes.topBar + 8),
		Size = UDim2.new(0, Theme.sizes.tabsCompact, 1, -(Theme.sizes.topBar + Theme.sizes.bar + 24)),
		ZIndex = 10,
	})
	Widgets.corner(tabColumn, Theme.radius.small)
	Widgets.stroke(tabColumn, Theme.colors.steel, 1)
	Widgets.padding(tabColumn, 6, 2)

	local tabBody = Widgets.scroller(tabColumn, "Liste", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	local tabButtons = {}
	for index, tab in ipairs(App.tabs) do
		if tab.group then
			Widgets.section(tabBody, tab.group).LayoutOrder = index * 2
		end
		local button = Widgets.button(tabBody, "Action_tab_" .. tab.id, tab.label, function()
			if audio then audio:play("click") end
			controller:setTab(tab.id)
		end, {
			Size = UDim2.new(1, -3, 0, 32), LayoutOrder = index * 2 + 1,
			TextXAlignment = Enum.TextXAlignment.Left, TextSize = Theme.text.small,
			BackgroundColor3 = Theme.colors.surfaceAlt, TextColor3 = Theme.colors.textDim,
		})
		Widgets.padding(button, 0, 6)
		tabButtons[tab.id] = button
	end

	-- ── Mini-carte en haut à droite ───────────────────────────
	local map = MiniMap.create(root, {
		controller = controller,
		camera = context.camera,
		snapshot = context.snapshot,
	})
	map.root.Position = UDim2.new(1, -8, 0, Theme.sizes.topBar + 8)
	map.root.AnchorPoint = Vector2.new(1, 0)

	-- ── Journal compact, au-dessus de la barre ────────────────
	-- Décalé à droite de la colonne d'onglets : sinon celle-ci, plus haute,
	-- recouvre les heures et les types des lignes.
	local logPanel = Widgets.frame(root, "Journal", {
		BackgroundColor3 = Theme.colors.panelDark,
		BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, Theme.sizes.tabsCompact + 16, 1, -(Theme.sizes.bar + 8)),
		Size = UDim2.fromOffset(720, 142),
		ZIndex = 9,
	})
	Widgets.corner(logPanel, Theme.radius.small)
	Widgets.stroke(logPanel, Theme.colors.steel, 1)
	Widgets.padding(logPanel, 6, 3)

	local logTitle = Widgets.label(logPanel, "Titre", "JOURNAL OPÉRATIONNEL", {
		Size = UDim2.new(1, 0, 0, 14),
		TextSize = 9,
		Font = Theme.fonts.bold,
		TextColor3 = Theme.colors.textDim,
	})
	local radioPanel = Widgets.frame(root, "Radio", {
		Position = UDim2.fromOffset(Theme.sizes.tabsCompact + 16, Theme.sizes.topBar + 8),
		Size = UDim2.fromOffset(480, 44), BackgroundColor3 = Theme.colors.panelDark,
		ZIndex = 19, Visible = false,
	})
	Widgets.stroke(radioPanel, Theme.colors.steel, 1)
	local radioText = Widgets.label(radioPanel, "Transmission", "", {
		Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0),
		TextSize = Theme.text.small, TextWrapped = true, TextColor3 = Theme.colors.text,
	})

	local logList = Widgets.scroller(logPanel, "Lignes", {
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 1, -16),
	})
	local logRows = Widgets.list(logList, function(entry)
		return entry.id or (entry.clock .. "|" .. entry.message)
	end, function(entry)
		local row = Widgets.frame(logList, "Journal_" .. tostring(entry.id or 0), {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 15),
		})
		local clock = Widgets.label(row, "Heure", entry.clock or "", {
			Size = UDim2.fromOffset(42, 15),
			TextSize = 8,
			Font = Theme.fonts.mono,
			TextColor3 = Theme.colors.textMuted,
		})
		local kind = Widgets.label(row, "Type", string.upper(entry.kind or ""), {
			Position = UDim2.fromOffset(44, 0),
			Size = UDim2.fromOffset(64, 15),
			TextSize = 8,
			Font = Theme.fonts.bold,
			TextColor3 = logColor(entry.kind),
		})
		local message = Widgets.label(row, "Message", entry.message or "", {
			Position = UDim2.fromOffset(110, 0),
			Size = UDim2.new(1, -112, 0, 15),
			TextSize = 8,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = Theme.colors.textDim,
		})
		return { instance = row, clock = clock, kind = kind, message = message }
	end, function(entryView, entry)
		entryView.clock.Text = entry.clock or ""
		entryView.kind.Text = string.upper(entry.kind or "")
		entryView.kind.TextColor3 = logColor(entry.kind)
		entryView.message.Text = entry.message or ""
	end)

	-- ── Tiroir de panneaux, au-dessus de la barre ─────────────
	local drawerLeft = tabColumn.Position.X.Offset + tabColumn.Size.X.Offset + 8
	local drawer = Widgets.frame(root, "Tiroir", {
		BackgroundColor3 = Theme.colors.panelDark,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, drawerLeft, 1, -(Theme.sizes.bar + 8)),
		Size = UDim2.new(1, -(drawerLeft + 8), 0, Theme.sizes.drawerHeight),
		ZIndex = 20,
		Visible = false,
		-- Un panneau ne doit jamais déborder sur la barre inférieure : son
		-- contenu défile à l'intérieur du tiroir.
		ClipsDescendants = true,
	})
	Widgets.stroke(drawer, Theme.colors.steel, 1)
	Widgets.corner(drawer, Theme.radius.small)

	local drawerHeader = Widgets.frame(drawer, "Entete", {
		BackgroundColor3 = Theme.colors.panel,
		Size = UDim2.new(1, 0, 0, 26),
	})
	local drawerTitle = Widgets.label(drawerHeader, "Titre", "PANNEAU", {
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -120, 1, 0),
		TextSize = 11,
		Font = Theme.fonts.bold,
		TextColor3 = Theme.colors.text,
	})
	local feedback = Widgets.label(drawerHeader, "RetourAction", "", {
		Position = UDim2.fromOffset(152, 0), Size = UDim2.new(1, -254, 1, 0),
		TextWrapped = true, TextSize = Theme.text.small, Visible = false,
	})
	local drawerClose = Widgets.button(drawerHeader, "Action_fermer_tiroir", "Fermer", function()
		controller:closeDrawer()
	end, {
		Position = UDim2.new(1, -92, 0, 3),
		Size = UDim2.fromOffset(84, 20),
		TextSize = 9,
		BackgroundColor3 = Theme.colors.command,
		TextColor3 = Theme.colors.text,
	})

	-- Les fiches larges peuvent défiler dans le tiroir. La navigation et Fermer restent fixes.
	local drawerViewport = Instance.new("ScrollingFrame")
	drawerViewport.Name = "FenetreTiroir"
	drawerViewport.BackgroundTransparency = 1
	drawerViewport.BorderSizePixel = 0
	drawerViewport.ClipsDescendants = true
	drawerViewport.ScrollingDirection = Enum.ScrollingDirection.X
	drawerViewport.ScrollBarThickness = 6
	drawerViewport.ScrollBarImageColor3 = Theme.colors.steel
	drawerViewport.CanvasSize = UDim2.fromOffset(0, 0)
	drawerViewport.CanvasPosition = Vector2.new(0, 0)
	drawerViewport.Parent = drawer
	local scrollPage: string? = nil
	local drawerContent = Widgets.frame(drawerViewport, "ContenuTiroir", {
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
	})

	local budget = BudgetPanel.create(drawerContent, { controller = controller, snapshot = context.snapshot })
	local panels = {
		incidents = IncidentPanel.create(drawerContent, { controller = controller, snapshot = context.snapshot }),
		vehicles = VehiclePanel.create(drawerContent, { controller = controller, snapshot = context.snapshot, openShop = budget.openShop }),
		personnel = PersonnelPanel.create(drawerContent, { controller = controller, snapshot = context.snapshot }),
		equipment = EquipmentPanel.create(drawerContent, { controller = controller, snapshot = context.snapshot }),
		command = CommandPanel.create(drawerContent, { controller = controller, snapshot = context.snapshot }),
		budget = budget,
		roles = MultiplayerPanel.create(drawerContent, { controller = controller, snapshot = context.snapshot }),
		missions = MissionPanel.create(drawerContent, { controller = controller, snapshot = context.snapshot }),
	}

	-- ── Notifications ─────────────────────────────────────────
	local toastsRoot = Widgets.vertical(root, "Notifications", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(Theme.sizes.tabsCompact + 18, Theme.sizes.topBar + 10),
		Size = UDim2.fromOffset(380, 190),
		ZIndex = 30,
	})
	local toastRows = Widgets.list(toastsRoot, function(toast)
		return toast.id
	end, function(toast)
		local card = Widgets.frame(toastsRoot, "Notification_" .. toast.id, {
			BackgroundColor3 = Theme.colors.panel,
			Size = UDim2.new(1, 0, 0, 42),
			ZIndex = 30,
		})
		Widgets.corner(card, Theme.radius.small)
		local stroke = Widgets.stroke(card, Theme.colors.info, 1)
		local message = Widgets.label(card, "Message", toast.message, {
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -44, 1, 0),
			TextSize = 10,
			TextWrapped = true,
			TextColor3 = Theme.colors.text,
			ZIndex = 31,
		})
		local close = Widgets.button(card, "Action_toast_close_" .. toast.id, "×", function()
			controller:dismissToast(toast.id)
		end, {
			Size = UDim2.fromOffset(26, 26),
			Position = UDim2.new(1, -32, 0, 8),
			TextSize = Theme.text.body,
			BackgroundColor3 = Theme.colors.command,
			TextColor3 = Theme.colors.commandText,
			ZIndex = 31,
		})
		return { instance = card, stroke = stroke, message = message, close = close }
	end, function(entry, toast)
		entry.message.Text = toast.message
		entry.stroke.Color = toast.ok and Theme.colors.active or Theme.colors.danger
	end)

	-- ── Barre inférieure ──────────────────────────────────────
	local bottom = BottomBar.create(root, {
		controller = controller,
		camera = context.camera,
		snapshot = context.snapshot,
	})

	-- ── Menu principal (au-dessus de tout) ────────────────────
	local menu = MainMenu.create(root, { controller = controller, snapshot = context.snapshot })

	local mapWidth: number? = nil
	local journalSize: any = nil
	local editor = HudEditor.new(root, {
		map = map.root, journal = logPanel, navigation = tabColumn, radio = radioPanel,
		commands = bottom.root, panel = drawer, notifications = toastsRoot,
	}, controller)
	local saveLayout = context.saveLayout
	local lock
	local reset = Widgets.button(topBar, "ReinitialiserHUD", "Réinitialiser", function()
		mapWidth, journalSize = nil, nil
		editor:reset()
	end, { Position = UDim2.new(1, -424, 0, 7), Size = UDim2.fromOffset(108,30), Visible = false })
	lock = Widgets.button(topBar, "PersonnaliserHUD", "🔒 HUD", function()
		editor.touched = true
		editor.editing = not editor.editing
		lock.Text = editor.editing and "🔓 Verrouiller" or "🔒 HUD"
		reset.Visible = editor.editing
		controller:render()
		if not editor.editing and editor.dirty and saveLayout then
			saveLayout(editor.layout)
			editor.dirty = false
		end
	end, { Position = UDim2.new(1, -308, 0, 7), Size = UDim2.fromOffset(112,30) })
	Widgets.resizeHandle(map.root, UDim2.new(0, 8, 1, -2), Vector2.new(0, 1), Vector2.new(-1, 1),
		function() return hudScale.Scale end, function(width, _height)
			if not editor.editing then return end
			mapWidth = width
			controller:render()
		end)
	Widgets.resizeHandle(logPanel, UDim2.new(1, 0, 0, 0), Vector2.new(1, 0), Vector2.new(1, -1),
		function() return hudScale.Scale end, function(width, height)
			if not editor.editing then return end
			journalSize = Vector2.new(width, height)
			controller:render()
		end)
	local app = {
		editor = editor,
		gui = gui,
		topGui = topGui,
		root = root,
		topBar = topBar,
		status = status,
		tabs = tabButtons,
		panels = panels,
		map = map,
		bottom = bottom,
		drawer = drawer,
		drawerTitle = drawerTitle,
		logPanel = logPanel,
		radioPanel = radioPanel,
		logRows = logRows,
		toastRows = toastRows,
		menu = menu,
		menuButton = menuButton,
		audio = audio,
		audioButton = audioButton,
		lastToastId = 0,
		camera = context.camera,
		scene = context.scene,
	}

	-- Branche la caméra après création (le bootstrap la fournit aussi).
	function app:setCamera(camera: any)
		self.camera = camera
		self.map.setCamera(camera)
		self.bottom.setCamera(camera)
	end

	function app:setScene(scene: any)
		self.scene = scene
	end

	-- Interroge la géométrie Roblox finale, y compris les panneaux déplacés et redimensionnés.
	function app:isHudAt(position: any): boolean
		for _, object in ipairs(parent:GetGuiObjectsAtPosition(position.X, position.Y)) do
			local node = object
			while node and node ~= parent do
				if node == topBar or node == menu.root then return true end
				for _, entry in pairs(editor.entries) do
					if node == entry.panel or node == entry.overlay then return true end
				end
				node = node.Parent
			end
		end
		return false
	end

	function app:render(state: any, snapshot: any)
		editor:restore()
		local vehicles = snapshot.vehicles or {}
		local alerts = snapshot.alerts or 0
		local me = nil
		for _, entry in ipairs(snapshot.players or {}) do
			if entry.userId == player.UserId then
				me = entry
			end
		end
		local roleLabel = me and (me.roleLabel or me.role) or "Non enregistré"
		status.Text = string.format(
			"%s · %s · %d alerte(s) · %s · %d engin(s)",
			snapshot.clock or "--:--",
			Theme.money(snapshot.budget or 0),
			alerts,
			roleLabel,
			#vehicles
		)
		status.TextColor3 = (snapshot.budget or 0) >= 0 and Theme.colors.textDim or Theme.colors.danger

		for id, button in pairs(tabButtons) do
			local active = (state.drawer == "vehicles" and id == "vehicles")
				or (state.drawer == "panel" and state.tab == id)
			button.BackgroundColor3 = active and Theme.colors.selection or Theme.colors.surfaceAlt
			button.TextColor3 = active and Theme.colors.text or Theme.colors.textDim
		end

		local drawerOpen = state.drawer ~= "none"
		drawer.Visible = drawerOpen
		local activeId = state.tab
		if state.drawer == "vehicles" then
			activeId = "vehicles"
			drawerTitle.Text = "FLOTTE — " .. string.upper(Theme.serviceLabel(state.category))
		else
			drawerTitle.Text = string.upper(tabLabel(state.tab))
		end

		local managing = drawerOpen and (activeId == "budget" or activeId == "personnel" or activeId == "equipment")
		local notice = controller.toasts[#controller.toasts]
		feedback.Visible = managing and notice ~= nil
		feedback.Text = notice and notice.message or ""
		feedback.TextColor3 = notice and not notice.ok and Theme.colors.warning or Theme.colors.text
		toastsRoot.Visible = not managing
		local headerHeight = managing and 42 or 26
		drawerHeader.Size = UDim2.new(1, 0, 0, headerHeight)
		drawerViewport.Position = UDim2.fromOffset(0, headerHeight)
		drawerViewport.Size = UDim2.new(1, 0, 1, -headerHeight)
		drawerClose.AnchorPoint = Vector2.new(0, 0.5)
		drawerClose.Position = UDim2.new(1, -92, 0.5, 0)
		drawerClose.Size = UDim2.fromOffset(84, managing and 30 or 20)
		for id, panel in pairs(panels) do
			panel.update(snapshot, state)
			panel.root.Visible = drawerOpen and id == activeId
		end

		-- Cadre de visée : la mini-carte montre ce que voit la caméra.
		local view = nil
		local camera = self.camera
		local absolute = gui.AbsoluteSize
		if absolute and absolute.X > 0 and absolute.Y > 0 then
			-- Sur écran dense les panneaux gagnent en taille physique tout en
			-- gardant le même espace logique que sur un bureau standard.
			local factor = math.clamp(math.min(absolute.X / 1600, absolute.Y / 900), 1, 1.5)
			hudScale.Scale = factor
			root.Size = UDim2.fromScale(1 / factor, 1 / factor)
			local width, height = absolute.X / factor, absolute.Y / factor
			self.map.resize(width, height, mapWidth)
			bottom.resize(width)
			local visibleWidth = math.max(1, width - drawerLeft - 8)
			-- Les fiches opérationnelles ont deux colonnes et une rangée de commandes.
			local contentWidth = math.max(visibleWidth, managing and 360 or 800)
			local overflow = contentWidth > visibleWidth
			drawerViewport.ScrollingEnabled = overflow
			drawerViewport.CanvasSize = UDim2.fromOffset(contentWidth, 0)
			drawerContent.Size = UDim2.new(0, contentWidth, 1, overflow and -drawerViewport.ScrollBarThickness or 0)
			local page = drawerOpen and activeId or nil
			if page ~= scrollPage or (not overflow and drawerViewport.CanvasPosition.X ~= 0) then
				drawerViewport.CanvasPosition = Vector2.new(0, 0)
			end
			scrollPage = page
			local availableHeight = math.max(1, height - Theme.sizes.topBar - Theme.sizes.bar - 24)
			drawer.Size = UDim2.new(1, -(drawerLeft + 8), 0, math.min(managing and 510 or Theme.sizes.drawerHeight, availableHeight))
			local feedbackLeft = visibleWidth < 620 and 10 or 152
			drawerTitle.Visible = not (feedbackLeft == 10 and feedback.Visible)
			drawerTitle.Size = feedback.Visible and UDim2.new(0, 138, 1, 0) or UDim2.new(1, -120, 1, 0)
			feedback.Position = UDim2.fromOffset(feedbackLeft, 0)
			feedback.Size = UDim2.new(1, -(feedbackLeft + 102), 1, 0)
			panels.personnel.resize(contentWidth - 24)
			local centerWidth = math.clamp(width - Theme.sizes.tabsCompact - self.map.root.Size.X.Offset - 32, 1, 720)
			local journalWidth = centerWidth
			local journalHeight = 142
			if journalSize then
				local maximumWidth = math.max(1, width - Theme.sizes.tabsCompact - self.map.root.Size.X.Offset - 32)
				journalWidth = math.clamp(journalSize.X, math.min(180, maximumWidth), maximumWidth)
				local maximumHeight = math.max(1, availableHeight - 54)
				journalHeight = math.clamp(journalSize.Y, math.min(80, maximumHeight), maximumHeight)
			end
			logPanel.Size = UDim2.fromOffset(journalWidth, journalHeight)
			radioPanel.Size = UDim2.fromOffset(centerWidth, 44)
			toastsRoot.Size = UDim2.fromOffset(math.min(380, centerWidth), 190)
		end
		if camera then
			if absolute and absolute.X and absolute.Y and absolute.X > 0 and absolute.Y > 0 then
				camera:setViewport(absolute.X, absolute.Y)
			end
			if camera.followId ~= nil then
				local followed = nil
				for _, vehicle in ipairs(vehicles) do
					if vehicle.id == camera.followId then
						followed = vehicle
					end
				end
				if followed then
					camera:track(followed.x, followed.z)
				else
					camera:follow(nil)
				end
			end
			local extent = camera:viewExtent()
			view = {
				x = camera.target.x,
				z = camera.target.z,
				width = extent.width,
				height = extent.height,
			}
		end

		map.update(snapshot, state, view)
		bottom.update(snapshot, state)

		if self.scene then
			self.scene:update(snapshot, state)
		end

		logRows.update(snapshot.log or {})
		toastRows.update(controller.toasts or {})
		menu.update(snapshot, state)

		if self.audio then
			self.audio:update(snapshot)
			radioPanel.Visible = type(self.audio.radioCaption) == "string" and self.audio.radioCaption ~= ""
			radioText.Text = radioPanel.Visible and ("Radio · " .. self.audio.radioCaption) or ""
			toastsRoot.Position = UDim2.fromOffset(Theme.sizes.tabsCompact + 16, Theme.sizes.topBar + (radioPanel.Visible and 58 or 8))
			local latest = nil
			for _, toast in ipairs(controller.toasts or {}) do
				if (toast.id or 0) > (self.lastToastId or 0) then
					latest = toast
				end
			end
			if latest then
				self.audio:play(latest.ok and "confirm" or "error")
				self.lastToastId = latest.id or self.lastToastId
			end
		end
		local size = gui.AbsoluteSize
		resizeTopbar()
		if editor.editing then
			status.Visible, brandName.Visible, city.Visible = false, false, false
		end
		if size.X > 0 and size.Y > 0 then
			editor:apply(size.X / hudScale.Scale, size.Y / hudScale.Scale, hudScale.Scale)
		end
	end

	return app
end

return App
