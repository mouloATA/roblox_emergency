--!strict
--[[
	BottomBar — barre inférieure fixe, cœur du gameplay.

	Quatre zones, comme dans Emergency 4 :
	1. catégories de moyens (INC, SAP, POL, TEC, LOG, CMD) ;
	2. groupes 1 à 6, pause et vitesses, horloge et budget ;
	3. commandes contextuelles réelles (engager, rentrer, armer, suivre…) ;
	4. personnel et matériel de l'unité sélectionnée.

	Aucun bouton n'est décoratif : chacun ouvre le tiroir, change la vitesse de
	simulation validée par le serveur, ou envoie une intention existante.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))

local UI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ERSClient"):WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))
local EngagementHints = require(UI:WaitForChild("EngagementHints"))

local BottomBar = {}

local CATEGORIES = {
	{ id = "fire", abbr = "INC", label = "Incendie" },
	{ id = "medical", abbr = "SAP", label = "Secours" },
	{ id = "police", abbr = "POL", label = "Police" },
	{ id = "technical", abbr = "TEC", label = "Technique" },
	{ id = "logistics", abbr = "LOG", label = "Logistique" },
	{ id = "command", abbr = "CMD", label = "Commandement" },
}

local function commandButton(parent: any, name: string, text: string, onClick: () -> ()): any
	return Widgets.button(parent, name, text, onClick, {
		BackgroundColor3 = Theme.colors.command,
		TextColor3 = Theme.colors.commandText,
		TextSize = 11,
		Font = Theme.fonts.bold,
	})
end

local function countByService(vehicles: { any }): any
	local counts = {}
	for _, vehicle in ipairs(vehicles or {}) do
		counts[vehicle.service] = (counts[vehicle.service] or 0) + 1
	end
	return counts
end

