local Card = {}
Card.Id = "starter_start_plus_one"
Card.Name = "Starter: Start +1"
Card.Description = "If a piece left the house this turn, add +1 to the roll that moves it off the start tile."
Card.Icon = "rbxassetid://129877086687729" -- TODO: set asset id

local function isPlayersFigure(player, fig)
	if not player or not fig then return false end
	local playerColor = player:GetAttribute("playerColor")
	local figColor = fig.Name:match("Figure_(%a+)_")
	return playerColor and figColor and playerColor == figColor
end

function Card.CanUse(player, ctx)
	if not player or not ctx or not ctx.targetFigure then return false, "Select a figure" end
	if player:GetAttribute("awaitingStartRoll") ~= true then return false, "Not available now" end
	local fig = ctx.targetFigure
	if fig:GetAttribute("leftHouseThisTurn") ~= true then return false, "Not eligible" end
	if not isPlayersFigure(player, fig) then return false, "Not your figure" end
	return true
end

function Card.OnUse(player, _)
	if not player then return false end
	player:SetAttribute("startPlusOnePending", true)
	return true
end

return Card
