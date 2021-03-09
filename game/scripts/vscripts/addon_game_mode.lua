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
local TROLL_FEED_DISTANCE_FROM_FOUNTAIN_TRIGGER = 6000 -- Distance from allince Fountain
local TROLL_FEED_BUFF_BASIC_TIME = (60 * 10)   -- 10 minutes
local TROLL_FEED_TOTAL_RESPAWN_TIME_MULTIPLE = 2.5 -- x2.5 respawn time. If you respawn 100sec, after debuff you respawn 250sec
local TROLL_FEED_INCREASE_BUFF_AFTER_DEATH = 60 -- 1 minute
local TROLL_FEED_RATIO_KD_TO_TRIGGER_MIN = -5 -- (Kill-Death)
local TROLL_FEED_NEED_TOKEN_TO_BUFF = 3
local TROLL_FEED_TOKEN_TIME_DIES_WITHIN = (60 * 1.5) -- 1.5 minutes
local TROLL_FEED_TOKEN_DURATION = (60 * 5) -- 5 minutes
local TROLL_FEED_MIN_RESPAWN_TIME = 60 -- 1 minute
local TROLL_FEED_SYSTEM_ASSISTS_TO_KILL_MULTI = 0.5 -- 10 assists = 5 "kills"

--Requirements to Buy Divine Rapier
local NET_WORSE_FOR_RAPIER_MIN = 20000

--Change team system
local ts_entities = LoadKeyValues('scripts/kv/ts_entities.kv')
local COOLDOWN_FOR_CHANGE_TEAM = (60 * 3) -- 3 minutes
local MIN_DIFFERNCE_PLAYERS_IN_TEAM = 2 -- Player can change team if they're playing 10vs12, not 11vs12
local TIME_LIMIT_FOR_CHANGE_TEAM = (60 * 20) -- Players cannot change team after this time
_G.changeTeamProgress = false
_G.changeTeamTimes = {}
_G.isChangeTeamAvailable = false

--Max neutral items for each player (hero/stash/courier)
_G.MAX_NEUTRAL_ITEMS_FOR_PLAYER = 3

local vo_tables = require("vo_tables")
require("common/init")
require("util")
require("neutral_items_drop_choice")
require("gpm_lib")
require("game_options/game_options")
require("shuffle_team")
require("map_loader")
Precache = require( "precache" )

WebApi.customGame = "Dota12v12"

