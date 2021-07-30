const SYNCED_CHAT_ROOT = $.GetContextPanel();
const MESSAGES_CONTAINER = $("#SC_MessagesContainer");
const TEXT_ENTRY = $("#SC_TextEntry");
const SYMBOLS_COUNTER = $("#SC_SymbolsCounter");
const SUBMIT_BUTTON = $("#SC_Submit");
const ANON_HUD_CHECK = $("#AnonMessageCheck");
let OPENED_STATE = false;
let NOT_SUPPORTER = true;
let MESSAGES = {};
let account_id;
let more_mess_button;
let sc_top_button;

const DATE_MULTIPLIERS = {
	DAY: 8.64e7,
	HOUR: 3.6e6,
	MIN: 60000,
	SEC: 1000,
};

const MAX_SYMBOLS = 100;
const LOCAL_PLAYER_INFO = Game.GetLocalPlayerInfo();

function TEXT_LENGTH() {
	return TEXT_ENTRY.text.length;
}

function UpdateChatMessageText() {
	let current_length = TEXT_LENGTH();
	SYMBOLS_COUNTER.SetHasClass("Limit", current_length == MAX_SYMBOLS);
	SYMBOLS_COUNTER.SetDialogVariable("curr", current_length);
}
function OpenShop() {
	GameEvents.SendEventClientSide("battlepass_inventory:open_specific_collection", {
		category: "Treasures",
		boostGlow: true,
	});
}
function SendChatMessage() {
	if (SUBMIT_BUTTON.BHasClass("COOLDOWN")) return;
	if (TEXT_ENTRY.text == "") return;

	if (NOT_SUPPORTER) {
		OpenShop();
		return;
	}

	GameEvents.SendCustomGameEventToServer("synced_chat:send", {
		steamId: LOCAL_PLAYER_INFO.player_steamid,
		steamName: LOCAL_PLAYER_INFO.player_name,
		text: TEXT_ENTRY.text,
		anon: ANON_HUD_CHECK.IsSelected(),
	});

	SUBMIT_BUTTON.SetHasClass("COOLDOWN", true);
	$.Schedule(10, () => {
		SUBMIT_BUTTON.SetHasClass("COOLDOWN", false);
	});
}

function AddOlderMessages(data) {
	Object.values(data)
		.reverse()
		.forEach((val) => {
			AddMessage(val, true);
		});
}

function ScrollMessages() {
	const scroll_pos = MESSAGES_CONTAINER.scrolloffset_y;
	const content_height = MESSAGES_CONTAINER.contentheight - MESSAGES_CONTAINER.desiredlayoutheight;
	if (scroll_pos + content_height < 50) {
		$.Schedule(0.2, function () {
			MESSAGES_CONTAINER.ScrollToBottom();
		});
	}
}

function ProcessPollResult(data) {
	if (data.account_id) account_id = data.account_id;

	let check_ping = false;
	if (data.ping) check_ping = true;

	Object.values(data.msg).forEach((val) => {
		AddMessage(val, false, check_ping);
	});
	ScrollMessages();
	SYNCED_CHAT_ROOT.SetHasClass("Loaded", true);
}

function ProcessSentMessage(data) {
	AddMessage(data);
	TEXT_ENTRY.text = "";
	ScrollMessages();
}