function BottomBar.create(parent: any, context: any): any
	local controller = context.controller
	local camera = context.camera

	local root = Widgets.frame(parent, "BarreInferieure", {
		BackgroundColor3 = Theme.colors.panelDark,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, Theme.sizes.bar),
		ZIndex = 12,
	})
	Widgets.stroke(root, Theme.colors.steel, 2)

	local content = Widgets.frame(root, "Contenu", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 6),
		Size = UDim2.new(1, -16, 1, -12),
	})

	-- ── 1. Catégories de moyens ───────────────────────────────
	local means = Widgets.frame(content, "Moyens", {
		BackgroundColor3 = Theme.colors.panel,
		Size = UDim2.new(0, 330, 1, 0),
	})
	Widgets.stroke(means, Theme.colors.steel, 1)
	Widgets.padding(means, 6, 2)

	Widgets.section(means, "Moyens disponibles")
	local categories = {}
	local cellWidth = (330 - 12 - 8) / 3
	for index, category in ipairs(CATEGORIES) do
		local column = (index - 1) % 3
		local row = math.floor((index - 1) / 3)
		local button = Widgets.button(means, "Categorie_" .. category.id, category.abbr, function()
			controller:openCategory(category.id)
		end, {
			Position = UDim2.fromOffset(column * (cellWidth + 4), 22 + row * 58),
			Size = UDim2.fromOffset(cellWidth, 52),
			TextSize = 15,
			Font = Theme.fonts.bold,
			BackgroundColor3 = Theme.colors.panelLight,
			TextColor3 = Theme.serviceColor[category.id] or Theme.colors.text,
		})
		local stroke = Widgets.stroke(button, Theme.colors.steel, 1)

		local caption = Widgets.label(button, "Libelle", category.label, {
			Position = UDim2.fromOffset(4, 26),
			Size = UDim2.new(1, -8, 0, 14),
			TextSize = 9,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Theme.colors.text,
		})
		local count = Widgets.label(button, "Compte", "0", {
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, -8, 0, 14),
			TextSize = 10,
			Font = Theme.fonts.mono,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Theme.colors.active,
		})
		categories[category.id] = { instance = button, label = caption, count = count, stroke = stroke }
	end

	-- ── 2. Groupes, temps, horloge et budget ──────────────────
	local groupsPanel = Widgets.frame(content, "GroupesTemps", {
		BackgroundColor3 = Theme.colors.panel,
		Position = UDim2.fromOffset(336, 0),
		Size = UDim2.new(0, 226, 1, 0),
	})
	Widgets.stroke(groupsPanel, Theme.colors.steel, 1)
	Widgets.padding(groupsPanel, 6, 2)

	Widgets.section(groupsPanel, "Groupes 1–6")
	local groups = {}
	local groupCell = (226 - 12 - 15) / 6
	for slot = 1, Config.GROUP_HOTKEYS do
		local button = Widgets.button(groupsPanel, "Groupe_" .. slot, tostring(slot), function()
			controller:selectGroupSlot(slot)
		end, {
			Position = UDim2.fromOffset((slot - 1) * (groupCell + 3), 22),
			Size = UDim2.fromOffset(groupCell, 24),
			TextSize = 11,
			Font = Theme.fonts.mono,
			BackgroundColor3 = Theme.colors.command,
			TextColor3 = Theme.colors.textDim,
		})
		groups[slot] = button
	end

	local pauseButton = Widgets.button(groupsPanel, "Action_pause", "PAUSE", function()
		local paused = (controller.snapshot.timeScale or 1) == 0
		controller:setTimeScale(paused and 1 or 0)
	end, {
		Position = UDim2.fromOffset(4, 52),
		Size = UDim2.fromOffset(74, 24),
		TextSize = 9,
		Font = Theme.fonts.bold,
		BackgroundColor3 = Theme.colors.command,
		TextColor3 = Theme.colors.commandText,
	})

	local speeds = {}
	local speedValues = { 1, 2, 4 }
	for index, scale in ipairs(speedValues) do
		local button = Widgets.button(groupsPanel, "Action_vitesse_" .. scale, "×" .. scale, function()
			controller:setTimeScale(scale)
		end, {
			Position = UDim2.fromOffset(82 + (index - 1) * 45, 52),
			Size = UDim2.fromOffset(41, 24),
			TextSize = 10,
			Font = Theme.fonts.mono,
			BackgroundColor3 = Theme.colors.command,
			TextColor3 = Theme.colors.textDim,
		})
		speeds[scale] = button
	end

	local clock = Widgets.label(groupsPanel, "Horloge", "--:--", {
		Position = UDim2.fromOffset(4, 82),
		Size = UDim2.new(1, -8, 0, 26),
		TextSize = 22,
		Font = Theme.fonts.mono,
		TextColor3 = Theme.colors.text,
	})
	local clockHint = Widgets.label(groupsPanel, "HorlogeAide", "heure simulée", {
		Position = UDim2.fromOffset(4, 106),
		Size = UDim2.new(1, -8, 0, 12),
		TextSize = 8,
		TextColor3 = Theme.colors.textMuted,
	})
	local budget = Widgets.label(groupsPanel, "Budget", "", {
		Position = UDim2.fromOffset(4, 122),
		Size = UDim2.new(1, -8, 0, 18),
		TextSize = 13,
		Font = Theme.fonts.bold,
		TextColor3 = Theme.colors.warning,
	})
	local alerts = Widgets.label(groupsPanel, "Alertes", "", {
		Position = UDim2.fromOffset(4, 142),
		Size = UDim2.new(1, -8, 0, 16),
		TextSize = 9,
		TextColor3 = Theme.colors.textDim,
	})

	-- ── 3. Commandes contextuelles ────────────────────────────
	local commandPanel = Widgets.frame(content, "CommandesContextuelles", {
		BackgroundColor3 = Theme.colors.panelDark,
		Position = UDim2.fromOffset(568, 0),
		Size = UDim2.new(1, -(568 + 340 + 12), 1, 0),
	})
	Widgets.stroke(commandPanel, Theme.colors.steel, 1)
	Widgets.padding(commandPanel, 6, 2)

	local commandTitle = Widgets.section(commandPanel, "Commandes de l'unité")
	local commandContext = Widgets.label(commandPanel, "Contexte", "Aucune sélection", {
		Position = UDim2.fromOffset(2, 18),
		Size = UDim2.new(1, -4, 0, 16),
		TextSize = 9,
		TextColor3 = Theme.colors.textDim,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local commands = {}

	local function placeCommand(name: string, text: string, column: number, row: number, onClick: () -> ()): any
		local button = commandButton(commandPanel, name, text, onClick)
		button.Position = UDim2.new(column * 0.25, 2, 0, 36 + row * 36)
		button.Size = UDim2.new(0.25, -4, 0, 32)
		commands[name] = button
		return button
	end

	commands.engage = placeCommand("Action_engager", "ENGAGER", 0, 0, function()
		local vehicle = controller:selectedVehicle()
		local incident = controller:selectedIncident()
		if vehicle and incident then
			controller:command("dispatch", { vehicleId = vehicle.id, incidentId = incident.id })
		else
			controller:toast("Sélectionnez un engin et une intervention.", false)
		end
	end)

	commands.engageGroup = placeCommand("Action_engager_groupe", "ENGAGER GRP", 1, 0, function()
		local group = controller:selectedGroup()
		local incident = controller:selectedIncident()
		if group and incident then
			controller:command("dispatch_group", { groupId = group.id, incidentId = incident.id })
		else
			controller:toast("Sélectionnez un groupe et une intervention.", false)
		end
	end)

	commands.recall = placeCommand("Action_rentrer", "RENTRER", 2, 0, function()
		local vehicle = controller:selectedVehicle()
		if vehicle then
			controller:command("recall", { vehicleId = vehicle.id })
		else
			controller:toast("Aucun engin sélectionné.", false)
		end
	end)

	commands.crew = placeCommand("Action_armer", "ARMER", 3, 0, function()
		local vehicle = controller:selectedVehicle()
		if vehicle then
			controller:command("auto_crew", { vehicleId = vehicle.id })
		else
			controller:toast("Aucun engin sélectionné.", false)
		end
	end)

	commands.follow = placeCommand("Action_suivre", "SUIVRE", 0, 1, function()
		local vehicle = controller:selectedVehicle()
		if not camera then
			controller:toast("Caméra indisponible.", false)
		elseif not vehicle then
			controller:toast("Sélectionnez un engin à suivre.", false)
		elseif camera.followId == vehicle.id then
			camera:follow(nil)
			controller:toast("Suivi caméra arrêté.", true)
		else
			camera:focus(vehicle.x, vehicle.z)
			camera:follow(vehicle.id)
			controller:toast("Caméra sur " .. vehicle.callsign .. ".", true)
		end
	end)

	commands.center = placeCommand("Action_centrer", "CENTRER", 1, 1, function()
		if not camera then
			controller:toast("Caméra indisponible.", false)
			return
		end
		local vehicle = controller:selectedVehicle()
		local incident = controller:selectedIncident()
		if vehicle then
			camera:focus(vehicle.x, vehicle.z)
		elseif incident then
			camera:focus(incident.x, incident.z)
		else
			camera:reset()
		end
	end)

	commands.sheet = placeCommand("Action_fiche", "FICHE", 2, 1, function()
		local vehicle = controller:selectedVehicle()
		local incident = controller:selectedIncident()
		if vehicle then
			controller:setTab("vehicles")
		elseif incident then
			controller:setTab("incidents")
		else
			controller:toast("Aucune fiche à ouvrir.", false)
		end
	end)

	commands.equipment = placeCommand("Action_materiel", "MATÉRIEL", 3, 1, function()
		if controller:selectedVehicle() then
			controller:setTab("equipment")
		else
			controller:toast("Sélectionnez un engin.", false)
		end
	end)

	local commandHint = Widgets.label(commandPanel, "Aide", "Clic carte : sélectionner · double-clic : recentrer", {
		Position = UDim2.fromOffset(2, 110),
		Size = UDim2.new(1, -4, 0, 14),
		TextSize = 9,
		TextColor3 = Theme.colors.textMuted,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	-- ── 4. Personnel et matériel ──────────────────────────────
	local crewPanel = Widgets.frame(content, "Personnel", {
		BackgroundColor3 = Theme.colors.panel,
		Position = UDim2.new(1, -340, 0, 0),
		Size = UDim2.new(0, 340, 1, 0),
	})
	Widgets.stroke(crewPanel, Theme.colors.steel, 1)
	Widgets.padding(crewPanel, 6, 2)

	Widgets.section(crewPanel, "Personnel & matériel")
	local unitLabel = Widgets.label(crewPanel, "Unite", "Aucune unité sélectionnée", {
		Position = UDim2.fromOffset(2, 20),
		Size = UDim2.new(1, -4, 0, 18),
		TextSize = 12,
		Font = Theme.fonts.bold,
		TextColor3 = Theme.colors.text,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local roleLabel = Widgets.label(crewPanel, "Service", "", {
		Position = UDim2.fromOffset(2, 38),
		Size = UDim2.new(1, -4, 0, 14),
		TextSize = 9,
		TextColor3 = Theme.colors.textDim,
	})
	local healthBar = Widgets.bar(crewPanel, "Sante", {
		Position = UDim2.fromOffset(2, 54),
		Size = UDim2.new(1, -4, 0, 6),
	})
	local healthText = Widgets.label(crewPanel, "SanteTexte", "", {
		Position = UDim2.fromOffset(2, 61),
		Size = UDim2.new(1, -4, 0, 14),
		TextSize = 9,
		TextColor3 = Theme.colors.textMuted,
	})
	local statusText = Widgets.label(crewPanel, "Statut", "", {
		Position = UDim2.fromOffset(2, 75),
		Size = UDim2.new(1, -4, 0, 14),
		TextSize = 9,
		TextColor3 = Theme.colors.active,
	})

	local crewRows = {}
	for index = 1, 4 do
		crewRows[index] = Widgets.label(crewPanel, "Membre_" .. index, "", {
			Position = UDim2.fromOffset(2, 91 + (index - 1) * 14),
			Size = UDim2.new(1, -4, 0, 13),
			TextSize = 9,
			TextColor3 = Theme.colors.textDim,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	local equipmentText = Widgets.label(crewPanel, "MaterielResume", "", {
		Position = UDim2.fromOffset(2, 149),
		Size = UDim2.new(1, -4, 0, 14),
		TextSize = 8,
		TextColor3 = Theme.colors.textMuted,
	})

	local function setCamera(value: any): ()
		camera = value
	end

	local function update(snapshot: any, state: any): ()
		local vehicles = snapshot.vehicles or {}
		local incidents = snapshot.incidents or {}
		local counts = countByService(vehicles)

		for _, category in ipairs(CATEGORIES) do
			local view = categories[category.id]
			view.count.Text = tostring(counts[category.id] or 0)
			local active = state.category == category.id and state.drawer == "vehicles"
			view.instance.BackgroundColor3 = active and Theme.colors.panelLight or Theme.colors.panel
			view.stroke.Color = active and Theme.colors.active or Theme.colors.steel
			view.stroke.Thickness = active and 2 or 1
		end

		-- Groupes : l'ordre d'affichage suit l'identifiant, comme les raccourcis.
		local sorted = {}
		for _, group in ipairs(snapshot.groups or {}) do
			table.insert(sorted, group)
		end
		table.sort(sorted, function(a, b)
			return a.id < b.id
		end)
		for slot, button in pairs(groups) do
			local group = sorted[slot]
			button.Text = group and tostring(slot) or tostring(slot)
			if group then
				local selected = controller.state.groupSlot == slot
				button.BackgroundColor3 = selected and Theme.colors.active or Theme.colors.panelLight
				button.TextColor3 = selected and Theme.colors.background or Theme.colors.text
			else
				button.BackgroundColor3 = Theme.colors.command
				button.TextColor3 = Theme.colors.textMuted
			end
		end

		local scale = snapshot.timeScale or 1
		local paused = scale == 0
		pauseButton.Text = paused and "REPRENDRE" or "PAUSE"
		pauseButton.BackgroundColor3 = paused and Theme.colors.active or Theme.colors.command
		pauseButton.TextColor3 = paused and Theme.colors.background or Theme.colors.commandText
		for value, button in pairs(speeds) do
			local active = not paused and scale == value
			button.BackgroundColor3 = active and Theme.colors.active or Theme.colors.command
			button.TextColor3 = active and Theme.colors.background or Theme.colors.textDim
		end

		clock.Text = snapshot.clock or "--:--"
		budget.Text = Theme.money(snapshot.budget or 0)
		alerts.Text = string.format(
			"%d véhicule(s) · %d urgence(s) · %d secteur(s)",
			#vehicles,
			#incidents,
			#(snapshot.sectors or {})
		)

		local vehicle = controller:selectedVehicle()
		local incident = controller:selectedIncident()
		local group = controller:selectedGroup()

		if vehicle and incident then
			commandContext.Text = string.format("%s → %s", vehicle.callsign, incident.name)
		elseif vehicle then
			commandContext.Text = string.format("%s · %s", vehicle.callsign, Theme.serviceLabel(vehicle.service))
		elseif incident then
			commandContext.Text = string.format("%s · %s", incident.name, Theme.statusLabel(incident.status))
		else
			commandContext.Text = "Aucune sélection — cliquez un engin ou une intervention."
		end

		local inScope = vehicle ~= nil and controller:canService(vehicle.service)
		Widgets.setEnabled(
			commands.engage,
			vehicle ~= nil
				and incident ~= nil
				and vehicle.status == Constants.VEHICLE_STATUS.AVAILABLE
				and (vehicle.crewCount or 0) >= (vehicle.crewRequired or 0)
				and controller:can("dispatch")
				and inScope
		)
		Widgets.setEnabled(
			commands.engageGroup,
			group ~= nil and incident ~= nil and #(group.vehicles or {}) > 0 and controller:can("dispatch")
		)
		Widgets.setEnabled(
			commands.recall,
			vehicle ~= nil
				and (vehicle.status == Constants.VEHICLE_STATUS.DISPATCHED
					or vehicle.status == Constants.VEHICLE_STATUS.ON_SCENE)
				and controller:can("recall")
				and inScope
		)
		Widgets.setEnabled(
			commands.crew,
			vehicle ~= nil
				and vehicle.status == Constants.VEHICLE_STATUS.AVAILABLE
				and (vehicle.crewCount or 0) < (vehicle.crewRequired or 0)
				and controller:can("assign_personnel")
				and inScope
		)
		Widgets.setEnabled(commands.follow, vehicle ~= nil)
		Widgets.setEnabled(commands.center, vehicle ~= nil or incident ~= nil)
		Widgets.setEnabled(commands.sheet, vehicle ~= nil or incident ~= nil)
		Widgets.setEnabled(
			commands.equipment,
			vehicle ~= nil and controller:can("equipment") and inScope
		)

		-- Aide contextuelle : explique pourquoi l'engagement est impossible, ou
		-- signale les capacités que l'engin sélectionné ne fournit pas.
		local closed = incident ~= nil
			and (incident.status == Constants.INCIDENT_STATUS.RESOLVED
				or incident.status == Constants.INCIDENT_STATUS.FAILED)
		local hint = EngagementHints.engageHint(
			vehicle,
			incident,
			controller:can("dispatch"),
			vehicle ~= nil and inScope or true,
			closed
		)
		if hint and vehicle then
			commandHint.Text = hint
			commandHint.TextColor3 = Theme.colors.warning
		else
			commandHint.Text = "Clic carte : sélectionner · double-clic : recentrer"
			commandHint.TextColor3 = Theme.colors.textMuted
		end

		-- Panneau personnel : personne sélectionnée, sinon équipage de l'engin.
		local person = controller:selectedPerson()
		if person then
			unitLabel.Text = person.name or "Membre"
			roleLabel.Text = string.format("%s · %s", person.grade or "—", Theme.serviceLabel(person.service))
			local health = math.clamp(person.health or 0, 0, 100)
			healthBar.set(health / 100)
			healthBar.setColor(health >= 60 and Theme.colors.active or Theme.colors.warning)
			healthText.Text = string.format("Santé %s · fatigue %s", Theme.percent(health), Theme.percent(person.fatigue or 0))
			if person.vehicleId then
				statusText.Text = "Affecté à un engin"
			else
				statusText.Text = Theme.statusLabel(person.status)
			end
			for index, row in ipairs(crewRows) do
				row.Text = index == 1 and ("● " .. (person.name or "")) or ""
			end
			equipmentText.Text = "Équipement individuel du membre"
		elseif vehicle then
			unitLabel.Text = string.format("%s — %s", vehicle.callsign, vehicle.name)
			roleLabel.Text = Theme.serviceLabel(vehicle.service)
			local condition = math.clamp(vehicle.condition or 0, 0, 100)
			healthBar.set(condition / 100)
			healthBar.setColor(condition >= 60 and Theme.colors.active or (condition >= 30 and Theme.colors.warning or Theme.colors.danger))
			healthText.Text = string.format("État mécanique %s", Theme.percent(condition))
			statusText.Text = string.format(
				"%s · %d/%d membre(s)",
				Theme.statusLabel(vehicle.status),
				vehicle.crewCount or 0,
				vehicle.crewRequired or 0
			)
			for index, row in ipairs(crewRows) do
				local name = (vehicle.crew or {})[index]
				if name then
					row.Text = "● " .. name
					row.TextColor3 = Theme.colors.textDim
				elseif index <= (vehicle.crewRequired or 0) then
					row.Text = "○ Poste libre"
					row.TextColor3 = Theme.colors.textMuted
				else
					row.Text = ""
				end
			end
			local quantity = 0
			for _, item in ipairs(vehicle.equipment or {}) do
				quantity += item.quantity or 0
			end
			equipmentText.Text = string.format(
				"Matériel : %d référence(s) · %d unité(s)",
				#(vehicle.equipment or {}),
				quantity
			)
		else
			unitLabel.Text = "Aucune unité sélectionnée"
			roleLabel.Text = "Cliquez un engin, un marqueur ou une ligne."
			healthBar.set(0)
			healthText.Text = ""
			statusText.Text = ""
			for _, row in ipairs(crewRows) do
				row.Text = ""
			end
			equipmentText.Text = ""
		end
	end

	update(context.snapshot or {
		vehicles = {},
		incidents = {},
		groups = {},
		sectors = {},
		timeScale = 1,
	}, controller.state)

	return {
		root = root,
		update = update,
		setCamera = setCamera,
		categories = categories,
		groups = groups,
		time = { pause = pauseButton, speeds = speeds },
		commands = commands,
		crew = {
			root = crewPanel,
			unitLabel = unitLabel,
			roleLabel = roleLabel,
			healthBar = healthBar,
			healthText = healthText,
			statusText = statusText,
			crewRows = crewRows,
			equipmentText = equipmentText,
		},
		clock = clock,
		budget = budget,
		commandContext = commandContext,
		commandHint = commandHint,
	}
end

return BottomBar
