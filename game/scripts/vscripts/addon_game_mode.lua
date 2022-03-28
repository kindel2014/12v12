if not IsDedicatedServer() and not IsInToolsMode() then error("") end
-- Rebalance the distribution of gold and XP to make for a better 10v10 game
local GOLD_SCALE_FACTOR_INITIAL = 1
local GOLD_SCALE_FACTOR_FINAL = 2.5
local GOLD_SCALE_FACTOR_FADEIN_SECONDS = (60 * 60) -- 60 minutes
local XP_SCALE_FACTOR_INITIAL = 2
local XP_SCALE_FACTOR_FINAL = 2
local XP_SCALE_FACTOR_FADEIN_SECONDS = (60 * 60) -- 60 minutes

local game_start = true

-- Anti feed system
local TROLL_FEED_DISTANCE_FROM_FOUNTAIN_TRIGGER = 3000 -- Distance from allince Fountain
local TROLL_FEED_BUFF_BASIC_TIME = (60 * 10)   -- 10 minutes
local TROLL_FEED_TOTAL_RESPAWN_TIME_MULTIPLE = 2.5 -- x2.5 respawn time. If you respawn 100sec, after debuff you respawn 250sec
local TROLL_FEED_INCREASE_BUFF_AFTER_DEATH = 60 -- 1 minute
local TROLL_FEED_RATIO_KD_TO_TRIGGER_MIN = -5 -- (Kills+Assists-Deaths)
local TROLL_FEED_NEED_TOKEN_TO_BUFF = 3
local TROLL_FEED_TOKEN_TIME_DIES_WITHIN = (60 * 1.5) -- 1.5 minutes
local TROLL_FEED_TOKEN_DURATION = (60 * 5) -- 5 minutes
local TROLL_FEED_MIN_RESPAWN_TIME = 60 -- 1 minute
local TROLL_FEED_SYSTEM_ASSISTS_TO_KILL_MULTI = 1 -- 10 assists = 10 "kills"

local TROLL_FEED_FORBIDDEN_TO_BUY_ITEMS = {
	item_smoke_of_deceit = true,
	item_ward_observer = true,
	item_ward_sentry = true,
	item_tome_of_knowledge = true,
}

--Requirements to Buy Divine Rapier
local NET_WORSE_FOR_RAPIER_MIN = 20000

--Max neutral items for each player (hero/stash/courier)
_G.MAX_NEUTRAL_ITEMS_FOR_PLAYER = 3

bonusGoldApplied = {}

require("protected_custom_events")
require("common/init")
require("util")
require("neutral_items_drop_choice")
require("gpm_lib")
require("game_options/game_options")
require("shuffle_team")
require("custom_pings")
require("chat_commands/admin_commands")

Precache = require( "precache" )

WebApi.customGame = "Dota12v12"

