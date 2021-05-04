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

	self.tp_end = ParticleManager:CreateParticle("particles/items2_fx/teleport_end.vpcf", PATTACH_CUSTOMORIGIN, nil)
	ParticleManager:SetParticleControl( self.tp_end, 0, self.pos_for_tp)
	ParticleManager:SetParticleControl( self.tp_end, 1, self.pos_for_tp)
	ParticleManager:SetParticleControl( self.tp_end, 2, Vector(200, 100, 20))
	ParticleManager:SetParticleControlEnt( self.tp_end, 3, caster, PATTACH_ABSORIGIN, "attach_origin", Vector(0,0,0), false)
	ParticleManager:SetParticleControl( self.tp_end, 4, Vector(1.0, 0, 0) )
	ParticleManager:SetParticleControl( self.tp_end, 5, self.pos_for_tp + Vector(0,0,150) )
end

function item_teleport_perk:OnChannelFinish(b_interrupted)
	local caster = self:GetCaster()
	if not b_interrupted then
		FindClearSpaceForUnit(caster, self.pos_for_tp, false)
		caster:EmitSound("Portal.Hero_Appear")
	end
	caster:StopSound("Portal.Loop_Appear")
	caster:RemoveModifierByName("modifier_teleport_from_perk")

	ParticleManager:DestroyParticle(self.tp_end, b_interrupted)
	ParticleManager:ReleaseParticleIndex(self.tp_end)
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
