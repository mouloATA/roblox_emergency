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

local scene = SceneView.new({
	workspace = workspace,
})
scene:mount()

local audio = AudioController.new({
	soundService = game:GetService("SoundService"),
	config = Config,
})
audio:mount()

local app = App.create(playerGui, {
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
end)
