--!strict
--[[
	TimeUtil — horloge de service et formats d'affichage.
	Le monde avance en secondes réelles ; l'horloge in-game est une conversion.
]]

local TimeUtil = {}

-- Convertit une durée en secondes de service en "HH:MM" (24 h simulées).
function TimeUtil.format(seconds: number, shiftStartHour: number?): string
	local total = math.floor(seconds)
	local secondsPerDay = 86400
	total = ((total % secondsPerDay) + secondsPerDay) % secondsPerDay
	local hours = math.floor(total / 3600)
	local minutes = math.floor((total % 3600) / 60)
	return string.format("%02d:%02d", (hours + (shiftStartHour or 0)) % 24, minutes)
end

-- Heure affichée pour un monde dont `time` est le temps de service écoulé.
function TimeUtil.clock(world: any): string
	local shift = math.max(1, world.config.SHIFT_SECONDS)
	local inGame = world.time / shift * 86400
	return TimeUtil.format(inGame, world.config.SHIFT_START_HOUR or 0)
end

-- Heure décimale 0..24, utilisée par l'éclairage de la scène.
function TimeUtil.hour(world: any): number
	local shift = math.max(1, world.config.SHIFT_SECONDS)
	local inGame = world.time / shift * 24 + (world.config.SHIFT_START_HOUR or 0)
	return inGame % 24
end

-- Formate une durée restante (secondes) en "1 min 20 s".
function TimeUtil.duration(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	local minutes = math.floor(total / 60)
	local rest = total % 60
	if minutes <= 0 then
		return string.format("%ds", rest)
	end
	return string.format("%d min %02ds", minutes, rest)
end

return TimeUtil
