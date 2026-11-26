--!strict
--[[
	CommandPanel — groupes, secteurs et engagement groupé.

	Un groupe rassemble des engins ; un secteur est une zone circulaire de la
	carte. Affecter un groupe à un secteur qui couvre l'intervention apporte un
	bonus de coordination réel, appliqué côté serveur.

	Le panneau crée, garnit, engage et dissout les groupes, puis crée et affecte
	les secteurs. Toutes les intentions passent par `NetworkService` : un poste
	sans droit de commandement ne peut rien modifier, même en cliquant.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))

local UI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ERSClient"):WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))

local CommandPanel = {}

local SERVICES = { false, "fire", "medical", "police", "technical", "command", "logistics" }
local SECTOR_RADIUS = 20

local function trim(text: string): string
	return (string.gsub(text or "", "^%s*(.-)%s*$", "%1"))
end

local function vehicleById(snapshot: any, id: any): any
	for _, vehicle in ipairs(snapshot.vehicles or {}) do
		if vehicle.id == id then
			return vehicle
		end
	end
	return nil
end

function CommandPanel.create(parent: any, context: any): any
	local controller = context.controller
	local serviceIndex = 1

	local root = Widgets.frame(parent, "PanneauCommandement", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	Widgets.padding(root, 10, 2)
	local latestSnapshot = context.snapshot or { vehicles = {}, incidents = {}, groups = {}, sectors = {} }

	local title = Widgets.label(root, "Titre", "COMMANDEMENT", {
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

	-- Le corps défile : groupes, secteur et commandement tiennent sur une
	-- hauteur plus grande que le tiroir. Rien ne doit passer sous la barre.
	local body = Widgets.scroller(root, "Corps", {
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 1, -46),
	})

	-- ── Groupes ───────────────────────────────────────────────
	Widgets.section(body, "Groupes tactiques")

	local createRow = Widgets.horizontal(body, "CreationGroupe", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
	})
	local nameBox = Widgets.textbox(createRow, "GroupeNom", "Nom du groupe", {
		Size = UDim2.new(1, -188, 0, 30),
	})
	local serviceButton = Widgets.button(createRow, "Action_service_groupe", "Tous services", function()
		serviceIndex = serviceIndex % #SERVICES + 1
		local service = SERVICES[serviceIndex]
		serviceButton.Text = service and Theme.serviceLabel(service) or "Tous services"
	end, { Size = UDim2.fromOffset(104, 30), TextSize = 10 })
	local createGroupButton = Widgets.button(createRow, "Action_create_group", "Créer", function()
		local name = trim(nameBox.Text)
		if #name < 2 then
			controller:toast("Nom de groupe trop court (2 caractères minimum).", false)
			return
		end
		controller:command("create_group", {
			name = name,
			service = SERVICES[serviceIndex] or nil,
		})
		nameBox.Text = ""
	end, { Size = UDim2.fromOffset(72, 30), TextSize = Theme.text.tiny })

	local groupList = Widgets.scroller(body, "Groupes", {
		Size = UDim2.new(1, 0, 0, 150),
	})

	local groupRows = Widgets.list(groupList, function(group)
		return group.id
	end, function(group)
		local row = Widgets.row(groupList, "GroupeLigne_" .. group.id, 62, function()
			controller:select("group", group.id)
		end)
		local name = Widgets.label(row, "Nom", group.name, {
			Position = UDim2.fromOffset(10, 5),
			Size = UDim2.new(1, -180, 0, 18),
			TextSize = Theme.text.small,
			Font = Theme.fonts.bold,
		})
		local meta = Widgets.label(row, "Meta", "", {
			Position = UDim2.fromOffset(10, 23),
			Size = UDim2.new(1, -180, 0, 14),
			TextSize = 10,
			TextColor3 = Theme.colors.textMuted,
		})
		local engage = Widgets.button(row, "Action_dispatch_group_" .. group.id, "Engager", function()
			local incident = controller:selectedIncident()
			if incident then
				controller:command("dispatch_group", { groupId = group.id, incidentId = incident.id })
			end
		end, { Size = UDim2.fromOffset(72, 24), Position = UDim2.new(1, -166, 0, 6), TextSize = 10 })
		local dissolve = Widgets.button(row, "Action_dissolve_group_" .. group.id, "Dissoudre", function()
			controller:command("dissolve_group", { groupId = group.id })
			if controller.state.groupId == group.id then
				controller.state.groupId = nil
			end
		end, { Size = UDim2.fromOffset(78, 24), Position = UDim2.new(1, -90, 0, 6), TextSize = 10 })
		local members = Widgets.label(row, "Membres", "", {
			Position = UDim2.fromOffset(10, 42),
			Size = UDim2.new(1, -22, 0, 14),
			TextSize = 10,
			TextColor3 = Theme.colors.textDim,
		})
		return {
			instance = row,
			name = name,
			meta = meta,
			engage = engage,
			dissolve = dissolve,
			members = members,
		}
	end, function(entry, group)
		local sectorName = group.sectorId and ("secteur #" .. group.sectorId) or "hors secteur"
		entry.name.Text = group.name
		entry.meta.Text = string.format(
			"%s · %d engin(s) · %s",
			group.service and Theme.serviceLabel(group.service) or "inter-services",
			#group.vehicles,
			sectorName
		)
		local callsigns = {}
		for _, vehicleId in ipairs(group.vehicles) do
			local vehicle = vehicleById(latestSnapshot, vehicleId)
			table.insert(callsigns, vehicle and vehicle.callsign or ("Engin #" .. vehicleId))
		end
		entry.members.Text = #callsigns > 0 and Widgets.join(callsigns, ", ") or "Groupe vide"
		Widgets.setSelected(entry.instance, controller.state.groupId == group.id)
		Widgets.setEnabled(entry.dissolve, controller:can("command"))
		Widgets.setEnabled(entry.engage, controller:can("command") and #group.vehicles > 0
			and controller.state.incidentId ~= nil)
	end)

	local groupActions = Widgets.horizontal(body, "ActionsGroupe", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
	})
	local addUnitButton = Widgets.button(groupActions, "Action_add_to_group", "Ajouter l'engin", function()
		local vehicle = controller:selectedVehicle()
		local group = controller:selectedGroup()
		if vehicle and group then
			controller:command("add_to_group", { groupId = group.id, vehicleId = vehicle.id })
		end
	end, { Size = UDim2.fromOffset(118, 30), TextSize = 10 })
	local rememberIncident = Widgets.label(groupActions, "RappelUrgence", "", {
		Size = UDim2.new(1, -124, 1, 0),
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.colors.textMuted,
	})

	local memberList = Widgets.scroller(body, "MembresGroupe", {
		Size = UDim2.new(1, 0, 0, 86),
	})
	local memberRows = Widgets.list(memberList, function(member)
		return member.id
	end, function(member)
		local row = Widgets.frame(memberList, "Membre_" .. member.id, {
			BackgroundColor3 = Theme.colors.surfaceAlt,
			BackgroundTransparency = 0.4,
			Size = UDim2.new(1, 0, 0, 26),
		})
		Widgets.corner(row, Theme.radius.small)
		local name = Widgets.label(row, "Nom", member.callsign, {
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.new(1, -88, 1, 0),
			TextSize = 10,
		})
		local remove = Widgets.button(row, "Action_remove_from_group_" .. member.id, "Retirer", function()
			local group = controller:selectedGroup()
			if group then
				controller:command("remove_from_group", { groupId = group.id, vehicleId = member.id })
			end
		end, { Size = UDim2.fromOffset(58, 20), Position = UDim2.new(1, -64, 0, 3), TextSize = 9 })
		return { instance = row, name = name, remove = remove }
	end, function(entry, member)
		entry.name.Text = member.callsign
		Widgets.setEnabled(entry.remove, controller:can("command"))
	end)

	-- ── Secteurs ──────────────────────────────────────────────
	Widgets.section(body, "Secteurs")

	local sectorCreateRow = Widgets.horizontal(body, "CreationSecteur", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
	})
	local sectorBox = Widgets.textbox(sectorCreateRow, "SecteurNom", "Nom du secteur", {
		Size = UDim2.new(1, -96, 0, 30),
	})
	local sectorButton = Widgets.button(sectorCreateRow, "Action_create_sector", "Créer ici", function()
		local name = trim(sectorBox.Text)
		if #name < 2 then
			controller:toast("Nom de secteur trop court (2 caractères minimum).", false)
			return
		end
		local incident = controller:selectedIncident()
		controller:command("create_sector", {
			name = name,
			x = incident and incident.x or Config.HQ_X,
			z = incident and incident.z or Config.HQ_Z,
			radius = SECTOR_RADIUS,
		})
		sectorBox.Text = ""
	end, { Size = UDim2.fromOffset(88, 30), TextSize = 10 })

	local sectorList = Widgets.scroller(body, "Secteurs", {
		Size = UDim2.new(1, 0, 0, 112),
	})
	local sectorRows = Widgets.list(sectorList, function(sector)
		return sector.id
	end, function(sector)
		local row = Widgets.frame(sectorList, "SecteurLigne_" .. sector.id, {
			BackgroundColor3 = Theme.colors.surfaceAlt,
			BackgroundTransparency = 0.4,
			Size = UDim2.new(1, 0, 0, 46),
		})
		Widgets.corner(row, Theme.radius.small)
		local name = Widgets.label(row, "Nom", sector.name, {
			Position = UDim2.fromOffset(8, 4),
			Size = UDim2.new(1, -112, 0, 16),
			TextSize = Theme.text.tiny,
			Font = Theme.fonts.bold,
		})
		local meta = Widgets.label(row, "Meta", "", {
			Position = UDim2.fromOffset(8, 21),
			Size = UDim2.new(1, -112, 0, 14),
			TextSize = 9,
			TextColor3 = Theme.colors.textMuted,
		})
		local assign = Widgets.button(row, "Action_assign_group_sector_" .. sector.id, "Affecter", function()
			local group = controller:selectedGroup()
			if group then
				controller:command("assign_group_sector", { sectorId = sector.id, groupId = group.id })
			end
		end, { Size = UDim2.fromOffset(88, 24), Position = UDim2.new(1, -96, 0, 10), TextSize = 9 })
		return { instance = row, name = name, meta = meta, assign = assign }
	end, function(entry, sector)
		entry.name.Text = sector.name
		entry.meta.Text = string.format(
			"Centre %d/%d · rayon %d · %s",
			math.floor(sector.x + 0.5),
			math.floor(sector.z + 0.5),
			math.floor(sector.radius + 0.5),
			sector.groupId and ("groupe #" .. sector.groupId) or "libre"
		)
		Widgets.setEnabled(entry.assign, controller:can("command") and controller.state.groupId ~= nil)
	end)

	local hint = Widgets.label(body, "Aide", "Sélectionnez une urgence sur la carte pour y engager un groupe. "
		.. "Le secteur créé est centré sur cette urgence, sinon sur le poste.", {
		Size = UDim2.new(1, 0, 0, 32),
		TextSize = 9,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.colors.textMuted,
	})

	local function update(snapshot: any, _state: any)
		latestSnapshot = snapshot
		local groups = snapshot.groups or {}
		groupRows.update(groups)
		sectorRows.update(snapshot.sectors or {})

		local group = controller:selectedGroup()
		local members = {}
		if group then
			for _, vehicleId in ipairs(group.vehicles) do
				local vehicle = vehicleById(snapshot, vehicleId)
				table.insert(members, {
					id = vehicleId,
					callsign = vehicle and vehicle.callsign or ("Engin #" .. vehicleId),
				})
			end
		end
		memberRows.update(members)

		local incident = controller:selectedIncident()
		rememberIncident.Text = incident and ("Urgence : " .. incident.id) or "Aucune urgence choisie"
		Widgets.setEnabled(createGroupButton, controller:can("command"))
		Widgets.setEnabled(sectorButton, controller:can("command"))
		Widgets.setEnabled(
			addUnitButton,
			controller:can("command") and group ~= nil and controller:selectedVehicle() ~= nil
		)
		addUnitButton.Text = group and ("Ajouter à " .. group.name) or "Choisir un groupe"

		subtitle.Text = string.format(
			"%d groupe(s) · %d secteur(s) · urgence %s",
			#groups,
			#(snapshot.sectors or {}),
			incident and incident.id or "non choisie"
		)
	end

	return {
		root = root,
		update = update,
		groupRows = groupRows,
		memberRows = memberRows,
		sectorRows = sectorRows,
		createGroupButton = createGroupButton,
		sectorButton = sectorButton,
		nameBox = nameBox,
		sectorBox = sectorBox,
	}
end

return CommandPanel
