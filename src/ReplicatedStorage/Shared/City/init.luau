--!strict
--[[
	City — plan déterministe de Val-des-Secours.

	Ce module est la source unique de la ville : le serveur y lit les volumes à
	construire en 3D, le client y lit les rues et les quartiers à dessiner sur la
	mini-carte. Comme il ne dépend que de nombres, les deux côtés obtiennent
	exactement la même ville, sans envoyer de géométrie par le réseau.

	Coordonnées en unités de carte (0..100). La conversion en studs est faite
	par les appelants avec `Config.WORLD_SCALE`.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Rng = require(Shared:WaitForChild("Utilities"):WaitForChild("Rng"))

local City = {}

City.WIDTH = 100
City.ROAD_HALF = 3 -- demi-largeur d'une chaussée
City.SIDEWALK = 1.2 -- largeur du trottoir
City.CURB = 0.15 -- hauteur du trottoir

-- Ceinture verte : le sol s'arrête un peu au-delà de la ville, et une double
-- rangée d'arbres masque son bord. Sans elle, la caméra voyait la fin de la
-- dalle et le ciel sous l'horizon.
City.OUTSKIRTS = 9 -- unités de carte de chaque côté
City.BELT_TREE_STEP = 6.5

-- Cinq avenues (nord-sud) et cinq rues (est-ouest) : la trame de la ville.
City.AVENUES = { 7, 28, 49, 70, 91 }
City.STREETS = { 7, 28, 49, 70, 91 }

-- Palette de façades (RGB 0-255) : le serveur la convertit en Color3.
City.PALETTE = {
	{ name = "ocre", rgb = { 158, 132, 100 } },
	{ name = "pierre", rgb = { 138, 136, 128 } },
	{ name = "brique", rgb = { 140, 86, 72 } },
	{ name = "crepi", rgb = { 176, 168, 150 } },
	{ name = "ardoise", rgb = { 96, 104, 112 } },
	{ name = "sable", rgb = { 168, 148, 112 } },
}

City.DISTRICTS = {
	{ id = "nord_ouest", name = "Saint-Marc", x = 18, z = 18 },
	{ id = "nord_est", name = "Les Halles", x = 80, z = 18 },
	{ id = "centre", name = "Centre", x = 49, z = 49 },
	{ id = "sud_ouest", name = "Ceinture Sud", x = 18, z = 80 },
	{ id = "sud_est", name = "Zone Est", x = 80, z = 80 },
}

-- Points d'intérêt : un par bloc réservé, pour que la ville ait des repères.
local POIS = {
	{ id = "eglise", name = "Église Saint-Marc", block = { 3, 2 }, style = "eglise", floors = 4 },
	{ id = "hopital", name = "Hôpital", block = { 4, 1 }, style = "public", floors = 6 },
	{ id = "commissariat", name = "Commissariat", block = { 2, 2 }, style = "public", floors = 3 },
	{ id = "ecole", name = "École", block = { 1, 2 }, style = "public", floors = 3 },
	{ id = "gare", name = "Gare", block = { 3, 4 }, style = "public", floors = 2 },
	{ id = "industrie", name = "Zone industrielle", block = { 4, 4 }, style = "industrie", floors = 2 },
}

-- Bloc occupé par la caserne : bâtiment au nord, cour et stationnement au sud.
local BARRACKS_BLOCK = { 1, 3 }

local function blockBounds(column: number, row: number): any
	local x0 = City.AVENUES[column] + City.ROAD_HALF
	local x1 = City.AVENUES[column + 1] - City.ROAD_HALF
	local z0 = City.STREETS[row] + City.ROAD_HALF
	local z1 = City.STREETS[row + 1] - City.ROAD_HALF
	return { x0 = x0, z0 = z0, x1 = x1, z1 = z1, width = x1 - x0, depth = z1 - z0 }
end

local function poiForBlock(column: number, row: number): any?
	for _, poi in ipairs(POIS) do
		if poi.block[1] == column and poi.block[2] == row then
			return poi
		end
	end
	return nil
end

-- Construit une chaussée et ses trottoirs pour un axe.
local function addRoad(roads: { any }, sidewalks: { any }, axis: string, coordinate: number): ()
	local half = City.ROAD_HALF
	if axis == "avenue" then
		table.insert(roads, { axis = axis, x = coordinate, width = half * 2, z0 = 0, z1 = City.WIDTH })
		for _, side in ipairs({ -1, 1 }) do
			local startX = coordinate + side * half
			table.insert(sidewalks, {
				axis = axis,
				x = startX + side * City.SIDEWALK / 2,
				width = City.SIDEWALK,
				z0 = 0,
				z1 = City.WIDTH,
			})
		end
	else
		table.insert(roads, { axis = axis, z = coordinate, width = half * 2, x0 = 0, x1 = City.WIDTH })
		for _, side in ipairs({ -1, 1 }) do
			local startZ = coordinate + side * half
			table.insert(sidewalks, {
				axis = axis,
				z = startZ + side * City.SIDEWALK / 2,
				width = City.SIDEWALK,
				x0 = 0,
				x1 = City.WIDTH,
			})
		end
	end
end

-- Construit un immeuble dans une parcelle (aucun chevauchement possible).
local function addBuilding(buildings: { any }, parcel: any, rng: any, style: string?, floors: number?): any
	local inset = 0.55
	local x0 = parcel.x0 + inset
	local x1 = parcel.x1 - inset
	local z0 = parcel.z0 + inset
	local z1 = parcel.z1 - inset
	if x1 - x0 < 2.4 or z1 - z0 < 2.4 then
		return nil
	end
	local palette = City.PALETTE[rng:integer(1, #City.PALETTE)]
	local building = {
		x0 = x0,
		x1 = x1,
		z0 = z0,
		z1 = z1,
		floors = floors or rng:integer(2, 6),
		style = style or "habitat",
		facade = palette.rgb,
		facadeName = palette.name,
	}
	table.insert(buildings, building)
	return building
end

-- Découpe un bloc en quatre parcelles (2 x 2) avec une courette centrale.
local function parcelsOf(block: any): { any }
	local gap = 1.2
	local middleX = (block.x0 + block.x1) / 2
	local middleZ = (block.z0 + block.z1) / 2
	return {
		{ x0 = block.x0, z0 = block.z0, x1 = middleX - gap / 2, z1 = middleZ - gap / 2 },
		{ x0 = middleX + gap / 2, z0 = block.z0, x1 = block.x1, z1 = middleZ - gap / 2 },
		{ x0 = block.x0, z0 = middleZ + gap / 2, x1 = middleX - gap / 2, z1 = block.z1 },
		{ x0 = middleX + gap / 2, z0 = middleZ + gap / 2, x1 = block.x1, z1 = block.z1 },
	}
end

local function addTrees(trees: { any }, block: any, rng: any, count: number): ()
	for _ = 1, count do
		table.insert(trees, {
			x = rng:integer(math.floor(block.x0 + 1), math.floor(block.x1 - 1)),
			z = rng:integer(math.floor(block.z0 + 1), math.floor(block.z1 - 1)),
			size = rng:integer(6, 11) / 10,
		})
	end
end

--[[
	Construit le plan complet.

	`seed` garantit une ville identique sur le serveur et sur chaque client :
	le client ne reçoit donc que les positions des engins et des urgences.
]]
function City.build(seed: number?): any
	local rng = Rng.new(seed or 20261117)
	local plan = {
		width = City.WIDTH,
		roads = {},
		sidewalks = {},
		crossings = {},
		trafficLights = {},
		streetlights = {},
		blocks = {},
		buildings = {},
		parks = {},
		trees = {},
		pois = {},
		bays = {},
		districts = City.DISTRICTS,
		barracks = nil,
	}

	for _, x in ipairs(City.AVENUES) do
		addRoad(plan.roads, plan.sidewalks, "avenue", x)
	end
	for _, z in ipairs(City.STREETS) do
		addRoad(plan.roads, plan.sidewalks, "street", z)
	end

	-- Passages piétons et feux aux carrefours (une approche par axe).
	for _, x in ipairs(City.AVENUES) do
		for _, z in ipairs(City.STREETS) do
			table.insert(plan.crossings, {
				x = x,
				z = z + City.ROAD_HALF + 0.9,
				axis = "street",
				width = City.ROAD_HALF * 2,
			})
			table.insert(plan.crossings, {
				x = x + City.ROAD_HALF + 0.9,
				z = z,
				axis = "avenue",
				width = City.ROAD_HALF * 2,
			})
			table.insert(plan.trafficLights, {
				x = x + City.ROAD_HALF + 1,
				z = z - City.ROAD_HALF - 1,
			})
		end
	end

	-- Lampadaires à mi-bloc, le long des avenues.
	for _, x in ipairs(City.AVENUES) do
		for z = 12, City.WIDTH - 8, 16 do
			table.insert(plan.streetlights, { x = x - City.ROAD_HALF - City.SIDEWALK / 2, z = z, side = -1 })
			table.insert(plan.streetlights, { x = x + City.ROAD_HALF + City.SIDEWALK / 2, z = z + 8, side = 1 })
		end
	end

	-- Arbres d'alignement sur les trottoirs du centre, hors carrefours.
	for _, x in ipairs({ 49 }) do
		for z = 16, City.WIDTH - 16, 12 do
			table.insert(plan.trees, { x = x + City.ROAD_HALF + City.SIDEWALK / 2, z = z, size = 0.9 })
			table.insert(plan.trees, { x = x - City.ROAD_HALF - City.SIDEWALK / 2, z = z + 6, size = 0.9 })
		end
	end
	for _, z in ipairs({ 49 }) do
		for x = 16, City.WIDTH - 16, 12 do
			table.insert(plan.trees, { x = x, z = z + City.ROAD_HALF + City.SIDEWALK / 2, size = 0.9 })
		end
	end

	-- Ceinture boisée : deux rangées serrées autour de la carte. Elles cachent
	-- le bord du sol depuis la caméra isométrique. Un RNG distinct garantit que
	-- l'ajout de la ceinture ne décale pas la ville existante.
	local beltRng = Rng.new((seed or 20261117) + 977)
	local inner = City.OUTSKIRTS * 0.35
	local outer = City.OUTSKIRTS * 0.72
	for x = 3, City.WIDTH - 3, City.BELT_TREE_STEP do
		for _, z in ipairs({ -inner, -outer, City.WIDTH + inner, City.WIDTH + outer }) do
			table.insert(plan.trees, {
				x = x + beltRng:integer(-2, 2),
				z = z + beltRng:integer(-1, 1),
				size = beltRng:integer(12, 17) / 10,
			})
		end
	end
	for z = 6, City.WIDTH - 6, City.BELT_TREE_STEP do
		for _, x in ipairs({ -inner, -outer, City.WIDTH + inner, City.WIDTH + outer }) do
			table.insert(plan.trees, {
				x = x + beltRng:integer(-1, 1),
				z = z + beltRng:integer(-2, 2),
				size = beltRng:integer(12, 17) / 10,
			})
		end
	end

	for column = 1, #City.AVENUES - 1 do
		for row = 1, #City.STREETS - 1 do
			local block = blockBounds(column, row)
			local isBarracks = column == BARRACKS_BLOCK[1] and row == BARRACKS_BLOCK[2]
			local poi = poiForBlock(column, row)
			local kind = "habitat"
			if isBarracks then
				kind = "caserne"
			elseif poi then
				kind = poi.style
			elseif column == 3 and row == 1 then
				kind = "parc"
			elseif column == 2 and row == 3 then
				kind = "place"
			end

			local record = {
				column = column,
				row = row,
				x0 = block.x0,
				z0 = block.z0,
				x1 = block.x1,
				z1 = block.z1,
				kind = kind,
				name = poi and poi.name or nil,
			}
			table.insert(plan.blocks, record)

			if kind == "parc" then
				table.insert(plan.parks, { x0 = block.x0, z0 = block.z0, x1 = block.x1, z1 = block.z1, name = "Parc municipal" })
				addTrees(plan.trees, block, rng, 7)
			elseif kind == "place" then
				table.insert(plan.parks, { x0 = block.x0, z0 = block.z0, x1 = block.x1, z1 = block.z1, name = "Place du marché", paved = true })
				for _, parcel in ipairs(parcelsOf(block)) do
					if rng:integer(1, 10) <= 3 then
						addBuilding(plan.buildings, parcel, rng, "commerce", rng:integer(1, 3))
					end
				end
			elseif kind == "caserne" then
				-- Bâtiment au nord du bloc, cour et stationnement au sud.
				local building = {
					x0 = block.x0 + 0.4,
					x1 = block.x1 - 0.4,
					z0 = block.z0 + 0.4,
					z1 = block.z0 + 6.4,
					floors = 2,
					style = "caserne",
					facade = { 156, 58, 48 },
					facadeName = "brique rouge",
				}
				table.insert(plan.buildings, building)
				plan.barracks = {
					x0 = block.x0,
					z0 = block.z0,
					x1 = block.x1,
					z1 = block.z1,
					building = building,
					apronZ0 = block.z0 + 6.6,
					apronZ1 = block.z1,
				}
				-- Huit places numérotées, deux rangées de quatre.
				for index = 1, 8 do
					local columnIndex = (index - 1) % 4
					local rowIndex = math.floor((index - 1) / 4)
					table.insert(plan.bays, {
						id = index,
						x = block.x0 + 2.2 + columnIndex * 3.4,
						z = block.z0 + 8.6 + rowIndex * 3.6,
						heading = 0,
					})
				end
			elseif poi then
				local building = {
					x0 = block.x0 + 1,
					x1 = block.x1 - 1,
					z0 = block.z0 + 1,
					z1 = block.z1 - 1,
					floors = poi.floors,
					style = poi.style,
					facade = { 168, 176, 180 },
					facadeName = poi.id,
				}
				table.insert(plan.buildings, building)
				table.insert(plan.pois, {
					id = poi.id,
					name = poi.name,
					x = (block.x0 + block.x1) / 2,
					z = (block.z0 + block.z1) / 2,
					style = poi.style,
				})
			else
				for _, parcel in ipairs(parcelsOf(block)) do
					if rng:integer(1, 10) <= 7 then
						addBuilding(plan.buildings, parcel, rng)
					end
				end
			end
		end
	end

	return plan
end

-- Position d'une place de stationnement (1..8) en unités de carte.
function City.bayPosition(plan: any, index: number): any?
	if not plan.bays or #plan.bays == 0 then
		return nil
	end
	return plan.bays[((index - 1) % #plan.bays) + 1]
end

return City
