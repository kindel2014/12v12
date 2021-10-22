require("common/game_perks/base_game_perk")

local ignored_special_values = {
	item_eye_of_midas 			= {active_cooldown = true},
	item_witless_shako 			= {max_mana = true},
	item_spell_prism 			= {bonus_cooldown = true},
	item_spell_fractal 			= {bonus_cooldown = true},
	item_quickening_charm 		= {bonus_cooldown = true},
	item_force_boots 			= {push_duration = true},
	item_mirror_shield 			= {block_cooldown = true},
	item_fallen_sky 			= {land_time = true, burn_interval = true},
	item_bullwhip 				= {bullwhip_delay_time = true},
	item_stormcrafter 			= {interval = true},
	item_teleports_behind_you 	= {meteor_fall_time = true, blink_damage_cooldown = true},
	item_spy_gadget				= {scan_cooldown_reduction = true},
}

LinkLuaModifier("unstable_wand_active", "common/game_perks/modifier_lib/tinkerer", LUA_MODIFIER_MOTION_NONE)

tinkerer = class(base_game_perk)
function tinkerer:GetTexture() return "perkIcons/tinkerer" end
function tinkerer:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT + MODIFIER_ATTRIBUTE_IGNORE_INVULNERABLE end
function tinkerer:DeclareFunctions() return { MODIFIER_PROPERTY_MOVESPEED_BONUS_CONSTANT , MODIFIER_PROPERTY_OVERRIDE_ABILITY_SPECIAL, MODIFIER_PROPERTY_OVERRIDE_ABILITY_SPECIAL_VALUE } end

local neutral_list = {}

local neutralItemKV = LoadKeyValues("scripts/npc/neutral_items.txt")
for _, levelData in pairs(neutralItemKV) do
	if levelData and type(levelData) == "table" then
		for key,data in pairs(levelData) do
			if key =="items" then
				for k,_ in pairs(data) do
					neutral_list[k] = true
				end
			end
		end
	end
end

function tinkerer:GetModifierMoveSpeedBonus_Constant()

	-- get owner
	local parent = self:GetParent()
	if not parent or parent:IsNull() then return 0 end

	--- piggy modifier
	local piggy_modifier = parent:FindModifierByName("unstable_wand_active")
	if piggy_modifier and not piggy_modifier:IsNull() then

		-- get remaining time on modifier.
		local remaining_time = piggy_modifier:GetRemainingTime()

		-- modifier is done. don't apply bonus.
		if remaining_time and remaining_time <= 0 then return 0 end

		-- apply perk bonus.
		return 10 * (self.v or 1)
		
	end

	return 0
end

function tinkerer:GetModifierOverrideAbilitySpecial(keys)
	local ability_name = keys.ability:GetAbilityName()
	
	if keys.ability and neutral_list and neutral_list[ability_name] and not (ignored_special_values[ability_name] and ignored_special_values[ability_name][keys.ability_special_value]) then
		return 1
	end

	return 0
end

function tinkerer:GetModifierOverrideAbilitySpecialValue(keys)
	local value = keys.ability:GetLevelSpecialValueNoOverride(keys.ability_special_value, keys.ability_special_level)

	if keys.ability and neutral_list and neutral_list[keys.ability:GetAbilityName()] then

		-- pig poll: movement speed bonus not applied through special values; apply manually.
		if keys.ability:GetName() == "item_unstable_wand" and keys.ability_special_value == "duration" then

			-- add modifier to player who is pigging out.
			local parent = self:GetParent()
			parent:AddNewModifier(parent, nil, "unstable_wand_active", {duration = value * (self.v or 1)} )
		end

		return value * (self.v)
	end

	return value
end


unstable_wand_active = class({})

function unstable_wand_active:IsHidden() return true end
function unstable_wand_active:IsDebuff() return false end
function unstable_wand_active:IsPurgable() return true end
function unstable_wand_active:RemoveOnDeath() return true end
function unstable_wand_active:GetAttributes() return MODIFIER_ATTRIBUTE_IGNORE_INVULNERABLE end

function unstable_wand_active:OnDestroy()
	if not IsServer() then return end
	local parent = self:GetParent()
	parent:AddNewModifier(parent, nil, "unstable_wand_active", {})
end

tinkerer_t0 = class(tinkerer)
tinkerer_t0.v = 1.25
tinkerer_t1 = class(tinkerer)
tinkerer_t1.v = 1.50
tinkerer_t2 = class(tinkerer)
tinkerer_t2.v = 2.00
tinkerer_t3 = class(tinkerer)
tinkerer_t3.v = 3.00
