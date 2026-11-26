--!strict
--[[
	Widgets — fabrique de composants d'interface.

	Toutes les créations d'Instances GUI passent par ici : les panneaux ne
	manipulent que des propriétés et des callbacks, jamais des classes Roblox
	dispersées. Les composants sont utilisables hors Studio grâce aux doublures
	de tests.

	`Widgets.list` réutilise les lignes par clé (identifiant) au lieu de tout
	reconstruire à chaque snapshot : pas de clignotement, pas de perte de
	défilement.
]]

local UI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ERSClient"):WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))

local Widgets = {}

-- Transparence de repos des boutons, pour la restaurer après réactivation.
-- Table à clés faibles : aucun champ personnalisé n'est écrit sur l'Instance.
local baseTransparency = setmetatable({}, { __mode = "k" })

local function apply(instance: any, props: any?)
	if not props then
		return
	end
	for key, value in pairs(props) do
		instance[key] = value
	end
end

function Widgets.corner(instance: any, radius: number?): any
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or Theme.radius.medium)
	corner.Parent = instance
	return corner
end

-- Cercle parfait (secteurs, pastilles).
function Widgets.circle(instance: any): any
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = instance
	return corner
end

function Widgets.stroke(instance: any, color: any, thickness: number?): any
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.colors.border
	stroke.Thickness = thickness or 1
	stroke.Parent = instance
	return stroke
end

function Widgets.padding(instance: any, all: number, extraX: number?): any
	local padding = Instance.new("UIPadding")
	local horizontal = all + (extraX or 0)
	padding.PaddingTop = UDim.new(0, all)
	padding.PaddingBottom = UDim.new(0, all)
	padding.PaddingLeft = UDim.new(0, horizontal)
	padding.PaddingRight = UDim.new(0, horizontal)
	padding.Parent = instance
	return padding
end

function Widgets.frame(parent: any, name: string, props: any?): any
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Theme.colors.surface
	frame.BackgroundTransparency = 0
	apply(frame, props)
	frame.Parent = parent
	return frame
end

function Widgets.label(parent: any, name: string, text: string, props: any?): any
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Theme.colors.text
	label.TextSize = Theme.text.body
	label.Font = Theme.fonts.body
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.RichText = false
	apply(label, props)
	label.TextSize = math.max(Theme.text.tiny, label.TextSize)
	label.Parent = parent
	return label
end

function Widgets.button(parent: any, name: string, text: string, onClick: () -> (), props: any?): any
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.TextColor3 = Theme.colors.text
	button.TextSize = Theme.text.small
	button.Font = Theme.fonts.bold
	button.BackgroundColor3 = Theme.colors.surfaceHigh
	button.BackgroundTransparency = 0
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.TextWrapped = false
	apply(button, props)
	button.TextSize = math.max(Theme.text.tiny, button.TextSize)
	button.Active = true
	baseTransparency[button] = button.BackgroundTransparency
	Widgets.corner(button, Theme.radius.small)

	button.MouseButton1Click:Connect(function()
		if not button.Active then
			return
		end
		onClick()
	end)

	button.Parent = parent
	return button
end

function Widgets.setEnabled(button: any, enabled: boolean): ()
	if button.Active == enabled then
		return
	end
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.TextTransparency = enabled and 0 or 0.5
	button.BackgroundTransparency = enabled and (baseTransparency[button] or 0) or 0.65
end

function Widgets.setSelected(instance: any, selected: boolean): ()
	instance.BackgroundColor3 = selected and Theme.colors.selection or Theme.colors.surfaceAlt
	instance.BackgroundTransparency = selected and 0.15 or 0.35
end

