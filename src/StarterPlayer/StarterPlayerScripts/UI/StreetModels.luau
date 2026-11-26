--!strict
-- Modèles originaux en coordonnées locales, face avant vers -Z.
local StreetModels = {}
local V = Vector3.new
local rgb = Color3.fromRGB
local steel, rubber, glass = rgb(165, 176, 182), rgb(30, 33, 35), rgb(57, 82, 97)
local white, blue, red = rgb(229, 234, 230), rgb(47, 111, 250), rgb(191, 49, 36)
local paint = {
	fire = red, medical = white, police = rgb(43, 64, 92), technical = rgb(215, 157, 53),
	logistics = rgb(175, 73, 46), command = rgb(171, 54, 43),
}
local shapes = {
	EPA = "ladder", BEA = "boom", CCF = "tanker", CCGC = "tanker",
	VSAV = "ambulance", AMBULANCE = "ambulance", UMH = "ambulance", VSS = "ambulance",
	FPT = "pumper", FPTL = "pumper", FPTSR = "pumper", VSR = "pumper", VPI = "pumper",
	VPC = "radio", VTRANS = "radio", MOTO = "motorcycle",
	VLM = "sedan", VMED = "sedan", VLI = "sedan", VL_COS = "sedan", VL_GROUPE = "sedan",
	VLIAISON = "sedan", VL_POLICE = "sedan", VRI = "sedan",
}

