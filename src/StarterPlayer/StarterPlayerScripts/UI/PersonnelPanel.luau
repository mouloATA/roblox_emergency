--!strict
--[[
	PersonnelPanel — effectifs, disponibilité et affectation aux engins.

	L'affectation se fait vers le véhicule sélectionné (carte ou panneau
	Véhicules). Le serveur revérifie la qualification, la fatigue et la place
	disponible ; l'interface ne fait qu'empêcher les clics manifestement inutiles.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

local UI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ERSClient"):WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))

local PersonnelPanel = {}

function PersonnelPanel.create(parent: any, context: any): any
	local controller = context.controller

	local root = Widgets.frame(parent, "PanneauPersonnel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	Widgets.padding(root, 10, 2)

	local title = Widgets.label(root, "Titre", "PERSONNEL", {
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

	-- Deux colonnes : effectifs à gauche, fiche du membre à droite. Le détail
	-- défile dans sa colonne pour ne jamais recouvrir la barre inférieure.
	local listColumn = Widgets.frame(root, "ColonneListe", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(0.5, -6, 1, -46),
	})
	local list = Widgets.scroller(listColumn, "Liste", {
		Size = UDim2.fromScale(1, 1),
	})

	local detailColumn = Widgets.frame(root, "ColonneDetail", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 6, 0, 46),
		Size = UDim2.new(0.5, -6, 1, -46),
	})
	local detail = Widgets.scroller(detailColumn, "Detail", {
		Size = UDim2.fromScale(1, 1),
	})

	local detailTitle = Widgets.label(detail, "DetailTitre", "Sélectionnez un membre", {
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = Theme.text.subtitle,
		Font = Theme.fonts.bold,
	})
	local detailLine = Widgets.label(detail, "DetailLigne", "", {
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.text.small,
		TextColor3 = Theme.colors.textDim,
	})
	local fatigueBar = Widgets.bar(detail, "Fatigue", { Size = UDim2.new(1, 0, 0, 6) })
	local fatigueLabel = Widgets.label(detail, "FatigueTexte", "", {
		Size = UDim2.new(1, 0, 0, 16),
		TextSize = Theme.text.tiny,
		TextColor3 = Theme.colors.textMuted,
	})
	local qualificationLabel = Widgets.label(detail, "Qualifications", "", {
		Size = UDim2.new(1, 0, 0, 32),
		TextSize = Theme.text.tiny,
		TextWrapped = true,
		TextColor3 = Theme.colors.textDim,
	})

	local actions = Widgets.horizontal(detail, "Actions", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
	})
	local assignButton = Widgets.button(actions, "Action_assign_personnel", "Affecter", function()
		local person = controller:selectedPerson()
		local vehicle = controller:selectedVehicle()
		if person and vehicle then
			controller:command("assign_personnel", { personId = person.id, vehicleId = vehicle.id })
		end
	end, { Size = UDim2.fromOffset(110, 30), TextSize = Theme.text.tiny })
	local unassignButton = Widgets.button(actions, "Action_unassign_personnel", "Retirer", function()
		local person = controller:selectedPerson()
		if person then
			controller:command("unassign_personnel", { personId = person.id })
		end
	end, { Size = UDim2.fromOffset(90, 30), TextSize = Theme.text.tiny })

	local rows = Widgets.list(list, function(person)
		return person.id
	end, function(person)
		local row = Widgets.row(list, "PersonnelLigne_" .. person.id, Theme.sizes.row, function()
			controller:select("person", person.id)
		end)
		local name = Widgets.label(row, "Nom", person.name, {
			Position = UDim2.fromOffset(10, 6),
			Size = UDim2.new(1, -100, 0, 18),
			TextSize = Theme.text.small,
			Font = Theme.fonts.bold,
		})
		local grade = Widgets.label(row, "Grade", "", {
			Position = UDim2.fromOffset(10, 25),
			Size = UDim2.new(1, -100, 0, 16),
			TextSize = 10,
			TextColor3 = Theme.colors.textMuted,
		})
		local status = Widgets.tag(row, "", Theme.colors.success)
		status.Position = UDim2.new(1, -84, 0, 6)
		local assignment = Widgets.label(row, "Affectation", "", {
			Position = UDim2.new(1, -84, 0, 28),
			Size = UDim2.new(0, 76, 0, 14),
			TextSize = 10,
			TextColor3 = Theme.colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		return {
			instance = row,
			name = name,
			grade = grade,
			status = status,
			assignment = assignment,
		}
	end, function(entry, person)
		entry.name.Text = person.name
		entry.grade.Text = string.format("%s · %s", person.grade, Theme.serviceLabel(person.service))
		local available = person.vehicleId == nil and person.fatigue < 85
		entry.status.Text = person.vehicleId and "Affecté" or (available and "Disponible" or "Repos")
		entry.status.BackgroundColor3 = person.vehicleId and Theme.colors.info
			or (available and Theme.colors.success or Theme.colors.textMuted)
		entry.status.Size = UDim2.fromOffset(math.max(46, #entry.status.Text * 8 + 12), 18)
		entry.assignment.Text = person.vehicleId and string.format("Engin #%d", person.vehicleId) or "—"
		Widgets.setSelected(entry.instance, controller.state.personId == person.id)
	end)

	local function update(snapshot: any, state: any)
		local personnel = snapshot.personnel or {}
		rows.update(personnel)
		local available = 0
		for _, person in ipairs(personnel) do
			if person.vehicleId == nil then
				available += 1
			end
		end
		subtitle.Text = string.format("%d membre(s) · %d sans affectation", #personnel, available)

		local selected = nil
		for _, person in ipairs(personnel) do
			if person.id == state.personId then
				selected = person
			end
		end

		local vehicle = controller:selectedVehicle()
		if not selected then
			detailTitle.Text = "Sélectionnez un membre"
			detailLine.Text = "Affectation vers le véhicule sélectionné."
			fatigueBar.set(0)
			fatigueLabel.Text = ""
			qualificationLabel.Text = ""
			Widgets.setEnabled(assignButton, false)
			Widgets.setEnabled(unassignButton, false)
			return
		end

		detailTitle.Text = selected.name
		detailLine.Text = string.format(
			"%s · %s · santé %s",
			selected.grade,
			Theme.serviceLabel(selected.service),
			Theme.percent(selected.health)
		)
		fatigueBar.set(selected.fatigue / 100)
		fatigueBar.setColor(selected.fatigue >= 85 and Theme.colors.danger
			or (selected.fatigue >= 60 and Theme.colors.warning or Theme.colors.success))
		fatigueLabel.Text = "Fatigue " .. Theme.percent(selected.fatigue)
		qualificationLabel.Text = "Qualifications : "
			.. (#selected.qualifications > 0 and Widgets.join(selected.qualifications, ", ") or "aucune")

		local canAssign = selected.vehicleId == nil and vehicle ~= nil
			and vehicle.status == Constants.VEHICLE_STATUS.AVAILABLE
			and controller:can("assign_personnel")
			and controller:canService(vehicle.service)
		Widgets.setEnabled(assignButton, canAssign)
		assignButton.Text = vehicle and string.format("Affecter à %s", vehicle.callsign) or "Choisir un engin"

		Widgets.setEnabled(
			unassignButton,
			selected.vehicleId ~= nil and controller:can("assign_personnel")
		)
	end

	return { root = root, update = update, rows = rows }
end

return PersonnelPanel
