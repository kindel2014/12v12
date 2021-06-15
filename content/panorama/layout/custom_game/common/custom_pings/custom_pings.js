const HUD_ROOT_FOR_TRACKER = FindDotaHudElement("HeroRelicProgress");
const HUD_PING_WHEEL = $("#Custom_PingWheel");
const HUD_FOR_CUSTOM_PINGS = $("#CustomPings_Minimap");

const ROOT = $.GetContextPanel();
const minimap = FindDotaHudElement("minimap_block");
const dota_hud = FindDotaHudElement("Hud");

const THINK = 0.01;
const PINGS_COUNT = 7;
const MIN_OFFSET = 18;
const MAX_OFFSET = 200;
const TRIGGER_TIME_FOR_WHEEL = 0.3;

// 80 - that's 1/2 of height/width from HUD_PING_WHEEL
const hud_wheel_half_width = 80;
const hud_wheel_half_height = 80;

// 80 - that's 1/2 of height/width from HUD_PING_WHEEL
const hud_ping_root_half_width = 25;
const hud_ping_root_half_height = 25;

// Game World width / height
const WORLD_Y = 8000;
const WORLD_X = 8000;

let time_counter = 0;
let b_root_visible = false;
let tracker_hud;

function SetRootPingActive(bool) {
	tracker_hud.hittest = bool;
	HUD_ROOT_FOR_TRACKER.hittestchildren = bool;
}

function ClearActive() {
	for (let i = 1; i <= PINGS_COUNT; i++) {
		$(`#Custom_Ping${i}`).SetHasClass("Active", false);
	}
	HUD_PING_WHEEL.SetHasClass("DefaultPing", false);
}

function PingToServer() {
	for (let i = 1; i <= PINGS_COUNT; i++) {
		const panel = $(`#Custom_Ping${i}`);
		if (panel.BHasClass("Active")) {
			let ping_pos_screen = HUD_PING_WHEEL.GetPositionWithinWindow();
			const x = ping_pos_screen.x + hud_wheel_half_width;
			const y = ping_pos_screen.y + hud_wheel_half_height;
			GameEvents.SendCustomGameEventToServer("custom_ping:ping", {
				pos: Game.ScreenXYToWorld(x, y),
				type: panel.GetAttributeInt("ping-type", 0),
			});
			// ClientPing({
			// 	pos_x: Game.ScreenXYToWorld(x, y)[0],
			// 	pos_y: Game.ScreenXYToWorld(x, y)[1],
			// 	type: panel.GetAttributeInt("ping-type", 0),
			// 	player_id: 0,
			// });
		}
	}
}

function GamePingsTracker() {
	if (GameUI.IsAltDown() && GameUI.IsMouseDown(0)) {
		time_counter += THINK;
	} else {
		if (b_root_visible) PingToServer();
		ClearActive();
		SetRootPingActive(false);
		HUD_PING_WHEEL.visible = false;
		b_root_visible = false;
		time_counter = 0;
	}

	if (time_counter >= TRIGGER_TIME_FOR_WHEEL && !b_root_visible) {
		const cursor = GameUI.GetCursorPosition();
		SetRootPingActive(true);
		$.Schedule(0.01, () => {
			if (tracker_hud.BHasHoverStyle()) {
				HUD_PING_WHEEL.visible = true;
				b_root_visible = true;
				HUD_PING_WHEEL.style.position = `${(cursor[0] - hud_wheel_half_width) / ROOT.actualuiscale_x}px ${
					(cursor[1] - hud_wheel_half_height) / ROOT.actualuiscale_y
				}px 0px`;
			}
		});
	}

	if (b_root_visible) {
		ClearActive();
		const cursor = GameUI.GetCursorPosition();
		const root_pos = HUD_PING_WHEEL.GetPositionWithinWindow();

		const x = cursor[0] - root_pos.x - hud_wheel_half_width;
		const y = root_pos.y - cursor[1] + hud_wheel_half_height;

		let deg = (Math.atan2(y, x) * 180) / Math.PI + (y < 0 ? 360 : 0);

		let element_n = Math.ceil(0.5 + deg / (360 / (PINGS_COUNT - 1)));
		element_n = element_n == 7 ? 1 : element_n;

		const x_abs = Math.abs(x);
		const y_abs = Math.abs(y);
		if (x_abs < MIN_OFFSET && y_abs < MIN_OFFSET) element_n = 7;

		if (x_abs <= MAX_OFFSET * ROOT.actualuiscale_x && y_abs <= MAX_OFFSET * ROOT.actualuiscale_y) {
			const panel = $(`#Custom_Ping${element_n}`);
			if (panel) panel.SetHasClass("Active", true);
			HUD_PING_WHEEL.SetHasClass("DefaultPing", element_n == 7);
		}
	}
	$.Schedule(THINK, () => {
		GamePingsTracker();
	});
}

