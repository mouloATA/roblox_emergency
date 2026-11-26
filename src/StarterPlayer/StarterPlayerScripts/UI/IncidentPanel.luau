--!strict
--[[
	IncidentPanel — réception, briefing et conduite des interventions.

	Le panneau présente l'urgence sélectionnée : nature, gravité, briefing,
	étape en cours, moyens exigés, matériel et qualifications. Les boutons
	engagent ou rappellent l'engin sélectionné sur cette urgence ; le serveur
	vérifie ensuite l'équipage, le périmètre et la disponibilité.

	Un incident clos reste consultable mais ne peut plus recevoir de moyens.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Catalogs = Shared:WaitForChild("Catalogs")
local Equipment = require(Catalogs:WaitForChild("Equipment"))
local Qualifications = require(Catalogs:WaitForChild("Qualifications"))

local UI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ERSClient"):WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))
local EngagementHints = require(UI:WaitForChild("EngagementHints"))

local IncidentPanel = {}

local SEVERITY_LABEL = { "Léger", "Grave", "Critique" }

local function capabilityText(requires: any): string
	local parts = {}
	for key, value in pairs(requires or {}) do
		table.insert(parts, string.format("%s %d", Constants.CAPABILITY_LABEL[key] or key, value))
	end
	if #parts == 0 then
		return "aucun moyen particulier"
	end
	table.sort(parts)
	return table.concat(parts, " · ")
end

local function labelList(ids: { any }, catalog: any): string
	local labels = {}
	for _, id in ipairs(ids or {}) do
		table.insert(labels, catalog.label(id))
	end
	if #labels == 0 then
		return "aucun"
	end
	table.sort(labels)
	return table.concat(labels, ", ")
end

local function statusColor(status: string): any
	if status == Constants.INCIDENT_STATUS.ACTIVE then
		return Theme.colors.accent
	elseif status == Constants.INCIDENT_STATUS.RESOLVED then
		return Theme.colors.success
	elseif status == Constants.INCIDENT_STATUS.FAILED then
		return Theme.colors.danger
	end
	return Theme.colors.warning
end

function IncidentPanel.create(parent: any, context: any): any
	local controller = context.controller

	local root = Widgets.frame(parent, "PanneauInterventions", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	Widgets.padding(root, 10, 2)

	local title = Widgets.label(root, "Titre", "INTERVENTIONS", {
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = Theme.text.subtitle,
		Font = Theme.fonts.bold,
	})
	local subtitle = Widgets.label(root, "SousTitre", "", {
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.text.tiny,
		TextColor3 = Theme.colors.textMuted,
	})

	-- Deux colonnes : la liste des urgences à gauche, le détail à droite. Le
	-- tiroir est large mais peu haut : empiler les deux aurait fait déborder
	-- le détail sur la barre inférieure.
	local listColumn = Widgets.frame(root, "ColonneListe", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(0.42, -6, 1, -46),
	})
	local list = Widgets.scroller(listColumn, "Liste", {
		Size = UDim2.fromScale(1, 1),
	})

	local detailColumn = Widgets.frame(root, "ColonneDetail", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.42, 6, 0, 46),
		Size = UDim2.new(0.58, -6, 1, -46),
	})
	local detail = Widgets.scroller(detailColumn, "Detail", {
		Size = UDim2.fromScale(1, 1),
	})

	local detailTitle = Widgets.label(detail, "DetailTitre", "Sélectionnez une intervention", {
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = Theme.text.subtitle,
		Font = Theme.fonts.bold,
	})
	local detailStatus = Widgets.label(detail, "DetailStatut", "", {
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.text.small,
		TextColor3 = Theme.colors.textDim,
	})
	local briefing = Widgets.label(detail, "Briefing", "", {
		Size = UDim2.new(1, 0, 0, 58),
		TextSize = Theme.text.tiny,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.colors.textDim,
	})
	local progressBar = Widgets.bar(detail, "Etape", { Size = UDim2.new(1, 0, 0, 6) })
	local progressLabel = Widgets.label(detail, "EtapeTexte", "", {
		Size = UDim2.new(1, 0, 0, 16),
		TextSize = Theme.text.tiny,
		TextColor3 = Theme.colors.textMuted,
	})
	local requiresLabel = Widgets.label(detail, "Moyens", "", {
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = Theme.text.tiny,
		TextWrapped = true,
		TextColor3 = Theme.colors.textDim,
	})
	local needsLabel = Widgets.label(detail, "Materiel", "", {
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = Theme.text.tiny,
		TextWrapped = true,
		TextColor3 = Theme.colors.textDim,
	})
	local onSceneLabel = Widgets.label(detail, "SurPlace", "", {
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.text.tiny,
		TextColor3 = Theme.colors.info,
	})

	local fieldStatus = Widgets.label(detail, "BilanTerrain", "", {
		Size = UDim2.new(1, 0, 0, 56), TextSize = Theme.text.small,
		TextWrapped = true, TextColor3 = Theme.colors.textDim,
	})
	local orderButtons = {}
	for _, order in ipairs({ "auto", "hold", "extinguish", "rescue", "extricate" }) do
		local button = Widgets.button(detail, "Ordre_" .. order, Constants.FIELD_LABEL[order], function()
			local vehicle, incident = controller:selectedVehicle(), controller:selectedIncident()
			if vehicle and incident then
				controller:command("field_order", { incidentId = incident.id, vehicleId = vehicle.id, order = order })
			end
		end, { Size = UDim2.new(1, -6, 0, 30), TextSize = Theme.text.small })
		button.Visible = false
		orderButtons[order] = button
	end

	local actions = Widgets.horizontal(detail, "Actions", {
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundTransparency = 1,
	})
	local dispatchButton = Widgets.button(actions, "Action_dispatch_urgence", "Engager l'engin", function()
		local incident = controller:selectedIncident()
		local vehicle = controller:selectedVehicle()
		if incident and vehicle then
			controller:command("dispatch", { vehicleId = vehicle.id, incidentId = incident.id })
		elseif not vehicle then
			controller:toast("Sélectionnez un engin dans la barre ou l'onglet Véhicules.", false)
		else
			controller:toast("Sélectionnez d'abord une intervention.", false)
		end
	end, { Size = UDim2.fromOffset(140, 34), TextSize = Theme.text.tiny })

	local recallButton = Widgets.button(actions, "Action_recall_urgence", "Rappeler", function()
		local vehicle = controller:selectedVehicle()
		if vehicle then
			controller:command("recall", { vehicleId = vehicle.id })
		else
			controller:toast("Sélectionnez l'engin à rappeler.", false)
		end
	end, { Size = UDim2.fromOffset(92, 34), TextSize = Theme.text.tiny })

	local engagementHint = Widgets.label(detail, "AideEngagement", "", {
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = Theme.text.tiny,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.colors.textMuted,
	})

	local rows = Widgets.list(list, function(incident)
		return incident.id
	end, function(incident)
		local row = Widgets.row(list, "UrgenceLigne_" .. incident.id, 58, function()
			controller:select("incident", incident.id)
		end)
		local name = Widgets.label(row, "Nom", incident.name, {
			Position = UDim2.fromOffset(10, 5),
			Size = UDim2.new(1, -106, 0, 18),
			TextSize = Theme.text.small,
			Font = Theme.fonts.bold,
		})
		local status = Widgets.tag(row, "", Theme.colors.warning)
		status.Position = UDim2.new(1, -92, 0, 5)
		local detailLine = Widgets.label(row, "LigneDetail", "", {
			Position = UDim2.fromOffset(10, 24),
			Size = UDim2.new(1, -22, 0, 15),
			TextSize = 10,
			TextColor3 = Theme.colors.textMuted,
		})
		local deadline = Widgets.label(row, "Delai", "", {
			Position = UDim2.fromOffset(10, 39),
			Size = UDim2.new(1, -22, 0, 14),
			TextSize = 10,
			Font = Theme.fonts.mono,
			TextColor3 = Theme.colors.warning,
		})
		return {
			instance = row,
			name = name,
			status = status,
			detailLine = detailLine,
			deadline = deadline,
		}
	end, function(entry, incident)
		entry.name.Text = incident.name .. " · " .. (SEVERITY_LABEL[incident.severity] or "?")
		entry.status.Text = Theme.statusLabel(incident.status)
		entry.status.BackgroundColor3 = statusColor(incident.status)
		entry.status.Size = UDim2.fromOffset(math.max(46, #entry.status.Text * 8 + 12), 18)
		entry.detailLine.Text = string.format(
			"%s · %d victime(s) · %d moyen(s) sur place",
			incident.id,
			incident.victims,
			#incident.onScene
		)
		entry.deadline.Text = incident.status == Constants.INCIDENT_STATUS.PENDING
				and ("Prise en charge dans " .. Theme.seconds(incident.deadlineIn))
			or (incident.status == Constants.INCIDENT_STATUS.ACTIVE
				and ("Étape " .. math.min(incident.stepIndex, math.max(1, incident.stepCount)) .. "/" .. incident.stepCount)
				or "Clôturée")
		entry.deadline.TextColor3 = incident.deadlineIn <= 20 and Theme.colors.danger or Theme.colors.warning
		Widgets.setSelected(entry.instance, controller.state.incidentId == incident.id)
	end)

	local function update(snapshot: any, state: any)
		local incidents = snapshot.incidents or {}
		rows.update(incidents)

		local open = 0
		for _, incident in ipairs(incidents) do
			if incident.status == Constants.INCIDENT_STATUS.PENDING or incident.status == Constants.INCIDENT_STATUS.ACTIVE then
				open += 1
			end
		end
		subtitle.Text = string.format("%d urgence(s) · %d en cours", #incidents, open)

		local incident = nil
		for _, entry in ipairs(incidents) do
			if entry.id == state.incidentId then
				incident = entry
			end
		end

		if not incident then
			detailTitle.Text = "Sélectionnez une intervention"
			detailStatus.Text = "Cliquez une ligne ou un marqueur « ! » sur la carte."
			briefing.Text = ""
			progressBar.set(0)
			progressLabel.Text = ""
			requiresLabel.Text = ""
			needsLabel.Text = ""
			onSceneLabel.Text = ""
			fieldStatus.Visible = false
			for _, button in pairs(orderButtons) do button.Visible = false end
			engagementHint.Text = "Sélectionnez une intervention, puis un engin."
			Widgets.setEnabled(dispatchButton, false)
			Widgets.setEnabled(recallButton, false)
			return
		end

		detailTitle.Text = incident.name
		detailStatus.Text = string.format(
			"%s · %s · %s · %s",
			incident.id,
			Theme.statusLabel(incident.status),
			SEVERITY_LABEL[incident.severity] or "?",
			Theme.serviceLabel(incident.service)
		)
		detailStatus.TextColor3 = statusColor(incident.status)
		briefing.Text = incident.briefing

		local ratio = 0
		if incident.stepSeconds > 0 then
			ratio = math.clamp(incident.stepProgress / incident.stepSeconds, 0, 1)
		end
		progressBar.set(ratio)
		progressBar.setColor(statusColor(incident.status))
		if incident.status == Constants.INCIDENT_STATUS.PENDING then
			progressLabel.Text = "En attente d'engagement — aucun moyen sur place."
		elseif incident.evacuating and incident.status == Constants.INCIDENT_STATUS.ACTIVE then
			progressLabel.Text = "Évacuation vers les urgences"
			progressBar.set(incident.savedVictims / math.max(1, incident.victims))
		elseif incident.fieldStep and incident.status == Constants.INCIDENT_STATUS.ACTIVE then
			progressLabel.Text = string.format("Étape %d/%d · %s · %d %%", incident.stepIndex, incident.stepCount, incident.stepLabel, math.floor(ratio * 100))
		elseif incident.status == Constants.INCIDENT_STATUS.ACTIVE then
			progressLabel.Text = string.format(
				"Étape %d/%d : %s (%s/%s)",
				math.min(incident.stepIndex, math.max(1, incident.stepCount)),
				incident.stepCount,
				incident.stepLabel,
				Theme.seconds(incident.stepProgress),
				Theme.seconds(incident.stepSeconds)
			)
		else
			progressLabel.Text = incident.outcome and ("Clôture : " .. incident.outcome) or "Clôturée."
		end

		requiresLabel.Text = "Moyens requis : " .. capabilityText(incident.requires)
		needsLabel.Text = string.format(
			"Matériel : %s\nQualifications : %s",
			labelList(incident.equipment, Equipment),
			labelList(incident.qualifications, Qualifications)
		)
		onSceneLabel.Text = string.format(
			"Engagés %d · sur place %d · victimes sauvées %d/%d",
			#incident.assigned,
			#incident.onScene,
			incident.savedVictims,
			incident.victims
		)

		local vehicle = controller:selectedVehicle()
		local closed = incident.status == Constants.INCIDENT_STATUS.RESOLVED
			or incident.status == Constants.INCIDENT_STATUS.FAILED
		local fieldLines = {}
		if #(incident.fireCells or {}) > 0 then
			local flames, loss = 0, 0
			for _, cell in ipairs(incident.fireCells) do
				if cell.burning then flames += 1 end
				if cell.spent then loss += 1 end
			end
			table.insert(fieldLines, string.format("Feu · %d foyer(s) actif(s), %d zone(s) brûlée(s), %d L appliqués", flames, loss, incident.waterUsed or 0))
		end
		if (incident.rescueTarget or 0) > 0 then table.insert(fieldLines, string.format("Mises à l'abri · %d/%d", incident.rescued, incident.rescueTarget)) end
		if (incident.extricationTarget or 0) > 0 then table.insert(fieldLines, string.format("Désincarcérations · %d/%d", incident.extricated, incident.extricationTarget)) end
		if incident.evacuating then
			table.insert(fieldLines, string.format("Urgences · %d en attente, %d en transport, %d admise(s)",
				incident.victims - incident.savedVictims - incident.inTransit, incident.inTransit, incident.savedVictims))
		end
		if vehicle and vehicle.incidentId == incident.id then
			local team = vehicle.callsign
			if vehicle.status == Constants.VEHICLE_STATUS.TRANSPORTING and vehicle.route then
				team ..= string.format(" · %d à bord · urgences dans %s", vehicle.patients, Theme.seconds(math.max(0, vehicle.route.startTime + vehicle.route.duration - snapshot.time)))
			elseif vehicle.status == Constants.VEHICLE_STATUS.HANDOVER then
				team ..= " · admission dans " .. Theme.seconds(vehicle.handoverIn or 0)
			elseif vehicle.status == Constants.VEHICLE_STATUS.ON_SCENE then
				team ..= " · " .. (Constants.FIELD_LABEL[vehicle.fieldActivity or vehicle.fieldOrder or "auto"] or "Disponible")
				if (vehicle.waterCapacity or 0) > 0 then team ..= string.format(" · %d L en cuve", vehicle.water) end
				if (vehicle.patientCapacity or 0) > 0 then team ..= string.format(" · %d place(s) sanitaire(s)", vehicle.patientCapacity) end
			end
			table.insert(fieldLines, team)
		end
		fieldStatus.Visible = #fieldLines > 0
		fieldStatus.Size = UDim2.new(1, 0, 0, math.max(22, #fieldLines * 32))
		fieldStatus.Text = table.concat(fieldLines, "\n")
		for order, button in pairs(orderButtons) do
			button.Visible = vehicle ~= nil and vehicle.incidentId == incident.id and table.find(vehicle.fieldChoices or {}, order) ~= nil
			if button.Visible then
				button.Text = Constants.FIELD_LABEL[order] .. " · " .. vehicle.callsign
				Widgets.setEnabled(button, vehicle.fieldOrder ~= order and controller:can("dispatch") and controller:canService(vehicle.service))
			end
		end
		local canDispatch = vehicle ~= nil
			and not closed
			and vehicle.status == Constants.VEHICLE_STATUS.AVAILABLE
			and vehicle.crewCount >= vehicle.crewRequired
			and controller:can("dispatch")
			and controller:canService(vehicle.service)
		local canRecall = vehicle ~= nil
			and vehicle.incidentId == incident.id
			and (vehicle.patients or 0) == 0
			and controller:can("recall")
			and controller:canService(vehicle.service)

		Widgets.setEnabled(dispatchButton, canDispatch)
		dispatchButton.Text = vehicle
				and ("Engager " .. vehicle.callsign)
			or "Choisir un engin"
		Widgets.setEnabled(recallButton, canRecall)

		local hint = EngagementHints.engageHint(
			vehicle,
			incident,
			controller:can("dispatch"),
			vehicle ~= nil and controller:canService(vehicle.service) or true,
			closed
		)
		engagementHint.Text = hint or "Engagement possible : l'engin partira vers cette intervention."
		engagementHint.TextColor3 = hint and Theme.colors.warning or Theme.colors.textMuted
	end

	return {
		root = root,
		update = update,
		rows = rows,
		orderButtons = orderButtons,
		dispatchButton = dispatchButton,
		recallButton = recallButton,
		engagementHint = engagementHint,
	}
end

return IncidentPanel
