SyncedChat = SyncedChat or {}


function SyncedChat:Init()
	SyncedChat.poll_delay = 60
	Timers:CreateTimer("sync_chat:poll_timer", {
		useGameTime = false,
		endTime = 10,
		callback = function()
			print("sync chat timer tick")
			SyncedChat:Poll()
			return SyncedChat.poll_delay
		end
	})
	SyncedChat.current_messages = {}
	RegisterCustomEventListener("synced_chat:send", function(data) SyncedChat:Send(data) end)
	RegisterCustomEventListener("synced_chat:request_inital", function(data) SyncedChat:SendInitialMessages(data) end)
	RegisterCustomEventListener("synced_chat:get_older_messages", function(data) SyncedChat:GetOlderMessages(data) end)
	RegisterCustomEventListener("synced_chat:window_state", function(data) SyncedChat:SetWindowState(data) end)
	SyncedChat.last_seen_id = 0

	SyncedChat.player_windows_state = {}
	for i = 0, 24 do
		SyncedChat.player_windows_state[i] = false
	end

	self.last_page = 1
end


function SyncedChat:GetOlderMessages()
	WebApi:Send(
		"match/get_older_messages",
		{
			customGame = WebApi.customGame,
			pageNum = self.last_page + 1,
		},
		function(response)
			self.last_page = self.last_page + 1

			for key, val in pairs(response) do
				if SyncedChat.current_messages[val.id] then
					response[key] = nil
				else
					SyncedChat.current_messages[val.id] = val
					if val.id > SyncedChat.last_seen_id then SyncedChat.last_seen_id = val.id end
				end
			end
			CustomGameEventManager:Send_ServerToAllClients("synced_chat:add_older_messages", response)
		end
	)
end


function SyncedChat:Poll()
	print("poll called")
	WebApi:Send(
		"match/poll_chat_messages",
		{
			customGame = WebApi.customGame,
			lastSeenMessageId = SyncedChat.last_seen_id > 0 and SyncedChat.last_seen_id or nil,
		},
		function(response)
			CustomGameEventManager:Send_ServerToAllClients("synced_chat:poll_result", response)
			DeepPrintTable(response)
			for _, val in pairs(response) do
				SyncedChat.current_messages[val.id] = val
				if val.id > SyncedChat.last_seen_id then SyncedChat.last_seen_id = val.id end
			end
		end
	)
end


function SyncedChat:Send(data)
	if data.text and data.text == "" then return end

	local anon = data.anon == 1

	WebApi:Send(
		"match/send_chat_message",
		{
			customGame = WebApi.customGame,
			steamId = data.steamId,
			steamName = data.steamName,
			text = data.text,
			anon = anon,
		},
		function(resp)
			if resp.id > SyncedChat.last_seen_id then SyncedChat.last_seen_id = resp.id end
			CustomGameEventManager:Send_ServerToAllClients("synced_chat:message_sent", resp)
		end,
		function(err)
			print("failed to sent message: ", err)
		end
	)
end


function SyncedChat:SetWindowState(data)
	local player_id = data.PlayerID
	if not player_id then return end

	SyncedChat.player_windows_state[player_id] = data.state == 1

	-- set poll delay shorter if anyone is having chat open
	for p_id, state in pairs(SyncedChat.player_windows_state) do
		if state then
			SyncedChat.poll_delay = 20
			return
		end
	end
	SyncedChat.poll_delay = 60
end


function SyncedChat:SendInitialMessages(data)
	if not data.PlayerID then return end
	local player = PlayerResource:GetPlayer(data.PlayerID)
	if player and not player:IsNull() then
		CustomGameEventManager:Send_ServerToPlayer(player, "synced_chat:poll_result", SyncedChat.current_messages)
	end
end
