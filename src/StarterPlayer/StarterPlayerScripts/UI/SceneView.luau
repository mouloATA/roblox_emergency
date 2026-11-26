--!strict
--[[
	SceneView — engins et urgences visibles dans la ville 3D.

	La scène est purement locale : elle ne crée que des pièces générées par
	code (aucun asset externe) et lit les positions du snapshot serveur. Chaque
	engin reçoit un modèle simple mais distinct selon son service, un gyrophare
	réellement allumé en intervention et un anneau vert de sélection.

	Les positions sont interpolées entre deux snapshots pour éviter les
	téléportations ; `update` recale immédiatement quand la vue n'est pas
	montée (tests headless).
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local City = require(Shared:WaitForChild("City"))

local UI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ERSClient"):WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local StreetModels = require(UI:WaitForChild("StreetModels"))
local StreetTraffic = require(UI:WaitForChild("StreetTraffic"))

local SceneView = {}

local function makePart(parent: any, name: string, size: Vector3, color: Color3, material: Enum.Material?, transparency: number?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Un seul déplacement rigide pour toute la carrosserie, roues et accessoires.
local function renderVehicle(self: any, entry: any): ()
	if entry.drawX == entry.x and entry.drawZ == entry.z and entry.drawHeading == entry.heading then return end
	entry.drawX, entry.drawZ, entry.drawHeading = entry.x, entry.z, entry.heading
	local x, z = entry.x * self.scale, entry.z * self.scale
	entry.folder:PivotTo(CFrame.lookAt(Vector3.new(x, 0, z),
		Vector3.new(x + math.sin(entry.heading), 0, z + math.cos(entry.heading))))
end

-- Crée le conteneur local de la scène mobile.
function SceneView.new(options: any?): any
	local opts = options or {}
	local self: any = setmetatable({}, { __index = SceneView })
	self.workspace = opts.workspace or workspace
	self.scale = opts.scale or Config.WORLD_SCALE
	self.mounted = false
	self.connection = nil
	self.vehicles = { entries = {} }
	self.incidents = { entries = {} }

	local previous = self.workspace:FindFirstChild("ERS_Engins")
	if previous then
		previous:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "ERS_Engins"
	root.Parent = self.workspace
	self.root = root
	self.traffic = StreetTraffic.new(root, self.scale)
	self.buildings = City.build(Config.CITY_SEED).buildings

	return self
end

-- Installe le modèle de spécialité et le témoin de sélection.
function SceneView.createVehicle(self: any, vehicle: any): any
	local service = vehicle.service or "fire"
	local built = StreetModels.vehicle(self.root, "Engin_" .. tostring(vehicle.id), vehicle.typeId, service)
	local ring = makePart(built.model, "Selection", Vector3.new(8.6, 0.12, 8.6), Theme.colors.active, Enum.Material.Neon, 0.6)
	ring.Shape = Enum.PartType.Ball
	ring.Position = Vector3.new(0, 0.43, 0)
	ring.Transparency = 1

	local entry = {
		id = vehicle.id,
		folder = built.model,
		typeId = vehicle.typeId,
		body = built.body,
		light = built.light,
		ring = ring,
		x = vehicle.x,
		z = vehicle.z,
		targetX = vehicle.x,
		targetZ = vehicle.z,
		heading = 0,
		targetHeading = 0,
		lastX = vehicle.x,
		lastZ = vehicle.z,
	}
	self.vehicles.entries[vehicle.id] = entry
	renderVehicle(self, entry)
	return entry
end

-- Crée le marqueur et le registre des foyers visibles.
function SceneView.createIncident(self: any, incident: any): any
	local folder = Instance.new("Folder")
	folder.Name = "Urgence_" .. tostring(incident.id)
	folder.Parent = self.root

	local beacon = makePart(folder, "Balise", Vector3.new(0.7, 10, 0.7), Theme.colors.warning, Enum.Material.Neon, 0.15)
	local glow = makePart(folder, "Flamme", Vector3.new(3.6, 3.6, 3.6), Theme.colors.accent, Enum.Material.Neon, 0.35)
	glow.Shape = Enum.PartType.Ball

	local entry = {
		id = incident.id,
		folder = folder,
		beacon = beacon,
		glow = glow,
		cells = {},
		x = incident.x,
		z = incident.z,
	}
	self.incidents.entries[incident.id] = entry
	return entry
end

-- Place les flammes sur les toits des parcelles bâties et au sol ailleurs.
local function flameHeight(buildings: {any}, x: number, z: number): number
	for _, b in ipairs(buildings) do
		if x >= b.x0 and x <= b.x1 and z >= b.z0 and z <= b.z1 then
			return b.floors * Config.FLOOR_HEIGHT + 0.7
		end
	end
	return 0.5
end

local function renderBurningCells(self: any, entry: any, incident: any): ()
	local active = {}
	for i, cell in ipairs(incident.fireCells or {}) do
		if cell.burning and incident.status ~= Constants.INCIDENT_STATUS.FAILED and incident.status ~= Constants.INCIDENT_STATUS.RESOLVED then
			active[i] = true
			local node = entry.cells[i]
			if not node then
				local anchor = makePart(entry.folder, "Foyer_" .. i, Vector3.new(1, 1, 1), Theme.colors.accent, nil, 1)
				local fire = Instance.new("Fire")
				fire.Parent = anchor
				node = {anchor = anchor, fire = fire}
				entry.cells[i] = node
			end
			if node.x ~= cell.x or node.z ~= cell.z then
				node.x, node.z = cell.x, cell.z
				node.anchor.Position = Vector3.new(cell.x * self.scale, flameHeight(self.buildings, cell.x, cell.z), cell.z * self.scale)
			end
			node.fire.Size = 3 + math.clamp(cell.heat or 0, 0, 100) * 0.13
			node.fire.Heat = node.fire.Size * 0.72
		end
	end
	for i, node in pairs(entry.cells) do
		if not active[i] then
			node.anchor:Destroy()
			entry.cells[i] = nil
		end
	end
end

local function incidentVisual(entry: any, incident: any): ()
	local scale = entry.scale or Config.WORLD_SCALE
	local x = incident.x * scale
	local z = incident.z * scale
	entry.beacon.Position = Vector3.new(x, 5, z)
	entry.glow.Position = Vector3.new(x, 1.9, z)

	local status = incident.status
	local color = Theme.colors.warning
	if status == Constants.INCIDENT_STATUS.ACTIVE then
		color = Theme.colors.accent
	elseif status == Constants.INCIDENT_STATUS.RESOLVED then
		color = Theme.colors.active
	elseif status == Constants.INCIDENT_STATUS.FAILED then
		color = Theme.colors.inactive
	end
	entry.beacon.Color = color
	entry.glow.Color = color
	entry.beacon.Transparency = status == Constants.INCIDENT_STATUS.RESOLVED and 0.7 or 0.15
	entry.glow.Transparency = status == Constants.INCIDENT_STATUS.RESOLVED and 0.8 or 0.35
end

--[[
	Recale la scène sur un snapshot.

	`state.vehicleId` commande l'anneau de sélection. Un engin inconnu est créé,
	un engin disparu est retiré : aucune instance ne fuit entre deux états.
]]
function SceneView.update(self: any, snapshot: any, state: any): ()
	StreetTraffic.sync(self.traffic, snapshot)
	local seenVehicles = {}
	for _, vehicle in ipairs(snapshot.vehicles or {}) do
		seenVehicles[vehicle.id] = true
		local entry = self.vehicles.entries[vehicle.id]
		if entry and entry.typeId ~= vehicle.typeId then
			entry.folder:Destroy()
			entry = nil
		end
		if not entry then
			entry = self:createVehicle(vehicle)
		end

		local dx = vehicle.x - entry.lastX
		local dz = vehicle.z - entry.lastZ
		if dx * dx + dz * dz > 0.0004 then
			entry.targetHeading = math.atan2(dx, dz)
			entry.lastX = vehicle.x
			entry.lastZ = vehicle.z
		end
		entry.targetX = vehicle.x
		entry.targetZ = vehicle.z

		local selected = state ~= nil and state.vehicleId == vehicle.id
		entry.ring.Transparency = selected and 0.55 or 1

		local engaged = vehicle.status == Constants.VEHICLE_STATUS.DISPATCHED
			or vehicle.status == Constants.VEHICLE_STATUS.ON_SCENE
			or vehicle.status == Constants.VEHICLE_STATUS.TRANSPORTING
		entry.light.Transparency = engaged and 0 or 0.85

		if not self.mounted then
			entry.x = entry.targetX
			entry.z = entry.targetZ
			entry.heading = entry.targetHeading
			renderVehicle(self, entry)
		end
	end

	for id, entry in pairs(self.vehicles.entries) do
		if not seenVehicles[id] then
			entry.folder:Destroy()
			self.vehicles.entries[id] = nil
		end
	end

	local seenIncidents = {}
	for _, incident in ipairs(snapshot.incidents or {}) do
		seenIncidents[incident.id] = true
		local entry = self.incidents.entries[incident.id]
		if not entry then
			entry = self:createIncident(incident)
		end
		entry.x = incident.x
		entry.z = incident.z
		entry.scale = self.scale
		incidentVisual(entry, incident)
		renderBurningCells(self, entry, incident)
	end

	for id, entry in pairs(self.incidents.entries) do
		if not seenIncidents[id] then
			entry.folder:Destroy()
			self.incidents.entries[id] = nil
		end
	end
end

-- Interpole les positions vers la cible courante (appelé à chaque frame).
function SceneView.step(self: any, dt: number?): ()
	local delta = math.clamp(dt or 0.016, 0, 0.5)
	local alpha = math.min(1, delta * 7)
	StreetTraffic.step(self.traffic, delta)
	for _, entry in pairs(self.vehicles.entries) do
		entry.x += (entry.targetX - entry.x) * alpha
		entry.z += (entry.targetZ - entry.z) * alpha
		local difference = (entry.targetHeading - entry.heading + math.pi) % (math.pi * 2) - math.pi
		entry.heading += difference * alpha
		renderVehicle(self, entry)
	end
end

function SceneView.mount(self: any): ()
	if self.mounted then
		return
	end
	self.mounted = true
	local RunService = game:GetService("RunService")
	self.connection = RunService.RenderStepped:Connect(function(dt: number)
		self:step(dt)
	end)
end

function SceneView.unmount(self: any): ()
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	self.mounted = false
end

function SceneView.destroy(self: any): ()
	self:unmount()
	if self.root then
		self.root:Destroy()
		self.root = nil
	end
	table.clear(self.vehicles.entries)
	table.clear(self.incidents.entries)
end

return SceneView
