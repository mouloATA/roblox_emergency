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
local MainMenu = require(UI:WaitForChild("MainMenu"))

local App = {}

App.tabs = {
	{ id = "incidents", label = "Interventions", key = "1" },
	{ id = "vehicles", label = "Véhicules", key = "2" },
	{ id = "personnel", label = "Personnel", key = "3" },
	{ id = "equipment", label = "Matériel", key = "4" },
	{ id = "command", label = "Commandement", key = "5" },
	{ id = "budget", label = "Budget", key = "6" },
	{ id = "roles", label = "Postes", key = "7" },
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
	gui.IgnoreGuiInset = true
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

	-- ── Barre supérieure ──────────────────────────────────────
	local topBar = Widgets.frame(root, "BarreSuperieure", {
		BackgroundColor3 = Theme.colors.panelDark,
		BackgroundTransparency = 0.08,
		Size = UDim2.new(1, 0, 0, Theme.sizes.topBar),
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
		Size = UDim2.fromOffset(300, 18),
		TextSize = Theme.text.small,
		Font = Theme.fonts.bold,
	})
	local city = Widgets.label(topBar, "Ville", string.format("%s · centre 112", Config.CITY_NAME), {
		Position = UDim2.fromOffset(58, 25),
		Size = UDim2.fromOffset(300, 14),
		TextSize = 9,
		TextColor3 = Theme.colors.textMuted,
	})

	local status = Widgets.label(topBar, "Statut", "Synchronisation…", {
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(700, 22),
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

	local tabBody = Widgets.vertical(tabColumn, "Liste", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	Widgets.section(tabBody, "Panneaux")

	local tabButtons = {}
	for _, tab in ipairs(App.tabs) do
		local button = Widgets.button(tabBody, "Action_tab_" .. tab.id, tab.key .. "  " .. tab.label, function()
			if audio then
				audio:play("click")
			end
			controller:setTab(tab.id)
		end, {
			Size = UDim2.new(1, 0, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 10,
			BackgroundColor3 = Theme.colors.command,
			TextColor3 = Theme.colors.textDim,
		})
		tabButtons[tab.id] = button
	end

	Widgets.label(tabBody, "Aide", "WASD/carte : déplacer\n+/- : zoom · Q/E : pivoter\n1–6 : groupes · Espace : pause\nM : menu · R : recentrer", {
		Size = UDim2.new(1, 0, 0, 76),
		TextSize = 8,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		TextColor3 = Theme.colors.textMuted,
	})

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
	local logHint = Widgets.label(logPanel, "Aide", "Le plus récent en tête", {
		Size = UDim2.new(0, 200, 0, 14),
		TextSize = 8,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.colors.textMuted,
	})
	logHint.Position = UDim2.new(1, -204, 0, 0)

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
	local drawer = Widgets.frame(root, "Tiroir", {
		BackgroundColor3 = Theme.colors.panelDark,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 8, 1, -(Theme.sizes.bar + 8)),
		Size = UDim2.new(1, -16, 0, Theme.sizes.drawerHeight),
		ZIndex = 20,
		Visible = false,
		-- Un panneau ne doit jamais déborder sur la barre inférieure : son
		-- contenu défile à l'intérieur du tiroir.
		ClipsDescendants = true,
	})
	Widgets.stroke(drawer, Theme.colors.steel, 2)
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
	local drawerClose = Widgets.button(drawerHeader, "Action_fermer_tiroir", "FERMER  ✕", function()
		controller:closeDrawer()
	end, {
		Position = UDim2.new(1, -92, 0, 3),
		Size = UDim2.fromOffset(84, 20),
		TextSize = 9,
		BackgroundColor3 = Theme.colors.command,
		TextColor3 = Theme.colors.commandText,
	})

	local drawerContent = Widgets.frame(drawer, "ContenuTiroir", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 1, -26),
	})

	local panels = {
		incidents = IncidentPanel.create(drawerContent, { controller = controller, snapshot = context.snapshot }),
		vehicles = VehiclePanel.create(drawerContent, { controller = controller, snapshot = context.snapshot }),
		personnel = PersonnelPanel.create(drawerContent, { controller = controller, snapshot = context.snapshot }),
		equipment = EquipmentPanel.create(drawerContent, { controller = controller, snapshot = context.snapshot }),
		command = CommandPanel.create(drawerContent, { controller = controller, snapshot = context.snapshot }),
		budget = BudgetPanel.create(drawerContent, { controller = controller, snapshot = context.snapshot }),
		roles = MultiplayerPanel.create(drawerContent, { controller = controller, snapshot = context.snapshot }),
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

	local app = {
		gui = gui,
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

	function app:render(state: any, snapshot: any)
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
			local active = state.tab == id and state.drawer ~= "none"
			button.BackgroundColor3 = active and Theme.colors.panelLight or Theme.colors.command
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

		for id, panel in pairs(panels) do
			panel.update(snapshot, state)
			panel.root.Visible = drawerOpen and id == activeId
		end

		-- Cadre de visée : la mini-carte montre ce que voit la caméra.
		local view = nil
		local camera = self.camera
		local absolute = gui.AbsoluteSize
		if absolute and absolute.X and absolute.Y then
			-- La mini-carte se réduit pour ne jamais passer sous la barre.
			self.map.resize(absolute.X, absolute.Y)
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
	end

	return app
end

return App
