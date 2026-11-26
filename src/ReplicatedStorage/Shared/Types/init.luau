--!strict
--[[
	Types — contrats de données partagés entre serveur et client.

	Ces alias documentent la forme des tables manipulées par les services.
	Les services restent des fonctions sur des tables simples (aucune classe
	cachée) : c'est ce qui permet de les tester hors Roblox.
]]

export type Result = {
	ok: boolean,
	message: string,
	data: any?,
}

export type Position = {
	x: number,
	z: number,
}

export type Route = {
	ax: number,
	az: number,
	bx: number,
	bz: number,
	startTime: number,
	duration: number,
	siren: boolean,
}

export type Qualification = {
	id: string,
	name: string,
	code: string?,
	category: string,
	description: string,
}

export type Capabilities = {
	fire: number?,
	rescue: number?,
	medical: number?,
	police: number?,
	command: number?,
	technical: number?,
}

export type VehicleType = {
	id: string,
	name: string,
	category: string,
	service: string,
	speed: number,
	acceleration: number,
	seats: number,
	crewRequired: number,
	driverRequired: boolean,
	qualifications: { string },
	capabilities: Capabilities,
	equipmentSlots: number,
	capacity: number,
	defaultEquipment: { { id: string, quantity: number } },
	cost: number,
	mobilizationCost: number,
	description: string,
}

export type EquipmentType = {
	id: string,
	name: string,
	category: string,
	services: { string },
	weight: number,
	cost: number,
	bonus: Capabilities,
	description: string,
}

export type IncidentStep = {
	id: string,
	label: string,
	requires: Capabilities,
	seconds: number,
}

export type IncidentType = {
	id: string,
	name: string,
	service: string,
	severity: number,
	requires: Capabilities,
	equipment: { string },
	qualifications: { string },
	steps: { IncidentStep },
	responseDeadline: number,
	victims: number,
	reward: number,
	penalty: number,
	weight: number,
	briefing: string,
}

export type Personnel = {
	id: number,
	name: string,
	grade: string,
	service: string,
	qualifications: { [string]: boolean },
	experience: number,
	fatigue: number,
	health: number,
	status: string,
	vehicleId: number?,
}

export type Vehicle = {
	id: number,
	typeId: string,
	callsign: string,
	status: string,
	condition: number,
	position: Position,
	home: Position,
	crew: { number },
	equipment: { [string]: number },
	incidentId: number?,
	route: Route?,
	repairRemaining: number,
}

export type Incident = {
	id: string,
	typeId: string,
	status: string,
	severity: number,
	position: Position,
	createdAt: number,
	deadline: number,
	assigned: { [number]: boolean },
	onScene: { [number]: boolean },
	stepIndex: number,
	stepProgress: number,
	underpoweredFor: number,
	victims: number,
	savedVictims: number,
	closedAt: number?,
	outcome: string?,
}

export type Player = {
	userId: number,
	name: string,
	role: string,
	joinedAt: number,
	lastAction: number,
}

export type Group = {
	id: number,
	name: string,
	service: string?,
	vehicles: { number },
	sectorId: number?,
	createdBy: number,
}

export type Sector = {
	id: number,
	name: string,
	x: number,
	z: number,
	radius: number,
	groupId: number?,
	createdBy: number,
}

export type Transaction = {
	time: number,
	amount: number,
	reason: string,
	balance: number,
}

export type LogEntry = {
	time: number,
	clock: string,
	kind: string,
	message: string,
}

export type World = {
	version: string,
	config: any,
	catalogs: any,
	budget: number,
	transactions: { Transaction },
	vehicles: { [number]: Vehicle },
	personnel: { [number]: Personnel },
	equipmentStock: { [string]: number },
	incidents: { [number]: Incident },
	groups: { [number]: Group },
	sectors: { [number]: Sector },
	players: { [number]: Player },
	log: { LogEntry },
	time: number,
	alarmCountdown: number,
	spawnedIncidents: number,
	finished: boolean,
	nextVehicleId: number,
	nextPersonnelId: number,
	nextIncidentId: number,
	nextGroupId: number,
	nextSectorId: number,
	rng: any,
	stats: any,
}

export type VehicleSnapshot = {
	id: number,
	typeId: string,
	name: string,
	callsign: string,
	service: string,
	status: string,
	condition: number,
	x: number,
	z: number,
	crew: { string },
	crewCount: number,
	crewRequired: number,
	equipment: { { id: string, name: string, quantity: number } },
	incidentId: number?,
	route: Route?,
}

export type IncidentSnapshot = {
	id: string,
	typeId: string,
	name: string,
	briefing: string,
	service: string,
	severity: number,
	status: string,
	x: number,
	z: number,
	victims: number,
	stepIndex: number,
	stepLabel: string,
	stepProgress: number,
	deadlineIn: number,
	assigned: { number },
	onScene: { number },
	requires: Capabilities,
}

export type Snapshot = {
	version: string,
	time: number,
	clock: string,
	budget: number,
	spent: number,
	earned: number,
	finished: boolean,
	players: { { userId: number, name: string, role: string, roleLabel: string } },
	vehicles: { VehicleSnapshot },
	personnel: { { id: number, name: string, grade: string, service: string, status: string, vehicleId: number?, fatigue: number, health: number, qualifications: { string } } },
	incidents: { IncidentSnapshot },
	groups: { { id: number, name: string, service: string?, vehicles: { number }, sectorId: number? } },
	sectors: { Sector },
	stock: { { id: string, name: string, quantity: number } },
	log: { LogEntry },
	stats: any,
	alerts: number,
}

return nil
