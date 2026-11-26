--!strict
--[[
	Config — réglages globaux d'Emergency Response Simulator.
	Tout l'équilibrage se règle ici ; les catalogues de contenu vivent dans
	`Shared/Catalogs`. Aucun nombre magique ailleurs dans le code.

	Les valeurs sont volontairement regroupées par domaine pour que
	l'équilibrage reste lisible et testable.
]]

local Config = {}

Config.VERSION = "0.3.0"
Config.GAME_NAME = "Emergency Response Simulator"
Config.GAME_SHORT = "ERS"
Config.CITY_NAME = "Val-des-Secours"

-- ─────────────────────────────────────────────────────────────
-- Cadence et réseau
-- ─────────────────────────────────────────────────────────────
Config.TICK_RATE = 1 -- Hz, simulation serveur
Config.SNAPSHOT_RATE = 4 -- Hz, envoi de l'état aux clients
Config.ACTION_COOLDOWN = 0.15 -- secondes entre deux intentions d'un joueur
Config.MAX_COMMAND_LENGTH = 64 -- caractères, champs texte réseau

-- ─────────────────────────────────────────────────────────────
-- Sauvegarde
-- ─────────────────────────────────────────────────────────────
Config.SAVE_STORE = "ERS_World"
Config.SAVE_KEY = "world"
Config.SAVE_INTERVAL = 60 -- secondes entre deux sauvegardes automatiques
Config.SAVE_RETRIES = 3
Config.SAVE_RETRY_DELAY = 2

-- ─────────────────────────────────────────────────────────────
-- Économie
-- ─────────────────────────────────────────────────────────────
Config.START_BUDGET = 25000
Config.MAX_FLEET = 40
Config.REPAIR_COST_PER_POINT = 12 -- € par point d'état manquant
Config.REPAIR_SECONDS_PER_POINT = 1.5 -- secondes d'atelier par point manquant
Config.MOBILIZATION_REFUND = 0 -- une mobilisation n'est jamais remboursée

-- ─────────────────────────────────────────────────────────────
-- Parc, personnel et stock de départ (prototype)
-- ─────────────────────────────────────────────────────────────
Config.START_VEHICLES = { "FPT", "VSAV", "VPC" }
Config.START_PERSONNEL = 12
Config.START_EQUIPMENT = {
	ARI = 6,
	EXTINCTEUR = 6,
	TUYAU = 6,
	DEFIB = 3,
	SAC_SECOURS = 4,
	BRANCARD = 2,
	RADIO = 6,
	PC_MOBILE = 1,
	BALISE = 4,
	CORDE = 2,
}

