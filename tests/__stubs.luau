--!nonstrict
--[[
	__stubs — doublures Roblox pour les tests headless.

	Ce fichier ne simule que ce que le projet utilise réellement : Instances GUI,
	signaux, tweens, caméra, entrées. Il permet de construire l'interface et de
	vérifier sa structure et ses actions sans ouvrir Studio.

	Il est chargé par `__prelude.luau` avant que `require` ne soit remplacé par
	le chargeur de modules virtuel.
]]

local Stubs = {}

-- ─────────────────────────────────────────────────────────────
-- Signaux
-- ─────────────────────────────────────────────────────────────
local function newSignal()
	local handlers = {}
	local signal = {
		connected = handlers,
	}

	function signal:Connect(callback)
		assert(type(callback) == "function", "Connect attend une fonction")
		local connection = {
			connected = true,
		}
		table.insert(handlers, { callback = callback, connection = connection })
		function connection:Disconnect()
			if not connection.connected then
				return
			end
			connection.connected = false
			for index, entry in ipairs(handlers) do
				if entry.connection == connection then
					table.remove(handlers, index)
					break
				end
			end
		end
		return connection
	end

	function signal:Fire(...)
		local snapshot = table.clone(handlers)
		for _, entry in ipairs(snapshot) do
			if entry.connection.connected then
				entry.callback(...)
			end
		end
	end

	function signal:Once(callback)
		local connection
		connection = self:Connect(function(...)
			connection:Disconnect()
			callback(...)
		end)
		return connection
	end

	function signal:Wait()
		return nil
	end

	return signal
end

Stubs.newSignal = newSignal

-- ─────────────────────────────────────────────────────────────
-- Types de données
-- ─────────────────────────────────────────────────────────────
local function udim2(xs, xo, ys, yo)
	return {
		X = { Scale = xs, Offset = xo },
		Y = { Scale = ys, Offset = yo },
	}
end

local UDim2 = {
	new = function(xs, xo, ys, yo)
		return udim2(xs or 0, xo or 0, ys or 0, yo or 0)
	end,
	fromScale = function(xs, ys)
		return udim2(xs or 0, 0, ys or 0, 0)
	end,
	fromOffset = function(xo, yo)
		return udim2(0, xo or 0, 0, yo or 0)
	end,
}

local UDim = {
	new = function(scale, offset)
		return { Scale = scale or 0, Offset = offset or 0 }
	end,
}

local Vector2 = {
	new = function(x, y)
		return { X = x or 0, Y = y or 0 }
	end,
}

local Vector3 = {
	new = function(x, y, z)
		return { X = x or 0, Y = y or 0, Z = z or 0 }
	end,
}

local function newColor(r, g, b)
	return { R = r or 0, G = g or 0, B = b or 0 }
end

