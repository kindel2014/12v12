_G.secretShopItemList = {
	item_ring_of_health = true,
	item_void_stone = true,
	item_energy_booster = true,
	item_vitality_booster = true,
	item_point_booster = true,
	item_platemail = true,
	item_talisman_of_evasion = true,
	item_hyperstone = true,
	item_ultimate_orb = true,
	item_demon_edge = true,
	item_mystic_staff = true,
	item_reaver = true,
	item_eagle = true,
	item_relic = true,
}

_G.secretShopLocations = {
	["632"] = Vector(4860, -1228, 192), -- Dire Secret Shop
	["475"] = Vector(-4894, 1745, 192), -- Radiant Secret Shop
}

function IsSecretShopItem(itemID)
	return secretShopItemList[itemID]
end

function IsNearSecretShop(unit)
	for radius, shop_location in pairs(secretShopLocations) do
		if (unit:GetAbsOrigin() - shop_location):Length2D() <= tonumber(radius) then
			return true
		end
	end
	return false
end