function Widgets.tag(parent: any, text: string, color: any): any
	local tag = Instance.new("TextLabel")
	tag.Name = "Etiquette"
	tag.Text = text
	tag.TextColor3 = Theme.colors.text
	tag.BackgroundColor3 = color
	tag.BackgroundTransparency = 0.15
	tag.TextSize = Theme.text.tiny
	tag.Font = Theme.fonts.bold
	tag.Size = UDim2.fromOffset(math.max(46, #text * 8 + 12), 18)
	tag.BorderSizePixel = 0
	Widgets.corner(tag, 9)
	tag.Parent = parent
	return tag
end

function Widgets.bar(parent: any, name: string, props: any?): any
	local track = Widgets.frame(parent, name, {
		BackgroundColor3 = Theme.colors.surfaceHigh,
		BackgroundTransparency = 0.25,
		Size = UDim2.new(1, 0, 0, 6),
	})
	Widgets.corner(track, 3)
	local fill = Widgets.frame(track, "Remplissage", {
		BackgroundColor3 = Theme.colors.success,
		Size = UDim2.fromScale(0, 1),
	})
	Widgets.corner(fill, 3)
	apply(track, props)

	return {
		root = track,
		fill = fill,
		set = function(ratio: number)
			local safe = math.clamp(ratio or 0, 0, 1)
			fill.Size = UDim2.fromScale(safe, 1)
		end,
		setColor = function(color: any)
			fill.BackgroundColor3 = color
		end,
	}
end

function Widgets.scroller(parent: any, name: string, props: any?): any
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Theme.colors.border
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ClipsDescendants = true
	apply(scroll, props)

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Parent = scroll

	scroll.Parent = parent
	return scroll
end

function Widgets.vertical(parent: any, name: string, props: any?): any
	local frame = Widgets.frame(parent, name, props)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Parent = frame
	return frame
end

function Widgets.horizontal(parent: any, name: string, props: any?): any
	local frame = Widgets.frame(parent, name, props)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = frame
	return frame
end

function Widgets.textbox(parent: any, name: string, placeholder: string, props: any?): any
	local box = Instance.new("TextBox")
	box.Name = name
	box.Text = ""
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = Theme.colors.textMuted
	box.TextColor3 = Theme.colors.text
	box.BackgroundColor3 = Theme.colors.surfaceHigh
	box.TextSize = Theme.text.small
	box.Font = Theme.fonts.body
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.ClearTextOnFocus = false
	box.BorderSizePixel = 0
	box.Size = UDim2.new(1, 0, 0, 32)
	apply(box, props)
	Widgets.corner(box, Theme.radius.small)
	box.Parent = parent
	return box
end

function Widgets.divider(parent: any): any
	local line = Widgets.frame(parent, "Separateur", {
		BackgroundColor3 = Theme.colors.border,
		BackgroundTransparency = 0.5,
		Size = UDim2.new(1, 0, 0, 1),
	})
	return line
end

-- Rangée cliquable : sert de bouton de sélection dans les listes.
function Widgets.row(parent: any, name: string, height: number, onClick: () -> ()): any
	local row = Instance.new("TextButton")
	row.Name = name
	row.Text = ""
	row.AutoButtonColor = false
	row.BorderSizePixel = 0
	row.BackgroundColor3 = Theme.colors.surfaceAlt
	row.BackgroundTransparency = 0.35
	row.Size = UDim2.new(1, 0, 0, height or Theme.sizes.row)
	row.Active = true
	Widgets.corner(row, Theme.radius.small)
	row.MouseButton1Click:Connect(function()
		if row.Active then
			onClick()
		end
	end)
	row.Parent = parent
	return row
end

function Widgets.section(parent: any, text: string): any
	return Widgets.label(parent, "Section_" .. text, string.upper(text), {
		TextColor3 = Theme.colors.textMuted,
		TextSize = Theme.text.tiny,
		Font = Theme.fonts.bold,
		Size = UDim2.new(1, 0, 0, 20),
	})
end

function Widgets.clear(container: any): ()
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function Widgets.find(root: any, name: string): any
	if root.Name == name then
		return root
	end
	for _, child in ipairs(root:GetDescendants()) do
		if child.Name == name then
			return child
		end
	end
	return nil
end

function Widgets.index(list: { any }, key: string): { [any]: any }
	local map = {}
	for _, entry in ipairs(list or {}) do
		map[entry[key]] = entry
	end
	return map
end

function Widgets.join(values: { any }, separator: string): string
	local parts = {}
	for _, value in ipairs(values or {}) do
		table.insert(parts, tostring(value))
	end
	return table.concat(parts, separator or ", ")
end

--[[
	Liste réconciliée par clé.

	keyOf(item) -> clé unique
	create(item) -> entrée (table libre, contenant au moins `instance`)
	update(entry, item, index) -> met à jour l'entrée existante

	Les entrées disparues sont détruites, les nouvelles sont créées, les autres
	sont mises à jour sur place.
]]
function Widgets.list(container: any, keyOf: (any) -> any, create: (any) -> any, update: (any, any, number) -> ()): any
	local entries = {}

	local function applyItems(items: { any })
		local seen = {}
		for index, item in ipairs(items or {}) do
			local key = keyOf(item)
			seen[key] = true
			local entry = entries[key]
			if not entry then
				entry = create(item)
				entries[key] = entry
			end
			if entry.instance then
				entry.instance.LayoutOrder = index
			end
			update(entry, item, index)
		end
		for key, entry in pairs(entries) do
			if not seen[key] then
				if entry.instance then
					entry.instance:Destroy()
				end
				entries[key] = nil
			end
		end
	end

	return {
		update = applyItems,
		entries = entries,
		clear = function()
			for key, entry in pairs(entries) do
				if entry.instance then
					entry.instance:Destroy()
				end
				entries[key] = nil
			end
		end,
	}
end

-- Poignée souris/tactile : les déplacements sont convertis en unités logiques du HUD.
function Widgets.resizeHandle(parent: any, position: any, anchor: any, direction: any, scale: () -> number, onResize: (number, number) -> ()): any
	local inputService = game:GetService("UserInputService")
	local handle = Widgets.button(parent, "Redimensionner", "↔", function() end, {
		Position = position, AnchorPoint = anchor, Size = UDim2.fromOffset(24, 20),
		ZIndex = 15, TextSize = 14,
	})
	local drag = nil
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			drag = { input = input, position = input.Position, width = parent.Size.X.Offset, height = parent.Size.Y.Offset, scale = scale() }
		end
	end)
	local changed = inputService.InputChanged:Connect(function(input)
		if not drag then return end
		local touch = drag.input.UserInputType == Enum.UserInputType.Touch
		if (touch and input ~= drag.input) or (not touch and input.UserInputType ~= Enum.UserInputType.MouseMovement) then return end
		onResize(drag.width + direction.X * (input.Position.X - drag.position.X) / drag.scale,
			drag.height + direction.Y * (input.Position.Y - drag.position.Y) / drag.scale)
	end)
	local ended = inputService.InputEnded:Connect(function(input)
		if drag and (input == drag.input or input.UserInputType == Enum.UserInputType.MouseButton1) then drag = nil end
	end)
	local focus = inputService.WindowFocusReleased:Connect(function() drag = nil end)
	handle.Destroying:Connect(function()
		changed:Disconnect()
		ended:Disconnect()
		focus:Disconnect()
	end)
	return handle
end

return Widgets
