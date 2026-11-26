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

local Nav = require(UI:WaitForChild("ManagementNav"))
local Catalogs = Shared:WaitForChild("Catalogs")
local Equipment = require(Catalogs:WaitForChild("Equipment"))
local Vehicles = require(Catalogs:WaitForChild("Vehicles"))
local EquipmentPanel = {}
local families = {
	{ "all", "Tout", 60 }, { "fire", "Incendie", 84 }, { "rescue", "Sauvetage", 96 },
	{ "medical", "Médical", 78 }, { "support", "Appui", 68 }, { "security", "Sécurité", 84 },
}
local familyOf = {
	protection = "fire", extinction = "fire", extrication = "rescue", rescue = "rescue", medical = "medical",
	recon = "support", radio = "support", command = "support", logistics = "support", intervention = "security",
}

-- Relie le magasin, le chargement et le choix de l’engin à la sélection tactique.
function EquipmentPanel.create(parent: any, context: any): any
	local controller = context.controller

	local root = Widgets.frame(parent, "PanneauMateriel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	Widgets.padding(root, 10, 2)

	local pages
	local previous = "stock"
	local body = Widgets.frame(root, "Inventaire", {
		BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 88), Size = UDim2.new(1, 0, 1, -88),
	})
	local stockList = Widgets.scroller(body, "Stock", { Size = UDim2.fromScale(1, 1) })
	local installedList = Widgets.scroller(body, "Installe", { Size = UDim2.fromScale(1, 1) })
	local fleet = Widgets.scroller(body, "Engins", { Size = UDim2.fromScale(1, 1) })
	local familiesNav = Nav.strip(root, "FamilleMateriel", families, function()
		stockList.CanvasPosition = Vector2.new(0, 0)
		controller:render()
	end, { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 36) })
	pages = Nav.strip(root, "VueMateriel", { { "stock", "Stock", 68 }, { "loaded", "À bord", 72 }, { "fleet", "Choisir l’engin", 116 } },
		function(id)
			if id ~= "fleet" then previous = id end
			controller:render()
		end, { Size = UDim2.new(1, 0, 0, 38) })
	local target = Widgets.label(root, "Cible", "", {
		Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, -6, 0, 32),
		TextSize = Theme.text.small, TextColor3 = Theme.colors.textDim,
	})
	local empty = Widgets.label(body, "Vide", "", {
		Size = UDim2.new(1, -8, 0, 38), TextColor3 = Theme.colors.textMuted, TextSize = Theme.text.small,
	})
	local fleetRows = Widgets.list(fleet, function(vehicle) return vehicle.id end, function(vehicle)
		local button = Widgets.button(fleet, "Choisir_" .. vehicle.id, "", function()
			controller:select("vehicle", vehicle.id)
			pages.select(previous)
		end, { Size = UDim2.new(1, -6, 0, 40) })
		return { instance = button }
	end, function(entry, vehicle)
		entry.instance.Text = vehicle.callsign .. "  ·  " .. vehicle.name .. "  ·  " .. Theme.statusLabel(vehicle.status)
		Widgets.setSelected(entry.instance, controller.state.vehicleId == vehicle.id)
	end)
	local payload = { units = 0, weight = 0 }

	local stockRows = Widgets.list(stockList, function(entry)
		return entry.id
	end, function(entry)
		local row = Widgets.frame(stockList, "Stock_" .. entry.id, {
			BackgroundColor3 = Theme.colors.surfaceAlt,
			BackgroundTransparency = 0.4,
			Size = UDim2.new(1, -6, 0, 42),
		})
		Widgets.corner(row, Theme.radius.small)
		local name = Widgets.label(row, "Nom", entry.name, {
			Position = UDim2.fromOffset(8, 2),
			Size = UDim2.new(1, -148, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = Theme.text.tiny,
		})
		local quantity = Widgets.label(row, "Quantite", "", {
			Position = UDim2.fromOffset(8, 22),
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
			else
				pages.select("fleet")
			end
		end, { Size = UDim2.fromOffset(122, 30), Position = UDim2.new(1, -130, 0, 5), TextSize = Theme.text.tiny })
		return { instance = row, name = name, quantity = quantity, install = install }
	end, function(entryView, entry)
		entryView.name.Text = entry.name
		entryView.quantity.Text = "En stock : " .. entry.quantity
		local vehicle = controller:selectedVehicle()
		local def = Equipment.get(entry.id)
		local typeDef = vehicle and Vehicles.get(vehicle.typeId)
		local reason = nil
		if not vehicle then reason = "Choisir l’engin"
		elseif not typeDef or not def or not table.find(def.services, typeDef.service) then reason = "Incompatible"
		elseif vehicle.status ~= Constants.VEHICLE_STATUS.AVAILABLE then reason = "En mission"
		elseif not controller:can("equipment") or not controller:canService(vehicle.service) then reason = "Poste restreint"
		elseif entry.quantity <= 0 or payload.units >= typeDef.equipmentSlots or payload.weight + def.weight > typeDef.capacity then reason = "Capacité atteinte" end
		entryView.install.Text = reason or "Installer"
		Widgets.setEnabled(entryView.install, reason == nil or vehicle == nil)
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
		local mode = pages.value
		local vehicle = controller:selectedVehicle()
		local typeDef = vehicle and Vehicles.get(vehicle.typeId)
		fleet.Visible = mode == "fleet"
		stockList.Visible = mode == "stock"
		installedList.Visible = mode == "loaded"
		familiesNav.root.Visible = mode == "stock"
		target.Visible = mode ~= "stock"
		pages.buttons.fleet.Text = vehicle and (vehicle.callsign .. "  ▾") or "Choisir l’engin"
		payload.units, payload.weight = 0, 0
		for _, entry in ipairs(vehicle and vehicle.equipment or {}) do
			local def = Equipment.get(entry.id)
			payload.units += entry.quantity
			payload.weight += (def and def.weight or 0) * entry.quantity
		end
		local entries
		if mode == "fleet" then
			target.Text = "Choisissez la destination du matériel."
			entries = snapshot.vehicles or {}
			fleetRows.update(entries)
			empty.Text = "Aucun engin dans la flotte."
		elseif mode == "loaded" then
			target.Text = typeDef and string.format("%s  ·  %d/%d emplacements  ·  %d/%d kg", vehicle.callsign,
				payload.units, typeDef.equipmentSlots, payload.weight, typeDef.capacity) or "Choisissez un engin pour voir son chargement."
			entries = vehicle and vehicle.equipment or {}
			installedRows.update(entries)
			empty.Text = vehicle and "Aucun matériel à bord." or ""
		else
			entries = {}
			for _, entry in ipairs(snapshot.stock or {}) do
				local def = Equipment.get(entry.id)
				if familiesNav.value == "all" or (def and familyOf[def.category] == familiesNav.value) then
					table.insert(entries, entry)
				end
			end
			stockRows.update(entries)
			empty.Text = "Aucun matériel en stock dans cette famille."
		end
		empty.Visible = #entries == 0
	end

	return { root = root, update = update, stock = stockRows }
end

return EquipmentPanel
