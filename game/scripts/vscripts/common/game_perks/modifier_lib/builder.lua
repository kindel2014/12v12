require("common/game_perks/base_game_perk")
LinkLuaModifier("modifier_builder_tower", 'common/game_perks/modifier_lib/builder', LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_builder_tower_hp_boost", 'common/game_perks/modifier_lib/builder', LUA_MODIFIER_MOTION_NONE)

builder = class(base_game_perk)

function builder:GetTexture() return "perkIcons/builder" end
function builder:OnCreated() self:StartIntervalThink(15) end

function builder:OnIntervalThink()
	if not IsServer() then return end
	
	local towers = Entities:FindAllByClassname('npc_dota_tower')
	local weakiest_tower
	local parent = self:GetParent()
	
	for _, tower in pairs(towers) do
		if parent:GetTeam() == tower:GetTeam() and ((not weakiest_tower) or weakiest_tower:GetHealth() > tower:GetHealth()) then
			weakiest_tower = tower
		end
	end
	
	if weakiest_tower then
		weakiest_tower:AddNewModifier(parent, nil, "modifier_builder_tower", { duration = 2, heal_per_sec = self.v })
	end
end

modifier_builder_tower = class(base_game_perk)
function modifier_builder_tower:OnCreated(params)
	self.heal_per_sec = params.heal_per_sec
	self:StartIntervalThink(1)

	local parent = self:GetParent()
	self.particle = ParticleManager:CreateParticle("particles/items5_fx/repair_kit.vpcf", PATTACH_ABSORIGIN_FOLLOW, parent)
	ParticleManager:SetParticleControl(self.particle, 0, parent:GetAbsOrigin())
	ParticleManager:SetParticleControl(self.particle, 1, parent:GetAbsOrigin())
	
	parent:EmitSound("DOTA_Item.RepairKit.Target")
end
function modifier_builder_tower:OnIntervalThink()
	if not IsServer() then return end
	local parent = self:GetParent()
	if parent:GetHealth() == parent:GetMaxHealth() then
		local hp_mod
		local hp_mod_name = "modifier_builder_tower_hp_boost"
		if parent:HasModifier(hp_mod_name) then
			hp_mod = parent:FindModifierByName(hp_mod_name)
		else
			hp_mod = parent:AddNewModifier(parent, nil, hp_mod_name, { duration = -1 })
		end
		hp_mod:SetStackCount(hp_mod:GetStackCount() + self.heal_per_sec)
		parent:CalculateGenericBonuses()
	else
		parent:Heal(self.heal_per_sec, nil)
	end
end
function modifier_builder_tower:OnDestroy()
	ParticleManager:DestroyParticle(self.particle, false)
	ParticleManager:ReleaseParticleIndex( self.particle )

	self:GetParent():StopSound("DOTA_Item.RepairKit.Target")
end
function modifier_builder_tower:GetAttributes() return MODIFIER_ATTRIBUTE_MULTIPLE end
function modifier_builder_tower:GetTexture() return "perkIcons/builder" end

modifier_builder_tower_hp_boost = class(base_game_perk)
function modifier_builder_tower_hp_boost:DeclareFunctions() return { MODIFIER_PROPERTY_EXTRA_HEALTH_BONUS } end
function modifier_builder_tower_hp_boost:GetTexture() return "perkIcons/builder" end
function modifier_builder_tower_hp_boost:GetModifierExtraHealthBonus()	return self:GetStackCount() end

builder_t0 = class(builder)
builder_t0.v = 15
builder_t1 = class(builder)
builder_t1.v = 30
builder_t2 = class(builder)
builder_t2.v = 60
builder_t3 = class(builder)
builder_t3.v = 120
