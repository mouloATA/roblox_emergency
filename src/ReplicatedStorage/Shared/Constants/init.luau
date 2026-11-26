--!strict
--[[
	Constants — chaînes d'état, services, actions et catégories.

	Aucune chaîne d'état ne doit être écrite à la main dans les services :
	on passe par ce module, ce qui évite les fautes de frappe silencieuses.
]]

local Constants = {}

-- États d'un véhicule.
Constants.VEHICLE_STATUS = {
	AVAILABLE = "available", -- au poste, prêt à partir
	DISPATCHED = "dispatched", -- en route vers une intervention
	ON_SCENE = "onscene", -- sur les lieux
	RETURNING = "returning", -- retour au poste
	MAINTENANCE = "maintenance", -- à l'atelier
}

-- États d'une intervention.
Constants.INCIDENT_STATUS = {
	PENDING = "pending", -- reçue, pas encore engagée
	ACTIVE = "active", -- moyens engagés / sur place
	RESOLVED = "resolved", -- terminée avec succès
	FAILED = "failed", -- perdue ou échouée
}

-- Services opérationnels.
Constants.SERVICE = {
	FIRE = "fire",
	MEDICAL = "medical",
	POLICE = "police",
	TECHNICAL = "technical",
	COMMAND = "command",
	LOGISTICS = "logistics",
}

Constants.SERVICE_LABEL = {
	fire = "Incendie",
	medical = "Secours à personne",
	police = "Police / gendarmerie",
	technical = "Technique",
	command = "Commandement",
	logistics = "Logistique",
}

-- Rôles multijoueur (spec §12.2).
Constants.ROLE = {
	DIRECTION = "direction",
	COMMANDEMENT = "commandement",
	INCENDIE = "incendie",
	SECOURS = "secours",
	POLICE = "police",
	LOGISTIQUE = "logistique",
	OBSERVATEUR = "observateur",
}

-- Actions soumises à permission.
Constants.ACTION = {
	VIEW = "view",
	DISPATCH = "dispatch",
	RECALL = "recall",
	ASSIGN_PERSONNEL = "assign_personnel",
	EQUIPMENT = "equipment",
	BUY_VEHICLE = "buy_vehicle",
	REPAIR = "repair",
	COMMAND = "command",
	ROLES = "roles",
	SAVE = "save",
	SET_TIME = "set_time",
	NEW_GAME = "new_game",
}

-- Catégories d'équipement (spec §8).
Constants.EQUIPMENT_CATEGORY = {
	EXTINCTION = "extinction",
	EXTRICATION = "extrication",
	RESCUE = "rescue",
	MEDICAL = "medical",
	RECON = "recon",
	PROTECTION = "protection",
	RADIO = "radio",
	COMMAND = "command",
	LOGISTICS = "logistics",
}

-- Types de journal.
Constants.LOG = {
	INFO = "info",
	DISPATCH = "dispatch",
	INCIDENT = "incident",
	SUCCESS = "success",
	FAILURE = "failure",
	MONEY = "money",
	SYSTEM = "system",
}

-- Capacités opérationnelles : utilisées par les besoins des interventions.
Constants.CAPABILITY_LABEL = {
	fire = "Incendie",
	rescue = "Sauvetage",
	medical = "Secours",
	police = "Police",
	command = "Commandement",
	technical = "Technique",
}

-- Libellés de statut pour l'interface (le client ne code pas ces chaînes).
Constants.STATUS_LABEL = {
	available = "Disponible",
	dispatched = "En route",
	onscene = "Sur place",
	returning = "Retour",
	maintenance = "Atelier",
	pending = "Nouvelle",
	active = "En cours",
	resolved = "Terminée",
	failed = "Échouée",
}

return Constants
