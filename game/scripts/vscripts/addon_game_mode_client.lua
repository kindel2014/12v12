if IsClient() then 
	local function AutoAttack(event)
		print("Auto attack setting: Value", event.value)
		SendToConsole("dota_player_units_auto_attack_mode " .. event.value)
	end
	ListenToGameEvent("auto_attack_setting", function(event) AutoAttack(event) end, nil)
end