LinkLuaModifier("modifier_dummy_inventory", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_core_courier", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_patreon_courier", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_shadow_amulet_thinker", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_fountain_phasing", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_abandoned", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_gold_bonus", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_troll_feed_token", 'anti_feed_system/modifier_troll_feed_token', LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_troll_feed_token_couter", 'anti_feed_system/modifier_troll_feed_token_couter', LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_troll_debuff_stop_feed", 'anti_feed_system/modifier_troll_debuff_stop_feed', LUA_MODIFIER_MOTION_NONE)

LinkLuaModifier("modifier_super_tower","game_options/modifiers_lib/modifier_super_tower", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_mega_creep","game_options/modifiers_lib/modifier_mega_creep", LUA_MODIFIER_MOTION_NONE)

LinkLuaModifier("modifier_delayed_damage","common/game_perks/modifier_lib/delayed_damage", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("creep_secret_shop","creep_secret_shop", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_stronger_builds","modifier_stronger_builds", LUA_MODIFIER_MOTION_NONE)


_G.lastDeathTimes = {}
_G.lastHeroKillers = {}
_G.lastHerosPlaceLastDeath = {}
_G.tableRadiantHeroes = {}
_G.tableDireHeroes = {}
_G.newRespawnTimes = {}

_G.tPlayersMuted = {}
_G.CUSTOM_GAME_STATS = CUSTOM_GAME_STATS or {}
for player_id = 0, 24 do
	_G.tPlayersMuted[player_id] = {}
	if not CUSTOM_GAME_STATS[player_id] then
		CUSTOM_GAME_STATS[player_id] = {
			perk = "",
			networth = 0,
			experiance = 0,
			building_damage = 0,
			hero_damage = 0,
			damage_taken = 0,
			wards = {
				npc_dota_observer_wards = 0,
				npc_dota_sentry_wards = 0,
			},
			killed_heroes = {},
			total_healing = 0,
		}
	end
end
if CMegaDotaGameMode == nil then
	_G.CMegaDotaGameMode = class({}) -- put CMegaDotaGameMode in the global scope
	--refer to: http://stackoverflow.com/questions/6586145/lua-require-with-global-local
end

function Activate()
	CMegaDotaGameMode:InitGameMode()
end

_G.ItemKVs = {}
_G.abandoned_players = {}
_G.first_dc_players = {}

function CMegaDotaGameMode:InitGameMode()
	_G.ItemKVs = LoadKeyValues("scripts/npc/npc_block_items_for_troll.txt")
	print( "10v10 Mode Loaded!" )

	local neutral_items = LoadKeyValues("scripts/npc/neutral_items.txt")

	_G.neutralItems = {}
	self.spawned_couriers = {}
	self.disconnected_players = {}
	for _, data in pairs( neutral_items ) do
		for item, turn in pairs( data.items ) do
			if turn == 1 then
				_G.neutralItems[item] = true
			end
		end
	end

	self.last_player_orders = {}

	for player_id = 0, 24 do
		self.last_player_orders[player_id] = 0
	end

	-- Adjust team limits
	GameRules:SetCustomGameTeamMaxPlayers( DOTA_TEAM_GOODGUYS, 12 )
	GameRules:SetCustomGameTeamMaxPlayers( DOTA_TEAM_BADGUYS, 12 )
	GameRules:SetStrategyTime( 0.0 )
	GameRules:SetShowcaseTime( 0.0 )

	-- Hook up gold & xp filters
    GameRules:GetGameModeEntity():SetItemAddedToInventoryFilter( Dynamic_Wrap( CMegaDotaGameMode, "ItemAddedToInventoryFilter" ), self )
	GameRules:GetGameModeEntity():SetModifyGoldFilter( Dynamic_Wrap( CMegaDotaGameMode, "FilterModifyGold" ), self )
	GameRules:GetGameModeEntity():SetModifyExperienceFilter( Dynamic_Wrap(CMegaDotaGameMode, "FilterModifyExperience" ), self )
	GameRules:GetGameModeEntity():SetBountyRunePickupFilter( Dynamic_Wrap(CMegaDotaGameMode, "FilterBountyRunePickup" ), self )
	GameRules:GetGameModeEntity():SetModifierGainedFilter( Dynamic_Wrap( CMegaDotaGameMode, "ModifierGainedFilter" ), self )
	GameRules:GetGameModeEntity():SetExecuteOrderFilter(Dynamic_Wrap(CMegaDotaGameMode, 'ExecuteOrderFilter'), self)
	GameRules:GetGameModeEntity():SetDamageFilter( Dynamic_Wrap( CMegaDotaGameMode, "DamageFilter" ), self )
	GameRules:SetCustomGameBansPerTeam(12)

	GameRules:GetGameModeEntity():SetUseDefaultDOTARuneSpawnLogic(true)
	
	GameRules:GetGameModeEntity():SetTowerBackdoorProtectionEnabled( true )
	GameRules:GetGameModeEntity():SetPauseEnabled(IsInToolsMode())
	GameRules:SetGoldTickTime( 0.3 ) -- default is 0.6
	GameRules:LockCustomGameSetupTeamAssignment(true)

	if GetMapName() == "dota_tournament" then
		GameRules:SetCustomGameSetupAutoLaunchDelay(20)
	else
		GameRules:SetCustomGameSetupAutoLaunchDelay(10)
	end

	GameRules:GetGameModeEntity():SetKillableTombstones( true )
	GameRules:GetGameModeEntity():SetFreeCourierModeEnabled(true)
	Convars:SetInt("dota_max_physical_items_purchase_limit", 100)
	if IsInToolsMode() then
		GameRules:GetGameModeEntity():SetDraftingBanningTimeOverride(0)
	end

	ListenToGameEvent("dota_match_done", Dynamic_Wrap(CMegaDotaGameMode, 'OnMatchDone'), self)
	ListenToGameEvent('game_rules_state_change', Dynamic_Wrap(CMegaDotaGameMode, 'OnGameRulesStateChange'), self)
	ListenToGameEvent( "npc_spawned", Dynamic_Wrap( CMegaDotaGameMode, "OnNPCSpawned" ), self )
	ListenToGameEvent( "entity_killed", Dynamic_Wrap( CMegaDotaGameMode, 'OnEntityKilled' ), self )
	ListenToGameEvent("dota_player_pick_hero", Dynamic_Wrap(CMegaDotaGameMode, "OnHeroPicked"), self)
	ListenToGameEvent('player_connect_full', Dynamic_Wrap(CMegaDotaGameMode, 'OnConnectFull'), self)
	ListenToGameEvent('player_disconnect', Dynamic_Wrap(CMegaDotaGameMode, 'OnPlayerDisconnect'), self)
	ListenToGameEvent( "player_chat", Dynamic_Wrap( CMegaDotaGameMode, "OnPlayerChat" ), self )
	ListenToGameEvent("dota_player_learned_ability", 	Dynamic_Wrap(CMegaDotaGameMode, "OnPlayerLearnedAbility" ),  self)
	
	self.m_CurrentGoldScaleFactor = GOLD_SCALE_FACTOR_INITIAL
	self.m_CurrentXpScaleFactor = XP_SCALE_FACTOR_INITIAL
	GameRules:GetGameModeEntity():SetThink( "OnThink", self, 5 )

	ListenToGameEvent("dota_player_used_ability", function(event)
		local hero = PlayerResource:GetSelectedHeroEntity(event.PlayerID)
		if not hero then return end
		if event.abilityname == "night_stalker_darkness" then
			local ability = hero:FindAbilityByName(event.abilityname)
			CustomGameEventManager:Send_ServerToAllClients("time_nightstalker_darkness", {
				duration = ability:GetSpecialValueFor("duration")
			})
		end
		if event.abilityname == "item_blink" then
			local oldpos = hero:GetAbsOrigin()
			Timers:CreateTimer( 0.01, function()
				local pos = hero:GetAbsOrigin()

				if IsInBugZone(pos) then
					FindClearSpaceForUnit(hero, oldpos, false)
				end
			end)
		end
	end, nil)

	_G.raxBonuses = {}
	_G.raxBonuses[DOTA_TEAM_GOODGUYS] = 0
	_G.raxBonuses[DOTA_TEAM_BADGUYS] = 0

	Timers:CreateTimer( 0.6, function()
		for i = 0, GameRules:NumDroppedItems() - 1 do
			local container = GameRules:GetDroppedItem( i )

			if container then
				local item = container:GetContainedItem()

				if item and item.GetAbilityName and not item:IsNull() and  item:GetAbilityName():find( "item_ward_" ) then
					local owner = item:GetOwner()

					if owner and not owner:IsNull() then
						local team = owner:GetTeam()
						local fountain
						local multiplier

						if team == DOTA_TEAM_GOODGUYS then
							multiplier = -350
							fountain = Entities:FindByName( nil, "ent_dota_fountain_good" )
						elseif team == DOTA_TEAM_BADGUYS then
							multiplier = -650
							fountain = Entities:FindByName( nil, "ent_dota_fountain_bad" )
						end

						local fountain_pos = fountain:GetAbsOrigin()

						if ( fountain_pos - container:GetAbsOrigin() ):Length2D() > 1200 then
							local pos_item = fountain_pos:Normalized() * multiplier + RandomVector( RandomFloat( 0, 200 ) ) + fountain_pos
							pos_item.z = fountain_pos.z

							container:SetAbsOrigin( pos_item )
							CustomGameEventManager:Send_ServerToPlayer( owner:GetPlayerOwner(), "display_custom_error", { message = "#dropped_wards_return_error" } )
						end
					end
				end
			end
		end

		return 0.6
	end )

	GameOptions:Init()
	UniquePortraits:Init()
	Battlepass:Init()
	CustomChat:Init()
	GamePerks:Init()
	GiftCodes:Init()
	CustomPings:Init()
	Kicks:Init()
	NeutralItemsDrop:Init()
end

function IsInBugZone(pos)
	local sum = pos.x + pos.y
	return sum > 14150 or sum < -14350 or pos.x > 7750 or pos.x < -7750 or pos.y > 7500 or pos.y < -7300
end

function GetActivePlayerCountForTeam(team)
    local number = 0
    for x=0,DOTA_MAX_TEAM do
        local pID = PlayerResource:GetNthPlayerIDOnTeam(team,x)
        if PlayerResource:IsValidPlayerID(pID) and (PlayerResource:GetConnectionState(pID) == 1 or PlayerResource:GetConnectionState(pID) == 2) then
            number = number + 1
        end
    end
    return number
end

function GetActiveHumanPlayerCountForTeam(team)
    local number = 0
    for x=0,DOTA_MAX_TEAM do
        local pID = PlayerResource:GetNthPlayerIDOnTeam(team,x)
        if PlayerResource:IsValidPlayerID(pID) and not self:isPlayerBot(pID) and (PlayerResource:GetConnectionState(pID) == 1 or PlayerResource:GetConnectionState(pID) == 2) then
            number = number + 1
        end
    end
    return number
end

function otherTeam(team)
    if team == DOTA_TEAM_BADGUYS then
        return DOTA_TEAM_GOODGUYS
    elseif team == DOTA_TEAM_GOODGUYS then
        return DOTA_TEAM_BADGUYS
    end
    return -1
end

function UnitInSafeZone(unit , unitPosition)
	local teamNumber = unit:GetTeamNumber()
	local fountains = Entities:FindAllByClassname('ent_dota_fountain')
	local allyFountainPosition
	for i, focusFountain in pairs(fountains) do
		if focusFountain:GetTeamNumber() == teamNumber then
			allyFountainPosition = focusFountain:GetAbsOrigin()
		end
	end
	return ((allyFountainPosition - unitPosition):Length2D()) <= TROLL_FEED_DISTANCE_FROM_FOUNTAIN_TRIGGER
end

function GetHeroKD(unit)
	if unit and unit:IsRealHero() then
		return (unit:GetKills() + (unit:GetAssists() * TROLL_FEED_SYSTEM_ASSISTS_TO_KILL_MULTI) - unit:GetDeaths())
	end
	return 0
end

function ItWorstKD(unit) -- use minimun TROLL_FEED_RATIO_KD_TO_TRIGGER_MIN
	local unitTeam = unit:GetTeamNumber()
	local focusTableHeroes

	if unitTeam == DOTA_TEAM_GOODGUYS then
		focusTableHeroes = _G.tableRadiantHeroes
	elseif unitTeam == DOTA_TEAM_BADGUYS then
		focusTableHeroes = _G.tableDireHeroes
	end

	for i, focusHero in pairs(focusTableHeroes) do
		local unitKD = GetHeroKD(unit)
		if unitKD > TROLL_FEED_RATIO_KD_TO_TRIGGER_MIN then
			return false
		elseif GetHeroKD(focusHero) <= unitKD and unit ~= focusHero then
			return false
		end
	end
	return true
end
function CMegaDotaGameMode:SetTeamColors()
	local ggcolor = {
		{70,70,255},
		{0,255,255},
		{255,0,255},
		{255,255,0},
		{255,165,0},
		{0,255,0},
		{255,0,0},
		{75,0,130},
		{109,49,19},
		{255,20,147},
		{128,128,0},
		{255,255,255}
	}
	local bgcolor = {
		{255,135,195},
		{160,180,70},
		{100,220,250},
		{0,128,0},
		{165,105,0},
		{153,50,204},
		{0,128,128},
		{0,0,165},
		{128,0,0},
		{180,255,180},
		{255,127,80},
		{0,0,0}
	}
	local team_colors = {
		[DOTA_TEAM_GOODGUYS] = { 0 , ggcolor },
		[DOTA_TEAM_BADGUYS] = { 0 , bgcolor },
	}

	for player_id = 0, PlayerResource:GetPlayerCount()-1 do
		local team = PlayerResource:GetTeam(player_id)
		local counter = team_colors[team][1] + 1
		team_colors[team][1] = counter
		local color = team_colors[team][2][counter]

		if color then
			CustomPings:SetColor(player_id, color)
			PlayerResource:SetCustomPlayerColor(player_id, color[1], color[2], color[3])
		end
	end
end

function CMegaDotaGameMode:OnHeroPicked(event)
	local hero = EntIndexToHScript(event.heroindex)
	if not hero then return end

	if hero:GetTeamNumber() == DOTA_TEAM_GOODGUYS then
		table.insert(_G.tableRadiantHeroes, hero)
	end

	if hero:GetTeamNumber() == DOTA_TEAM_BADGUYS then
		table.insert(_G.tableDireHeroes, hero)
	end

	local player_id = hero:GetPlayerOwnerID()
	if not IsInToolsMode() and player_id and _G.tUserIds[player_id] and not self.disconnected_players[player_id] then
		SendToServerConsole('kickid '.. _G.tUserIds[player_id]);
	end
end
---------------------------------------------------------------------------
-- Filter: DamageFilter
---------------------------------------------------------------------------
function CMegaDotaGameMode:DamageFilter(event)
	local entindex_victim_const = event.entindex_victim_const
	local entindex_attacker_const = event.entindex_attacker_const
	local entindex_inflictor_const = event.entindex_inflictor_const
	local target
	local attacker
	local ability

	if (entindex_victim_const) then target = EntIndexToHScript(entindex_victim_const) end
	if (entindex_attacker_const) then attacker = EntIndexToHScript(entindex_attacker_const) end
	if (entindex_inflictor_const) then ability = EntIndexToHScript(entindex_inflictor_const) end

	if event.damage and target and not target:IsNull() and target:IsAlive() and attacker and not attacker:IsNull() and attacker:IsAlive() and attacker.GetPlayerOwnerID and attacker:GetPlayerOwnerID() then
		local attacker_id = attacker:GetPlayerOwnerID()
		if attacker_id >= 0 then
			if target.IsRealHero and target:IsRealHero() then
				CUSTOM_GAME_STATS[attacker_id].hero_damage = CUSTOM_GAME_STATS[attacker_id].hero_damage + event.damage
			elseif target.IsBuilding and target:IsBuilding() then
				CUSTOM_GAME_STATS[attacker_id].building_damage = CUSTOM_GAME_STATS[attacker_id].building_damage + event.damage
			end
		end
	end

	if target and target:HasModifier("modifier_troll_debuff_stop_feed") and (target:GetHealth() <= event.damage) and (attacker ~= target) and (attacker:GetTeamNumber()~=DOTA_TEAM_NEUTRALS) then
		if ItWorstKD(target) and (not (UnitInSafeZone(target, _G.lastHerosPlaceLastDeath[target]))) then
			local newTime = target:FindModifierByName("modifier_troll_debuff_stop_feed"):GetRemainingTime() + TROLL_FEED_INCREASE_BUFF_AFTER_DEATH
			--target:RemoveModifierByName("modifier_troll_debuff_stop_feed")
			local normalRespawnTime =  target:GetRespawnTime()
			local addRespawnTime = normalRespawnTime * (TROLL_FEED_TOTAL_RESPAWN_TIME_MULTIPLE - 1)

			if addRespawnTime + normalRespawnTime < TROLL_FEED_MIN_RESPAWN_TIME then
				addRespawnTime = TROLL_FEED_MIN_RESPAWN_TIME - normalRespawnTime
			end
			target:AddNewModifier(target, nil, "modifier_troll_debuff_stop_feed", { duration = newTime, addRespawnTime = addRespawnTime })
		end
		target:Kill(nil, target)
	end

	if target and target.delay_damage_by_perk and target.delay_damage_by_perk_duration and event.damage > 10 then
		local delayed_damage = event.damage * (target.delay_damage_by_perk / 100)
		local black_list_for_delay = {
			["delayed_damage_perk"] = true,
			["skeleton_king_reincarnation"] = true,
		}
		if (not ability or not black_list_for_delay[ability:GetName()]) and (not event.damagetype_const or event.damagetype_const > 0) then
			event.damage = event.damage - delayed_damage
			target:AddNewModifier(target, nil, "modifier_delayed_damage", {
				duration = target.delay_damage_by_perk_duration,
				attacker_ent = entindex_attacker_const,
				damage_type = event.damagetype_const,
				damage = delayed_damage
			})
		end
	end

	return true
end

---------------------------------------------------------------------------
-- Event: OnEntityKilled
---------------------------------------------------------------------------
function CMegaDotaGameMode:OnEntityKilled( event )
	local entindex_killed = event.entindex_killed
    local entindex_attacker = event.entindex_attacker
	local killedUnit
    local killer
	local name

	if (entindex_killed) then
		killedUnit = EntIndexToHScript(entindex_killed)
		name = killedUnit:GetUnitName()
	end
	if (entindex_attacker) then killer = EntIndexToHScript(entindex_attacker) end

	local raxRespawnTimeWorth = {
		npc_dota_goodguys_range_rax_top = 2,
		npc_dota_goodguys_melee_rax_top = 4,
		npc_dota_goodguys_range_rax_mid = 2,
		npc_dota_goodguys_melee_rax_mid = 4,
		npc_dota_goodguys_range_rax_bot = 2,
		npc_dota_goodguys_melee_rax_bot = 4,
		npc_dota_badguys_range_rax_top = 2,
		npc_dota_badguys_melee_rax_top = 4,
		npc_dota_badguys_range_rax_mid = 2,
		npc_dota_badguys_melee_rax_mid = 4,
		npc_dota_badguys_range_rax_bot = 2,
		npc_dota_badguys_melee_rax_bot = 4,
	}
	if raxRespawnTimeWorth[name] ~= nil then
		local team = killedUnit:GetTeam()
		raxBonuses[team] = raxBonuses[team] + raxRespawnTimeWorth[name]
		SendOverheadEventMessage( nil, OVERHEAD_ALERT_MANA_ADD, killedUnit, raxRespawnTimeWorth[name], nil )
		GameRules:SendCustomMessage("#destroyed_" .. string.sub(name,10,#name - 4),-1,0)
		if raxBonuses[team] == 18 then
			raxBonuses[team] = 22
			if team == DOTA_TEAM_BADGUYS then
				GameRules:SendCustomMessage("#destroyed_badguys_all_rax",-1,0)
			else
				GameRules:SendCustomMessage("#destroyed_goodguys_all_rax",-1,0)
			end
		end
	end
	if killedUnit:IsClone() then killedUnit = killedUnit:GetCloneSource() end
	--print("fired")
    if killer and killedUnit and killedUnit:IsRealHero() and not killedUnit:IsReincarnating() then
		local player_id = -1
		if killer:IsRealHero() and killer.GetPlayerID then
			player_id = killer:GetPlayerID()
		else
			if killer:GetPlayerOwnerID() ~= -1 then
				player_id = killer:GetPlayerOwnerID()
			end
		end
		if player_id ~= -1 then
			local kh = CUSTOM_GAME_STATS[player_id].killed_heroes

			kh[name] = kh[name] and kh[name] + 1 or 1
		end


	    local dotaTime = GameRules:GetDOTATime(false, false)
	    --local timeToStartReduction = 0 -- 20 minutes
	    local respawnReduction = 0.65 -- Original Reduction rate

	    -- Reducation Rate slowly increases after a certain time, eventually getting to original levels, this is to prevent games lasting too long
	    --if dotaTime > timeToStartReduction then
	    --	dotaTime = dotaTime - timeToStartReduction
	    --	respawnReduction = respawnReduction + ((dotaTime / 60) / 100) -- 0.75 + Minutes of Game Time / 100 e.g. 25 minutes fo game time = 0.25
	    --end

	    --if respawnReduction > 1 then
	    --	respawnReduction = 1
	    --end

	    local timeLeft = killedUnit:GetRespawnTime()
	 	timeLeft = timeLeft * respawnReduction -- Respawn time reduced by a rate

	    -- Disadvantaged teams get 5 seconds less respawn time for every missing player
	    local herosTeam = GetActivePlayerCountForTeam(killedUnit:GetTeamNumber())
	    local opposingTeam = GetActivePlayerCountForTeam(otherTeam(killedUnit:GetTeamNumber()))
	    local difference = herosTeam - opposingTeam

	    local addedTime = 0
	    if difference < 0 then
	        addedTime = difference * 5
	        local RespawnReductionRate = string.format("%.2f", tostring(respawnReduction))
		    local OriginalRespawnTime = tostring(math.floor(timeLeft))
		    local TimeToReduce = tostring(math.floor(addedTime))
		    local NewRespawnTime = tostring(math.floor(timeLeft + addedTime))
	        --GameRules:SendCustomMessage( "ReductionRate:"  .. " " .. RespawnReductionRate .. " " .. "OriginalTime:" .. " " ..OriginalRespawnTime .. " " .. "TimeToReduce:" .. " " ..TimeToReduce .. " " .. "NewRespawnTime:" .. " " .. NewRespawnTime, 0, 0)
	    end

	    timeLeft = timeLeft + addedTime
	    --print(timeLeft)

	    local rax_bonus = raxBonuses[killedUnit:GetTeam()] - raxBonuses[killedUnit:GetOpposingTeamNumber()]
	    if rax_bonus < 0 then rax_bonus = 0 end

		timeLeft = timeLeft + rax_bonus

	    if timeLeft < 1 then
	        timeLeft = 1
	    end

		if killedUnit and (not killedUnit:HasModifier("modifier_troll_debuff_stop_feed")) and (not ItWorstKD(killedUnit)) then
			killedUnit:SetTimeUntilRespawn(timeLeft)
		end
    end

	if killedUnit and killedUnit:IsRealHero() and (PlayerResource:GetSelectedHeroEntity(killedUnit:GetPlayerID())) then
		_G.lastHeroKillers[killedUnit] = killer
		_G.lastHerosPlaceLastDeath[killedUnit] = killedUnit:GetOrigin()
		if (killer ~= killedUnit) then
			_G.lastDeathTimes[killedUnit] = GameRules:GetGameTime()
		end
	end

end

LinkLuaModifier("modifier_rax_bonus", LUA_MODIFIER_MOTION_NONE)


function CMegaDotaGameMode:OnNPCSpawned(event)
	local spawnedUnit = EntIndexToHScript(event.entindex)
	local tokenTrollCouter = "modifier_troll_feed_token_couter"

	-- Apply bonus gold
	if not GameOptions:OptionsIsActive("no_winrate_gold_bonus") then
		if CMegaDotaGameMode.winrates and spawnedUnit and not spawnedUnit:IsNull() and spawnedUnit:IsRealHero()
		and not spawnedUnit.bonusGoldApplied and CMegaDotaGameMode.winrates[spawnedUnit:GetUnitName()] then
			local player_id = spawnedUnit:GetPlayerOwnerID()
			local player_stats = CustomNetTables:GetTableValue("game_state", "player_stats")
			local b_no_bonus
			if player_stats and player_stats[tostring(player_id)] and player_stats[tostring(player_id)].lastWinnerHeroes then
				b_no_bonus = table.contains(player_stats[tostring(player_id)].lastWinnerHeroes, spawnedUnit:GetUnitName())
			end
			if not bonusGoldApplied[player_id] and not b_no_bonus then
				local winrate = math.min(CMegaDotaGameMode.winrates[spawnedUnit:GetUnitName()]  * 100, 49.99)
				-- if you change formula here, change it in hero_selection_overlay.js too
				local gold = math.floor((-100 * winrate + 5100) / 5) * 5

				spawnedUnit:AddNewModifier(spawnedUnit, nil, "modifier_gold_bonus", { duration = 300, gold = gold})
				bonusGoldApplied[spawnedUnit:GetPlayerOwnerID()] = true
			end
		end
	end

	Timers:CreateTimer(0.1, function()
		if spawnedUnit and not spawnedUnit:IsNull() and ((spawnedUnit.IsTempestDouble and spawnedUnit:IsTempestDouble()) or (spawnedUnit.IsClone and spawnedUnit:IsClone())) then
			local playerId = spawnedUnit:GetPlayerOwnerID()
			if GamePerks.choosed_perks[playerId] then
				local perkName = GamePerks.choosed_perks[playerId]
				spawnedUnit:AddNewModifier(spawnedUnit, nil, perkName, {duration = -1})
				local mainHero = PlayerResource:GetSelectedHeroEntity(playerId)
				local perkStacks = mainHero:GetModifierStackCount(perkName, mainHero)
				spawnedUnit:SetModifierStackCount(perkName, nil, perkStacks)
			end
		end
	end)

	if spawnedUnit and spawnedUnit.reduceCooldownAfterRespawn
	and _G.lastHeroKillers[spawnedUnit] and not _G.lastHeroKillers[spawnedUnit]:IsNull() then
		local killersTeam = _G.lastHeroKillers[spawnedUnit]:GetTeamNumber()
		if killersTeam ~=spawnedUnit:GetTeamNumber() and killersTeam~= DOTA_TEAM_NEUTRALS then
			for i = 0, 20 do
				local item = spawnedUnit:GetItemInSlot(i)
				if item then
					local cooldown_remaining = item:GetCooldownTimeRemaining()
					if cooldown_remaining > 0 then
						item:EndCooldown()
						item:StartCooldown(cooldown_remaining-(cooldown_remaining/100*spawnedUnit.reduceCooldownAfterRespawn))
					end
				end
			end
			for i = 0, 30 do
				local ability = spawnedUnit:GetAbilityByIndex(i)
				if ability then
					local cooldown_remaining = ability:GetCooldownTimeRemaining()
					if cooldown_remaining > 0 then
						ability:EndCooldown()
						ability:StartCooldown(cooldown_remaining-(cooldown_remaining/100*spawnedUnit.reduceCooldownAfterRespawn))
					end
				end
			end
		end
		spawnedUnit.reduceCooldownAfterRespawn = false
	end
	-- Assignment of tokens during quick death, maximum 3
	if spawnedUnit and (_G.lastDeathTimes[spawnedUnit] ~= nil) and (spawnedUnit:GetDeaths() > 1)
	and ((GameRules:GetGameTime() - _G.lastDeathTimes[spawnedUnit]) < TROLL_FEED_TOKEN_TIME_DIES_WITHIN)
	and not spawnedUnit:HasModifier("modifier_troll_debuff_stop_feed") and (_G.lastHeroKillers[spawnedUnit]~=spawnedUnit)
	and (not (UnitInSafeZone(spawnedUnit, _G.lastHerosPlaceLastDeath[spawnedUnit]))) and (_G.lastHeroKillers[spawnedUnit]
	and not _G.lastHeroKillers[spawnedUnit]:IsNull() and _G.lastHeroKillers[spawnedUnit]:GetTeamNumber()~=DOTA_TEAM_NEUTRALS) then
		local maxToken = TROLL_FEED_NEED_TOKEN_TO_BUFF
		local currentStackTokenCouter = spawnedUnit:GetModifierStackCount(tokenTrollCouter, spawnedUnit)
		local needToken = currentStackTokenCouter + 1
		if needToken > maxToken then
			needToken = maxToken
		end
		spawnedUnit:AddNewModifier(spawnedUnit, nil, tokenTrollCouter, { duration = TROLL_FEED_TOKEN_DURATION })
		spawnedUnit:AddNewModifier(spawnedUnit, nil, "modifier_troll_feed_token", { duration = TROLL_FEED_TOKEN_DURATION })
		spawnedUnit:SetModifierStackCount(tokenTrollCouter, spawnedUnit, needToken)
	end

	-- Issuing a debuff if 3 quick deaths have accumulated and the hero has the worst KD in the team
	if spawnedUnit:GetModifierStackCount(tokenTrollCouter, spawnedUnit) == 3 and ItWorstKD(spawnedUnit) then
		spawnedUnit:RemoveModifierByName(tokenTrollCouter)
		local normalRespawnTime = spawnedUnit:GetRespawnTime()
		local addRespawnTime = normalRespawnTime * (TROLL_FEED_TOTAL_RESPAWN_TIME_MULTIPLE - 1)
		if addRespawnTime + normalRespawnTime < TROLL_FEED_MIN_RESPAWN_TIME then
			addRespawnTime = TROLL_FEED_MIN_RESPAWN_TIME - normalRespawnTime
		end
		GameRules:SendCustomMessage("#anti_feed_system_add_debuff_message", spawnedUnit:GetPlayerID(), 0)
		spawnedUnit:AddNewModifier(spawnedUnit, nil, "modifier_troll_debuff_stop_feed", { duration = TROLL_FEED_BUFF_BASIC_TIME, addRespawnTime = addRespawnTime })
	end

	local owner = spawnedUnit:GetOwner()
	local name = spawnedUnit:GetUnitName()

	if owner and owner.GetPlayerID and ( name == "npc_dota_sentry_wards" or name == "npc_dota_observer_wards" ) then
		local player_id = owner:GetPlayerID()

		CUSTOM_GAME_STATS[player_id].wards[name] = CUSTOM_GAME_STATS[player_id].wards[name] + 1

		Timers:CreateTimer(0.04, function()
			ReloadTimerHoldingCheckerForPlayer(player_id)
			return nil
		end)


		-- Allow placing sentry wards in your own camps but automatically destroy them just before the end of the minute mark.
		Timers:NextTick(function()
			if not IsValidEntity(spawnedUnit) or not spawnedUnit:IsAlive() then return end

			local list = Entities:FindAllByClassname("trigger_multiple")
			local find_name = "neutralcamp_good"
			if owner:GetTeam() == DOTA_TEAM_BADGUYS then
				find_name = "neutralcamp_evil"
			end

			for _, trigger in pairs(list) do
				if trigger:GetName():find(find_name) ~= nil then
					if IsInTriggerBox(trigger, 12, spawnedUnit:GetAbsOrigin()) then
						local time = GameRules:GetDOTATime(false,false)
						local duration = 59.5 - (time % 60)

						local observer_modifier = spawnedUnit:FindModifierByName("modifier_item_buff_ward")
						if observer_modifier then
							observer_modifier:SetDuration(duration, true)
						end

						local observer_modifier = spawnedUnit:FindModifierByName("modifier_item_ward_true_sight")
						if observer_modifier then
							observer_modifier:SetDuration(duration, true)
						end

						break
					end
				end
			end
		end)
	end

	if spawnedUnit:IsRealHero() then
		spawnedUnit:AddNewModifier(spawnedUnit, nil, "modifier_rax_bonus", {})
		local playerId = spawnedUnit:GetPlayerID()

		Timers:CreateTimer(1, function()
			UniquePortraits:UpdatePortraitsDataFromPlayer(playerId)
		end)

		if not spawnedUnit.firstTimeSpawned then
			spawnedUnit.firstTimeSpawned = true
		end

		Timers:CreateTimer(0, function()
			CreateDummyInventoryForPlayer(playerId)
		end)

		local player = PlayerResource:GetPlayer(playerId)
		if player and not player.checked_courier_secret_shop then
			CheckSuppCourier(spawnedUnit:GetPlayerOwnerID())
		end
	end
end

function CheckSuppCourier(player_id)
	local connect_state = PlayerResource:GetConnectionState(player_id)
	if connect_state == DOTA_CONNECTION_STATE_ABANDONED then return end

	if connect_state ~= DOTA_CONNECTION_STATE_CONNECTED then
		Timers:CreateTimer(1, function() CheckSuppCourier(player_id) end)
		return
	end
	Timers:CreateTimer(2, function()
		local courier = PlayerResource:GetPreferredCourierForPlayer(player_id)
		if courier and not courier:IsNull() then
			if Supporters:GetLevel(player_id) > 0 then
				courier:AddNewModifier(courier, nil, "creep_secret_shop", { duration = -1 })
				PlayerResource:GetPlayer(player_id).checked_courier_secret_shop = true
			end
		else
			Timers:CreateTimer(1, function() CheckSuppCourier(player_id) end)
		end
	end)
end

function CMegaDotaGameMode:CreateCourierForPlayer(pos, player_id)
	local player = PlayerResource:GetPlayer(player_id)
	if player then
		local c_state = PlayerResource:GetConnectionState(player_id)
		if c_state == DOTA_CONNECTION_STATE_CONNECTED or c_state == DOTA_CONNECTION_STATE_NOT_YET_CONNECTED then
			local courier = player:SpawnCourierAtPosition(pos + RandomVector(RandomFloat(10,25)))
			self.spawned_couriers[player_id] = courier
			for i = 0, 23 do
				courier:SetControllableByPlayer(i, false)
			end
			courier:SetControllableByPlayer(player_id, true)
		elseif not c_state == DOTA_CONNECTION_STATE_ABANDONED then
			Timers:CreateTimer(0.1, function()
				CMegaDotaGameMode:CreateCourierForPlayer(pos, player_id)
			end)
		end
	else
		Timers:CreateTimer(0.1, function()
			CMegaDotaGameMode:CreateCourierForPlayer(pos, player_id)
		end)
	end
end

function CMegaDotaGameMode:ModifierGainedFilter(filterTable)

	local disableHelpResult = DisableHelp.ModifierGainedFilter(filterTable)
	if disableHelpResult == false then
		return false
	end

	local parent = filterTable.entindex_parent_const and filterTable.entindex_parent_const ~= 0 and EntIndexToHScript(filterTable.entindex_parent_const)

	if parent and filterTable.name_const and filterTable.name_const == "modifier_item_shadow_amulet_fade" then
		filterTable.duration = 15
		parent:AddNewModifier(parent, nil, "modifier_shadow_amulet_thinker", {})
	end

	if parent.isDummy then
		return false
	end

	--[[ BUFF AMPLIFY LOGIC PART ]]--

	local caster = filterTable.entindex_caster_const and filterTable.entindex_caster_const ~= 0 and EntIndexToHScript(filterTable.entindex_caster_const)
	if not caster or not parent then return end

	local ability = filterTable.entindex_ability_const and filterTable.entindex_ability_const ~= 0 and EntIndexToHScript(filterTable.entindex_ability_const)
	local m_name = filterTable.name_const

	local is_amplified_perk = amplified_modifier[m_name] or counter_updaters[m_name] or self_updaters[m_name]
	if ability then
		is_amplified_perk = is_amplified_perk and (not common_buffs_not_amplify_by_skills[m_name] or not common_buffs_not_amplify_by_skills[m_name][ability:GetAbilityName()])
	end

	local is_correct_source = (parent:GetTeam() == caster:GetTeam()) or enemies_buff[m_name]
	local is_correct_duration = filterTable.duration and filterTable.duration > 0
	local amplify_source = buffs_from_parent[m_name] and parent or caster

	if amplify_source and amplify_source.buff_amplify and is_amplified_perk and is_correct_source and is_correct_duration then
		local new_duration = filterTable.duration * amplify_source.buff_amplify

		if counter_updaters[m_name] then
			Timers:CreateTimer(0, function()
				local parent_modifier = parent:FindModifierByName(counter_updaters[m_name])
				if parent_modifier then
					parent_modifier:SetDuration(new_duration, true)
				end
			end)
		end
		if self_updaters[m_name] then
			Timers:CreateTimer(0, function()
				local modifier = parent:FindModifierByName(m_name)
				if not modifier then return nil end
				local time = modifier:GetRemainingTime() + modifier:GetElapsedTime()
				if (time + 0.05) < new_duration then
					modifier:SetDuration(new_duration, true)
				end
				return 0.1
			end)
		end

		filterTable.duration = new_duration
	end

	--[[ Elder Titan's Spell Immunity from Astral Spirit ]]--
	if m_name == "modifier_elder_titan_echo_stomp_magic_immune" then
		local duration_ratio = ability:GetSpecialValueFor("scepter_magic_immune_per_hero_new_value") / ability:GetSpecialValueFor("scepter_magic_immune_per_hero")
		filterTable.duration = filterTable.duration * duration_ratio
	end

	return true
end

function CMegaDotaGameMode:OnThink()
	if GameRules:State_Get() == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then

		-- update the scale factor:
	 	-- * SCALE_FACTOR_INITIAL at the start of the game
		-- * SCALE_FACTOR_FINAL after SCALE_FACTOR_FADEIN_SECONDS have elapsed
		local curTime = GameRules:GetDOTATime( false, false )
		local goldFracTime = math.min( math.max( curTime / GOLD_SCALE_FACTOR_FADEIN_SECONDS, 0 ), 1 )
		local xpFracTime = math.min( math.max( curTime / XP_SCALE_FACTOR_FADEIN_SECONDS, 0 ), 1 )
		self.m_CurrentGoldScaleFactor = GOLD_SCALE_FACTOR_INITIAL + (goldFracTime * ( GOLD_SCALE_FACTOR_FINAL - GOLD_SCALE_FACTOR_INITIAL ) )
		self.m_CurrentXpScaleFactor = XP_SCALE_FACTOR_INITIAL + (xpFracTime * ( XP_SCALE_FACTOR_FINAL - XP_SCALE_FACTOR_INITIAL ) )
--		print( "Gold scale = " .. self.m_CurrentGoldScaleFactor )
--		print( "XP scale = " .. self.m_CurrentXpScaleFactor )

		for i = 0, 23 do
			if PlayerResource:IsValidPlayer( i ) then
				local hero = PlayerResource:GetSelectedHeroEntity( i )
				if hero and hero:IsAlive() then
					local pos = hero:GetAbsOrigin()

					if IsInBugZone(pos) then
						-- hero:ForceKill(false)
						-- Kill this unit immediately.

						local naprv = Vector(pos[1]/math.sqrt(pos[1]*pos[1]+pos[2]*pos[2]+pos[3]*pos[3]),pos[2]/math.sqrt(pos[1]*pos[1]+pos[2]*pos[2]+pos[3]*pos[3]),0)
						pos[3] = 0
						FindClearSpaceForUnit(hero, pos-naprv*1100, false)
					end
				end
			end
		end

		for player_id, last_order_time in pairs(self.last_player_orders) do
			if GameRules:GetGameTime() - last_order_time > 120 and PlayerResource:GetConnectionState(player_id) == DOTA_CONNECTION_STATE_CONNECTED then
				self.last_player_orders[player_id] = 9999999
				local hero = PlayerResource:GetSelectedHeroEntity(player_id)
				if hero then
					local team = hero:GetTeam()

					local fountain
					local multiplier

					if team == DOTA_TEAM_GOODGUYS then
						multiplier = -350
						fountain = Entities:FindByName( nil, "ent_dota_fountain_good" )
					elseif team == DOTA_TEAM_BADGUYS then
						multiplier = -650
						fountain = Entities:FindByName( nil, "ent_dota_fountain_bad" )
					end

					local fountain_pos = fountain:GetAbsOrigin()
					local move_pos = fountain_pos:Normalized() * multiplier + RandomVector( RandomFloat( 0, 200 ) ) + fountain_pos

					ExecuteOrderFromTable({
						UnitIndex = hero:entindex(),
						OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
						Position = move_pos
					})
				end
			end
		end
	end
	return 5
end


function CMegaDotaGameMode:FilterBountyRunePickup( filterTable )
--	print( "FilterBountyRunePickup" )
--  for k, v in pairs( filterTable ) do
--  	print("MG: " .. k .. " " .. tostring(v) )
--  end
	filterTable["gold_bounty"] = self.m_CurrentGoldScaleFactor * filterTable["gold_bounty"]
	filterTable["xp_bounty"] = self.m_CurrentXpScaleFactor * filterTable["xp_bounty"]
	return true
end

function CMegaDotaGameMode:FilterModifyGold( filterTable )
--	print( "FilterModifyGold" )
--	print( self.m_CurrentGoldScaleFactor )
	filterTable["gold"] = self.m_CurrentGoldScaleFactor * filterTable["gold"]
	if PlayerResource:GetTeam(filterTable.player_id_const) == ShuffleTeam.weakTeam then
		filterTable["gold"] = ShuffleTeam.multGold * filterTable["gold"]
	end
	return true
end

function CMegaDotaGameMode:FilterModifyExperience( filterTable )
	local hero = EntIndexToHScript(filterTable.hero_entindex_const)

	if hero and hero.IsTempestDouble and hero:IsTempestDouble() then
		return false
	end

	local new_exp = self.m_CurrentXpScaleFactor * filterTable["experience"]

	if hero and hero.GetPlayerOwnerID and hero:GetPlayerOwnerID() then
		local player_id = hero:GetPlayerOwnerID()
		CUSTOM_GAME_STATS[player_id].experiance = CUSTOM_GAME_STATS[player_id].experiance + new_exp
	end

	filterTable["experience"] = new_exp
	return true
end

function CMegaDotaGameMode:OnMatchDone(keys)
	local couriers = FindUnitsInRadius(DOTA_TEAM_GOODGUYS, Vector( 0, 0, 0 ), nil, FIND_UNITS_EVERYWHERE, DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_COURIER, DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER, false )
		
	for i = 0, 23 do
		if PlayerResource:IsValidPlayerID( i ) then
			local networth = 0
			local hero = PlayerResource:GetSelectedHeroEntity( i )

			for _, cour in pairs( couriers ) do
				for s = 0, 8 do
					local item = cour:GetItemInSlot( s )

					if item and item:GetOwner() == hero then
						networth = networth + item:GetCost()
					end
				end
			end

			for s = 0, 8 do
				local item = hero:GetItemInSlot( s )

				if item then
					networth = networth + item:GetCost()
				end
			end

			networth = networth + PlayerResource:GetGold( i )

			local stats = CUSTOM_GAME_STATS[i]
			stats.perk = GamePerks.choosed_perks[i]
			stats.networth = networth
			stats.damage_taken = PlayerResource:GetHeroDamageTaken(i, true) + PlayerResource:GetCreepDamageTaken(i, true)
			stats.total_healing = PlayerResource:GetHealing(i)
			stats.xpm = stats.experiance / GameRules:GetGameTime() * 60

			CustomNetTables:SetTableValue( "custom_stats", tostring( i ), stats )
		end
	end

	if keys.winningteam then
		WebApi:AfterMatch(keys.winningteam)
	end
end

function CMegaDotaGameMode:OnGameRulesStateChange(keys)
	local newState = GameRules:State_Get()

	if newState ==  DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP then
		AutoTeam:Init()
		GameRules:SendCustomMessage("#workaround_chat_message", -1, 0)
	end

	if newState ==  DOTA_GAMERULES_STATE_HERO_SELECTION then
		GameOptions:RecordVotingResults()
		ShuffleTeam:SortInMMR()
		AutoTeam:EnableFreePatreonForBalance()
		Timers:CreateTimer(1, function()
			GameRules:SendCustomMessage("#workaround_chat_message", -1, 0)
		end)
	end

	if newState == DOTA_GAMERULES_STATE_STRATEGY_TIME then
		self:SetTeamColors()
		for i=0, DOTA_MAX_TEAM_PLAYERS do
			if PlayerResource:IsValidPlayer(i) then
				if PlayerResource:HasSelectedHero(i) == false then
					local player = PlayerResource:GetPlayer(i)
					player:MakeRandomHeroSelection()
				end
			end
		end
	end

	if newState == DOTA_GAMERULES_STATE_PRE_GAME then
		InitWardsChecker()
		if not GameOptions:OptionsIsActive("super_towers") then
			AddModifierAllByClassname("npc_dota_tower", "modifier_super_tower")
		end
		AddModifierAllByClassname("npc_dota_fort", "modifier_stronger_builds")
		AddModifierAllByClassname("npc_dota_barracks", "modifier_stronger_builds")

		local parties = {}
		local party_indicies = {}
		local party_members_count = {}
		local party_index = 1
		-- Set up player colors
		for id = 0, 23 do
			if PlayerResource:IsValidPlayer(id) then
				local party_id = tonumber(tostring(PlayerResource:GetPartyID(id)))
				if party_id and party_id > 0 then
					if not party_indicies[party_id] then
						party_indicies[party_id] = party_index
						party_index = party_index + 1
					end
					local party_index = party_indicies[party_id]
					parties[id] = party_index
					if not party_members_count[party_index] then
						party_members_count[party_index] = 0
					end
					party_members_count[party_index] = party_members_count[party_index] + 1
				end
			end
		end
		for id, party in pairs(parties) do
			 -- at least 2 ppl in party!
			if party_members_count[party] and party_members_count[party] < 2 then
				parties[id] = nil
			end
		end
		if parties then
			CustomNetTables:SetTableValue("game_state", "parties", parties)
		end
		Timers:CreateTimer(3, function()
			if not IsDedicatedServer() then
				CustomGameEventManager:Send_ServerToAllClients("is_local_server", {})
			end
			ShuffleTeam:SendNotificationForWeakTeam()
		end)
        local toAdd = {
            luna_moon_glaive_fountain = 4,
            ursa_fury_swipes_fountain = 1,
        }
		Timers:RemoveTimer("game_options_unpause")
		Convars:SetFloat("host_timescale", 1)
		Convars:SetFloat("host_timescale", IsInToolsMode() and 1 or 0.07)
		Timers:CreateTimer({
			useGameTime = false,
			endTime = 2.1,
			callback = function()
				Convars:SetFloat("host_timescale", 1)
				if not IsInToolsMode() then SendToServerConsole("dota_pause") end
				return nil
			end
		})

        local fountains = Entities:FindAllByClassname('ent_dota_fountain')
		-- Loop over all ents
        for k,fountain in pairs(fountains) do

			fountain:AddNewModifier(fountain, nil, "modifier_fountain_phasing", { duration = 90 })

            for skillName,skillLevel in pairs(toAdd) do
                fountain:AddAbility(skillName)
                local ab = fountain:FindAbilityByName(skillName)
                if ab then
                    ab:SetLevel(skillLevel)
                end
            end

            local item = CreateItem('item_monkey_king_bar_fountain', fountain, fountain)
            if item then
                fountain:AddItem(item)
            end

		end
		GamePerks:StartTrackPerks()
	end

	if newState == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
		
		ShuffleTeam:GiveBonusToWeakTeam()

		Convars:SetFloat("host_timescale", 1)
		if game_start then
			GameRules:SetTimeOfDay( 0.251 )
			game_start = false
			Timers:CreateTimer(0.1, function()
				GPM_Init()
				return nil
			end)
			Timers:CreateTimer(0, function()
				for player_id = 0, 24 do
					if not abandoned_players[player_id] and PlayerResource:GetConnectionState(player_id) == DOTA_CONNECTION_STATE_ABANDONED then
						abandoned_players[player_id] = true
						local team = PlayerResource:GetTeam(player_id)

						local fountain
						if team and (team == DOTA_TEAM_GOODGUYS) or (team == DOTA_TEAM_BADGUYS)then
							fountain = Entities:FindByName( nil, "ent_dota_fountain_" .. (team == DOTA_TEAM_GOODGUYS and "good" or "bad"))
						end

						local block_unit = function(unit)
							unit:Stop()
							unit:AddNewModifier(unit, nil, "modifier_abandoned", { duration = -1 })
							unit:AddNoDraw()
							if fountain then
								unit:SetAbsOrigin(fountain:GetAbsOrigin())
							end

							if unit.HasInventory and unit:HasInventory() then
								for item_slot = 0, 20 do
									local item = unit:GetItemInSlot(item_slot)
									if item and not item:IsNull() and item.GetAbilityName and item:GetAbilityName() then
										if item:IsNeutralDrop() then
											print("Add neutral to stash (10s fail-safe)")
											AddNeutralItemToStashWithEffects(unit:GetPlayerID(), unit:GetTeam(), item)
										elseif item:GetCost() then
											unit:SellItem(item)
										end
									end
								end
							end
						end

						Timers:CreateTimer(first_dc_players[player_id] and 60 or 0, function()
							if abandoned_players[player_id] then
								CallbackHeroAndCourier(player_id, block_unit)
								
								local gold_for_team = PlayerResource:GetGold(player_id)
								local connected_players_counter = 0
								for _player_id = 0, 24 do
									if _player_id ~= player_id and PlayerResource:GetConnectionState(_player_id) == DOTA_CONNECTION_STATE_CONNECTED then
										connected_players_counter = connected_players_counter + 1
									end
								end
								if connected_players_counter > 0 then
									gold_for_team = math.floor(gold_for_team / connected_players_counter)
									for _player_id = 0, 24 do
										if _player_id ~= player_id and PlayerResource:GetConnectionState(_player_id) == DOTA_CONNECTION_STATE_CONNECTED then
											local _hero = PlayerResource:GetSelectedHeroEntity(_player_id)
											if _hero and not _hero:IsNull() then
												_hero:ModifyGold(gold_for_team, false, 0)
											end
										end
									end
								end
							end
						end)
						if not first_dc_players[player_id] then
							first_dc_players[player_id] = true
						end
					end
				end
				return 10
			end)
		end
	end
end

function SearchAndCheckRapiers(buyer, unit, plyID, maxSlots, timerKey)
	local fullRapierCost = GetItemCost("item_rapier")
	for i = 0, maxSlots do
		local item = unit:GetItemInSlot(i)
		if item and item:GetAbilityName() == "item_rapier" and (item:GetPurchaser() == buyer) and ((item.defend == nil) or (item.defend == false)) then
			local playerNetWorse = PlayerResource:GetNetWorth(plyID)
			if playerNetWorse < NET_WORSE_FOR_RAPIER_MIN then
				CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(plyID), "display_custom_error", { message = "#rapier_small_networth" })
				UTIL_Remove(item)
				buyer:ModifyGold(fullRapierCost, false, 0)
				Timers:CreateTimer(0.03, function()
					Timers:RemoveTimer(timerKey)
				end)
			else
				if GetHeroKD(buyer) > 0 then
					Timers:CreateTimer(0.03, function()
						item.defend = true
						Timers:RemoveTimer(timerKey)
					end)
				elseif (GetHeroKD(buyer) <= 0) then
					CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(plyID), "display_custom_error", { message = "#rapier_littleKD" })
					UTIL_Remove(item)
					buyer:ModifyGold(fullRapierCost, false, 0)
					Timers:CreateTimer(0.03, function()
						Timers:RemoveTimer(timerKey)
					end)
				end
			end
		end
	end
end

function CMegaDotaGameMode:ItemAddedToInventoryFilter( filterTable )
	if filterTable["item_entindex_const"] == nil then
		return true
	end
 	if filterTable["inventory_parent_entindex_const"] == nil then
		return true
	end
	local hInventoryParent = EntIndexToHScript( filterTable["inventory_parent_entindex_const"] )
	local hItem = EntIndexToHScript( filterTable["item_entindex_const"] )
	if hItem ~= nil and hInventoryParent ~= nil then
		local itemName = hItem:GetName()

		if itemName == "item_banhammer" and GameOptions:OptionsIsActive("no_trolls_kick") then
			local playerId = hItem:GetPurchaser():GetPlayerID()
			if playerId then
				CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(playerId), "display_custom_error", { message = "#you_cannot_buy_it" })
			end
			UTIL_Remove(hItem)
			return false
		end
		local pitems = {
			"item_patreonbundle_1",
			"item_patreonbundle_2",
		}
		if hInventoryParent:IsRealHero() then
			local plyID = hInventoryParent:GetPlayerID()
			if not plyID then return true end

			local pitem = false
			for i=1,#pitems do
				if itemName == pitems[i] then
					pitem = true
					break
				end
			end
			if pitem == true then
				local supporter_level = Supporters:GetLevel(plyID)
				if supporter_level < 1 then
					CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(plyID), "display_custom_error", { message = "#nopatreonerror" })
					UTIL_Remove(hItem)
					return false
				end
			end

			if itemName == "item_banhammer" then
				if GameRules:GetDOTATime(false,false) < 300 then
					CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(plyID), "display_custom_error", { message = "#notyettime" })
					UTIL_Remove(hItem)
					return false
				end
			end
		else
			for i=1,#pitems do
				if itemName == pitems[i] then
					local prsh = hItem:GetPurchaser()
					if prsh ~= nil then
						if prsh:IsRealHero() then
							local prshID = prsh:GetPlayerID()

							if not prshID then
								UTIL_Remove(hItem)
								return false
							end
							local supporter_level = Supporters:GetLevel(prshID)
							if not supporter_level then
								UTIL_Remove(hItem)
								return false
							end
							if itemName == "item_banhammer" then
								if GameRules:GetDOTATime(false,false) < 300 then
									CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(prshID), "display_custom_error", { message = "#notyettime" })
									UTIL_Remove(hItem)
									return false
								end
							else
								if supporter_level < 1 then
									CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(prshID), "display_custom_error", { message = "#nopatreonerror" })
									UTIL_Remove(hItem)
									return false
								end
							end
						else
							UTIL_Remove(hItem)
							return false
						end
					else
						UTIL_Remove(hItem)
						return false
					end
				end
			end
		end

		if hItem:GetPurchaser() and (itemName == "item_relic") then
			local buyer = hItem:GetPurchaser()
			local plyID = buyer:GetPlayerID()
			local itemEntIndex = hItem:GetEntityIndex()
			local timerKey = "seacrh_rapier_on_player"..itemEntIndex
			Timers:CreateTimer(timerKey, {
				useGameTime = false,
				endTime = 0.4,
				callback = function()
					if hItem.transfer then
						SearchAndCheckRapiers(buyer, buyer, plyID, 20, timerKey)
						return 0.45
					end
				end
			})
		end


		local purchaser = hItem:GetPurchaser()
		local itemCost = hItem:GetCost()
		if purchaser then
			local prshID = purchaser:GetPlayerID()
			local supporter_level = Supporters:GetLevel(prshID)
			local correctInventory = hInventoryParent:IsRealHero() or (hInventoryParent:GetClassname() == "npc_dota_lone_druid_bear") or hInventoryParent:IsCourier()
			local in_shop_range = hInventoryParent:IsInRangeOfShop(DOTA_SHOP_HOME, true) or not hInventoryParent:IsAlive()

			if (filterTable["item_parent_entindex_const"] > 0) and correctInventory and (ItemIsFastBuying(hItem:GetName()) or supporter_level > 0) and not in_shop_range then
				local transfer_result = hItem:TransferToBuyer(hInventoryParent)
				if transfer_result ~= nil then
					hItem:SetCombineLocked(true)
					Timers:CreateTimer(0, function()
						if hItem and not hItem:IsNull() then
							hInventoryParent:TakeItem(hItem)
							hItem:SetCombineLocked(false)
						end
						if transfer_result == true then
							purchaser:AddItem(hItem)
						end
					end)
				end
				local unique_key_cd = itemName .. "_" .. purchaser:GetEntityIndex()
				if _G.lastTimeBuyItemWithCooldown[unique_key_cd] and (_G.itemsCooldownForPlayer[itemName] and (GameRules:GetGameTime() - _G.lastTimeBuyItemWithCooldown[unique_key_cd]) < _G.itemsCooldownForPlayer[itemName]) then
					local checkMaxCount = CheckMaxItemCount(hItem:GetAbilityName(), unique_key_cd, prshID, false)
					if checkMaxCount then
						MessageToPlayerItemCooldown(itemName, prshID)
					end
					Timers:CreateTimer(0.08, function()
						UTIL_Remove(hItem)
					end)
					return false
				end
			else
				hItem.transfer = true
			end

			if (filterTable["item_parent_entindex_const"] > 0) and hItem and correctInventory and (not purchaser:CheckPersonalCooldown(hItem)) then
				UTIL_Remove(hItem)
				return false
			end
		end
	end

	if _G.neutralItems[hItem:GetAbilityName()] and hItem.old == nil then
		hItem.old = true
		local inventoryIsCorrect = hInventoryParent:IsRealHero() or (hInventoryParent:GetClassname() == "npc_dota_lone_druid_bear") or hInventoryParent:IsCourier()
		if inventoryIsCorrect then
			local playerId = hInventoryParent:GetPlayerOwnerID() or hInventoryParent:GetPlayerID()
			local player = PlayerResource:GetPlayer(playerId)

			hItem.secret_key = RandomInt(1,999999)
			CustomGameEventManager:Send_ServerToPlayer( player, "neutral_item_picked_up", {
				item = filterTable.item_entindex_const,
				secret = hItem.secret_key,
			})

			local container = hItem:GetContainer()
			if container then
				container:RemoveSelf()
			end

			return false
		end
	end

	if hItem and hItem.neutralDropInBase then
		hItem.secret_key = nil
		hItem.neutralDropInBase = false
		local inventoryIsCorrect = hInventoryParent:IsRealHero() or (hInventoryParent:GetClassname() == "npc_dota_lone_druid_bear") or hInventoryParent:IsCourier()
		local playerId = inventoryIsCorrect and hInventoryParent:GetPlayerOwnerID()
		if playerId then
			NotificationToAllPlayerOnTeam({
				PlayerID = playerId,
				item = filterTable.item_entindex_const,
			})
		end
	end

	return true
end

function CMegaDotaGameMode:OnConnectFull(data)
	local player_id = data.PlayerID
	_G.tUserIds[player_id] = data.userid
	if Kicks:IsPlayerKicked(player_id) then
		Kicks:DropItemsForDisconnetedPlayer(player_id)
		SendToServerConsole('kickid '.. data.userid);
	end
	
	local hero = PlayerResource:GetSelectedHeroEntity(player_id)

	if abandoned_players[player_id] then
		local unblock_unit = function(unit)
			unit:RemoveModifierByName("modifier_abandoned")
			unit:RemoveNoDraw()
		end
		CallbackHeroAndCourier(player_id, unblock_unit)
		abandoned_players[player_id] = nil
	end

	if hero then
		hero:CheckManuallySpentAttributePoints()
	end

	CustomGameEventManager:Send_ServerToAllClients( "change_leave_status", {leave = false, playerId = player_id} )
end

function CMegaDotaGameMode:OnPlayerDisconnect(data)
	local player_id = data.PlayerID
	if not player_id then return end

	if not self.disconnected_players[player_id] then
		self.disconnected_players[player_id] = true
	end

	CustomGameEventManager:Send_ServerToAllClients( "change_leave_status", {leave = true, playerId = data.PlayerID} )
end

function GetBlockItemByID(id)
	for k,v in pairs(_G.ItemKVs) do
		if tonumber(v["ID"]) == id then
			v["name"] = k
			return v
		end
	end
end

function CMegaDotaGameMode:ExecuteOrderFilter(filterTable)
	local orderType = filterTable.order_type
	local playerId = filterTable.issuer_player_id_const
	local target = filterTable.entindex_target ~= 0 and EntIndexToHScript(filterTable.entindex_target) or nil
	local ability = filterTable.entindex_ability ~= 0 and EntIndexToHScript(filterTable.entindex_ability) or nil
	local orderVector = Vector(filterTable.position_x, filterTable.position_y, 0)
	-- `entindex_ability` is item id in some orders without entity
	if ability and not ability.GetAbilityName then ability = nil end
	local abilityName = ability and ability:GetAbilityName() or nil
	local unit
	-- TODO: Are there orders without a unit?
	if filterTable.units and filterTable.units["0"] then
		unit = EntIndexToHScript(filterTable.units["0"])
	end

	if playerId then
		self.last_player_orders[playerId] = GameRules:GetGameTime()
	end

	if not IsInToolsMode() and unit and unit.GetTeam and PlayerResource:GetPlayer(playerId) then
		if unit:GetTeam() ~= PlayerResource:GetPlayer(playerId):GetTeam() then
			return false
		end
		local is_not_owned_unit = false
		for _, _unit_ent in pairs (filterTable.units) do
			local _unit = EntIndexToHScript(_unit_ent)
			if _unit and IsValidEntity(_unit) and _unit.GetPlayerOwnerID then
				local unit_owner_id = _unit:GetPlayerOwnerID()
				if
					unit_owner_id and
					unit_owner_id ~= playerId and
					(
						(PlayerResource:GetConnectionState(unit_owner_id) == DOTA_CONNECTION_STATE_DISCONNECTED and GameRules:GetDOTATime(false,false) < 900)
						or
						PlayerResource:GetConnectionState(unit_owner_id) == DOTA_CONNECTION_STATE_ABANDONED
					)
				then
					is_not_owned_unit = true
				end
			end
		end
		if is_not_owned_unit then
			return false
		end
	end

	if orderType == DOTA_UNIT_ORDER_TAKE_ITEM_FROM_NEUTRAL_ITEM_STASH  then
		local main_hero = PlayerResource:GetSelectedHeroEntity(playerId)
		Timers:CreateTimer(0, function()
			if main_hero:GetItemInSlot(DOTA_ITEM_NEUTRAL_SLOT) == nil then
				main_hero:SwapItems(ability:GetItemSlot(), DOTA_ITEM_NEUTRAL_SLOT)
			end
		end)
	end

	if orderType == DOTA_UNIT_ORDER_CAST_TARGET then
		if target and target:GetName() == "npc_dota_seasonal_ti9_drums" then
			CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(playerId), "display_custom_error", { message = "#dota_hud_error_cant_cast_on_other" })
			return
		end
	end

	local itemsToBeDestroy = {
		["item_disable_help_custom"] = true,
		["item_mute_custom"] = true,
		["item_reset_mmr"] = true,
	}
	if orderType == DOTA_UNIT_ORDER_PURCHASE_ITEM then
		local item_name = filterTable.shop_item_name or ""
		if WARDS_LIST[item_name] then
			if BlockedWardsFilter(playerId, "#you_cannot_buy_it") == false then return false end
		end

		if item_name == "item_gem" then
			local kills = PlayerResource:GetKills(playerId)
			local assists = PlayerResource:GetAssists(playerId)
			local deaths = PlayerResource:GetDeaths(playerId)

			if kills + assists > deaths then
				return true
			else
				CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(playerId), "display_custom_error", { message = "#you_cannot_buy_it" })
				return false
			end
		end

		local hero = PlayerResource:GetSelectedHeroEntity(playerId)
		if TROLL_FEED_FORBIDDEN_TO_BUY_ITEMS[item_name] and hero and hero:HasModifier("modifier_troll_debuff_stop_feed") then
			CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(playerId), "display_custom_error", { message = "#you_cannot_buy_it" })
			return false
		end
	end

	if orderType == DOTA_UNIT_ORDER_DROP_ITEM or orderType == DOTA_UNIT_ORDER_EJECT_ITEM_FROM_STASH then
		if ability and ability:GetAbilityName() == "item_relic" then
			CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(playerId), "display_custom_error", { message = "#cannotpullit" })
			return false
		end
	end

	if  orderType == DOTA_UNIT_ORDER_SELL_ITEM  then
		if ability and ability:GetAbilityName() == "item_relic" then
			Timers:RemoveTimer("seacrh_rapier_on_player"..filterTable.entindex_ability)
		end
	end

	if orderType == DOTA_UNIT_ORDER_GIVE_ITEM then
		if target:GetClassname() == "ent_dota_shop" and ability:GetAbilityName() == "item_relic" then
			Timers:RemoveTimer("seacrh_rapier_on_player"..ability:GetEntityIndex())
		end

		if _G.neutralItems[ability:GetAbilityName()] then
			local targetID = target:GetPlayerOwnerID()
			if targetID and targetID~=playerId then
				if CheckCountOfNeutralItemsForPlayer(targetID) >= _G.MAX_NEUTRAL_ITEMS_FOR_PLAYER then
					DisplayError(playerId, "#unit_still_have_a_lot_of_neutral_items")
					return
				end
			end
		end
	end

	if orderType == DOTA_UNIT_ORDER_PICKUP_ITEM then
		if not target or not target.GetContainedItem then return true end
		local pickedItem = target:GetContainedItem()
		if not pickedItem then return true end
		local itemName = pickedItem:GetAbilityName()

		if WARDS_LIST[itemName] then
			if BlockedWardsFilter(playerId, "#cannotpickupit") == false then return false end
		end
		if _G.neutralItems[itemName] then
			if CheckCountOfNeutralItemsForPlayer(playerId) >= _G.MAX_NEUTRAL_ITEMS_FOR_PLAYER then
				DisplayError(playerId, "#player_still_have_a_lot_of_neutral_items")
				return
			end
		end
	end

	if orderType == DOTA_UNIT_ORDER_TAKE_ITEM_FROM_NEUTRAL_ITEM_STASH then
		if _G.neutralItems[ability:GetAbilityName()] then
			if CheckCountOfNeutralItemsForPlayer(playerId) >= _G.MAX_NEUTRAL_ITEMS_FOR_PLAYER then
				DisplayError(playerId, "#player_still_have_a_lot_of_neutral_items")
				return
			end
		end
	end

	if orderType == DOTA_UNIT_ORDER_DROP_ITEM or orderType == DOTA_UNIT_ORDER_EJECT_ITEM_FROM_STASH then
		if ability and itemsToBeDestroy[ability:GetAbilityName()] then
			ability:Destroy()
		end
	end

	if orderType == DOTA_UNIT_ORDER_EJECT_ITEM_FROM_STASH then
		if ability and itemsToBeDestroy[ability:GetAbilityName()] then
			ability:Destroy()
		end
	end

	local disableHelpResult = DisableHelp.ExecuteOrderFilter(orderType, ability, target, unit, orderVector)
	if disableHelpResult == false then
		return false
	end

	if orderType == DOTA_UNIT_ORDER_CAST_POSITION then

		if abilityName == "wisp_relocate" then
			local fountains = Entities:FindAllByClassname('ent_dota_fountain')

			local enemy_fountain_pos
			for _, focus_f in pairs(fountains) do
				if focus_f:GetTeamNumber() ~= PlayerResource:GetTeam(playerId) then
					enemy_fountain_pos = focus_f:GetAbsOrigin()
				end
			end
			if enemy_fountain_pos and ((enemy_fountain_pos - orderVector):Length2D() <= 1900) then
				CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(playerId), "display_custom_error", { message = "#cannot_relocate_enemy_fountain" })
				return false
			end
		end
	end


	if unit and unit:IsCourier() then
		if (orderType == DOTA_UNIT_ORDER_DROP_ITEM or orderType == DOTA_UNIT_ORDER_GIVE_ITEM) and ability and ability:IsItem() then
			local purchaser = ability:GetPurchaser()
			if purchaser and purchaser:GetPlayerID() ~= playerId then
				if purchaser:GetTeam() == PlayerResource:GetPlayer(playerId):GetTeam() then
					return false
				end
			end
		end
		local secret_modifier = unit:FindModifierByName("creep_secret_shop")
		if Supporters:GetLevel(unit:GetPlayerOwnerID()) > 0 then
			if ability and ability:GetAbilityName() == "courier_go_to_secretshop" then
				if secret_modifier and secret_modifier.ForceToSecretShop then
					if unit:IsInRangeOfShop(DOTA_SHOP_HOME, true) then
						secret_modifier:ForceToSecretShop()
						return false
					end
				else
					unit:AddNewModifier(unit, nil, "creep_secret_shop", { duration = -1 })
				end
			elseif secret_modifier and orderType ~= DOTA_UNIT_ORDER_PURCHASE_ITEM then
				if secret_modifier.OrderFilter then
					secret_modifier:OrderFilter(filterTable)
				end
			end
		end
	end

	--for _, _unit_ent in pairs (filterTable.units) do
	--	local _unit = EntIndexToHScript(_unit_ent)
	--	local unit_owner_id = _unit:GetOwner():GetPlayerID()
	--	if _unit:IsCourier() and unit_owner_id and unit_owner_id ~= playerId then
	--		return false
	--	end
	--end

	return true
