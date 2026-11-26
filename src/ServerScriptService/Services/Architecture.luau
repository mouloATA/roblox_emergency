--!strict
-- Volumes originaux des repères urbains. Les dimensions viennent des parcelles.
local Architecture = {}
local V, rgb = Vector3.new, Color3.fromRGB
local stone, slate = rgb(192, 179, 153), rgb(69, 78, 88)
local steel, glass = rgb(128, 139, 145), rgb(58, 87, 106)

-- Deux versants avec faîtage longitudinal. Les pignons ferment le volume.
local function roof(parent: Instance, name: string, x: number, y: number, z: number, w: number, rise: number, depth: number, color: Color3): ()
	for _, side in ipairs({-1, 1}) do
		local wedge = Instance.new("WedgePart")
		wedge.Name = name
		wedge.Size = V(depth, rise, w / 2)
		wedge.Position = V(x + side * w / 4, y + rise / 2, z)
		wedge.Orientation = V(0, -side * 90, 0)
		wedge.Color, wedge.Material = color, Enum.Material.Slate
		wedge.Anchored, wedge.CanCollide, wedge.CanTouch, wedge.CanQuery = true, false, false, false
		wedge.Parent = parent
	end
end

-- La nef, le transept et le clocher occupent la même parcelle que le POI.
function Architecture.church(parent: Instance, decor: any, x: number, z: number, w: number, d: number, h: number): ()
	local naveWidth, length = w * 0.37, d * 0.83
	local function block(name: string, width: number, height: number, depth: number, px: number, base: number, pz: number, color: Color3)
		return decor(parent, name, V(width, height, depth), V(px, base + height / 2, pz), color, Enum.Material.Concrete)
	end
	local nave = block("Nef", naveWidth, h, length, x, 0, z, stone)
	nave.CanCollide, nave.CanQuery = true, true
	roof(parent, "ToitNef", x, h, z, naveWidth + 1.1, h * 0.40, length + 1.2, slate)
	local transept = block("Transept", w * 0.70, h * 0.65, d * 0.20, x, 0, z - d * 0.11, stone)
	transept.CanCollide, transept.CanQuery = true, true
	roof(parent, "ToitTransept", x, h * 0.65, z - d * 0.11, w * 0.71, 2.65, d * 0.22, slate)
	for _, side in ipairs({-1, 1}) do
		local wall = x + side * naveWidth / 2
		for bay = -2, 2 do
			local pz = z + bay * length * 0.16
			block("Contrefort", 1.75, h * 0.8, 1.1, wall, 0, pz - length * 0.06, stone)
			decor(parent, "Vitre_Vitrail", V(0.21, h * 0.44, 2.3), V(wall + side * 0.12, h * 0.64, pz), glass, Enum.Material.Glass, 0.12)
		end
	end
	local towerZ, towerW, towerH = z + length * 0.41, naveWidth * 0.54, h * 1.85
	local tower = block("Clocher", towerW, towerH, towerW, x, 0, towerZ, stone)
	tower.CanCollide, tower.CanQuery = true, true
	roof(parent, "Fleche", x, towerH, towerZ, towerW + 1.1, towerW * 0.85, towerW + 1.1, slate)
	local faceZ = towerZ + towerW / 2 + 0.14
	block("Portail", towerW * 0.52, 5.3, 0.35, x, 0, faceZ, rgb(83, 65, 53))
	for _, side in ipairs({-1, 1}) do
		block("AbatSon", 1.12, 2.86, 0.32, x + side * 1.11, towerH - 3.78, faceZ, slate)
	end
	local clock = decor(parent, "CadranClocher", V(0.27, 3.25, 3.25), V(x, towerH - 6.5, faceZ), rgb(225, 220, 195), Enum.Material.SmoothPlastic)
	clock.Shape, clock.Orientation = Enum.PartType.Cylinder, V(0, 90, 0)
	block("Aiguille", 0.13, 1.09, 0.18, x, towerH - 6.50, faceZ + 0.20, slate)
	block("AiguilleCourte", 0.75, 0.15, 0.18, x + 0.36, towerH - 6.59, faceZ + 0.20, slate)
