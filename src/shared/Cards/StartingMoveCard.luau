local Card = {}
Card.Id = "starter_move_one"
Card.Name = "Starter: Move +1"
Card.Description = "Move one of your pieces forward one space."
Card.Icon = "rbxassetid://100244499853123" -- TODO: set asset id

local function isPlayersFigure(player, fig)
	if not player or not fig then return false end
	local playerColor = player:GetAttribute("playerColor")
	local figColor = fig.Name:match("Figure_(%a+)_")
	return playerColor and figColor and playerColor == figColor
end

function Card.CanUse(player, ctx)
	if not player or not ctx or not ctx.targetFigure then return false, "Select a figure" end
	local fig = ctx.targetFigure
	local steps = fig:GetAttribute("stepsTaken") or -1
	if steps < 0 then return false, "Figure must be on board" end
	if not isPlayersFigure(player, fig) then return false, "Not your figure" end
	return true
end

function Card.OnUse(player, ctx)
	local fig = ctx and ctx.targetFigure
	if not fig then return false end
	return { effect = "moveOne", targetFigure = fig, steps = 1 }
end

return Card