function ClientPing(data) {
	if (data.type == undefined || PINGS_DATA[data.type] == undefined) return;

	const original_map_width = Math.ceil(minimap.actuallayoutwidth / minimap.actualuiscale_x);
	const original_map_height = Math.ceil(minimap.actuallayoutheight / minimap.actualuiscale_y);

	const coef_x = data.pos_x / (WORLD_X * 2);
	const coef_y = data.pos_y / (WORLD_Y * 2);
	const pos_x = (coef_x + 0.5) * original_map_width;
	const pos_y = (0.5 - coef_y) * original_map_height;

	if (pos_x > original_map_width || pos_y > original_map_height) return;

	const new_ping = $.CreatePanel("Panel", HUD_FOR_CUSTOM_PINGS, "");
	new_ping.BLoadLayoutSnippet("CustomPing");

	const margin_side = pos_x - hud_ping_root_half_width + coef_x * 8;
	if (dota_hud.BHasClass("HUDFlipped")) {
		new_ping.style.marginLeft = `${original_map_width - margin_side - hud_ping_root_half_width * 2}px`;
	} else {
		new_ping.style.marginLeft = `${margin_side}px`;
	}

	const margin_top = pos_y + hud_ping_root_half_height - coef_y * 8;

	new_ping.style.marginTop = `${original_map_height - margin_top}px`;

	const image = new_ping.GetChild(0);
	image.AddClass("Pulse");

	if (PINGS_DATA[data.type].image != undefined) {
		image.SetImage(PINGS_DATA[data.type].image);
	}
	if (PINGS_DATA[data.type].sound != undefined) {
		Game.EmitSound(PINGS_DATA[data.type].sound);
	}

	if (data.type == C_PingsTypes.DEFAULT || data.type == C_PingsTypes.DANGER || data.type == C_PingsTypes.WAYPOINT) {
		const player_color = GetHEXPlayerColor(data.player_id);
		image.style.washColor = player_color;
	} else if (data.type == C_PingsTypes.RETREAT) {
		image.style.washColor = "#ff0a0a;";
	}

	if (data.type == C_PingsTypes.WAYPOINT) {
		new_ping.GetChild(1).SetImage(GetPortraitIcon(data.player_id, Players.GetPlayerSelectedHero(data.player_id)));
	}

	$.Schedule(3.5, () => {
		new_ping.DeleteAsync(0);
	});
}

(function () {
	HUD_FOR_CUSTOM_PINGS.RemoveAndDeleteChildren();
	HUD_ROOT_FOR_TRACKER.Children().forEach((p) => {
		if (p.id == "CustomPingsHudTracker") p.DeleteAsync(0);
	});
	const panel = $("#CustomPingsHudTracker");
	panel.SetParent(HUD_ROOT_FOR_TRACKER);
	panel.hittest = true;
	tracker_hud = panel;
	GamePingsTracker();
	GameEvents.Subscribe("custom_ping:ping_client", ClientPing);
})();