end

-- Donne une silhouette et des équipements propres à la fonction du bâtiment.
function Architecture.detail(parent: Instance, decor: any, b: any, x: number, z: number, w: number, d: number, h: number, index: number): ()
	local face, kind = z + d / 2, b.facadeName
	local function item(name: string, width: number, height: number, depth: number, px: number, py: number, pz: number, color: Color3, material: Enum.Material?)
		return decor(parent, name, V(width, height, depth), V(px, py, pz), color, material or Enum.Material.Concrete)
	end
	if kind == "industrie" then
		for i = 1, 2 do
			local px = x + (i - 1.5) * w * 0.33
			local chimney = item("ChemineeUsine", 11, 2.8, 2.8, px, h + 5.5, z - d * 0.24, rgb(141, 93, 71), Enum.Material.Brick)
			chimney.Shape, chimney.Orientation = Enum.PartType.Cylinder, V(0, 0, 90)
			item("Quai", w * 0.25, 1.15, 3.6, px, 0.57, face + 1.7, steel)
			item("PorteQuai", w * 0.20, 4.1, 0.35, px, 2.8, face + 0.25, slate, Enum.Material.Metal)
		end
	elseif kind == "hopital" then
		item("AuventUrgences", w * 0.48, 0.62, 5.5, x, 4.8, face + 2.1, rgb(91, 138, 149))
		for _, side in ipairs({-1, 1}) do
			item("PilierUrgences", 0.65, 4.5, 0.65, x + side * w * 0.22, 2.25, face + 4.3, steel)
			item("LocalTechnique", w * 0.20, 2.5, d * 0.20, x + side * w * 0.26, h + 1.65, z, steel, Enum.Material.Metal)
			item("H_Hopital", 1.0, 5.4, 0.45, x + side * 1.35, h - 3.8, face + 0.40, rgb(51, 117, 163))
		end
		item("H_Hopital", 2.4, 0.9, 0.45, x, h - 3.8, face + 0.40, rgb(51, 117, 163))
	elseif kind == "gare" or kind == "ecole" or kind == "commissariat" then
		local wRoof = kind == "gare" and w * 0.76 or w * 0.33
		local tint = kind == "ecole" and rgb(152, 108, 79) or slate
		roof(parent, "Fronton", x, h + 0.7, face - d * 0.18, wRoof, 3.2, d * 0.37, tint)
		item("Marquise", wRoof, 0.40, 3.8, x, 4.1, face + 1.5, glass, Enum.Material.Glass)
		for i = -1, 1 do
			item("Colonnes", 0.55, 4, 0.55, x + i * wRoof * 0.44, 2, face + 3, steel)
		end
	elseif b.style == "commerce" then
		for i = -2, 2 do
			item("Store", w / 6, 0.23, 2.65, x + i * w / 6, 3.68, face + 1.1,
				i % 2 == 0 and rgb(118, 72, 63) or rgb(216, 199, 169), Enum.Material.Fabric).Orientation = V(11, 0, 0)
		end
	else
		roof(parent, "Combles", x, h + 0.68, z, w + 1.4, math.min(4.4, w * 0.14), d + 1.2, index % 2 == 0 and slate or rgb(132, 86, 66))
		item("Souche", 1.65, 3.6, 1.65, x + w * 0.29, h + 3.1, z + d * 0.20, rgb(136, 88, 70), Enum.Material.Brick)
		for floor = 1, math.min(3, b.floors - 1) do
			local y = floor * h / b.floors
			item("Balcon", w * 0.64, 0.29, 1.9, x, y, face + 0.76, stone)
			item("GardeCorps", w * 0.64, 0.80, 0.14, x, y + 0.68, face + 1.62, steel, Enum.Material.Metal)
		end
	end
end

return Architecture
