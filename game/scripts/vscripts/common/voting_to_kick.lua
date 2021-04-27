_G.votingForKick = nil
_G.kicks = {}
_G.tUserIds = {}

local timeToVoting = 40
local votesToKick = 6
local reasonCheck = {
	["feeding"] = true,
	["ability_abuse"] = true,
	["hateful_talk"] = true,
	["afk"] = true,
}

local steamIDsToDebugg = {
	[104356809] = 1, -- Sheodar
	[93913347] = 1, -- Darklord
}

RegisterCustomEventListener("voting_to_kick_reason_is_picked", function(data)
	if not _G.votingForKick and IsServer() then
		_G.votingForKick = {}
		local playerInit = PlayerResource:GetPlayer(data.PlayerID)
		local heroInit = PlayerResource:GetSelectedHeroEntity(data.PlayerID)
		local heroTarget = heroInit.wantToKick

		if not heroTarget then return end
		if not reasonCheck[data.reason] then return end
		local playerTargetID = heroTarget:GetPlayerOwnerID()

		_G.votingForKick.playersVoted = {}
		_G.votingForKick.reason = data.reason
		_G.votingForKick.init = data.PlayerID
		_G.votingForKick.target =playerTargetID
		_G.votingForKick.votes = 1
		_G.votingForKick.playersVoted[data.PlayerID] = true
		UpdateVotingForKick()
		local all_heroes = HeroList:GetAllHeroes()
		for _, hero in pairs(all_heroes) do
			if hero:IsRealHero() and hero:IsControllableByAnyPlayer() and (hero:GetTeam() == playerInit:GetTeam())then
				EmitSoundOn("Hero_Chen.TeleportOut", hero)
			end
		end

		CustomGameEventManager:Send_ServerToTeam(playerInit:GetTeam(), "voting_to_kick_show_voting", { playerId = playerTargetID, reason = data.reason, playerIdInit = data.PlayerID})
		CustomGameEventManager:Send_ServerToPlayer(playerInit, "voting_to_kick_hide_reason", {})

		Timers:CreateTimer("start_voting_to_kick", {
			useGameTime = false,
			endTime = timeToVoting,
			callback = function()
				CustomGameEventManager:Send_ServerToTeam(playerInit:GetTeam(), "voting_to_kick_hide_voting", {})
				if _G.votingForKick.votes < votesToKick then
					GameRules:SendCustomMessageToTeam("#voting_to_kick_voting_failed", playerInit:GetTeam(), _G.votingForKick.target, 0)
				end
				_G.votingForKick = nil
				return nil
			end
		})

	else
		CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(data.PlayerID), "display_custom_error", { message = "#voting_to_kick_voiting_for_now" })
	end
end)

function SendDegugResult(data, text)
	local all_heroes = HeroList:GetAllHeroes()
	for _, hero in pairs(all_heroes) do
		if hero:IsRealHero() and hero:IsControllableByAnyPlayer() and steamIDsToDebugg[PlayerResource:GetSteamAccountID(hero:GetPlayerID())] then
			CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(hero:GetPlayerID()), "voting_to_kick_debug_print", {playerVotedId = data.PlayerID, vote=text, total=votesToKick})
		end
	end
end

function UpdateVotingForKick()
	if not _G.votingForKick then return end
	local maxVoicesInTeam = 0
	local votedParties = {}
	for playerId = 0, 24 do
		local connectionState = PlayerResource:GetConnectionState(playerId)
		if PlayerResource:GetTeam(_G.votingForKick.target) == PlayerResource:GetTeam(playerId)
		and (connectionState == DOTA_CONNECTION_STATE_CONNECTED or connectionState == DOTA_CONNECTION_STATE_NOT_YET_CONNECTED) then
			local party = tostring(PlayerResource:GetPartyID(playerId));
			if votedParties[party] then
				maxVoicesInTeam = maxVoicesInTeam + 0.5
			else
				maxVoicesInTeam = maxVoicesInTeam + 1
				votedParties[party] = true
			end
		end
	end
	votesToKick = math.floor(maxVoicesInTeam/2)
end

function GetVoteWeight(player_id)
	if not _G.votingForKick then return end
	for _player_id, _ in pairs(_G.votingForKick.playersVoted) do
		if PlayerResource:GetPartyID(player_id) == PlayerResource:GetPartyID(_player_id) then
			return 0.5
		end
	end
	return 1
end

RegisterCustomEventListener("voting_to_kick_vote_yes", function(data)
	if _G.votingForKick then
		_G.votingForKick.votes = _G.votingForKick.votes + GetVoteWeight(data.PlayerID)
		_G.votingForKick.playersVoted[data.PlayerID] = true
		SendDegugResult(data, "YES TOTAL VOICES: ".._G.votingForKick.votes)
		if _G.votingForKick.votes >= votesToKick then
			_G.kicks[_G.votingForKick.target] = true
			Timers:RemoveTimer("start_voting_to_kick")
			CustomGameEventManager:Send_ServerToTeam(PlayerResource:GetPlayer(_G.votingForKick.init):GetTeam(), "voting_to_kick_hide_voting", {})
			SendToServerConsole('kickid '.. _G.tUserIds[_G.votingForKick.target]);
			GameRules:SendCustomMessage("#voting_to_kick_player_kicked", _G.votingForKick.target, 0)
			_G.votingForKick = nil
		end
		UpdateVotingForKick()
	end
end)

RegisterCustomEventListener("voting_to_kick_vote_no", function(data)
	SendDegugResult(data, "NO")
end)

RegisterCustomEventListener("voting_to_kick_check_voting_state", function(data)
	if _G.votingForKick and _G.votingForKick.target and data.PlayerID and (PlayerResource:GetTeam(_G.votingForKick.target) == PlayerResource:GetTeam(data.PlayerID)) then
		CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(data.PlayerID), "voting_to_kick_show_voting", {
			playerId = _G.votingForKick.target,
			reason = _G.votingForKick.reason,
			playerIdInit = _G.votingForKick.init,
			playerVoted = _G.votingForKick.playersVoted[data.PlayerID],
		})
	end
end)
