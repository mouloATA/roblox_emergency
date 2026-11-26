--!strict
-- Un achat ou une cession par tour entre les responsables présents.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Result = require(Shared:WaitForChild("Utilities"):WaitForChild("Result"))
local Recruitment = require(Shared:WaitForChild("Catalogs"):WaitForChild("Recruitment"))
local Services = game:GetService("ServerScriptService"):WaitForChild("ERS"):WaitForChild("Services")
local PermissionService = require(Services:WaitForChild("PermissionService"))

local PurchaseService = {}
local TURN_SECONDS = 30

local function buyers(world: any): {number}
	local ids = {}
	for id, player in pairs(world.players) do
		if player.connected and PermissionService.can(world, id, Constants.ACTION.BUY_VEHICLE) then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		local ra, rb = world.players[a].role, world.players[b].role
		if ra ~= rb then
			return ra == Constants.ROLE.DIRECTION
		end
		return a < b
	end)
	return ids
end

-- Réconcilie les postes connectés et attribue automatiquement les tours expirés.
function PurchaseService.state(world: any): any
	local ids = buyers(world)
	local turn = world.purchaseTurn or {}
	world.purchaseTurn = turn
	local now = os.clock()
	if not table.find(ids, turn.owner) or turn.count ~= #ids then
		turn.owner = table.find(ids, turn.owner) and turn.owner or ids[1]
		turn.untilClock = now + TURN_SECONDS
	elseif #ids > 1 and now >= turn.untilClock then
		local elapsed = math.floor((now - turn.untilClock) / TURN_SECONDS) + 1
		local index = table.find(ids, turn.owner) or 1
		turn.owner = ids[(index - 1 + elapsed) % #ids + 1]
		turn.untilClock += elapsed * TURN_SECONDS
	end
	turn.count = #ids
	return {
		owner = turn.owner,
		name = turn.owner and world.players[turn.owner].name or "",
		count = #ids,
		remaining = #ids > 1 and math.ceil(turn.untilClock - now) or 0,
		surcharge = (world.stats.purchases or 0) * Recruitment.increase,
	}
end

-- Vérifie le poste et le tour avant toute opération financière.
function PurchaseService.check(world: any, actorId: number): any
	local permission = PermissionService.require(world, actorId, Constants.ACTION.BUY_VEHICLE)
	if not permission.ok then return permission end
	local turn = PurchaseService.state(world)
	if turn.owner ~= actorId then
		return Result.err("Tour d’achat de " .. turn.name .. ".")
	end
	return Result.ok()
end

-- Passe la main après une transaction réussie ; les acquisitions augmentent les prix.
function PurchaseService.advance(world: any, actorId: number, acquisition: boolean): ()
	if acquisition then world.stats.purchases = (world.stats.purchases or 0) + 1 end
	local ids = buyers(world)
	local current = table.find(ids, actorId)
	if current then
		world.purchaseTurn.owner = ids[current % #ids + 1]
		world.purchaseTurn.untilClock = os.clock() + TURN_SECONDS
	end
end

-- Tarif actuel, également utilisé pour les devis affichés par les clients.
function PurchaseService.price(world: any, base: number): number
	return base + (world.stats.purchases or 0) * Recruitment.increase
end

return PurchaseService
