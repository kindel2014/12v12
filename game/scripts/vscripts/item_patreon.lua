function OnSpellStart( event )
    local caster = event.caster
    local abilityname = event.Ability
    --local psets = Patreons:GetPlayerSettings(caster:GetPlayerID())
    --if psets.level > 0 then
        local pa1 = caster:AddAbility(abilityname)
        pa1:SetLevel(1)
        pa1:CastAbility()
        Timers:CreateTimer(1, function()
            caster:RemoveAbility(abilityname)
        end)
    --else
    --    CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(caster:GetPlayerID()), "display_custom_error", { message = "#nopatreonerror" })
    --end
end

function OnSpellStartBundle( event )
    local caster = event.caster
    local ability = event.ability
    local item1 = event.Item1
    local item2 = event.Item2
    local item3 = event.Item3
    local item4 = event.Item4
    if caster:IsRealHero() then
        local supporter_level = Supporters:GetLevel(caster:GetPlayerID())
        if supporter_level > 0 then
            ability:RemoveSelf()
            caster:AddItemByName(item1)
            caster:AddItemByName(item2)
            caster:AddItemByName(item3)
            caster:AddItemByName(item4)
        else
            CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(caster:GetPlayerID()), "display_custom_error", { message = "#nopatreonerror" })
        end
    end
end

function OnSpellStartBanHammer(event)
	if not IsServer() then return end
	
    local target = event.target
    local caster = event.caster
    local ability = event.ability
	
	local caster_player = caster:GetPlayerOwner()
	local caster_id = caster:GetPlayerOwnerID()
	local target_id = target:GetPlayerOwnerID()
	
	if target_id and ((WebApi.playerMatchesCount and WebApi.playerMatchesCount[target_id] and WebApi.playerMatchesCount[target_id] < 5) or PlayerResource:GetConnectionState(target_id) == DOTA_CONNECTION_STATE_ABANDONED) then
		ability:EndCooldown()
		CustomGameEventManager:Send_ServerToPlayer(caster_player, "display_custom_error", { message = "#voting_to_kick_no_kick_new_players" })
		return
	end
	
    if caster:IsRealHero() then
        local supporter_level = Supporters:GetLevel(target_id)

        if target:IsRealHero() and target:IsControllableByAnyPlayer() and not target:IsTempestDouble() then
            if (supporter_level > 0) then
                CustomGameEventManager:Send_ServerToPlayer(caster_player, "display_custom_error", { message = "#cannotkickotherpatreons" })
				ability:EndCooldown()
            else
                if not Kicks.voting then
					Kicks:PreVoting(caster_id, target_id)
					
                    CustomGameEventManager:Send_ServerToPlayer(caster_player, "voting_to_kick_show_reason", { target_id = target_id })

                    GameRules:SendCustomMessage("#alert_for_ban_message_1", caster_id, 0)
                    GameRules:SendCustomMessage("#alert_for_ban_message_2", target_id, 0)

                    local all_heroes = HeroList:GetAllHeroes()
                    for _, hero in pairs(all_heroes) do
                        if hero:IsRealHero() and hero:IsControllableByAnyPlayer() then
                            EmitSoundOn("Hero_Chen.HandOfGodHealHero", hero)
                        end
                    end
                    ability:RemoveSelf()
                else
                    ability:EndCooldown()
                    CustomGameEventManager:Send_ServerToPlayer(caster_player, "display_custom_error", { message = "#voting_to_kick_voiting_for_now" })
                end
            end
        end
    end
end
