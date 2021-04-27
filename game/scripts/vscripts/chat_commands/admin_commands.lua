Commands = Commands or class({})

local admin_ids = {
    [104356809] = 1, -- Sheodar
	[93913347] = 1, -- Darklord
}

function IsAdmin(player)
    local steam_account_id = PlayerResource:GetSteamAccountID(player:GetPlayerID())
    return (admin_ids[steam_account_id] == 1)
end

function CDOTA_BaseNPC:GetAbilityByName(ability_name)
	local result
	for i = 0, 30 do
		local ability = self:GetAbilityByIndex(i)
		if ability and ability:GetAbilityName() == ability_name then
			result = ability
		end
	end
	return result
end

function Commands:m(player, arg)
    if not IsAdmin(player) then return end
	local hero = PlayerResource:GetSelectedHeroEntity(0)
	local pudge = PlayerResource:GetSelectedHeroEntity(1)
	local hook = pudge:GetAbilityByIndex(0)
	
	local dummmy_ability = hero:GetAbilityByName("delayed_damage_perk")
	if dummmy_ability then
		print(dummmy_ability)
	end

	ApplyDamage({
		victim = hero,
		attacker = pudge,
		damage = 100,
		damage_type = DAMAGE_TYPE_PURE,
		damage_flags = DOTA_DAMAGE_FLAG_REFLECTION,
		ability = dummmy_ability
	})
end


