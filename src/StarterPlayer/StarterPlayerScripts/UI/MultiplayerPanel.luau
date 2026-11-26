--!strict
--[[
	MultiplayerPanel — postes, joueurs connectés et prise de fonction.

	Chaque joueur peut prendre un poste libre (`claim_role`) ; la direction peut
	attribuer un poste à un joueur sélectionné (`assign_role`). Le serveur
	refuse un poste déjà tenu, la confiscation de la direction et toute
	attribution faite sans le droit « roles ».

	Ce panneau rend aussi visible qui tient quoi : aucune action de rôle n'est
	simulée localement, le snapshot fait foi.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Catalogs = Shared:WaitForChild("Catalogs")
local Permissions = require(Catalogs:WaitForChild("Permissions"))

local UI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ERSClient"):WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))

local MultiplayerPanel = {}

local ROLE_ORDER = {
	Constants.ROLE.DIRECTION,
	Constants.ROLE.COMMANDEMENT,
	Constants.ROLE.INCENDIE,
	Constants.ROLE.SECOURS,
	Constants.ROLE.POLICE,
	Constants.ROLE.LOGISTIQUE,
	Constants.ROLE.OBSERVATEUR,
}

local function roleItems(): { any }
	local items = {}
	for _, roleId in ipairs(ROLE_ORDER) do
		if Permissions.exists(roleId) then
			table.insert(items, {
				id = roleId,
				label = Permissions.label(roleId),
				description = Permissions.roles[roleId].description,
			})
		end
	end
	return items
end

function MultiplayerPanel.create(parent: any, context: any): any
	local controller = context.controller
	local localUserId = controller.player and controller.player.UserId or 0
	local latestSnapshot = context.snapshot or { players = {} }

	local root = Widgets.frame(parent, "PanneauPostes", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	Widgets.padding(root, 10, 2)

	local title = Widgets.label(root, "Titre", "POSTES ET ÉQUIPE", {
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

	local currentCard = Widgets.frame(root, "PosteActuel", {
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundColor3 = Theme.colors.surfaceAlt,
		BackgroundTransparency = 0.3,
	})
	Widgets.corner(currentCard, Theme.radius.medium)
	Widgets.stroke(currentCard, Theme.colors.border)
	local currentRole = Widgets.label(currentCard, "Role", "", {
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 20),
		TextSize = Theme.text.body,
		Font = Theme.fonts.bold,
	})
	local currentDescription = Widgets.label(currentCard, "Description", "", {
		Position = UDim2.fromOffset(10, 26),
		Size = UDim2.new(1, -20, 0, 28),
		TextSize = 9,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.colors.textDim,
	})

	-- Le corps défile : la liste des postes peut dépasser le tiroir.
	local body = Widgets.scroller(root, "Corps", {
		Position = UDim2.fromOffset(0, 114),
		Size = UDim2.new(1, 0, 1, -114),
	})

	Widgets.section(body, "Postes")

	local roleList = Widgets.scroller(body, "Roles", {
		Size = UDim2.new(1, 0, 0, 246),
	})
	local roleButtons = {}

	local roleRows = Widgets.list(roleList, function(role)
		return role.id
	end, function(role)
		local row = Widgets.frame(roleList, "RoleLigne_" .. role.id, {
			BackgroundColor3 = Theme.colors.surfaceAlt,
			BackgroundTransparency = 0.4,
			Size = UDim2.new(1, 0, 0, 56),
		})
		Widgets.corner(row, Theme.radius.small)
		local name = Widgets.label(row, "Nom", role.label, {
			Position = UDim2.fromOffset(8, 3),
			Size = UDim2.new(1, -112, 0, 17),
			TextSize = Theme.text.tiny,
			Font = Theme.fonts.bold,
		})
		local holder = Widgets.label(row, "Titulaire", "", {
			Position = UDim2.fromOffset(8, 20),
			Size = UDim2.new(1, -112, 0, 14),
			TextSize = 9,
			TextColor3 = Theme.colors.textMuted,
		})
		local description = Widgets.label(row, "Description", role.description, {
			Position = UDim2.fromOffset(8, 34),
			Size = UDim2.new(1, -112, 0, 18),
			TextSize = 8,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = Theme.colors.textMuted,
		})
		local action = Widgets.button(row, "Action_role_" .. role.id, "Prendre", function()
			local targetId = controller.state.userId
			local assign = controller:can("roles")
				and targetId ~= nil
				and targetId ~= localUserId
				and role.id ~= Constants.ROLE.DIRECTION
			if assign then
				controller:command("assign_role", { userId = targetId, role = role.id })
			else
				controller:command("claim_role", { role = role.id })
			end
		end, { Size = UDim2.fromOffset(92, 26), Position = UDim2.new(1, -100, 0, 15), TextSize = 9 })
		roleButtons[role.id] = action
		return { instance = row, name = name, holder = holder, description = description, action = action }
	end, function(entry, role)
		local snapshot = latestSnapshot
		local holderPlayer = nil
		for _, player in ipairs(snapshot.players or {}) do
			if player.connected ~= false and player.role == role.id then
				holderPlayer = player
			end
		end

		local isSelf = holderPlayer and holderPlayer.userId == localUserId
		local target = controller.state.userId
		local targetValid = controller:can("roles")
			and target ~= nil
			and target ~= localUserId
			and role.id ~= Constants.ROLE.DIRECTION

		if holderPlayer then
			entry.holder.Text = "Titulaire : " .. holderPlayer.name .. (isSelf and " (vous)" or "")
			entry.holder.TextColor3 = isSelf and Theme.colors.info or Theme.colors.textMuted
		else
			entry.holder.Text = "Poste libre"
			entry.holder.TextColor3 = Theme.colors.success
		end

		Widgets.setEnabled(entry.action, not isSelf and (targetValid or holderPlayer == nil or role.id == Constants.ROLE.OBSERVATEUR))
		if isSelf then
			entry.action.Text = "Poste actuel"
		elseif targetValid then
			entry.action.Text = "Attribuer"
		elseif holderPlayer and role.id ~= Constants.ROLE.OBSERVATEUR then
			entry.action.Text = "Tenu"
		else
			entry.action.Text = "Prendre"
		end
	end)

	Widgets.section(body, "Joueurs connectés")

	local playersList = Widgets.scroller(body, "Joueurs", {
		Size = UDim2.new(1, 0, 0, 104),
	})
	local playerRows = Widgets.list(playersList, function(player)
		return player.userId
	end, function(player)
		local row = Widgets.row(playersList, "JoueurLigne_" .. player.userId, 42, function()
			controller:select("user", player.userId)
		end)
		local name = Widgets.label(row, "Nom", player.name, {
			Position = UDim2.fromOffset(10, 4),
			Size = UDim2.new(1, -22, 0, 17),
			TextSize = Theme.text.small,
			Font = Theme.fonts.bold,
		})
		local role = Widgets.label(row, "Role", "", {
			Position = UDim2.fromOffset(10, 22),
			Size = UDim2.new(1, -22, 0, 14),
			TextSize = 9,
			TextColor3 = Theme.colors.textDim,
		})
		return { instance = row, name = name, role = role }
	end, function(entry, player)
		entry.name.Text = player.name .. (player.userId == localUserId and " (vous)" or "")
		entry.role.Text = (player.roleLabel or player.role)
			.. (player.connected == false and " · déconnecté" or "")
		entry.role.TextColor3 = player.connected == false and Theme.colors.textMuted or Theme.colors.textDim
		Widgets.setSelected(entry.instance, controller.state.userId == player.userId)
	end)

	local footer = Widgets.horizontal(body, "Pied", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
	})
	local observerButton = Widgets.button(footer, "Action_claim_observateur", "Devenir observateur", function()
		controller:command("claim_role", { role = Constants.ROLE.OBSERVATEUR })
	end, { Size = UDim2.fromOffset(140, 30), TextSize = 9 })
	local resyncButton = Widgets.button(footer, "Action_request_snapshot", "Resynchroniser", function()
		controller:command("request_snapshot", nil)
	end, { Size = UDim2.fromOffset(104, 30), TextSize = 9 })
	local targetLabel = Widgets.label(footer, "Cible", "", {
		Size = UDim2.new(1, -250, 1, 0),
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.colors.textMuted,
	})

	local function update(snapshot: any, _state: any)
		latestSnapshot = snapshot
		local players = snapshot.players or {}
		roleRows.update(roleItems())
		playerRows.update(players)

		local me = nil
		for _, player in ipairs(players) do
			if player.userId == localUserId then
				me = player
			end
		end
		if me then
			currentRole.Text = me.roleLabel or Permissions.label(me.role)
			local roleDef = Permissions.roles[me.role]
			currentDescription.Text = roleDef and roleDef.description or ""
		else
			currentRole.Text = "Non enregistré"
			currentDescription.Text = "Le serveur attribuera un poste à la prochaine synchronisation."
		end

		local target = nil
		for _, player in ipairs(players) do
			if player.userId == controller.state.userId then
				target = player
			end
		end
		targetLabel.Text = target
				and ("Cible d'attribution : " .. target.name)
			or "Cliquez un joueur pour lui attribuer un poste."
		subtitle.Text = string.format("%d joueur(s) · votre poste : %s", #players, currentRole.Text)
		Widgets.setEnabled(observerButton, me ~= nil and me.role ~= Constants.ROLE.OBSERVATEUR)
	end

	return {
		root = root,
		update = update,
		roleButtons = roleButtons,
		roleRows = roleRows,
		playerRows = playerRows,
		observerButton = observerButton,
		resyncButton = resyncButton,
	}
end

return MultiplayerPanel
