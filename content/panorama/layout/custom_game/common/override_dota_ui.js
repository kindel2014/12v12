function OverrideDotaNeutralItemsShop() {
	var shop_grid_1 = $.GetContextPanel().GetParent().GetParent().GetParent().FindChildTraverse("GridNeutralsCategory");
	if (shop_grid_1) {
		shop_grid_1.style.overflow = "squish scroll";
	}
}

const SHOP = FindDotaHudElement("GridMainShopContents");

function RemoveSecretShopOverlay() {
	SHOP.FindChildrenWithClassTraverse("MainShopItem").forEach((item) => {
		item.FindChildTraverse("AvailableAtOtherShopOverlay").style.backgroundColor = "transparent";
		item.FindChildTraverse("AvailableAtOtherShopNeedGoldOverlay").style.backgroundColor = "transparent";
	});
	$.Schedule(0.5, RemoveSecretShopOverlay);
}

SubscribeToNetTableKey("game_state", "patreon_bonuses", function (patreon_bonuses) {
	let local_stats = patreon_bonuses[Game.GetLocalPlayerID()];
	let level = 0;

	if (local_stats && local_stats.level) {
		level = local_stats.level;
	}

	if (level > 0) RemoveSecretShopOverlay();
});

(function () {
	OverrideDotaNeutralItemsShop();
})();
