local Protect = {}
Protect.Id = "protect"
Protect.Name = "Protect Figure"
Protect.Description = "Make a chosen figure immune to capture for 1 full opponent turn."
Protect.Icon = "rbxassetid://0" -- replace with your asset

function Protect.CanUse(player, ctx)
    if not ctx or not ctx.targetFigure then return false, "Select a figure" end
    local fig = ctx.targetFigure
    -- Only allow using on player's own figure
    if not string.match(fig.Name, "Figure_%a+_") then return false, "Invalid target" end
    -- Could add ownership check in production
    return true
end

function Protect.OnUse(player, ctx)
    local fig = ctx.targetFigure
    if not fig then return false end
    -- Mark attribute; consuming logic: protectedTurns will be decremented by game loop
    local current = fig:GetAttribute("protectedTurns") or 0
    fig:SetAttribute("protectedTurns", current + 1)
    return true
end

return Protect
