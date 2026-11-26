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
	Eight = "missions",
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
local PAN_KEYS = { W = {0,-1}, Up = {0,-1}, S = {0,1}, Down = {0,1}, A = {-1,0}, Left = {-1,0}, D = {1,0}, Right = {1,0} }

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
	self.held = {}
	self.velocity = { x = 0, y = 0 }
	self.drag = nil
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

	if TAB_KEYS[name] then
		self.controller:setTab(TAB_KEYS[name])
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

-- Annule les gestes lors d'une perte de focus ou de l'ouverture d'un menu.
function InputController.cancelMovement(self: any): ()
	table.clear(self.held)
	self.drag = nil
	self.velocity.x, self.velocity.y = 0, 0
	self.lastClick = nil
end

-- Les touches maintenues déplacent la caméra en continu, avec accélération et freinage courts.
function InputController.step(self: any, dt: number): ()
	if self.controller.state.menuOpen or (self.app.editor and self.app.editor.editing)
		or game:GetService("UserInputService"):GetFocusedTextBox() then
		self:cancelMovement()
		return
	end
	local x, y = 0, 0
	for key in pairs(self.held) do
		x += PAN_KEYS[key][1]
		y += PAN_KEYS[key][2]
	end
	local length = math.max(1, math.sqrt(x*x+y*y))
	local seconds = math.min(dt, 0.05)
	local alpha = 1 - math.exp(-20*seconds)
	self.velocity.x += (x/length-self.velocity.x)*alpha
	self.velocity.y += (y/length-self.velocity.y)*alpha
	if self.camera and (math.abs(self.velocity.x)+math.abs(self.velocity.y) > 0.001) then
		self.camera:panScreen(self.velocity.x*600*seconds, self.velocity.y*600*seconds)
	end
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
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if self.controller.state.menuOpen or (self.app.editor and self.app.editor.editing) then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local position = input.Position or UserInputService:GetMouseLocation()
			if not self.app:isHudAt(position) then
				self.drag = { start = position, last = position, moved = false }
			end
			return
		end
		if input.KeyCode then
			local name = input.KeyCode.Name
			if PAN_KEYS[name] and not (self.ctrl and name == "S") then self.held[name] = true return end
			self:handleKey(input.KeyCode)
		end
	end)

	self.endConnection = UserInputService.InputEnded:Connect(function(input: any)
		if input and input.KeyCode then self.held[input.KeyCode.Name] = nil end
		if input and input.UserInputType == Enum.UserInputType.MouseButton1 then
			if self.drag and not self.drag.moved then self:handleClick() end
			self.drag = nil
		end
		if input and (input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl) then
			self.ctrl = false
		end
	end)

	self.changedConnection = UserInputService.InputChanged:Connect(function(input: any, processed: boolean)
		if input == nil or self.camera == nil then
			return
		end
		if self.controller.state.menuOpen or (self.app.editor and self.app.editor.editing) then self:cancelMovement() return end
		if input.UserInputType == Enum.UserInputType.MouseMovement and self.drag then
			local drag = self.drag
			local position = input.Position
			local dx, dy = position.X - drag.start.X, position.Y - drag.start.Y
			if not drag.moved and dx*dx+dy*dy < 16 then return end
			drag.moved = true
			self.lastClick = nil
			if not processed and not self.app:isHudAt(position) then
				self.camera:panScreen(drag.last.X-position.X, drag.last.Y-position.Y)
			end
			drag.last = position
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			if processed or self.app:isHudAt(UserInputService:GetMouseLocation()) then return end
			local amount = input.Position and input.Position.Z or 0
			self.camera:zoom(-amount * Config.CAMERA_ZOOM_STEP)
		end
	end)
	self.frameConnection = game:GetService("RunService").RenderStepped:Connect(function(dt) self:step(dt) end)
	self.focusConnection = UserInputService.WindowFocusReleased:Connect(function() self.ctrl = false self:cancelMovement() end)
end

function InputController.unmount(self: any): ()
	self:cancelMovement()
	if self.frameConnection then self.frameConnection:Disconnect() end
	if self.focusConnection then self.focusConnection:Disconnect() end
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
