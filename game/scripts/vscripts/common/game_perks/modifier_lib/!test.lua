-- This is the damage redirect ability
warden_bulwark = class({})

function warden_bulwark:GetIntrinsicModifierName()
	return "modifier_warden_bulwark"
end

modifier_warden_bulwark = class({})

function modifier_warden_bulwark:IsDebuff() return false end
function modifier_warden_bulwark:IsHidden() return true end
function modifier_warden_bulwark:IsPurgable() return false end
function modifier_warden_bulwark:GetAttributes() return MODIFIER_ATTRIBUTE_IGNORE_INVULNERABLE end

function modifier_warden_bulwark:IsAura() return true end
function modifier_warden_bulwark:GetAuraRadius() return self.radius or 0 end
function modifier_warden_bulwark:GetAuraSearchFlags() return DOTA_UNIT_TARGET_FLAG_NOT_ILLUSIONS end
function modifier_warden_bulwark:GetAuraSearchTeam() return DOTA_UNIT_TARGET_TEAM_FRIENDLY end
function modifier_warden_bulwark:GetAuraSearchType() return DOTA_UNIT_TARGET_HERO end
function modifier_warden_bulwark:GetModifierAura() return "modifier_warden_bulwark_buff" end

function modifier_warden_bulwark:OnCreated(keys)
	self:OnRefresh(keys)
end

function modifier_warden_bulwark:OnRefresh(keys)
	self.radius = self:GetAbility():GetSpecialValueFor("radius")
end

function modifier_warden_bulwark:GetAuraEntityReject(unit)
	if IsServer() then
		if unit:HasModifier("modifier_warden_bulwark") then
			return true
		else
			return false
		end
	end
end

modifier_warden_bulwark_buff = class({})

function modifier_warden_bulwark_buff:IsDebuff() return false end
function modifier_warden_bulwark_buff:IsHidden() return false end
function modifier_warden_bulwark_buff:IsPurgable() return false end

function modifier_warden_bulwark_buff:DeclareFunctions()
	local funcs = {
		MODIFIER_EVENT_ON_TAKEDAMAGE
	}
	return funcs
end

function modifier_warden_bulwark_buff:OnTakeDamage(keys)
	if IsServer() then
		if keys.unit == self:GetParent() then
			local caster = self:GetCaster()

			local transfer_pfx = ParticleManager:CreateParticle("particles/units/heroes/hero_centaur/centaur_return.vpcf", PATTACH_ABSORIGIN_FOLLOW, keys.unit)
			ParticleManager:SetParticleControlEnt(transfer_pfx, 0, caster, PATTACH_POINT_FOLLOW, "attach_hitloc", Vector(0, 0, 0), true)
			ParticleManager:SetParticleControlEnt(transfer_pfx, 1, keys.unit, PATTACH_POINT_FOLLOW, "attach_hitloc", Vector(0, 0, 0), true)
			ParticleManager:ReleaseParticleIndex(transfer_pfx)

			if not caster:HasModifier("modifier_warden_bulwark_buff_sound_delay") then
				EmitAnnouncerSoundForPlayer("Bulwark.Proc", caster:GetPlayerOwnerID())
				caster:AddNewModifier(caster, self:GetAbility(), "modifier_warden_bulwark_buff_sound_delay", {duration = 0.2})
			end
		end
	end
end

modifier_warden_bulwark_buff_sound_delay = class({})

function modifier_warden_bulwark_buff_sound_delay:IsDebuff() return false end
function modifier_warden_bulwark_buff_sound_delay:IsHidden() return true end
function modifier_warden_bulwark_buff_sound_delay:IsPurgable() return false end
function modifier_warden_bulwark_buff_sound_delay:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT + MODIFIER_ATTRIBUTE_IGNORE_INVULNERABLE end









