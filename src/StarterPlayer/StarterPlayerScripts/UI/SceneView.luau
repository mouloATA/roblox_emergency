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

local UI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ERSClient"):WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))

local SceneView = {}

local PARTICULE_COLOR = {
	fire = Color3.fromRGB(196, 52, 40),
	medical = Color3.fromRGB(240, 240, 240),
	police = Color3.fromRGB(64, 104, 220),
	technical = Color3.fromRGB(214, 168, 64),
	logistics = Color3.fromRGB(120, 176, 140),
	command = Color3.fromRGB(190, 120, 200),
}

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

-- Positionne les pièces d'un engin autour de son point de carte, avec cap.
local function renderVehicle(self: any, entry: any): ()
	local scale = self.scale
	local centerX = entry.x * scale
	local centerZ = entry.z * scale
	local cosH = math.cos(entry.heading)
	local sinH = math.sin(entry.heading)
	for _, item in ipairs(entry.parts) do
		local ox, oy, oz = item.ox, item.oy, item.oz
		item.part.Position = Vector3.new(
			centerX + ox * cosH + oz * sinH,
			oy,
			centerZ - ox * sinH + oz * cosH
		)
		item.part.Orientation = Vector3.new(0, math.deg(entry.heading), 0)
	end
	entry.ring.Position = Vector3.new(centerX, 0.3, centerZ)
end

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

	return self
end

function SceneView.createVehicle(self: any, vehicle: any): any
	local folder = Instance.new("Folder")
	folder.Name = "Engin_" .. tostring(vehicle.id)
	folder.Parent = self.root

	local service = vehicle.service or "fire"
	local color = Theme.serviceColor[service] or Theme.colors.info
	local isLarge = vehicle.typeId == "FPT" or vehicle.typeId == "VPC" or vehicle.typeId == "EPS"
	local length = isLarge and 5.6 or 4.4

	local body = makePart(folder, "Caisse", Vector3.new(length, 1.5, 2.1), color, Enum.Material.SmoothPlastic, 0)
	body.Shape = Enum.PartType.Block
	local cabin = makePart(folder, "Cabine", Vector3.new(2.0, 1.1, 2.0), Color3.fromRGB(232, 232, 232), Enum.Material.SmoothPlastic, 0)
	local light = makePart(folder, "Gyrophare", Vector3.new(length * 0.42, 0.28, 0.7),
		PARTICULE_COLOR[service] or Theme.colors.warning, Enum.Material.Neon, 0.85)
	local ring = makePart(folder, "Selection", Vector3.new(7, 0.22, 7), Theme.colors.active, Enum.Material.Neon, 0.6)
	ring.Shape = Enum.PartType.Ball
	ring.Transparency = 1

	local entry = {
		id = vehicle.id,
		folder = folder,
		body = body,
		cabin = cabin,
		light = light,
		ring = ring,
		parts = {
			{ part = body, ox = 0, oy = 1.15, oz = 0 },
			{ part = cabin, ox = -length * 0.28, oy = 2.15, oz = 0 },
			{ part = light, ox = length * 0.2, oy = 2.55, oz = 0 },
		},
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
		x = incident.x,
		z = incident.z,
	}
	self.incidents.entries[incident.id] = entry
	return entry
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
	local seenVehicles = {}
	for _, vehicle in ipairs(snapshot.vehicles or {}) do
		seenVehicles[vehicle.id] = true
		local entry = self.vehicles.entries[vehicle.id]
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
		entry.light.Transparency = engaged and 0 or 0.85
		entry.light.Color = PARTICULE_COLOR[vehicle.service] or Theme.colors.warning

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