-- ─────────────────────────────────────────────────────────────
-- Alertes : rotation de départ, jouable avec la flotte initiale
-- (les interventions police/technique s'ouvrent avec les achats)
-- ─────────────────────────────────────────────────────────────
Config.PROTOTYPE_SCENARIOS = {
	"FEU_VEHICULE",
	"ACCIDENT_VICTIME",
	"FEU_HABITATION",
	"MALAISE",
	"ACCIDENT_DOMESTIQUE",
	"VICTIME_INCONSCIENTE",
}
Config.MAX_ACTIVE_INCIDENTS = 2
Config.FIRST_ALERT_DELAY = 10 -- secondes avant la première alerte
Config.ALERT_INTERVAL = 55 -- secondes entre deux alertes automatiques
Config.UNDERPOWER_FAIL_SECONDS = 60 -- sans moyens suffisants, l'intervention échoue
Config.RESPONSE_WARNING_RATIO = 0.7 -- seuil d'alerte avant la date limite

-- ─────────────────────────────────────────────────────────────
-- Carte / déplacements (coordonnées normalisées 0..100)
-- ─────────────────────────────────────────────────────────────
Config.MAP_SIZE = 100
Config.WORLD_SCALE = 6 -- studs par unité de carte pour la scène 3D
Config.HQ_X = 14
Config.HQ_Z = 62
Config.TRAVEL_BASE = 4 -- secondes fixes (sortie de caserne)
Config.TRAVEL_PER_UNIT = 0.8 -- secondes par unité de carte / vitesse
Config.RETURN_FACTOR = 1.4 -- le retour est plus rapide qu'un départ
Config.SIREN_FACTOR = 0.75 -- gain de temps en sirène
Config.ARRIVAL_RADIUS = 0.8 -- unité de carte

-- ─────────────────────────────────────────────────────────────
-- Horloge de service
-- ─────────────────────────────────────────────────────────────
Config.SHIFT_SECONDS = 720 -- 12 minutes réelles = 24 h simulées
Config.SHIFT_START_HOUR = 6
Config.DAY_SECONDS = 86400

-- ─────────────────────────────────────────────────────────────
-- Personnel
-- ─────────────────────────────────────────────────────────────
Config.MAX_FATIGUE = 100
Config.REST_FATIGUE = 85 -- au-delà, plus d'engagement possible
Config.FATIGUE_PER_SECOND = 0.05 -- fatigue pendant une intervention
Config.FATIGUE_RECOVERY = 0.10 -- récupération hors intervention
Config.FATIGUE_ASSIGNED = 0.01 -- fatigue passive d'un personnel affecté
Config.MIN_HEALTH = 1

-- ─────────────────────────────────────────────────────────────
-- Journal / alertes
-- ─────────────────────────────────────────────────────────────
Config.LOG_LIMIT = 120
Config.TRANSACTION_LIMIT = 120
Config.SNAPSHOT_LOG_LIMIT = 60

-- ─────────────────────────────────────────────────────────────
-- Interface
-- ─────────────────────────────────────────────────────────────
Config.DESIGN_WIDTH = 1600
Config.DESIGN_HEIGHT = 900
Config.UI_SCALE_MIN = 0.55
Config.UI_SCALE_MAX = 1.6
Config.TOAST_SECONDS = 5

-- ─────────────────────────────────────────────────────────────
-- Scène 3D (Phase 1 : ville générée, source unique `Shared/City`)
-- ─────────────────────────────────────────────────────────────
Config.GROUND_COLOR = Color3.fromRGB(96, 108, 86)
Config.OUTSKIRTS_COLOR = Color3.fromRGB(88, 102, 80)
Config.PATH_COLOR = Color3.fromRGB(150, 140, 120)
Config.HEDGE_COLOR = Color3.fromRGB(54, 82, 54)
Config.ROAD_COLOR = Color3.fromRGB(52, 52, 56)
Config.BUILDING_COLOR = Color3.fromRGB(84, 82, 76)
Config.HQ_COLOR = Color3.fromRGB(164, 42, 36)
Config.SCENE_BUILDINGS = 14
Config.CITY_SEED = 20261117 -- plan identique sur le serveur et chez les clients
Config.SIDEWALK_COLOR = Color3.fromRGB(150, 148, 142)
Config.MARKING_COLOR = Color3.fromRGB(226, 222, 206)
Config.ROOF_COLOR = Color3.fromRGB(72, 66, 62)
Config.WINDOW_COLOR = Color3.fromRGB(44, 58, 70)
Config.GRASS_COLOR = Color3.fromRGB(62, 96, 62)
Config.FLOOR_HEIGHT = 3.4 -- studs par étage

-- Éclairage : l'heure suit `world.time`, l'ambiance reste douce pour garder
-- la ville lisible à toute heure.
Config.LIGHTING_LATITUDE = 46
Config.LIGHTING_BRIGHTNESS = 2.4
Config.LIGHTING_AMBIENT = Color3.fromRGB(74, 82, 92)
Config.LIGHTING_OUTDOOR_AMBIENT = Color3.fromRGB(116, 126, 140)
Config.LIGHTING_HAZE_COLOR = Color3.fromRGB(186, 198, 210)
Config.LIGHTING_HAZE_DECAY = Color3.fromRGB(104, 112, 126)
Config.LIGHTING_ATMOSPHERE_DENSITY = 0.22
Config.LIGHTING_ATMOSPHERE_HAZE = 1.1
-- Nuit : l'ambiance reste lisible, les lampadaires prennent le relais.
Config.LIGHTING_NIGHT_BRIGHTNESS = 0.8
Config.LIGHTING_NIGHT_AMBIENT = Color3.fromRGB(58, 68, 88)
Config.LIGHTING_NIGHT_OUTDOOR_AMBIENT = Color3.fromRGB(86, 98, 120)
Config.LIGHTING_NIGHT_HAZE_COLOR = Color3.fromRGB(40, 50, 66)
Config.LIGHTING_DAWN_HOUR = 5 -- début de l'aube (facteur 0)
Config.LIGHTING_DAY_HOUR = 7 -- plein jour
Config.LIGHTING_DUSK_HOUR = 19 -- début du crépuscule (facteur 1)
Config.LIGHTING_NIGHT_HOUR = 21 -- nuit complète
Config.LIGHTING_LAMP_COLOR = Color3.fromRGB(255, 214, 150)
Config.LIGHTING_LAMP_RANGE = 26
Config.LIGHTING_LAMP_BRIGHTNESS = 1.4
Config.LIGHTING_WINDOW_NIGHT = Color3.fromRGB(255, 206, 138)

-- Ciel procédural : étoiles et lune générées en code (aucun asset externe).
Config.SKY_RADIUS = 1400
Config.SKY_STARS = 220
Config.SKY_STAR_MIN = 14
Config.SKY_STAR_MAX = 26
Config.SKY_MOON_SIZE = 80

-- Audio : sons fournis avec le client Roblox (`rbxasset://`), sans upload.
Config.AUDIO_AMBIENCE = "rbxasset://sounds/action_falling.ogg"
Config.AUDIO_AMBIENCE_VOLUME = 0.10
Config.AUDIO_AMBIENCE_SPEED = 0.55
Config.AUDIO_SIREN = "rbxasset://sounds/action_falling.ogg"
Config.AUDIO_SIREN_VOLUME = 0.22
Config.AUDIO_SIREN_SPEEDS = { 0.78, 1.12 }
Config.AUDIO_SIREN_PERIOD = 0.9
Config.AUDIO_CLICK = "rbxasset://sounds/action_jump.mp3"
Config.AUDIO_ALERT = "rbxasset://sounds/volume_slider.ogg"
Config.AUDIO_ERROR = "rbxasset://sounds/action_jump_land.mp3"

-- ─────────────────────────────────────────────────────────────
-- Caméra isométrique (unités de carte)
-- ─────────────────────────────────────────────────────────────
Config.CAMERA_YAW = 45 -- degrés, orientation de repos
Config.CAMERA_PITCH = 36 -- degrés sous l'horizon
Config.CAMERA_FOV = 34
Config.CAMERA_DISTANCE = 420
Config.CAMERA_DISTANCE_MIN = 160
Config.CAMERA_DISTANCE_MAX = 760
Config.CAMERA_ZOOM_STEP = 40
Config.CAMERA_PAN_STEP = 8 -- unités par appui clavier
Config.CAMERA_SMOOTH = 9 -- vitesse de lissage (par seconde)
Config.CAMERA_MARGIN = 8 -- marge de déplacement autour de la ville

-- ─────────────────────────────────────────────────────────────
-- Temps simulé (contrôlé par le PC, validé par le serveur)
-- ─────────────────────────────────────────────────────────────
Config.TIME_SCALES = { 0, 1, 2, 4 } -- 0 = pause
Config.GROUP_HOTKEYS = 6 -- boutons de groupe 1 à 6 sur la barre

return Config
