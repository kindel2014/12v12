SyncedChat = SyncedChat or {}

function SyncedChat:Init()
	Timers:CreateTimer("sync_chat:poll_timer", {
		useGameTime = false,
		endTime = 10,
		callback = function()
			print("sync chat timer tick")
			SyncedChat:Poll()
			return 20
		end
	})
	SyncedChat.current_messages = {}
	RegisterCustomEventListener("synced_chat:send", function(data) SyncedChat:Send(data) end)
	RegisterCustomEventListener("synced_chat:request_inital", function(data) SyncedChat:SendInitialMessages(data) end)
	SyncedChat.last_seen_id = 0
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
	print("sending message from dota")
	DeepPrintTable(data)
	WebApi:Send(
		"match/send_chat_message",
		{
			customGame = WebApi.customGame,
			steamId = data.steamId,
			steamName = data.steamName,
			text = data.text,
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


function SyncedChat:SendInitialMessages(data)
	local player = PlayerResource:GetPlayer(data.PlayerID)
	if player and not player:IsNull() then
		CustomGameEventManager:Send_ServerToPlayer(player, "synced_chat:poll_result", SyncedChat.current_messages)
	end
end
