local Card = {}
Card.Id = "starter_protect_start"
Card.Name = "Starter: Safe Start"
Card.Description = "If a piece left the house this turn, make it immune to capture until your next turn."
Card.Icon = "rbxassetid://89136599721424" -- TODO: set asset id

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

function Card.OnUse(player, ctx)
	local fig = ctx and ctx.targetFigure
	if not fig then return false end
	local activeCount = player:GetAttribute("activePlayerCount") or 4
	local turns = math.max(1, activeCount - 1)
	fig:SetAttribute("protectedTurns", turns)
	return true
end

return Card