LinkLuaModifier("modifier_dummy_inventory", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_core_courier", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_patreon_courier", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_silencer_new_int_steal", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_shadow_amulet_thinker", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_troll_feed_token", 'anti_feed_system/modifier_troll_feed_token', LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_troll_feed_token_couter", 'anti_feed_system/modifier_troll_feed_token_couter', LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_troll_debuff_stop_feed", 'anti_feed_system/modifier_troll_debuff_stop_feed', LUA_MODIFIER_MOTION_NONE)

LinkLuaModifier("modifier_super_tower","game_options/modifiers_lib/modifier_super_tower", LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_mega_creep","game_options/modifiers_lib/modifier_mega_creep", LUA_MODIFIER_MOTION_NONE)

_G.newStats = newStats or {}
_G.personalCouriers = {}
_G.mainTeamCouriers = {}

_G.lastDeathTimes = {}
_G.lastHeroKillers = {}
_G.lastHerosPlaceLastDeath = {}
_G.tableRadiantHeroes = {}
_G.tableDireHeroes = {}
_G.newRespawnTimes = {}

_G.itemsIsBuy = {}
_G.lastTimeBuyItemWithCooldown = {}

_G.tPlayersMuted = {}

if CMegaDotaGameMode == nil then
	_G.CMegaDotaGameMode = class({}) -- put CMegaDotaGameMode in the global scope
	--refer to: http://stackoverflow.com/questions/6586145/lua-require-with-global-local
end

function Activate()
	CMegaDotaGameMode:InitGameMode()
end

_G.ItemKVs = {}

function CMegaDotaGameMode:InitGameMode()
	_G.ItemKVs = LoadKeyValues("scripts/npc/npc_block_items_for_troll.txt")
	print( "10v10 Mode Loaded!" )

	local neutral_items = LoadKeyValues("scripts/npc/neutral_items.txt")

	_G.neutralItems = {}

	for _, data in pairs( neutral_items ) do
		for item, turn in pairs( data.items ) do
			if turn == 1 then
				_G.neutralItems[item] = true
			end
		end
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
	GameRules:GetGameModeEntity():SetRuneSpawnFilter( Dynamic_Wrap( CMegaDotaGameMode, "RuneSpawnFilter" ), self )
	GameRules:GetGameModeEntity():SetExecuteOrderFilter(Dynamic_Wrap(CMegaDotaGameMode, 'ExecuteOrderFilter'), self)
	GameRules:GetGameModeEntity():SetDamageFilter( Dynamic_Wrap( CMegaDotaGameMode, "DamageFilter" ), self )
	GameRules:SetCustomGameBansPerTeam(12)

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

	ListenToGameEvent('game_rules_state_change', Dynamic_Wrap(CMegaDotaGameMode, 'OnGameRulesStateChange'), self)
	ListenToGameEvent( "npc_spawned", Dynamic_Wrap( CMegaDotaGameMode, "OnNPCSpawned" ), self )
	ListenToGameEvent( "entity_killed", Dynamic_Wrap( CMegaDotaGameMode, 'OnEntityKilled' ), self )
	ListenToGameEvent("dota_player_pick_hero", Dynamic_Wrap(CMegaDotaGameMode, "OnHeroPicked"), self)
	ListenToGameEvent('player_connect_full', Dynamic_Wrap(CMegaDotaGameMode, 'OnConnectFull'), self)
	ListenToGameEvent('player_disconnect', Dynamic_Wrap(CMegaDotaGameMode, 'OnPlayerDisconnect'), self)
	ListenToGameEvent( "player_chat", Dynamic_Wrap( CMegaDotaGameMode, "OnPlayerChat" ), self )

	self.m_CurrentGoldScaleFactor = GOLD_SCALE_FACTOR_INITIAL
	self.m_CurrentXpScaleFactor = XP_SCALE_FACTOR_INITIAL
	self.couriers = {}
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

					if owner then
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
							CustomGameEventManager:Send_ServerToPlayer( PlayerResource:GetPlayer( owner:GetPlayerID() ), "display_custom_error", { message = "#dropped_wards_return_error" } )
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
	return (unit:GetKills() + (unit:GetAssists() * TROLL_FEED_SYSTEM_ASSISTS_TO_KILL_MULTI) - unit:GetDeaths())
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
	local ggp = 0
	local bgp = 0
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
	for i=0, PlayerResource:GetPlayerCount()-1 do
		if PlayerResource:GetTeam(i) == DOTA_TEAM_GOODGUYS then
			ggp = ggp + 1
			PlayerResource:SetCustomPlayerColor(i,ggcolor[ggp][1],ggcolor[ggp][2],ggcolor[ggp][3])
		end
		if PlayerResource:GetTeam(i) == DOTA_TEAM_BADGUYS then
			bgp = bgp + 1
			PlayerResource:SetCustomPlayerColor(i,bgcolor[bgp][1],bgcolor[bgp][2],bgcolor[bgp][3])
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
end
---------------------------------------------------------------------------
-- Filter: DamageFilter
---------------------------------------------------------------------------
function CMegaDotaGameMode:DamageFilter(event)
	local entindex_victim_const = event.entindex_victim_const
	local entindex_attacker_const = event.entindex_attacker_const
	local death_unit
	local killer

	if (entindex_victim_const) then death_unit = EntIndexToHScript(entindex_victim_const) end
	if (entindex_attacker_const) then killer = EntIndexToHScript(entindex_attacker_const) end

	if death_unit and death_unit:HasModifier("modifier_troll_debuff_stop_feed") and (death_unit:GetHealth() <= event.damage) and (killer ~= death_unit) and (killer:GetTeamNumber()~=DOTA_TEAM_NEUTRALS) then
		if ItWorstKD(death_unit) and (not (UnitInSafeZone(death_unit, _G.lastHerosPlaceLastDeath[death_unit]))) then
			local newTime = death_unit:FindModifierByName("modifier_troll_debuff_stop_feed"):GetRemainingTime() + TROLL_FEED_INCREASE_BUFF_AFTER_DEATH
			--death_unit:RemoveModifierByName("modifier_troll_debuff_stop_feed")
			local normalRespawnTime =  death_unit:GetRespawnTime()
			local addRespawnTime = normalRespawnTime * (TROLL_FEED_TOTAL_RESPAWN_TIME_MULTIPLE - 1)

			if addRespawnTime + normalRespawnTime < TROLL_FEED_MIN_RESPAWN_TIME then
				addRespawnTime = TROLL_FEED_MIN_RESPAWN_TIME - normalRespawnTime
			end
			death_unit:AddNewModifier(death_unit, nil, "modifier_troll_debuff_stop_feed", { duration = newTime, addRespawnTime = addRespawnTime })
		end
		death_unit:Kill(nil, death_unit)
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
		npc_dota_goodguys_range_rax_top = 1,
		npc_dota_goodguys_melee_rax_top = 2,
		npc_dota_goodguys_range_rax_mid = 1,
		npc_dota_goodguys_melee_rax_mid = 2,
		npc_dota_goodguys_range_rax_bot = 1,
		npc_dota_goodguys_melee_rax_bot = 2,
		npc_dota_badguys_range_rax_top = 1,
		npc_dota_badguys_melee_rax_top = 2,
		npc_dota_badguys_range_rax_mid = 1,
		npc_dota_badguys_melee_rax_mid = 2,
		npc_dota_badguys_range_rax_bot = 1,
		npc_dota_badguys_melee_rax_bot = 2,
	}
	if raxRespawnTimeWorth[name] ~= nil then
		local team = killedUnit:GetTeam()
		raxBonuses[team] = raxBonuses[team] + raxRespawnTimeWorth[name]
		SendOverheadEventMessage( nil, OVERHEAD_ALERT_MANA_ADD, killedUnit, raxRespawnTimeWorth[name], nil )
		GameRules:SendCustomMessage("#destroyed_" .. string.sub(name,10,#name - 4),-1,0)
		if raxBonuses[team] == 9 then
			raxBonuses[team] = 11
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

			newStats[player_id] = newStats[player_id] or {
				npc_dota_sentry_wards = 0,
				npc_dota_observer_wards = 0,
				tower_damage = 0,
				killed_hero = {}
			}

			local kh = newStats[player_id].killed_hero

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

		timeLeft = timeLeft + ((raxBonuses[killedUnit:GetTeam()] - raxBonuses[killedUnit:GetOpposingTeamNumber()]) * (1-respawnReduction))

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

	Timers:CreateTimer(0.1, function()
		if spawnedUnit and not spawnedUnit:IsNull() and ((spawnedUnit.IsTempestDouble and spawnedUnit:IsTempestDouble()) or (spawnedUnit.IsClone and spawnedUnit:IsClone())) then
			local playerId = spawnedUnit:GetPlayerOwnerID()
			if _G.PlayersPatreonsPerk[playerId] then
				local perkName = _G.PlayersPatreonsPerk[playerId]
				spawnedUnit:AddNewModifier(spawnedUnit, nil, perkName, {duration = -1})
				local mainHero = PlayerResource:GetSelectedHeroEntity(playerId)
				local perkStacks = mainHero:GetModifierStackCount(perkName, mainHero)
				spawnedUnit:SetModifierStackCount(perkName, nil, perkStacks)
			end
		end
	end)

	if spawnedUnit and spawnedUnit.reduceCooldownAfterRespawn and _G.lastHeroKillers[spawnedUnit] then
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
	if spawnedUnit and (_G.lastDeathTimes[spawnedUnit] ~= nil) and (spawnedUnit:GetDeaths() > 1) and ((GameRules:GetGameTime() - _G.lastDeathTimes[spawnedUnit]) < TROLL_FEED_TOKEN_TIME_DIES_WITHIN) and not spawnedUnit:HasModifier("modifier_troll_debuff_stop_feed") and (_G.lastHeroKillers[spawnedUnit]~=spawnedUnit) and (not (UnitInSafeZone(spawnedUnit, _G.lastHerosPlaceLastDeath[spawnedUnit]))) and (_G.lastHeroKillers[spawnedUnit]:GetTeamNumber()~=DOTA_TEAM_NEUTRALS) then
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

		newStats[player_id] = newStats[player_id] or {
			npc_dota_sentry_wards = 0,
			npc_dota_observer_wards = 0,
			tower_damage = 0,
			killed_hero = {}
		}

		newStats[player_id][name] = newStats[player_id][name] + 1
		local wardsName = {
			["npc_dota_sentry_wards"] = "item_ward_sentry",
			["npc_dota_observer_wards"] = "item_ward_observer",
		}
		Timers:CreateTimer(0.04, function()
			if HeroHasWards(owner:GetAssignedHero(), wardsName[name]) then
				ReloadTimerHoldingCheckerForPlayer(player_id)
			else
				RemoveTimerHoldingCheckerForPlayer(player_id)
			end
			return nil
		end
		)
	end

	if spawnedUnit:IsRealHero() then
		spawnedUnit:AddNewModifier(spawnedUnit, nil, "modifier_rax_bonus", {})
		-- Silencer Nerf
		local playerId = spawnedUnit:GetPlayerID()
		Timers:CreateTimer(1, function()
			if spawnedUnit:HasModifier("modifier_silencer_int_steal") then
				spawnedUnit:RemoveModifierByName('modifier_silencer_int_steal')
				spawnedUnit:AddNewModifier(spawnedUnit, nil, "modifier_silencer_new_int_steal", {})
			end
			UniquePortraits:UpdatePortraitsDataFromPlayer(playerId)
		end)

		if self.couriers[spawnedUnit:GetTeamNumber()] then
			self.couriers[spawnedUnit:GetTeamNumber()]:SetControllableByPlayer(spawnedUnit:GetPlayerID(), true)
		end

		if not spawnedUnit.firstTimeSpawned then
			spawnedUnit.firstTimeSpawned = true
			spawnedUnit:SetContextThink("HeroFirstSpawn", function()
				--[[
				if spawnedUnit == PlayerResource:GetSelectedHeroEntity(playerId) then
					Patreons:GiveOnSpawnBonus(playerId)
				end
				]]
			end, 2/30)
		end

		if PlayerResource:GetPlayer(playerId) and not PlayerResource:GetPlayer(playerId).dummyInventory then
			CreateDummyInventoryForPlayer(playerId, spawnedUnit)
		end

		if not spawnedUnit.dummyCaster then
			Cosmetics:InitCosmeticForUnit(spawnedUnit)
		end
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

	return true
end

function CMegaDotaGameMode:RuneSpawnFilter(kv)
	local r = RandomInt( 0, 5 )

	if r == 5 then r = 6 end

	kv.rune_type = r

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

	filterTable["experience"] = self.m_CurrentXpScaleFactor * filterTable["experience"]
	return true
end

function CMegaDotaGameMode:OnGameRulesStateChange(keys)
	local newState = GameRules:State_Get()

	if newState ==  DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP then
		AutoTeam:Init()
	end

	if newState ==  DOTA_GAMERULES_STATE_HERO_SELECTION then
		ShuffleTeam:SortInMMR()
		AutoTeam:EnableFreePatreonForBalance()
	end

	if newState == DOTA_GAMERULES_STATE_PRE_GAME then
		if not GameRules.map_loaded then
			MapLoader:LoadRandom()
			GameRules.map_loaded = true
		end
	end

	if newState == DOTA_GAMERULES_STATE_POST_GAME then
		local couriers = FindUnitsInRadius( 2, Vector( 0, 0, 0 ), nil, FIND_UNITS_EVERYWHERE, DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_COURIER, DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER, false )

		for i = 0, 23 do
			if PlayerResource:IsValidPlayer( i ) then
				local networth = 0
				local hero = PlayerResource:GetSelectedHeroEntity( i )

				for _, cour in pairs( couriers ) do
					if cour:GetTeam() == cour:GetTeam() then
						for s = 0, 8 do
							local item = cour:GetItemInSlot( s )

							if item and item:GetOwner() == hero then
								networth = networth + item:GetCost()
							end
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

				local stats = {
					networth = networth,
					total_damage = PlayerResource:GetRawPlayerDamage( i ),
					total_healing = PlayerResource:GetHealing( i ),
				}

				if newStats and newStats[i] then
					stats.tower_damage = newStats[i].tower_damage
					stats.sentries_count = newStats[i].npc_dota_sentry_wards
					stats.observers_count = newStats[i].npc_dota_observer_wards
					stats.killed_hero = newStats[i].killed_hero
				end

				CustomNetTables:SetTableValue( "custom_stats", tostring( i ), stats )
			end
		end

		local winner
		local forts = Entities:FindAllByClassname("npc_dota_fort")
		for _, fort in ipairs(forts) do
			if fort:GetHealth() > 0 then
				local team = fort:GetTeam()
				if winner then
					winner = nil
					break
				end

				winner = team
			end
		end

		if winner then
			WebApi:AfterMatch(winner)
		end
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
		ShuffleTeam:GiveBonusToWeakTeam()
		if GameOptions:OptionsIsActive("super_towers") then
			local towers = Entities:FindAllByClassname('npc_dota_tower')
			for _, tower in pairs(towers) do
				tower:AddNewModifier(tower, nil, "modifier_super_tower", {duration = -1})
			end
		end

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
				return nil
			end
		})

        local fountains = Entities:FindAllByClassname('ent_dota_fountain')
		-- Loop over all ents
        for k,fountain in pairs(fountains) do
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
		if game_start then
			local courier_spawn = {}
			courier_spawn[2] = Entities:FindByClassname(nil, "info_courier_spawn_radiant")
			courier_spawn[3] = Entities:FindByClassname(nil, "info_courier_spawn_dire")

			--for team = 2, 3 do
			--	self.couriers[team] = CreateUnitByName("npc_dota_courier", courier_spawn[team]:GetAbsOrigin(), true, nil, nil, team)
			--	if _G.mainTeamCouriers[team] == nil then
			--		_G.mainTeamCouriers[team] = self.couriers[team]
			--	end
			--	self.couriers[team]:AddNewModifier(self.couriers[team], nil, "modifier_core_courier", {})
			--end
		end
--		Timers:CreateTimer(30, function()
--			for i=0,PlayerResource:GetPlayerCount() do
--				local hero = PlayerResource:GetSelectedHeroEntity(i)
--				if hero ~= nil then
--					if hero:GetTeam() == DOTA_TEAM_GOODGUYS then
--						hero:AddItemByName("item_courier")
--						break
--					end
--				end
--			end
--			for i=0,PlayerResource:GetPlayerCount() do
--				local hero = PlayerResource:GetSelectedHeroEntity(i)
--				if hero ~= nil then
--					if hero:GetTeam() == DOTA_TEAM_BADGUYS then
--						hero:AddItemByName("item_courier")
--						break
--					end
--				end
--			end
--		end)
		StartTrackPerks()
	end

	if newState == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
		Convars:SetFloat("host_timescale", 1)
		CheckTeamBalance()
		if game_start then
			game_start = false
			Timers:CreateTimer(0.1, function()
				GPM_Init()
				return nil
			end)
		end
	end
end

function SearchAndCheckRapiers(buyer, unit, plyID, maxSlots, timerKey)
	local fullRapierCost = 6000
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
			"item_reset_mmr"
		}
		if hInventoryParent:IsRealHero() then
			local plyID = hInventoryParent:GetPlayerID()
			if not plyID then return true end

			if itemName == "item_patreon_courier" then
				BlockToBuyCourier(plyID, hItem)
				return false
			end

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

							if itemName == "item_patreon_courier" then
								BlockToBuyCourier(prshID, hItem)
								return false
							end

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

		if  hItem:GetPurchaser() and (itemName == "item_relic")then
			local buyer = hItem:GetPurchaser()
			local plyID = buyer:GetPlayerID()
			local itemEntIndex = hItem:GetEntityIndex()
			local timerKey = "seacrh_rapier_on_player"..itemEntIndex
			Timers:CreateTimer(timerKey, {
				useGameTime = false,
				endTime = 0.4,
				callback = function()
					SearchAndCheckRapiers(buyer, buyer, plyID, 20, timerKey)
					--SearchAndCheckRapiers(buyer, SearchCorrectCourier(plyID, buyer:GetTeamNumber()), plyID, 10,timerKey)
					return 0.45
				end
			})
		end

		local purchaser = hItem:GetPurchaser()
		if purchaser then
			local prshID = purchaser:GetPlayerID()
			local correctInventory = hInventoryParent:IsMainHero() or hInventoryParent:GetClassname() == "npc_dota_lone_druid_bear" or hInventoryParent:IsCourier()

			if (filterTable["item_parent_entindex_const"] > 0) and hItem and correctInventory then
				if not purchaser:CheckPersonalCooldown(hItem) then
					purchaser:RefundItem(hItem)
					return false
				end

				if not purchaser:IsMaxItemsForPlayer(hItem) then
					purchaser:RefundItem(hItem)
					return false
				end

				if hItem:ItemIsFastBuying(prshID) then
					return hItem:TransferToBuyer(hInventoryParent)
				end
			end
		end
	end

	if _G.neutralItems[hItem:GetAbilityName()] and hItem.new == nil then
		hItem.new = true
		local inventoryIsCorrect = hInventoryParent:IsRealHero() or (hInventoryParent:GetClassname() == "npc_dota_lone_druid_bear") or hInventoryParent:IsCourier()
		if inventoryIsCorrect then
			local playerId = hInventoryParent:GetPlayerOwnerID() or hInventoryParent:GetPlayerID()
			CustomGameEventManager:Send_ServerToPlayer( PlayerResource:GetPlayer( playerId ), "neutral_item_picked_up", { item = filterTable.item_entindex_const })
			return false
		end
	end

	if hItem and hItem.neutralDropInBase then
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
	_G.tUserIds[data.PlayerID] = data.userid
	if _G.kicks and _G.kicks[data.PlayerID] then
		SendToServerConsole('kickid '.. data.userid);
	end
	CustomGameEventManager:Send_ServerToAllClients( "change_leave_status", {leave = false, playerId = data.PlayerID} )
	CheckTeamBalance()
