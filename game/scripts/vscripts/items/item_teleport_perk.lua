item_teleport_perk = item_teleport_perk or class({})
LinkLuaModifier("modifier_teleport_from_perk","items/item_teleport_perk", LUA_MODIFIER_MOTION_NONE)

function item_teleport_perk:OnSpellStart()
	if not IsServer() then return end
	
	local caster = self:GetCaster()
	if not caster then return end
	
	local player_id = caster:GetPlayerOwnerID()
	if not player_id then return end

	self.pos_for_tp = self:GetCursorPosition()
	self:SetChanneling(false)
	caster:AddNewModifier(caster, nil, "modifier_teleport_from_perk", {})
	caster:EmitSound("Portal.Loop_Appear")
end

function item_teleport_perk:OnChannelFinish(b_interrupted)
	local caster = self:GetCaster()
	if not b_interrupted then
		FindClearSpaceForUnit(caster, self.pos_for_tp, false)
		caster:EmitSound("Portal.Hero_Appear")
	end
	caster:StopSound("Portal.Loop_Appear")
	caster:RemoveModifierByName("modifier_teleport_from_perk")
end

modifier_teleport_from_perk = modifier_teleport_from_perk or class({})
function modifier_teleport_from_perk:RemoveOnDeath() return true end
function modifier_teleport_from_perk:IsHidden() return true end
function modifier_teleport_from_perk:GetEffectName()
	return "particles/items2_fx/teleport_start.vpcf"
end

item_teleport_perk_0 = class(item_teleport_perk)
item_teleport_perk_1 = class(item_teleport_perk)
item_teleport_perk_2 = class(item_teleport_perk)
