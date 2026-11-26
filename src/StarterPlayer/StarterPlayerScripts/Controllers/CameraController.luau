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

	Les commandes mettent à jour la cible immédiatement. Le cadrage affiché
	converge vers cette cible à chaque image avec une interpolation exponentielle.
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
	self.display = { x = self.target.x, z = self.target.z, distance = self.distance, yaw = self.yaw }
	return self
end

-- Position de la caméra pour le cadrage courant (studs).
function CameraController.position(self: any, pose: any?): Vector3
	local target = pose or self.target
	local distance = pose and pose.distance or self.distance
	local pitch = math.rad(self.config.CAMERA_PITCH)
	local horizontal = distance * math.cos(pitch)
	local height = distance * math.sin(pitch)
	local yaw = math.rad(pose and pose.yaw or self.yaw)
	local scale = self.config.WORLD_SCALE
	return Vector3.new(
		target.x * scale + math.sin(yaw) * horizontal,
		height,
		target.z * scale + math.cos(yaw) * horizontal
	)
end

function CameraController.apply(self: any): ()
	if not self.camera then
		return
	end
	local scale = self.config.WORLD_SCALE
	local lookAt = Vector3.new(self.display.x * scale, 0, self.display.z * scale)
	self.camera.CameraType = Enum.CameraType.Scriptable
	self.camera.FieldOfView = self.config.CAMERA_FOV
	self.camera.CFrame = CFrame.lookAt(self:position(self.display), lookAt)
end

-- Interpole le cadrage à chaque image, avec une réponse indépendante de la fréquence d'affichage.
function CameraController.step(self: any, dt: number): ()
	local alpha = 1 - math.exp(-18 * math.max(0, dt))
	self.display.x += (self.target.x - self.display.x) * alpha
	self.display.z += (self.target.z - self.display.z) * alpha
	self.display.distance += (self.distance - self.display.distance) * alpha
	self.display.yaw += ((self.yaw - self.display.yaw + 180) % 360 - 180) * alpha
	self:apply()
end

-- Déplacement relatif à l'écran et proportionnel au zoom courant.
function CameraController.panScreen(self: any, dx: number, dy: number): ()
	local units = 2 * self.distance * math.tan(math.rad(self.config.CAMERA_FOV) / 2)
		/ math.max(1, self.viewport.height) / self.config.WORLD_SCALE
	local yaw = math.rad(self.yaw)
	local vertical = dy / math.sin(math.rad(self.config.CAMERA_PITCH))
	self.followId = nil
	self:pan((math.cos(yaw) * dx + math.sin(yaw) * vertical) * units,
		(-math.sin(yaw) * dx + math.cos(yaw) * vertical) * units)
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
	self.followId = nil
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