local Color3 = {
	new = newColor,
	fromRGB = function(r, g, b)
		return newColor((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
	end,
	fromHSV = function(h, s, v)
		return newColor(h or 0, s or 0, v or 0)
	end,
}

local CFrame = {
	new = function(x, y, z)
		if type(x) == "table" then
			return { Position = x, __type = "CFrame" }
		end
		return {
			Position = Vector3.new(x or 0, y or 0, z or 0),
			__type = "CFrame",
		}
	end,
	lookAt = function(from, to)
		return {
			Position = from,
			LookVector = Vector3.new((to.X or 0) - (from.X or 0), (to.Y or 0) - (from.Y or 0), (to.Z or 0) - (from.Z or 0)),
			__type = "CFrame",
		}
	end,
}

local TweenInfo = {
	new = function(time, easingStyle, easingDirection, repeatCount, reverses, delayTime)
		return {
			Time = time or 0,
			EasingStyle = easingStyle,
			EasingDirection = easingDirection,
			RepeatCount = repeatCount or 0,
			Reverses = reverses or false,
			DelayTime = delayTime or 0,
		}
	end,
}

local Rect = {
	new = function(minX, minY, maxX, maxY)
		return { Min = Vector2.new(minX, minY), Max = Vector2.new(maxX, maxY) }
	end,
}

-- ─────────────────────────────────────────────────────────────
-- Enum (mémoïsé pour que les comparaisons d'identité fonctionnent)
-- ─────────────────────────────────────────────────────────────
local enumItems = {}
local Enum = setmetatable({}, {
	__index = function(_, category)
		return setmetatable({}, {
			__index = function(_, item)
				local key = category .. "." .. item
				local value = enumItems[key]
				if not value then
					value = { EnumType = category, Name = item, Value = 0 }
					enumItems[key] = value
				end
				return value
			end,
		})
	end,
})

-- ─────────────────────────────────────────────────────────────
-- Instances
-- ─────────────────────────────────────────────────────────────
local GUI_CLASSES = {
	Frame = true,
	ScrollingFrame = true,
	TextLabel = true,
	TextButton = true,
	TextBox = true,
	ImageLabel = true,
	ImageButton = true,
	ViewportFrame = true,
	CanvasGroup = true,
}

local SIGNAL_NAMES = {
	MouseButton1Click = true,
	MouseButton1Down = true,
	MouseButton1Up = true,
	MouseEnter = true,
	MouseLeave = true,
	Activated = true,
	Focused = true,
	FocusLost = true,
	Changed = true,
	InputBegan = true,
	InputEnded = true,
	TouchTap = true,
	TouchLongPress = true,
}

local DEFAULTS = {
	Visible = true,
	Text = "",
	TextSize = 14,
	TextScaled = false,
	BackgroundTransparency = 0,
	BorderSizePixel = 1,
	LayoutOrder = 0,
	ZIndex = 1,
	ClipsDescendants = false,
	ScrollBarThickness = 6,
	AutomaticCanvasSize = 0,
	TextWrapped = false,
	RichText = false,
	AnchorPoint = Vector2.new(0, 0),
	Size = UDim2.new(0, 0, 0, 0),
	Position = UDim2.new(0, 0, 0, 0),
	BackgroundColor3 = newColor(1, 1, 1),
	TextColor3 = newColor(0, 0, 0),
	AbsoluteSize = Vector2.new(100, 40),
	AbsolutePosition = Vector2.new(0, 0),
	AbsoluteContentSize = Vector2.new(100, 40),
	CanvasSize = UDim2.new(0, 0, 0, 0),
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	AutomaticSize = Enum.AutomaticSize.None,
	AutomaticCanvasSize = Enum.AutomaticSize.None,
}

local InstanceMT = {}
local methods = {}

-- Double de la synthèse vocale ; mémorise les commandes de lecture.
function methods:Play()
	assert(self.ClassName == "AudioTextToSpeech")
	self.IsPlaying = true
end

function methods:Pause()
	assert(self.ClassName == "AudioTextToSpeech")
	self.IsPlaying = false
end

-- Mémorise la pose du modèle pour les assertions de sens et de mouvement.
function methods:PivotTo(target)
	assert(self.ClassName == "Model")
	self.WorldPivot = target
end

function methods:GetChildren()
	local copy = {}
	for _, child in ipairs(self.__children) do
		table.insert(copy, child)
	end
	return copy
end

function methods:GetDescendants()
	local list = {}
	local function walk(node)
		for _, child in ipairs(node.__children) do
			table.insert(list, child)
			walk(child)
		end
	end
	walk(self)
	return list
end

function methods:FindFirstChild(name)
	for _, child in ipairs(self.__children) do
		if child.Name == name then
			return child
		end
	end
	return nil
end

function methods:FindFirstChildOfClass(className)
	for _, child in ipairs(self.__children) do
		if child.ClassName == className then
			return child
		end
	end
	return nil
end

function methods:WaitForChild(name)
	local child = self:FindFirstChild(name)
	if not child then
		error("WaitForChild : " .. tostring(name) .. " introuvable sous " .. tostring(self.Name))
	end
	return child
end

function methods:IsA(className)
	if self.ClassName == className then
		return true
	end
	if className == "GuiObject" and GUI_CLASSES[self.ClassName] then
		return true
	end
	if className == "BasePart" and (self.ClassName == "Part" or self.ClassName == "SpawnLocation") then
		return true
	end
	return false
end

function methods:Destroy()
	if self.__destroyed then
		return
	end
	self.__destroyed = true
	for _, child in ipairs(table.clone(self.__children)) do
		child:Destroy()
	end
	if self.__parent then
		local siblings = self.__parent.__children
		for index, child in ipairs(siblings) do
			if child == self then
				table.remove(siblings, index)
				break
			end
		end
	end
	self.__parent = nil
	self.Parent = nil
end

function methods:ClearAllChildren()
	for _, child in ipairs(table.clone(self.__children)) do
		child:Destroy()
	end
	table.clear(self.__children)
end

function methods:Clone()
	local copy = Instance.new(self.ClassName)
	for key, value in pairs(self) do
		if key ~= "__children" and key ~= "__parent" and key ~= "__destroyed" and key ~= "__isInstance" and key ~= "ClassName" then
			copy[key] = value
		end
	end
	for _, child in ipairs(self.__children) do
		local childCopy = child:Clone()
		childCopy.Parent = copy
	end
	return copy
end

function methods:GetPropertyChangedSignal(_property)
	return newSignal()
end

InstanceMT.__index = function(self, key)
	if key == "Parent" then
		return self.__parent
	end
	if key == "ClassName" then
		return rawget(self, "ClassName")
	end
	local value = rawget(self, key)
	if value ~= nil then
		return value
	end
	if SIGNAL_NAMES[key] then
		local signal = newSignal()
		rawset(self, key, signal)
		return signal
	end
	if DEFAULTS[key] ~= nil then
		return DEFAULTS[key]
	end
	return nil
end

-- Champs internes légitimes des doublures. Tout autre champ `__xxx` est refusé :
-- Roblox n'accepte pas d'attribut arbitraire sur une Instance, donc une écriture
-- de ce type doit casser les tests headless au lieu de passer inaperçue.
local INTERNAL_FIELDS = {
	__parent = true,
	__children = true,
	__destroyed = true,
	__isInstance = true,
}

InstanceMT.__newindex = function(self, key, value)
	if type(key) == "string" and key:sub(1, 2) == "__" and not INTERNAL_FIELDS[key] then
		error(
			string.format(
				"Champ interne inconnu '%s' écrit sur une Instance (%s) : Roblox refuse ce champ.",
				key,
				tostring(rawget(self, "ClassName"))
			),
			2
		)
	end
	if key == "Parent" then
		local previous = self.__parent
		if previous then
			for index, child in ipairs(previous.__children) do
				if child == self then
					table.remove(previous.__children, index)
					break
				end
			end
		end
		self.__parent = value
		if value then
			table.insert(value.__children, self)
		end
		return
	end
	rawset(self, key, value)
end

local function newInstance(className, parent)
	local instance = {
		ClassName = className,
		Name = className,
		__children = {},
		__parent = nil,
		__destroyed = false,
		__isInstance = true,
	}
	for key, value in pairs(methods) do
		instance[key] = value
	end
	setmetatable(instance, InstanceMT)
	if parent then
		instance.Parent = parent
	end
	return instance
end

local Instance = {
	new = function(className, parent)
		return newInstance(className, parent)
	end,
}

Stubs.Instance = Instance
Stubs.UDim = UDim
Stubs.UDim2 = UDim2
Stubs.Vector2 = Vector2
Stubs.Vector3 = Vector3
Stubs.Color3 = Color3
Stubs.CFrame = CFrame
Stubs.TweenInfo = TweenInfo
Stubs.Rect = Rect
Stubs.Enum = Enum
Stubs.newSignal = newSignal

-- ─────────────────────────────────────────────────────────────
-- Services
-- ─────────────────────────────────────────────────────────────
local localPlayer = {
	UserId = 1,
	Name = "JoueurTest",
	DisplayName = "JoueurTest",
}

local camera = newInstance("Camera")
camera.CFrame = CFrame.new(300, 400, 300)
camera.CameraType = Enum.CameraType.Custom
camera.FieldOfView = 40

local workspace = newInstance("Workspace")
workspace.CurrentCamera = camera

local players = {
	LocalPlayer = localPlayer,
	PlayerAdded = newSignal(),
	PlayerRemoving = newSignal(),
	GetPlayers = function()
		return { localPlayer }
	end,
	GetPlayerFromCharacter = function()
		return localPlayer
	end,
}

local tweenService = {
	Create = function(_, instance, _info, properties)
		local completed = newSignal()
		local tween = {
			Completed = completed,
			Play = function()
				for key, value in pairs(properties) do
					instance[key] = value
				end
				completed:Fire(Enum.PlaybackState.Completed)
			end,
			Cancel = function() end,
			Pause = function() end,
		}
		return tween
	end,
}

local userInputService = {
	InputBegan = newSignal(),
	InputChanged = newSignal(),
	InputEnded = newSignal(),
	TouchEnabled = false,
	KeyboardEnabled = true,
	MouseEnabled = true,
	GetLastInputType = function()
		return Enum.UserInputType.Keyboard
	end,
}

local runService = {
	Heartbeat = newSignal(),
	RenderStepped = newSignal(),
	Stepped = newSignal(),
	IsStudio = function()
		return true
	end,
	IsClient = function()
		return true
	end,
	IsServer = function()
		return false
	end,
}

local guiService = {
	SelectedObject = nil,
}

local services = {
	Players = players,
	Workspace = workspace,
	TweenService = tweenService,
	UserInputService = userInputService,
	RunService = runService,
	GuiService = guiService,
	Lighting = newInstance("Lighting"),
	SoundService = newInstance("SoundService"),
	ReplicatedStorage = newInstance("ReplicatedStorage"),
	ServerScriptService = newInstance("ServerScriptService"),
	StarterPlayer = newInstance("StarterPlayer"),
	DataStoreService = {
		GetDataStore = function()
			error("DataStore indisponible en test")
		end,
	},
}

Stubs.services = services
Stubs.workspace = workspace
Stubs.camera = camera
Stubs.localPlayer = localPlayer

Stubs.task = {
	wait = function()
		return 0
	end,
	spawn = function(callback, ...)
		callback(...)
		return nil
	end,
	defer = function(callback, ...)
		callback(...)
		return nil
	end,
	delay = function()
		-- Volontairement inactif : les tests ne doivent pas dépendre du temps.
	end,
	cancel = function() end,
}

-- Équivalent de `typeof` côté Roblox : les doublures d'Instance se déclarent
-- comme telles pour que les services puissent distinguer une Instance d'une
-- table, exactement comme en jeu.
function Stubs.typeof(value)
	if type(value) == "table" and rawget(value, "__isInstance") then
		return "Instance"
	end
	return type(value)
end

return Stubs