end

local blockedChatPhraseCode = {
	[820] = true,
}

function CMegaDotaGameMode:OnPlayerChat(keys)
	local text = keys.text
	local playerid = keys.playerid
	if string.sub(text, 0,4) == "-ch " then
		local data = {}
		data.num = tonumber(string.sub(text, 5))
		if not blockedChatPhraseCode[data.num] then
			data.PlayerID = playerid
			SelectVO(data)
		end
	end

	local player = PlayerResource:GetPlayer(keys.playerid)

	local args = {}

	for i in string.gmatch(text, "%S+") do
		table.insert(args, i)
	end

	local command = args[1]
	if not command then return end
	table.remove(args, 1)

	local fixed_command = command.sub(command, 2)

	if Commands[fixed_command] then
		Commands[fixed_command](Commands, player, args)
	end
end

msgtimer = {}
RegisterCustomEventListener("OnTimerClick", function(keys)
	if msgtimer[keys.PlayerID] and GameRules:GetGameTime() - msgtimer[keys.PlayerID] < 3 then
		return
	end
	msgtimer[keys.PlayerID] = GameRules:GetGameTime()

	local time = math.abs(math.floor(GameRules:GetDOTATime(false, true)))
	local min = math.floor(time / 60)
	local sec = time - min * 60
	if min < 10 then min = "0" .. min end
	if sec < 10 then sec = "0" .. sec end
	CustomChat:MessageToTeam(min .. ":" .. sec, PlayerResource:GetTeam(keys.PlayerID), keys.PlayerID)
end)

