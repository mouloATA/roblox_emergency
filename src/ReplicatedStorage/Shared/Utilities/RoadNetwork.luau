--!strict
--[[
	RoadNetwork — graphe routier construit depuis `Shared/City`.

	Le plan de ville est une grille : chaque avenue (axe nord-sud) et chaque rue
	(axe est-ouest) se croise en un carrefour. Le réseau ne stocke donc que les
	carrefours (nœuds) et les tronçons entre deux carrefours consécutifs (arêtes).
	Aucune géométrie n'est envoyée par le réseau : le serveur et chaque client
	reconstruisent le même graphe à partir de la même graine.

	`RoadNetwork.path` renvoie une polyligne passant par les routes. Un véhicule
	part de sa place de stationnement (hors chaussée), rejoint la route la plus
	proche, suit le graphe, puis rejoint le point d'intervention. Le trajet reste
	donc déterministe et testable sans moteur physique.
]]

local RoadNetwork = {}

local EPSILON = 1e-6

export type Point = { x: number, z: number }
export type Edge = {
	id: number,
	ax: number,
	az: number,
	bx: number,
	bz: number,
	a: number,
	b: number,
	length: number,
}
export type Network = {
	avenues: { number },
	streets: { number },
	nodes: { Point },
	nodeIds: { [string]: number },
	edges: { Edge },
	adjacency: { [number]: { { node: number, length: number } } },
}

local function nodeKey(avenueIndex: number, streetIndex: number): string
	return string.format("%d:%d", avenueIndex, streetIndex)
end

local function clamp01(value: number): number
	if value < 0 then
		return 0
	elseif value > 1 then
		return 1
	end
	return value
end

-- [[ Construit le graphe : nœuds aux carrefours, arêtes le long des axes. ]]
function RoadNetwork.build(plan: any): Network
	local avenues = {}
	local streets = {}
	for _, road in ipairs(plan.roads or {}) do
		if road.axis == "avenue" then
			table.insert(avenues, road.x)
		elseif road.axis == "street" then
			table.insert(streets, road.z)
		end
	end
	table.sort(avenues)
	table.sort(streets)

	local network: Network = {
		avenues = avenues,
		streets = streets,
		nodes = {},
		nodeIds = {},
		edges = {},
		adjacency = {},
	}

	for streetIndex, z in ipairs(streets) do
		for avenueIndex, x in ipairs(avenues) do
			local id = #network.nodes + 1
			network.nodes[id] = { x = x, z = z }
			network.nodeIds[nodeKey(avenueIndex, streetIndex)] = id
			network.adjacency[id] = {}
		end
	end

	local function connect(a: number, b: number): ()
		local pointA = network.nodes[a]
		local pointB = network.nodes[b]
		local length = math.sqrt((pointB.x - pointA.x) ^ 2 + (pointB.z - pointA.z) ^ 2)
		local id = #network.edges + 1
		table.insert(network.edges, {
			id = id,
			ax = pointA.x,
			az = pointA.z,
			bx = pointB.x,
			bz = pointB.z,
			a = a,
			b = b,
			length = length,
		})
		table.insert(network.adjacency[a], { node = b, length = length })
		table.insert(network.adjacency[b], { node = a, length = length })
	end

	for avenueIndex = 1, #avenues do
		for streetIndex = 1, #streets - 1 do
			connect(
				network.nodeIds[nodeKey(avenueIndex, streetIndex)],
				network.nodeIds[nodeKey(avenueIndex, streetIndex + 1)]
			)
		end
	end
	for streetIndex = 1, #streets do
		for avenueIndex = 1, #avenues - 1 do
			connect(
				network.nodeIds[nodeKey(avenueIndex, streetIndex)],
				network.nodeIds[nodeKey(avenueIndex + 1, streetIndex)]
			)
		end
	end

	return network
end

-- [[ Vrai si le graphe contient au moins un carrefour et une arête. ]]
function RoadNetwork.usable(network: Network?): boolean
	return network ~= nil and #network.nodes >= 2 and #network.edges >= 1
end

-- Projette un point sur une arête ; `t` est borné à [0, 1].
local function projectOnEdge(edge: Edge, x: number, z: number): any
	local dx = edge.bx - edge.ax
	local dz = edge.bz - edge.az
	local lengthSquared = dx * dx + dz * dz
	local t = 0
	if lengthSquared > EPSILON then
		t = ((x - edge.ax) * dx + (z - edge.az) * dz) / lengthSquared
	end
	t = clamp01(t)
	local px = edge.ax + dx * t
	local pz = edge.az + dz * t
	return {
		x = px,
		z = pz,
		t = t,
		distance = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2),
		edge = edge,
	}
end

