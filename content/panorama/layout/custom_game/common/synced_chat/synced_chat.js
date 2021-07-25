const SYNCED_CHAT_ROOT = $.GetContextPanel();
const MESSAGES_CONTAINER = $("#SC_MessagesContainer");
const TEXT_ENTRY = $("#SC_TextEntry");
const SYMBOLS_COUNTER = $("#SC_SymbolsCounter");
const SUBMIT_BUTTON = $("#SC_Submit");
const LOCK_SCREEN = $("#SC_Locked");
const ANON_HUD_CHECK = $("#AnonMessageCheck");
let NOT_SUPPORTER = false;
let MESSAGES = {};

const MAX_SYMBOLS = 100;
const LOCAL_PLAYER_INFO = Game.GetLocalPlayerInfo();

function TEXT_LENGTH() {
	return TEXT_ENTRY.text.length;
}

function UpdateChatMessageText() {
	let current_length = TEXT_LENGTH();
	SYMBOLS_COUNTER.SetHasClass("LIMIT", current_length == MAX_SYMBOLS);
	SYMBOLS_COUNTER.SetDialogVariable("curr", current_length);
}

function SendChatMessage() {
	if (NOT_SUPPORTER) return;
	if (SUBMIT_BUTTON.BHasClass("COOLDOWN")) return;
	if (TEXT_ENTRY.text == "") return;

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

function ProcessPollResult(data) {
	Object.values(data).forEach((val) => {
		AddMessage(val);
	});
	MESSAGES_CONTAINER.ScrollToBottom();
}

function ProcessSentMessage(data) {
	AddMessage(data);
	TEXT_ENTRY.text = "";
	$.Schedule(0.2, () => {
		MESSAGES_CONTAINER.ScrollToBottom();
	});
}

function AddMessage(msg_data, is_old) {
	if (NOT_SUPPORTER) return;
	if (MESSAGES[msg_data.id]) return;

	let text_content = msg_data.Content;
	text_content = text_content.replace(/<:.*:\d*>/g, "");
	if (text_content == "") return;

	const message_panel = $.CreatePanel("Panel", MESSAGES_CONTAINER, "SC_Msg_" + msg_data.id);

	const added_at_date = new Date(msg_data.AddedAt);
	let hours = added_at_date.getHours().toString().padStart(2, 0);
	let minutes = added_at_date.getMinutes().toString().padStart(2, 0);
	let seconds = added_at_date.getSeconds().toString().padStart(2, 0);

	message_panel.BLoadLayoutSnippet("SC_MessageLine");
	message_panel.GetChild(0).text = `${hours}:${minutes}:${seconds}`;

	const avatar = message_panel.GetChild(1);
	const steam_nickname = message_panel.GetChild(2);
	const dev_nickname = message_panel.GetChild(3);

	if (msg_data.SteamId != "-1") {
		if (msg_data.Anonymous == 0) {
			avatar.steamid = msg_data.SteamId;
			steam_nickname.steamid = msg_data.SteamId;
		} else {
			steam_nickname.AddClass("NoUser");
			avatar.GetChild(1).SetImage("file://{resources}/images/custom_game/no_user.png");
			$.Schedule(0.1, () => {
				steam_nickname.GetChild(0).text = $.Localize("anon_player");
			});
		}
		dev_nickname.style.visibility = "collapse";
	} else {
		avatar.style.visibility = "collapse";
		steam_nickname.style.visibility = "collapse";
		dev_nickname.text = `[${$.Localize("#DEV")}] ${msg_data.SteamName}`;
	}

	message_panel.GetChild(5).text = text_content;
	MESSAGES[msg_data.id] = message_panel;

	if (is_old != undefined) {
		MESSAGES_CONTAINER.MoveChildAfter(message_panel, more_mess_button);
		message_panel.ScrollParentToMakePanelFit(1, true);
	}
}

function CloseSyncedChat() {
	$.GetContextPanel().SetHasClass("show", false);
}

SubscribeToNetTableKey("game_state", "patreon_bonuses", function (patreon_bonuses) {
	let local_stats = patreon_bonuses[Game.GetLocalPlayerID()];
	let level = 0;
	if (local_stats && local_stats.level) {
		level = local_stats.level;
	}
	LOCK_SCREEN.style.visibility = level == 0 ? "visible" : "collapse";
	NOT_SUPPORTER = level == 0;
});

let more_mess_button;
(function () {
	MESSAGES_CONTAINER.RemoveAndDeleteChildren();

	more_mess_button = $.CreatePanel("Button", MESSAGES_CONTAINER, "");
	more_mess_button.BLoadLayoutSnippet("MoreMessage");
	more_mess_button.SetPanelEvent("onactivate", () => {
		GameEvents.SendCustomGameEventToServer("synced_chat:get_older_messages", {});
	});

	SYMBOLS_COUNTER.SetDialogVariable("max", MAX_SYMBOLS);
	SYMBOLS_COUNTER.SetDialogVariable("curr", 0);

	GameEvents.Subscribe("synced_chat:poll_result", ProcessPollResult);
	GameEvents.Subscribe("synced_chat:add_older_messages", AddOlderMessages);
	GameEvents.Subscribe("synced_chat:message_sent", ProcessSentMessage);

	GameEvents.SendCustomGameEventToServer("synced_chat:request_inital", {});

	const sync_chat_toggle = _AddMenuButton("OpenSyncedChat");
	CreateButtonInTopMenu(
		sync_chat_toggle,
		() => {
			SYNCED_CHAT_ROOT.ToggleClass("show");
		},
		() => {
			$.DispatchEvent("DOTAShowTextTooltip", sync_chat_toggle, "#synced_chat_header");
		},
		() => {
			$.DispatchEvent("DOTAHideTextTooltip");
		},
	);
})();
