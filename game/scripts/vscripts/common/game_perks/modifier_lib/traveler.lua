require("common/game_perks/base_game_perk")

traveler = class(base_game_perk)

function traveler:DeclareFunctions() return { MODIFIER_EVENT_ON_TELEPORTING } end

function traveler:OnTeleporting(keys)
	if not IsServer() then return end
	local parent = self:GetParent()
	local tp_scroll = parent:GetItemInSlot(DOTA_ITEM_TP_SCROLL)
	if not tp_scroll then return end
	Timers:CreateTimer(0, function()
		local cd_remaining = tp_scroll:GetCooldownTimeRemaining()
		tp_scroll:EndCooldown()
		tp_scroll:StartCooldown(cd_remaining * self.v)
	end)
end

function traveler:GetTexture() return "perkIcons/traveler" end

traveler_t0 = class(traveler)
traveler_t1 = class(traveler)
traveler_t2 = class(traveler)

function traveler_t0:OnCreated() self.v = 0.1 end
function traveler_t1:OnCreated() self.v = 0.70 end
function traveler_t2:OnCreated() self.v = 0.50 end
