--!strict
-- Le serveur suit les interventions réelles et ne déclenche chaque appel qu'une fois.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Missions = require(Shared:WaitForChild("Catalogs"):WaitForChild("Missions"))
local Utilities = Shared:WaitForChild("Utilities")
local Operations = require(Utilities:WaitForChild("Operations"))
local Result = require(Utilities:WaitForChild("Result"))
local Services = game:GetService("ServerScriptService"):WaitForChild("ERS"):WaitForChild("Services")
local PermissionService = require(Services:WaitForChild("PermissionService"))
local IncidentService = require(Services:WaitForChild("IncidentService"))
local MissionService = {}

local function openObjective(world: any, def: any, number: number): any
	local objective = def.objectives[number]
	local result = IncidentService.spawn(world, objective.typeId, {x = objective.x, z = objective.z})
	if result.ok then
		local incident = result.data
		incident.missionLabel = def.name .. " · " .. objective.label
		incident.missionBriefing = objective.briefing
		Operations.log(world, Constants.LOG.INCIDENT, incident.id .. " · " .. objective.briefing)
	end
	return result
end

-- Lance une mission sans effacer les interventions déjà engagées.
function MissionService.start(world: any, actorId: number, id: string): any
	local allowed = PermissionService.require(world, actorId, Constants.ACTION.START_MISSION)
	if not allowed.ok then
		return allowed
	end
	local def = Missions.byId[id]
	if not def then
		return Result.err("Mission inconnue.")
	end
	if world.finished then
		return Result.err("Le service est terminé.")
	end
	if world.mission and world.mission.status == "active" then
		return Result.err("Une mission est déjà en cours.")
	end
	local first = openObjective(world, def, 1)
	if not first.ok then
		return first
	end
	world.mission = { id = id, status = "active", startTime = world.time, incidentIds = {first.data.id} }
	return Result.ok("Mission engagée · " .. def.name)
end

local function triggerReached(world: any, mission: any, def: any, first: any): boolean
	if def.trigger == "radio" then
		return world.time - mission.startTime >= def.delay
	end
	if first.status == Constants.INCIDENT_STATUS.RESOLVED then
		return true
	end
	if def.trigger == "arrival" then
		return next(first.onScene) ~= nil
	end
	return first.stepIndex >= 2
end

local function finish(world: any, mission: any, def: any, success: boolean): ()
	mission.status = success and "completed" or "failed"
	if success then
		local key = "mission_" .. def.id
		world.stats[key] = (world.stats[key] or 0) + 1
	end
	Operations.log(world, success and Constants.LOG.SUCCESS or Constants.LOG.FAILURE,
		def.name .. (success and " · Tous les objectifs sont remplis." or " · Un objectif a échoué."))
end

-- Déclenche les renforts et valide les objectifs après le tic des interventions.
function MissionService.step(world: any): ()
	local mission = world.mission
	if not mission or mission.status ~= "active" then
		return
	end
	local def = Missions.byId[mission.id]
	local first = world.incidents[mission.incidentIds[1]]
	local secondId = mission.incidentIds[2]
	if not secondId then
		if first.status == Constants.INCIDENT_STATUS.FAILED then
			finish(world, mission, def, false)
		elseif triggerReached(world, mission, def, first) and IncidentService.activeCount(world) < world.config.MAX_ACTIVE_INCIDENTS then
			local second = openObjective(world, def, 2)
			if second.ok then
				mission.incidentIds[2] = second.data.id
			end
		end
		return
	end
	local second = world.incidents[secondId]
	if first.closedAt and second.closedAt then
		finish(world, mission, def, first.status == Constants.INCIDENT_STATUS.RESOLVED
			and second.status == Constants.INCIDENT_STATUS.RESOLVED and first.savedVictims == first.victims
			and second.savedVictims == second.victims)
	end
end

-- Expose les objectifs et les identifiants sélectionnables sans les tables de simulation.
function MissionService.snapshot(world: any): any
	local mission = world.mission
	if not mission then
		return nil
	end
	local def = Missions.byId[mission.id]
	local objectives = {}
	for index, objective in ipairs(def.objectives) do
		local incidentId = mission.incidentIds[index]
		local incident = world.incidents[incidentId]
		local status = incident and incident.status or (mission.status == "failed" and "cancelled" or "locked")
		if incident and status == Constants.INCIDENT_STATUS.RESOLVED and incident.savedVictims < incident.victims then
			status = Constants.INCIDENT_STATUS.FAILED
		end
		table.insert(objectives, {label = objective.label, incidentId = incidentId, status = status})
	end
	return {id = def.id, name = def.name, status = mission.status, objectives = objectives}
end

return MissionService
