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

	for i = 0, 20 do
		if hero:GetItemInSlot(i) ~= nil then
			hero:SellItem(hero:GetItemInSlot(i))
		end
	end
end
