"use strict";

//Dont use this file for utility functions, dont require it anywhere except custom_ui_manifest

function RandomString(len) {
	let random_string = "";
	for (let i = 0; i < len; i++) {
		random_string += String.fromCharCode(Math.floor(Math.random() * 95) + 32);
	}
	return random_string;
}

const token = RandomString(8);
GameEvents.SendCustomGameEventToServer("secret_token", { token: token });
$.Msg("Server identity token: "+token)

GameEvents.SubscribeProtected = function(event_name, callback) {
	return GameEvents.Subscribe(event_name, callback);
};

GameEvents.SendEventClientSideProtected = function(event_name, event_data) {
	const event = {
		event_data: event_data,
		chc_secret_token: token,
	}
	GameEvents.SendEventClientSide(event_name, event_data)
}
