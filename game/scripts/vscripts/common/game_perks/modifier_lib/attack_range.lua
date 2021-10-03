require("common/game_perks/base_game_perk")

attack_range = class(base_game_perk)

function attack_range:DeclareFunctions() return { MODIFIER_PROPERTY_ATTACK_RANGE_BONUS } end

function attack_range:GetTexture() return "perkIcons/attack_range" end

function attack_range:GetModifierAttackRangeBonus()
	if self:GetParent():IsRangedAttacker() then
		return self.v[2]
	else
		return self.v[1]
	end
end

attack_range_t0 = class(attack_range)
attack_range_t1 = class(attack_range)
attack_range_t2 = class(attack_range)
attack_range_t3 = class(attack_range)

function attack_range_t0:OnCreated() self.v = {40, 50} end
function attack_range_t1:OnCreated() self.v = {80, 100} end
function attack_range_t2:OnCreated() self.v = {160, 200} end
function attack_range_t3:OnCreated() self.v = {320, 400} end
