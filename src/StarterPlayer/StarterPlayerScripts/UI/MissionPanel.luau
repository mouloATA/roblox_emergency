--!strict
-- Tableau du service : ordres de mission, objectifs cliquables et distinctions.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Missions = require(Shared:WaitForChild("Catalogs"):WaitForChild("Missions"))
local Constants = require(Shared:WaitForChild("Constants"))
local Config = require(Shared:WaitForChild("Config"))
local UI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ERSClient"):WaitForChild("UI")
local Widgets = require(UI:WaitForChild("Widgets"))
local Theme = require(UI:WaitForChild("Theme"))
local MissionPanel = {}

local labels = {
	locked = "À découvrir", cancelled = "Annulé", pending = "À engager", active = "En cours",
	resolved = "Rempli", completed = "Réussie", failed = "Échec",
}

-- Construit les contrôles une fois. Le serveur renseigne les objectifs et les résultats.
function MissionPanel.create(parent: any, context: any): any
	local controller = context.controller
	local root = Widgets.scroller(parent, "PanneauMissions", {Size = UDim2.fromScale(1, 1)})
	Widgets.padding(root, 10, 4)
	local summary = Widgets.label(root, "Bulletin", "", {
		Size = UDim2.new(1, -6, 0, 32), TextSize = Theme.text.small, Font = Theme.fonts.bold, TextWrapped = true,
	})
	local active = Widgets.section(root, "Objectifs")
	local buttons = {}
	local links = {}
	local ids = {}
	for i = 1, 2 do
		links[i] = Widgets.button(root, "Objectif_" .. i, "", function()
			if ids[i] then
				controller:select("incident", ids[i], true)
			end
		end, {Size = UDim2.new(1, -8, 0, 38), TextSize = Theme.text.small, TextWrapped = true})
	end
	local choose = Widgets.section(root, "Choisir une mission")
	for _, mission in ipairs(Missions.list) do
		local card = Widgets.frame(root, "Mission_" .. mission.id, {
			Size = UDim2.new(1, -8, 0, 84), BackgroundColor3 = Theme.colors.surfaceAlt,
		})
		local go = Widgets.button(card, "Action_mission_" .. mission.id, "Lancer", function()
			controller:command(Constants.ACTION.START_MISSION, {missionId = mission.id})
		end, {Size = UDim2.fromOffset(78, 32), Position = UDim2.new(1, -82, 0, 2), TextSize = Theme.text.small})
		Widgets.label(card, "Nom", mission.name, {
			Position = UDim2.fromOffset(6, 4), Size = UDim2.new(1, -94, 0, 26),
			TextSize = Theme.text.body, Font = Theme.fonts.bold,
		})
		Widgets.label(card, "Briefing", mission.briefing, {
			Position = UDim2.fromOffset(6, 34), Size = UDim2.new(1, -12, 0, 46), TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top, TextSize = Theme.text.small, TextColor3 = Theme.colors.textDim,
		})
		buttons[mission.id] = go
	end
	Widgets.section(root, "Distinctions de service")
	local awards = {}
	for i = 1, 6 do
		awards[i] = Widgets.label(root, "Distinction_" .. i, "", {
			Size = UDim2.new(1, -8, 0, 46), TextSize = Theme.text.small, TextWrapped = true,
		})
	end

	local function update(snapshot: any, _state: any): ()
		local mission = snapshot.mission
		local report = snapshot.progression
		summary.Text = report and string.format("Score %d pts   ·   Évaluation %s   ·   %d perte(s) civile(s) (−%d pts)",
			report.score, report.rating and tostring(report.rating) .. "/100" or "—", report.civilianLosses, report.civilianPenalty)
			or "Bulletin en attente"
		active.Visible = mission ~= nil
		if mission then
			active.Text = mission.name .. " · " .. labels[mission.status]
		end
		for i, link in ipairs(links) do
			local objective = mission and mission.objectives[i]
			ids[i] = objective and objective.incidentId or nil
			link.Visible = objective ~= nil
			if objective then
				link.Text = (objective.incidentId and (objective.incidentId .. " · ") or "") .. objective.label .. " · " .. labels[objective.status]
				Widgets.setEnabled(link, ids[i] ~= nil)
			end
		end
		local canLaunch = controller:can(Constants.ACTION.START_MISSION)
		local busy = mission and mission.status == "active"
		local saturated = (snapshot.alerts or 0) >= Config.MAX_ACTIVE_INCIDENTS
		choose.Text = if snapshot.finished then "FIN DE SERVICE" elseif busy then "MISSION EN COURS"
			elseif saturated then "TOUTES LES INTERVENTIONS SONT MOBILISÉES"
			elseif canLaunch then "CHOISIR UNE MISSION" else "MISSIONS · LANCEMENT PAR LE COMMANDEMENT"
		for id, button in pairs(buttons) do
			local wins = (snapshot.stats or {})["mission_" .. id] or 0
			button.Text = busy and mission.id == id and "En cours" or (wins > 0 and "Rejouer" or "Lancer")
			Widgets.setEnabled(button, canLaunch and not busy and not snapshot.finished and not saturated)
		end
		for i, row in ipairs(awards) do
			local award = report and report.awards[i]
			if award then
				row.Text = string.format("%s · %s\n%s", award.name, award.earned and "Obtenue" or string.format("%d/%d", award.current, award.target), award.condition)
				row.TextColor3 = award.earned and Theme.colors.success or Theme.colors.textDim
			end
		end
	end
	return {root = root, update = update, buttons = buttons, links = links, summary = summary}
end

return MissionPanel
