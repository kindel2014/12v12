Kicks = Kicks or class({})

_G.votingForKick = nil
_G.kicks = {}
_G.tUserIds = {}

function Kicks:Init()
	self.time_to_voting = 40
	self.votes_for_kick = 6
	self.reasons_for_kick = {
		["feeding"] = true,
		["ability_abuse"] = true,
		["hateful_talk"] = true,
		["afk"] = true,
	}
	self.debug_steam_ids = {
		[104356809] = 1, -- Sheodar
		[93913347] = 1, -- Darklord
	}
	self.stats = {}

	for player_id = 0, 24 do
		self.stats[player_id] = {
			reports = 0,
			voting_start = 0,
			voting_reported = 0
		}
	end

	CustomGameEventManager:RegisterListener("voting_to_kick_reason_is_picked",function(_, keys)
		self:StartVoting(keys)
	end)
	CustomGameEventManager:RegisterListener("voting_to_kick_vote_yes",function(_, keys)
		self:VoteYes(keys)
	end)
	CustomGameEventManager:RegisterListener("voting_to_kick_vote_no",function(_, keys)
		self:VoteNo(keys)
	end)
	CustomGameEventManager:RegisterListener("voting_to_kick_check_voting_state",function(_, keys)
		self:CheckState(keys)
	end)
	CustomGameEventManager:RegisterListener("voting_to_kick_report",function(_, keys)
		self:Report(keys.PlayerID)
	end)
end

function Kicks:Report(player_id)
	if not player_id or not _G.votingForKick or not _G.votingForKick.init or not _G.votingForKick.reports_count then return end
	if _G.votingForKick.players_reports and _G.votingForKick.players_reports[player_id] then return end

	_G.votingForKick.players_reports[player_id] = true
	_G.votingForKick.reports_count = _G.votingForKick.reports_count + 1
	
	local init_pid = _G.votingForKick.init
	
	if _G.votingForKick.reports_count >= 6 then
		self:StopVoting(false)
		self.stats[init_pid].voting_reported = self.stats[init_pid].voting_reported + 1
	end
	
	self.stats[init_pid].reports = self.stats[init_pid].reports + 1
end

function Kicks:StartVoting(data)
	if _G.votingForKick then
		CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(data.PlayerID), "display_custom_error", { message = "#voting_to_kick_voiting_for_now" })
		return
	end
	
	local playerInit = PlayerResource:GetPlayer(data.PlayerID)
	local team = playerInit:GetTeam()
	local heroInit = PlayerResource:GetSelectedHeroEntity(data.PlayerID)
	local heroTarget = heroInit.wantToKick

	if not heroTarget then return end
	if not self.reasons_for_kick[data.reason] then return end
	
	local playerTargetID = heroTarget:GetPlayerOwnerID()

	_G.votingForKick = {
		playersVoted = {},
		team = team,
		reason = data.reason,
		init = data.PlayerID,
		target = playerTargetID,
		votes = 1,
		players_reports = {},
		reports_count = 0,
	}

	self.stats[data.PlayerID].voting_start = self.stats[data.PlayerID].voting_start + 1
	
	_G.votingForKick.playersVoted[data.PlayerID] = true
	self:UpdateVotingForKick()
	
	local all_heroes = HeroList:GetAllHeroes()
	for _, hero in pairs(all_heroes) do
		if hero:IsRealHero() and hero:IsControllableByAnyPlayer() and (hero:GetTeam() ==team)then
			EmitSoundOn("Hero_Chen.TeleportOut", hero)
		end
	end

	CustomGameEventManager:Send_ServerToTeam(team, "voting_to_kick_show_voting", { playerId = playerTargetID, reason = data.reason, playerIdInit = data.PlayerID})
	CustomGameEventManager:Send_ServerToPlayer(playerInit, "voting_to_kick_hide_reason", {})

	Timers:CreateTimer("start_voting_to_kick", {
		useGameTime = false,
		endTime = self.time_to_voting,
		callback = function()
			self:StopVoting(false)
			return nil
		end
	})
end

function Kicks:StopVoting(successful_voting)
	Timers:RemoveTimer("start_voting_to_kick")
	CustomGameEventManager:Send_ServerToTeam(_G.votingForKick.team, "voting_to_kick_hide_voting", {})
	GameRules:SendCustomMessage(successful_voting and "#voting_to_kick_player_kicked" or "#voting_to_kick_voting_failed", _G.votingForKick.target, 0)
	_G.votingForKick = nil
end

function Kicks:UpdateVotingForKick()
	if not _G.votingForKick then return end
	local max_voices_in_team = 0
	local voted_parties = {}
	for playerId = 0, 24 do
		local connectionState = PlayerResource:GetConnectionState(playerId)
		if PlayerResource:GetTeam(_G.votingForKick.target) == PlayerResource:GetTeam(playerId)
			and (connectionState == DOTA_CONNECTION_STATE_CONNECTED or connectionState == DOTA_CONNECTION_STATE_NOT_YET_CONNECTED) then
			local party = tostring(PlayerResource:GetPartyID(playerId));
			if voted_parties[party] then
				max_voices_in_team = max_voices_in_team + 0.5
			else
				max_voices_in_team = max_voices_in_team + 1
				voted_parties[party] = true
			end
		end
	end
	self.votes_for_kick = math.floor(max_voices_in_team/2)
end

function Kicks:SendDegugResult(data, text)
	for player_id = 0, 24 do
		if self.debug_steam_ids[PlayerResource:GetSteamAccountID(player_id)] then
			CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(player_id), "voting_to_kick_debug_print", {
				playerVotedId = data.PlayerID, 
				vote = text,
				total = self.votes_for_kick
			})
		end
	end
end


function Kicks:GetVoteWeight(player_id)
	if not _G.votingForKick then return end
	for _player_id, _ in pairs(_G.votingForKick.playersVoted) do
		if PlayerResource:GetPartyID(player_id) == PlayerResource:GetPartyID(_player_id) then
			return 0.5
		end
	end
	return 1
end

function Kicks:VoteYes(data)
	if not _G.votingForKick then return end
	
	_G.votingForKick.votes = _G.votingForKick.votes + self:GetVoteWeight(data.PlayerID)
	_G.votingForKick.playersVoted[data.PlayerID] = true
	self:SendDegugResult(data, "YES TOTAL VOICES: ".._G.votingForKick.votes)
	if _G.votingForKick.votes >= self.votes_for_kick then
		_G.kicks[_G.votingForKick.target] = true
		SendToServerConsole('kickid '.. _G.tUserIds[_G.votingForKick.target]);
		self:StopVoting(true)
	end
	
	self:UpdateVotingForKick()
end

function Kicks:VoteNo(data)
	self:SendDegugResult(data, "NO")
end

function Kicks:CheckState(data)
	if _G.votingForKick and _G.votingForKick.target and data.PlayerID and (PlayerResource:GetTeam(_G.votingForKick.target) == PlayerResource:GetTeam(data.PlayerID)) then
		CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(data.PlayerID), "voting_to_kick_show_voting", {
			playerId = _G.votingForKick.target,
			reason = _G.votingForKick.reason,
			playerIdInit = _G.votingForKick.init,
			playerVoted = _G.votingForKick.playersVoted[data.PlayerID],
		})
	end
end

function Kicks:GetReports(player_id)
	return self.stats[player_id] and self.stats[player_id].reports or 0
end

function Kicks:GetInitVotings(player_id)
	return self.stats[player_id] and self.stats[player_id].voting_start or 0
end

function Kicks:GetFailedVotings(player_id)
	return self.stats[player_id] and self.stats[player_id].voting_reported or 0
end
