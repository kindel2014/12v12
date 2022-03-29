require("common/game_perks/base_game_perk")

hp_regen = class(base_game_perk)

function hp_regen:DeclareFunctions() return { MODIFIER_PROPERTY_HEALTH_REGEN_CONSTANT } end
function hp_regen:GetTexture() return "perkIcons/hp_regen" end
function hp_regen:GetModifierConstantHealthRegen()
	return self:GetPerkValue(self.v[1], self.v[2], self.v[3])
end

hp_regen_t0 = class(hp_regen)
hp_regen_t1 = class(hp_regen)
hp_regen_t2 = class(hp_regen)
hp_regen_t3 = class(hp_regen)

function hp_regen_t0:OnCreated() self.v = {2, 1, 0.2} end
function hp_regen_t1:OnCreated() self.v = {4, 1, 0.4} end
function hp_regen_t2:OnCreated() self.v = {8, 1, 0.8} end
function hp_regen_t3:OnCreated() self.v = {16, 1, 1.6} end
