--!strict
--[[
	Bootstrap client — point d'entrée unique côté joueur.

	Il assemble le contrôleur d'interface, l'application, le réseau, la caméra
	et les raccourcis. Aucune logique de jeu ici : le client affiche les
	snapshots du serveur et envoie des intentions.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local clientRoot = player:WaitForChild("PlayerScripts"):WaitForChild("ERSClient")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Catalogs = Shared:WaitForChild("Catalogs")
local catalogs = {
	vehicles = require(Catalogs:WaitForChild("Vehicles")),
	qualifications = require(Catalogs:WaitForChild("Qualifications")),
	equipment = require(Catalogs:WaitForChild("Equipment")),
	incidents = require(Catalogs:WaitForChild("Incidents")),
	permissions = require(Catalogs:WaitForChild("Permissions")),
}

local Controllers = clientRoot:WaitForChild("Controllers")
local InterfaceController = require(Controllers:WaitForChild("InterfaceController"))
local NetworkController = require(Controllers:WaitForChild("NetworkController"))
local CameraController = require(Controllers:WaitForChild("CameraController"))
local InputController = require(Controllers:WaitForChild("InputController"))
local AudioController = require(Controllers:WaitForChild("AudioController"))
local UI = clientRoot:WaitForChild("UI")
local App = require(UI:WaitForChild("App"))
local SceneView = require(UI:WaitForChild("SceneView"))

local controller = InterfaceController.new({
	player = player,
	catalogs = catalogs,
})

-- La caméra et la vue 3D sont créées avant l'interface : la mini-carte et la
-- barre inférieure reçoivent ainsi la même caméra que les raccourcis.
local camera = CameraController.new()
camera:mount()
game:GetService("RunService"):BindToRenderStep("ERS_Camera", Enum.RenderPriority.Camera.Value + 1, function()
	camera:syncCamera(workspace.CurrentCamera)
end)
-- Les joueurs et leurs postes sont déjà accessibles dans le panneau Postes.
game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)

local scene = SceneView.new({
	workspace = workspace,
})
scene:mount()

local audio = AudioController.new({
	soundService = game:GetService("SoundService"),
	config = Config,
})
audio:mount()

local preferences = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("HudPreferences")
local app
app = App.create(playerGui, {
	saveLayout = function(layout)
		local copy = {}
		for id, settings in pairs(layout) do copy[id] = table.clone(settings) end
		task.spawn(function()
			local ok, result = pcall(function() return preferences:InvokeServer(copy) end)
			if not ok or not result.ok then app.editor.dirty = true end
			controller:toast(ok and result.message or "Sauvegarde du HUD inaccessible. Verrouillez à nouveau pour réessayer.", ok and result.ok)
		end)
	end,
	controller = controller,
	player = player,
	camera = camera,
	scene = scene,
	audio = audio,
})

controller:setRenderer(function(state: any, snapshot: any)
	app:render(state, snapshot)
end)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local network = NetworkController.new(controller, {
	command = remotes:WaitForChild("Command"),
	snapshot = remotes:WaitForChild("Snapshot"),
	feedback = remotes:WaitForChild("Feedback"),
	request = remotes:WaitForChild("RequestSnapshot"),
})
network:mount()

local input = InputController.new(controller, app, camera)
input:mount()

-- Premier rendu immédiat, puis synchronisation complète avec le serveur.
controller:render()
task.spawn(function()
	network:requestSnapshot()
	local ok, result = pcall(function() return preferences:InvokeServer() end)
	if ok and result.ok and not app.editor.touched and not app.editor.editing then
		app.editor.layout = result.layout
		controller:render()
	end
end)
