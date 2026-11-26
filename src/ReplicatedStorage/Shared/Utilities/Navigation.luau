--!strict
--[[
	Navigation — trajets sur la carte normalisée.

	Un trajet est une polyligne : le réseau routier (`RoadNetwork`) fournit les
	points, `Navigation` calcule la longueur, la durée et la position à un
	instant donné. Sans polyligne (tests, repli), le trajet reste une ligne
	directe. Les services ne connaissent que `route`, `position` et `arrived`.

	Les positions intermédiaires ne sont jamais transmises : le serveur est
	autoritaire, le client interpole les positions du snapshot.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Utilities = Shared:WaitForChild("Utilities")
local MathX = require(Utilities:WaitForChild("MathX"))

local Navigation = {}

export type Point = { x: number, z: number }

export type Route = {
	ax: number,
	az: number,
	bx: number,
	bz: number,
	startTime: number,
	duration: number,
	siren: boolean,
	points: { Point }?,
	cumulative: { number }?,
	length: number?,
}

-- Longueur cumulée d'une polyligne ; renvoie aussi la longueur totale.
function Navigation.measure(points: { Point }): ({ number }, number)
	local cumulative = { 0 }
	local total = 0
	for index = 2, #points do
		local previous = points[index - 1]
		local current = points[index]
		total += MathX.distance(previous.x, previous.z, current.x, current.z)
		cumulative[index] = total
	end
	return cumulative, total
end

-- Construit un trajet de `from` vers `to`.
-- `path` est une polyligne optionnelle (issue du réseau routier).
function Navigation.route(
	config: any,
	from: any,
	to: any,
	speed: number,
	now: number,
	siren: boolean?,
	path: { Point }?
): Route
	local points = path
	local cumulative = nil
	local total = MathX.distance(from.x, from.z, to.x, to.z)
	if points ~= nil and #points >= 2 then
		cumulative, total = Navigation.measure(points)
	else
		points = nil
	end

	local safeSpeed = math.max(0.2, speed)
	local duration = config.TRAVEL_BASE + (total * config.TRAVEL_PER_UNIT) / safeSpeed
	if siren then
		duration *= config.SIREN_FACTOR
	end
	return {
		ax = from.x,
		az = from.z,
		bx = to.x,
		bz = to.z,
		startTime = now,
		duration = math.max(0.1, duration),
		siren = siren == true,
		points = points,
		cumulative = cumulative,
		length = total,
	}
end

-- Avancement du trajet, borné à [0, 1].
function Navigation.progress(route: Route, now: number): number
	if route.duration <= 0 then
		return 1
	end
	return MathX.clamp((now - route.startTime) / route.duration, 0, 1)
end

-- Position sur la polyligne à la distance parcourue demandée.
local function positionAlong(points: { Point }, cumulative: { number }, distance: number): Point
	local total = cumulative[#cumulative] or 0
	if total <= 0 then
		local first = points[1]
		return { x = first.x, z = first.z }
	end
	local travelled = MathX.clamp(distance, 0, total)
	for index = 2, #points do
		if travelled <= cumulative[index] or index == #points then
			local segment = cumulative[index] - cumulative[index - 1]
			local ratio = if segment <= 0 then 0 else (travelled - cumulative[index - 1]) / segment
			local previous = points[index - 1]
			local current = points[index]
			return {
				x = MathX.lerp(previous.x, current.x, ratio),
				z = MathX.lerp(previous.z, current.z, ratio),
			}
		end
	end
	local last = points[#points]
	return { x = last.x, z = last.z }
end

function Navigation.position(route: Route, now: number): Point
	local t = Navigation.progress(route, now)
	if route.points ~= nil and route.cumulative ~= nil and route.length ~= nil then
		return positionAlong(route.points, route.cumulative, t * route.length)
	end
	return {
		x = MathX.lerp(route.ax, route.bx, t),
		z = MathX.lerp(route.az, route.bz, t),
	}
end

function Navigation.arrived(route: Route, now: number): boolean
	return Navigation.progress(route, now) >= 1
end

function Navigation.remaining(route: Route, now: number): number
	return math.max(0, route.duration - (now - route.startTime))
end

return Navigation
