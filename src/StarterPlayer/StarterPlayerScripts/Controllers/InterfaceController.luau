--!strict
--[[
	InterfaceController — état de l'interface et intentions client.

	Il ne calcule aucun résultat de jeu : il conserve l'état local (onglet,
	sélection, menu, notifications), lit le dernier snapshot serveur et envoie
	des intentions via le transport réseau. Les permissions affichées ici ne
	remplacent jamais celles du serveur : elles évitent seulement les clics
	manifestement voués au refus.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local Catalogs = Shared:WaitForChild("Catalogs")
local Permissions = require(Catalogs:WaitForChild("Permissions"))

local Controller = {}

local VALID_TABS = {
	incidents = true,
	vehicles = true,
	personnel = true,
	equipment = true,
	command = true,
	budget = true,
	roles = true,
	missions = true,
}

local function emptySnapshot(): any
	return {
		version = Config.VERSION,
		time = 0,
		timeScale = 1,
		paused = false,
		clock = string.format("%02d:00", Config.SHIFT_START_HOUR),
		budget = Config.START_BUDGET,
		spent = 0,
		earned = 0,
		finished = false,
		players = {},
		vehicles = {},
		personnel = {},
		incidents = {},
		groups = {},
		sectors = {},
		stock = {},
		log = {},
		stats = {},
		alerts = 0,
	}
end

local function findById(list: { any }?, key: string, id: any): any
	for _, entry in ipairs(list or {}) do
		if entry[key] == id then
			return entry
		end
	end
	return nil
end

--[[
	Crée un contrôleur.

	options.player     : joueur local (UserId utilisé dans les snapshots)
	options.transport  : function(action, payload) envoyant l'intention au serveur
	options.requester  : function() demandant un snapshot complet
	options.snapshot   : snapshot initial (facultatif)
]]
function Controller.new(options: any?): any
	local opts = options or {}
	local self: any = setmetatable({}, { __index = Controller })

	self.player = opts.player or game:GetService("Players").LocalPlayer
	self.config = opts.config or Config
	self.constants = opts.constants or Constants
	self.permissions = opts.permissions or Permissions
	self.catalogs = opts.catalogs

	self.snapshot = opts.snapshot or emptySnapshot()
	self.state = {
		tab = "incidents",
		vehicleId = nil,
		incidentId = nil,
		personId = nil,
		groupId = nil,
		userId = nil,
		menuOpen = true,
		-- Tiroir de la barre inférieure : "none", "vehicles" ou "panel".
		drawer = "none",
		category = "all",
		groupSlot = nil,
		layers = {
			units = true,
			incidents = true,
			sectors = true,
			buildings = true,
		},
	}
	self.toasts = {}
	self.nextToastId = 1
	self.renderer = nil
	self.transport = opts.transport
	self.requester = opts.requester
	return self
end

function Controller.setRenderer(self: any, renderer: any): ()
	self.renderer = renderer
	self:render()
end

function Controller.setTransport(self: any, transport: any): ()
	self.transport = transport
end

function Controller.setRequester(self: any, requester: any): ()
	self.requester = requester
end

function Controller.render(self: any): ()
	if self.renderer then
		self.renderer(self.state, self.snapshot)
	end
end

-- Envoie une intention. Le serveur reste seul juge de son acceptation.
function Controller.command(self: any, action: string, payload: any?): boolean
	if not self.transport then
		self:toast("Réseau non initialisé : action impossible.", false)
		return false
	end
	local ok, err = pcall(self.transport, action, payload)
	if not ok then
		self:toast("Erreur d'envoi : " .. tostring(err), false)
		return false
	end
	return true
end

function Controller.send(self: any, action: string, payload: any?): boolean
	return self:command(action, payload)
end

function Controller.requestSnapshot(self: any): boolean
	if not self.requester then
		return false
	end
	local ok, err = pcall(self.requester)
	if not ok then
		self:toast("Synchronisation impossible : " .. tostring(err), false)
		return false
	end
	return true
end

-- Poste du joueur local tel que publié par le serveur.
function Controller.role(self: any): string
	local me = findById(self.snapshot.players, "userId", self.player.UserId)
	return me and me.role or Constants.ROLE.OBSERVATEUR
end

function Controller.can(self: any, action: string): boolean
	return self.permissions.can(self:role(), action)
end

function Controller.canService(self: any, service: string): boolean
	return self.permissions.canService(self:role(), service)
end

function Controller.isSelf(self: any, userId: any): boolean
	return userId ~= nil and self.player ~= nil and userId == self.player.UserId
end

function Controller.select(self: any, kind: string, id: any, focus: boolean?): ()
	if kind == "vehicle" then
		self.state.vehicleId = id
	elseif kind == "incident" then
		self.state.incidentId = id
	elseif kind == "person" then
		self.state.personId = id
	elseif kind == "group" then
		self.state.groupId = id
	elseif kind == "user" then
		self.state.userId = id
	end
	if focus then
		if kind == "vehicle" then
			self.state.tab = "vehicles"
		elseif kind == "incident" then
			self.state.tab = "incidents"
		end
		self.state.drawer = "panel"
	end
	self:render()
end

function Controller.setTab(self: any, tab: string): ()
	if VALID_TABS[tab] then
		self.state.tab = tab
		self.state.drawer = "panel"
		self:render()
	end
end

-- Catégorie de véhicules : ouvre le tiroir filtré sur un service.
function Controller.openCategory(self: any, service: string?): ()
	self.state.category = service or "all"
	self.state.drawer = "vehicles"
	self:render()
end

function Controller.closeDrawer(self: any): ()
	self.state.drawer = "none"
	self:render()
end

function Controller.toggleDrawer(self: any, mode: string): ()
	if mode == "vehicles" or mode == "panel" then
		self.state.drawer = self.state.drawer == mode and "none" or mode
		self:render()
	end
end

-- Couches d'information de la mini-carte.
function Controller.toggleLayer(self: any, layer: string): ()
	if self.state.layers[layer] ~= nil then
		self.state.layers[layer] = not self.state.layers[layer]
		self:render()
	end
end

-- Boutons de groupe 1..6 : sélectionnent le n-ième groupe existant.
function Controller.selectGroupSlot(self: any, slot: number): boolean
	local groups = {}
	for _, group in ipairs(self.snapshot.groups or {}) do
		table.insert(groups, group)
	end
	table.sort(groups, function(a, b)
		return a.id < b.id
	end)
	local group = groups[slot]
	if not group then
		self.state.groupSlot = nil
		self:toast(string.format("Aucun groupe en position %d.", slot), false)
		return false
	end
	self.state.groupSlot = slot
	self.state.groupId = group.id
	self:render()
	return true
end

-- Demande une vitesse de simulation au serveur (il reste seul juge).
function Controller.setTimeScale(self: any, scale: number): boolean
	if not self:can("set_time") then
		self:toast("Votre poste ne peut pas régler le temps.", false)
		return false
	end
	return self:command("set_time_scale", { scale = scale })
end

function Controller.setMenu(self: any, open: boolean): ()
	self.state.menuOpen = open == true
	self:render()
end

function Controller.selectedVehicle(self: any): any
	return findById(self.snapshot.vehicles, "id", self.state.vehicleId)
end

function Controller.selectedIncident(self: any): any
	return findById(self.snapshot.incidents, "id", self.state.incidentId)
end

function Controller.selectedPerson(self: any): any
	return findById(self.snapshot.personnel, "id", self.state.personId)
end

function Controller.selectedGroup(self: any): any
	return findById(self.snapshot.groups, "id", self.state.groupId)
end

function Controller.selectedUser(self: any): any
	return findById(self.snapshot.players, "userId", self.state.userId)
end

function Controller.applySnapshot(self: any, snapshot: any): ()
	if type(snapshot) ~= "table" then
		return
	end
	self.snapshot = snapshot

	if self.state.vehicleId and not findById(snapshot.vehicles, "id", self.state.vehicleId) then
		self.state.vehicleId = nil
	end
	if self.state.incidentId and not findById(snapshot.incidents, "id", self.state.incidentId) then
		self.state.incidentId = nil
	end
	if self.state.personId and not findById(snapshot.personnel, "id", self.state.personId) then
		self.state.personId = nil
	end
	if self.state.groupId and not findById(snapshot.groups, "id", self.state.groupId) then
		self.state.groupId = nil
		self.state.groupSlot = nil
	end
	if self.state.userId and not findById(snapshot.players, "userId", self.state.userId) then
		self.state.userId = nil
	end

	self:render()
end

-- Notification locale (retour serveur, erreur réseau, conseil).
-- Elle se retire d'elle-même après huit secondes pour ne pas masquer la carte.
function Controller.toast(self: any, message: string, ok: boolean?): ()
	while #self.toasts >= 3 do
		table.remove(self.toasts, 1)
	end
	local id = self.nextToastId
	table.insert(self.toasts, {
		id = id,
		message = message,
		ok = ok ~= false,
	})
	self.nextToastId += 1
	self:render()
	task.delay(8, function()
		self:dismissToast(id)
	end)
end

function Controller.dismissToast(self: any, id: any): ()
	for index, toast in ipairs(self.toasts) do
		if toast.id == id then
			table.remove(self.toasts, index)
			break
		end
	end
	self:render()
end

function Controller.clearToasts(self: any): ()
	table.clear(self.toasts)
	self:render()
end

-- Retour du serveur : affiche le message réel, sans le réécrire.
function Controller.onFeedback(self: any, result: any): ()
	if type(result) ~= "table" then
		return
	end
	local message = result.message
	if type(message) ~= "string" or #message == 0 then
		message = result.ok and "Action appliquée." or "Action refusée."
	end
	self:toast(message, result.ok == true)
end

return Controller
