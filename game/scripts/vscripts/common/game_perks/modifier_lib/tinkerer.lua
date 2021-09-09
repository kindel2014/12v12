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
}

tinkerer = class(base_game_perk)
function tinkerer:GetTexture() return "perkIcons/tinkerer" end
function tinkerer:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT + MODIFIER_ATTRIBUTE_IGNORE_INVULNERABLE end
function tinkerer:DeclareFunctions() return { MODIFIER_PROPERTY_OVERRIDE_ABILITY_SPECIAL, MODIFIER_PROPERTY_OVERRIDE_ABILITY_SPECIAL_VALUE } end

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
		return value * (self.v or 1)
	end

	return value
end


tinkerer_t0 = class(tinkerer)
tinkerer_t0.v = 1.15
tinkerer_t1 = class(tinkerer)
tinkerer_t1.v = 1.30
tinkerer_t2 = class(tinkerer)
tinkerer_t2.v = 1.60
tinkerer_t3 = class(tinkerer)
tinkerer_t3.v = 2.20