-- this goes on the damage filter (victim and kvs need to exist)
if victim and victim:HasModifier("modifier_warden_bulwark_buff") then
	if attacker and attacker:GetTeam() ~= victim:GetTeam() then
		local caster = victim:FindModifierByName("modifier_warden_bulwark_buff"):GetCaster()
		if caster then
			local bulwark_ability = caster:FindAbilityByName("warden_bulwark")
			if bulwark_ability then
				local redirect_amount = 0.01 * bulwark_ability:GetSpecialValueFor("damage_redirect")

				ApplyDamage({victim = caster, attacker = attacker, damage = keys.damage * redirect_amount, damage_type = keys.damagetype_const, damage_flags = DOTA_DAMAGE_FLAG_NO_SPELL_AMPLIFICATION + DOTA_DAMAGE_FLAG_NON_LETHAL})

				keys.damage = keys.damage * (1 - redirect_amount)
			end
		end
	end
end






-- This is the damage delay ability
sentinel_shake_it_off = class({})

function sentinel_shake_it_off:GetIntrinsicModifierName()
	return "modifier_sentinel_shake_it_off"
end

modifier_sentinel_shake_it_off = class({})

function modifier_sentinel_shake_it_off:IsHidden() return true end
function modifier_sentinel_shake_it_off:IsDebuff() return false end
function modifier_sentinel_shake_it_off:IsPurgable() return false end
function modifier_sentinel_shake_it_off:GetAttributes() return MODIFIER_ATTRIBUTE_IGNORE_INVULNERABLE + MODIFIER_ATTRIBUTE_PERMANENT end

modifier_sentinel_shake_it_off_stack = class({})

function modifier_sentinel_shake_it_off_stack:IsHidden() return true end
function modifier_sentinel_shake_it_off_stack:IsDebuff() return false end
function modifier_sentinel_shake_it_off_stack:IsPurgable() return false end
function modifier_sentinel_shake_it_off_stack:GetAttributes() return MODIFIER_ATTRIBUTE_MULTIPLE end

function modifier_sentinel_shake_it_off_stack:OnCreated(keys)
	if IsServer() then
		self.damage_tick = 0.5 * (keys.damage or 0) / keys.duration

		if self.damage_tick > 0 then
			self:GetParent():AddNewModifier(self:GetParent(), self:GetAbility(), "modifier_sentinel_shake_it_off_stagger", {duration = keys.duration})
		else
			self:Destroy()
		end
	end
end

modifier_sentinel_shake_it_off_stagger = class({})

function modifier_sentinel_shake_it_off_stagger:IsHidden() return false end
function modifier_sentinel_shake_it_off_stagger:IsDebuff() return true end
function modifier_sentinel_shake_it_off_stagger:IsPurgable() return false end

function modifier_sentinel_shake_it_off_stagger:OnCreated(keys)
	if IsServer() then
		self:StartIntervalThink(0.5)
	end
end

function modifier_sentinel_shake_it_off_stagger:OnIntervalThink()
	if IsServer() then
		local parent = self:GetParent()
		local damage_stacks = parent:FindAllModifiersByName("modifier_sentinel_shake_it_off_stack")
		local damage_tick = 0

		for _, stack in pairs(damage_stacks) do
			damage_tick = damage_tick + (stack.damage_tick or 0)
		end

		ApplyDamage({victim = parent, attacker = parent, damage = damage_tick, damage_type = DAMAGE_TYPE_PURE, damage_flags = DOTA_DAMAGE_FLAG_BYPASSES_BLOCK + DOTA_DAMAGE_FLAG_HPLOSS + DOTA_DAMAGE_FLAG_NO_DAMAGE_MULTIPLIERS + DOTA_DAMAGE_FLAG_NON_LETHAL})
	end
end







-- this part goes on the damage filter (needs citim and kvs to exist)
if victim and victim:HasModifier("modifier_sentinel_shake_it_off") then
	if attacker and attacker ~= victim then
		local stagger_ability = victim:FindAbilityByName("sentinel_shake_it_off")
		if stagger_ability then
			local stagger_amount =  0.01 * stagger_ability:GetSpecialValueFor("stagger_amount")
			local stagger_duration = stagger_ability:GetSpecialValueFor("stagger_duration")
			victim:AddNewModifier(victim, stagger_ability, "modifier_sentinel_shake_it_off_stack", {damage = keys.damage * stagger_amount, duration = stagger_duration})

			keys.damage = keys.damage * (1 - stagger_amount)
		end
	end
end
