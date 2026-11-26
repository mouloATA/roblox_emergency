--!strict
--[[
	AudioController — sons de l'interface, ambiance et sirènes.

	Le client ne joue que des sons fournis avec Roblox (`rbxasset://`) : aucun
	asset audio n'est uploadé ni redistribué. L'ambiance et la sirène sont deux
	arrangements du même souffle continu, rejoué à des vitesses différentes.

	La sirène suit l'état réel des engins : elle démarre dès qu'un véhicule est
	engagé et s'arrête au retour. Le bouton **SON** de la barre supérieure coupe
	tout le groupe audio, sans interrompre la simulation.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))

local AudioController = {}
AudioController.__index = AudioController

local FOLDER_NAME = "ERS_Audio"
local GROUP_NAME = "Groupe"

-- Description des bruits ponctuels (identifiant de config, volume, vitesse).
local CUES = {
	click = { source = "AUDIO_CLICK", volume = 0.30, speed = 1.35 },
	confirm = { source = "AUDIO_ALERT", volume = 0.35, speed = 1.15 },
	alert = { source = "AUDIO_ALERT", volume = 0.55, speed = 1.30 },
	error = { source = "AUDIO_ERROR", volume = 0.45, speed = 0.80 },
}

function AudioController.new(options: any?): any
	local opts = options or {}
	local self: any = setmetatable({}, AudioController)
	self.soundService = opts.soundService or game:GetService("SoundService")
	self.config = opts.config or Config
	self.mounted = false
	self.muted = false
	self.folder = nil
	self.group = nil
	self.ambience = nil
	self.siren = nil
	self.cueSounds = {}
	self.sirenActive = false
	self.sirenPhase = 1
	self.knownAlerts = nil
	self.engaged = 0
	return self
end

function AudioController.createSound(self: any, name: string, source: string, volume: number, speed: number, looped: boolean): any
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = source
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.Looped = looped
	sound.SoundGroup = self.group
	sound.Parent = self.folder
	return sound
end

-- Monte le dossier audio et lance l'ambiance. Idempotent.
function AudioController.mount(self: any): ()
	if self.mounted then
		return
	end
	self.folder = self.soundService:FindFirstChild(FOLDER_NAME)
	if not self.folder then
		self.folder = Instance.new("Folder")
		self.folder.Name = FOLDER_NAME
		self.folder.Parent = self.soundService
	end

	self.group = self.folder:FindFirstChild(GROUP_NAME)
	if not self.group then
		self.group = Instance.new("SoundGroup")
		self.group.Name = GROUP_NAME
		self.group.Volume = 1
		self.group.Parent = self.folder
	end
	self.group.Volume = self.muted and 0 or 1

	self.ambience = self:createSound(
		"Ambiance",
		self.config.AUDIO_AMBIENCE,
		self.config.AUDIO_AMBIENCE_VOLUME,
		self.config.AUDIO_AMBIENCE_SPEED,
		true
	)
	self.ambience.Playing = true
	self.mounted = true

	-- Alternance de la sirène : une boucle légère côté client, sans réseau.
	task.spawn(function()
		while self.mounted do
			task.wait(self.config.AUDIO_SIREN_PERIOD)
			self:tickSiren()
		end
	end)
end

function AudioController.getCue(self: any, cue: string): any?
	local spec = CUES[cue]
	if not spec then
		return nil
	end
	if not self.cueSounds[cue] then
		self.cueSounds[cue] = self:createSound(
			"Bruit_" .. cue,
			self.config[spec.source],
			spec.volume,
			spec.speed,
			false
		)
	end
	return self.cueSounds[cue]
end

-- Joue un bruit ponctuel. Retourne `false` si le son est coupé.
function AudioController.play(self: any, cue: string): boolean
	if self.muted then
		return false
	end
	if not self.mounted then
		self:mount()
	end
	local sound = self:getCue(cue)
	if not sound then
		return false
	end
	local spec = CUES[cue]
	sound.PlaybackSpeed = spec.speed
	sound.Volume = spec.volume
	sound.TimePosition = 0
	sound.Playing = true
	return true
end

function AudioController.startSiren(self: any): ()
	self.sirenActive = true
	self.sirenPhase = 1
	if self.muted then
		return
	end
	if not self.siren then
		self.siren = self:createSound(
			"Sirene",
			self.config.AUDIO_SIREN,
			self.config.AUDIO_SIREN_VOLUME,
			self.config.AUDIO_SIREN_SPEEDS[1],
			true
		)
	end
	self.siren.PlaybackSpeed = self.config.AUDIO_SIREN_SPEEDS[1]
	self.siren.Playing = true
end

function AudioController.stopSiren(self: any): ()
	self.sirenActive = false
	if self.siren then
		self.siren.Playing = false
	end
end

-- Alterne les deux tons de la sirène. Appelé par la boucle de `mount`.
function AudioController.tickSiren(self: any): number?
	if not self.sirenActive or self.muted or not self.siren then
		return nil
	end
	self.sirenPhase = self.sirenPhase == 1 and 2 or 1
	self.siren.PlaybackSpeed = self.config.AUDIO_SIREN_SPEEDS[self.sirenPhase]
	return self.sirenPhase
end

function AudioController.setMuted(self: any, muted: boolean): boolean
	self.muted = muted == true
	if self.group then
		self.group.Volume = self.muted and 0 or 1
	end
	if self.muted then
		self:stopSiren()
	elseif self.engaged > 0 then
		self:startSiren()
	end
	return self.muted
end

function AudioController.toggleMuted(self: any): boolean
	return self:setMuted(not self.muted)
end

--[[
	Suit le snapshot : alerte sur une nouvelle urgence, sirène tant qu'un engin
	est engagé. Le premier snapshot ne sonne pas (il ne fait qu'initialiser).
]]
function AudioController.update(self: any, snapshot: any): ()
	if not snapshot then
		return
	end

	local current = {}
	local newAlert = false
	for _, incident in ipairs(snapshot.incidents or {}) do
		if incident.status == Constants.INCIDENT_STATUS.PENDING
			or incident.status == Constants.INCIDENT_STATUS.ACTIVE then
			current[incident.id] = true
			if self.knownAlerts and not self.knownAlerts[incident.id] then
				newAlert = true
			end
		end
	end
	if self.knownAlerts and newAlert then
		self:play("alert")
	end
	self.knownAlerts = current

	local engaged = 0
	for _, vehicle in ipairs(snapshot.vehicles or {}) do
		if vehicle.status == Constants.VEHICLE_STATUS.DISPATCHED
			or vehicle.status == Constants.VEHICLE_STATUS.ON_SCENE then
			engaged += 1
		end
	end
	self.engaged = engaged
	if engaged > 0 and not self.sirenActive then
		self:startSiren()
	elseif engaged == 0 and self.sirenActive then
		self:stopSiren()
	end
end

function AudioController.unmount(self: any): ()
	self.mounted = false
	self:stopSiren()
	if self.folder then
		self.folder:Destroy()
		self.folder = nil
	end
	self.group = nil
	self.ambience = nil
	self.siren = nil
	table.clear(self.cueSounds)
end

return AudioController
