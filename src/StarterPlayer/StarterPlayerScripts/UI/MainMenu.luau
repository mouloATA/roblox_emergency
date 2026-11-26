--!strict
--[[
	MainMenu — écran d'accueil et choix du poste.

	Le menu présente la mission, les postes disponibles et l'état de l'équipe.
	Choisir un poste envoie `claim_role` ; le serveur refuse un poste déjà tenu.
	« Entrer en opération » ferme simplement l'écran : le jeu continue derrière,
	puisque la simulation tourne déjà côté serveur.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local Catalogs = Shared:WaitForChild("Catalogs")
local Permissions = require(Catalogs:WaitForChild("Permissions"))

local UI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ERSClient"):WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))

local MainMenu = {}

local ROLE_ORDER = {
	Constants.ROLE.DIRECTION,
	Constants.ROLE.COMMANDEMENT,
	Constants.ROLE.INCENDIE,
	Constants.ROLE.SECOURS,
	Constants.ROLE.POLICE,
	Constants.ROLE.LOGISTIQUE,
	Constants.ROLE.OBSERVATEUR,
}

function MainMenu.create(parent: any, context: any): any
	local controller = context.controller
	local localUserId = controller.player and controller.player.UserId or 0
	local latestSnapshot = context.snapshot or { players = {} }

	local overlay = Widgets.frame(parent, "MenuPrincipal", {
		BackgroundColor3 = Theme.colors.background,
		BackgroundTransparency = 0.2,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 40,
	})
	overlay.Visible = true

	local card = Widgets.frame(overlay, "Carte", {
		BackgroundColor3 = Theme.colors.surface,
		Size = UDim2.fromOffset(840, 566),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
	})
	Widgets.corner(card, Theme.radius.large)
	Widgets.stroke(card, Theme.colors.border)
	Widgets.padding(card, 22, 6)

	local title = Widgets.label(card, "Titre", "EMERGENCY RESPONSE SIMULATOR", {
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = 26,
		Font = Theme.fonts.bold,
		TextColor3 = Theme.colors.text,
	})
	local subtitle = Widgets.label(card, "SousTitre", string.format(
		"%s · centre 112 · version %s",
		Config.CITY_NAME,
		Config.VERSION
	), {
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.text.small,
		TextColor3 = Theme.colors.accent,
	})
	local mission = Widgets.label(card, "Mission",
		"Vous dirigez les secours de Val-des-Secours. Recevez les alertes, composez les équipages, "
		.. "engagez les engins, gérez le budget et le matériel. Chaque décision est appliquée par le serveur.",
		{
			Position = UDim2.fromOffset(0, 54),
			Size = UDim2.new(1, 0, 0, 42),
			TextSize = Theme.text.tiny,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = Theme.colors.textDim,
		})

	local rolesSection = Widgets.section(card, "Choisissez votre poste")
	rolesSection.Position = UDim2.fromOffset(0, 102)
	rolesSection.Size = UDim2.new(0.66, -10, 0, 18)

	local rolesList = Widgets.scroller(card, "Roles", {
		Position = UDim2.fromOffset(0, 124),
		Size = UDim2.new(0.66, -10, 0, 318),
	})

	local roleButtons = {}
	for index, roleId in ipairs(ROLE_ORDER) do
		if Permissions.exists(roleId) then
			local role = Permissions.roles[roleId]
			local row = Widgets.frame(rolesList, "Poste_" .. roleId, {
				BackgroundColor3 = Theme.colors.surfaceAlt,
				BackgroundTransparency = 0.35,
				Size = UDim2.new(1, 0, 0, 42),
				LayoutOrder = index,
			})
			Widgets.corner(row, Theme.radius.small)
			local name = Widgets.label(row, "Nom", role.label, {
				Position = UDim2.fromOffset(10, 4),
				Size = UDim2.new(1, -112, 0, 17),
				TextSize = Theme.text.tiny,
				Font = Theme.fonts.bold,
			})
			local description = Widgets.label(row, "Description", role.description, {
				Position = UDim2.fromOffset(10, 21),
				Size = UDim2.new(1, -112, 0, 16),
				TextSize = 9,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = Theme.colors.textMuted,
			})
			local button = Widgets.button(row, "Action_claim_" .. roleId, "Prendre", function()
				controller:command("claim_role", { role = roleId })
			end, { Size = UDim2.fromOffset(92, 26), Position = UDim2.new(1, -100, 0, 8), TextSize = 9 })
			roleButtons[roleId] = button
		end
	end

	local side = Widgets.frame(card, "Cote", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.66, 10, 0, 102),
		Size = UDim2.new(0.34, -10, 0, 422),
	})

	local sideTitle = Widgets.label(side, "Titre", "VOTRE POSTE", {
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.text.tiny,
		Font = Theme.fonts.bold,
		TextColor3 = Theme.colors.textMuted,
	})
	local currentRole = Widgets.label(side, "Role", "Non enregistré", {
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = Theme.text.subtitle,
		Font = Theme.fonts.bold,
		TextColor3 = Theme.colors.accent,
	})
	local currentDescription = Widgets.label(side, "Description", "", {
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 54),
		TextSize = 9,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.colors.textDim,
	})

	local teamTitle = Widgets.label(side, "EquipeTitre", "ÉQUIPE EN LIGNE", {
		Position = UDim2.fromOffset(0, 108),
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.text.tiny,
		Font = Theme.fonts.bold,
		TextColor3 = Theme.colors.textMuted,
	})
	local team = Widgets.label(side, "Equipe", "", {
		Position = UDim2.fromOffset(0, 128),
		Size = UDim2.new(1, 0, 0, 86),
		TextSize = 10,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.colors.textDim,
	})

	local controlsTitle = Widgets.label(side, "CommandesTitre", "COMMANDES", {
		Position = UDim2.fromOffset(0, 224),
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.text.tiny,
		Font = Theme.fonts.bold,
		TextColor3 = Theme.colors.textMuted,
	})
	local controls = Widgets.label(side, "Commandes",
		"1–7 : groupes ou panneaux\n8 : missions · M : menu\nFlèches : déplacer la caméra\nR : recentrer\nCtrl+S : sauvegarder",
		{
			Position = UDim2.fromOffset(0, 244),
			Size = UDim2.new(1, 0, 0, 96),
			TextSize = 10,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = Theme.colors.textDim,
		})

	local enterButton = Widgets.button(side, "Action_enter", "Entrer en opération", function()
		controller:setMenu(false)
	end, {
		Size = UDim2.new(1, 0, 0, 38),
		Position = UDim2.new(0, 0, 1, -38),
		TextSize = Theme.text.small,
		BackgroundColor3 = Theme.colors.accent,
	})

	-- Nouvelle partie : réservée à la direction. Un écran de confirmation
	-- évite d'effacer une progression par un clic malheureux.
	-- `confirmPanel` est déclaré avant le bouton : la fermeture capture la
	-- variable locale, pas une globale nulle.
	local confirmPanel
	local newGameButton = Widgets.button(side, "Action_new_game", "Nouvelle partie", function()
		if confirmPanel then
			confirmPanel.Visible = true
		end
	end, {
		Size = UDim2.new(1, 0, 0, 38),
		Position = UDim2.new(0, 0, 1, -82),
		TextSize = Theme.text.small,
		BackgroundColor3 = Theme.colors.command,
		TextColor3 = Theme.colors.commandText,
	})
	newGameButton.Visible = false

	confirmPanel = Widgets.frame(card, "ConfirmationNouvellePartie", {
		BackgroundColor3 = Theme.colors.surface,
		Size = UDim2.fromOffset(430, 176),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
	})
	Widgets.corner(confirmPanel, Theme.radius.large)
	Widgets.stroke(confirmPanel, Theme.colors.danger, 2)
	Widgets.padding(confirmPanel, 16, 6)

	Widgets.label(confirmPanel, "Titre", "Nouvelle partie ?", {
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = Theme.text.subtitle,
		Font = Theme.fonts.bold,
		TextColor3 = Theme.colors.danger,
	})
	Widgets.label(confirmPanel, "Texte",
		"Le budget, le parc, les équipages, les interventions et les statistiques repartent de zéro. "
		.. "Les postes en ligne sont conservés. La progression sauvegardée sera remplacée à la prochaine sauvegarde.",
		{
			Position = UDim2.fromOffset(0, 32),
			Size = UDim2.new(1, 0, 0, 72),
			TextSize = Theme.text.tiny,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = Theme.colors.textDim,
		})

	local cancelNewGame = Widgets.button(confirmPanel, "Action_cancel_new_game", "Annuler", function()
		confirmPanel.Visible = false
	end, {
		Position = UDim2.new(0, 0, 1, -38),
		Size = UDim2.fromOffset(180, 34),
		TextSize = Theme.text.small,
		BackgroundColor3 = Theme.colors.panelLight,
	})
	local confirmNewGame = Widgets.button(confirmPanel, "Action_confirm_new_game", "Confirmer", function()
		confirmPanel.Visible = false
		controller:setMenu(false)
		controller:command("new_game")
	end, {
		Position = UDim2.new(1, -180, 1, -38),
		Size = UDim2.fromOffset(180, 34),
		TextSize = Theme.text.small,
		BackgroundColor3 = Theme.colors.danger,
		TextColor3 = Theme.colors.text,
	})

	local footer = Widgets.label(card, "Pied", "", {
		Position = UDim2.new(0, 0, 1, -28),
		Size = UDim2.new(0.66, -10, 0, 20),
		TextSize = 9,
		TextColor3 = Theme.colors.textMuted,
	})

	-- L'écran utilise le mode Sibling : la carte et tous ses enfants sont
	-- dessinés au-dessus du voile par la seule hiérarchie, sans remonter
	-- chaque ZIndex. Seul le voile porte un ZIndex élevé, pour passer devant
	-- la barre, le tiroir et les notifications.

	local function update(snapshot: any, state: any)
		latestSnapshot = snapshot
		overlay.Visible = state.menuOpen == true
		if not overlay.Visible then
			confirmPanel.Visible = false
		end

		-- « Nouvelle partie » n'a de sens que pour un poste autorisé : le
		-- serveur refuserait l'intention, autant ne pas la proposer.
		newGameButton.Visible = controller:can(Constants.ACTION.NEW_GAME)

		local me = nil
		local teamLines = {}
		for _, player in ipairs(snapshot.players or {}) do
			if player.userId == localUserId then
				me = player
			end
			table.insert(teamLines, string.format("%s — %s", player.name, player.roleLabel or player.role))
		end
		team.Text = #teamLines > 0 and table.concat(teamLines, "\n") or "Aucun joueur connecté."

		if me then
			currentRole.Text = me.roleLabel or Permissions.label(me.role)
			local roleDef = Permissions.roles[me.role]
			currentDescription.Text = roleDef and roleDef.description or ""
		else
			currentRole.Text = "Synchronisation…"
			currentDescription.Text = "Le serveur attribue un poste au premier joueur connecté."
		end

		for roleId, button in pairs(roleButtons) do
			local holder = nil
			for _, player in ipairs(snapshot.players or {}) do
				if player.connected ~= false and player.role == roleId then
					holder = player
				end
			end
			local isSelf = holder and holder.userId == localUserId
			Widgets.setEnabled(button, holder == nil or roleId == Constants.ROLE.OBSERVATEUR)
			button.Text = isSelf and "Actuel" or (holder and "Tenu" or "Prendre")
		end

		footer.Text = string.format(
			"%s · %d joueur(s) · budget %s",
			Config.GAME_SHORT,
			#(snapshot.players or {}),
			Theme.money(snapshot.budget or 0)
		)
	end

	return {
		root = overlay,
		update = update,
		card = card,
		enterButton = enterButton,
		newGameButton = newGameButton,
		confirmPanel = confirmPanel,
		roleButtons = roleButtons,
	}
end

return MainMenu
