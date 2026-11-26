--!strict
--[[
	NetworkController — branchement des RemoteEvents sur le contrôleur.

	Le client n'écrit jamais l'état du jeu : il envoie `Command` et reçoit
	`Snapshot` / `Feedback`. Une erreur de transport devient une notification,
	jamais une exception qui casse l'interface.
]]

local NetworkController = {}

function NetworkController.new(controller: any, remotes: any): any
	local self: any = setmetatable({}, { __index = NetworkController })
	self.controller = controller
	self.remotes = remotes
	self.connections = {}
	return self
end

function NetworkController.mount(self: any): ()
	self.controller:setTransport(function(action: any, payload: any)
		return self:command(action, payload)
	end)
	self.controller:setRequester(function()
		return self:requestSnapshot()
	end)

	table.insert(self.connections, self.remotes.snapshot.OnClientEvent:Connect(function(snapshot: any)
		self.controller:applySnapshot(snapshot)
	end))
	table.insert(self.connections, self.remotes.feedback.OnClientEvent:Connect(function(result: any)
		self.controller:onFeedback(result)
	end))
end

-- Envoie une intention au serveur (RemoteEvent `Command`).
function NetworkController.command(self: any, action: string, payload: any?): boolean
	local ok, err = pcall(function()
		self.remotes.command:FireServer(action, payload)
	end)
	if not ok then
		self.controller:toast("Erreur réseau : " .. tostring(err), false)
	end
	return ok
end

-- Demande un snapshot complet (RemoteFunction `RequestSnapshot`).
function NetworkController.requestSnapshot(self: any): boolean
	local ok, snapshot = pcall(function()
		return self.remotes.request:InvokeServer()
	end)
	if not ok then
		self.controller:toast("Synchronisation impossible : " .. tostring(snapshot), false)
		return false
	end
	if type(snapshot) == "table" then
		self.controller:applySnapshot(snapshot)
		return true
	end
	return false
end

function NetworkController.unmount(self: any): ()
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return NetworkController
