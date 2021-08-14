creep_secret_shop = class({})

function creep_secret_shop:IsHidden() return true end
function creep_secret_shop:RemoveOnDeath() return false end
function creep_secret_shop:IsPurgeException() return false end
function creep_secret_shop:RemoveOnDeath() return false end
function creep_secret_shop:DeclareFunctions() return { MODIFIER_EVENT_ON_ORDER } end

local secret_shop_pos = {
	[DOTA_TEAM_BADGUYS] = Vector(4860, -1228, 129),
	[DOTA_TEAM_GOODGUYS] = Vector(-4894, 1745, 129)
}
local home_shop_pos = {
	[DOTA_TEAM_BADGUYS] = Vector(6980, 6334, 390),
	[DOTA_TEAM_GOODGUYS] = Vector(-7045, -6480, 384)
}

function creep_secret_shop:OnCreated()
	if not IsServer() then return end
	
	local parent = self:GetParent()
	if not parent then return end

	local team = parent:GetTeam()
	if not team or not secret_shop_pos[team] or not home_shop_pos[team] then return end

	self.is_secret_shop = false
	self.parent = parent
	self.team = team
	self.home_pos = home_shop_pos[team] + RandomVector(RandomFloat(100, 100))
	self.secret_pos = secret_shop_pos[team] + RandomVector(RandomFloat(50, 50))

	self.last_pos = self.parent:GetAbsOrigin()
	
	self:StartIntervalThink(30)
end

function creep_secret_shop:OnIntervalThink()
	if not IsServer() then return end
	if not self.parent:IsAlive() then return end
	
	local current_pos = self.parent:GetAbsOrigin()
	
	if current_pos == self.secret_pos then return end
	
	if self.last_pos == current_pos then
		self.is_secret_shop = true
		self.parent:AddNoDraw()
		self:MoveToPos(self.secret_pos)
	else
		self.last_pos = current_pos
	end
end

function creep_secret_shop:OnOrder(data)
	if not IsServer() then return end
	if data.unit and data.unit ~= self.parent then return end
	if data.order_type and data.order_type == DOTA_UNIT_ORDER_PURCHASE_ITEM then return end
	
	local current_pos = self.parent:GetAbsOrigin()

	if self.is_secret_shop then
		self:MoveToPos(self.home_pos)
		self.parent:RemoveNoDraw()
	end
	
	self.last_pos = current_pos
	self.is_secret_shop = false
	
	self:StartIntervalThink(30)
end

function creep_secret_shop:MoveToPos(pos)
	self.parent:SetAbsOrigin(pos)
	self.last_pos = pos
end

function creep_secret_shop:CheckState()
	local state = {}
	if self.is_secret_shop then
		state = {
			[MODIFIER_STATE_NOT_ON_MINIMAP] = true,
			[MODIFIER_STATE_ATTACK_IMMUNE] = true,
			[MODIFIER_STATE_MAGIC_IMMUNE] = true,
			[MODIFIER_STATE_NO_HEALTH_BAR] = true,
			[MODIFIER_STATE_INVULNERABLE] = true,
			[MODIFIER_STATE_NO_UNIT_COLLISION] = true,
			[MODIFIER_STATE_DISARMED] = true,
			[MODIFIER_STATE_INVISIBLE] = true,
			[MODIFIER_STATE_BLIND] = true,
		}
	end
	return state
end
