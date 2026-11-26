--!strict
--[[
	Rng — générateur pseudo-aléatoire déterministe (LCG).

	Roblox fournit Random.new, mais les tests hors Studio n'en disposent pas.
	Ce générateur donne des séquences reproductibles et testables partout.
]]

local Rng = {}
Rng.__index = Rng

export type Rng = {
	state: number,
	next: (self: Rng) -> number,
	float: (self: Rng) -> number,
	integer: (self: Rng, minimum: number, maximum: number) -> number,
	pick: (self: Rng, list: { any }) -> any,
	weighted: (self: Rng, list: { any }, weight: (any) -> number) -> any?,
}

local MODULUS = 2147483647
local MULTIPLIER = 48271

function Rng.new(seed: number?): Rng
	local s = math.floor(math.abs(seed or os.time()))
	s = (s % (MODULUS - 1)) + 1
	return setmetatable({
		state = s,
	}, Rng :: any) :: Rng
end

function Rng.next(self: Rng): number
	self.state = (self.state * MULTIPLIER) % MODULUS
	return self.state
end

function Rng.float(self: Rng): number
	return (self:next() - 1) / (MODULUS - 2)
end

function Rng.integer(self: Rng, minimum: number, maximum: number): number
	local low = math.floor(minimum)
	local high = math.floor(maximum)
	if high <= low then
		return low
	end
	return low + self:next() % (high - low + 1)
end

function Rng.pick(self: Rng, list: { any }): any
	if #list == 0 then
		return nil
	end
	return list[self:integer(1, #list)]
end

function Rng.weighted(self: Rng, list: { any }, weight: (any) -> number): any?
	if #list == 0 then
		return nil
	end

	local total = 0
	for _, item in ipairs(list) do
		total += math.max(0, weight(item))
	end
	if total <= 0 then
		return self:pick(list)
	end

	local roll = self:float() * total
	for _, item in ipairs(list) do
		roll -= math.max(0, weight(item))
		if roll <= 0 then
			return item
		end
	end
	return list[#list]
end

return Rng
