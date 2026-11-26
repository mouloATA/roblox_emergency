--!strict
--[[
	MiniMap — mini-carte tactique encadrée, en haut à droite.

	Elle est dessinée à partir du plan partagé `Shared/City` : le client
	reconstruit exactement la même ville que le serveur, sans recevoir de
	géométrie par le réseau. Les seules données dynamiques sont les positions
	du snapshot (engins, urgences, secteurs).

	Cliquer un marqueur sélectionne l'élément, ouvre le panneau correspondant
	et braque la caméra sur sa position. Les couches d'information sont
	réellement activables : elles masquent ou affichent les marqueurs.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local City = require(Shared:WaitForChild("City"))

local UI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ERSClient"):WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))

local MiniMap = {}

local function mapPosition(x: number, z: number): any
	local size = City.WIDTH
	return UDim2.fromScale(math.clamp(x / size, 0, 1), math.clamp(z / size, 0, 1))
end

local function scaleRect(x0: number, z0: number, x1: number, z1: number): any
	return {
		position = mapPosition(x0, z0),
		size = UDim2.fromScale((x1 - x0) / City.WIDTH, (z1 - z0) / City.WIDTH),
	}
end

local function blockColor(kind: string): any
	if kind == "parc" then
		return Theme.colors.success
	elseif kind == "place" then
		return Theme.colors.steel
	elseif kind == "caserne" then
		return Theme.colors.accent
	end
	return Theme.colors.panel
end

function MiniMap.create(parent: any, context: any): any
	local controller = context.controller
	local plan = City.build(Config.CITY_SEED)
	local camera = context.camera

	local root = Widgets.frame(parent, "MiniCarte", {
		BackgroundColor3 = Theme.colors.panelDark,
		Size = UDim2.fromOffset(Theme.sizes.minimapWidth, Theme.sizes.minimapHeight),
		ZIndex = 10,
	})
	Widgets.stroke(root, Theme.colors.steel, 2)
	Widgets.corner(root, Theme.radius.small)

	local inner = Theme.sizes.minimapWidth - 16

	local header = Widgets.label(root, "Titre", "CARTE TACTIQUE", {
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -16, 0, 18),
		TextSize = 11,
		Font = Theme.fonts.bold,
		TextColor3 = Theme.colors.text,
	})
	local summary = Widgets.label(root, "Resume", "", {
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -16, 0, 18),
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Theme.fonts.mono,
		TextColor3 = Theme.colors.textDim,
	})
	summary.Position = UDim2.fromOffset(8, 4)

	local host = Widgets.frame(root, "Zone", {
		BackgroundColor3 = Theme.colors.well,
		Position = UDim2.fromOffset(8, 26),
		Size = UDim2.fromOffset(inner, inner),
	})
	Widgets.stroke(host, Theme.colors.border, 1)
	host.ClipsDescendants = true

	-- ── Fond de ville, dessiné une seule fois ─────────────────
	local cityLayer = Widgets.frame(host, "Ville", {
		BackgroundColor3 = Theme.colors.map,
		BackgroundTransparency = 0,
		Size = UDim2.fromScale(1, 1),
	})

	for _, road in ipairs(plan.roads) do
		if road.axis == "avenue" then
			Widgets.frame(cityLayer, "Avenue", {
				BackgroundColor3 = Theme.colors.mapGrid,
				Size = UDim2.fromScale(road.width / City.WIDTH, 1),
				Position = mapPosition(road.x - road.width / 2, 0),
			})
		else
			Widgets.frame(cityLayer, "Rue", {
				BackgroundColor3 = Theme.colors.mapGrid,
				Size = UDim2.fromScale(1, road.width / City.WIDTH),
				Position = mapPosition(0, road.z - road.width / 2),
			})
		end
	end

	for _, block in ipairs(plan.blocks) do
		local rect = scaleRect(block.x0, block.z0, block.x1, block.z1)
		local tile = Widgets.frame(cityLayer, "Ilot_" .. block.column .. "_" .. block.row, {
			BackgroundColor3 = blockColor(block.kind),
			BackgroundTransparency = block.kind == "habitat" and 0.15 or 0.05,
			Position = rect.position,
			Size = rect.size,
		})
		Widgets.stroke(tile, Theme.colors.map, 1)
	end

	-- Bâtiments : couche activable, masquée sans perdre les îlots.
	local buildingLayer = Widgets.frame(host, "Batiments", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	for index, building in ipairs(plan.buildings) do
		local rect = scaleRect(building.x0, building.z0, building.x1, building.z1)
		Widgets.frame(buildingLayer, "Batiment_" .. index, {
			BackgroundColor3 = Theme.colors.background,
			BackgroundTransparency = 0.25,
			Position = rect.position,
			Size = rect.size,
		})
	end

	local shortName = {eglise = "Église", commissariat = "Police", industrie = "Usine"}
	for _, poi in ipairs(plan.pois) do
		Widgets.label(host, "POI_" .. poi.id, shortName[poi.id] or poi.name, {
			Position = UDim2.new(0, 0, 0, 0),
			Size = UDim2.fromOffset(64, 16),
			TextSize = 8,
			Font = Theme.fonts.bold,
			TextColor3 = Theme.colors.text,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 12,
		}).Position = mapPosition(poi.x, poi.z)
	end

	local districtLabels = {}
	for _, district in ipairs(plan.districts) do
		local label = Widgets.label(host, "Quartier_" .. district.id, string.upper(district.name), {
			Size = UDim2.fromOffset(94, 16),
			TextSize = 8,
			Font = Theme.fonts.bold,
			TextColor3 = Theme.colors.textMuted,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 12,
		})
		label.Position = mapPosition(district.x, district.z - 7)
		table.insert(districtLabels, label)
	end

	-- Caserne : repère fixe et lisible.
	local hq = Widgets.frame(host, "Caserne", {
		BackgroundColor3 = Theme.colors.accent,
		Size = UDim2.fromOffset(16, 16),
		Position = mapPosition(Config.HQ_X, Config.HQ_Z),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 14,
	})
	Widgets.corner(hq, 3)
	Widgets.stroke(hq, Theme.colors.text, 1)
	Widgets.label(hq, "Etiquette", "PC", {
		Size = UDim2.fromScale(1, 1),
		TextSize = 9,
		Font = Theme.fonts.bold,
		TextColor3 = Theme.colors.background,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local sectorLayer = Widgets.frame(host, "Secteurs", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	local routeLayer = Widgets.frame(host, "Trajets", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	local markerLayer = Widgets.frame(host, "Marqueurs", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })

	-- Cadre de visée de la caméra principale.
	local viewFrame = Widgets.frame(host, "Visee", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.3, 0.24),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 15,
	})
	Widgets.stroke(viewFrame, Theme.colors.active, 2)
	viewFrame.Visible = false

	-- ── Marqueurs de véhicules ────────────────────────────────
	local vehicleMarkers = Widgets.list(markerLayer, function(vehicle)
		return vehicle.id
	end, function(vehicle)
		local marker = Instance.new("TextButton")
		marker.Name = "Vehicule_" .. vehicle.id
		marker.Text = ""
		marker.BorderSizePixel = 0
		marker.Size = UDim2.fromOffset(10, 10)
		marker.AnchorPoint = Vector2.new(0.5, 0.5)
		marker.BackgroundColor3 = Theme.serviceColor[vehicle.service] or Theme.colors.info
		marker.AutoButtonColor = false
		marker.ZIndex = 16
		Widgets.corner(marker, 2)
		local stroke = Widgets.stroke(marker, Theme.colors.background, 1)

		local caption = Widgets.label(marker, "Indicatif", vehicle.callsign, {
			Size = UDim2.fromOffset(72, 16),
			Position = UDim2.fromOffset(-28, 11),
			TextSize = 8,
			TextColor3 = Theme.colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Theme.fonts.mono,
			ZIndex = 16,
		})

		marker.MouseButton1Click:Connect(function()
			controller:select("vehicle", vehicle.id, true)
			if camera then
				local selected = controller:selectedVehicle()
				if selected then
					camera:focus(selected.x, selected.z)
				end
			end
		end)

		return { instance = marker, stroke = stroke, caption = caption }
	end, function(entry, vehicle)
		entry.instance.Position = mapPosition(vehicle.x, vehicle.z)
		entry.instance.BackgroundColor3 = Theme.serviceColor[vehicle.service] or Theme.colors.info
		entry.instance.BackgroundTransparency = vehicle.status == Constants.VEHICLE_STATUS.AVAILABLE and 0.25 or 0
		entry.caption.Text = vehicle.callsign
		local selected = controller.state.vehicleId == vehicle.id
		entry.caption.Visible = selected
		entry.stroke.Color = selected and Theme.colors.active or Theme.colors.background
		entry.stroke.Thickness = selected and 2 or 1
	end)

	-- ── Marqueurs d'interventions ─────────────────────────────
	local incidentMarkers = Widgets.list(markerLayer, function(incident)
		return incident.id
	end, function(incident)
		local marker = Instance.new("TextButton")
		marker.Name = "Intervention_" .. incident.id
		marker.Text = "!"
		marker.TextColor3 = Theme.colors.background
		marker.TextSize = Theme.text.tiny
		marker.Font = Theme.fonts.bold
		marker.BorderSizePixel = 0
		marker.Size = UDim2.fromOffset(16, 16)
		marker.AnchorPoint = Vector2.new(0.5, 0.5)
		marker.BackgroundColor3 = Theme.colors.warning
		marker.AutoButtonColor = false
		marker.ZIndex = 17
		Widgets.circle(marker)
		local stroke = Widgets.stroke(marker, Theme.colors.background, 1)

		local caption = Widgets.label(marker, "Delai", "", {
			Size = UDim2.fromOffset(56, 16),
			Position = UDim2.fromOffset(-20, 17),
			TextSize = 8,
			TextColor3 = Theme.colors.warning,
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Theme.fonts.mono,
			ZIndex = 17,
		})

		marker.MouseButton1Click:Connect(function()
			controller:select("incident", incident.id, true)
			if camera then
				local selected = controller:selectedIncident()
				if selected then
					camera:focus(selected.x, selected.z)
				end
			end
		end)

		return { instance = marker, stroke = stroke, caption = caption }
	end, function(entry, incident)
		entry.instance.Position = mapPosition(incident.x, incident.z)
		local color = Theme.colors.warning
		if incident.status == Constants.INCIDENT_STATUS.ACTIVE then
			color = Theme.colors.accent
		elseif incident.status == Constants.INCIDENT_STATUS.RESOLVED then
			color = Theme.colors.success
		elseif incident.status == Constants.INCIDENT_STATUS.FAILED then
			color = Theme.colors.danger
		end
		entry.instance.BackgroundColor3 = color
		entry.caption.TextColor3 = color
		entry.caption.Text = Theme.seconds(incident.deadlineIn)
		local selected = controller.state.incidentId == incident.id
		entry.stroke.Color = selected and Theme.colors.active or Theme.colors.background
		entry.stroke.Thickness = selected and 2 or 1
	end)

	-- ── Secteurs ──────────────────────────────────────────────
	local sectorViews = Widgets.list(sectorLayer, function(sector)
		return sector.id
	end, function(sector)
		local circle = Widgets.frame(sectorLayer, "Secteur_" .. sector.id, {
			BackgroundColor3 = Theme.colors.info,
			BackgroundTransparency = 0.9,
			Size = UDim2.fromScale(0.01, 0.01),
			AnchorPoint = Vector2.new(0.5, 0.5),
		})
		Widgets.circle(circle)
		Widgets.stroke(circle, Theme.colors.info, 1)
		local name = Widgets.label(circle, "Nom", sector.name, {
			Size = UDim2.fromOffset(90, 12),
			Position = UDim2.fromScale(0.5, -0.1),
			AnchorPoint = Vector2.new(0.5, 0.5),
			TextSize = 9,
			TextColor3 = Theme.colors.info,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		return { instance = circle, label_ = name }
	end, function(entry, sector)
		local diameter = (sector.radius * 2) / City.WIDTH
		entry.instance.Position = mapPosition(sector.x, sector.z)
		entry.instance.Size = UDim2.fromScale(diameter, diameter)
		entry.instance.BackgroundTransparency = sector.groupId and 0.85 or 0.94
		entry.label_.Text = sector.name
	end)

	-- ── Trajets en cours ──────────────────────────────────────
	-- Un conteneur par engin, puis un segment par tronçon de la polyligne
	-- routière : la carte suit les rues au lieu de tracer un vol d'oiseau.
	local routeViews = Widgets.list(routeLayer, function(vehicle)
		return vehicle.id
	end, function(vehicle)
		local line = Widgets.frame(routeLayer, "Trajet_" .. vehicle.id, {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		})
		return { instance = line, segments = {} }
	end, function(entry, vehicle)
		local route = vehicle.route
		if not route then
			entry.instance.Visible = false
			return
		end

		local points = route.points
		if points == nil or #points < 2 then
			points = {
				{ x = route.ax, z = route.az },
				{ x = route.bx, z = route.bz },
			}
		end

		local needed = #points - 1
		while #entry.segments < needed do
			local segment = Widgets.frame(entry.instance, "Segment_" .. (#entry.segments + 1), {
				BackgroundColor3 = Theme.serviceColor[vehicle.service] or Theme.colors.info,
				BackgroundTransparency = 0.4,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(0, 2),
				AnchorPoint = Vector2.new(0.5, 0.5),
			})
			table.insert(entry.segments, segment)
		end

		for index, segment in ipairs(entry.segments) do
			if index > needed then
				segment.Visible = false
			else
				segment.Visible = true
				local a = points[index]
				local b = points[index + 1]
				local ax = a.x / City.WIDTH
				local az = a.z / City.WIDTH
				local bx = b.x / City.WIDTH
				local bz = b.z / City.WIDTH
				local dx = bx - ax
				local dz = bz - az
				local length = math.sqrt(dx * dx + dz * dz)
				segment.Size = UDim2.new(length, 0, 0, 2)
				segment.Position = UDim2.fromScale((ax + bx) / 2, (az + bz) / 2)
				segment.Rotation = math.deg(math.atan2(dz, dx))
			end
		end

		entry.instance.Visible = true
	end)

	-- ── Commandes sous la carte ───────────────────────────────
	local controls = Widgets.frame(root, "Commandes", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, inner + 30),
		Size = UDim2.fromOffset(inner, 24),
	})

	local layerButtons = {}
	local layerOrder = { "units", "incidents", "sectors", "buildings" }
	local layerLabels = {
		units = "UNITÉS",
		incidents = "URG.",
		sectors = "SECT.",
		buildings = "BÂTI",
	}
	local cell = (inner - 4 * 4) / 5
	for index, layer in ipairs(layerOrder) do
		local button = Widgets.button(controls, "Couche_" .. layer, layerLabels[layer], function()
			controller:toggleLayer(layer)
		end, {
			Position = UDim2.fromOffset((index - 1) * (cell + 4), 0),
			Size = UDim2.fromOffset(cell, 22),
			TextSize = 8,
			Font = Theme.fonts.bold,
			BackgroundColor3 = Theme.colors.command,
			TextColor3 = Theme.colors.textDim,
		})
		layerButtons[layer] = button
	end

	local crewButton = Widgets.button(controls, "Couche_personnel", "ÉQUIPES", function()
		controller:setTab("personnel")
	end, {
		Position = UDim2.fromOffset(4 * (cell + 4), 0),
		Size = UDim2.fromOffset(cell, 22),
		TextSize = 8,
		Font = Theme.fonts.bold,
		BackgroundColor3 = Theme.colors.command,
		TextColor3 = Theme.colors.commandText,
	})
	layerButtons.personnel = crewButton

	local function update(snapshot: any, state: any, view: any?): ()
		local units = snapshot.vehicles or {}
		local incidents = snapshot.incidents or {}
		local sectors = snapshot.sectors or {}
		summary.Text = string.format("%d · %d · %d", #units, #incidents, #sectors)

		vehicleMarkers.update(units)
		incidentMarkers.update(incidents)
		sectorViews.update(sectors)
		routeViews.update(units)

		for _, entry in pairs(vehicleMarkers.entries) do
			entry.instance.Visible = state.layers.units == true
		end
		for _, entry in pairs(incidentMarkers.entries) do
			entry.instance.Visible = state.layers.incidents == true
		end
		for _, entry in pairs(sectorViews.entries) do
			entry.instance.Visible = state.layers.sectors == true
		end
		for _, entry in pairs(routeViews.entries) do
			entry.instance.Visible = entry.instance.Visible and state.layers.units == true
		end
		buildingLayer.Visible = state.layers.buildings == true

		for layer, button in pairs(layerButtons) do
			if layer ~= "personnel" then
				local active = state.layers[layer] == true
				button.BackgroundColor3 = active and Theme.colors.panelLight or Theme.colors.command
				button.TextColor3 = active and Theme.colors.active or Theme.colors.textMuted
			end
		end

		if view and camera then
			local width = math.clamp((view.width or 0) / City.WIDTH, 0.04, 1)
			local height = math.clamp((view.height or 0) / City.WIDTH, 0.04, 1)
			viewFrame.Size = UDim2.fromScale(width, height)
			viewFrame.Position = mapPosition(view.x, view.z)
			viewFrame.Visible = true
		else
			viewFrame.Visible = false
		end
	end

	local function setCamera(value: any): ()
		camera = value
	end

	-- Réduit la carte pour qu'elle reste sous la barre supérieure, à droite de
	-- la colonne d'onglets et au-dessus de la barre inférieure. Sans cela, une
	-- fenêtre courte la ferait passer sous la barre de commandes.
	local function resize(viewportX: number?, viewportY: number?, requestedWidth: number?): ()
		if not viewportX or not viewportY or viewportX <= 0 or viewportY <= 0 then
			return
		end
		local availableX = viewportX - Theme.sizes.tabsCompact - 24
		local availableY = viewportY - Theme.sizes.topBar - Theme.sizes.bar - 24
		local fitX = availableX / Theme.sizes.minimapWidth
		local fitY = availableY / Theme.sizes.minimapHeight
		local fraction = math.clamp(math.min(1, fitX, fitY), 0.50, 1)
		local side = math.max(140, math.floor((Theme.sizes.minimapHeight * fraction) - 76))
		if requestedWidth then
			local maximum = math.max(140, math.min(availableX - 196, availableY - 76))
			side = math.clamp(requestedWidth - 16, math.min(240, maximum), maximum)
		end
		local width = side + 16
		if root.Size.X.Offset == width and controls.Size.X.Offset == side and root.Size.Y.Offset == side + 76 then return end
		root.Size = UDim2.fromOffset(width, side + 76)
		host.Size = UDim2.fromOffset(side, side)
		controls.Position = UDim2.fromOffset(8, side + 30)
		controls.Size = UDim2.fromOffset(side, 26)
		for i, key in ipairs({"units", "incidents", "sectors", "buildings", "personnel"}) do
			local button = layerButtons[key]
			button.Size = UDim2.new(0.2, -3.2, 0, 24)
			button.Position = UDim2.new((i - 1) / 5, (i - 1) * 0.8, 0, 0)
			button.Text = key == "personnel" and (side < 280 and "ÉQ." or "ÉQUIPES") or layerLabels[key]
		end
		for _, label in ipairs(districtLabels) do
			label.Visible = side >= 300
		end
	end

	update(context.snapshot or { vehicles = {}, incidents = {}, sectors = {} }, controller.state, nil)

	return {
		root = root,
		update = update,
		resize = resize,
		setCamera = setCamera,
		markers = { vehicles = vehicleMarkers, incidents = incidentMarkers },
		routes = routeViews,
		layerButtons = layerButtons,
		viewFrame = viewFrame,
		plan = plan,
	}
end

return MiniMap
