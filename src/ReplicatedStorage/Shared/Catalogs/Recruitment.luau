--!strict
-- Barème de la caserne. Les tarifs sont exprimés en euros.
local Recruitment = {}
Recruitment.profiles = {
	{ id = "dog_handler", grade = "Maître-chien", service = "fire", cost = 1550, qualifications = { MAITRE_CHIEN = true, SAPEUR = true, CONDUCTEUR = true } },
	{ id = "technician", grade = "Technicien", service = "technical", cost = 1400, qualifications = { TECHNICIEN = true, CONDUCTEUR = true } },
	{ id = "firefighter", grade = "Sapeur", service = "fire", cost = 1200, qualifications = { SAPEUR = true, CONDUCTEUR = true, CHEF_AGRES = true } },
	{ id = "medic", grade = "Secouriste", service = "medical", cost = 1450, qualifications = { SECOURISTE = true, CHEF_AGRES = true, CONDUCTEUR = true } },
	{ id = "doctor", grade = "Médecin", service = "medical", cost = 2400, qualifications = { MEDECIN = true, SECOURISTE = true, CONDUCTEUR = true } },
	{ id = "officer", grade = "Brigadier", service = "police", cost = 1300, qualifications = { POLICIER = true, GENDARME = true, CONDUCTEUR = true } },
	{ id = "coordinator", grade = "Officier", service = "command", cost = 1800, qualifications = { COS = true, CHEF_GROUPE = true, CONDUCTEUR = true } },
	{ id = "logistician", grade = "Logisticien", service = "logistics", cost = 1100, qualifications = { CONDUCTEUR = true } },
}
Recruitment.byId = {}
for _, profile in ipairs(Recruitment.profiles) do
	Recruitment.byId[profile.id] = profile
end

Recruitment.increase = 30
Recruitment.maxPersonnel = 64
Recruitment.maxLevel = 3

-- Coût de la formation pour passer au niveau suivant.
function Recruitment.trainingCost(level: number): number
	return (level + 1) * 500
end

-- Indemnité pour un transfert, calculée sur le prix payé à l'entrée.
function Recruitment.transferValue(person: any): number
	return math.floor((person.hireCost or 1200) / 2)
end

return Recruitment
