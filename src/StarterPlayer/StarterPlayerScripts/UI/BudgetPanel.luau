--!strict
--[[
	BudgetPanel — budget, achats de véhicules et sauvegarde.

	Le panneau n'écrit jamais le budget : il affiche le solde du snapshot et
	envoie une intention `buy_vehicle` ou `save`. Le serveur vérifie le droit,
	le prix et le plafond de flotte, puis débite réellement le budget.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local Catalogs = Shared:WaitForChild("Catalogs")
local Vehicles = require(Catalogs:WaitForChild("Vehicles"))

local UI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ERSClient"):WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))

local BudgetPanel = {}

local function kindColor(kind: string): any
	if kind == Constants.LOG.SUCCESS then
		return Theme.colors.success
	elseif kind == Constants.LOG.FAILURE then
		return Theme.colors.danger
	elseif kind == Constants.LOG.MONEY then
		return Theme.colors.warning
	end
	return Theme.colors.textDim
end

function BudgetPanel.create(parent: any, context: any): any
	local controller = context.controller
	local latestSnapshot = context.snapshot or { vehicles = {}, log = {}, budget = 0 }

	local root = Widgets.frame(parent, "PanneauBudget", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	Widgets.padding(root, 10, 2)

	local title = Widgets.label(root, "Titre", "BUDGET", {
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = Theme.text.subtitle,
		Font = Theme.fonts.bold,
	})
	local balance = Widgets.label(root, "Solde", "—", {
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 34),
		TextSize = 28,
		Font = Theme.fonts.bold,
		TextColor3 = Theme.colors.success,
	})
	local summary = Widgets.label(root, "Resume", "", {
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.text.tiny,
		TextColor3 = Theme.colors.textMuted,
	})

	-- Le corps défile : catalogue et opérations dépassent la hauteur du
	-- tiroir, qui reste aligné sur la barre inférieure.
	local body = Widgets.scroller(root, "Corps", {
		Position = UDim2.fromOffset(0, 78),
		Size = UDim2.new(1, 0, 1, -78),
	})

	Widgets.section(body, "Achat de véhicule")

	local buyList = Widgets.scroller(body, "Catalogue", {
		Size = UDim2.new(1, 0, 0, 300),
	})
	local buyButtons = {}

	local buyRows = Widgets.list(buyList, function(def)
		return def.id
	end, function(def)
		local row = Widgets.frame(buyList, "Achat_" .. def.id, {
			BackgroundColor3 = Theme.colors.surfaceAlt,
			BackgroundTransparency = 0.4,
			Size = UDim2.new(1, 0, 0, 48),
		})
		Widgets.corner(row, Theme.radius.small)
		local service = Widgets.frame(row, "Service", {
			BackgroundColor3 = Theme.serviceColor[def.service] or Theme.colors.info,
			Size = UDim2.fromOffset(3, 40),
			Position = UDim2.fromOffset(0, 4),
		})
		Widgets.corner(service, 2)
		local name = Widgets.label(row, "Nom", def.name, {
			Position = UDim2.fromOffset(10, 3),
			Size = UDim2.new(1, -112, 0, 17),
			TextSize = Theme.text.tiny,
			Font = Theme.fonts.bold,
		})
		local meta = Widgets.label(row, "Meta", "", {
			Position = UDim2.fromOffset(10, 21),
			Size = UDim2.new(1, -112, 0, 14),
			TextSize = 9,
			TextColor3 = Theme.colors.textMuted,
		})
		local cost = Widgets.label(row, "Cout", Theme.money(def.cost), {
			Position = UDim2.fromOffset(10, 34),
			Size = UDim2.new(0, 90, 0, 12),
			TextSize = 9,
			TextColor3 = Theme.colors.warning,
		})
		local buy = Widgets.button(row, "Action_buy_" .. def.id, "Acheter", function()
			controller:command("buy_vehicle", { typeId = def.id })
		end, { Size = UDim2.fromOffset(74, 24), Position = UDim2.new(1, -82, 0, 12), TextSize = 10 })
		buyButtons[def.id] = buy
		return { instance = row, name = name, meta = meta, cost = cost, buy = buy }
	end, function(entry, def)
		entry.name.Text = def.name
		entry.meta.Text = string.format(
			"%s · %d place(s) · %d opérateur(s) requis",
			Theme.serviceLabel(def.service),
			def.seats,
			def.crewRequired
		)
		local snapshot = latestSnapshot
		local affordable = (snapshot.budget or 0) >= def.cost
		local underCap = #(snapshot.vehicles or {}) < Config.MAX_FLEET
		Widgets.setEnabled(entry.buy, controller:can("buy_vehicle") and affordable and underCap)
		entry.buy.Text = affordable and "Acheter" or "Fonds"
	end)

	Widgets.section(body, "Dernières opérations")

	local moneyList = Widgets.scroller(body, "Operations", {
		Size = UDim2.new(1, 0, 0, 120),
	})
	local moneyRows = Widgets.list(moneyList, function(entry)
		return entry.id or (entry.clock .. "|" .. entry.message)
	end, function(entry)
		local row = Widgets.frame(moneyList, "Operation_" .. tostring(entry.id or 0), {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 26),
		})
		local clock = Widgets.label(row, "Heure", entry.clock or "", {
			Size = UDim2.fromOffset(44, 26),
			TextSize = 9,
			Font = Theme.fonts.mono,
			TextColor3 = Theme.colors.textMuted,
		})
		local message = Widgets.label(row, "Message", entry.message, {
			Position = UDim2.fromOffset(46, 0),
			Size = UDim2.new(1, -48, 0, 26),
			TextSize = 9,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = kindColor(entry.kind),
		})
		return { instance = row, clock = clock, message = message }
	end, function(entryView, entry)
		entryView.clock.Text = entry.clock or ""
		entryView.message.Text = entry.message or ""
		entryView.message.TextColor3 = kindColor(entry.kind)
	end)

	local footer = Widgets.horizontal(body, "Pied", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
	})
	local saveButton = Widgets.button(footer, "Action_save", "Sauvegarder", function()
		controller:command("save", nil)
	end, { Size = UDim2.fromOffset(126, 32), TextSize = Theme.text.tiny })
	local footerHint = Widgets.label(footer, "Aide", "Sauvegarde serveur (DataStore ou mémoire).", {
		Size = UDim2.new(1, -132, 1, 0),
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.colors.textMuted,
	})

	local function update(snapshot: any, _state: any)
		latestSnapshot = snapshot
		buyRows.update(Vehicles.list)
		balance.Text = Theme.money(snapshot.budget or 0)
		balance.TextColor3 = (snapshot.budget or 0) >= 0 and Theme.colors.success or Theme.colors.danger
		summary.Text = string.format(
			"Dépensé %s · encaissé %s · %d véhicule(s)/%d",
			Theme.money(snapshot.spent or 0),
			Theme.money(snapshot.earned or 0),
			#(snapshot.vehicles or {}),
			Config.MAX_FLEET
		)

		local money = {}
		for _, entry in ipairs(snapshot.log or {}) do
			if entry.kind == Constants.LOG.MONEY then
				table.insert(money, entry)
				if #money >= 6 then
					break
				end
			end
		end
		moneyRows.update(money)
		Widgets.setEnabled(saveButton, controller:can("save"))
		footerHint.Text = controller:can("save")
				and "Sauvegarde serveur (DataStore ou mémoire)."
			or "Votre poste ne peut pas sauvegarder."
	end

	return {
		root = root,
		update = update,
		rows = buyRows,
		buyButtons = buyButtons,
		moneyRows = moneyRows,
		saveButton = saveButton,
	}
end

return BudgetPanel
