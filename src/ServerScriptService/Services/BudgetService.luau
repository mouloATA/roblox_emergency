--!strict
--[[
	BudgetService — trésorerie opérationnelle (spec §13).

	Toutes les variations passent par ce module : dépense, recette, pénalité.
	Les montants sont entiers, les écritures sont datées et limitées en nombre.
	Une pénalité peut rendre le budget négatif : c'est un état de jeu réel.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Utilities = Shared:WaitForChild("Utilities")
local Result = require(Utilities:WaitForChild("Result"))

local BudgetService = {}

local function record(world: any, amount: number, reason: string): ()
	table.insert(world.transactions, 1, {
		time = world.time,
		amount = amount,
		reason = reason,
		balance = world.budget,
	})
	while #world.transactions > world.config.TRANSACTION_LIMIT do
		table.remove(world.transactions)
	end
end

-- Vérifie qu'une dépense est possible sans la réaliser.
function BudgetService.canAfford(world: any, amount: number): boolean
	return world.budget >= math.max(0, math.floor(amount))
end

-- Dépense ; refusée si le solde est insuffisant (sauf allowNegative).
function BudgetService.charge(world: any, amount: number, reason: string, allowNegative: boolean?): any
	local value = math.floor(amount + 0.5)
	if value <= 0 then
		return Result.ok("Aucun frais.", 0)
	end
	if not allowNegative and world.budget < value then
		return Result.err(string.format("Budget insuffisant : %d € requis, %d € disponibles.", value, world.budget))
	end
	world.budget -= value
	world.stats.spent += value
	record(world, -value, reason)
	return Result.ok(string.format("Dépense de %d € — %s.", value, reason), value)
end

function BudgetService.spend(world: any, amount: number, reason: string): any
	return BudgetService.charge(world, amount, reason, false)
end

-- Pénalité : elle s'applique même si le budget ne peut pas la couvrir.
function BudgetService.penalty(world: any, amount: number, reason: string): any
	return BudgetService.charge(world, amount, reason, true)
end

-- Recette (règlement d'intervention, dotation…).
function BudgetService.earn(world: any, amount: number, reason: string): any
	local value = math.floor(amount + 0.5)
	if value <= 0 then
		return Result.ok("Aucune recette.", 0)
	end
	world.budget += value
	world.stats.earned += value
	record(world, value, reason)
	return Result.ok(string.format("Recette de %d € — %s.", value, reason), value)
end

function BudgetService.summary(world: any): any
	return {
		balance = world.budget,
		spent = world.stats.spent,
		earned = world.stats.earned,
		transactions = world.transactions,
	}
end

return BudgetService