votimer = {}
vousedcol = {}
SelectVO = function(keys)
	local supporter_level = Supporters:GetLevel(keys.PlayerID)
	if not keys.num then return end

	local heroes = {
		"abaddon",
		"alchemist",
		"ancient_apparition",
		"antimage",
		"arc_warden",
		"axe",
		"bane",
		"batrider",
		"beastmaster",
		"bloodseeker",
		"bounty_hunter",
		"brewmaster",
		"bristleback",
		"broodmother",
		"centaur",
		"chaos_knight",
		"chen",
		"clinkz",
		"rattletrap",
		"crystal_maiden",
		"dark_seer",
		"dark_willow",
		"dazzle",
		"dawnbreaker",
		"death_prophet",
		"disruptor",
		"doom_bringer",
		"dragon_knight",
		"drow_ranger",
		"earth_spirit",
		"earthshaker",
		"elder_titan",
		"ember_spirit",
		"enchantress",
		"enigma",
		"faceless_void",
		"grimstroke",
		"gyrocopter",
		"hoodwink",
		"huskar",
		"invoker",
		"wisp",
		"jakiro",
		"juggernaut",
		"keeper_of_the_light",
		"kunkka",
		"legion_commander",
		"leshrac",
		"lich",
		"life_stealer",
		"lina",
		"lion",
		"lone_druid",
		"luna",
		"lycan",
		"magnataur",
		"marci",
		"mars",
		"medusa",
		"meepo",
		"mirana",
		"monkey_king",
		"morphling",
		"naga_siren",
		"furion",
		"necrolyte",
		"night_stalker",
		"nyx_assassin",
		"ogre_magi",
		"omniknight",
		"oracle",
		"obsidian_destroyer",
		"pangolier",
		"phantom_assassin",
		"phantom_lancer",
		"phoenix",
		"puck",
		"pudge",
		"pugna",
		"queenofpain",
		"razor",
		"riki",
		"rubick",
		"sand_king",
		"shadow_demon",
		"nevermore",
		"shadow_shaman",
		"silencer",
		"skywrath_mage",
		"slardar",
		"slark",
		"snapfire",
		"sniper",
		"spectre",
		"spirit_breaker",
		"storm_spirit",
		"sven",
		"techies",
		"templar_assassin",
		"terrorblade",
		"tidehunter",
		"shredder",
		"tinker",
		"tiny",
		"treant",
		"troll_warlord",
		"tusk",
		"abyssal_underlord",
		"undying",
		"ursa",
		"vengefulspirit",
		"venomancer" ,
		"viper",
		"visage",
		"void_spirit",
		"warlock",
		"weaver",
		"windrunner",
		"winter_wyvern",
		"witch_doctor",
		"skeleton_king",
		"zuus"
	}
	local selectedid = 1
	local selectedid2 = nil
	local selectedstr = nil
	local startheronums = 110
	if keys.num >= startheronums then
		local locnum = keys.num - startheronums
		local mesarrs = {
			"_laugh",
			"_thank",
			"_deny",
			"_1",
			"_2",
			"_3",
			"_4",
			"_5"
		}
		selectedstr = heroes[math.floor(locnum/8)+1]..mesarrs[math.fmod(locnum,8)+1]
		print(math.floor(locnum/8))
		print(selectedstr)
		selectedid = math.floor(locnum/8)+2
		selectedid2 = math.fmod(locnum,8)+1
	else
		if keys.num < (startheronums-8) then
			local mesarrs = {
				--dp1
				"Applause",
				"Crash_and_Burn",
				"Crickets",
				"Party_Horn",
				"Rimshot",
				"Charge",
				"Drum_Roll",
				"Frog",
				--dp2
				"Headshake",
				"Kiss",
				"Ow",
				"Snore",
				"Bockbock",
				"Crybaby",
				"Sad_Trombone",
				"Yahoo",
				--misc
				"",
				"Sleighbells",
				"Sparkling_Celebration",
				"Greevil_Laughter",
				"Frostivus_Magic",
				"Ceremonial_Drums",
				"Oink_Oink",
				"Celebratory_Gong",
				--en an
				"patience",
				"wow",
				"all_dead",
				"brutal",
				"disastah",
				"oh_my_lord",
				"youre_a_hero",
				--en an2
				"that_was_questionable",
				"playing_to_win",
				"what_just_happened",
				"looking_spicy",
				"no_chill",
				"ding_ding_ding",
				"absolutely_perfect",
				"lets_play",
				--ch an
				"duiyou_ne",
				"wan_bu_liao_la",
				"po_liang_lu",
				"tian_huo",
				"jia_you",
				"zou_hao_bu_song",
				"liu_liu_liu",
				--ch an2
				"hu_lu_wa",
				"ni_qi_bu_qi",
				"gao_fu_shuai",
				"gan_ma_ne_xiong_di",
				"bai_tuo_shei_qu",
				"piao_liang",
				"lian_dou_xiu_wai_la",
				"zai_jian_le_bao_bei",
				--ru an
				"bozhe_ti_posmotri",
				"zhil_do_konsta",
				"ay_ay_ay",
				"ehto_g_g",
				"eto_prosto_netchto",
				"krasavchik",
				"bozhe_kak_eto_bolno",
				--ru an2
				"oy_oy_bezhat",
				"eto_nenormalno",
				"eto_sochno",
				"kreasa_kreasa",
				"kak_boyge_te_byechenya",
				"eto_ge_popayx_feeda",
				"da_da_da_nyet",
				"wot_eto_bru",
				--bp19
				"kooka_laugh",
				"monkey_biz",
				"orangutan_kiss",
				"skeeter",
				"crowd_groan",
				"head_bonk",
				"record_scratch",
				"ta_da",
				--epic
				"easiest_money",
				"echo_slama_jama",
				"next_level",
				"oy_oy_oy",
				"ta_daaaa",
				"ceeb",
				"goodness_gracious",
				--epic2
				"nakupuuu",
				"whats_cooking",
				"eughahaha",
				"glados_chat_21",
				"glados_chat_01",
				"glados_chat_07",
				"glados_chat_04",
				"",
				--kor cas
				"kor_yes_no",
				"kor_scan",
				"kor_immortality",
				"kor_roshan",
				"kor_yolo",
				"kor_million_dollar_house",
				"",
				"",
			}
			selectedstr = mesarrs[keys.num]
			selectedid2 = keys.num
		else
			local hero = PlayerResource:GetSelectedHeroEntity(keys.PlayerID)
			if not hero or hero:IsNull() or not hero.GetName then return end

			local locnum = keys.num - (startheronums-8)
			local nowheroname = string.sub(hero:GetName(), 15)
			local mesarrs = {
				"_laugh",
				"_thank",
				"_deny",
				"_1",
				"_2",
				"_3",
				"_4",
				"_5"
			}
			local herolocid = 2
			for i=1, #heroes do
				if nowheroname == heroes[i] then
					break
				end
				herolocid = herolocid + 1
			end
			selectedstr = nowheroname..mesarrs[locnum+1]
			selectedid = herolocid
			print(selectedid)
			selectedid2 = locnum+1
		end
	end
	if selectedstr ~= nil and selectedid2 ~= nil then
		local heroesvo = {
			{
				--dp1
				"soundboard.applause",
				"soundboard.crash",
				"soundboard.cricket",
				"soundboard.party_horn",
				"soundboard.rimshot",
				"soundboard.charge",
				"soundboard.drum_roll",
				"soundboard.frog",
				--dp2
				"soundboard.headshake",
				"soundboard.kiss",
				"soundboard.ow",
				"soundboard.snore",
				"soundboard.bockbock",
				"soundboard.crybaby",
				"soundboard.sad_bone",
				"soundboard.yahoo",
				--misc
				"",
				"soundboard.sleighbells",
				"soundboard.new_year_celebration",
				"soundboard.greevil_laughs",
				"soundboard.frostivus_magic",
				"soundboard.new_year_drums",
				"soundboard.new_year_pig",
				"soundboard.new_year_gong",
				--en an
				"soundboard.patience",
				"soundboard.wow",
				"soundboard.all_dead",
				"soundboard.brutal",
				"soundboard.disastah",
				"soundboard.oh_my_lord",
				"soundboard.youre_a_hero",
				--en an2
				"soundboard.that_was_questionable",
				"soundboard.playing_to_win",
				"soundboard.what_just_happened",
				"soundboard.looking_spicy",
				"soundboard.no_chill",
				"custom_soundboard.ding_ding_ding",
				"soundboard.absolutely_perfect",
				"custom_soundboard.lets_play",
				--ch an
				"soundboard.duiyou_ne",
				"soundboard.wan_bu_liao_la",
				"soundboard.po_liang_lu",
				"soundboard.tian_huo",
				"soundboard.jia_you",
				"soundboard.zou_hao_bu_song",
				"soundboard.liu_liu_liu",
				--ch an2
				"soundboard.hu_lu_wa",
				"soundboard.ni_qi_bu_qi",
				"soundboard.gao_fu_shuai",
				"soundboard.gan_ma_ne_xiong_di",
				"soundboard.bai_tuo_shei_qu",
				"soundboard.piao_liang",
				"soundboard.lian_dou_xiu_wai_la",
				"soundboard.zai_jian_le_bao_bei",
				--ru an
				"soundboard.bozhe_ti_posmotri",
				"soundboard.zhil_do_konsta",
				"soundboard.ay_ay_ay",
				"soundboard.ehto_g_g",
				"soundboard.eto_prosto_netchto",
				"soundboard.krasavchik",
				"soundboard.bozhe_kak_eto_bolno",
				--ru an2
				"soundboard.oy_oy_bezhat",
				"soundboard.eto_nenormalno",
				"soundboard.eto_sochno",
				"soundboard.kreasa_kreasa",
				"soundboard.kak_boyge_te_byechenya",
				"soundboard.eto_ge_popayx_feeda",
				"soundboard.da_da_da_nyet",
				"soundboard.wot_eto_bru",
				--bp19
				"custom_soundboard.ti9_kooka_laugh",
				"custom_soundboard.ti9_monkey_biz",
				"custom_soundboard.ti9_orangutan_kiss",
				"custom_soundboard.ti9_skeeter",
				"custom_soundboard.ti9_crowd_groan",
				"custom_soundboard.ti9_head_bonk",
				"custom_soundboard.ti9_record_scratch",
				"custom_soundboard.ti9_ta_da",
				--epic
				"soundboard.easiest_money",
				"soundboard.echo_slama_jama",
				"soundboard.next_level",
				"soundboard.oy_oy_oy",
				"soundboard.ta_daaaa",
				"soundboard.ceb.start",
				"soundboard.goodness_gracious",
				--epic2
				"soundboard.nakupuuu",
				"soundboard.whats_cooking",
				"soundboard.eughahaha",
				"custom_soundboard.glados_chat_01",
				"custom_soundboard.glados_chat_21",
				"custom_soundboard.glados_chat_04",
				"custom_soundboard.glados_chat_07",
				"",
				--kor cas
				"custom_soundboard.kor_yes_no",
				"custom_soundboard.kor_scan",
				"custom_soundboard.kor_immortality",
				"custom_soundboard.kor_roshan",
				"custom_soundboard.kor_yolo",
				"custom_soundboard.kor_million_dollar_house",
				"",
				"",
			},
			{
				"abaddon_abad_laugh_03",
				"abaddon_abad_failure_01",
				"abaddon_abad_deny_06",
				"abaddon_abad_lasthit_06",
				"abaddon_abad_death_03",
				"abaddon_abad_kill_05",
				"abaddon_abad_cast_01",
				"abaddon_abad_begin_02",
			},
			{
				"alchemist_alch_laugh_07",
				"alchemist_alch_win_03",
				"alchemist_alch_kill_02",
				"alchemist_alch_ability_rage_25",
				"alchemist_alch_kill_08",
				"alchemist_alch_ability_rage_14",
				"alchemist_alch_ability_failure_02",
				"alchemist_alch_respawn_06",
			},
			{
				"ancient_apparition_appa_laugh_01",
				"ancient_apparition_appa_lasthit_04",
				"ancient_apparition_appa_spawn_03",
				"ancient_apparition_appa_kill_03",
				"ancient_apparition_appa_death_13",
				"ancient_apparition_appa_purch_02",
				"ancient_apparition_appa_battlebegins_01",
				"ancient_apparition_appa_attack_05",
			},
			{
				"antimage_anti_laugh_05",
				"antimage_anti_respawn_09",
				"antimage_anti_deny_12",
				"antimage_anti_magicuser_01",
				"antimage_anti_ability_failure_02",
				"antimage_anti_kill_08",
				"antimage_anti_kill_13",
				"antimage_anti_rare_02",
			},
			{
				"arc_warden_arcwar_laugh_06",
				"arc_warden_arcwar_thanks_02",
				"arc_warden_arcwar_deny_10",
				"arc_warden_arcwar_flux_08",
				"arc_warden_arcwar_death_02",
				"arc_warden_arcwar_tempest_double_killed_04",
				"arc_warden_arcwar_failure_03",
				"arc_warden_arcwar_rival_05",
			},
			{
				"axe_axe_laugh_03",
				"axe_axe_drop_medium_01",
				"axe_axe_deny_08",
				"axe_axe_kill_06",
				"axe_axe_deny_16",
				"axe_axe_ability_failure_01",
				"axe_axe_rival_01",
				"axe_axe_rival_22",
				},
				{
				"bane_bane_battlebegins_01",
				"bane_bane_thanks_02",
				"bane_bane_ability_enfeeble_05",
				"bane_bane_spawn_02",
				"bane_bane_purch_04",
				"bane_bane_lasthit_11",
				"bane_bane_kill_13",
				"bane_bane_level_06",
				},
				{
				"batrider_bat_laugh_02",
				"batrider_bat_kill_10",
				"batrider_bat_cast_01",
				"batrider_bat_win_03",
				"batrider_bat_battlebegins_02",
				"batrider_bat_ability_napalm_06",
				"batrider_bat_kill_04",
				"batrider_bat_ability_failure_03",
				},
				{
				"beastmaster_beas_laugh_09",
				"beastmaster_beas_ability_summonsboar_04",
				"beastmaster_beas_rare_01",
				"beastmaster_beas_kill_07",
				"beastmaster_beas_immort_02",
				"beastmaster_beas_ability_animalsound_02",
				"beastmaster_beas_buysnecro_07",
				"beastmaster_beas_ability_animalsound_01",
				},
				{
				"bloodseeker_blod_laugh_02",
				"bloodseeker_blod_kill_10",
				"bloodseeker_blod_deny_09",
				"bloodseeker_blod_drop_rare_01",
				"bloodseeker_blod_respawn_10",
				"bloodseeker_blod_ability_rupture_02",
				"bloodseeker_blod_ability_rupture_04",
				"bloodseeker_blod_begin_01",
				},
				{
				"bounty_hunter_bount_laugh_07",
				"bounty_hunter_bount_ability_track_kill_02",
				"bounty_hunter_bount_rival_15",
				"bounty_hunter_bount_kill_14",
				"bounty_hunter_bount_bottle_01",
				"bounty_hunter_bount_ability_wind_attack_04",
				"bounty_hunter_bount_ability_track_02",
				"bounty_hunter_bount_level_09",
				},
				{
				"brewmaster_brew_laugh_07",
				"brewmaster_brew_ability_primalsplit_11",
				"brewmaster_brew_ability_failure_03",
				"brewmaster_brew_level_07",
				"brewmaster_brew_level_08",
				"brewmaster_brew_kill_03",
				"brewmaster_brew_respawn_01",
				"brewmaster_brew_spawn_05",
				},
				{
				"bristleback_bristle_laugh_02",
				"bristleback_bristle_levelup_04",
				"bristleback_bristle_rival_31",
				"bristleback_bristle_happy_04",
				"bristleback_bristle_deny_08",
				"bristleback_bristle_attack_22",
				"bristleback_bristle_kill_03",
				"bristleback_bristle_spawn_03",
				},
				{
				"broodmother_broo_laugh_06",
				"broodmother_broo_ability_spawn_05",
				"broodmother_broo_invis_02",
				"broodmother_broo_kill_16",
				"broodmother_broo_kill_01",
				"broodmother_broo_ability_spawn_10",
				"broodmother_broo_ability_spawn_06",
				"broodmother_broo_kill_17",
				},
				{
				"centaur_cent_laugh_04",
				"centaur_cent_thanks_02",
				"centaur_cent_hoof_stomp_03",
				"centaur_cent_happy_02",
				"centaur_cent_failure_03",
				"centaur_cent_rival_21",
				"centaur_cent_doub_edge_05",
				"centaur_cent_levelup_06",
				},
				{
				"chaos_knight_chaknight_laugh_15",
				"chaos_knight_chaknight_levelup_04",
				"chaos_knight_chaknight_rival_10",
				"chaos_knight_chaknight_kill_10",
				"chaos_knight_chaknight_ally_04",
				"chaos_knight_chaknight_ability_phantasm_03",
				"chaos_knight_chaknight_purch_02",
				"chaos_knight_chaknight_battlebegins_01",
				},
				{
				"chen_chen_laugh_09",
				"chen_chen_thanks_02",
				"chen_chen_cast_04",
				"chen_chen_kill_04",
				"chen_chen_death_04",
				"chen_chen_bottle_02",
				"chen_chen_battlebegins_01",
				"chen_chen_respawn_06",
				},
				{
				"clinkz_clinkz_laugh_02",
				"clinkz_clinkz_thanks_04",
				"clinkz_clinkz_deny_07",
				"clinkz_clinkz_kill_06",
				"clinkz_clinkz_rival_01",
				"clinkz_clinkz_rival_07",
				"clinkz_clinkz_win_01",
				"clinkz_clinkz_kill_02",
				},
				{
				"rattletrap_ratt_kill_14",
				"rattletrap_ratt_level_13",
				"rattletrap_ratt_deny_09",
				"rattletrap_ratt_ability_flare_12",
				"rattletrap_ratt_ability_batt_14",
				"rattletrap_ratt_ability_batt_09",
				"rattletrap_ratt_respawn_18",
				"rattletrap_ratt_win_05",
				},
				{
				"crystalmaiden_cm_laugh_06",
				"crystalmaiden_cm_thanks_02",
				"crystalmaiden_cm_deny_02",
				"crystalmaiden_cm_kill_09",
				"crystalmaiden_cm_levelup_04",
				"crystalmaiden_cm_respawn_05",
				"crystalmaiden_cm_respawn_06",
				"crystalmaiden_cm_levelup_03",
				},
				{
				"dark_seer_dkseer_laugh_10",
				"dark_seer_dkseer_move_03",
				"dark_seer_dkseer_deny_06",
				"dark_seer_dkseer_kill_01",
				"dark_seer_dkseer_firstblood_02",
				"dark_seer_dkseer_happy_02",
				"dark_seer_dkseer_ability_wallr_05",
				"dark_seer_dkseer_rare_02",
				},
				{
				"dark_willow_sylph_wheel_laugh_01",
				"dark_willow_sylph_drop_rare_02",
				"dark_willow_sylph_respawn_01",
				"dark_willow_sylph_wheel_deny_02",
				"dark_willow_sylph_kill_06",
				"dark_willow_sylph_wheel_all_05",
				"dark_willow_sylph_wheel_all_02",
				"dark_willow_sylph_wheel_all_10",
				},
				{
				"dazzle_dazz_laugh_02",
				"dazzle_dazz_purch_03",
				"dazzle_dazz_deny_08",
				"dazzle_dazz_kill_05",
				"dazzle_dazz_lasthit_08",
				"dazzle_dazz_ability_shadowave_02",
				"dazzle_dazz_kill_10",
				"dazzle_dazz_respawn_09",
				},
				{
				"dawnbreaker_valora_wheel_laugh_04",
				"dawnbreaker_valora_wheel_thanks_01",
				"dawnbreaker_valora_wheel_deny_01",
				"dawnbreaker_valora_wheel_all_01",
				"dawnbreaker_valora_wheel_all_02",
				"dawnbreaker_valora_wheel_all_03",
				"dawnbreaker_valora_wheel_all_04",
				"dawnbreaker_valora_wheel_all_05",
				},
				{
				"death_prophet_dpro_laugh_012",
				"death_prophet_dpro_denyghost_04",
				"death_prophet_dpro_deny_16",
				"death_prophet_dpro_kill_11",
				"death_prophet_dpro_fail_05",
				"death_prophet_dpro_exorcism_15",
				"death_prophet_dpro_kill_18",
				"death_prophet_dpro_levelup_10",
				},
				{
				"disruptor_dis_laugh_03",
				"disruptor_dis_purch_02",
				"disruptor_dis_staticstorm_06",
				"disruptor_dis_respawn_10",
				"disruptor_dis_kill_10",
				"disruptor_dis_underattack_02",
				"disruptor_dis_rare_02",
				"disruptor_dis_illus_02",
				},
				{
				"doom_bringer_doom_laugh_10",
				"doom_bringer_doom_happy_01",
				"doom_bringer_doom_ability_lvldeath_03",
				"doom_bringer_doom_level_05",
				"doom_bringer_doom_respawn_12",
				"doom_bringer_doom_lose_04",
				"doom_bringer_doom_ability_fail_02",
				"doom_bringer_doom_respawn_08",
				},
				{
				"dragon_knight_drag_laugh_07",
				"dragon_knight_drag_level_05",
				"dragon_knight_drag_purch_01",
				"dragon_knight_drag_kill_11",
				"dragon_knight_drag_lasthit_09",
				"dragon_knight_drag_kill_01",
				"dragon_knight_drag_move_05",
				"dragon_knight_drag_ability_eldrag_06",
				},
				{
				"drowranger_dro_laugh_04",
				"drowranger_dro_win_04",
				"drowranger_dro_deny_02",
				"drowranger_drow_kill_13",
				"drowranger_drow_rival_13",
				"drowranger_dro_kill_05",
				"drowranger_dro_win_03",
				"drowranger_drow_kill_17",
				},
				{
				"earth_spirit_earthspi_laugh_06",
				"earth_spirit_earthspi_thanks_04",
				"earth_spirit_earthspi_deny_05",
				"earth_spirit_earthspi_rollingboulder_20",
				"earth_spirit_earthspi_invis_03",
				"earth_spirit_earthspi_lasthit_10",
				"earth_spirit_earthspi_failure_06",
				"earth_spirit_earthspi_illus_02",
				},
				{
				"earthshaker_erth_laugh_03",
				"earthshaker_erth_move_06",
				"earthshaker_erth_death_09",
				"earthshaker_erth_kill_08",
				"earthshaker_erth_respawn_06",
				"earthshaker_erth_ability_echo_06",
				"earthshaker_erth_rival_20",
				"earthshaker_erth_rare_05",
				},
				{
				"elder_titan_elder_laugh_05",
				"elder_titan_elder_purch_03",
				"elder_titan_elder_deny_06",
				"elder_titan_elder_lose_05",
				"elder_titan_elder_failure_01",
				"elder_titan_elder_move_11",
				"elder_titan_elder_failure_02",
				"elder_titan_elder_kill_04",
				},
				{
				"ember_spirit_embr_laugh_12",
				"ember_spirit_embr_levelup_01",
				"ember_spirit_embr_itemrare_01",
				"ember_spirit_embr_attack_06",
				"ember_spirit_embr_kill_12",
				"ember_spirit_embr_move_02",
				"ember_spirit_embr_rival_03",
				"ember_spirit_embr_failure_02",
				},
				{
				"enchantress_ench_laugh_05",
				"enchantress_ench_win_03",
				"enchantress_ench_deny_13",
				"enchantress_ench_death_08",
				"enchantress_ench_deny_14",
				"enchantress_ench_kill_08",
				"enchantress_ench_deny_15",
				"enchantress_ench_rare_01",
				},
				{
				"enigma_enig_laugh_03",
				"enigma_enig_respawn_05",
				"enigma_enig_purch_01",
				"enigma_enig_ability_black_03",
				"enigma_enig_lasthit_01",
				"enigma_enig_rival_20",
				"enigma_enig_drop_medium_01",
				"enigma_enig_ability_black_01",
				},
				{
				"faceless_void_face_laugh_07",
				"faceless_void_face_win_03",
				"faceless_void_face_lose_03",
				"faceless_void_face_kill_01",
				"faceless_void_face_kill_11",
				"faceless_void_face_ability_chronos_failure_08",
				"faceless_void_face_rare_03",
				"faceless_void_face_ability_chronos_failure_07",
				},
				{
				"grimstroke_grimstroke_laugh_11",
				"grimstroke_grimstroke_wheel_thanks_01",
				"grimstroke_grimstroke_kill_11",
				"grimstroke_grimstroke_wheel_deny_03",
				"grimstroke_grimstroke_spawn_14",
				"grimstroke_grimstroke_kill_10",
				"grimstroke_grimstroke_wheel_deny_01",
				"grimstroke_grimstroke_taunt_01",
				},
				{
				"gyrocopter_gyro_laugh_11",
				"gyrocopter_gyro_flak_cannon_09",
				"gyrocopter_gyro_failure_03",
				"gyrocopter_gyro_homing_missile_destroyed_02",
				"gyrocopter_gyro_respawn_12",
				"gyrocopter_gyro_deny_05",
				"gyrocopter_gyro_kill_15",
				"gyrocopter_gyro_kill_02",
				},
				{
				"hoodwink_hoodwink_wheel_laugh_04",
				"hoodwink_hoodwink_wheel_thanks_02_02",
				"hoodwink_hoodwink_wheel_deny_01",
				"hoodwink_hoodwink_net_hit_12",
				"hoodwink_hoodwink_kill_23",
				"hoodwink_hoodwink_levelup_26",
				"hoodwink_hoodwink_attack_25",
				"hoodwink_hoodwink_lasthit_03",
				},
				{
				"huskar_husk_laugh_09",
				"huskar_husk_purch_01",
				"huskar_husk_ability_lifebrk_01",
				"huskar_husk_kill_06",
				"huskar_husk_ability_brskrblood_03",
				"huskar_husk_ability_lifebrk_05",
				"huskar_husk_lasthit_07",
				"huskar_husk_kill_04",
				},
				{
				"invoker_invo_laugh_06",
				"invoker_invo_purch_01",
				"invoker_invo_ability_invoke_01",
				"invoker_invo_kill_01",
				"invoker_invo_attack_05",
				"invoker_invo_failure_06",
				"invoker_invo_lasthit_06",
				"invoker_invo_rare_04",
				},
				{
				"wisp_laugh",
				"wisp_thanks",
				"wisp_deny",
				"wisp_ally",
				"wisp_win",
				"wisp_lose",
				"wisp_no_mana_not_yet01",
				"wisp_battlebegins",
				},
				{
				"jakiro_jak_deny_13",
				"jakiro_jak_bottle_01",
				"jakiro_jak_rare_03",
				"jakiro_jak_deny_12",
				"jakiro_jak_level_05",
				"jakiro_jak_bottle_03",
				"jakiro_jak_ability_failure_07",
				"jakiro_jak_brother_02",
				},
				{
				"juggernaut_jug_laugh_05",
				"juggernaut_jugg_set_complete_06",
				"juggernaut_jugg_set_complete_04",
				"juggernaut_jugg_taunt_06",
				"juggernaut_jugg_set_complete_03",
				"juggernaut_jug_ability_stunteleport_03",
				"juggernaut_jug_kill_09",
				"juggernaut_jugg_set_complete_05",
				},
				{
				"keeper_of_the_light_keep_laugh_06",
				"keeper_of_the_light_keep_thanks_04",
				"keeper_of_the_light_keep_nomana_06",
				"keeper_of_the_light_keep_kill_18",
				"keeper_of_the_light_keep_deny_12",
				"keeper_of_the_light_keep_deny_16",
				"keeper_of_the_light_keep_kill_09",
				"keeper_of_the_light_keep_cast_02",
				},
				{
				"kunkka_kunk_laugh_06",
				"kunkka_kunk_thanks_03",
				"kunkka_kunk_kill_04",
				"kunkka_kunk_attack_08",
				"kunkka_kunk_kill_10",
				"kunkka_kunk_ability_tidebrng_02",
				"kunkka_kunk_ally_06",
				"kunkka_kunk_kill_13",
				},
				{
				"legion_commander_legcom_laugh_05",
				"legion_commander_legcom_itemcommon_02",
				"legion_commander_legcom_deny_07",
				"legion_commander_legcom_move_15",
				"legion_commander_legcom_ally_11",
				"legion_commander_legcom_duel_08",
				"legion_commander_legcom_duelfailure_06",
				"legion_commander_legcom_kill_14",
				},
				{
				"leshrac_lesh_deny_14",
				"leshrac_lesh_bottle_01",
				"leshrac_lesh_kill_13",
				"leshrac_lesh_lasthit_08",
				"leshrac_lesh_deny_13",
				"leshrac_lesh_purch_01",
				"leshrac_lesh_cast_01",
				"leshrac_lesh_kill_11",
				},
				{
				"lich_lich_level_09",
				"lich_lich_ability_armor_01",
				"lich_lich_kill_05",
				"lich_lich_immort_02",
				"lich_lich_attack_03",
				"lich_lich_ability_nova_01",
				"lich_lich_kill_09",
				"lich_lich_ability_icefrog_01",
				},
				{
				"life_stealer_lifest_laugh_07",
				"life_stealer_lifest_levelup_11",
				"life_stealer_lifest_ability_infest_burst_08",
				"life_stealer_lifest_ability_infest_burst_05",
				"life_stealer_lifest_ability_rage_06",
				"life_stealer_lifest_attack_02",
				"life_stealer_lifest_kill_13",
				"life_stealer_lifest_ability_infest_burst_06",
				},
				{
				"lina_lina_laugh_09",
				"lina_lina_kill_01",
				"lina_lina_kill_05",
				"lina_lina_kill_02",
				"lina_lina_spawn_08",
				"lina_lina_kill_03",
				"lina_lina_drop_common_01",
				"lina_lina_purch_02",
				},
				{
				"lion_lion_laugh_01",
				"lion_lion_move_12",
				"lion_lion_deny_06",
				"lion_lion_kill_05",
				"lion_lion_cast_03",
				"lion_lion_kill_02",
				"lion_lion_kill_04",
				"lion_lion_respawn_01",
				},
				{
				"lone_druid_lone_druid_laugh_05",
				"lone_druid_lone_druid_level_03",
				"lone_druid_lone_druid_ability_trueform_09",
				"lone_druid_lone_druid_ability_rabid_04",
				"lone_druid_lone_druid_ability_failure_02",
				"lone_druid_lone_druid_purch_02",
				"lone_druid_lone_druid_death_03",
				"lone_druid_lone_druid_bearform_ability_trueform_04",
				},
				{
				"luna_luna_laugh_09",
				"luna_luna_levelup_03",
				"luna_luna_drop_common",
				"luna_luna_kill_06",
				"luna_luna_ability_failure_03",
				"luna_luna_drop_medium",
				"luna_luna_shiwiz_02",
				"luna_luna_ability_eclipse_08",
				},
				{
				"lycan_lycan_laugh_14",
				"lycan_lycan_kill_04",
				"lycan_lycan_immort_02",
				"lycan_lycan_kill_01",
				"lycan_lycan_level_05",
				"lycan_lycan_attack_02",
				"lycan_lycan_attack_05",
				"lycan_lycan_cast_02",
				},
				{
				"magnataur_magn_laugh_06",
				"magnataur_magn_purch_04",
				"magnataur_magn_failure_08",
				"magnataur_magn_kill_01",
				"magnataur_magn_failure_10",
				"magnataur_magn_lasthit_02",
				"magnataur_magn_failure_03",
				"magnataur_magn_rare_05",
				},
				{
				"marci_marci_laugh",
				"marci_marci_thanks",
				"marci_marci_deny",
				"marci_marci_move",
				"marci_marci_move_2",
				"marci_marci_immortality",
				"marci_marci_surprised",
				"marci_marci_sad",
				},
				{
				"mars_mars_laugh_08",
				"mars_mars_thanks_03",
				"mars_mars_lose_05",
				"mars_mars_kill_09",
				"mars_mars_kill_10",
				"mars_mars_ability4_09",
				"mars_mars_song_02",
				"mars_mars_wheel_all_11",
				},
				{
				"medusa_medus_laugh_05",
				"medusa_medus_items_15",
				"medusa_medus_deny_01",
				"medusa_medus_kill_09",
				"medusa_medus_failure_01",
				"medusa_medus_deny_12",
				"medusa_medus_begin_03",
				"medusa_medus_illus_02",
				},
				{
				"meepo_meepo_deny_16",
				"meepo_meepo_drop_medium",
				"meepo_meepo_earthbind_05",
				"meepo_meepo_failure_03",
				"meepo_meepo_purch_05",
				"meepo_meepo_lose_05",
				"meepo_meepo_respawn_08",
				"meepo_meepo_lose_04",
				},
				{
				"mirana_mir_laugh_03",
				"mirana_mir_drop_common_01",
				"mirana_mir_illus_03",
				"mirana_mir_kill_09",
				"mirana_mir_kill_02",
				"mirana_mir_attack_08",
				"mirana_mir_rare_04",
				"mirana_mir_kill_04",
				},
				{
				"monkey_king_monkey_laugh_17",
				"monkey_king_monkey_drop_common_01",
				"monkey_king_monkey_regen_02",
				"monkey_king_monkey_win_02",
				"monkey_king_monkey_death_01",
				"monkey_king_monkey_drop_medium_01",
				"monkey_king_monkey_deny_brood_01",
				"monkey_king_monkey_ability5_07",
				},
				{
				"morphling_mrph_laugh_08",
				"morphling_mrph_ability_repfriend_02",
				"morphling_mrph_cast_01",
				"morphling_mrph_attack_09",
				"morphling_mrph_regen_02",
				"morphling_mrph_respawn_02",
				"morphling_mrph_kill_09",
				"morphling_mrph_kill_06",
				},
				{
				"naga_siren_naga_laugh_04",
				"naga_siren_naga_kill_02",
				"naga_siren_naga_kill_12",
				"naga_siren_naga_cast_01",
				"naga_siren_naga_rival_21",
				"naga_siren_naga_deny_08",
				"naga_siren_naga_rival_14",
				"naga_siren_naga_death_07",
				},
				{
				"furion_furi_laugh_01",
				"furion_furi_equipping_04",
				"furion_furi_equipping_05",
				"furion_furi_kill_01",
				"furion_furi_kill_03",
				"furion_furi_equipping_02",
				"furion_furi_deny_07",
				"furion_furi_kill_11",
				},
				{
				"necrolyte_necr_laugh_07",
				"necrolyte_necr_breath_02",
				"necrolyte_necr_purch_04",
				"necrolyte_necr_kill_03",
				"necrolyte_necr_rare_05",
				"necrolyte_necr_lose_03",
				"necrolyte_necr_respawn_12",
				"necrolyte_necr_rare_04",
				},
				{
				"night_stalker_nstalk_laugh_06",
				"night_stalker_nstalk_purch_03",
				"night_stalker_nstalk_respawn_05",
				"night_stalker_nstalk_purch_01",
				"night_stalker_nstalk_cast_01",
				"night_stalker_nstalk_attack_11",
				"night_stalker_nstalk_battlebegins_01",
				"night_stalker_nstalk_spawn_03",
				},
				{
				"nyx_assassin_nyx_laugh_07",
				"nyx_assassin_nyx_items_11",
				"nyx_assassin_nyx_death_03",
				"nyx_assassin_nyx_burn_05",
				"nyx_assassin_nyx_chitter_02",
				"nyx_assassin_nyx_waiting_01",
				"nyx_assassin_nyx_rival_25",
				"nyx_assassin_nyx_levelup_10",
				},
				{
				"ogre_magi_ogmag_laugh_14",
				"ogre_magi_ogmag_rival_04",
				"ogre_magi_ogmag_illus_02",
				"ogre_magi_ogmag_ability_multi_05",
				"ogre_magi_ogmag_kill_11",
				"ogre_magi_ogmag_rival_05",
				"ogre_magi_ogmag_rival_03",
				"ogre_magi_ogmag_kill_03",
				},
				{
				"omniknight_omni_laugh_10",
				"omniknight_omni_death_13",
				"omniknight_omni_level_09",
				"omniknight_omni_kill_09",
				"omniknight_omni_ability_degaura_04",
				"omniknight_omni_kill_02",
				"omniknight_omni_kill_12",
				"omniknight_omni_ability_degaura_05",
				},
				{
				"oracle_orac_laugh_13",
				"oracle_orac_kill_09",
				"oracle_orac_death_11",
				"oracle_orac_lasthit_04",
				"oracle_orac_itemare_02",
				"oracle_orac_respawn_06",
				"oracle_orac_kill_22",
				"oracle_orac_randomprophecies_02",
				},
				{
				"outworld_destroyer_odest_laugh_04",
				"outworld_destroyer_odest_begin_02",
				"outworld_destroyer_odest_win_04",
				"outworld_destroyer_odest_attack_11",
				"outworld_destroyer_odest_death_10",
				"outworld_destroyer_odest_rival_13",
				"outworld_destroyer_odest_death_12",
				"outworld_destroyer_odest_lasthit_03",
				},
				{
				"pangolin_pangolin_laugh_14",
				"pangolin_pangolin_kill_08",
				"pangolin_pangolin_levelup_11",
				"pangolin_pangolin_kill_06",
				"pangolin_pangolin_ability3_04",
				"pangolin_pangolin_ability4_08",
				"pangolin_pangolin_doubledam_03",
				"pangolin_pangolin_ally_09",
				},
				{
				"phantom_assassin_phass_laugh_07",
				"phantom_assassin_phass_happy_09",
				"phantom_assassin_phass_kill_02",
				"phantom_assassin_phass_kill_10",
				"phantom_assassin_phass_kill_01",
				"phantom_assassin_phass_ability_blur_02",
				"phantom_assassin_phass_deny_14",
				"phantom_assassin_phass_level_06",
				},
				{
				"phantom_lancer_plance_laugh_03",
				"phantom_lancer_plance_drop_rare",
				"phantom_lancer_plance_lasthit_06",
				"phantom_lancer_plance_cast_02",
				"phantom_lancer_plance_illus_02",
				"phantom_lancer_plance_respawn_05",
				"phantom_lancer_plance_win_02",
				"phantom_lancer_plance_kill_10",
				},
				{
				"phoenix_phoenix_bird_laugh",
				"phoenix_phoenix_bird_emote_good",
				"phoenix_phoenix_bird_denied",
				"phoenix_phoenix_bird_victory",
				"phoenix_phoenix_bird_death_defeat",
				"phoenix_phoenix_bird_inthebag",
				"phoenix_phoenix_bird_emote_bad",
				"phoenix_phoenix_bird_level_up",
				},
				{
				"puck_puck_laugh_01",
				"puck_puck_spawn_04",
				"puck_puck_kill_09",
				"puck_puck_ability_orb_03",
				"puck_puck_spawn_05",
				"puck_puck_lose_04",
				"puck_puck_ability_dreamcoil_05",
				"puck_puck_win_04",
				},
				{
				"pudge_pud_laugh_05",
				"pudge_pud_thanks_02",
				"pudge_pud_ability_rot_07",
				"pudge_pud_attack_08",
				"pudge_pud_rare_05",
				"pudge_pud_acknow_05",
				"pudge_pud_lasthit_07",
				"pudge_pud_kill_07",
				},
				{
				"pugna_pugna_laugh_01",
				"pugna_pugna_level_06",
				"pugna_pugna_cast_05",
				"pugna_pugna_ability_nblast_05",
				"pugna_pugna_respawn_03",
				"pugna_pugna_battlebegins_01",
				"pugna_pugna_ability_nward_07",
				"pugna_pugna_ability_life_08",
				},
				{
				"queenofpain_pain_laugh_04",
				"queenofpain_pain_spawn_02",
				"queenofpain_pain_kill_08",
				"queenofpain_pain_kill_12",
				"queenofpain_pain_attack_04",
				"queenofpain_pain_cast_01",
				"queenofpain_pain_taunt_01",
				"queenofpain_pain_respawn_04",
				},
				{
				"razor_raz_laugh_05",
				"razor_raz_ability_static_05",
				"razor_raz_cast_01",
				"razor_raz_kill_03",
				"razor_raz_kill_10",
				"razor_raz_lasthit_02",
				"razor_raz_kill_05",
				"razor_raz_kill_09",
				},
				{
				"riki_riki_laugh_03",
				"riki_riki_kill_01",
				"riki_riki_kill_03",
				"riki_riki_cast_01",
				"riki_riki_ability_blink_05",
				"riki_riki_ability_invis_03",
				"riki_riki_respawn_07",
				"riki_riki_kill_14",
				},
				{
				"rubick_rubick_laugh_06",
				"rubick_rubick_move_12",
				"rubick_rubick_lasthit_06",
				"rubick_rubick_levelup_04",
				"rubick_rubick_rival_07",
				"rubick_rubick_itemcommon_02",
				"rubick_rubick_failure_02",
				"rubick_rubick_itemrare_01",
				},
				{
				"sandking_skg_laugh_07",
				"sandking_sand_thanks_03",
				"sandking_skg_ability_caustic_04",
				"sandking_skg_kill_04",
				"sandking_skg_win_04",
				"sandking_skg_ability_epicenter_01",
				"sandking_skg_kill_09",
				"sandking_skg_kill_03",
				},
				{
				"shadow_demon_shadow_demon_laugh_03",
				"shadow_demon_shadow_demon_doubdam_02",
				"shadow_demon_shadow_demon_kill_10",
				"shadow_demon_shadow_demon_attack_13",
				"shadow_demon_shadow_demon_attack_03",
				"shadow_demon_shadow_demon_ability_soul_catcher_01",
				"shadow_demon_shadow_demon_lasthit_07",
				"shadow_demon_shadow_demon_kill_14",
				},
				{
				"nevermore_nev_laugh_02",
				"nevermore_nev_thanks_02",
				"nevermore_nev_deny_03",
				"nevermore_nev_kill_11",
				"nevermore_nev_ability_presence_02",
				"nevermore_nev_lasthit_02",
				"nevermore_nev_attack_07",
				"nevermore_nev_attack_11",
				},
				{
				"shadowshaman_shad_blink_02",
				"shadowshaman_shad_level_03",
				"shadowshaman_shad_ability_voodoo_06",
				"shadowshaman_shad_kill_03",
				"shadowshaman_shad_ability_entrap_03",
				"shadowshaman_shad_refresh_02",
				"shadowshaman_shad_ability_voodoo_08",
				"shadowshaman_shad_attack_07",
				},
				{
				"silencer_silen_laugh_13",
				"silencer_silen_level_06",
				"silencer_silen_deny_11",
				"silencer_silen_ability_silence_05",
				"silencer_silen_ability_failure_04",
				"silencer_silen_ability_curse_02",
				"silencer_silen_death_10",
				"silencer_silen_respawn_02",
				},
				{
				"skywrath_mage_drag_laugh_01",
				"skywrath_mage_drag_lasthit_07",
				"skywrath_mage_drag_deny_04",
				"skywrath_mage_drag_failure_01",
				"skywrath_mage_drag_fastres_01",
				"skywrath_mage_drag_thanks_02",
				"skywrath_mage_drag_inthebag_01",
				"skywrath_mage_drag_cast_02",
				},
				{
				"slardar_slar_laugh_05",
				"slardar_slar_kill_07",
				"slardar_slar_kill_01",
				"slardar_slar_longdistance_02",
				"slardar_slar_cast_02",
				"slardar_slar_deny_05",
				"slardar_slar_kill_03",
				"slardar_slar_win_05",
				},
				{
				"slark_slark_laugh_01",
				"slark_slark_illus_02",
				"slark_slark_cast_03",
				"slark_slark_rival_03",
				"slark_slark_failure_05",
				"slark_slark_kill_08",
				"slark_slark_drop_rare_01",
				"slark_slark_happy_07",
				},
				{
				"snapfire_snapfire_laugh_02_02",
				"snapfire_snapfire_wheel_thanks_02",
				"snapfire_snapfire_spawn_25",
				"snapfire_snapfire_wheel_all_03",
				"snapfire_snapfire_wheel_all_07",
				"snapfire_snapfire_whawiz_01",
				"snapfire_snapfire_rival_67",
				"snapfire_snapfire_spawn_24",
				},
				{
				"sniper_snip_laugh_08",
				"sniper_snip_level_06",
				"sniper_snip_ability_fail_04",
				"sniper_snip_tf2_04",
				"sniper_snip_ability_shrapnel_06",
				"sniper_snip_rare_04",
				"sniper_snip_kill_05",
				"sniper_snip_ability_shrapnel_03",
				},
				{
				"spectre_spec_laugh_13",
				"spectre_spec_ability_haunt_01",
				"spectre_spec_deny_01",
				"spectre_spec_death_07",
				"spectre_spec_lasthit_01",
				"spectre_spec_doubdam_02",
				"spectre_spec_kill_02",
				"spectre_spec_kill_01",
				},
				{
				"spirit_breaker_spir_laugh_06",
				"spirit_breaker_spir_level_07",
				"spirit_breaker_spir_ability_bash_03",
				"spirit_breaker_spir_purch_03",
				"spirit_breaker_spir_cast_01",
				"spirit_breaker_spir_lose_05",
				"spirit_breaker_spir_lasthit_07",
				"spirit_breaker_spir_ability_failure_02",
				},
				{
				"stormspirit_ss_laugh_06",
				"stormspirit_ss_win_03",
				"stormspirit_ss_kill_02",
				"stormspirit_ss_attack_06",
				"stormspirit_ss_ability_lightning_06",
				"stormspirit_ss_kill_03",
				"stormspirit_ss_ability_static_02",
				"stormspirit_ss_lasthit_04",
				},
				{
				"sven_sven_laugh_11",
				"sven_sven_thanks_01",
				"sven_sven_ability_teleport_01",
				"sven_sven_kill_02",
				"sven_sven_kill_05",
				"sven_sven_rare_07",
				"sven_sven_win_04",
				"sven_sven_respawn_02",
				},
				{
				"techies_tech_kill_23",
				"techies_tech_settrap_08",
				"techies_tech_failure_06",
				"techies_tech_suicidesquad_09",
				"techies_tech_detonatekill_02",
				"techies_tech_trapgoesoff_10",
				"techies_tech_ally_03",
				"techies_tech_kill_07",
				},
				{
				"templar_assassin_temp_laugh_02",
				"templar_assassin_temp_lasthit_06",
				"templar_assassin_temp_kill_10",
				"templar_assassin_temp_kill_12",
				"templar_assassin_temp_psionictrap_04",
				"templar_assassin_temp_levelup_01",
				"templar_assassin_temp_psionictrap_06",
				"templar_assassin_temp_refraction_04",
				},
				{
				"terrorblade_terr_laugh_07",
				"terrorblade_terr_conjureimage_03",
				"terrorblade_terr_purch_02",
				"terrorblade_terr_sunder_03",
				"terrorblade_terr_reflection_06",
				"terrorblade_terr_failure_05",
				"terrorblade_terr_kill_14",
				"terrorblade_terr_doubdam_04",
				},
				{
				"tidehunter_tide_laugh_05",
				"tidehunter_tide_battlebegins_02",
				"tidehunter_tide_ability_ravage_02",
				"tidehunter_tide_kill_12",
				"tidehunter_tide_level_18",
				"tidehunter_tide_bottle_01",
				"tidehunter_tide_rival_25",
				"tidehunter_tide_rare_01",
				},
				{
				"shredder_timb_laugh_04",
				"shredder_timb_thanks_03",
				"shredder_timb_kill_10",
				"shredder_timb_happy_05",
				"shredder_timb_drop_rare_02",
				"shredder_timb_whirlingdeath_05",
				"shredder_timb_rival_08",
				"shredder_timb_haste_02",
				},
				{
				"tinker_tink_laugh_10",
				"tinker_tink_thanks_03",
				"tinker_tink_levelup_06",
				"tinker_tink_ability_laser_03",
				"tinker_tink_respawn_01",
				"tinker_tink_kill_03",
				"tinker_tink_respawn_03",
				"tinker_tink_ability_laser_01",
				},
				{
				"tiny_tiny_laugh_05",
				"tiny_tiny_spawn_03",
				"tiny_tiny_ability_toss_11",
				"tiny_tiny_attack_03",
				"tiny_tiny_kill_09",
				"tiny_tiny_ability_toss_07",
				"tiny_tiny_attack_06",
				"tiny_tiny_level_02",
				},
				{
				"treant_treant_laugh_07",
				"treant_treant_freakout",
				"treant_treant_failure_03",
				"treant_treant_attack_07",
				"treant_treant_ability_naturesguise_06",
				"treant_treant_cast_02",
				"treant_treant_kill_05",
				"treant_treant_failure_01",
				},
				{
				"troll_warlord_troll_laugh_05",
				"troll_warlord_troll_battletrance_05",
				"troll_warlord_troll_deny_09",
				"troll_warlord_troll_kill_03",
				"troll_warlord_troll_ally_08",
				"troll_warlord_troll_ally_11",
				"troll_warlord_troll_death_05",
				"troll_warlord_troll_unknown_09",
				},
				{
				"tusk_tusk_laugh_06",
				"tusk_tusk_kill_26",
				"tusk_tusk_snowball_17",
				"tusk_tusk_rival_19",
				"tusk_tusk_snowball_24",
				"tusk_tusk_move_26",
				"tusk_tusk_kill_22",
				"tusk_tusk_snowball_23",
				},
				{
				"abyssal_underlord_abys_laugh_02",
				"abyssal_underlord_abys_thanks_03",
				"abyssal_underlord_abys_failure_01",
				"abyssal_underlord_abys_move_02",
				"abyssal_underlord_abys_kill_13",
				"abyssal_underlord_abys_rival_01",
				"abyssal_underlord_abys_move_12",
				"abyssal_underlord_abys_darkrift_03",
				},
				{
				"undying_undying_levelup_10",
				"undying_undying_thanks_04",
				"undying_undying_kill_09",
				"undying_undying_respawn_03",
				"undying_undying_gummy_vit_01",
				"undying_undying_respawn_05",
				"undying_undying_deny_14",
				"undying_undying_failure_02",
				},
				{
				"ursa_ursa_laugh_20",
				"ursa_ursa_respawn_12",
				"ursa_ursa_kill_10",
				"ursa_ursa_failure_02",
				"ursa_ursa_spawn_05",
				"ursa_ursa_kill_07",
				"ursa_ursa_levelup_07",
				"ursa_ursa_lasthit_08",
				},
				{
				"vengefulspirit_vng_deny_11",
				"vengefulspirit_vng_kill_01",
				"vengefulspirit_vng_respawn_06",
				"vengefulspirit_vng_regen_02",
				"vengefulspirit_vng_rare_09",
				"vengefulspirit_vng_deny_03",
				"vengefulspirit_vng_rare_10",
				"vengefulspirit_vng_rare_05",
				},
				{
				"venomancer_venm_laugh_02",
				"venomancer_venm_ability_ward_02",
				"venomancer_venm_purch_01",
				"venomancer_venm_kill_03",
				"venomancer_venm_ability_fail_07",
				"venomancer_venm_cast_02",
				"venomancer_venm_rosh_04",
				"venomancer_venm_attack_11",
				},
				{
				"viper_vipe_laugh_06",
				"viper_vipe_respawn_07",
				"viper_vipe_deny_06",
				"viper_vipe_kill_03",
				"viper_vipe_move_14",
				"viper_vipe_lasthit_05",
				"viper_vipe_ability_viprstrik_02",
				"viper_vipe_rare_03",
				},
				{
				"visage_visa_laugh_14",
				"visage_visa_happy_07",
				"visage_visa_rival_09",
				"visage_visa_kill_13",
				"visage_visa_failure_01",
				"visage_visa_rival_02",
				"visage_visa_spawn_05",
				"visage_visa_happy_03",
				},
				{
				"void_spirit_voidspir_laugh_05",
				"void_spirit_voidspir_thanks_04",
				"void_spirit_voidspir_spawn_14",
				"void_spirit_voidspir_rival_114",
				"void_spirit_voidspir_rival_113",
				"void_spirit_voidspir_rival_72",
				"void_spirit_voidspir_rival_71",
				"void_spirit_voidspir_wheel_all_10_02",
				},
				{
				"warlock_warl_laugh_06",
				"warlock_warl_ability_reign_07",
				"warlock_warl_defusal_04",
				"warlock_warl_kill_05",
				"warlock_warl_incant_18",
				"warlock_warl_kill_07",
				"warlock_warl_lasthit_02",
				"warlock_warl_doubdemon_06",
				},
				{
				"weaver_weav_laugh_04",
				"weaver_weav_win_03",
				"weaver_weav_ability_timelap_05",
				"weaver_weav_kill_07",
				"weaver_weav_fastres_01",
				"weaver_weav_respawn_02",
				"weaver_weav_kill_03",
				"weaver_weav_lasthit_07",
			},
			{
				"windrunner_wind_laugh_08",
				"windrunner_wind_lasthit_04",
				"windrunner_wind_deny_06",
				"windrunner_wind_kill_11",
				"windrunner_wind_ability_shackleshot_01",
				"windrunner_wind_kill_06",
				"windrunner_wind_lose_06",
				"windrunner_wind_attack_04",
			},
			{
				"winter_wyvern_winwyv_laugh_03",
				"winter_wyvern_winwyv_thanks_01",
				"winter_wyvern_winwyv_deny_08",
				"winter_wyvern_winwyv_death_09",
				"winter_wyvern_winwyv_lasthit_07",
				"winter_wyvern_winwyv_kill_03",
				"winter_wyvern_winwyv_winterscurse_11",
				"winter_wyvern_winwyv_levelup_08",
			},
			{
				"witchdoctor_wdoc_laugh_02",
				"witchdoctor_wdoc_level_08",
				"witchdoctor_wdoc_killspecial_01",
				"witchdoctor_wdoc_killspecial_03",
				"witchdoctor_wdoc_move_06",
				"witchdoctor_wdoc_ability_cask_03",
				"witchdoctor_wdoc_kill_11",
				"witchdoctor_wdoc_laugh_03",
			},
			{
				"skeleton_king_wraith_laugh_04",
				"skeleton_king_wraith_ally_01",
				"skeleton_king_wraith_move_08",
				"skeleton_king_wraith_attack_03",
				"skeleton_king_wraith_purch_03",
				"skeleton_king_wraith_rare_06",
				"skeleton_king_wraith_items_02",
				"skeleton_king_wraith_win_03",
			},
			{
				"zuus_zuus_laugh_01",
				"zuus_zuus_level_03",
				"zuus_zuus_win_05",
				"zuus_zuus_cast_02",
				"zuus_zuus_kill_05",
				"zuus_zuus_death_07",
				"zuus_zuus_ability_thunder_01",
				"zuus_zuus_rival_13",
			}
		}
		if vousedcol[keys.PlayerID] == nil then vousedcol[keys.PlayerID] = 0 end
		if votimer[keys.PlayerID] ~= nil then
			if GameRules:GetGameTime() - votimer[keys.PlayerID] > 5 + vousedcol[keys.PlayerID] and (phraseDoesntHasCooldown == nil or phraseDoesntHasCooldown == true) then
				local chat = LoadKeyValues("scripts/hero_chat_wheel_english.txt")
				--EmitAnnouncerSound(heroesvo[selectedid][selectedid2])
				ChatSound(heroesvo[selectedid][selectedid2], keys.PlayerID)
				CustomChat:MessageToAll(chat["dota_chatwheel_message_"..selectedstr], keys.PlayerID)

				votimer[keys.PlayerID] = GameRules:GetGameTime()
				vousedcol[keys.PlayerID] = vousedcol[keys.PlayerID] + 1
			else
				local remaining_cd = string.format("%.1f", 5 + vousedcol[keys.PlayerID] - (GameRules:GetGameTime() - votimer[keys.PlayerID]))
				CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(keys.PlayerID), "display_custom_error_with_value", {
					message = "#wheel_cooldown",
					values = {
						["sec"] = remaining_cd,
					},
				})
			end
		else
			local chat = LoadKeyValues("scripts/hero_chat_wheel_english.txt")
			--EmitAnnouncerSound(heroesvo[selectedid][selectedid2])
			ChatSound(heroesvo[selectedid][selectedid2], keys.PlayerID)
			CustomChat:MessageToAll(chat["dota_chatwheel_message_"..selectedstr], keys.PlayerID)
			votimer[keys.PlayerID] = GameRules:GetGameTime()
			vousedcol[keys.PlayerID] = vousedcol[keys.PlayerID] + 1
		end
	end
