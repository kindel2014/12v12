const SYNCED_CHAT_ROOT = $.GetContextPanel();
const MESSAGES_CONTAINER = $("#SC_MessagesContainer");
const TEXT_ENTRY = $("#SC_TextEntry");
const SYMBOLS_COUNTER = $("#SC_SymbolsCounter");
const SUBMIT_BUTTON = $("#SC_Submit");
const LOCK_SCREEN = $("#SC_Locked");
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

	GameEvents.SendCustomGameEventToServer("synced_chat:send", {
		steamId: LOCAL_PLAYER_INFO.player_steamid,
		steamName: LOCAL_PLAYER_INFO.player_name,
		text: TEXT_ENTRY.text,
	});

	SUBMIT_BUTTON.SetHasClass("COOLDOWN", true);
	$.Schedule(10, () => {
		SUBMIT_BUTTON.SetHasClass("COOLDOWN", false);
	});
}

function ProcessPollResult(data) {
	Object.values(data).forEach((val, idx) => {
		AddMessage(val);
	});
}

function ProcessSentMessage(data) {
	AddMessage(data);
	TEXT_ENTRY.text = "";
	$.Schedule(0.2, () => {
		MESSAGES_CONTAINER.ScrollToBottom();
	});
}

function AddMessage(msg_data) {
	if (NOT_SUPPORTER) return;
	if (MESSAGES[msg_data.id]) return;
	const message_panel = $.CreatePanel(
		"Panel",
		MESSAGES_CONTAINER,
		"SC_Msg_" + msg_data.id
	);

	const added_at_date = new Date(msg_data.AddedAt);
	let hours = added_at_date.getHours();
	hours = hours > 9 ? hours : `0${hours}`;
	let minutes = added_at_date.getMinutes();
	minutes = minutes > 9 ? minutes : `0${minutes}`;
	let seconds = added_at_date.getSeconds();
	seconds = seconds > 9 ? seconds : `0${seconds}`;
	const date_as_string = `${hours}:${minutes}:${seconds}`;

	message_panel.BLoadLayoutSnippet("SC_MessageLine");

	message_panel.GetChild(0).text = date_as_string;
	const avatar = message_panel.GetChild(1);
	const steam_nickname = message_panel.GetChild(2);
	const dev_nickname = message_panel.GetChild(3);
	if (msg_data.SteamId != "-1") {
		avatar.steamid = msg_data.SteamId;
		steam_nickname.steamid = msg_data.SteamId;
		dev_nickname.style.visibility = "collapse";
	} else {
		avatar.style.visibility = "collapse";
		steam_nickname.style.visibility = "collapse";
		dev_nickname.text = `[${$.Localize("#DEV")}] ${msg_data.SteamName}`;
	}

	message_panel.GetChild(5).text = msg_data.Content;
	MESSAGES[msg_data.id] = message_panel;
}

function CloseSyncedChat() {
	$.GetContextPanel().SetHasClass("show", false);
}

SubscribeToNetTableKey(
	"game_state",
	"patreon_bonuses",
	function (patreon_bonuses) {
		let local_stats = patreon_bonuses[Game.GetLocalPlayerID()];
		let level = 0;
		if (local_stats && local_stats.level) {
			level = local_stats.level;
		}
		LOCK_SCREEN.style.visibility = level == 0 ? "visible" : "collapse";
		NOT_SUPPORTER = level == 0;
	}
);

(function () {
	SYMBOLS_COUNTER.SetDialogVariable("max", MAX_SYMBOLS);
	SYMBOLS_COUNTER.SetDialogVariable("curr", 0);

	GameEvents.Subscribe("synced_chat:poll_result", ProcessPollResult);
	GameEvents.Subscribe("synced_chat:message_sent", ProcessSentMessage);

	GameEvents.SendCustomGameEventToServer("synced_chat:request_inital", {});

	const sync_chat_toggle = _AddMenuButton("OpenSyncedChat");
	CreateButtonInTopMenu(
		sync_chat_toggle,
		() => {
			SYNCED_CHAT_ROOT.ToggleClass("show");
		},
		() => {
			$.DispatchEvent(
				"DOTAShowTextTooltip",
				sync_chat_toggle,
				"#synced_chat_header"
			);
		},
		() => {
			$.DispatchEvent("DOTAHideTextTooltip");
		}
	);
})();
