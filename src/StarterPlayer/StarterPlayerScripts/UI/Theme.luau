--!strict
--[[
	Theme — palette, typographie et formats de l'interface tactique.

	Aucune couleur ni taille n'est écrite à la main dans les panneaux : tout
	passe par ce module, ce qui garantit une interface cohérente et permet de
	changer le thème en un seul endroit.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

local Theme = {}

Theme.colors = {
	background = Color3.fromRGB(14, 18, 22),
	surface = Color3.fromRGB(24, 30, 36),
	surfaceAlt = Color3.fromRGB(33, 41, 49),
	surfaceHigh = Color3.fromRGB(43, 53, 63),
	border = Color3.fromRGB(60, 72, 84),
	text = Color3.fromRGB(233, 239, 243),
	textDim = Color3.fromRGB(150, 164, 176),
	textMuted = Color3.fromRGB(108, 122, 134),
	accent = Color3.fromRGB(216, 96, 50),
	danger = Color3.fromRGB(200, 64, 64),
	success = Color3.fromRGB(80, 178, 118),
	warning = Color3.fromRGB(226, 176, 70),
	info = Color3.fromRGB(90, 150, 214),
	selection = Color3.fromRGB(60, 88, 112),
	map = Color3.fromRGB(20, 26, 32),
	mapGrid = Color3.fromRGB(38, 46, 54),

	-- Style « Emergency 4 » : panneaux bleu acier, boutons noirs, états verts.
	panel = Color3.fromRGB(56, 73, 92),
	panelDark = Color3.fromRGB(34, 46, 59),
	panelLight = Color3.fromRGB(78, 98, 118),
	steel = Color3.fromRGB(126, 140, 154),
	well = Color3.fromRGB(22, 30, 39),
	command = Color3.fromRGB(16, 17, 19),
	commandHover = Color3.fromRGB(42, 44, 48),
	commandText = Color3.fromRGB(214, 66, 52),
	active = Color3.fromRGB(96, 206, 128),
	inactive = Color3.fromRGB(96, 104, 112),
}

Theme.serviceColor = {
	fire = Color3.fromRGB(210, 92, 48),
	medical = Color3.fromRGB(80, 178, 118),
	police = Color3.fromRGB(74, 116, 198),
	technical = Color3.fromRGB(176, 148, 92),
	command = Color3.fromRGB(186, 122, 196),
	logistics = Color3.fromRGB(120, 150, 140),
}

Theme.statusColor = {
	available = Theme.colors.success,
	dispatched = Theme.colors.warning,
	onscene = Theme.colors.accent,
	returning = Theme.colors.info,
	maintenance = Theme.colors.textMuted,
	pending = Theme.colors.warning,
	active = Theme.colors.accent,
	resolved = Theme.colors.success,
	failed = Theme.colors.danger,
}

Theme.fonts = {
	title = Enum.Font.GothamBold,
	body = Enum.Font.Gotham,
	bold = Enum.Font.GothamBold,
	mono = Enum.Font.Code,
}

Theme.text = {
	title = 22,
	subtitle = 17,
	body = 15,
	small = 13,
	tiny = 11,
}

Theme.sizes = {
	topBar = 44,
	tabsWidth = 206,
	panelWidth = 372,
	logHeight = 148,
	statusBar = 28,
	row = 54,
	gap = 8,
	bar = 188, -- hauteur de la barre inférieure
	barGap = 6,
	minimapWidth = 360,
	minimapHeight = 420,
	drawerHeight = 340,
	tabsCompact = 152,
}

Theme.radius = {
	small = 4,
	medium = 7,
	large = 10,
}

-- Formate un montant en euros avec séparateurs de milliers.
function Theme.money(value: number): string
	local rounded = math.floor((value or 0) + 0.5)
	local sign = ""
	if rounded < 0 then
		sign = "−"
		rounded = -rounded
	end
	local digits = tostring(rounded)
	local parts = {}
	while #digits > 3 do
		table.insert(parts, 1, string.sub(digits, -3))
		digits = string.sub(digits, 1, -4)
	end
	table.insert(parts, 1, digits)
	return sign .. table.concat(parts, " ") .. " €"
end

function Theme.percent(value: number): string
	return string.format("%d %%", math.floor((value or 0) + 0.5))
end

function Theme.seconds(value: number): string
	local total = math.max(0, math.floor(value or 0))
	return string.format("%d:%02d", math.floor(total / 60), total % 60)
end

function Theme.serviceLabel(service: string?): string
	if not service then
		return "Interventions"
	end
	return Constants.SERVICE_LABEL[service] or service
end

function Theme.statusLabel(status: string?): string
	return Constants.STATUS_LABEL[status or ""] or (status or "")
end

return Theme