end

function CMegaDotaGameMode:OnPlayerDisconnect(data)
	CustomGameEventManager:Send_ServerToAllClients( "change_leave_status", {leave = true, playerId = data.PlayerID} )
	Timers:CreateTimer(1, function()
		CheckTeamBalance()
	end)
	Timers:CreateTimer(310, function()
		CheckTeamBalance()
	end)
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

	if not IsInToolsMode() and unit and unit.GetTeam and PlayerResource:GetPlayer(playerId) then
		if unit:GetTeam() ~= PlayerResource:GetPlayer(playerId):GetTeam() then
			return false
		end
	end

	if orderType == DOTA_UNIT_ORDER_CAST_TARGET then
		if target:GetName() == "npc_dota_seasonal_ti9_drums" then
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
		local entIndexAbility = filterTable["entindex_ability"]
		if ItemIsWard(entIndexAbility) then
			if _G.playerIsBlockForWards[playerId] then
				CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(playerId), "display_custom_error", { message = "#you_cannot_buy_it" })
				return false
			elseif not _G.playerHasTimerWards[playerId] then
				StartTimerHoldingCheckerForPlayer(playerId)
			end
		end
	end

	if orderType == DOTA_UNIT_ORDER_DROP_ITEM or orderType == DOTA_UNIT_ORDER_EJECT_ITEM_FROM_STASH then
		if ability:GetAbilityName() == "item_relic" then
			CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(playerId), "display_custom_error", { message = "#cannotpullit" })
			return false
		end
	end

	if  orderType == DOTA_UNIT_ORDER_SELL_ITEM  then
		if ability:GetAbilityName() == "item_relic" then
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
		if not target then return true end
		local pickedItem = target:GetContainedItem()
		if not pickedItem then return true end
		local itemName = pickedItem:GetAbilityName()

		if _G.wardsList[itemName] then
			if _G.playerIsBlockForWards[playerId] then
				CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(playerId), "display_custom_error", { message = "#cannotpickupit" })
				return false
			elseif not _G.playerHasTimerWards[playerId] then
				StartTimerHoldingCheckerForPlayer(playerId)
			end
		end
		if _G.neutralItems[itemName] then
			if CheckCountOfNeutralItemsForPlayer(playerId) >= _G.MAX_NEUTRAL_ITEMS_FOR_PLAYER then
				DisplayError(playerId, "#player_still_have_a_lot_of_neutral_items")
				return
			end
		end
	end

	if orderType == 38 then
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

	if orderType == 25 then
		if ability and itemsToBeDestroy[ability:GetAbilityName()] then
			ability:Destroy()
		end
	end

	local disableHelpResult = DisableHelp.ExecuteOrderFilter(orderType, ability, target, unit, orderVector)
	if disableHelpResult == false then
		return false
	end

	--if filterTable then
	--	filterTable = EditFilterToCourier(filterTable)
	--end

	if orderType == DOTA_UNIT_ORDER_CAST_POSITION then
		if abilityName == "item_ward_dispenser" or abilityName == "item_ward_sentry" or abilityName == "item_ward_observer" then
			local list = Entities:FindAllByClassname("trigger_multiple")
			local fs = {
				Vector(5000,6912,0),
				Vector(-5300,-6938,0)
			}
			if PlayerResource:GetTeam(playerId) == 2 then
				fs = {fs[2],fs[1]}
			end
			for i=1,#list do
				if list[i]:GetName():find("neutralcamp") ~= nil then
					if IsInTriggerBox(list[i], 12, orderVector) and ( fs[1] - orderVector ):Length2D() < ( fs[2] - orderVector ):Length2D() then
						CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(playerId), "display_custom_error", { message = "#block_spawn_error" })
						return false
					end
				end
			end
		end
	end

	if unit then
		if unit:IsCourier() then
			if (orderType == DOTA_UNIT_ORDER_DROP_ITEM or orderType == DOTA_UNIT_ORDER_GIVE_ITEM) and ability and ability:IsItem() then
				local purchaser = ability:GetPurchaser()
				if purchaser and purchaser:GetPlayerID() ~= playerId then
					if purchaser:GetTeam() == PlayerResource:GetPlayer(playerId):GetTeam() then
						--CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(playerId), "display_custom_error", { message = "#hud_error_courier_cant_order_item" })
						return false
					end
				end
			end
		end
	end

	return true
