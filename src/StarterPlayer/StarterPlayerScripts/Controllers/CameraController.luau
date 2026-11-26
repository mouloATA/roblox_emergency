--!strict
--[[
	CameraController — caméra isométrique tactique.

	La caméra décrit une orbite autour d'un point de la carte : distance,
	orientation (par pas de 45°) et inclinaison fixes. Elle ne suit pas le
	personnage : elle sert à lire la ville et à désigner un objectif.

	Repères :
	- `target`    : point visé, en unités de carte (0..100) ;
	- `distance`  : rayon de l'orbite, en studs ;
	- `yaw`       : orientation autour de la cible, en degrés.

	Les setters appliquent immédiatement le nouveau cadrage : l'interface
	reste réactive, et les tests peuvent vérifier la caméra sans boucle de jeu.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MathX = require(Shared:WaitForChild("Utilities"):WaitForChild("MathX"))

local CameraController = {}

local function normalizeYaw(degrees: number): number
	local value = degrees % 360
	if value < 0 then
		value += 360
	end
	return value
end

function CameraController.new(options: any?): any
	local opts = options or {}
	local self: any = setmetatable({}, { __index = CameraController })
	self.camera = opts.camera or workspace.CurrentCamera
	self.config = opts.config or Config
	self.target = { x = self.config.HQ_X, z = self.config.HQ_Z }
	self.distance = self.config.CAMERA_DISTANCE
	self.yaw = self.config.CAMERA_YAW
	self.followId = nil
	self.viewport = { width = 16, height = 9 }
	self.mounted = false
	return self
end

-- Position de la caméra pour le cadrage courant (studs).
function CameraController.position(self: any): Vector3
	local pitch = math.rad(self.config.CAMERA_PITCH)
	local horizontal = self.distance * math.cos(pitch)
	local height = self.distance * math.sin(pitch)
	local yaw = math.rad(self.yaw)
	local scale = self.config.WORLD_SCALE
	return Vector3.new(
		self.target.x * scale + math.sin(yaw) * horizontal,
		height,
		self.target.z * scale + math.cos(yaw) * horizontal
	)
end

function CameraController.apply(self: any): ()
	if not self.camera then
		return
	end
	local scale = self.config.WORLD_SCALE
	local lookAt = Vector3.new(self.target.x * scale, 0, self.target.z * scale)
	self.camera.CameraType = Enum.CameraType.Scriptable
	self.camera.FieldOfView = self.config.CAMERA_FOV
	self.camera.CFrame = CFrame.lookAt(self:position(), lookAt)
end

function CameraController.mount(self: any): ()
	self.mounted = true
	self:apply()
end

-- Roblox peut remplacer la caméra ou reprendre sa propriété au chargement du personnage.
-- N’écrit la pose que lorsqu’il faut rendre le contrôle à la vue tactique.
function CameraController.syncCamera(self: any, current: any): ()
	if self.mounted and current and (self.camera ~= current or current.CameraType ~= Enum.CameraType.Scriptable) then
		self.camera = current
		self:apply()
	end
end

-- Déplace le point visé (unités de carte).
function CameraController.pan(self: any, dx: number, dz: number): ()
	local margin = self.config.CAMERA_MARGIN
	local size = self.config.MAP_SIZE
	self.target.x = MathX.clamp(self.target.x + dx, -margin, size + margin)
	self.target.z = MathX.clamp(self.target.z + dz, -margin, size + margin)
	self:apply()
end

-- Rapproche (delta négatif) ou éloigne la caméra. `delta` en studs.
function CameraController.zoom(self: any, delta: number): ()
	self.distance = MathX.clamp(self.distance + delta, self.config.CAMERA_DISTANCE_MIN, self.config.CAMERA_DISTANCE_MAX)
	self:apply()
end

-- Fait tourner la caméra par pas de 45° (1 = sens horaire).
function CameraController.rotate(self: any, steps: number): ()
	local step = 45
	self.yaw = normalizeYaw(self.yaw + (steps or 1) * step)
	self:apply()
end

-- Braque la caméra sur un point de la carte et arrête le suivi.
function CameraController.focus(self: any, x: number, z: number): ()
	local margin = self.config.CAMERA_MARGIN
	local size = self.config.MAP_SIZE
	self.followId = nil
	self.target.x = MathX.clamp(x or 0, -margin, size + margin)
	self.target.z = MathX.clamp(z or 0, -margin, size + margin)
	self:apply()
end

function CameraController.focusIncident(self: any, incident: any): ()
	if incident then
		self:focus(incident.x, incident.z)
	end
end

-- Suit un véhicule : `track` est appelé à chaque snapshot.
function CameraController.follow(self: any, vehicleId: any): ()
	self.followId = vehicleId
end

function CameraController.track(self: any, x: number, z: number): ()
	if self.followId == nil then
		return
	end
	self.target.x = MathX.clamp(x, 0, self.config.MAP_SIZE)
	self.target.z = MathX.clamp(z, 0, self.config.MAP_SIZE)
	self:apply()
end

function CameraController.reset(self: any): ()
	self.followId = nil
	self.target = { x = self.config.HQ_X, z = self.config.HQ_Z }
	self.distance = self.config.CAMERA_DISTANCE
	self.yaw = self.config.CAMERA_YAW
	self:apply()
end

--[[
	Emprise visible au sol, en unités de carte.

	Sert à dessiner le cadre de visée sur la mini-carte. On suppose un écran
	proche du 16/9 : la largeur vaut 16/9 de la hauteur, bornée par la carte.
]]
function CameraController.viewExtent(self: any): any
	local scale = self.config.WORLD_SCALE
	local halfHeight = self.distance * math.tan(math.rad(self.config.CAMERA_FOV) / 2)
	local aspect = (self.viewport.width or 16) / (self.viewport.height or 9)
	local halfWidth = halfHeight * aspect
	return {
		width = (halfWidth * 2) / scale,
		height = (halfHeight * 2) / scale,
	}
end

-- Mémorise la taille du viewport (pour l'emprise visible).
function CameraController.setViewport(self: any, width: number, height: number): ()
	if width and height and width > 0 and height > 0 then
		self.viewport = { width = width, height = height }
	end
end

return CameraController
