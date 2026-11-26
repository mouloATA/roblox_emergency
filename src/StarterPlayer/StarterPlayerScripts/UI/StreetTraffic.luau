--!strict
-- Circulation d'ambiance. Les clients échantillonnent les mêmes parcours avec
-- l'heure de la simulation. Aucune pièce mobile à répliquer par le serveur.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local City = require(Shared:WaitForChild("City"))
local UI = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ERSClient"):WaitForChild("UI")
local StreetModels = require(UI:WaitForChild("StreetModels"))

local StreetTraffic = {}
local colors = {
	Color3.fromRGB(91, 125, 147), Color3.fromRGB(191, 163, 109), Color3.fromRGB(155, 80, 68),
	Color3.fromRGB(91, 122, 103), Color3.fromRGB(139, 142, 157), Color3.fromRGB(63, 84, 91),
}

-- Un rectangle à virages arrondis, sur la file de droite ou sur le trottoir.
local function loop(column: number, row: number, walking: boolean): any
	local inset = walking and City.ROAD_HALF + City.SIDEWALK * 0.78 or City.ROAD_HALF * 0.48
	local x0, x1 = City.AVENUES[column] + inset, City.AVENUES[column + 1] - inset
	local z0, z1 = City.STREETS[row] + inset, City.STREETS[row + 1] - inset
	local corners = {{x0, z0}, {x1, z0}, {x1, z1}, {x0, z1}}
	local radius = walking and 0.20 or 1.25
	local v = walking and 0.47 or 1.8
	local route: any = {duration = 0, sections = {}}
	for i, start in ipairs(corners) do
		local stop = corners[i % 4 + 1]
		local length = math.abs(stop[1] - start[1]) + math.abs(stop[2] - start[2])
		local dx, dz = (stop[1] - start[1]) / length, (stop[2] - start[2]) / length
		local section = {
			x = start[1] + dx * radius, z = start[2] + dz * radius, dx = dx, dz = dz,
			run = (length - 2 * radius) / v, pause = walking and 0 or 1.15, v = v, r = radius,
			turn = radius * math.pi / (2 * v),
		}
		route.duration += section.run + section.pause + section.turn
		table.insert(route.sections, section)
	end
	return route
end

-- Position et direction sur un circuit fermé, y compris le temps d'arrêt.
function StreetTraffic.sample(route: any, time: number): (number, number, number, number)
	local t = time % route.duration
	for _, s in ipairs(route.sections) do
		local total = s.run + s.pause + s.turn
		if t <= total then
			-- Marquer l'arrêt trois unités avant le virage.
			local beforeStop = math.max(0, s.run - 3 / s.v)
			local moving = math.clamp(t - math.clamp(t - beforeStop, 0, s.pause), 0, s.run)
			local x, z = s.x + s.dx * moving * s.v, s.z + s.dz * moving * s.v
			local angle = math.clamp((t - s.run - s.pause) / s.turn, 0, 1) * math.pi / 2
			local c, a = math.cos(angle), math.sin(angle)
			return x + s.r * (a * s.dx - (1 - c) * s.dz),
				z + s.r * (a * s.dz + (1 - c) * s.dx), c * s.dx - a * s.dz, c * s.dz + a * s.dx
		end
		t -= total
	end
	local first = route.sections[1]
	return first.x, first.z, first.dx, first.dz
end

-- Installe huit voitures et huit passants sur quatre îlots disjoints.
function StreetTraffic.new(parent: Instance, scale: number): any
	local folder = Instance.new("Folder")
	folder.Name, folder.Parent = "VieUrbaine", parent
	local state: any = { actors = {}, scale = scale, time = 0, speed = 0, elapsed = 1 }
	for _, column in ipairs({1, 3}) do
		for _, row in ipairs({1, 3}) do
			for _, walking in ipairs({false, true}) do
				local route = loop(column, row, walking)
				for i = 0, 1 do
					local n = #state.actors + 1
					local color = colors[(n - 1) % #colors + 1]
					local model
					if walking then
						model = StreetModels.walker(folder, "Pieton_" .. n, color, n)
					else
						model = StreetModels.vehicle(folder, "Voiture_" .. n, "civil", "civil", color).model
					end
					table.insert(state.actors, {
						model = model, route = route, walking = walking,
						offset = route.duration * (i * 0.5 + 0.037 * (row + column)),
					})
				end
			end
		end
	end
	StreetTraffic.step(state, 0)
	return state
end

-- Recale l'horloge quand un nouveau tic arrive, notamment après une reprise.
function StreetTraffic.sync(state: any, snapshot: any): ()
	if type(snapshot.time) ~= "number" then return end
	local speed = snapshot.timeScale or 1
	if state.lastTick ~= snapshot.time or state.speed ~= speed then
		state.time, state.speed, state.lastTick = snapshot.time, speed, snapshot.time
		state.elapsed = 1
	end
end

-- Actualise les poses localement à 15 Hz, y compris lors du passage en pause.
function StreetTraffic.step(state: any, dt: number): ()
	state.time += dt * state.speed
	state.elapsed += dt
	if state.elapsed < 1 / 15 or state.lastPose == state.time then return end
	state.elapsed, state.lastPose = 0, state.time
	for _, actor in ipairs(state.actors) do
		local t = state.time + actor.offset
		local x, z, dx, dz = StreetTraffic.sample(actor.route, t)
		local y = actor.walking and 0.08 * math.abs(math.sin(t * 4)) or 0
		local p = Vector3.new(x * state.scale, y, z * state.scale)
		actor.model:PivotTo(CFrame.lookAt(p, Vector3.new(p.X + dx, y, p.Z + dz)))
	end
end

return StreetTraffic
