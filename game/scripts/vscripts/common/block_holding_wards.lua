--[[
	Times in seconds
--]]

local BASE_TIME = 480 -- Time for see, player save or use wards
local BLOCK_TIME = 240 -- Time to block buying and pick up ward
--[[
	System work with this items list. You need write ID from KV files (original dota or custom)
--]]
local wardsID = {
	[42] = "item_ward_observer",
	[43] = "item_ward_sentry",
	[218] = "item_ward_dispenser",
}

_G.wardsList = {
	["item_ward_observer"] = true,
	["item_ward_sentry"] = true,
	["item_ward_dispenser"] = true,
}

_G.playerIsBlockForWards = {}
_G.playerHasTimerWards = {}

function ItemIsWard(itemID)
	return wardsID[itemID]
end

function SearchCourierForPlayer(playerID)
	local couriers = Entities:FindAllByClassname('npc_dota_courier')
	for _, courier in pairs(couriers) do
		if courier:GetOwner() and courier:GetOwner():GetPlayerID() == playerID then
			return courier
		end
	end
	return false
end

function StartTimerHoldingCheckerForPlayer(playerID)
	local couriers = Entities:FindAllByClassname('npc_dota_courier')
	for i, x in pairs(couriers) do
		print(i, x)
	end

	print("Start timer to block holding")
	local player = PlayerResource:GetPlayer(playerID)
	local playerEntIndex = player:GetEntityIndex()
	_G.playerHasTimerWards[playerID] = true
	Timers:CreateTimer("base_timer_to_holding_items" .. tostring(playerEntIndex), {
		useGameTime = false,
		endTime = BASE_TIME,
		callback = function()
			if not player or player:IsNull() then
				_G.playerHasTimerWards[playerID] = false
				return
			end
			_G.playerIsBlockForWards[playerID] = true
			_G.playerHasTimerWards[playerID] = false
			Timers:CreateTimer("base_block_to_holding_items" .. tostring(playerEntIndex), {
				useGameTime = false,
				endTime = BLOCK_TIME,
				callback = function()
					_G.playerIsBlockForWards[playerID] = false
					print("Hi, you UNblocked for buying and pick uping wards.")
					return nil
				end
			})
			DropWardsInBase(player:GetAssignedHero())
			if SearchCourierForPlayer(playerID) then
				DropWardsInBase(SearchCourierForPlayer(playerID))
			end
			print("Hi, you blocked for buying and pick uping wards.")
			return nil
		end
	})
end

function ReloadTimerHoldingCheckerForPlayer(playerID)
	print("You use ward. You have new timer")
	local playerEntIndex = PlayerResource:GetPlayer(playerID):GetEntityIndex()
	Timers:RemoveTimer("base_timer_to_holding_items" .. playerEntIndex)
	StartTimerHoldingCheckerForPlayer(playerID)
end

function RemoveTimerHoldingCheckerForPlayer(playerID)
	print("You use ward but you dont have any wards. Timer removed")
	local playerEntIndex = PlayerResource:GetPlayer(playerID):GetEntityIndex()
	_G.playerHasTimerWards[playerID] = false
	Timers:RemoveTimer("base_timer_to_holding_items" .. playerEntIndex)
end

function HeroHasWards(hero, itemName)
	print("start found wards")
	for i = 0, 20 do
		local currentItem = hero:GetItemInSlot(i)
		if currentItem then
			print(currentItem:GetName())
		end
		if currentItem and (currentItem:GetName() == itemName or currentItem:GetName() == "item_ward_dispenser") then
			print("You have ward in slot:", i)
			return true
		end
	end
	return false
end

function DropWardsInBase(unit)
	print("sorry, i drop your wards in base")

	local team = unit:GetTeam()
	local fountain
	local multiplier

	if team == DOTA_TEAM_GOODGUYS then
		multiplier = -350
		fountain = Entities:FindByName(nil, "ent_dota_fountain_good")
	elseif team == DOTA_TEAM_BADGUYS then
		multiplier = -650
		fountain = Entities:FindByName(nil, "ent_dota_fountain_bad")
	end

	local fountain_pos = fountain:GetAbsOrigin()
	local pos_item = fountain_pos:Normalized() * multiplier + RandomVector(RandomFloat(0, 200)) + fountain_pos
	pos_item.z = fountain_pos.z

	for i = 0, 20 do
		local currentItem = unit:GetItemInSlot(i)
		if currentItem and _G.wardsList[currentItem:GetName()] then
			unit:DropItemAtPositionImmediate(currentItem, pos_item)
		end
	end
end
