Kicks = Kicks or class({})

_G.tUserIds = {}

function Kicks:Init()
	self.time_to_voting = 40
	self.votes_for_kick = 6
	self.voting = nil
	self.kicks_id = {}
	self.pre_voting = {}
	
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

function Kicks:IsPlayerKicked(player_id)
	if Kicks.kicks_id and Kicks.kicks_id[player_id] then
		return true
	end
	return false
end

function Kicks:Report(player_id)
	if not player_id or not self.voting or not self.voting.init or not self.voting.reports_count then return end
	if self.voting.players_reports and self.voting.players_reports[player_id] then return end

	self.voting.players_reports[player_id] = true
	self.voting.reports_count = self.voting.reports_count + 1
	
	local init_pid = self.voting.init
	
	if self.voting.reports_count >= 6 then
		self:StopVoting(false)
		self.stats[init_pid].voting_reported = self.stats[init_pid].voting_reported + 1
	end
	
	self.stats[init_pid].reports = self.stats[init_pid].reports + 1
end

function Kicks:StartVoting(data)
	local player_init_id = data.PlayerID
	if not player_init_id then return end
	
	if self.voting then
		CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(data.PlayerID), "display_custom_error", { message = "#voting_to_kick_voiting_for_now" })
		return
	end
	
	local player_init = PlayerResource:GetPlayer(player_init_id)
	local team = player_init:GetTeam()

	if not self.reasons_for_kick[data.reason] then return end
	
	local player_target_id = self.pre_voting[player_init_id]

	self.voting = {
		playersVoted = {},
		team = team,
		reason = data.reason,
		init = data.PlayerID,
		target = player_target_id,
		votes = 1,
		players_reports = {},
		reports_count = 0,
	}

	self.stats[data.PlayerID].voting_start = self.stats[data.PlayerID].voting_start + 1
	
	self.voting.playersVoted[data.PlayerID] = true
	self:UpdateVotingForKick()
	
	local all_heroes = HeroList:GetAllHeroes()
	for _, hero in pairs(all_heroes) do
		if hero:IsRealHero() and hero:IsControllableByAnyPlayer() and (hero:GetTeam() == team)then
			EmitSoundOn("Hero_Chen.TeleportOut", hero)
		end
	end

	CustomGameEventManager:Send_ServerToTeam(team, "voting_to_kick_show_voting", { playerId = player_target_id, reason = data.reason, playerIdInit = data.PlayerID})
	CustomGameEventManager:Send_ServerToPlayer(player_init, "voting_to_kick_hide_reason", {})

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
	CustomGameEventManager:Send_ServerToTeam(self.voting.team, "voting_to_kick_hide_voting", {})
	GameRules:SendCustomMessage(successful_voting and "#voting_to_kick_player_kicked" or "#voting_to_kick_voting_failed", self.voting.target, 0)
	self.voting = nil
end

function Kicks:UpdateVotingForKick()
	if not self.voting then return end
	local max_voices_in_team = 0
	local voted_parties = {}
	for playerId = 0, 24 do
		local connectionState = PlayerResource:GetConnectionState(playerId)
		if PlayerResource:GetTeam(self.voting.target) == PlayerResource:GetTeam(playerId)
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
	if not self.voting then return end
	for _player_id, _ in pairs(self.voting.playersVoted) do
		if PlayerResource:GetPartyID(player_id) == PlayerResource:GetPartyID(_player_id) then
			return 0.5
		end
	end
	return 1
end

function Kicks:VoteYes(data)
	if not self.voting then return end
	
	self.voting.votes = self.voting.votes + self:GetVoteWeight(data.PlayerID)
	self.voting.playersVoted[data.PlayerID] = true
	self:SendDegugResult(data, "YES TOTAL VOICES: "..self.voting.votes)
	if self.voting.votes >= self.votes_for_kick then
		self.kicks_id[self.voting.target] = true
		SendToServerConsole('kickid '.. _G.tUserIds[self.voting.target]);
		self:StopVoting(true)
	end
	
	self:UpdateVotingForKick()
end

function Kicks:VoteNo(data)
	self:SendDegugResult(data, "NO")
end

function Kicks:CheckState(data)
	if self.voting and self.voting.target and data.PlayerID and (PlayerResource:GetTeam(self.voting.target) == PlayerResource:GetTeam(data.PlayerID)) then
		CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(data.PlayerID), "voting_to_kick_show_voting", {
			playerId = self.voting.target,
			reason = self.voting.reason,
			playerIdInit = self.voting.init,
			playerVoted = self.voting.playersVoted[data.PlayerID],
		})
	end
end

function Kicks:PreVoting(caster_id, target_id)
	self.pre_voting[caster_id] = target_id
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
