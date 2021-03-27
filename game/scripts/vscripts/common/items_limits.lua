LinkLuaModifier("modifier_dummy_inventory_custom", LUA_MODIFIER_MOTION_VERTICAL)

local notFastItems = {
	["item_ward_observer"] = true,
	["item_ward_sentry"] = true,
	["item_smoke_of_deceit"] = true,
	["item_clarity"] = true,
	["item_flask"] = true,
	["item_greater_mango"] = true,
	["item_enchanted_mango"] = true,
	["item_tango"] = true,
	["item_faerie_fire"] = true,
	["item_tpscroll"] = true,
	["item_dust"] = true,
}

local fastItems = {
	["item_disable_help_custom"] = true,
	["item_mute_custom"] = true,
	["item_banhammer"] = true,
}

local maxItemsForPlayer = {
	["item_banhammer"] = 2,
}
_G.itemsCooldownForPlayer = {
	["item_disable_help_custom"] = 10,
	["item_mute_custom"] = 10,
	["item_tome_of_knowledge"] = 300,
	["item_banhammer"] = 600,
	["item_reset_mmr"] = 20,
}


local maxItemsForPlayersData = {}
_G.itemsIsBuy = {}
_G.lastTimeBuyItemWithCooldown = {}
local itemsWithCharges = {}

local dotaItemsKV = LoadKeyValues("scripts/npc/items.txt")
for itemName, itemData in pairs(dotaItemsKV) do
	if type(itemData) == 'table' and itemData.ItemStockMax then
		itemsWithCharges[itemName] = true;
	end
end

function ItemIsFastBuying(itemName)
	return fastItems[itemName]
end

function CDOTA_BaseNPC:DoesHeroHasFreeSlot()
	for i = 0, 15 do
		if self:GetItemInSlot(i) == nil then
			return i
		end
	end
	return false
end

function CDOTA_Item:SetCooldownStackedItem(itemName, buyer)
	if _G.itemsCooldownForPlayer[itemName] then
		local buyerEntIndex = buyer:GetEntityIndex()
		Timers:CreateTimer(0.04, function()
			local itemCost = self:GetCost()
			local item = self
			if not notFastItems[itemName] then
				UTIL_Remove(item)
				item = buyer:AddItemByName(itemName)
			end
			local unique_key_cd = itemName .. "_" .. buyerEntIndex
			if _G.lastTimeBuyItemWithCooldown[unique_key_cd] == nil or (_G.itemsCooldownForPlayer[itemName] and (GameRules:GetGameTime() - _G.lastTimeBuyItemWithCooldown[unique_key_cd]) >= _G.itemsCooldownForPlayer[itemName]) then
				_G.lastTimeBuyItemWithCooldown[unique_key_cd] = GameRules:GetGameTime()
			elseif _G.itemsCooldownForPlayer[itemName] then
				buyer:ModifyGold(itemCost, false, 0)
				MessageToPlayerItemCooldown(itemName, buyer:GetPlayerID())
				UTIL_Remove(item)
			end
		end)
	end
end

function CDOTA_Item:TransferToBuyer(unit)
	local buyer = self:GetPurchaser()
	local buyerEntIndex = buyer:GetEntityIndex()
	local itemName = self:GetName()
	if notFastItems[itemName] then
		self:SetCooldownStackedItem(itemName, buyer)
		return
	end
	local unique_key = itemName .. "_" .. buyerEntIndex

	if unit:IsIllusion() then
		return
	end
	if not buyer:DoesHeroHasFreeSlot() and not itemsWithCharges[itemName] then
		buyer:ModifyGold(self:GetCost(), false, 0)
		UTIL_Remove(self)
		CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(buyer:GetPlayerID()), "display_custom_error", { message = "#dota_hud_error_cant_purchase_inventory_full" })
		return false
	end

	_G.itemsIsBuy[unique_key] = not _G.itemsIsBuy[unique_key]

	if _G.itemsIsBuy[unique_key] == true then
		if not itemsWithCharges[itemName] then
			UTIL_Remove(self)
			buyer:AddItemByName(itemName)
			return false
		else
			self:SetCooldownStackedItem(itemName, buyer)
		end
	end
