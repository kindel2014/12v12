require("common/game_perks/base_game_perk")

linken = class(base_game_perk)

function linken:DeclareFunctions() return { MODIFIER_PROPERTY_ABSORB_SPELL } end
function linken:GetTexture() return "perkIcons/linken" end

function linken:GetAbsorbSpell(params)
	local parent = self:GetParent()

	if params.ability:GetCaster():GetTeamNumber() == parent:GetTeamNumber() then
		return nil
	end

	if parent:FindModifierByName("linken_cooldown") then
		return nil
	end

	for i = DOTA_ITEM_SLOT_1, DOTA_ITEM_SLOT_6 do
		local item = parent:GetItemInSlot(i)
		if item and not item:IsNull() and item:GetAbilityName() == "item_sphere" then
			if item:IsCooldownReady() then return nil end
		end
	end

	if parent:FindModifierByName("modifier_special_bonus_spell_block") then return nil end

	parent:EmitSound("DOTA_Item.LinkensSphere.Activate")

	local pfx = ParticleManager:CreateParticle("particles/items_fx/immunity_sphere.vpcf", PATTACH_POINT_FOLLOW, parent)
	ParticleManager:SetParticleControlEnt(pfx, 0, parent, PATTACH_POINT_FOLLOW, "attach_hitloc", parent:GetAbsOrigin(), true)
	ParticleManager:ReleaseParticleIndex(pfx)

	parent:AddNewModifier(parent, self:GetAbility(), "linken_cooldown", {duration = self.v})

	return 1
end


linken_t0 = class(linken)
linken_t0.v = 90
linken_t1 = class(linken)
linken_t1.v = 60
linken_t2 = class(linken)
linken_t2.v = 30
linken_t3 = class(linken)
linken_t3.v = 15

LinkLuaModifier("linken_cooldown", "common/game_perks/modifier_lib/linken", LUA_MODIFIER_MOTION_NONE)
linken_cooldown = class({})

function linken_cooldown:IsPurgable() return false end
function linken_cooldown:GetTexture() return "perkIcons/linken" end
function linken_cooldown:RemoveOnDeath() return false end