end

local blockedChatPhraseCode = {
	[796] = true,
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
	Say(PlayerResource:GetPlayer(keys.PlayerID), min .. ":" .. sec, true)
end)

votimer = {}
vousedcol = {}
SelectVO = function(keys)
	local supporter_level = Supporters:GetLevel(keys.PlayerID)
	print(keys.num)
	local heroes = vo_tables.heroes
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
			local mesarrs = vo_tables.mesarrs
			selectedstr = mesarrs[keys.num]
			selectedid2 = keys.num
		else
			local locnum = keys.num - (startheronums-8)
			local nowheroname = string.sub(PlayerResource:GetSelectedHeroEntity(keys.PlayerID):GetName(), 15)
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
		local heroesvo = vo_tables.heroesvo
		if vousedcol[keys.PlayerID] == nil then vousedcol[keys.PlayerID] = 0 end
		if votimer[keys.PlayerID] ~= nil then
			if GameRules:GetGameTime() - votimer[keys.PlayerID] > 5 + vousedcol[keys.PlayerID] and (phraseDoesntHasCooldown == nil or phraseDoesntHasCooldown == true) then
				local chat = LoadKeyValues("scripts/hero_chat_wheel_english.txt")
				--EmitAnnouncerSound(heroesvo[selectedid][selectedid2])
				ChatSound(heroesvo[selectedid][selectedid2], keys.PlayerID)
				--GameRules:SendCustomMessage("<font color='#70EA72'>".."test".."</font>",-1,0)
				Say(PlayerResource:GetPlayer(keys.PlayerID), chat["dota_chatwheel_message_"..selectedstr], false)

				votimer[keys.PlayerID] = GameRules:GetGameTime()
				vousedcol[keys.PlayerID] = vousedcol[keys.PlayerID] + 1
			else
				local remaining_cd = " ("..string.format("%.1f", 5 + vousedcol[keys.PlayerID] - (GameRules:GetGameTime() - votimer[keys.PlayerID])).."s)"
				CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(keys.PlayerID), "display_custom_error", { message = "#wheel_cooldown"..remaining_cd })
			end
		else
			local chat = LoadKeyValues("scripts/hero_chat_wheel_english.txt")
			--EmitAnnouncerSound(heroesvo[selectedid][selectedid2])
			ChatSound(heroesvo[selectedid][selectedid2], keys.PlayerID)
			Say(PlayerResource:GetPlayer(keys.PlayerID), chat["dota_chatwheel_message_"..selectedstr], false)
			votimer[keys.PlayerID] = GameRules:GetGameTime()
			vousedcol[keys.PlayerID] = vousedcol[keys.PlayerID] + 1
		end
	end
