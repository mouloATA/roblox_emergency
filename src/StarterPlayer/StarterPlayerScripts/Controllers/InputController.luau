--!strict
--[[
	InputController — raccourcis clavier et souris.

	Les touches ne modifient que l'état local (panneaux, menu, caméra) ou
	envoient une intention déjà permise (`save`, vitesse de simulation). Quand
	Roblox signale une saisie texte (`processed`), le raccourci est ignoré.

	Règles :
	- 1–6 sélectionnent les groupes s'il en existe, sinon ouvrent le panneau ;
	- WASD et flèches déplacent la caméra, +/- zooment, Q/E pivotent ;
	- Espace met en pause ou reprend, R recentre sur la caserne ;
	- Ctrl+S sauvegarde (S seul déplace la caméra vers le sud) ;
	- double-clic gauche recentre sur l'unité sélectionnée.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local InputController = {}

local TAB_KEYS = {
	One = "incidents",
	Two = "vehicles",
	Three = "personnel",
	Four = "equipment",
	Five = "command",
	Six = "budget",
	Seven = "roles",
}

local DIGIT_SLOTS = {
	One = 1,
	Two = 2,
	Three = 3,
	Four = 4,
	Five = 5,
	Six = 6,
}

local DOUBLE_CLICK_SECONDS = 0.4

function InputController.new(controller: any, app: any, camera: any): any
	local self: any = setmetatable({}, { __index = InputController })
	self.controller = controller
	self.app = app
	self.camera = camera
	self.connection = nil
	self.changedConnection = nil
	self.endConnection = nil
	self.ctrl = false
	self.lastClick = nil
	return self
end

function InputController.save(self: any): ()
	if not self.controller:can("save") then
		self.controller:toast("Votre poste ne peut pas sauvegarder.", false)
		return
	end
	self.controller:command("save", nil)
end

-- Recentre la caméra sur l'élément sélectionné, sinon sur la caserne.
function InputController.centerSelection(self: any): ()
	if not self.camera then
		return
	end
	local vehicle = self.controller:selectedVehicle()
	if vehicle then
		self.camera:focus(vehicle.x, vehicle.z)
		return
	end
	local incident = self.controller:selectedIncident()
	if incident then
		self.camera:focus(incident.x, incident.z)
		return
	end
	self.camera:reset()
end

-- Double-clic détecté par l'horloge locale (aucune horloge serveur requise).
function InputController.handleClick(self: any, now: number?): ()
	local stamp = now or os.clock()
	if self.lastClick and stamp - self.lastClick <= DOUBLE_CLICK_SECONDS then
		self.lastClick = nil
		self:centerSelection()
		return
	end
	self.lastClick = stamp
end

-- Traite une touche. Retourne true si elle a été consommée.
function InputController.handleKey(self: any, keyCode: any): boolean
	local name = keyCode and keyCode.Name or nil
	if not name then
		return false
	end

	-- Ctrl+S : sauvegarde explicite, pour ne pas voler « S » au déplacement.
	if self.ctrl and name == "S" then
		self:save()
		return true
	end

	if name == "M" then
		self.controller:setMenu(true)
		return true
	end

	-- `Échap` n'est volontairement pas capté : Roblox l'utilise pour son propre
	-- menu et Studio peut l'envoyer à l'ouverture de la fenêtre de jeu, ce qui
	-- refermait le menu au démarrage. On ferme avec « Entrer en opération ».

	local slot = DIGIT_SLOTS[name]
	if slot then
		local groups = self.controller.snapshot.groups or {}
		if #groups > 0 then
			self.controller:selectGroupSlot(slot)
			return true
		end
		local tab = TAB_KEYS[name]
		if tab then
			self.controller:setTab(tab)
		end
		return true
	end

	if name == "Seven" then
		self.controller:setTab(TAB_KEYS.Seven)
		return true
	end

	local step = Config.CAMERA_PAN_STEP
	if name == "W" or name == "Up" then
		if self.camera then
			self.camera:pan(0, -step)
		end
		return true
	elseif name == "S" or name == "Down" then
		if self.camera then
			self.camera:pan(0, step)
		end
		return true
	elseif name == "A" or name == "Left" then
		if self.camera then
			self.camera:pan(-step, 0)
		end
		return true
	elseif name == "D" or name == "Right" then
		if self.camera then
			self.camera:pan(step, 0)
		end
		return true
	end

	if name == "Equal" or name == "KeypadPlus" then
		if self.camera then
			self.camera:zoom(-Config.CAMERA_ZOOM_STEP)
		end
		return true
	elseif name == "Minus" or name == "KeypadMinus" then
		if self.camera then
			self.camera:zoom(Config.CAMERA_ZOOM_STEP)
		end
		return true
	elseif name == "Q" then
		if self.camera then
			self.camera:rotate(-1)
		end
		return true
	elseif name == "E" then
		if self.camera then
			self.camera:rotate(1)
		end
		return true
	end

	if name == "R" then
		if self.camera then
			self.camera:reset()
		end
		return true
	end

	if name == "Space" then
		local scale = self.controller.snapshot.timeScale or 1
		self.controller:setTimeScale(scale == 0 and 1 or 0)
		return true
	end

	return false
end

function InputController.mount(self: any): ()
	local UserInputService = game:GetService("UserInputService")

	self.connection = UserInputService.InputBegan:Connect(function(input: any, processed: boolean)
		if input == nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
			self.ctrl = true
			return
		end
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:handleClick()
			return
		end
		if input.KeyCode then
			self:handleKey(input.KeyCode)
		end
	end)

	self.endConnection = UserInputService.InputEnded:Connect(function(input: any)
		if input and (input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl) then
			self.ctrl = false
		end
	end)

	self.changedConnection = UserInputService.InputChanged:Connect(function(input: any)
		if input == nil or self.camera == nil then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			local amount = input.Position and input.Position.Z or 0
			self.camera:zoom(-amount * Config.CAMERA_ZOOM_STEP)
		end
	end)
end

function InputController.unmount(self: any): ()
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	if self.changedConnection then
		self.changedConnection:Disconnect()
		self.changedConnection = nil
	end
	if self.endConnection then
		self.endConnection:Disconnect()
		self.endConnection = nil
	end
end

return InputController
