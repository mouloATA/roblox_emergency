--!strict
--[[
	EquipmentPanel — stock central et chargement du matériel.

	Installer/déposer passe par `install_equipment` / `uninstall_equipment`.
	Le serveur contrôle la compatibilité de service, les emplacements, le poids
	et la disponibilité du stock.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

local UI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ERSClient"):WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))

local EquipmentPanel = {}

function EquipmentPanel.create(parent: any, context: any): any
	local controller = context.controller

	local root = Widgets.frame(parent, "PanneauMateriel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	Widgets.padding(root, 10, 2)

	local title = Widgets.label(root, "Titre", "MATÉRIEL", {
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = Theme.text.subtitle,
		Font = Theme.fonts.bold,
	})
	local subtitle = Widgets.label(root, "SousTitre", "", {
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.text.tiny,
		TextColor3 = Theme.colors.textMuted,
	})

	local target = Widgets.label(root, "Cible", "", {
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.text.tiny,
		TextColor3 = Theme.colors.info,
	})

	local listTitle = Widgets.section(root, "Stock disponible")
	listTitle.Position = UDim2.fromOffset(0, 62)

	local stockList = Widgets.scroller(root, "Stock", {
		Position = UDim2.fromOffset(0, 84),
		Size = UDim2.new(1, 0, 0.47, 4),
	})

	local installedTitle = Widgets.section(root, "Matériel de l'engin sélectionné")
	installedTitle.Position = UDim2.new(0, 0, 0.47, 88)

	local installedList = Widgets.scroller(root, "Installe", {
		Position = UDim2.new(0, 0, 0.47, 110),
		Size = UDim2.new(1, 0, 0.53, -120),
	})

	local stockRows = Widgets.list(stockList, function(entry)
		return entry.id
	end, function(entry)
		local row = Widgets.frame(stockList, "Stock_" .. entry.id, {
			BackgroundColor3 = Theme.colors.surfaceAlt,
			BackgroundTransparency = 0.4,
			Size = UDim2.new(1, 0, 0, 34),
		})
		Widgets.corner(row, Theme.radius.small)
		local name = Widgets.label(row, "Nom", entry.name, {
			Position = UDim2.fromOffset(8, 2),
			Size = UDim2.new(1, -100, 0, 16),
			TextSize = Theme.text.tiny,
		})
		local quantity = Widgets.label(row, "Quantite", "", {
			Position = UDim2.fromOffset(8, 16),
			Size = UDim2.new(0, 80, 0, 14),
			TextSize = 10,
			TextColor3 = Theme.colors.textMuted,
		})
		local install = Widgets.button(row, "Action_installer_" .. entry.id, "Installer", function()
			local vehicle = controller:selectedVehicle()
			if vehicle then
				controller:command("install_equipment", {
					vehicleId = vehicle.id,
					equipmentId = entry.id,
					quantity = 1,
				})
			end
		end, { Size = UDim2.fromOffset(66, 24), Position = UDim2.new(1, -72, 0, 5), TextSize = 10 })
		return { instance = row, name = name, quantity = quantity, install = install }
	end, function(entryView, entry)
		entryView.name.Text = entry.name
		entryView.quantity.Text = "En stock : " .. entry.quantity
		local vehicle = controller:selectedVehicle()
		Widgets.setEnabled(
			entryView.install,
			vehicle ~= nil
				and entry.quantity > 0
				and vehicle.status == Constants.VEHICLE_STATUS.AVAILABLE
				and controller:can("equipment")
				and controller:canService(vehicle.service)
		)
	end)

	local installedRows = Widgets.list(installedList, function(entry)
		return entry.id
	end, function(entry)
		local row = Widgets.frame(installedList, "Embarque_" .. entry.id, {
			BackgroundColor3 = Theme.colors.surfaceAlt,
			BackgroundTransparency = 0.4,
			Size = UDim2.new(1, 0, 0, 30),
		})
		Widgets.corner(row, Theme.radius.small)
		local name = Widgets.label(row, "Nom", entry.name, {
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.new(1, -110, 1, 0),
			TextSize = Theme.text.tiny,
		})
		local quantity = Widgets.label(row, "Quantite", "", {
			Position = UDim2.new(1, -100, 0, 0),
			Size = UDim2.fromOffset(30, 30),
			TextSize = 10,
			TextColor3 = Theme.colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		local remove = Widgets.button(row, "Action_deposer_" .. entry.id, "Déposer", function()
			local vehicle = controller:selectedVehicle()
			if vehicle then
				controller:command("uninstall_equipment", {
					vehicleId = vehicle.id,
					equipmentId = entry.id,
					quantity = 1,
				})
			end
		end, { Size = UDim2.fromOffset(60, 22), Position = UDim2.new(1, -66, 0, 4), TextSize = 10 })
		return { instance = row, name = name, quantity = quantity, remove = remove }
	end, function(entryView, entry)
		entryView.name.Text = entry.name
		entryView.quantity.Text = "×" .. entry.quantity
		local vehicle = controller:selectedVehicle()
		Widgets.setEnabled(entryView.remove, vehicle ~= nil
			and vehicle.status == Constants.VEHICLE_STATUS.AVAILABLE
			and controller:can("equipment")
			and controller:canService(vehicle.service))
	end)

	local function update(snapshot: any, _state: any)
		stockRows.update(snapshot.stock or {})
		local vehicle = controller:selectedVehicle()
		if vehicle then
			target.Text = string.format("Destination : %s (%d emplacements)", vehicle.callsign, #vehicle.equipment)
			installedRows.update(vehicle.equipment or {})
		else
			target.Text = "Sélectionnez un véhicule au poste pour charger du matériel."
			installedRows.update({})
		end
		local total = 0
		for _, entry in ipairs(snapshot.stock or {}) do
			total += entry.quantity
		end
		subtitle.Text = string.format("%d référence(s) · %d unité(s) en stock", #(snapshot.stock or {}), total)
	end

	return { root = root, update = update, stock = stockRows }
end

return EquipmentPanel