-- Point de la chaussée le plus proche d'une position libre.
function RoadNetwork.nearest(network: Network, x: number, z: number): any?
	if not RoadNetwork.usable(network) then
		return nil
	end
	local best = nil
	for _, edge in ipairs(network.edges) do
		local projection = projectOnEdge(edge, x, z)
		if best == nil or projection.distance < best.distance then
			best = projection
		end
	end
	return best
end

-- [[ Dijkstra déterministe entre deux carrefours ; renvoie distance et chemin. ]]
function RoadNetwork.shortest(network: Network, fromNode: number, toNode: number): (number, { number })
	local count = #network.nodes
	local best = {}
	local previous = {}
	local visited = {}
	for id = 1, count do
		best[id] = math.huge
		previous[id] = nil
		visited[id] = false
	end
	best[fromNode] = 0

	for _ = 1, count do
		local current = nil
		for id = 1, count do
			if not visited[id] and (current == nil or best[id] < best[current]) then
				current = id
			end
		end
		if current == nil or best[current] == math.huge then
			break
		end
		visited[current] = true
		if current == toNode then
			break
		end
		for _, link in ipairs(network.adjacency[current] or {}) do
			local candidate = best[current] + link.length
			if candidate < best[link.node] then
				best[link.node] = candidate
				previous[link.node] = current
			end
		end
	end

	if best[toNode] == math.huge then
		return math.huge, {}
	end

	local reversed = {}
	local cursor = toNode
	while cursor ~= nil do
		table.insert(reversed, cursor)
		if cursor == fromNode then
			break
		end
		cursor = previous[cursor]
	end
	local path = {}
	for index = #reversed, 1, -1 do
		table.insert(path, reversed[index])
	end
	return best[toNode], path
end

local function appendPoint(points: { Point }, point: Point): ()
	local last = points[#points]
	if last == nil or math.abs(last.x - point.x) > EPSILON or math.abs(last.z - point.z) > EPSILON then
		table.insert(points, { x = point.x, z = point.z })
	end
end

-- [[ Trajet routier de `from` à `to` : polyligne commençant et finissant aux
-- extrémités demandées, avec au moins un point sur la chaussée. ]]
function RoadNetwork.path(network: Network?, from: Point, to: Point): { Point }
	if not network or not RoadNetwork.usable(network) then
		return { { x = from.x, z = from.z }, { x = to.x, z = to.z } }
	end

	local start = RoadNetwork.nearest(network, from.x, from.z)
	local finish = RoadNetwork.nearest(network, to.x, to.z)
	if start == nil or finish == nil then
		return { { x = from.x, z = from.z }, { x = to.x, z = to.z } }
	end

	-- Même tronçon : le plus court chemin reste sur ce tronçon.
	if start.edge.id == finish.edge.id then
		local points = {}
		appendPoint(points, { x = from.x, z = from.z })
		appendPoint(points, { x = start.x, z = start.z })
		appendPoint(points, { x = finish.x, z = finish.z })
		appendPoint(points, { x = to.x, z = to.z })
		return points
	end

	local startEndpoints = { start.edge.a, start.edge.b }
	local finishEndpoints = { finish.edge.a, finish.edge.b }
	local bestDistance = math.huge
	local bestNodes = nil
	local bestStart = nil
	local bestFinish = nil

	for _, startNode in ipairs(startEndpoints) do
		local startPoint = network.nodes[startNode]
		local entry = math.sqrt((startPoint.x - start.x) ^ 2 + (startPoint.z - start.z) ^ 2)
		for _, finishNode in ipairs(finishEndpoints) do
			local finishPoint = network.nodes[finishNode]
			local exit = math.sqrt((finishPoint.x - finish.x) ^ 2 + (finishPoint.z - finish.z) ^ 2)
			local middle, nodes = RoadNetwork.shortest(network, startNode, finishNode)
			local total = entry + middle + exit
			if total < bestDistance - EPSILON then
				bestDistance = total
				bestNodes = nodes
				bestStart = startNode
				bestFinish = finishNode
			end
		end
	end

	local points = {}
	appendPoint(points, { x = from.x, z = from.z })
	appendPoint(points, { x = start.x, z = start.z })
	if bestNodes then
		for _, nodeId in ipairs(bestNodes) do
			appendPoint(points, network.nodes[nodeId])
		end
		-- Garantit que le dernier carrefour est bien celui de sortie, même si le
		-- chemin le plus court emprunte l'autre extrémité du tronçon.
		appendPoint(points, network.nodes[bestFinish])
	end
	appendPoint(points, { x = finish.x, z = finish.z })
	appendPoint(points, { x = to.x, z = to.z })
	return points
end

return RoadNetwork