end

function ChatSound(phrase, playerId)
	local all_heroes = HeroList:GetAllHeroes()
	for _, hero in pairs(all_heroes) do
		if hero:IsRealHero() and hero:IsControllableByAnyPlayer() and hero:GetPlayerID() and ((not _G.tPlayersMuted[hero:GetPlayerID()]) or (not _G.tPlayersMuted[hero:GetPlayerID()][playerId])) then
			EmitAnnouncerSoundForPlayer(phrase, hero:GetPlayerID())
			if phrase == "soundboard.ceb.start" then
				Timers:CreateTimer(2, function()
					StopGlobalSound("soundboard.ceb.start")
					EmitAnnouncerSoundForPlayer("soundboard.ceb.stop", hero:GetPlayerID())
				end
				)
			end
		end
	end
end

RegisterCustomEventListener("SelectVO", SelectVO)

RegisterCustomEventListener("set_mute_player", function(data)
	local fromId = data.PlayerID
	local toId = data.toPlayerId
	local disable = data.disable
	_G.tPlayersMuted[fromId] = _G.tPlayersMuted[fromId] or {}
	if disable == 0 then
		_G.tPlayersMuted[fromId][toId] = false
	else
		_G.tPlayersMuted[fromId][toId] = true
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
		playersSortInfo[focusHero:GetPlayerOwnerID()] = sortFunction(focusHero)
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

function CheckTeamBalance()
	if GameRules:GetDOTATime(false, true) >= TIME_LIMIT_FOR_CHANGE_TEAM then
		CustomGameEventManager:Send_ServerToAllClients("HideTeamChangePanel", {} )
		return
	end

	if GameOptions:OptionsIsActive("no_switch_team") then
		return
	end

	if GetMapName() == "dota_tourtament" then
		return
	end

	_G.changeTeamProgress = false
	local radiantPlayers = 0
	local direPlayers = 0

	for playerID = 0, 23 do
		local state = PlayerResource:GetConnectionState(playerID)
		if state == DOTA_CONNECTION_STATE_DISCONNECTED or state == DOTA_CONNECTION_STATE_CONNECTED or state == DOTA_CONNECTION_STATE_NOT_YET_CONNECTED then
			local team = PlayerResource:GetTeam(playerID)
			if team == DOTA_TEAM_GOODGUYS then
				radiantPlayers = radiantPlayers + 1
			elseif team == DOTA_TEAM_BADGUYS then
				direPlayers = direPlayers + 1
			end
		end
	end

	if math.abs(radiantPlayers-direPlayers) >= MIN_DIFFERNCE_PLAYERS_IN_TEAM then
		local highTeam = DOTA_TEAM_GOODGUYS
		if radiantPlayers < direPlayers then
			highTeam = DOTA_TEAM_BADGUYS
		end
		Timers:CreateTimer(0.5, function()
			_G.isChangeTeamAvailable = true
			CustomGameEventManager:Send_ServerToTeam(highTeam, "ShowTeamChangePanel", {} )
		end)
	else
		CustomGameEventManager:Send_ServerToAllClients("HideTeamChangePanel", {} )
	end
end

RegisterCustomEventListener("PlayerChangeTeam", function(data)
	local oldTeam = PlayerResource:GetTeam(data.PlayerID)
	local newTeam
	if oldTeam == DOTA_TEAM_GOODGUYS then
		newTeam = DOTA_TEAM_BADGUYS
	else
		newTeam = DOTA_TEAM_GOODGUYS
	end
	ChangeTeam(data.PlayerID, newTeam)
end)

function PlayerForFeedBack(team)
	for id = 0, 23 do
		local state = PlayerResource:GetConnectionState(id)
		if (PlayerResource:GetTeam(id) == team) and (state == DOTA_CONNECTION_STATE_ABANDONED or state == DOTA_CONNECTION_STATE_NOT_YET_CONNECTED) then
			return id
		end
	end
	return nil
end

function ChangeTeam(playerID, newTeam)
	if GameRules:GetDOTATime(false, true) >= TIME_LIMIT_FOR_CHANGE_TEAM then
		CustomGameEventManager:Send_ServerToAllClients("HideTeamChangePanel", {} )
		return
	end
	if GetTopPlayersList(3, PlayerResource:GetTeam(playerID), GetHeroKD)[playerID] then
		CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(playerID), "display_custom_error", { message = "#too_huge_kda_for_change_team" })
		return
	end
	if GetTopPlayersList(3, PlayerResource:GetTeam(playerID), function(hero)
		return PlayerResource:GetNetWorth(hero:GetPlayerOwnerID())
	end)[playerID] then
		CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(playerID), "display_custom_error", { message = "#too_huge_nw_for_change_team" })
		return
	end

	if _G.changeTeamProgress or (not _G.isChangeTeamAvailable) then return end

	if _G.changeTeamTimes[playerID] and (GameRules:GetGameTime() - _G.changeTeamTimes[playerID]) < COOLDOWN_FOR_CHANGE_TEAM then
		DisplayError(playerID, "Cooldown for change team")
		return
	end
	local feedbackChangeTeamPlayer = PlayerForFeedBack(newTeam)
	if not feedbackChangeTeamPlayer then return end
	_G.changeTeamTimes[playerID] = GameRules:GetGameTime()
	_G.changeTeamProgress = true
	_G.isChangeTeamAvailable = false
	CustomGameEventManager:Send_ServerToAllClients("HideTeamChangePanel", {} )
	CustomGameEventManager:Send_ServerToAllClients("PlayerChangedTeam", {playerId = playerID} )

	local teamForFeedback = DOTA_TEAM_BADGUYS
	if newTeam == DOTA_TEAM_BADGUYS then
		teamForFeedback = DOTA_TEAM_GOODGUYS
	end

	ChangeTeamForPlayer(playerID, newTeam)
	Timers:CreateTimer(4, function()
		ChangeTeamForPlayer(feedbackChangeTeamPlayer, teamForFeedback)
	end)
	Timers:CreateTimer(5, function()
		CheckTeamBalance()
	end)
