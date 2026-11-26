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

local Recruitment = require(Shared:WaitForChild("Catalogs"):WaitForChild("Recruitment"))

local Nav = require(UI:WaitForChild("ManagementNav"))
local Qualifications = require(Shared:WaitForChild("Catalogs"):WaitForChild("Qualifications"))
local Config = require(Shared:WaitForChild("Config"))
local Crew = require(Shared:WaitForChild("Utilities"):WaitForChild("Crew"))
local Vehicles = require(Shared:WaitForChild("Catalogs"):WaitForChild("Vehicles"))
local crewRules = { config = Config, catalogs = { vehicles = Vehicles } }
local PersonnelPanel = {}

-- Affiche la garde et les offres de recrutement pour le service choisi.
function PersonnelPanel.create(parent: any, context: any): any
	local controller = context.controller

	local root = Widgets.frame(parent, "PanneauPersonnel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	Widgets.padding(root, 10, 2)

	local rosterBody = Widgets.frame(root, "Garde", {
		BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 90), Size = UDim2.new(1, 0, 1, -90),
	})
	local recruits = Widgets.scroller(root, "Offres", {
		Position = UDim2.fromOffset(0, 90), Size = UDim2.new(1, 0, 1, -90),
	})
	local pages = Nav.strip(root, "VuePersonnel", { { "roster", "Effectif", 88 }, { "recruit", "Recruter", 94 } },
		function() controller:render() end, { Size = UDim2.new(1, -135, 0, 38) })
	local subtitle = Widgets.label(root, "SousTitre", "", {
		Position = UDim2.new(1, -132, 0, 0), Size = UDim2.fromOffset(132, 36), TextSize = Theme.text.small,
		TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.colors.textDim, TextWrapped = true,
	})
	local list
	local detail
	local services = Nav.strip(root, "ServicePersonnel", Nav.services, function()
		list.CanvasPosition = Vector2.new(0, 0)
		detail.CanvasPosition = Vector2.new(0, 0)
		recruits.CanvasPosition = Vector2.new(0, 0)
		controller:render()
	end, { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 36) })
	local priceSort = Nav.priceSort(root, Recruitment.profiles, services, recruits, function() controller:render() end)

	-- Deux colonnes : effectifs à gauche, fiche du membre à droite. Le détail
	-- défile dans sa colonne pour ne jamais recouvrir la barre inférieure.
	local listColumn = Widgets.frame(rosterBody, "ColonneListe", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(0.45, -6, 1, 0),
	})
	list = Widgets.scroller(listColumn, "Liste", {
		Size = UDim2.fromScale(1, 1),
	})

	local detailColumn = Widgets.frame(rosterBody, "ColonneDetail", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.45, 6, 0, 0),
		Size = UDim2.new(0.55, -6, 1, 0),
	})
	detail = Widgets.scroller(detailColumn, "Detail", {
		Size = UDim2.fromScale(1, 1),
	})

	local choosingFor = nil
	local preferredId = nil
	local chooser = Widgets.scroller(detailColumn, "ChoixAffectation", { Size = UDim2.fromScale(1, 1), Visible = false })
	local back = Widgets.button(chooser, "RetourAgent", "Retour à la fiche", function()
		choosingFor = nil
		controller:render()
	end, { Size = UDim2.fromOffset(136, 32), LayoutOrder = 0 })
	local destinations = Widgets.list(chooser, function(vehicle) return vehicle.id end, function(vehicle)
		local button = Widgets.button(chooser, "Affecter_" .. vehicle.id, "", function()
			local personId = choosingFor
			choosingFor = nil
			if personId then
				controller:command("assign_personnel", { personId = personId, vehicleId = vehicle.id })
				controller:render()
			end
		end, { Size = UDim2.new(1, -6, 0, 42), TextWrapped = true })
		return { instance = button }
	end, function(entry, vehicle)
		entry.instance.Text = vehicle.callsign .. "  ·  " .. vehicle.name
	end)
	local function chooseDestination()
		choosingFor = controller.state.personId
		chooser.CanvasPosition = Vector2.new(0, 0)
		controller:render()
	end

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
		if person and preferredId then
			controller:command("assign_personnel", { personId = person.id, vehicleId = preferredId })
		else
			chooseDestination()
		end
	end, { Size = UDim2.new(0.56, -6, 0, 30), TextSize = Theme.text.tiny })
	local other = Widgets.button(actions, "ChangerDestination", "Autre engin", chooseDestination, {
		Size = UDim2.new(0.44, -6, 0, 30), TextSize = Theme.text.tiny,
	})
	local unassignButton = Widgets.button(actions, "Action_unassign_personnel", "Retirer", function()
		local person = controller:selectedPerson()
		if person then
			controller:command("unassign_personnel", { personId = person.id })
		end
	end, { Size = UDim2.fromOffset(90, 30), TextSize = Theme.text.tiny })

	local trainButton = Widgets.button(detail, "Action_train_personnel", "Former", function()
		local person = controller:selectedPerson()
		if person then controller:command("train_personnel", { personId = person.id }) end
	end, { Size = UDim2.new(1, 0, 0, 30), TextSize = Theme.text.small })
	local transferButton = Widgets.button(detail, "Action_transfer_personnel", "Transférer", function()
		local person = controller:selectedPerson()
		if person then controller:command("transfer_personnel", { personId = person.id }) end
	end, { Size = UDim2.new(1, 0, 0, 30), TextSize = Theme.text.small })
	local emptyRoster = Widgets.label(list, "EffectifVide", "Aucun agent dans ce service.", {
		Size = UDim2.new(1, -8, 0, 40), TextColor3 = Theme.colors.textMuted, TextSize = Theme.text.small,
	})
	local latest = context.snapshot or {}
	local recruitRows = Widgets.list(recruits, function(profile) return profile.id end, function(profile)
		local labels = {}
		for id in pairs(profile.qualifications) do table.insert(labels, Qualifications.label(id)) end
		table.sort(labels)
		return Nav.offer(recruits, "Offre_" .. profile.id, "Action_recruit_" .. profile.id, profile.grade,
			table.concat(labels, "  ·  "), profile.service, "Recruter", function()
				controller:command("recruit_personnel", { profileId = profile.id })
			end)
	end, function(entry, profile)
		local turn = latest.purchase or {}
		local price = profile.cost + (turn.surcharge or 0)
		entry.cost.Text = Theme.money(price)
		local reason = nil
		if not controller:can("buy_vehicle") then reason = "Poste restreint"
		elseif turn.owner and turn.owner ~= controller.player.UserId then reason = "Hors tour"
		elseif #(latest.personnel or {}) >= Recruitment.maxPersonnel then reason = "Effectif complet"
		elseif (latest.budget or 0) < price then reason = "Solde insuffisant" end
		entry.buy.Text = reason or "Recruter"
		Widgets.setEnabled(entry.buy, reason == nil)
	end)

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
		status.TextColor3 = Theme.colors.background
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
		local available = person.vehicleId == nil and person.fatigue < Config.REST_FATIGUE and person.health > Config.MIN_HEALTH
		entry.status.Text = person.vehicleId and "Affecté" or (available and "Disponible" or "Repos")
		entry.status.BackgroundColor3 = person.vehicleId and Theme.colors.info
			or (available and Theme.colors.success or Theme.colors.textMuted)
		entry.status.Size = UDim2.fromOffset(math.max(46, #entry.status.Text * 8 + 12), 18)
		entry.assignment.Text = person.vehicleId and string.format("Engin #%d", person.vehicleId) or "—"
		Widgets.setSelected(entry.instance, controller.state.personId == person.id)
	end)

	local function update(snapshot: any, state: any)
		latest = snapshot
		local personnel = snapshot.personnel or {}
		local recruiting = pages.value == "recruit"
		priceSort.setVisible(recruiting)
		rosterBody.Visible = not recruiting
		recruits.Visible = recruiting
		local turn = snapshot.purchase or {}
		if recruiting then
			choosingFor = nil
			subtitle.Text = Theme.money(snapshot.budget or 0)
			if (turn.count or 0) > 1 then subtitle.Text ..= " · Tour de " .. turn.name end
			recruitRows.update(priceSort.offers())
			return
		end
		local filtered = Nav.byService(personnel, services.value)
		rows.update(filtered)
		emptyRoster.Visible = #filtered == 0
		local available = 0
		local selected = nil
		for _, person in ipairs(filtered) do
			if person.vehicleId == nil and person.fatigue < Config.REST_FATIGUE and person.health > Config.MIN_HEALTH then available += 1 end
			if person.id == state.personId then selected = person end
		end
		subtitle.Text = string.format("%d en effectif · %d disponibles", #filtered, available)
		local canBuy = controller:can("buy_vehicle") and (turn.owner == nil or turn.owner == controller.player.UserId)
		actions.Visible = selected ~= nil
		fatigueBar.root.Visible = selected ~= nil
		fatigueLabel.Visible = selected ~= nil
		qualificationLabel.Visible = selected ~= nil
		trainButton.Visible = selected ~= nil
		transferButton.Visible = selected ~= nil
		if not selected or choosingFor ~= selected.id or selected.vehicleId then choosingFor = nil end
		chooser.Visible = choosingFor ~= nil
		detail.Visible = choosingFor == nil
		if not selected then
			detailTitle.Text = "Sélectionnez un membre"
			detailLine.Text = #filtered == 0 and "Ouvrez Recruter pour renforcer ce service." or "Choisissez un agent dans l’effectif."
			fatigueBar.set(0)
			fatigueLabel.Text = ""
			qualificationLabel.Text = ""
			Widgets.setEnabled(assignButton, false)
			Widgets.setEnabled(unassignButton, false)
			return
		end

		local level = selected.level or 0
		local fee = Recruitment.trainingCost(level)
		local free = canBuy and selected.vehicleId == nil
		Widgets.setEnabled(trainButton, free and level < Recruitment.maxLevel and (snapshot.budget or 0) >= fee)
		Widgets.setEnabled(transferButton, free)
		trainButton.Text = level == Recruitment.maxLevel and "Formation maximale"
			or string.format("Former au niveau %d · %s", level + 1, Theme.money(fee))
		transferButton.Text = "Transférer · +" .. Theme.money(selected.transferValue or 600)
		detailTitle.Text = string.format("%s · niv. %d", selected.name, level)
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

		local candidates = {}
		preferredId = nil
		local assignedVehicle = nil
		local agent = table.clone(selected)
		agent.qualifications = selected.qualificationIds or {}
		for _, vehicle in ipairs(snapshot.vehicles or {}) do
			if vehicle.id == selected.vehicleId then assignedVehicle = vehicle end
			if controller:can("assign_personnel") and controller:canService(vehicle.service)
				and Crew.canAssign(crewRules, agent, vehicle).ok then
				table.insert(candidates, vehicle)
				if vehicle.id == state.vehicleId then
					preferredId = vehicle.id
					assignButton.Text = "Affecter à " .. vehicle.callsign
				end
			end
		end
		if not preferredId then assignButton.Text = #candidates > 0 and "Choisir un engin" or "Aucun engin disponible" end
		assignButton.Visible = selected.vehicleId == nil
		other.Visible = preferredId ~= nil and #candidates > 1
		unassignButton.Visible = selected.vehicleId ~= nil
		Widgets.setEnabled(assignButton, #candidates > 0)
		Widgets.setEnabled(unassignButton, assignedVehicle ~= nil and assignedVehicle.status == Constants.VEHICLE_STATUS.AVAILABLE
			and controller:can("assign_personnel") and controller:canService(assignedVehicle.service))
		if choosingFor then
			destinations.update(candidates)
			back.Text = #candidates == 0 and "Aucun engin · Retour" or "Retour à la fiche"
		end
	end

	local function resize(width: number)
		local narrow = width < 620
		listColumn.Size = narrow and UDim2.new(1, 0, 0.42, -4) or UDim2.new(0.45, -6, 1, 0)
		detailColumn.Position = narrow and UDim2.new(0, 0, 0.42, 4) or UDim2.new(0.45, 6, 0, 0)
		detailColumn.Size = narrow and UDim2.new(1, 0, 0.58, -4) or UDim2.new(0.55, -6, 1, 0)
	end
	return { root = root, update = update, resize = resize, rows = rows }
end

return PersonnelPanel
