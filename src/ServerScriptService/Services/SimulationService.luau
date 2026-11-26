--!strict
--[[
	SimulationService — boucle de jeu serveur et contrôle du temps.

	La simulation est indépendante de l'affichage : elle avance au rythme des
	tics serveur. Les clients ne reçoivent que des snapshots.

	Le rythme est piloté par `world.timeScale` (0 = pause, 1, 2, 4). Seul un
	poste autorisé peut le changer : le serveur valide la valeur demandée, le
	client ne fait que proposer une vitesse.

	Ordre d'un tic :
	1. horloge et alertes ;
	2. déplacements ;
	3. progression des interventions ;
	4. atelier ;
	5. fatigue.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Result = require(Shared:WaitForChild("Utilities"):WaitForChild("Result"))
local Operations = require(Shared:WaitForChild("Utilities"):WaitForChild("Operations"))

local ServerScript = game:GetService("ServerScriptService"):WaitForChild("ERS")
local Services = ServerScript:WaitForChild("Services")
local PermissionService = require(Services:WaitForChild("PermissionService"))
local DispatchService = require(Services:WaitForChild("DispatchService"))
local IncidentService = require(Services:WaitForChild("IncidentService"))
local VehicleService = require(Services:WaitForChild("VehicleService"))
local PersonnelService = require(Services:WaitForChild("PersonnelService"))

local SimulationService = {}
local MissionService = require(Services:WaitForChild("MissionService"))

-- Vitesse courante, toujours ramenée à une valeur autorisée.
function SimulationService.timeScale(world: any): number
	local scale = world.timeScale
	if type(scale) ~= "number" then
		return 1
	end
	for _, allowed in ipairs(world.config.TIME_SCALES) do
		if scale == allowed then
			return scale
		end
	end
	return 1
end

--[[
	Change la vitesse de simulation.

	Refusé sans `SET_TIME` (direction et commandement), refusé hors des valeurs
	de `Config.TIME_SCALES`. Un refus ne modifie jamais l'état.
]]
function SimulationService.setTimeScale(world: any, actorId: number, scale: any): any
	local check = PermissionService.require(world, actorId, Constants.ACTION.SET_TIME)
	if not check.ok then
		return check
	end
	if type(scale) ~= "number" then
		return Result.err("Vitesse invalide.")
	end
	local accepted = false
	for _, allowed in ipairs(world.config.TIME_SCALES) do
		if scale == allowed then
			accepted = true
			break
		end
	end
	if not accepted then
		return Result.err("Vitesse non autorisée.")
	end

	local previous = SimulationService.timeScale(world)
	world.timeScale = scale
	if scale ~= previous then
		if scale == 0 then
			Operations.log(world, Constants.LOG.SYSTEM, "Simulation en pause.")
		else
			Operations.log(world, Constants.LOG.SYSTEM, string.format("Simulation à ×%d.", scale))
		end
	end

	if scale == 0 then
		return Result.ok("Simulation en pause.", { timeScale = scale })
	end
	return Result.ok(string.format("Vitesse ×%d.", scale), { timeScale = scale })
end

function SimulationService.step(world: any, dt: number): ()
	local scaled = dt * SimulationService.timeScale(world)
	if scaled <= 0 then
		return
	end

	world.time += scaled

	if not world.finished and world.time >= world.config.SHIFT_SECONDS then
		world.finished = true
		world.saveRequested = true
		Operations.log(world, Constants.LOG.SYSTEM, "Fin de service : la relève est en cours.")
	end

	-- Nouvelles alertes uniquement pendant le service.
	if not world.finished and not (world.mission and world.mission.status == "active") then
		world.alarmCountdown -= scaled
		if world.alarmCountdown <= 0 then
			if IncidentService.activeCount(world) < world.config.MAX_ACTIVE_INCIDENTS then
				local spawned = IncidentService.spawnRandom(world)
				if spawned.ok then
					world.alarmCountdown = world.config.ALERT_INTERVAL
				else
					world.alarmCountdown = 5
				end
			else
				world.alarmCountdown = 5
			end
		end
	end

	DispatchService.step(world, scaled)
	IncidentService.step(world, scaled)
	MissionService.step(world)
	VehicleService.stepRepair(world, scaled)
	PersonnelService.stepFatigue(world, scaled)
end

return SimulationService
