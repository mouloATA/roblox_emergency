--!strict
-- Objectifs originaux pour les lieux de Val-des-Secours. Le second appel est
-- découvert sur place, au bilan d'une équipe ou à l'alerte du garde forestier.
local Missions = {}

Missions.list = {
	{
		id = "eglise", name = "Fumée au clocher",
		briefing = "L’alarme retentit à l’église Saint-Marc. Équipez le FPT d’un sac de secours avant son départ et gardez le VSAV disponible pour le parvis.",
		trigger = "arrival",
		objectives = {
			{ label = "Maîtriser le feu de la sacristie", typeId = "FEU_COMMERCE", x = 59.5, z = 38.5,
				briefing = "Le personnel de l'église est sorti. La fumée vient de la sacristie, à côté du clocher." },
			{ label = "Évacuer la personne intoxiquée", typeId = "MALAISE", x = 55, z = 41,
				briefing = "L'équipe arrivée au parvis a retrouvé une personne intoxiquée. Un VSAV est demandé." },
		},
	},
	{
		id = "route", name = "Collision au carrefour",
		briefing = "Collision avenue Centrale. Envoyez le FPT pour la désincarcération, le VPC pour le balisage et le VSAV pour les blessés. Prévoyez un départ feu.",
		trigger = "assessment",
		objectives = {
			{ label = "Dégager et évacuer les blessés", typeId = "ACCIDENT_CIRCULATION", x = 49, z = 49,
				briefing = "Une portière est bloquée. Balisez le carrefour et désincarcérez les occupants pour le transport." },
			{ label = "Éteindre la voiture en contrebas", typeId = "FEU_VEHICULE", x = 53, z = 49,
				briefing = "Après le balisage, l'équipe signale un véhicule vide qui commence à brûler en bord de chaussée." },
		},
	},
	{
		id = "foret", name = "Feu de lisière",
		briefing = "La végétation brûle au nord du parc boisé. Un garde fait le tour du sentier pendant que les secours tiennent la lisière.",
		trigger = "radio", delay = 35,
		objectives = {
			{ label = "Éteindre le front de végétation", typeId = "FEU_FORET", x = 59.5, z = 17.5,
				briefing = "Un feu de végétation longe le chemin nord du parc. Attaquez les foyers et surveillez les reprises." },
			{ label = "Secourir le promeneur au sentier", typeId = "MALAISE", x = 55, z = 12,
				briefing = "Le garde a rejoint un promeneur gêné par les fumées au départ du sentier. Évacuez-le vers l’hôpital." },
		},
	},
}

Missions.byId = {}
for _, def in ipairs(Missions.list) do
	Missions.byId[def.id] = def
end

return Missions
