--!nonstrict
--[[
	__env — environnement Roblox virtuel partagé par les tests.

	Le CLI Luau exécute chaque module avec sa propre table de globales : on ne
	peut donc pas définir `game` une fois pour toutes. L'en-tête injecté par
	tools/check.ps1 dans chaque fichier expose les globales Roblox sous forme de
	locales, et `require` sous forme de fonction locale qui sait résoudre un
	Instance virtuel vers son fichier.

	Arbre reconstruit (identique à l'exécution réelle) :

		ReplicatedStorage.Shared.*
		ServerScriptService.ERS.Services.*
		Players.LocalPlayer.PlayerScripts.ERSClient.*
		Players.LocalPlayer.PlayerGui
]]

local realRequire = require
local stubs = realRequire("./__stubs")
local manifest = realRequire("./manifest")

local env = {}
env.stubs = stubs

local function newNode(name)
	local node = {
		Name = name,
		ClassName = "Folder",
		__children = {},
		__file = nil,
	}
	function node:WaitForChild(childName)
		local child = self.__children[childName]
		if not child then
			error("WaitForChild : " .. tostring(childName) .. " introuvable sous " .. tostring(self.Name))
		end
		return child
	end
	function node:FindFirstChild(childName)
		return self.__children[childName]
	end
	function node:IsA(className)
		return className == "Folder" or className == "Instance"
	end
	return node
end

local services = {
	ReplicatedStorage = newNode("ReplicatedStorage"),
	ServerScriptService = newNode("ServerScriptService"),
	Workspace = stubs.workspace,
	Players = stubs.services.Players,
	RunService = stubs.services.RunService,
	TweenService = stubs.services.TweenService,
	UserInputService = stubs.services.UserInputService,
	GuiService = stubs.services.GuiService,
	Lighting = stubs.services.Lighting,
	SoundService = stubs.services.SoundService,
	DataStoreService = stubs.services.DataStoreService,
}
env.services = services

-- PlayerScripts et PlayerGui : deux dossiers réels à l'exécution.
local playerScripts = newNode("PlayerScripts")
local playerGui = stubs.Instance.new("PlayerGui")
local localPlayer = stubs.localPlayer

localPlayer.Name = "JoueurTest"
localPlayer.__children = {
	PlayerScripts = playerScripts,
	PlayerGui = playerGui,
}
localPlayer.WaitForChild = function(_, childName)
	local child = localPlayer.__children[childName]
	if not child then
		error("WaitForChild : " .. tostring(childName) .. " introuvable sous LocalPlayer")
	end
	return child
end
localPlayer.FindFirstChild = function(_, childName)
	return localPlayer.__children[childName]
end
localPlayer.IsA = function(_, className)
	return className == "Player" or className == "Instance"
end

services.Players.__children = { LocalPlayer = localPlayer }
services.StarterPlayer = newNode("StarterPlayer")
services.StarterPlayer.__children.StarterPlayerScripts = newNode("StarterPlayerScripts")

env.playerScripts = playerScripts
env.playerGui = playerGui
env.localPlayer = localPlayer

local function ensureNode(path)
	local segments = {}
	for segment in string.gmatch(path, "[^%.]+") do
		table.insert(segments, segment)
	end
	if #segments == 0 then
		error("Chemin de module vide")
	end

	local root = services[segments[1]]
	if not root then
		root = newNode(segments[1])
		services[segments[1]] = root
	end
	if root.__children == nil then
		root.__children = {}
	end

	local current = root
	for index = 2, #segments do
		local segment = segments[index]
		local child = current.__children[segment]
		if not child then
			child = newNode(segment)
			current.__children[segment] = child
		end
		current = child
	end
	return current
end

for _, entry in ipairs(manifest) do
	local node = ensureNode(entry.path)
	node.__file = entry.file
end

env.game = {
	GetService = function(_, name)
		local service = services[name]
		if not service then
			service = newNode(name)
			services[name] = service
		end
		return service
	end,
	Workspace = stubs.workspace,
}

env.workspace = stubs.workspace
env.Instance = stubs.Instance
env.UDim = stubs.UDim
env.UDim2 = stubs.UDim2
env.Vector2 = stubs.Vector2
env.Vector3 = stubs.Vector3
env.Color3 = stubs.Color3
env.CFrame = stubs.CFrame
env.TweenInfo = stubs.TweenInfo
env.Rect = stubs.Rect
env.Enum = stubs.Enum

-- `task.wait` renvoie 0 et `task.spawn` ne s'exécute pas : aucun test ne doit
-- dépendre du temps réel ni lancer une boucle infinie.
env.task = {
	wait = function()
		return 0
	end,
	spawn = function() end,
	defer = function(callback, ...)
		callback(...)
	end,
	delay = function() end,
	cancel = function() end,
}

env.typeof = stubs.typeof

local cache = {}
env.cache = cache

env.require = function(target)
	if type(target) == "string" then
		return realRequire(target)
	end
	if type(target) == "table" then
		local file = rawget(target, "__file")
		if file then
			if cache[file] == nil then
				cache[file] = realRequire("./" .. file)
			end
			return cache[file]
		end
	end
	error("require : cible non résolue (utilisez un chemin game:GetService(...))")
end

return env
