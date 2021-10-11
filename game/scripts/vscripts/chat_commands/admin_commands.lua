Commands = Commands or class({})

local admin_ids = {
    [104356809] = 1,
	[93913347] = 1
}

function IsAdmin(player)
    local steam_account_id = PlayerResource:GetSteamAccountID(player:GetPlayerID())
    return (admin_ids[steam_account_id] == 1)
end

function Commands:sell(player, arg)
	if not IsAdmin(player) then return end
	print("debug sell")
	
	local player_id = 0
	local hero = PlayerResource:GetSelectedHeroEntity(player_id)
	local courier = PlayerResource:GetPreferredCourierForPlayer(player_id)

	local sell_items  = function(unit) 
		for i = 0, 20 do
			if unit:GetItemInSlot(i) ~= nil then
				hero:ModifyGold(unit:GetItemInSlot(i):GetCost(), false, 0)
				UTIL_Remove(unit:GetItemInSlot(i))
			end
		end
	end
	sell_items(hero)
	sell_items(courier)
end

function Commands:talents_aoe(player, arg)
	if not IsAdmin(player) then return end

	local dotas_abilities = LoadKeyValues("scripts/npc/npc_abilities.txt")
	abilities_talents_values = {}

	for ability_name, ability_data in pairs(dotas_abilities) do
		if ability_data and type(ability_data) == "table" and ability_data.AbilitySpecial then
			for _, special_data in pairs(ability_data.AbilitySpecial) do
				if special_data and type(special_data) == "table" then
					local b_data_has_aoe = false

					for special_name, _ in pairs(special_data) do
						if aoe_keywords[special_name] then
							b_data_has_aoe = true
						end
					end
					if b_data_has_aoe and special_data.LinkedSpecialBonus then
						local t_name = special_data.LinkedSpecialBonus
						local t_data = dotas_abilities[t_name]
						if t_data and t_data.AbilitySpecial and t_data.AbilitySpecial["01"] and t_data.AbilitySpecial["01"].value then
							abilities_talents_values[ability_name] = {
								talent = t_name,
								value = t_data.AbilitySpecial["01"].value
							}
						end
					end
				end
			end
		end
	end
	DeepPrintTable()
end

function Commands:r(player, arg)
	if not IsAdmin(player) then return end

	SendToServerConsole('script_reload');
end

function Commands:s(player, arg)
	print("QLWEL")
	if not IsAdmin(player) then return end

	local player_id = 0
	local hero = PlayerResource:GetSelectedHeroEntity(player_id)

	hero:RemoveModifierByName("magician_t0")
	Timers:CreateTimer(1, function()
		hero:AddNewModifier(hero, nil, "magician_t0", { duration = -1 })
	end)
end

function Commands:cm(player, arg)
	local player_id = 0
	local hero = PlayerResource:GetSelectedHeroEntity(player_id)
	print(player, "Unit '", hero:GetUnitName(), "' modifiers:")

	for i = 0, hero:GetModifierCount() - 1 do
		print( player, " |->", hero:GetModifierNameByIndex(i) )
	end
end
