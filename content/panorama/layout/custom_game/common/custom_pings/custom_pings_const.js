const C_PingsTypes = {
	DEFAULT: 0,
	DANGER: 1,
	WAYPOINT: 2,
	RETREAT: 3,
	ATTACK: 4,
	ENEMY_WARD: 5,
	FRIENDLY_WARD: 6,
};

const PINGS_DATA = {
	[C_PingsTypes.DEFAULT]: {
		image: "file://{resources}/images/custom_game/ping_icon_world_minimap.png",
		sound: "General.Ping",
	},
	[C_PingsTypes.DANGER]: {
		image: "file://{resources}/images/custom_game/import_dota/ping_danger_psd.png",
		sound: "General.PingWarning",
	},
	[C_PingsTypes.WAYPOINT]: {
		image: "file://{resources}/images/custom_game/ping_icon_waypoint_minimap.png",
		sound: "General.PingWaypoint",
	},
	[C_PingsTypes.RETREAT]: {
		image: "file://{resources}/images/custom_game/import_dota/ping_danger_psd.png",
		sound: "General.PingWarning",
	},
	[C_PingsTypes.ATTACK]: {
		image: "file://{resources}/images/custom_game/import_dota/ping_icon_attack_psd.png",
		sound: "General.PingAttack",
	},
	[C_PingsTypes.ENEMY_WARD]: {
		image: "file://{resources}/images/custom_game/import_dota/ping_icon_enemyward_psd.png",
		sound: "General.PingEnemyWard",
	},
	[C_PingsTypes.FRIENDLY_WARD]: {
		image: "file://{resources}/images/custom_game/import_dota/ping_icon_friendlyward_psd.png",
		sound: "General.PingFriendlyWard",
	},
};
