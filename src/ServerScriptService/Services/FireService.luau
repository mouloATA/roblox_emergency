--!strict
-- Foyers adjacents d'une intervention, modélisés en unités de jeu.
local FireService = {}

local MATERIALS = {
	vegetation = { ignition = 19, spread = 2.4, fuel = 85 },
	wood = { ignition = 28, spread = 1.6, fuel = 140 },
	synthetic = { ignition = 35, spread = 1.2, fuel = 105 },
}
local OFFSETS = { {0, 0}, {2, 0}, {-2, 0}, {0, 2}, {0, -2}, {2, 2}, {-2, -2} }

-- Allume un premier foyer et place les combustibles voisins sur la carte.
function FireService.ignite(incident: any, definition: any): ()
	local material = definition.fireMaterial
	for _, step in ipairs(definition.steps) do
		if step.id == "attaque" or step.id == "extinction" then
			material = material or (if definition.id == "FEU_FORET" then "vegetation"
				elseif definition.id == "FEU_VEHICULE" then "synthetic" else "wood")
			break
		end
	end
	incident.fireCells = {}
	incident.waterUsed = 0
	if not MATERIALS[material] then return end
	for index = 1, math.min(#OFFSETS, 1 + 2 * definition.severity) do
		local cellMaterial = if index == 3 and material == "synthetic" then "vegetation" else material
		local offset = OFFSETS[index]
		table.insert(incident.fireCells, {
			x = math.clamp(incident.position.x + offset[1], 0, 100),
			z = math.clamp(incident.position.z + offset[2], 0, 100),
			material = cellMaterial, heat = if index == 1 then 55 else 0,
			burning = index == 1, spent = false, fuel = MATERIALS[cellMaterial].fuel,
		})
	end
end

-- Compte les foyers actifs et ceux dont le combustible est épuisé.
function FireService.count(incident: any): (number, number)
	local burning, spent = 0, 0
	for _, cell in ipairs(incident.fireCells) do
		if cell.burning then burning += 1 end
		if cell.spent then spent += 1 end
	end
	return burning, spent
end

-- Transmet la chaleur à distance d'une cellule ; les nouvelles flammes rayonnent au pas suivant.
function FireService.step(incident: any, dt: number): ()
	local cells = incident.fireCells
	local gains = table.create(#cells, 0)
	for index, cell in ipairs(cells) do
		if cell.burning then
			gains[index] += 0.7
			for neighbor, other in ipairs(cells) do
				local dx, dz = cell.x - other.x, cell.z - other.z
				if not other.burning and not other.spent and dx * dx + dz * dz <= 4.1 then
					gains[neighbor] += MATERIALS[cell.material].spread
				end
			end
		end
	end
	for index, cell in ipairs(cells) do
		if cell.spent then continue end
		local rate = if gains[index] > 0 then gains[index] else -0.6
		cell.heat = math.clamp(cell.heat + dt * rate, 0, 100)
		if cell.burning then
			cell.fuel = math.max(0, cell.fuel - dt)
			if cell.fuel == 0 then
				cell.spent, cell.burning, cell.heat = true, false, 0
			end
		elseif cell.heat >= MATERIALS[cell.material].ignition then
			cell.burning = true
		end
	end
end

-- Le jet poursuit le foyer déjà refroidi avant de passer au suivant.
function FireService.applyWater(incident: any, liters: number): number
	local target = nil
	for _, cell in ipairs(incident.fireCells) do
		if cell.burning and (not target or cell.heat < target.heat) then target = cell end
	end
	if not target then return 0 end
	local used = math.min(liters, target.heat)
	target.heat -= used
	incident.waterUsed += used
	if target.heat <= 2 then
		target.burning = false
	end
	return used
end

return FireService
