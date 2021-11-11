function OverrideDotaNeutralItemsShop() {
	var shop_grid_1 = $.GetContextPanel().GetParent().GetParent().GetParent().FindChildTraverse("GridNeutralsCategory");
	if (shop_grid_1) {
		shop_grid_1.style.overflow = "squish scroll";
	}
}

const SHOP = FindDotaHudElement("GridMainShopContents");
const LOCAL_PLAYER_ID = Game.GetLocalPlayerID();

let timer_for_secret_shop;
let count = 0;
function RemoveSecretShopOverlay() {
	SHOP.FindChildrenWithClassTraverse("MainShopItem").forEach((item) => {
		item.FindChildTraverse("AvailableAtOtherShopOverlay").style.backgroundColor = "transparent";
		item.FindChildTraverse("AvailableAtOtherShopNeedGoldOverlay").style.backgroundColor = "transparent";
	});
	timer_for_secret_shop = $.Schedule(1, RemoveSecretShopOverlay);
}

SubscribeToNetTableKey("game_state", "patreon_bonuses", function (patreon_bonuses) {
	CheckSuppLevel(patreon_bonuses);
});

function CheckSuppLevel(patreon_bonuses) {
	if (!LOCAL_PLAYER_ID || LOCAL_PLAYER_ID < 0) return;

	let local_stats = patreon_bonuses[LOCAL_PLAYER_ID];

	let level = 0;

	if (local_stats && local_stats.level) {
		level = local_stats.level;
	}

	if (timer_for_secret_shop) {
		timer_for_secret_shop = $.CancelScheduled(timer_for_secret_shop);
	}

	if (level > 0) RemoveSecretShopOverlay();
}

function OverrideSpectatorsUI() {
	FindDotaHudElement("SpectatorGoldDisplay").style.marginLeft = "84px";
	FindDotaHudElement("RadiantDiscreteDisplay").style.marginLeft = "10px";
	FindDotaHudElement("DireDiscreteDisplay").style.marginRight = "10px";
}

(function () {
	OverrideDotaNeutralItemsShop();
	CheckSuppLevel(CustomNetTables.GetTableValue("game_state", "patreon_bonuses"));

	if (Players.IsSpectator(LOCAL_PLAYER_ID)) OverrideSpectatorsUI();
})();
