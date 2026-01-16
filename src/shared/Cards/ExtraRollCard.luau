local Extra = {}
Extra.Id = "extraroll"
Extra.Name = "Extra Roll"
Extra.Description = "Allow the current player to roll the dice again immediately."
Extra.Icon = "rbxassetid://115818225037496"

function Extra.CanUse(player, ctx)
    -- Must be player's turn; gameDynamics enforces this server-side if needed
    return true
end

function Extra.OnUse(player, ctx)
    -- Effect: signal via attribute that player may roll again
    player:SetAttribute("allowExtraRoll", true)
    return true
end

return Extra
