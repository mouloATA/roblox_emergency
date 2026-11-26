--!strict
--[[
	Result — valeurs de retour uniformes des services.

	Toute action d'API renvoie { ok, message, data } :
	- ok      : l'action a réellement été appliquée ;
	- message : texte utilisateur en français ;
	- data    : charge utile optionnelle (identifiants, objets créés…).
]]

local Result = {}

export type Result = {
	ok: boolean,
	message: string,
	data: any?,
}

function Result.ok(message: string?, data: any?): Result
	return {
		ok = true,
		message = message or "OK",
		data = data,
	}
end

function Result.err(message: string?, data: any?): Result
	return {
		ok = false,
		message = message or "Action refusée",
		data = data,
	}
end

function Result.isOk(result: Result?): boolean
	return result ~= nil and result.ok == true
end

function Result.unwrap(result: Result): any?
	return result.data
end

return Result
