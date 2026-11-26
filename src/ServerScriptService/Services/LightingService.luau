--!strict
--[[
	LightingService — éclairage de la scène aligné sur l'horloge de service.

	L'heure affichée dans l'interface ne servait jusqu'ici qu'au texte : la ville
	restait éclairée en plein jour à minuit. Ce service traduit `world.time` en
	`Lighting.ClockTime`, installe une atmosphère légère, une seule fois, et
	règle la scène pour la nuit : étoiles, lune, lampadaires et fenêtres.

	Il est volontairement séparé de la simulation : celle-ci reste testable sans
	service Roblox, et l'éclairage peut être appliqué à un `Lighting` et une
	scène injectés dans les tests.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Utilities = Shared:WaitForChild("Utilities")
local TimeUtil = require(Utilities:WaitForChild("TimeUtil"))

local LightingService = {}

local ATMOSPHERE_NAME = "ERS_Atmosphere"

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Mélange linéaire de deux couleurs (utile pour l'aube et le crépuscule).
local function mixColor(a: Color3, b: Color3, t: number): Color3
	return Color3.new(lerp(a.R, b.R, t), lerp(a.G, b.G, t), lerp(a.B, b.B, t))
end

--[[
	Facteur de jour : 0 en pleine nuit, 1 en plein jour.

	La transition est linéaire sur `LIGHTING_DAWN_HOUR..LIGHTING_DAY_HOUR` le
	matin, puis sur `LIGHTING_DUSK_HOUR..LIGHTING_NIGHT_HOUR` le soir. Exposé
	pour que les tests vérifient les bornes sans dépendre de l'heure réelle.
]]
function LightingService.daylight(hour: number, config: any?): number
	local cfg = config or Config
	local h = hour % 24
	local dawn = cfg.LIGHTING_DAWN_HOUR
	local day = cfg.LIGHTING_DAY_HOUR
	local dusk = cfg.LIGHTING_DUSK_HOUR
	local night = cfg.LIGHTING_NIGHT_HOUR
	if h <= dawn or h >= night then
		return 0
	elseif h < day then
		return (h - dawn) / (day - dawn)
	elseif h <= dusk then
		return 1
	end
	return 1 - (h - dusk) / (night - dusk)
end

-- Allume ou éteint les éléments de nuit (étoiles, lune, lampadaires, vitres).
-- Retourne le nombre d'éléments modifiés, pour les tests.
function LightingService.applyScene(scene: any, night: number, config: any?): number
	if not scene then
		return 0
	end
	local cfg = config or Config
	local changed = 0
	local isNight = night >= 0.5

	local sky = scene:FindFirstChild("Ciel")
	if sky then
		local starAlpha = math.clamp(1 - night * 0.9, 0.1, 1)
		local moonAlpha = math.clamp(1 - night * 0.95, 0.05, 1)
		for _, body in ipairs(sky:GetChildren()) do
			body.Transparency = body.Name == "Lune" and moonAlpha or starAlpha
			changed += 1
		end
	end

	local furniture = scene:FindFirstChild("Mobilier")
	if furniture then
		for _, part in ipairs(furniture:GetChildren()) do
			if string.sub(part.Name, 1, 5) == "Lampe" then
				local glow = part:FindFirstChild("Eclairage")
				if glow then
					glow.Enabled = isNight
					glow.Brightness = cfg.LIGHTING_LAMP_BRIGHTNESS
					changed += 1
				end
			end
		end
	end

	local buildings = scene:FindFirstChild("Batiments")
	if buildings then
		for _, part in ipairs(buildings:GetChildren()) do
			if string.sub(part.Name, 1, 5) == "Vitre" then
				if isNight then
					part.Material = Enum.Material.Neon
					part.Color = cfg.LIGHTING_WINDOW_NIGHT
					part.Transparency = 0.05
				else
					part.Material = Enum.Material.Glass
					part.Color = cfg.WINDOW_COLOR
					part.Transparency = 0.15
				end
				changed += 1
			end
		end
	end

	return changed
end

local function ensureAtmosphere(lighting: any, world: any, day: number): any
	local atmosphere = lighting:FindFirstChild(ATMOSPHERE_NAME)
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = ATMOSPHERE_NAME
		atmosphere.Parent = lighting
	end
	local cfg = world.config
	atmosphere.Density = cfg.LIGHTING_ATMOSPHERE_DENSITY
	atmosphere.Haze = cfg.LIGHTING_ATMOSPHERE_HAZE
	atmosphere.Glare = 0.15
	atmosphere.Color = mixColor(cfg.LIGHTING_NIGHT_HAZE_COLOR, cfg.LIGHTING_HAZE_COLOR, day)
	atmosphere.Decay = cfg.LIGHTING_HAZE_DECAY
	return atmosphere
end

--[[
	Applique l'heure simulée à un service `Lighting` (ou à sa doublure de test).

	`scene` est facultative : la scène 3D donne les étoiles, les lampadaires et
	les vitres à éteindre ou allumer. Sans elle, seuls le ciel et l'ambiance
	suivent l'horloge.
]]
function LightingService.apply(lighting: any, world: any, scene: any?): number
	local hour = TimeUtil.hour(world)
	local cfg = world.config
	local day = LightingService.daylight(hour, cfg)
	if scene then
		world.scene = scene
	end

	lighting.ClockTime = hour
	lighting.GeographicLatitude = cfg.LIGHTING_LATITUDE
	lighting.Brightness = lerp(cfg.LIGHTING_NIGHT_BRIGHTNESS, cfg.LIGHTING_BRIGHTNESS, day)
	lighting.Ambient = mixColor(cfg.LIGHTING_NIGHT_AMBIENT, cfg.LIGHTING_AMBIENT, day)
	lighting.OutdoorAmbient = mixColor(cfg.LIGHTING_NIGHT_OUTDOOR_AMBIENT, cfg.LIGHTING_OUTDOOR_AMBIENT, day)
	lighting.EnvironmentDiffuseScale = 0.6
	lighting.EnvironmentSpecularScale = 0.4
	ensureAtmosphere(lighting, world, day)

	LightingService.applyScene(scene or world.scene, 1 - day, cfg)

	world.lightingHour = hour
	world.lightingNight = 1 - day
	return hour
end

--[[
	Met l'éclairage à jour si l'heure simulée a assez changé.

	Un appel par tic suffit : l'heure n'est réécrite que lorsque la minute
	simulée change, ce qui évite de modifier `ClockTime` soixante fois par
	seconde pour rien. Retourne `true` quand une écriture a eu lieu.
]]
function LightingService.step(world: any, lighting: any?, scene: any?): boolean
	local target = lighting or game:GetService("Lighting")
	local hour = TimeUtil.hour(world)
	local last = world.lightingHour
	if type(last) == "number" and math.abs(hour - last) < (1 / 60) then
		return false
	end
	LightingService.apply(target, world, scene)
	return true
end

return LightingService
