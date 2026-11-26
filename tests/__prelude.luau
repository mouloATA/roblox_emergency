--!nonstrict
--[[
	__prelude — alias de `__env` conservé pour les suites de tests.

	L'en-tête injecté par tools/check.ps1 définit déjà `game`, `require`, etc.
	Ce module existe pour que les suites puissent écrire :

		local __env = require("./__prelude")
]]

return require("./__env")
