--!strict
--[[
	NetworkService — frontière réseau et validation des intentions (spec §2.2).

	Toute action client passe par `handle`, qui :
	1. identifie l'acteur côté serveur (Player.UserId) ;
	2. valide la forme de la charge utile ;
	3. applique un anti-spam ;
	4. délègue au service métier, qui revérifie les permissions et l'état.

	Le client ne peut donc jamais écrire directement le budget, les effectifs ou
	le résultat d'une intervention.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Utilities = Shared:WaitForChild("Utilities")
local Constants = require(Shared:WaitForChild("Constants"))
local Result = require(Utilities:WaitForChild("Result"))

local ServerScript = game:GetService("ServerScriptService"):WaitForChild("ERS")
local Services = ServerScript:WaitForChild("Services")
local PermissionService = require(Services:WaitForChild("PermissionService"))
local PersonnelService = require(Services:WaitForChild("PersonnelService"))
local EquipmentService = require(Services:WaitForChild("EquipmentService"))
local VehicleService = require(Services:WaitForChild("VehicleService"))
local DispatchService = require(Services:WaitForChild("DispatchService"))
local CommandService = require(Services:WaitForChild("CommandService"))
local SimulationService = require(Services:WaitForChild("SimulationService"))
local SnapshotService = require(Services:WaitForChild("SnapshotService"))
local WorldService = require(Services:WaitForChild("WorldService"))

local NetworkService = {}

local function isId(value: any): boolean
	return type(value) == "number" and value > 0 and value % 1 == 0 and value < 1e9
end

local function isIncidentId(value: any): boolean
	return type(value) == "string" and #value >= 1 and #value <= 16
end

local function isText(value: any, maximum: number): boolean
	return type(value) == "string" and #value >= 1 and #value <= maximum
end

local function isCount(value: any, minimum: number, maximum: number): boolean
	return type(value) == "number" and value % 1 == 0 and value >= minimum and value <= maximum
end

--[[
	Extrait l'identité de l'acteur.

	Dans Roblox, un joueur est une Instance (`typeof(...) == "Instance"`), pas
	une table : une validation `type(player) == "table"` refuserait tous les
	vrais joueurs. Les tables restent acceptées pour les tests hors Studio.
]]
local function identityOf(player: any): (number?, string?)
	if player == nil then
		return nil, nil
	end
	if typeof(player) == "Instance" then
		if not player:IsA("Player") then
			return nil, nil
		end
	elseif type(player) ~= "table" then
		return nil, nil
	end

	local okId, userId = pcall(function()
		return player.UserId
	end)
	local okName, name = pcall(function()
		return player.Name
	end)
	if not okId or not okName then
		return nil, nil
	end
	if type(userId) ~= "number" or type(name) ~= "string" then
		return nil, nil
	end
	return userId, name
end

local handlers = {}

handlers.dispatch = function(world: any, userId: number, payload: any): any
	if not isId(payload.vehicleId) then
		return Result.err("Identifiant de véhicule invalide.")
	end
	if not isIncidentId(payload.incidentId) then
		return Result.err("Identifiant d'intervention invalide.")
	end
	return DispatchService.dispatch(world, userId, payload.vehicleId, payload.incidentId)
end

handlers.recall = function(world: any, userId: number, payload: any): any
	if not isId(payload.vehicleId) then
		return Result.err("Identifiant de véhicule invalide.")
	end
	return DispatchService.recall(world, userId, payload.vehicleId)
end

handlers.auto_crew = function(world: any, userId: number, payload: any): any
	if not isId(payload.vehicleId) then
		return Result.err("Identifiant de véhicule invalide.")
	end
	return PersonnelService.autoCrew(world, userId, payload.vehicleId)
end

handlers.assign_personnel = function(world: any, userId: number, payload: any): any
	if not isId(payload.personId) or not isId(payload.vehicleId) then
		return Result.err("Identifiants invalides.")
	end
	return PersonnelService.assign(world, userId, payload.personId, payload.vehicleId)
end

handlers.unassign_personnel = function(world: any, userId: number, payload: any): any
	if not isId(payload.personId) then
		return Result.err("Identifiant de membre invalide.")
	end
	return PersonnelService.unassign(world, userId, payload.personId)
end

handlers.install_equipment = function(world: any, userId: number, payload: any): any
	if not isId(payload.vehicleId) or not isText(payload.equipmentId, 32) then
		return Result.err("Paramètres invalides.")
	end
	if not isCount(payload.quantity, 1, 99) then
		return Result.err("Quantité invalide.")
	end
	return EquipmentService.install(world, userId, payload.vehicleId, payload.equipmentId, payload.quantity)
end

handlers.uninstall_equipment = function(world: any, userId: number, payload: any): any
	if not isId(payload.vehicleId) or not isText(payload.equipmentId, 32) then
		return Result.err("Paramètres invalides.")
	end
	if not isCount(payload.quantity, 1, 99) then
		return Result.err("Quantité invalide.")
	end
	return EquipmentService.uninstall(world, userId, payload.vehicleId, payload.equipmentId, payload.quantity)
end

handlers.buy_vehicle = function(world: any, userId: number, payload: any): any
	if not isText(payload.typeId, 32) then
		return Result.err("Type de véhicule invalide.")
	end
	return VehicleService.buy(world, userId, payload.typeId)
end

handlers.repair_vehicle = function(world: any, userId: number, payload: any): any
	if not isId(payload.vehicleId) then
		return Result.err("Identifiant de véhicule invalide.")
	end
	return VehicleService.repair(world, userId, payload.vehicleId)
end

handlers.create_group = function(world: any, userId: number, payload: any): any
	if not isText(payload.name, world.config.MAX_COMMAND_LENGTH) then
		return Result.err("Nom de groupe invalide.")
	end
	return CommandService.createGroup(world, userId, payload.name, payload.service)
end

handlers.add_to_group = function(world: any, userId: number, payload: any): any
	if not isId(payload.groupId) or not isId(payload.vehicleId) then
		return Result.err("Identifiants invalides.")
	end
	return CommandService.addUnit(world, userId, payload.groupId, payload.vehicleId)
end

handlers.remove_from_group = function(world: any, userId: number, payload: any): any
	if not isId(payload.groupId) or not isId(payload.vehicleId) then
		return Result.err("Identifiants invalides.")
	end
	return CommandService.removeUnit(world, userId, payload.groupId, payload.vehicleId)
end

handlers.dissolve_group = function(world: any, userId: number, payload: any): any
	if not isId(payload.groupId) then
		return Result.err("Identifiant de groupe invalide.")
	end
	return CommandService.dissolve(world, userId, payload.groupId)
end

handlers.dispatch_group = function(world: any, userId: number, payload: any): any
	if not isId(payload.groupId) or not isIncidentId(payload.incidentId) then
		return Result.err("Paramètres invalides.")
	end
	return CommandService.dispatchGroup(world, userId, payload.groupId, payload.incidentId)
end

handlers.create_sector = function(world: any, userId: number, payload: any): any
	if not isText(payload.name, world.config.MAX_COMMAND_LENGTH) then
		return Result.err("Nom de secteur invalide.")
	end
	if type(payload.x) ~= "number" or type(payload.z) ~= "number" or type(payload.radius) ~= "number" then
		return Result.err("Coordonnées invalides.")
	end
	return CommandService.createSector(world, userId, payload.name, payload.x, payload.z, payload.radius)
end

handlers.assign_group_sector = function(world: any, userId: number, payload: any): any
	if not isId(payload.sectorId) or not isId(payload.groupId) then
		return Result.err("Identifiants invalides.")
	end
	return CommandService.assignGroupToSector(world, userId, payload.sectorId, payload.groupId)
end

handlers.claim_role = function(world: any, userId: number, payload: any): any
	if not isText(payload.role, 32) then
		return Result.err("Poste invalide.")
	end
	return PermissionService.claim(world, userId, payload.role)
end

handlers.assign_role = function(world: any, userId: number, payload: any): any
	if not isId(payload.userId) or not isText(payload.role, 32) then
		return Result.err("Paramètres invalides.")
	end
	return PermissionService.assignRole(world, userId, payload.userId, payload.role)
end

handlers.save = function(world: any, userId: number, _payload: any): any
	local check = PermissionService.require(world, userId, Constants.ACTION.SAVE)
	if not check.ok then
		return check
	end
	world.saveRequested = true
	return Result.ok("Sauvegarde demandée.")
end

-- Vitesse de simulation : le serveur seul décide de l'accepter.
handlers.set_time_scale = function(world: any, userId: number, payload: any): any
	if type(payload.scale) ~= "number" then
		return Result.err("Vitesse invalide.")
	end
	return SimulationService.setTimeScale(world, userId, payload.scale)
end

--[[
	Nouvelle partie : réservée à la direction.

	Le monde est remis dans son état de départ, les postes en ligne sont
	conservés et la prochaine sauvegarde remplace l'ancienne progression.
]]
handlers.new_game = function(world: any, userId: number, _payload: any): any
	local check = PermissionService.require(world, userId, Constants.ACTION.NEW_GAME)
	if not check.ok then
		return check
	end
	WorldService.reset(world)
	return Result.ok("Nouvelle partie : budget, parc et effectif réinitialisés.")
end

handlers.request_snapshot = function(_world: any, _userId: number, _payload: any): any
	return Result.ok("Snapshot demandé.")
end

NetworkService.actions = handlers

-- Point d'entrée unique des commandes client.
function NetworkService.handle(world: any, player: any, action: any, payload: any): any
	local userId, playerName = identityOf(player)
	if not userId or not playerName then
		return Result.err("Joueur invalide.")
	end
	if type(action) ~= "string" then
		return Result.err("Action invalide.")
	end
	if payload ~= nil and type(payload) ~= "table" then
		return Result.err("Charge utile invalide.")
	end

	if world.players[userId] == nil then
		PermissionService.seed(world, userId, playerName)
	end

	local record = world.players[userId]
	if record and world.config.ACTION_COOLDOWN > 0 then
		local now = os.clock()
		if record.lastAction and now - record.lastAction < world.config.ACTION_COOLDOWN then
			return Result.err("Trop d'actions en peu de temps.")
		end
		record.lastAction = now
	end

	local handler = handlers[action]
	if not handler then
		return Result.err("Action inconnue.")
	end

	local ok, result = pcall(handler, world, userId, payload or {})
	if not ok then
		return Result.err("Erreur interne : " .. tostring(result))
	end
	if type(result) ~= "table" or type(result.ok) ~= "boolean" then
		return Result.err("Réponse interne invalide.")
	end
	return result
end

-- Crée (ou réutilise) les objets réseau dans ReplicatedStorage.Remotes.
function NetworkService.createRemotes(parent: any): any
	local folder = parent:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = parent
	end

	local function ensure(className: string, name: string): any
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing
		end
		local instance = Instance.new(className)
		instance.Name = name
		instance.Parent = folder
		return instance
	end

	return {
		folder = folder,
		command = ensure("RemoteEvent", "Command"),
		snapshot = ensure("RemoteEvent", "Snapshot"),
		feedback = ensure("RemoteEvent", "Feedback"),
		request = ensure("RemoteFunction", "RequestSnapshot"),
	}
end

-- Branche les événements réseau sur un monde. Retourne les fonctions de push.
function NetworkService.mount(world: any, remotes: any): any
	local Players = game:GetService("Players")

	local function sendSnapshot(player: any): ()
		remotes.snapshot:FireClient(player, SnapshotService.build(world))
	end

	local function broadcast(): ()
		remotes.snapshot:FireAllClients(SnapshotService.build(world))
	end

	Players.PlayerAdded:Connect(function(player: any)
		local seeded = PermissionService.seed(world, player.UserId, player.Name)
		world.players[player.UserId].connected = true
		world.players[player.UserId].lastAction = -math.huge
		remotes.feedback:FireClient(player, Result.ok(
			string.format("Bienvenue au centre 112, %s. Poste : %s.", player.Name, seeded.data and seeded.data.role or "observateur")
		))
		sendSnapshot(player)
	end)

	Players.PlayerRemoving:Connect(function(player: any)
		local record = world.players[player.UserId]
		if record then
			record.connected = false
		end
	end)

	remotes.command.OnServerEvent:Connect(function(player: any, action: any, payload: any)
		local result = NetworkService.handle(world, player, action, payload)
		remotes.feedback:FireClient(player, result)
		if result.ok then
			sendSnapshot(player)
		end
	end)

	remotes.request.OnServerInvoke = function(player: any): any
		if world.players[player.UserId] == nil then
			PermissionService.seed(world, player.UserId, player.Name)
		end
		return SnapshotService.build(world)
	end

	return {
		sendSnapshot = sendSnapshot,
		broadcast = broadcast,
	}
end

return NetworkService
