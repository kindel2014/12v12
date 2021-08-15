"use strict";

// item_name: item_id
const items = { 
	"item_ward_sentry": 43, 
	"item_dust": 40
}

let item_costs

const SHOP = FindDotaHudElement("shop")
const QUICK_BUY_ROW = FindDotaHudElement("lower_hud").FindChildTraverse("quickbuy").FindChildTraverse("Row1")
const CONTEXT = $.GetContextPanel()

function CreateItemButton(name, id) {
	const panel = $.CreatePanelWithProperties("DOTAShopItem", CONTEXT, id, { itemname: name })
	
	panel.style.width = "38px"
	panel.style.height = "28px"
	panel.style.margin = "1px"

	// I cant find way to trigger DOTAShopPanal update, so for now this just disabled
	panel.RemoveClass("ShowStockAmount")
	panel.RemoveClass("OutOfStock")

	panel.SetPanelEvent("oncontextmenu", () => {
		Game.PrepareUnitOrders({
			OrderType: dotaunitorder_t.DOTA_UNIT_ORDER_PURCHASE_ITEM,
			UnitIndex: Players.GetLocalPlayerPortraitUnit(),
			AbilityIndex: id,
			Queue: false,
			ShowEffects: true
		})
	})

	const update = function() {
		if (!panel.IsValid()) return
		$.Schedule(0., update)
			
		const gold = Players.GetGold(Game.GetLocalPlayerID())
		panel.SetHasClass("CanPurchase", gold >= item_costs[name])
	}

	update()
}

GameEvents.SendCustomGameEventToServer("shortcut_shop_request_item_costs", items)
GameEvents.Subscribe("shortcut_shop_item_costs", function(data) {
	item_costs = data

	CONTEXT.RemoveAndDeleteChildren()
	Object.entries(items).forEach( entry => {
		const [name, id] = entry;
		CreateItemButton(name, id) 
	})
}) 

$.RegisterEventHandler("PanelStyleChanged", QUICK_BUY_ROW, function() {
	CONTEXT.SetHasClass("QuickBuyTwoRows", !QUICK_BUY_ROW.BHasClass("Empty"))
})

$.RegisterEventHandler("PanelStyleChanged", SHOP, function() {
	CONTEXT.SetHasClass("Hidden", SHOP.BHasClass("ShopOpen"))
})


