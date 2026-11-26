--!strict
--[[
	SceneService — construit la ville 3D à partir du plan partagé `City`.

	Le plan (`Shared/City`) décrit les rues, les blocs, les immeubles et la
	caserne en unités de carte. Ce service ne fait que le traduire en pièces
	Roblox : aucune coordonnée de ville n'est écrite ici, donc la 3D et la
	mini-carte restent forcément d'accord.

	La scène est reconstruite à chaque démarrage (idempotent) et ne contient
	aucun asset externe : tout est généré par code.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local City = require(Shared:WaitForChild("City"))
local Rng = require(Shared:WaitForChild("Utilities"):WaitForChild("Rng"))
local Services = game:GetService("ServerScriptService"):WaitForChild("ERS"):WaitForChild("Services")
local Architecture = require(Services:WaitForChild("Architecture"))

local SceneService = {}

-- Couleur depuis une palette RGB 0-255.
local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function makePart(parent: any, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Pièce décorative : ne bloque pas les déplacements (marquages, vitres, props).
local function decoration(parent: any, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?, transparency: number?): Part
	local part = makePart(parent, name, size, position, color, material)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	if transparency then
		part.Transparency = transparency
	end
	return part
end

local function label(part: any, text: string, offset: number): any
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Etiquette"
	billboard.Size = UDim2.fromScale(11, 2.6)
	billboard.StudsOffset = Vector3.new(0, offset, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 900
	billboard.Parent = part

	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = text
	textLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	textLabel.TextStrokeTransparency = 0.4
	textLabel.TextScaled = true
	textLabel.Font = Enum.Font.GothamBold
	textLabel.Parent = billboard
	return billboard
end

-- ── Voirie ────────────────────────────────────────────────────

local function buildRoads(scene: any, plan: any, scale: number): ()
	local roads = Instance.new("Folder")
	roads.Name = "Voirie"
	roads.Parent = scene

	-- Découpe les rubans aux carrefours : une seule face visible par zone.
	local function ribbon(parent: any, name: string, strip: any, height: number, bottom: number, cuts: boolean, margin: number, color: Color3, material: Enum.Material)
		local avenue = strip.axis == "avenue"
		local first, last = avenue and strip.z0 or strip.x0, avenue and strip.z1 or strip.x1
		local intervals = {}
		if cuts then
			for _, cross in ipairs(plan.roads) do
				if (cross.axis == "avenue") ~= avenue then
					local center = avenue and cross.z or cross.x
					table.insert(intervals, {center - cross.width / 2 - margin, center + cross.width / 2 + margin})
				end
			end
		end
		table.sort(intervals, function(a, b) return a[1] < b[1] end)
		local segment = 0
		local function emit(start: number, finish: number)
			if finish <= start then return end
			segment += 1
			local length, center = (finish - start) * scale, (start + finish) / 2 * scale
			local size = avenue and Vector3.new(strip.width * scale, height, length) or Vector3.new(length, height, strip.width * scale)
			local position = avenue and Vector3.new(strip.x * scale, bottom + height / 2, center)
				or Vector3.new(center, bottom + height / 2, strip.z * scale)
			makePart(parent, name .. "_" .. segment, size, position, color, material)
		end
		local cursor = first
		for _, interval in ipairs(intervals) do
			emit(cursor, math.min(last, interval[1]))
			cursor = math.max(cursor, interval[2])
		end
		emit(cursor, last)
	end
	for index, road in ipairs(plan.roads) do
		ribbon(roads, (road.axis == "avenue" and "Avenue_" or "Rue_") .. index,
			road, 0.2, 0.02, road.axis ~= "avenue", 0, Color3.fromRGB(54, 55, 60), Enum.Material.Asphalt)
	end

	local sidewalks = Instance.new("Folder")
	sidewalks.Name = "Trottoirs"
	sidewalks.Parent = scene
	for index, walk in ipairs(plan.sidewalks) do
		-- Les avenues possèdent les coins ; les rues s'arrêtent avant ces coins.
		ribbon(sidewalks, "Trottoir_" .. index, walk, 0.37, 0, true,
			walk.axis == "avenue" and 0 or City.SIDEWALK, Color3.fromRGB(144, 142, 136), Enum.Material.Concrete)
	end
end

local function onIntersection(value: number, spacing: number): boolean
	for _, road in ipairs(City.AVENUES) do
		if math.abs(value - road) < spacing then
			return true
		end
	end
	return false
end

local function buildMarkings(scene: any, plan: any, scale: number): ()
	local markings = Instance.new("Folder")
	markings.Name = "Marquages"
	markings.Parent = scene

	local white = Color3.fromRGB(214, 210, 194)

	-- Lignes axiales discontinues, interrompues aux carrefours.
	for index, road in ipairs(plan.roads) do
		if road.axis == "avenue" then
			local z = 2
			while z < City.WIDTH do
				if not onIntersection(z, 4) then
					decoration(markings, "AxeA_" .. index .. "_" .. z, Vector3.new(0.22 * scale, 0.04, 1.7 * scale),
						Vector3.new(road.x * scale, 0.24, z * scale), white, Enum.Material.SmoothPlastic)
				end
				z += 3.4
			end
		else
			local x = 2
			while x < City.WIDTH do
				if not onIntersection(x, 4) then
					decoration(markings, "AxeR_" .. index .. "_" .. x, Vector3.new(1.7 * scale, 0.04, 0.22 * scale),
						Vector3.new(x * scale, 0.24, road.z * scale), white, Enum.Material.SmoothPlastic)
				end
				x += 3.4
			end
		end
	end

	-- Passages piétons : bandes parallèles à l'axe traversé.
	for index, crossing in ipairs(plan.crossings) do
		for stripe = -2, 2 do
			if crossing.axis == "avenue" then
				decoration(markings, "Passage_" .. index .. "_" .. stripe, Vector3.new(0.5 * scale, 0.04, crossing.width * scale),
					Vector3.new((crossing.x + stripe * 0.85) * scale, 0.24, crossing.z * scale), white, Enum.Material.SmoothPlastic, 0.1)
			else
				decoration(markings, "Passage_" .. index .. "_" .. stripe, Vector3.new(crossing.width * scale, 0.04, 0.5 * scale),
					Vector3.new(crossing.x * scale, 0.24, (crossing.z + stripe * 0.85) * scale), white, Enum.Material.SmoothPlastic, 0.1)
			end
		end
	end
end

-- ── Bâtiments ─────────────────────────────────────────────────

local function materialFor(style: string): Enum.Material
	if style == "caserne" then
		return Enum.Material.Brick
	elseif style == "industrie" then
		return Enum.Material.CorrodedMetal
	elseif style == "public" then
		return Enum.Material.Concrete
	end
	return Enum.Material.Concrete
end

-- Fenêtres : un motif lisible à distance, sans multiplier les pièces.
local function addFacadeWindows(parent: any, building: any, box: any, scale: number, floors: number, floorHeight: number): ()
	local width = (building.x1 - building.x0) * scale
	local depth = (building.z1 - building.z0) * scale
	local visibleFloors = math.min(floors, 4)
	local windowColor = Color3.fromRGB(46, 60, 74)

	for floor = 1, visibleFloors do
		local y = (floor - 1) * floorHeight + floorHeight * 0.6
		for column = -1, 1, 2 do
			-- Façade sud (vers la caméra).
			decoration(parent, "Vitre_S_" .. floor .. "_" .. column, Vector3.new(1.7, 1.6, 0.2),
				Vector3.new(box.centerX + column * width * 0.24, y, box.zMax + 0.12), windowColor, Enum.Material.Glass, 0.15)
			-- Façade est.
			decoration(parent, "Vitre_E_" .. floor .. "_" .. column, Vector3.new(0.2, 1.6, 1.7),
				Vector3.new(box.xMax + 0.12, y, box.centerZ + column * depth * 0.24), windowColor, Enum.Material.Glass, 0.15)
		end
	end

	-- Porte d'entrée au rez-de-chaussée, côté sud.
	decoration(parent, "Porte", Vector3.new(2.6, 3.4, 0.25),
		Vector3.new(box.centerX, 1.7, box.zMax + 0.16), Color3.fromRGB(58, 48, 42), Enum.Material.WoodPlanks)
end

local function buildBuildings(scene: any, plan: any, scale: number, config: any): ()
	local folder = Instance.new("Folder")
	folder.Name = "Batiments"
	folder.Parent = scene

	for index, building in ipairs(plan.buildings) do
		local xMin, xMax = building.x0 * scale, building.x1 * scale
		local zMin, zMax = building.z0 * scale, building.z1 * scale
		local floors = building.floors
		local height = floors * config.FLOOR_HEIGHT
		local width = xMax - xMin
		local depth = zMax - zMin
		local centerX = (xMin + xMax) / 2
		local centerZ = (zMin + zMax) / 2

		if building.style == "caserne" then
			continue -- La remise et sa tour sont construites avec leur parvis.
		elseif building.style == "eglise" then
			Architecture.church(folder, decoration, centerX, centerZ, width, depth, height)
			continue
		end

		makePart(
			folder,
			"Batiment_" .. index,
			Vector3.new(width, height, depth),
			Vector3.new(centerX, height / 2, centerZ),
			rgb(building.facade),
			materialFor(building.style)
		)

		-- Toiture légèrement débordante.
		decoration(folder, "Toit_" .. index, Vector3.new(width + 1.6, 0.7, depth + 1.6),
			Vector3.new(centerX, height + 0.35, centerZ), Color3.fromRGB(74, 70, 66), Enum.Material.Slate)

		-- Bandeau de corniche.
		decoration(folder, "Corniche_" .. index, Vector3.new(width + 0.8, 0.35, depth + 0.8),
			Vector3.new(centerX, height - 0.2, centerZ), rgb(building.facade), Enum.Material.Concrete)

		addFacadeWindows(folder, building, {
			centerX = centerX,
			centerZ = centerZ,
			xMax = xMax,
			zMax = zMax,
		}, scale, floors, config.FLOOR_HEIGHT)
		Architecture.detail(folder, decoration, building, centerX, centerZ, width, depth, height, index)
	end
end

-- ── Mobilier urbain ───────────────────────────────────────────

local function buildFurniture(scene: any, plan: any, scale: number, config: any): ()
	local folder = Instance.new("Folder")
	folder.Name = "Mobilier"
	folder.Parent = scene

	-- Arbres : tronc + houppier.
	for index, tree in ipairs(plan.trees) do
		local size = tree.size or 1
		decoration(folder, "Tronc_" .. index, Vector3.new(0.8 * size, 5 * size, 0.8 * size),
			Vector3.new(tree.x * scale, 2.5 * size, tree.z * scale), Color3.fromRGB(84, 62, 44), Enum.Material.Wood, 0)
		local crown = decoration(folder, "Houppier_" .. index,
			Vector3.new(6 * size, 6 * size, 6 * size),
			Vector3.new(tree.x * scale, 6.6 * size, tree.z * scale), Color3.fromRGB(58, 104, 58), Enum.Material.Grass, 0)
		crown.Shape = Enum.PartType.Ball
	end

	-- Lampadaires.
	local metal = Color3.fromRGB(98, 102, 108)
	for index, light in ipairs(plan.streetlights) do
		decoration(folder, "Mat_" .. index, Vector3.new(0.3, 9, 0.3),
			Vector3.new(light.x * scale, 4.5, light.z * scale), metal, Enum.Material.Metal)
		decoration(folder, "Bras_" .. index, Vector3.new(2.6, 0.22, 0.22),
			Vector3.new(light.x * scale + light.side * 1.3, 8.9, light.z * scale), metal, Enum.Material.Metal)
		local bulb = decoration(folder, "Lampe_" .. index, Vector3.new(1.4, 0.3, 0.6),
			Vector3.new(light.x * scale + light.side * 2.4, 8.7, light.z * scale),
			Color3.fromRGB(236, 224, 180), Enum.Material.Neon)
		-- Allumée par `LightingService` à la tombée du jour.
		local glow = Instance.new("PointLight")
		glow.Name = "Eclairage"
		glow.Enabled = false
		glow.Brightness = config and config.LIGHTING_LAMP_BRIGHTNESS or 1.4
		glow.Range = config and config.LIGHTING_LAMP_RANGE or 26
		glow.Color = config and config.LIGHTING_LAMP_COLOR or Color3.fromRGB(255, 214, 150)
		glow.Shadows = false
		glow.Parent = bulb
	end

	-- Feux tricolores.
	for index, signal in ipairs(plan.trafficLights) do
		decoration(folder, "FeuMat_" .. index, Vector3.new(0.28, 7, 0.28),
			Vector3.new(signal.x * scale, 3.5, signal.z * scale), metal, Enum.Material.Metal)
		decoration(folder, "FeuBoitier_" .. index, Vector3.new(0.9, 2.2, 0.7),
			Vector3.new(signal.x * scale, 6.4, signal.z * scale), Color3.fromRGB(40, 42, 44), Enum.Material.SmoothPlastic)
		decoration(folder, "FeuRouge_" .. index, Vector3.new(0.42, 0.42, 0.2),
			Vector3.new(signal.x * scale, 6.9, signal.z * scale + 0.38), Color3.fromRGB(200, 52, 44), Enum.Material.Neon)
		decoration(folder, "FeuVert_" .. index, Vector3.new(0.42, 0.42, 0.2),
			Vector3.new(signal.x * scale, 5.9, signal.z * scale + 0.38), Color3.fromRGB(70, 190, 96), Enum.Material.Neon)
	end
end

-- ── Sol, blocs, caserne ───────────────────────────────────────

local function buildGround(scene: any, plan: any, scale: number, config: any): ()
	local outskirts = City.OUTSKIRTS or 0
	local size = (City.WIDTH + outskirts * 2) * scale

	-- Le sol s'arrête à la ceinture boisée : plus de dalle géante qui déborde
	-- de la carte et laisse voir son bord sous l'horizon.
	local ground = makePart(scene, "Sol", Vector3.new(size, 2, size),
		Vector3.new(City.WIDTH * scale / 2, -1, City.WIDTH * scale / 2), config.GROUND_COLOR, Enum.Material.Grass)
	ground.Name = "Sol"

	local lots = Instance.new("Folder")
	lots.Name = "Ilots"
	lots.Parent = scene

	for index, block in ipairs(plan.blocks) do
		local width = (block.x1 - block.x0) * scale
		local depth = (block.z1 - block.z0) * scale
		local centerX = (block.x0 + block.x1) / 2 * scale
		local centerZ = (block.z0 + block.z1) / 2 * scale
		local color = Color3.fromRGB(132, 130, 124)
		if block.kind == "parc" then
			color = Color3.fromRGB(64, 100, 62)
		elseif block.kind == "place" then
			color = Color3.fromRGB(146, 138, 120)
		end
		makePart(lots, "Ilot_" .. index, Vector3.new(width, 0.3, depth),
			Vector3.new(centerX, 0.15, centerZ), color, Enum.Material.Slate)
	end
end

-- Ceinture : chemin de gravier et haie basse au bord du sol. Ils donnent une
-- limite lisible à la ville et masquent la transition avec le ciel.
local function buildOutskirts(scene: any, scale: number, config: any): ()
	local folder = Instance.new("Folder")
	folder.Name = "Ceinture"
	folder.Parent = scene

	local center = City.WIDTH / 2 * scale
	local half = (City.WIDTH / 2 + City.OUTSKIRTS) * scale
	local pathHalf = half - 4.5 * scale
	local pathWidth = 2.2 * scale
	local hedgeAt = half - 1.6 * scale

	local pathColor = config and config.PATH_COLOR or Color3.fromRGB(150, 140, 120)
	local hedgeColor = config and config.HEDGE_COLOR or Color3.fromRGB(54, 82, 54)

	for _, side in ipairs({ -1, 1 }) do
		makePart(folder, "Chemin_NordSud_" .. side, Vector3.new(pathWidth, 0.12, half * 2),
			Vector3.new(center + side * pathHalf, 0.06, center), pathColor, Enum.Material.Ground)
		makePart(folder, "Chemin_EstOuest_" .. side, Vector3.new(half * 2, 0.12, pathWidth),
			Vector3.new(center, 0.06, center + side * pathHalf), pathColor, Enum.Material.Ground)
		makePart(folder, "Haie_NordSud_" .. side, Vector3.new(1.6 * scale, 1.8, half * 2),
			Vector3.new(center + side * hedgeAt, 0.9, center), hedgeColor, Enum.Material.Grass)
		makePart(folder, "Haie_EstOuest_" .. side, Vector3.new(half * 2, 1.8, 1.6 * scale),
			Vector3.new(center, 0.9, center + side * hedgeAt), hedgeColor, Enum.Material.Grass)
	end
end

-- Ciel procédural : une voûte d'étoiles et une lune, éteintes le jour. Aucun
-- asset : les positions viennent du même RNG déterministe que la ville.
local function buildSky(scene: any, scale: number, config: any): ()
	local folder = Instance.new("Folder")
	folder.Name = "Ciel"
	folder.Parent = scene

	local center = City.WIDTH / 2 * scale
	local radius = config and config.SKY_RADIUS or 1400
	local count = config and config.SKY_STARS or 220
	local minSize = config and config.SKY_STAR_MIN or 14
	local maxSize = config and config.SKY_STAR_MAX or 26
	local rng = Rng.new((config and config.CITY_SEED or 20261117) + 1301)
	local white = Color3.fromRGB(236, 240, 250)

	for index = 1, count do
		local azimuth = rng:float() * math.pi * 2
		local elevation = math.rad(9 + rng:float() * 68)
		local horizontal = radius * math.cos(elevation)
		local starSize = rng:integer(minSize, maxSize)
		local star = decoration(folder, "Etoile_" .. index,
			Vector3.new(starSize, starSize, starSize),
			Vector3.new(
				center + math.cos(azimuth) * horizontal,
				radius * math.sin(elevation),
				center + math.sin(azimuth) * horizontal
			), white, Enum.Material.Neon, 1)
		star.Shape = Enum.PartType.Ball
		star.CastShadow = false
	end

	local moonSize = config and config.SKY_MOON_SIZE or 80
	local moon = decoration(folder, "Lune", Vector3.new(moonSize, moonSize, moonSize),
		Vector3.new(center - radius * 0.62, radius * 0.58, center - radius * 0.48),
		Color3.fromRGB(232, 234, 226), Enum.Material.Neon, 1)
	moon.Shape = Enum.PartType.Ball
	moon.CastShadow = false
end

local function buildBarracks(scene: any, plan: any, scale: number, config: any): ()
	local barracks = plan.barracks
	if not barracks then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Caserne"
	folder.Parent = scene

	local x0, x1 = barracks.x0 * scale, barracks.x1 * scale
	local z0, z1 = barracks.z0 * scale, barracks.z1 * scale
	local centerX = (x0 + x1) / 2
	local width = x1 - x0

	-- Parvis en asphalte clair.
	makePart(folder, "Parvis", Vector3.new(width, 0.24, (barracks.apronZ1 - barracks.apronZ0) * scale),
		Vector3.new(centerX, 0.24, (barracks.apronZ0 + barracks.apronZ1) / 2 * scale),
		Color3.fromRGB(86, 88, 92), Enum.Material.Asphalt)

	-- Marquage des huit places.
	local white = Color3.fromRGB(222, 218, 200)
	for _, bay in ipairs(plan.bays) do
		local bx = bay.x * scale
		local bz = bay.z * scale
		decoration(folder, "Place_" .. bay.id .. "_G", Vector3.new(0.2, 0.06, 4.2 * scale),
			Vector3.new(bx - 1.5 * scale, 0.38, bz), white, Enum.Material.SmoothPlastic)
		decoration(folder, "Place_" .. bay.id .. "_D", Vector3.new(0.2, 0.06, 4.2 * scale),
			Vector3.new(bx + 1.5 * scale, 0.38, bz), white, Enum.Material.SmoothPlastic)
		decoration(folder, "Place_" .. bay.id .. "_F", Vector3.new(3.2 * scale, 0.06, 0.2),
			Vector3.new(bx, 0.38, bz - 2.1 * scale), white, Enum.Material.SmoothPlastic)
	end

	-- Bâtiment de la caserne, avec ses portes de remise.
	local building = barracks.building
	local bx0, bx1 = building.x0 * scale, building.x1 * scale
	local bz0, bz1 = building.z0 * scale, building.z1 * scale
	local height = 7.2
	makePart(folder, "Batiment_Caserne", Vector3.new(bx1 - bx0, height, bz1 - bz0),
		Vector3.new((bx0 + bx1) / 2, height / 2, (bz0 + bz1) / 2),
		Color3.fromRGB(152, 58, 48), Enum.Material.Brick)
	decoration(folder, "Toit_Caserne", Vector3.new(bx1 - bx0 + 1.6, 0.6, bz1 - bz0 + 1.6),
		Vector3.new((bx0 + bx1) / 2, height + 0.3, (bz0 + bz1) / 2),
		Color3.fromRGB(66, 42, 40), Enum.Material.Slate)

	for door = 0, 3 do
		local doorX = bx0 + 6 + door * (bx1 - bx0 - 12) / 3
		decoration(folder, "Remise_" .. door, Vector3.new(7.6, 5.2, 0.3),
			Vector3.new(doorX, 2.7, bz1 + 0.16),
			Color3.fromRGB(58, 52, 50), Enum.Material.Metal)
		for panel = 1, 4 do
			decoration(folder, "SectionRemise", Vector3.new(7.5, panel == 3 and 0.70 or 0.10, 0.14),
				Vector3.new(doorX, 0.35 + panel, bz1 + 0.35), Color3.fromRGB(112, 135, 145), Enum.Material.Metal)
		end
	end
	local towerX, towerZ = bx0 + 6, bz0 + 5
	makePart(folder, "TourDeSechage", Vector3.new(8, 18, 8), Vector3.new(towerX, 9, towerZ),
		Color3.fromRGB(154, 85, 65), Enum.Material.Brick)
	for level = 1, 3 do
		decoration(folder, "OuvertureTour", Vector3.new(3.1, 2.25, 0.15), Vector3.new(towerX, 7 + level * 3, towerZ + 4.1),
			Color3.fromRGB(60, 68, 72), Enum.Material.Metal)
	end

	-- Bandeau « CASERNE » au-dessus des remises.
	local sign = Instance.new("Part")
	sign.Name = "Enseigne"
	sign.Anchored = true
	sign.CanCollide = false
	sign.Size = Vector3.new(12, 2, 0.3)
	sign.Position = Vector3.new((bx0 + bx1) / 2, 6.2, bz1 + 0.3)
	sign.Color = Color3.fromRGB(30, 32, 36)
	sign.Material = Enum.Material.SmoothPlastic
	sign.Parent = folder
	label(sign, "CASERNE", 1.6)

	-- Mât et drapeau, repère visuel depuis la caméra.
	decoration(folder, "MatDrapeau", Vector3.new(0.3, 12, 0.3),
		Vector3.new(x0 + 1.5, 6, z0 + 1.5), Color3.fromRGB(200, 200, 200), Enum.Material.Metal)
	decoration(folder, "Drapeau", Vector3.new(3.4, 2, 0.2),
		Vector3.new(x0 + 3.3, 10.6, z0 + 1.5), Color3.fromRGB(58, 90, 176), Enum.Material.Fabric)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn_Caserne"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = Vector3.new(centerX, 0.7, barracks.apronZ1 * scale + 2)
	spawn.Color = Color3.fromRGB(220, 220, 220)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder

	-- Repère du PC sur la mini-carte et la caméra.
	local beacon = Instance.new("Part")
	beacon.Name = "PC_Marqueur"
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.Transparency = 1
	beacon.Size = Vector3.new(1, 1, 1)
	beacon.Position = Vector3.new(centerX, height + 6, (bz0 + bz1) / 2)
	beacon.Parent = folder

	-- Les étiquettes de la caserne sont posées même si `config` change de place.
end

local function buildPoi(scene: any, plan: any, scale: number): ()
	local folder = Instance.new("Folder")
	folder.Name = "PointsInteret"
	folder.Parent = scene

	for index, poi in ipairs(plan.pois) do
		local marker = makePart(folder, "POI_" .. poi.id, Vector3.new(1, 1, 1),
			Vector3.new(poi.x * scale, 22, poi.z * scale), Color3.fromRGB(240, 240, 240), Enum.Material.Neon)
		marker.Transparency = 1
		marker.CanCollide = false
		label(marker, poi.name, 1.5)
		marker.Name = "POI_" .. index .. "_" .. poi.id
	end
end

-- Construit la scène complète dans `workspace`. Idempotent.
function SceneService.build(config: any, workspace: any): any
	local previous = workspace:FindFirstChild("ERS_Scene")
	if previous then
		previous:Destroy()
	end

	local scene = Instance.new("Folder")
	scene.Name = "ERS_Scene"
	scene.Parent = workspace

	local plan = City.build(config.CITY_SEED)
	local scale = config.WORLD_SCALE

	buildGround(scene, plan, scale, config)
	buildRoads(scene, plan, scale)
	buildMarkings(scene, plan, scale)
	buildBuildings(scene, plan, scale, config)
	buildBarracks(scene, plan, scale, config)
	buildFurniture(scene, plan, scale, config)
	buildOutskirts(scene, scale, config)
	buildSky(scene, scale, config)
	buildPoi(scene, plan, scale)

	return scene
end

-- Plan utilisé par la scène (exposé pour les tests et la mini-carte).
function SceneService.plan(config: any): any
	return City.build(config.CITY_SEED)
end

return SceneService