end

function CDOTA_Item:HasPersonalCooldown()
	return itemsCooldownForPlayer[self:GetName()] and true
end

function MessageToPlayerItemCooldown(itemName, playerID)
	if _G.itemsCooldownForPlayer[itemName] then
		CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(playerID), "display_custom_error", { message = "#fast_buy_items" })
	else
		CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(playerID), "display_custom_error", { message = "#you_can_buy_only_one_item" })
	end
end

function CheckMaxItemCount(item, unique_key,playerID,checker)
	local itemName = item:GetAbilityName()
	if maxItemsForPlayer[itemName] then
		if not maxItemsForPlayersData[unique_key] then
			maxItemsForPlayersData[unique_key] = 1
		else
			if maxItemsForPlayersData[unique_key] >=  maxItemsForPlayer[itemName] then
				CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(playerID), "display_custom_error", { message = "you_cannot_buy_more_items_this_type" })
				return false
			elseif checker then
				maxItemsForPlayersData[unique_key] = maxItemsForPlayersData[unique_key]+1
			end
		end
	end
	return true
end

function CDOTA_BaseNPC:CheckPersonalCooldown(item)
	local buyerEntIndex = self:GetEntityIndex()
	local itemName = item:GetAbilityName()
	local unique_key = itemName .. "_" .. buyerEntIndex
	local playerID = self:GetPlayerID()
	local supporter_level = Supporters:GetLevel(playerID)

	if _G.lastTimeBuyItemWithCooldown[unique_key] == nil or (_G.itemsCooldownForPlayer[itemName] and (GameRules:GetGameTime() - _G.lastTimeBuyItemWithCooldown[unique_key]) >= _G.itemsCooldownForPlayer[itemName]) then
		if not itemsWithCharges[itemName] then
			_G.lastTimeBuyItemWithCooldown[unique_key] = GameRules:GetGameTime()
			local checkMaxCount = CheckMaxItemCount(item, unique_key, playerID, true)
			return (true and checkMaxCount)
		elseif not ItemIsFastBuying(itemName) and (not (supporter_level > 0)) then
			_G.lastTimeBuyItemWithCooldown[unique_key] = GameRules:GetGameTime()
			local checkMaxCount = CheckMaxItemCount(item, unique_key, playerID, true)
			return (true and checkMaxCount)
		end
	elseif _G.itemsCooldownForPlayer[itemName] then
		if itemsWithCharges[itemName] then
			if not ItemIsFastBuying(itemName) and (not (supporter_level > 0)) then
				local checkMaxCount = CheckMaxItemCount(item, unique_key, playerID, false)
				if checkMaxCount then
					MessageToPlayerItemCooldown(itemName, playerID)
				end
				return false
			end
		else
			local checkMaxCount = CheckMaxItemCount(item, unique_key, playerID, false)
			if checkMaxCount then
				MessageToPlayerItemCooldown(itemName, playerID)
			end
			return false
		end
	end
	return true
end

-------------------------------------------------------------------------
function CreateDummyInventoryForPlayer(playerId, unit)
	local player = PlayerResource:GetPlayer(playerId)
	if not player or player:IsNull() then return end

	if player.dummyInventory then
		player.dummyInventory:Kill(nil, nil)
	end

	local startPointSpawn = unit:GetAbsOrigin() + (RandomFloat(100, 100))

	local dInventory = CreateUnitByName("npc_dummy_inventory", startPointSpawn, true, unit, unit, PlayerResource:GetTeam(playerId))
	dInventory:SetControllableByPlayer(playerId, true)
	dInventory:AddNewModifier(dInventory, nil, "modifier_dummy_inventory_custom", {duration = -1})

	player.dummyInventory = dInventory
end
-------------------------------------------------------------------------
