--!strict
--[[
	Qualifications — référentiel des qualifications opérationnelles.

	Les codes « COS … » viennent du vocabulaire du mod CSP-IRG. Le cahier des
	charges demande explicitement de ne pas leur inventer une signification :
	ils restent donc paramétrables et leur sens exact est à documenter avec la
	source (voir docs/DataModel.md).
]]

local Qualifications = {}

Qualifications.list = {
	{
		id = "COS",
		name = "Chef d'opération de secours",
		code = "COS",
		category = "command",
		description = "Code de qualification CSP-IRG. Sens exact à documenter avec la source.",
	},
	{
		id = "COS15",
		name = "COS — variante 15",
		code = "COS 15",
		category = "command",
		description = "Variante paramétrable du code COS. Aucune signification inventée.",
	},
	{
		id = "COS_POL",
		name = "COS — variante police",
		code = "COS POL",
		category = "command",
		description = "Variante paramétrable du code COS. Aucune signification inventée.",
	},
	{
		id = "COS_GEN",
		name = "COS — variante gendarmerie",
		code = "COS GEN",
		category = "command",
		description = "Variante paramétrable du code COS. Aucune signification inventée.",
	},
	{
		id = "COS_DDE",
		name = "COS — variante technique",
		code = "COS DDE",
		category = "command",
		description = "Variante paramétrable du code COS. Aucune signification inventée.",
	},
	{
		id = "CHEF_GROUPE",
		name = "Chef de groupe",
		category = "command",
		description = "Commande plusieurs agrès et coordonne un secteur.",
	},
	{
		id = "CHEF_AGRES",
		name = "Chef d'agrès",
		category = "command",
		description = "Responsable de l'engin et de son équipage.",
	},
	{
		id = "CONDUCTEUR",
		name = "Conducteur",
		code = "COND",
		category = "operations",
		description = "Habilité à conduire un engin en intervention.",
	},
	{
		id = "SAPEUR",
		name = "Sapeur-pompier",
		category = "fire",
		description = "Qualification de base incendie et secours.",
	},
	{
		id = "SECOURISTE",
		name = "Secouriste",
		category = "medical",
		description = "Prise en charge des victimes et gestes de premiers secours.",
	},
	{
		id = "MEDECIN",
		name = "Médecin",
		category = "medical",
		description = "Direction médicale des opérations de secours à personne.",
	},
	{
		id = "INFIRMIER",
		name = "Infirmier",
		category = "medical",
		description = "Soutien sanitaire et soins d'urgence.",
	},
	{
		id = "POLICIER",
		name = "Policier",
		category = "police",
		description = "Sécurisation, circulation et interpellation.",
	},
	{
		id = "GENDARME",
		name = "Gendarme",
		category = "police",
		description = "Sécurisation hors zone police et coordination militaire.",
	},
	{
		id = "TECHNICIEN",
		name = "Technicien",
		code = "TEC",
		category = "technical",
		description = "Réseaux, levage, dépannage et logistique technique.",
	},
	{
		id = "PLONGEUR",
		name = "Plongeur",
		category = "fire",
		description = "Sauvetage aquatique et recherche de victimes en milieu noyé.",
	},
	{
		id = "MAITRE_CHIEN",
		name = "Maître-chien",
		category = "operations",
		description = "Recherche de victimes et appui cynophile aux équipes engagées.",
	},
	{
		id = "TIREUR",
		name = "Tireur",
		category = "police",
		description = "Neutralisation d'une menace par arme de service.",
	},
	{
		id = "TIREUR_ELITE",
		name = "Tireur d'élite",
		category = "police",
		description = "Tir de précision depuis un point d'appui, sur décision du chef.",
	},
	{
		id = "ECLAIREUR",
		name = "Éclaireur",
		category = "police",
		description = "Reconnaissance discrète et description des lieux avant l'assaut.",
	},
	{
		id = "PROFILEUR",
		name = "Profileur",
		category = "police",
		description = "Analyse du comportement d'un forcené ou d'un preneur d'otage.",
	},
	{
		id = "NEGOCIATEUR",
		name = "Négociateur",
		category = "police",
		description = "Négociation de crise et recherche d'une issue sans violence.",
	},
	{
		id = "DEMINEUR",
		name = "Démineur",
		category = "technical",
		description = "Examen et neutralisation d'un engin explosif ou d'un colis suspect.",
	},
}

Qualifications.map = {}
for _, qualification in ipairs(Qualifications.list) do
	Qualifications.map[qualification.id] = qualification
end

function Qualifications.get(id: string): any?
	return Qualifications.map[id]
end

function Qualifications.exists(id: string): boolean
	return Qualifications.map[id] ~= nil
end

function Qualifications.label(id: string): string
	local qualification = Qualifications.map[id]
	return qualification and qualification.name or id
end

return Qualifications