end

function ChangeTeamForPlayer(playerID, newTeam)
	local maxPlayerInTeam = GameRules:GetCustomGameTeamMaxPlayers(newTeam)
	GameRules:SetCustomGameTeamMaxPlayers( newTeam, maxPlayerInTeam + 1)
	PlayerResource:SetCustomTeamAssignment(playerID, newTeam)

	local hero = PlayerResource:GetSelectedHeroEntity(playerID)
	if IsValidEntity(hero) then
		if _G.PlayersPatreonsPerk[playerID] then
			local perkName = _G.PlayersPatreonsPerk[playerID]
			local perkStacks = hero:GetModifierStackCount(perkName, hero)
			hero:RemoveModifierByName(perkName)
			Timers:CreateTimer(4, function()
				hero:AddNewModifier(hero, nil, perkName, {duration = -1})
				if perkStacks > 0 then
					hero:SetModifierStackCount(perkName, nil, perkStacks)
				end
			end)
		end

		hero:SetTeam(newTeam)
		hero:Kill(nil, hero)
		hero:SetTimeUntilRespawn(1)

		Timers:CreateTimer(3, function()
			CreateDummyInventoryForPlayer(hero:GetPlayerOwnerID(), hero)
			Cosmetics:InitCosmeticForUnit(hero)
		end)

		if hero:HasAbility('arc_warden_tempest_double') then
			local clones = Entities:FindAllByName(hero:GetClassname())
			for _,tempestDouble in pairs(clones) do
				if tempestDouble:IsTempestDouble() and playerID == tempestDouble:GetPlayerID() then
					tempestDouble:Kill(nil, nil)
				end
			end
		end

		if hero:HasAbility('meepo_divided_we_stand') then
			local clones = Entities:FindAllByName(hero:GetClassname())

			for _,meepoClone in pairs(clones) do
				if meepoClone:IsClone() and playerID == meepoClone:GetPlayerID() then
					meepoClone:SetTimeUntilRespawn(1)
				end
			end
		end

		local changeTeamForUnits = function(table, func)
			for spell, data in pairs(table) do
				if hero:HasAbility(spell) then
					local name = data.Name
					local units = Entities:FindAllByName(name)
					if #units == 0 then
						units = Entities:FindAllByModel(name)
					end
					for _, unit in pairs(units) do
						if unit:GetPlayerOwnerID() == playerID and (not data.Modifier or unit:HasModifier(data.Modifier)) then
							func(unit, newTeam)
							unit:SetTeam(newTeam)
						end
					end
				end
			end
		end

		changeTeamForUnits(ts_entities.Switch, function(unit, team) unit:SetTeam(team) end)
		changeTeamForUnits(ts_entities.Kill, function(unit) unit:Kill(nil, nil) end)

		local couriers = Entities:FindAllByName("npc_dota_courier")
		for _, courier in pairs(couriers) do
			if courier:GetPlayerOwnerID() == playerID then
				local fountain
				local vMoveFromFountain
				if newTeam == DOTA_TEAM_GOODGUYS then
					fountain = Entities:FindByName( nil, "ent_dota_fountain_good" )
					vMoveFromFountain = Vector(500,500,0)
				elseif newTeam == DOTA_TEAM_BADGUYS then
					fountain = Entities:FindByName( nil, "ent_dota_fountain_bad" )
					vMoveFromFountain = Vector(-500,-500,0)
				end
				local vFountainPoint = fountain:GetAbsOrigin()
				local vNewCourierPount = vFountainPoint + vMoveFromFountain + RandomVector(150)
				courier:SetTeam(newTeam)
				FindClearSpaceForUnit(courier, vNewCourierPount, false)
			end
		end
	end
	GameRules:SetCustomGameTeamMaxPlayers( newTeam, maxPlayerInTeam )
end

RegisterCustomEventListener("patreon_update_chat_wheel_favorites", function(data)
	local playerId = data.PlayerID
	if not playerId then return end

	if WebApi.playerSettings and WebApi.playerSettings[data.PlayerID] then
		local favourites = data.favourites
		if not favourites then return end

		WebApi.playerSettings[data.PlayerID].chatWheelFavourites = favourites
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
