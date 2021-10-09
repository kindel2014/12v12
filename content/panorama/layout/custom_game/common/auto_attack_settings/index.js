function FetchPlayerAutoAttackSettings() {
	//Next lines opens settings, get current auto attack mode and closes settings popup
	const popupManager = FindDotaHudElement("PopupManager");

	$.DispatchEvent("DOTAShowSettingsPopup");

	const options = popupManager.FindChildTraverse("OptionsTabContent");

	$.DispatchEvent("DOTASetActiveTab", options, 1);

	const autoAttack = options.FindChildTraverse("AutoAttackOptions");
	const mode = autoAttack
		.GetChild(1)
		.Children()
		.findIndex((panel) => panel.checked);

	// Hide last created settings popup
	for (const panel of popupManager.Children()) {
		if (panel.paneltype == "PopupSettings") {
			panel.visible = false;
			break;
		}
	}

	// Close settings popup
	// Somehow $.DispatchEvent("UIPopupButtonClicked", options) doesn't work
	$.CreatePanelWithProperties("Panel", options, "", {
		onload: "UIPopupButtonClicked()",
	});

	$.Msg(`Auto attack mode: ${mode}`);

	// Send data to lua side
	// We need toggle auto attack mode to -1 to update setting properly
	GameEvents.SendEventClientSide("auto_attack_setting", { value: -1 });

	$.Schedule(1, () => {
		GameEvents.SendEventClientSide("auto_attack_setting", { value: mode });
	});
}

function OnGameStateChanged() {
	if (Game.GameStateIs(DOTA_GameState.DOTA_GAMERULES_STATE_GAME_IN_PROGRESS)) {
		FetchPlayerAutoAttackSettings();
	}
}

GameEvents.Subscribe("game_rules_state_change", OnGameStateChanged);
OnGameStateChanged();
