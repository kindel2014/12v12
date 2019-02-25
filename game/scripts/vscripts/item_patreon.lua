function OnSpellStart( event )
    local caster = event.caster
    local abilityname = event.Ability
    local psets = Patreons:GetPlayerSettings(caster:GetPlayerID())
    --if psets.level > 0 then
        local pa1 = caster:AddAbility(abilityname)
        pa1:SetLevel(1)
        pa1:CastAbility()
        Timers:CreateTimer(1, function()
            caster:RemoveAbility(abilityname)
        end)
    --else
    --    CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(caster:GetPlayerID()), "display_custom_error", { message = "Error Test" })--need error text
    --end
end

function OnSpellStartBundle( event )
    local caster = event.caster
    local ability = event.ability
    local item1 = event.Item1
    local item2 = event.Item2
    local item3 = event.Item3
    local item4 = event.Item4
    local psets = Patreons:GetPlayerSettings(caster:GetPlayerID())
    if psets.level > 0 then
        ability:RemoveSelf()
        caster:AddItemByName(item1)
        caster:AddItemByName(item2)
        caster:AddItemByName(item3)
        caster:AddItemByName(item4)
    else
        CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(caster:GetPlayerID()), "display_custom_error", { message = "Error Test" })--need error text
    end
end