end

function ChatSound(phrase, source_player_id)
	local all_heroes = HeroList:GetAllHeroes()
	for _, hero in pairs(all_heroes) do
		if hero:IsRealHero() and hero:IsControllableByAnyPlayer() then
			local player_id = hero:GetPlayerOwnerID()
			if player_id and not _G.tPlayersMuted[player_id][source_player_id] then
				local player = PlayerResource:GetPlayer(player_id)
				CustomGameEventManager:Send_ServerToPlayer(player, "chat_wheel:emit_sound", {
					sound = phrase
				})
				if phrase == "soundboard.ceb.start" then
					Timers:CreateTimer(2, function()
						StopGlobalSound("soundboard.ceb.start")
						CustomGameEventManager:Send_ServerToPlayer(player, "chat_wheel:emit_sound", {
							sound = "soundboard.ceb.stop"
						})
					end)
				end
			end
		end
	end
end

RegisterCustomEventListener("SelectVO", SelectVO)

RegisterCustomEventListener("set_mute_player", function(data)
	if data and data.PlayerID and data.toPlayerId then
		local fromId = data.PlayerID
		local toId = data.toPlayerId
		local disable = data.disable

		_G.tPlayersMuted[fromId][toId] = disable == 1
	end
end)

function GetTopPlayersList(fromTopCount, team, sortFunction)
	local focusTableHeroes

	if team == DOTA_TEAM_GOODGUYS then
		focusTableHeroes = _G.tableRadiantHeroes
	elseif team == DOTA_TEAM_BADGUYS then
		focusTableHeroes = _G.tableDireHeroes
	end
	local playersSortInfo = {}

	for _, focusHero in pairs(focusTableHeroes) do
		if focusHero and not focusHero:IsNull() and IsValidEntity(focusHero) and focusHero.GetPlayerOwnerID then
			playersSortInfo[focusHero:GetPlayerOwnerID()] = sortFunction(focusHero)
		end
	end

	local topPlayers = {}

	local countPlayers = 0
	while(countPlayers < fromTopCount or countPlayers == 12) do
		local bestPlayerValue = -1
		local bestPlayer
		for playerID, playerInfo in pairs(playersSortInfo) do
			if not topPlayers[playerID] then
				if bestPlayerValue < playerInfo then
					bestPlayerValue = playerInfo
					bestPlayer = playerID
				end
			end
		end
		countPlayers = countPlayers + 1
		if bestPlayer and bestPlayerValue > -1 then
			topPlayers[bestPlayer] = bestPlayerValue
		end
	end
	return topPlayers
