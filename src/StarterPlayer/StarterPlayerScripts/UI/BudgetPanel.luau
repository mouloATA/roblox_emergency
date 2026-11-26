--!strict
-- Catalogue des véhicules et relevé des finances de la garde.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local Vehicles = require(Shared:WaitForChild("Catalogs"):WaitForChild("Vehicles"))

local UI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ERSClient"):WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))
local Nav = require(UI:WaitForChild("ManagementNav"))
local BudgetPanel = {}

-- Ouvre les achats par service et garde le solde visible pendant la consultation.
function BudgetPanel.create(parent: any, context: any): any
	local controller = context.controller
	local root = Widgets.frame(parent, "PanneauBudget", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	Widgets.padding(root, 10, 2)
	local catalogue = Widgets.scroller(root, "Catalogue", {
		Position = UDim2.fromOffset(0, 120), Size = UDim2.new(1, 0, 1, -120),
	})
	local pages = Nav.strip(root, "VueBudget", { { "shop", "Acheter un engin", 144 }, { "ledger", "Finances", 86 } },
		function() controller:render() end, { Size = UDim2.new(1, -124, 0, 38) })
	local balance = Widgets.label(root, "Solde", "", {
		Position = UDim2.new(1, -120, 0, 0), Size = UDim2.fromOffset(120, 34), Font = Theme.fonts.bold,
		TextSize = Theme.text.subtitle, TextColor3 = Theme.colors.success, TextXAlignment = Enum.TextXAlignment.Right,
	})
	local categories = Nav.strip(root, "ServiceAchat", Nav.services, function()
		catalogue.CanvasPosition = Vector2.new(0, 0)
		controller:render()
	end, { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 36) })
	local priceSort = Nav.priceSort(root, Vehicles.list, categories, catalogue, function() controller:render() end)
	local summary = Widgets.label(root, "Resume", "", {
		Position = UDim2.fromOffset(0, 82), Size = UDim2.new(1, -145, 0, 34), TextSize = Theme.text.small,
		TextColor3 = Theme.colors.textDim, TextWrapped = true,
	})
	local pass = Widgets.button(root, "Action_pass_purchase_turn", "Passer mon tour", function()
		controller:command("pass_purchase_turn", nil)
	end, { Position = UDim2.new(1, -136, 0, 82), Size = UDim2.fromOffset(136, 32) })
	local ledger = Widgets.scroller(root, "Corps", { Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -46) })
	local totals = Widgets.label(ledger, "Totaux", "", {
		Size = UDim2.new(1, -8, 0, 30), Font = Theme.fonts.bold, TextSize = Theme.text.body, LayoutOrder = 0,
	})
	local saveButton = Widgets.button(ledger, "Action_save", "Sauvegarder la garde", function()
		controller:command("save", nil)
	end, { Size = UDim2.fromOffset(186, 32), LayoutOrder = 1 })
	Widgets.section(ledger, "Dernières opérations").LayoutOrder = 2
	local empty = Widgets.label(ledger, "AucuneOperation", "Aucune opération enregistrée.", {
		Size = UDim2.new(1, -8, 0, 28), TextColor3 = Theme.colors.textMuted, LayoutOrder = 3,
	})
	local moneyRows = Widgets.list(ledger, function(event)
		return event.id or (event.clock .. "|" .. event.message)
	end, function(event)
		local line = Widgets.label(ledger, "Operation_" .. tostring(event.id or 0), "", {
			Size = UDim2.new(1, -8, 0, 32), TextSize = Theme.text.small, TextWrapped = true,
		})
		return { instance = line }
	end, function(entry, event, index)
		entry.instance.Text = (event.clock or "") .. "   " .. (event.message or "")
		entry.instance.LayoutOrder = index + 3
	end)

	local latest = context.snapshot or {}
	local rows = Widgets.list(catalogue, function(def) return def.id end, function(def)
		local detail = string.format("%s  ·  %d places  ·  Équipage requis %d", Theme.serviceLabel(def.service), def.seats, def.crewRequired)
		return Nav.offer(catalogue, "Achat_" .. def.id, "Action_buy_" .. def.id, def.id .. "  ·  " .. def.name,
			detail, def.service, "Acheter", function() controller:command("buy_vehicle", { typeId = def.id }) end)
	end, function(entry, def)
		local turn = latest.purchase or {}
		local price = def.cost + (turn.surcharge or 0)
		local reason = nil
		if not controller:can("buy_vehicle") then reason = "Poste restreint"
		elseif turn.owner ~= nil and turn.owner ~= controller.player.UserId then reason = "Hors tour"
		elseif #(latest.vehicles or {}) >= Config.MAX_FLEET then reason = "Flotte pleine"
		elseif (latest.budget or 0) < price then reason = "Solde insuffisant" end
		entry.cost.Text = Theme.money(price)
		entry.buy.Text = reason or "Acheter"
		Widgets.setEnabled(entry.buy, reason == nil)
	end)

	local function update(snapshot: any, _state: any)
		latest = snapshot
		local shopping = pages.value == "shop"
		local turn = snapshot.purchase or {}
		local multiple = (turn.count or 0) > 1
		balance.Text = Theme.money(snapshot.budget or 0)
		balance.TextColor3 = (snapshot.budget or 0) >= 0 and Theme.colors.success or Theme.colors.danger
		categories.root.Visible = shopping
		priceSort.setVisible(shopping)
		summary.Visible = shopping
		catalogue.Visible = shopping
		ledger.Visible = not shopping
		pass.Visible = shopping and multiple
		Widgets.setEnabled(pass, multiple and turn.owner == controller.player.UserId)
		if shopping then
			local offers = priceSort.offers()
			summary.Size = UDim2.new(1, multiple and -145 or 0, 0, 34)
			summary.Text = string.format("%d modèles  ·  Flotte %d/%d", #offers, #(snapshot.vehicles or {}), Config.MAX_FLEET)
			if multiple then summary.Text ..= string.format("  ·  Tour de %s (%d s)", turn.name, turn.remaining) end
			if (turn.surcharge or 0) > 0 then summary.Text ..= "  ·  Majoration " .. Theme.money(turn.surcharge) end
			rows.update(offers)
		else
			totals.Text = "Dépenses  " .. Theme.money(snapshot.spent or 0) .. "     Recettes  " .. Theme.money(snapshot.earned or 0)
			local money = {}
			for _, event in ipairs(snapshot.log or {}) do
				if event.kind == Constants.LOG.MONEY then table.insert(money, event) end
			end
			empty.Visible = #money == 0
			moneyRows.update(money)
			Widgets.setEnabled(saveButton, controller:can("save"))
		end
	end
	-- Accès depuis la flotte, dans le service de l’engin actuellement consulté.
	local function openShop(service: string?)
		pages.select("shop")
		categories.select(service or "all")
		controller:setTab("budget")
	end
	return { root = root, update = update, rows = rows, saveButton = saveButton, openShop = openShop }
end

return BudgetPanel
