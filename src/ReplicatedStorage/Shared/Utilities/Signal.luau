--!strict
--[[
	Signal — signal minimal, sans dépendance Roblox.

	Utilisé par les contrôleurs client et par les tests. Un signal ne garde
	pas de référence forte sur ses abonnés au-delà de la connexion : l'appelant
	doit appeler `Disconnect` (ou `DisconnectAll` sur le signal).
]]

local Signal = {}
Signal.__index = Signal

export type Connection = {
	connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	connections: { { callback: (...any) -> (), connection: Connection } },
	Connect: (self: Signal, callback: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	DisconnectAll: (self: Signal) -> (),
}

function Signal.new(): Signal
	return setmetatable({
		connections = {},
	}, Signal :: any) :: Signal
end

function Signal.Connect(self: Signal, callback: (...any) -> ()): Connection
	assert(type(callback) == "function", "Signal:Connect attend une fonction")

	local connection: Connection = {
		connected = true,
		Disconnect = function() end,
	}

	table.insert(self.connections, {
		callback = callback,
		connection = connection,
	})

	connection.Disconnect = function()
		if not connection.connected then
			return
		end
		connection.connected = false
		for index, entry in ipairs(self.connections) do
			if entry.connection == connection then
				table.remove(self.connections, index)
				break
			end
		end
	end

	return connection
end

function Signal.Fire(self: Signal, ...: any): ()
	local snapshot = table.clone(self.connections)
	for _, entry in ipairs(snapshot) do
		if entry.connection.connected then
			entry.callback(...)
		end
	end
end

function Signal.DisconnectAll(self: Signal): ()
	for _, entry in ipairs(self.connections) do
		entry.connection.connected = false
	end
	table.clear(self.connections)
end

return Signal