end

function PlayerForFeedBack(team)
	for id = 0, 23 do
		local state = PlayerResource:GetConnectionState(id)
		if (PlayerResource:GetTeam(id) == team) and (state == DOTA_CONNECTION_STATE_ABANDONED or state == DOTA_CONNECTION_STATE_NOT_YET_CONNECTED) then
			return id
		end
	end
	return nil
end

RegisterCustomEventListener("patreon_update_chat_wheel_favorites", function(data)
	local playerId = data.PlayerID
	if not playerId then return end

	if WebApi.player_settings and WebApi.player_settings[data.PlayerID] then
		local favourites = data.favourites
		if not favourites then return end

		local old_settings = CustomNetTables:GetTableValue("player_settings", tostring(playerId))
		old_settings.chatWheelFavourites = favourites

		CustomNetTables:SetTableValue("player_settings", tostring(playerId), old_settings)

		WebApi.player_settings[data.PlayerID].chatWheelFavourites = favourites
		WebApi:ScheduleUpdateSettings(data.PlayerID)
	end
end)

RegisterCustomEventListener("ResetMmrRequest", function(data)
	if not IsServer() then return end

	local playerId = data.PlayerID
	if not playerId then return end

	local steamId = Battlepass:GetSteamId(playerId)
	if not steamId then return end

	local mapName = GetMapName()
	if not mapName then return end

	WebApi:Send(
		"match/reset_mmr",
		{
			mapName = mapName,
			steamId = steamId,
		},
		function()
			print("Successfully reset mmr")
		end,
		function(e)
			print("error while reset mmr: ", e)
		end
	)
end)

RegisterCustomEventListener("shortcut_shop_request_item_costs", function(event)
	local player_id = event.PlayerID
	if not player_id then return end

	local player = PlayerResource:GetPlayer(player_id)
	if not player then return end

	event.PlayerID = nil

	local res = {}

	for item_name,_ in pairs(event) do
		res[item_name] = GetItemCost(item_name)
	end

	CustomGameEventManager:Send_ServerToPlayer(player, "shortcut_shop_item_costs", res)
end)

function AddModifierAllByClassname(class_name, modifier_name)
	local units = Entities:FindAllByClassname(class_name)
	for _, unit in pairs(units) do
		unit:AddNewModifier(unit, nil, modifier_name, {duration = -1})
	end
end

function CMegaDotaGameMode:OnPlayerLearnedAbility(data)
	local ability_name = data.abilityname or ""

	local hero = PlayerResource:GetSelectedHeroEntity(data.PlayerID)
	if not hero then return end

	if ability_name == "special_bonus_attributes" then
		hero:RegisterManuallySpentAttributePoint()
	end
end
