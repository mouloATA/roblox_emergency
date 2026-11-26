--!strict
-- Navigation et présentation communes aux achats, aux effectifs et au magasin.
local UI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ERSClient"):WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))

local ManagementNav = {}

ManagementNav.services = {
	{ "all", "Tous", 62 }, { "fire", "Incendie", 84 }, { "medical", "Secours médical", 126 },
	{ "police", "Police", 68 }, { "technical", "Technique", 92 },
	{ "command", "Commandement", 132 }, { "logistics", "Logistique", 98 },
}

-- Crée des onglets à largeur explicite, défilables horizontalement sur un petit écran.
function ManagementNav.strip(parent: any, name: string, options: any, onChange: (string) -> (), props: any): any
	local root = Widgets.scroller(parent, name, props)
	root.ScrollingDirection = Enum.ScrollingDirection.X
	root.AutomaticCanvasSize = Enum.AutomaticSize.X
	root.ScrollBarThickness = 3
	local layout = root:FindFirstChildOfClass("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 5)
	local nav = { root = root, value = options[1][1], buttons = {} }
	local markers = {}
	local function paint()
		for id, button in pairs(nav.buttons) do
			local active = nav.value == id
			button.BackgroundColor3 = active and Theme.colors.selection or Theme.colors.surfaceAlt
			button.TextColor3 = active and Theme.colors.text or Theme.colors.textDim
			markers[id].Visible = active
		end
	end
	local function select(id: string)
		if nav.value == id or not nav.buttons[id] then return end
		nav.value = id
		paint()
		onChange(id)
	end
	nav.select = select
	for index, option in ipairs(options) do
		local id = option[1]
		local button = Widgets.button(root, name .. "_" .. id, option[2], function()
			select(id)
		end, {
			Size = UDim2.new(0, option[3], 1, -5), TextSize = Theme.text.small, LayoutOrder = index,
		})
		nav.buttons[id] = button
		markers[id] = Widgets.frame(button, "Actif", {
			Position = UDim2.new(0, 6, 1, -3), Size = UDim2.new(1, -12, 0, 3),
			BackgroundColor3 = Theme.serviceColor[id] or Theme.colors.info,
		})
	end
	paint()
	return nav
end

-- Conserve l'ordre du catalogue ou de la garde dans le service demandé.
function ManagementNav.byService(items: any, service: string): any
	if service == "all" then return items end
	local result = {}
	for _, item in ipairs(items) do
		if item.service == service then table.insert(result, item) end
	end
	return result
end

-- Classe les offres du service au prix numérique. La majoration de garde est commune à toutes les offres.
function ManagementNav.priceSort(parent: any, catalog: any, services: any, list: any, onChange: () -> ()): any
	local sorted = table.clone(catalog)
	local function order(direction: string)
		table.sort(sorted, function(a, b)
			if a.cost == b.cost then return a.id < b.id end
			if direction == "desc" then return a.cost > b.cost end
			return a.cost < b.cost
		end)
	end
	order("asc")
	local options = { { "asc", "Prix croissant", 106 }, { "desc", "Prix décroissant", 124 } }
	local width = options[1][3] + options[2][3] + 5
	local control = ManagementNav.strip(parent, "TriPrix", options, function(direction)
		order(direction)
		list.CanvasPosition = Vector2.new(0, 0)
		onChange()
	end, {
		Position = UDim2.new(1, -width, 0, 42), Size = UDim2.fromOffset(width, 36),
	})
	return {
		offers = function() return ManagementNav.byService(sorted, services.value) end,
		setVisible = function(visible: boolean)
			control.root.Visible = visible
			services.root.Size = UDim2.new(1, visible and -(width + 10) or 0, 0, 36)
		end,
	}
end

-- Présente une offre avec son prix courant et une action distincte des caractéristiques.
function ManagementNav.offer(parent: any, rowId: string, actionId: string, title: string, detail: string, service: string, verb: string, action: () -> ()): any
	local row = Widgets.frame(parent, rowId, {
		BackgroundColor3 = Theme.colors.surfaceAlt, Size = UDim2.new(1, -6, 0, 64),
	})
	Widgets.corner(row, Theme.radius.medium)
	Widgets.frame(row, "Service", {
		Position = UDim2.fromOffset(0, 10), Size = UDim2.new(0, 3, 1, -20),
		BackgroundColor3 = Theme.serviceColor[service] or Theme.colors.info,
	})
	Widgets.label(row, "Nom", title, {
		Position = UDim2.fromOffset(12, 7), Size = UDim2.new(1, -132, 0, 24),
		Font = Theme.fonts.bold, TextSize = Theme.text.body, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Widgets.label(row, "Meta", detail, {
		Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -132, 0, 26),
		TextSize = Theme.text.small, TextWrapped = true, TextColor3 = Theme.colors.textDim,
	})
	local cost = Widgets.label(row, "Cout", "", {
		Position = UDim2.new(1, -118, 0, 4), Size = UDim2.fromOffset(108, 20),
		TextXAlignment = Enum.TextXAlignment.Right, Font = Theme.fonts.bold, TextColor3 = Theme.colors.text,
	})
	local button = Widgets.button(row, actionId, verb, action, {
		Position = UDim2.new(1, -118, 0, 28), Size = UDim2.fromOffset(108, 30),
		BackgroundColor3 = Theme.colors.selection,
	})
	return { instance = row, cost = cost, buy = button }
end

return ManagementNav
