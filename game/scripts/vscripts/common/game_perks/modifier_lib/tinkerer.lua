require("common/game_perks/base_game_perk")

tinkerer = class(base_game_perk)

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

function tinkerer:GetTexture() return "perkIcons/tinkerer" end
function tinkerer:DeclareFunctions()
	return {
		MODIFIER_PROPERTY_OVERRIDE_ABILITY_SPECIAL,
		MODIFIER_PROPERTY_OVERRIDE_ABILITY_SPECIAL_VALUE
	}
end

function tinkerer:GetModifierOverrideAbilitySpecial(keys)
	if keys.ability and neutral_list and neutral_list[keys.ability:GetAbilityName()] then
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
tinkerer_t1 = class(tinkerer)
tinkerer_t2 = class(tinkerer)

function tinkerer_t0:OnCreated() self.v = 15 end
function tinkerer_t1:OnCreated() self.v = 30 end
function tinkerer_t2:OnCreated() self.v = 60 end
