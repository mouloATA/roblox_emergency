--!strict
-- Préférences d'interface personnelles, indépendantes de la sauvegarde de la garde.
local HudPreferenceService = {}
local allowed = { map = true, journal = true, navigation = true, radio = true, commands = true, panel = true, notifications = true }

-- Accepte uniquement les panneaux connus et des coordonnées finies et bornées.
function HudPreferenceService.validate(value: any): any?
	if type(value) ~= "table" then return nil end
	local result = {}
	for id, panel in pairs(value) do
		if not allowed[id] or type(panel) ~= "table" then return nil end
		for key, number in pairs(panel) do
			if key ~= "x" and key ~= "y" and key ~= "scale" then return nil end
			if type(number) ~= "number" or number ~= number then return nil end
		end
		if type(panel.x) ~= "number" or type(panel.y) ~= "number" or type(panel.scale) ~= "number" then return nil end
		if panel.x < 0 or panel.x > 1 or panel.y < 0 or panel.y > 1 or panel.scale < 0.65 or panel.scale > 1.75 then return nil end
		result[id] = { x = panel.x, y = panel.y, scale = panel.scale }
	end
	return result
end

-- Crée un gestionnaire testable. La clé vient toujours du joueur authentifié.
function HudPreferenceService.new(store: any): any
	local cache, busy, lastWrite = {}, {}, {}
	return function(player: any, layout: any): any
		local id = player.UserId
		if busy[id] then return { ok = false, message = "Sauvegarde du HUD en cours." } end
		local clean = nil
		if layout ~= nil then
			clean = HudPreferenceService.validate(layout)
			if not clean then return { ok = false, message = "Disposition du HUD invalide." } end
			if os.clock() - (lastWrite[id] or -math.huge) < 2 then
				return { ok = false, message = "Patientez deux secondes puis verrouillez à nouveau le HUD." }
			end
			lastWrite[id] = os.clock()
		end
		busy[id] = true
		local ok = true
		if clean then
			cache[id] = clean
			ok = store ~= nil and pcall(function() store:SetAsync(tostring(id), clean) end)
		elseif cache[id] == nil then
			local loaded
			ok = store ~= nil and pcall(function() loaded = store:GetAsync(tostring(id)) end)
			cache[id] = HudPreferenceService.validate(loaded) or {}
		end
		busy[id] = nil
		return { ok = true, persistent = ok, layout = cache[id],
			message = ok and "Disposition du HUD enregistrée." or "HUD conservé pour cette session. Sauvegarde persistante indisponible." }
	end
end

-- Monte la préférence avec un repli en mémoire quand Studio refuse les DataStores.
function HudPreferenceService.mount(parent: any): ()
	local remote = Instance.new("RemoteFunction")
	remote.Name = "HudPreferences"
	local ok, store = pcall(function()
		return game:GetService("DataStoreService"):GetDataStore("ERS_HudPreferences_v1")
	end)
	remote.OnServerInvoke = HudPreferenceService.new(ok and store or nil)
	remote.Parent = parent
end

return HudPreferenceService
