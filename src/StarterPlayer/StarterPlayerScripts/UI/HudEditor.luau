--!strict
-- Éditeur local des positions relatives et de l'échelle des panneaux.
local UI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ERSClient"):WaitForChild("UI")
local Widgets = require(UI:WaitForChild("Widgets"))
local Theme = require(UI:WaitForChild("Theme"))
local HudEditor = {}
local labels = { map = "Carte tactique", journal = "Journal", navigation = "Navigation", radio = "Radio",
	commands = "Commandes", panel = "Panneau ouvert", notifications = "Notifications" }

-- Monte les poignées au-dessus des panneaux pendant la personnalisation.
function HudEditor.new(root: any, panels: any, controller: any): any
	local self: any = { editing = false, layout = {}, entries = {}, width = 1, height = 1, zoom = 1, dirty = false, touched = false }
	local inputs = game:GetService("UserInputService")
	local drag = nil
	for id, panel in pairs(panels) do
		local scale = Instance.new("UIScale")
		scale.Name, scale.Scale, scale.Parent = "Personnalisation", 1, panel
		local overlay = Widgets.frame(root, "Edition_" .. id, {
			BackgroundTransparency = 0.85, BackgroundColor3 = Theme.colors.info, ZIndex = 80, Visible = false,
		})
		Widgets.stroke(overlay, Theme.colors.info, 2)
		local move = Widgets.button(overlay, "Deplacer", labels[id] .. " · Déplacer", function() end, {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.9, TextColor3 = Theme.colors.text,
		})
		local resize = Widgets.button(overlay, "Taille", "↘", function() end, {
			Position = UDim2.fromScale(1, 1), AnchorPoint = Vector2.new(1, 1), Size = UDim2.fromOffset(28, 28), ZIndex = 2,
		})
		local entry = { panel = panel, scale = scale, overlay = overlay }
		self.entries[id] = entry
		local function begin(input, resizing)
			if not self.editing then return end
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
			drag = { id = id, input = input, point = input.Position, resizing = resizing,
				x = entry.x, y = entry.y, w = entry.w, h = entry.h, scale = scale.Scale }
		end
		move.InputBegan:Connect(function(input) begin(input, false) end)
		resize.InputBegan:Connect(function(input) begin(input, true) end)
	end
	local changed = inputs.InputChanged:Connect(function(input)
		if not drag or not self.editing then return end
		local touch = drag.input.UserInputType == Enum.UserInputType.Touch
		if touch and input ~= drag.input or not touch and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
		local dx, dy = (input.Position.X - drag.point.X) / self.zoom, (input.Position.Y - drag.point.Y) / self.zoom
		local x, y, scale = drag.x, drag.y, drag.scale
		if drag.resizing then
			scale = math.clamp(drag.scale * math.max((drag.w + dx) / drag.w, (drag.h + dy) / drag.h), 0.65, 1.75)
		else
			x, y = x + dx, y + dy
		end
		self.layout[drag.id] = { x = math.clamp(x / self.width, 0, 1), y = math.clamp(y / self.height, 0, 1), scale = scale }
		self.dirty = true
		self.touched = true
		controller:render()
	end)
	local ended = inputs.InputEnded:Connect(function(input)
		if drag and (input == drag.input or input.UserInputType == Enum.UserInputType.MouseButton1) then drag = nil end
	end)
	local focus = inputs.WindowFocusReleased:Connect(function() drag = nil end)
	root.Destroying:Connect(function() changed:Disconnect() ended:Disconnect() focus:Disconnect() end)

	-- Retrouve les coordonnées automatiques avant chaque recalcul du HUD.
	function self:restore()
		for _, entry in pairs(self.entries) do
			if entry.base then
				entry.panel.Position = entry.base.position
				entry.panel.AnchorPoint = entry.base.anchor
			end
			entry.scale.Scale = 1
		end
	end

	-- Borne chaque panneau à l'écran, même après un changement de résolution.
	function self:apply(width: number, height: number, zoom: number)
		if not self.editing then drag = nil end
		self.width, self.height, self.zoom = width, height, zoom
		for id, entry in pairs(self.entries) do
			local panel = entry.panel
			entry.base = { position = panel.Position, anchor = panel.AnchorPoint }
			local w = panel.Size.X.Scale * width + panel.Size.X.Offset
			local h = panel.Size.Y.Scale * height + panel.Size.Y.Offset
			local config = self.layout[id]
			local scale = config and math.min(config.scale, width / math.max(1,w), height / math.max(1,h)) or 1
			local x = panel.Position.X.Scale * width + panel.Position.X.Offset - panel.AnchorPoint.X * w
			local y = panel.Position.Y.Scale * height + panel.Position.Y.Offset - panel.AnchorPoint.Y * h
			if config then
				x = math.clamp(config.x * width, 0, math.max(0,width-w*scale))
				y = math.clamp(config.y * height, 0, math.max(0,height-h*scale))
				panel.AnchorPoint = Vector2.new(0,0)
				panel.Position = UDim2.fromOffset(x,y)
				entry.scale.Scale = scale
			end
			entry.x, entry.y, entry.w, entry.h = x, y, w*scale, h*scale
			entry.overlay.Position = UDim2.fromOffset(x,y)
			entry.overlay.Size = UDim2.fromOffset(w*scale,h*scale)
			entry.overlay.Visible = self.editing and panel.Visible
			local oldHandle = panel:FindFirstChild("Redimensionner")
			if oldHandle then oldHandle.Visible = self.editing end
		end
	end

	-- Rétablit la disposition automatique et abandonne le geste en cours.
	function self:reset()
		self.layout = {}
		self.dirty = true
		self.touched = true
		drag = nil
		controller:render()
	end
	return self
end

return HudEditor
