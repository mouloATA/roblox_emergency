--!strict
--[[
	MathX — petites mathématiques partagées.
	Testé dans tests/Unit/spec.luau.
]]

local MathX = {}

function MathX.clamp(value: number, minimum: number, maximum: number): number
	if value < minimum then
		return minimum
	elseif value > maximum then
		return maximum
	end
	return value
end

function MathX.round(value: number): number
	if value >= 0 then
		return math.floor(value + 0.5)
	end
	return math.ceil(value - 0.5)
end

function MathX.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function MathX.distance(ax: number, az: number, bx: number, bz: number): number
	local dx = bx - ax
	local dz = bz - az
	return math.sqrt(dx * dx + dz * dz)
end

-- Rapport sûr : un besoin nul est toujours satisfait.
function MathX.ratio(value: number, need: number): number
	if need <= 0 then
		return 1
	end
	return value / need
end

function MathX.sum(t: { [string]: number }): number
	local total = 0
	for _, value in pairs(t) do
		total += value
	end
	return total
end

return MathX