local function part(model: Model, name: string, size: Vector3, x: number, y: number, z: number,
	color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size, p.Position = size, V(x, y, z)
	p.Color, p.Material = color, material or Enum.Material.SmoothPlastic
	p.Shape = shape or Enum.PartType.Block
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function newModel(parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.WorldPivot = CFrame.new(0, 0, 0)
	model.Parent = parent
	return model
end

local function wheel(model: Model, x: number, z: number, radius: number): ()
	part(model, "Pneu", V(0.40, radius * 2, radius * 2), x, radius + 0.24, z,
		rubber, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	part(model, "Jante", V(0.42, radius, radius), x, radius + 0.24, z,
		steel, Enum.Material.Metal, Enum.PartType.Cylinder)
end

local function ladder(model: Model, y: number, z: number, length: number): ()
	for _, side in ipairs({-1, 1}) do
		part(model, "Longeron", V(0.16, 0.25, length), side * 0.56, y, z, steel, Enum.Material.Metal)
	end
	for rung = 0, 7 do
		part(model, "Echelon", V(1.1, 0.13, 0.13), 0, y, z + length * (rung / 8 - 0.44), steel, Enum.Material.Metal)
	end
end

-- Assemble une carrosserie et les équipements distinctifs de la spécialité.
function StreetModels.vehicle(parent: Instance, name: string, typeId: string, service: string, civilianColor: Color3?): any
	local model = newModel(parent, name)
	local style = civilianColor and "sedan" or shapes[typeId] or "van"
	local color = civilianColor or paint[service] or red
	local body, beacon
	if style == "motorcycle" then
		wheel(model, 0, -1.35, 0.56)
		wheel(model, 0, 1.3, 0.56)
		body = part(model, "Reservoir", V(0.78, 0.7, 1.65), 0, 1.27, 0, color)
		part(model, "Selle", V(0.7, 0.24, 1), 0, 1.56, 0.38, rubber)
		part(model, "Fourche", V(0.32, 1.22, 0.28), 0, 1.25, -1.29, steel).Orientation = V(-14, 0, 0)
		part(model, "Guidon", V(1.0, 0.15, 0.22), 0, 1.9, -1.12, steel)
		part(model, "SauteVent", V(0.85, 0.7, 0.13), 0, 2.04, -1.32, glass, Enum.Material.Glass)
		beacon = part(model, "Gyrophare", V(0.32, 0.3, 0.32), 0, 1.68, 1.17, blue, Enum.Material.Neon)
	else
		local car = style == "sedan"
		local width, length = car and 2.65 or 3.35, car and 5.65 or 7.8
		local half = length / 2
		local belt = car and 1.15 or 1.85
		local cabZ = car and -0.15 or -half + 1.19
		body = part(model, "Caisse", V(width, belt, length), 0, 0.72 + belt / 2, 0, color)
		part(model, "Chassis", V(width - 0.65, 0.32, length - 0.2), 0, 0.68, 0, rubber)
		part(model, "Habitacle", V(width - 0.24, 0.95, car and 2.9 or 1.95), 0, belt + 1.07, cabZ, glass, Enum.Material.Glass)
		part(model, "Pavillon", V(width - 0.15, 0.23, car and 2.7 or 2.12), 0, belt + 1.6, cabZ, color)
		for _, side in ipairs({-1, 1}) do
			local x = side * (width / 2 - 0.04)
			wheel(model, x, -half * 0.61, car and 0.56 or 0.70)
			wheel(model, x, half * 0.61, car and 0.56 or 0.70)
			part(model, "Montant", V(0.14, 0.94, 0.16), x * 0.96, belt + 1.07, cabZ + 0.14, color)
			part(model, "Retroviseur", V(0.38, 0.22, 0.31), x * 1.12, belt + 0.96, cabZ - 0.56, rubber)
			part(model, "Phare", V(width * 0.21, 0.34, 0.12), x * 0.72, 1.50, -half, white, Enum.Material.Neon)
			part(model, "FeuArriere", V(0.24, 0.4, 0.13), x * 0.85, 1.4, half, rgb(222, 50, 42))
			if not civilianColor then
				part(model, "BandeReflechissante", V(0.09, 0.17, length * 0.94), x * 1.04, 1.52, 0,
					service == "medical" and rgb(28, 131, 168) or rgb(229, 207, 96))
			end
		end
		part(model, "Calandre", V(width * 0.46, 0.45, 0.12), 0, 1.48, -half, rubber)
		if not car then
			local deck = belt + 0.72
			if style == "tanker" then
				local tank = part(model, "Citerne", V(4.6, 2.7, 2.7), 0, deck + 0.65, 1.02, steel, Enum.Material.Metal, Enum.PartType.Cylinder)
				tank.Orientation = V(0, 90, 0)
				part(model, "Trappe", V(0.75, 0.2, 0.75), 0, deck + 2.02, 1.05, rubber)
			else
				part(model, "Cellule", V(width - 0.06, 1.42, 4.98), 0, deck + 0.68, 1.19, color)
				for _, side in ipairs({-1, 1}) do
					for bay = 0, 1 do
						local x, z = side * width * 0.50, 0.09 + bay * 2.12
						local glazed = style == "ambulance" or style == "radio"
						part(model, glazed and "Baie" or "Volet", V(0.10, 1.19, 1.84), x, deck + 0.61, z, glazed and glass or steel)
						if not glazed then
							part(model, "Poignee", V(0.14, 0.11, 0.75), x, deck + 0.18, z, rubber)
						end
					end
				end
				if style == "ladder" or style == "pumper" then
					ladder(model, deck + 1.62, style == "ladder" and 0.2 or 1.28, style == "ladder" and 6.9 or 4.5)
				elseif style == "boom" then
					for _, offset in ipairs({-0.44, 0.44}) do
						part(model, "BrasElevateur", V(0.52, 0.49, 4.75), offset, deck + 1.66, 0.9, steel)
					end
					part(model, "Nacelle", V(1.78, 0.87, 0.9), 0, deck + 1.92, -1.76, white)
				elseif style == "radio" then
					part(model, "MatRadio", V(0.13, 2.35, 0.13), 0.76, deck + 2.2, 2.12, steel)
					part(model, "Parabole", V(1.15, 0.27, 1.15), 0, deck + 1.7, 0.54, white, nil, Enum.PartType.Ball).Orientation = V(-24, 0, 0)
				elseif style == "ambulance" then
					part(model, "PortesSanitaires", V(0.12, 2.54, 0.13), 0, 2.22, half, rubber)
					part(model, "Aérateur", V(0.9, 0.24, 1.02), 0, deck + 1.49, 1.8, white)
				else
					part(model, "Galerie", V(2.58, 0.21, 3.84), 0, deck + 1.53, 1.23, steel)
				end
			end
		end
		if not civilianColor then
			beacon = part(model, "Gyrophare", V(width * 0.76, 0.25, 0.48), 0, belt + 1.83, cabZ, blue, Enum.Material.Neon)
		end
	end
	return { model = model, body = body, light = beacon }
end

-- Assemble un passant à l'échelle des voitures et des portes de la ville.
function StreetModels.walker(parent: Instance, name: string, coat: Color3, index: number): Model
	local model = newModel(parent, name)
	local skin = ({rgb(172, 121, 90), rgb(106, 73, 55), rgb(211, 165, 131)})[index % 3 + 1]
	local trousers = rgb(52, 62, 72)
	part(model, "Tete", V(0.54, 0.62, 0.54), 0, 2.54, 0, skin, nil, Enum.PartType.Ball)
	part(model, "Cheveux", V(0.55, 0.24, 0.55), 0, 2.76, 0.03, rubber, nil, Enum.PartType.Ball)
	part(model, "Veste", V(0.69, 0.85, 0.41), 0, 1.82, 0, coat)
	for _, side in ipairs({-1, 1}) do
		part(model, "Jambe", V(0.27, 0.89, 0.29), side * 0.18, 0.99, side * 0.10, trousers)
		part(model, "Chaussure", V(0.28, 0.23, 0.45), side * 0.18, 0.43, side * 0.10 - 0.05, rubber)
		part(model, "Bras", V(0.22, 0.75, 0.25), side * 0.44, 1.77, -side * 0.1, coat)
	end
	return model
end

return StreetModels
