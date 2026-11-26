--!strict
--[[
	VehiclePanel — flotte, équipages, matériel embarqué et engagements.

	Chaque bouton correspond à une intention réellement traitée par le serveur
	(`dispatch`, `recall`, `auto_crew`, `repair_vehicle`, `uninstall_equipment`).
	Les boutons sont désactivés quand l'action est impossible côté client, mais
	la décision finale reste serveur.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))

local UI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ERSClient"):WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))
local EngagementHints = require(UI:WaitForChild("EngagementHints"))

local VehiclePanel = {}

function VehiclePanel.create(parent: any, context: any): any
	local controller = context.controller

	local root = Widgets.frame(parent, "PanneauVehicules", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	Widgets.padding(root, 10, 2)

	Widgets.button(root, "OuvrirCatalogue", "Acheter un engin", function()
		context.openShop(controller.state.category)
	end, { Position = UDim2.new(1, -148, 0, 0), Size = UDim2.fromOffset(148, 34) })
	local title = Widgets.label(root, "Titre", "Flotte en service", {
		Size = UDim2.new(1, -156, 0, 24),
		TextSize = Theme.text.subtitle,
		Font = Theme.fonts.bold,
	})
	local subtitle = Widgets.label(root, "SousTitre", "", {
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, -156, 0, 18),
		TextSize = Theme.text.tiny,
		TextColor3 = Theme.colors.textMuted,
	})

	-- Deux colonnes : flotte à gauche, fiche de l'engin à droite. Le détail
	-- défile dans sa colonne pour ne jamais recouvrir la barre inférieure.
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
	-- Le détail occupe la colonne de droite, sous l'en-tête du panneau.
	local detail = Widgets.scroller(detailColumn, "Detail", {
		Size = UDim2.fromScale(1, 1),
	})

	local detailTitle = Widgets.label(detail, "DetailTitre", "Sélectionnez un véhicule", {
		Size = UDim2.new(1, 0, 0, 42),
		TextSize = Theme.text.subtitle,
		Font = Theme.fonts.bold,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local statusLine = Widgets.label(detail, "DetailStatut", "", {
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.text.small,
		TextColor3 = Theme.colors.textDim,
	})
	local conditionBar = Widgets.bar(detail, "Etat", { Size = UDim2.new(1, 0, 0, 6) })
	local conditionLabel = Widgets.label(detail, "EtatTexte", "", {
		Size = UDim2.new(1, 0, 0, 16),
		TextSize = Theme.text.tiny,
		TextColor3 = Theme.colors.textMuted,
	})
	local crewLabel = Widgets.label(detail, "Equipage", "", {
		Size = UDim2.new(1, 0, 0, 32),
		TextSize = Theme.text.small,
		TextWrapped = true,
		TextColor3 = Theme.colors.textDim,
	})

	local actions = Widgets.horizontal(detail, "Actions", {
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundTransparency = 1,
	})

	local dispatchButton
	local recallButton
	local crewButton
	local repairButton

	dispatchButton = Widgets.button(actions, "Action_dispatch", "Engager", function()
		local vehicle = controller:selectedVehicle()
		if vehicle and controller.state.incidentId then
			controller:command("dispatch", { vehicleId = vehicle.id, incidentId = controller.state.incidentId })
		else
			controller:toast("Sélectionnez d'abord une intervention, puis engagez l'engin.", false)
		end
	end, { Size = UDim2.fromOffset(96, 34), TextSize = Theme.text.tiny })

	recallButton = Widgets.button(actions, "Action_recall", "Rappeler", function()
		local vehicle = controller:selectedVehicle()
		if vehicle then
			controller:command("recall", { vehicleId = vehicle.id })
		end
	end, { Size = UDim2.fromOffset(92, 34), TextSize = Theme.text.tiny })

	crewButton = Widgets.button(actions, "Action_auto_crew", "Équipage auto", function()
		local vehicle = controller:selectedVehicle()
		if vehicle then
			controller:command("auto_crew", { vehicleId = vehicle.id })
		end
	end, { Size = UDim2.fromOffset(120, 34), TextSize = Theme.text.tiny })

	repairButton = Widgets.button(actions, "Action_repair", "Réparer", function()
		local vehicle = controller:selectedVehicle()
		if vehicle then
			controller:command("repair_vehicle", { vehicleId = vehicle.id })
		end
	end, { Size = UDim2.fromOffset(96, 34), TextSize = Theme.text.tiny })

	-- Aide permanente : dit pourquoi « Engager » est grisé, ou signale un
	-- engin dont les capacités ne couvrent pas les moyens requis.
	local engagementHint = Widgets.label(detail, "AideEngagement", "", {
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = Theme.text.tiny,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.colors.warning,
	})

	local equipmentTitle = Widgets.section(detail, "Matériel embarqué")
	local equipmentList = Widgets.scroller(detail, "Materiel", {
		Size = UDim2.new(1, 0, 0, 100),
	})

	local equipmentRows = Widgets.list(equipmentList, function(entry)
		return entry.id
	end, function(entry)
		local row = Widgets.frame(equipmentList, "Materiel_" .. entry.id, {
			BackgroundColor3 = Theme.colors.surfaceAlt,
			BackgroundTransparency = 0.4,
			Size = UDim2.new(1, 0, 0, 28),
		})
		Widgets.corner(row, Theme.radius.small)
		local name = Widgets.label(row, "Nom", entry.name, {
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.new(1, -80, 1, 0),
			TextSize = Theme.text.tiny,
		})
		local quantity = Widgets.label(row, "Quantite", "×" .. entry.quantity, {
			Position = UDim2.new(1, -70, 0, 0),
			Size = UDim2.fromOffset(30, 28),
			TextSize = Theme.text.tiny,
			TextColor3 = Theme.colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		local remove = Widgets.button(row, "Action_retirer_" .. entry.id, "Retirer", function()
			local vehicle = controller:selectedVehicle()
			if vehicle then
				controller:command("uninstall_equipment", {
					vehicleId = vehicle.id,
					equipmentId = entry.id,
					quantity = 1,
				})
			end
		end, { Size = UDim2.fromOffset(56, 22), Position = UDim2.new(1, -60, 0, 3), TextSize = 10 })
		return { instance = row, name = name, quantity = quantity, remove = remove }
	end, function(entryView, entry)
		entryView.name.Text = entry.name
		entryView.quantity.Text = "×" .. entry.quantity
		local vehicle = controller:selectedVehicle()
		Widgets.setEnabled(entryView.remove, vehicle ~= nil
			and vehicle.status == Constants.VEHICLE_STATUS.AVAILABLE
			and controller:can("equipment")
			and controller:canService(vehicle.service))
	end)

	local vehicleRows = Widgets.list(list, function(vehicle)
		return vehicle.id
	end, function(vehicle)
		local row = Widgets.row(list, "VehiculeLigne_" .. vehicle.id, Theme.sizes.row + 8, function()
			controller:select("vehicle", vehicle.id)
		end)

		local callsign = Widgets.label(row, "Indicatif", vehicle.callsign, {
			Position = UDim2.fromOffset(10, 6),
			Size = UDim2.new(0.45, 0, 0, 18),
			TextSize = Theme.text.small,
			Font = Theme.fonts.bold,
		})
		local typeName = Widgets.label(row, "Type", vehicle.name, {
			Position = UDim2.fromOffset(10, 24),
			Size = UDim2.new(0.55, 0, 0, 16),
			TextSize = 10,
			TextColor3 = Theme.colors.textMuted,
		})
		local status = Widgets.tag(row, "", Theme.colors.success)
		status.Position = UDim2.new(1, -84, 0, 6)
		local crew = Widgets.label(row, "EquipageResume", "", {
			Position = UDim2.new(1, -84, 0, 28),
			Size = UDim2.new(0, 76, 0, 14),
			TextSize = 10,
			TextColor3 = Theme.colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		local condition = Widgets.bar(row, "EtatResume", {
			Position = UDim2.fromOffset(10, 46),
			Size = UDim2.new(1, -100, 0, 4),
		})
		return {
			instance = row,
			callsign = callsign,
			typeName = typeName,
			status = status,
			crew = crew,
			condition = condition,
		}
	end, function(entry, vehicle)
		entry.callsign.Text = vehicle.callsign
		entry.typeName.Text = vehicle.name
		entry.status.Text = Theme.statusLabel(vehicle.status)
		entry.status.BackgroundColor3 = Theme.statusColor[vehicle.status] or Theme.colors.info
		entry.status.Size = UDim2.fromOffset(math.max(46, #entry.status.Text * 8 + 12), 18)
		entry.crew.Text = string.format("%d/%d", vehicle.crewCount, vehicle.crewRequired)
		entry.condition.set(vehicle.condition / 100)
		entry.condition.setColor(
			vehicle.condition >= 60 and Theme.colors.success
				or (vehicle.condition >= 30 and Theme.colors.warning or Theme.colors.danger)
		)
		Widgets.setSelected(entry.instance, controller.state.vehicleId == vehicle.id)
	end)

	local function update(snapshot: any, state: any)
		local vehicles = snapshot.vehicles or {}
		local category = state.category or "all"
		local visible = {}
		for _, vehicle in ipairs(vehicles) do
			if category == "all" or vehicle.service == category then
				table.insert(visible, vehicle)
			end
		end
		vehicleRows.update(visible)
		subtitle.Text = string.format(
			"%d/%d engin(s) · catégorie %s",
			#visible,
			#vehicles,
			category == "all" and "toutes" or Theme.serviceLabel(category)
		)

		local selected = nil
		for _, vehicle in ipairs(vehicles) do
			if vehicle.id == state.vehicleId then
				selected = vehicle
			end
		end

		local incidentSelected = state.incidentId ~= nil
		if not selected then
			detailTitle.Text = "Sélectionnez un véhicule"
			statusLine.Text = "Cliquez une ligne ou un marqueur de la carte."
			conditionBar.set(0)
			conditionLabel.Text = ""
			crewLabel.Text = ""
			equipmentRows.update({})
			engagementHint.Text = ""
			Widgets.setEnabled(dispatchButton, false)
			Widgets.setEnabled(recallButton, false)
			Widgets.setEnabled(crewButton, false)
			Widgets.setEnabled(repairButton, false)
			return
		end

		detailTitle.Text = selected.callsign .. " — " .. selected.name
		statusLine.Text = string.format(
			"%s · %s · %d/%d membres",
			Theme.statusLabel(selected.status),
			Theme.serviceLabel(selected.service),
			selected.crewCount,
			selected.crewRequired
		)
		conditionBar.set(selected.condition / 100)
		conditionBar.setColor(selected.condition >= 60 and Theme.colors.success
			or (selected.condition >= 30 and Theme.colors.warning or Theme.colors.danger))
		conditionLabel.Text = string.format(
			"État mécanique %s%s",
			Theme.percent(selected.condition),
			selected.repairRemaining and selected.repairRemaining > 0
				and string.format(" · atelier %s", Theme.seconds(selected.repairRemaining))
				or ""
		)
		crewLabel.Text = #selected.crew > 0
			and ("Équipage : " .. Widgets.join(selected.crew, ", "))
			or "Équipage : aucun membre affecté."

		local isAvailable = selected.status == Constants.VEHICLE_STATUS.AVAILABLE
		local isEngaged = selected.status == Constants.VEHICLE_STATUS.DISPATCHED
			or selected.status == Constants.VEHICLE_STATUS.ON_SCENE
		local inScope = controller:canService(selected.service)

		local incident = controller:selectedIncident()
		local closed = incident ~= nil
			and (incident.status == Constants.INCIDENT_STATUS.RESOLVED
				or incident.status == Constants.INCIDENT_STATUS.FAILED)

		Widgets.setEnabled(
			dispatchButton,
			isAvailable
				and incidentSelected
				and selected.crewCount >= selected.crewRequired
				and controller:can("dispatch")
				and inScope
		)
		dispatchButton.Text = incidentSelected and "Engager" or "Choisir urgence"

		local hint = EngagementHints.engageHint(selected, incident, controller:can("dispatch"), inScope, closed)
		engagementHint.Text = hint or ""
		engagementHint.TextColor3 = hint
				and (string.sub(hint, 1, 1) == "⚠" and Theme.colors.warning or Theme.colors.textMuted)
			or Theme.colors.textMuted

		Widgets.setEnabled(recallButton, isEngaged and controller:can("recall") and inScope)
		Widgets.setEnabled(
			crewButton,
			isAvailable and selected.crewCount < selected.crewRequired and controller:can("assign_personnel") and inScope
		)
		Widgets.setEnabled(
			repairButton,
			isAvailable and selected.condition < 100 and controller:can("repair") and inScope
		)
		repairButton.Text = string.format(
			"Réparer %s",
			Theme.money(math.ceil((100 - selected.condition) * Config.REPAIR_COST_PER_POINT))
		)

		equipmentRows.update(selected.equipment or {})
	end

	return {
		root = root,
		update = update,
		rows = vehicleRows,
		dispatchButton = dispatchButton,
		engagementHint = engagementHint,
	}
end

return VehiclePanel