function AddMessage(msg_data, is_old, check_ping) {
	if (MESSAGES[msg_data.id]) return;

	let text_content = msg_data.Content;
	text_content = text_content.replace(/<:.*:\d*>/g, (token) => {
		token = token.replace(/^</, "").replace(/\d*>/, "");
		return token;
	});
	if (text_content == "") return;

	const message_panel = $.CreatePanel("Panel", MESSAGES_CONTAINER, "SC_Msg_" + msg_data.id);
	message_panel.BLoadLayoutSnippet("SC_MessageLine");

	text_content = text_content.replace(/sid:\d*/g, (token) => {
		token = token = token.replace("sid:", "");
		let result = token;
		if (account_id && account_id == token) {
			result = `<font color='#fcb13b'>@${LOCAL_PLAYER_INFO.player_name}</font>`;
			message_panel.AddClass("Ping");
			if (check_ping && sc_top_button && !SYNCED_CHAT_ROOT.BHasClass("show")) {
				sc_top_button.AddClass("Ping");
			}
		}
		return result;
	});

	const date_hud = message_panel.FindChildTraverse("SC_Msg_Date");

	const added_at_date = new Date(msg_data.AddedAt);
	let today = new Date();
	today.setMinutes(today.getMinutes() + today.getTimezoneOffset());
	let diff = Math.max(1000, today - added_at_date);

	if (diff >= DATE_MULTIPLIERS.DAY) {
		const days = Math.floor(diff / DATE_MULTIPLIERS.DAY);
		date_hud.text = days > 1 ? LocalizeWithValues("sc_days_ago", { v: days }) : $.Localize("sc_yesterday");
	} else if (diff >= DATE_MULTIPLIERS.HOUR) {
		date_hud.text = LocalizeWithValues("sc_hours_ago", { v: Math.floor(diff / DATE_MULTIPLIERS.HOUR) });
	} else if (diff >= DATE_MULTIPLIERS.MIN) {
		date_hud.text = LocalizeWithValues("sc_mins_ago", { v: Math.floor(diff / DATE_MULTIPLIERS.MIN) });
	} else {
		date_hud.text = LocalizeWithValues("sc_sec_ago", { v: Math.floor(diff / DATE_MULTIPLIERS.SEC) });
	}

	const avatar = message_panel.FindChildTraverse("SC_Msg_Avatar");
	const steam_nickname = message_panel.FindChildTraverse("SC_Msg_Name");

	if (msg_data.SteamId != "-1") {
		if (msg_data.Anonymous == 0) {
			avatar.steamid = msg_data.SteamId;
			steam_nickname.steamid = msg_data.SteamId;
		} else {
			message_panel.AddClass("Anon");
			avatar.GetChild(1).SetImage("file://{resources}/images/custom_game/no_user.png");
		}
	} else {
		message_panel.AddClass("Dev");
		message_panel.FindChildTraverse("SC_Dev_Name").text = msg_data.SteamName;
	}

	message_panel.FindChildTraverse("SC_Msg_Text").text = text_content;
	MESSAGES[msg_data.id] = message_panel;

	if (is_old) {
		MESSAGES_CONTAINER.MoveChildAfter(message_panel, more_mess_button);
		message_panel.ScrollParentToMakePanelFit(1, true);
	}
}

function CloseSyncedChat() {
	SYNCED_CHAT_ROOT.SetHasClass("show", false);
	OPENED_STATE = false;
	GameEvents.SendCustomGameEventToServer("synced_chat:window_state", {
		state: OPENED_STATE,
	});
}

SubscribeToNetTableKey("game_state", "patreon_bonuses", function (patreon_bonuses) {
	let local_stats = patreon_bonuses[Game.GetLocalPlayerID()];
	let level = 0;

	if (local_stats && local_stats.level) {
		level = local_stats.level;
	}

	NOT_SUPPORTER = level == 0;
	SYNCED_CHAT_ROOT.SetHasClass("Locked", NOT_SUPPORTER);
});

function AddButtonToChat(class_name, text_key, callback) {
	const button = $.CreatePanel("Button", MESSAGES_CONTAINER, "");
	button.BLoadLayoutSnippet("MoreMessage");
	button.AddClass(class_name);
	button.GetChild(1).text = $.Localize(text_key);
	button.SetPanelEvent("onactivate", callback);

	return button;
}

(function () {
	MESSAGES_CONTAINER.RemoveAndDeleteChildren();

	AddButtonToChat("SuppChat", "loadscreen_become_supp", OpenShop);

	more_mess_button = AddButtonToChat("MoreMessage", "load_more_messages", () => {
		if (NOT_SUPPORTER) return;
		if (more_mess_button.BHasClass("Cooldown")) return;
		GameEvents.SendCustomGameEventToServer("synced_chat:get_older_messages", {});
		more_mess_button.AddClass("Cooldown");
		$.Schedule(10, () => {
			more_mess_button.RemoveClass("Cooldown");
		});
	});

	SYMBOLS_COUNTER.SetDialogVariable("max", MAX_SYMBOLS);
	SYMBOLS_COUNTER.SetDialogVariable("curr", 0);

	GameEvents.Subscribe("synced_chat:poll_result", ProcessPollResult);
	GameEvents.Subscribe("synced_chat:add_older_messages", AddOlderMessages);
	GameEvents.Subscribe("synced_chat:message_sent", ProcessSentMessage);

	GameEvents.SendCustomGameEventToServer("synced_chat:request_inital", {});

	sc_top_button = _AddMenuButton("OpenSyncedChat");
	CreateButtonInTopMenu(
		sc_top_button,
		() => {
			SYNCED_CHAT_ROOT.ToggleClass("show");
			OPENED_STATE = !OPENED_STATE;
			GameEvents.SendCustomGameEventToServer("synced_chat:window_state", {
				state: OPENED_STATE,
			});

			if (SYNCED_CHAT_ROOT.first_open == undefined) {
				SYNCED_CHAT_ROOT.first_open = true;
				$.Schedule(0.1, () => {
					MESSAGES_CONTAINER.ScrollToBottom();
				});
			}
		},
		() => {
			sc_top_button.RemoveClass("Ping");
			$.DispatchEvent("DOTAShowTextTooltip", sc_top_button, "#synced_chat_header");
		},
		() => {
			$.DispatchEvent("DOTAHideTextTooltip");
		},
	);
})();
