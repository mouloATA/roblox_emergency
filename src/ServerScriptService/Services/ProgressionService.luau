--!strict
-- La note de service moyenne et les six distinctions reposent sur des bilans
-- clos. Les compteurs numériques sont pris en charge par la sauvegarde existante.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Operations = require(Shared:WaitForChild("Utilities"):WaitForChild("Operations"))
local ProgressionService = {}

local decorations = {
	{id = "care", name = "Secours médical", condition = "Cinq victimes admises à l’hôpital.", counter = "admissions", target = 5},
	{id = "police", name = "Mérite de la police", condition = "Deux bilans complets avec un équipage de police sur une intervention qui l’exige.", counter = "policeResponses", target = 2},
	{id = "fire", name = "Maîtrise du feu", condition = "Trois incendies éteints à l’eau avec un bilan complet.", counter = "firesControlled", target = 3},
	{id = "canine", name = "Sauvetage cynophile", condition = "Un sauvetage réussi par un équipage comprenant un maître-chien, avec toutes les victimes admises.", counter = "canineRescues", target = 1},
	{id = "technical", name = "Gestion de catastrophe", condition = "Deux bilans complets avec un engin technique sur un chantier technique ou de désincarcération.", counter = "technicalResponses", target = 2},
	{id = "gold", name = "Médaille d’or nationale", condition = "Réunir les cinq distinctions de spécialité.", counter = "specialties", target = 5},
}

local function add(stats: any, key: string, amount: number): ()
	stats[key] = (stats[key] or 0) + amount
end

-- Calcule une seule fois le bilan après l'admission ou l'échec, avant le retour des engins.
function ProgressionService.record(world: any, incident: any): ()
	if incident.scoreDelta ~= nil or incident.closedAt == nil then
		return
	end
	local stats = world.stats
	local success = incident.status == Constants.INCIDENT_STATUS.RESOLVED
	local complete = success and incident.outcome == "success"
	local saved = math.clamp(incident.savedVictims or 0, 0, incident.victims)
	local lost = incident.victims - saved
	local config = world.config
	local base = (complete and config.SCORE_FULL or (success and config.SCORE_PARTIAL or -config.SCORE_FAILURE)) * incident.severity
	local penalty = lost * config.SCORE_CIVILIAN_LOSS
	local delta = base + saved * config.SCORE_ADMISSION - penalty
	local quality = complete and 100 or (success and 65 or 0)
	if success and incident.firstArrivalAt and incident.firstArrivalAt - incident.createdAt > (incident.deadline - incident.createdAt) / 2 then
		quality -= 10
	end
	if incident.victims > 0 then
		quality = math.floor(quality * (1 - 0.5 * lost / incident.victims))
	end

	incident.scoreDelta = delta
	add(stats, "score", delta)
	add(stats, "ratedCalls", 1)
	add(stats, "ratingSum", quality)
	add(stats, "civilianLosses", lost)
	add(stats, "civilianPenalty", penalty)
	add(stats, "admissions", saved)
	if complete then
		if (incident.waterUsed or 0) > 0 then
			add(stats, "firesControlled", 1)
		end
		local services = incident.respondingServices or {}
		local needs = world.catalogs.incidents.get(incident.typeId).requires
		if services.police and needs.police then
			add(stats, "policeResponses", 1)
		end
		if services.technical and (needs.technical or (incident.extricated or 0) > 0) then
			add(stats, "technicalResponses", 1)
		end
		if incident.canineSearch and (incident.rescued or 0) > 0 and saved == incident.victims then
			add(stats, "canineRescues", 1)
		end
	end
	Operations.log(world, success and Constants.LOG.SUCCESS or Constants.LOG.FAILURE,
		string.format("%s · Bilan %+d pts · qualité %d/100 · %d perte(s) civile(s) (−%d pts).", incident.id, delta, quality, lost, penalty))
	for _, award in ipairs(decorations) do
		local key = "award_" .. award.id
		if (stats[key] or 0) == 0 and (stats[award.counter] or 0) >= award.target then
			stats[key] = 1
			if award.id ~= "gold" then add(stats, "specialties", 1) end
			Operations.log(world, Constants.LOG.SUCCESS, "Distinction obtenue · " .. award.name)
		end
	end
end

-- Mémorise la première arrivée et les services qui ont vraiment atteint le lieu.
function ProgressionService.arrive(world: any, incident: any, vehicle: any): ()
	incident.firstArrivalAt = incident.firstArrivalAt or world.time
	incident.respondingServices = incident.respondingServices or {}
	local def = world.catalogs.vehicles.get(vehicle.typeId)
	if def then
		incident.respondingServices[def.service] = true
	end
end

-- Construit le bulletin affiché à tous les postes, y compris avant la première alerte.
function ProgressionService.snapshot(world: any): any
	local stats = world.stats
	local awards = {}
	for _, award in ipairs(decorations) do
		table.insert(awards, {id = award.id, name = award.name, condition = award.condition,
			current = math.min(stats[award.counter] or 0, award.target), target = award.target,
			earned = (stats["award_" .. award.id] or 0) > 0})
	end
	local count = stats.ratedCalls or 0
	return {
		score = stats.score or 0, rating = count > 0 and math.floor(stats.ratingSum / count + 0.5) or nil,
		civilianLosses = stats.civilianLosses or 0, civilianPenalty = stats.civilianPenalty or 0,
		awards = awards,
	}
end

return ProgressionService
