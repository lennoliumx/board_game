local CollectionService = game:GetService("CollectionService")

local Card = {}
Card.Id = "starter_capture_bonus"
Card.Name = "Starter: Capture +1"
Card.Description = "After you capture an opponent, you may move the capturing piece 1 extra square."
Card.Icon = "rbxassetid://129099854984765" -- TODO: set asset id

local function isPlayersFigure(player, fig)
	if not player or not fig then return false end
	local playerColor = player:GetAttribute("playerColor")
	local figColor = fig.Name:match("Figure_(%a+)_")
	return playerColor and figColor and playerColor == figColor
end

local function findFigureByName(name)
	for _, fig in ipairs(CollectionService:GetTagged("figure")) do
		if fig.Name == name then return fig end
	end
	return nil
end

function Card.CanUse(player, _)
	if not player then return false, "Invalid" end
	if player:GetAttribute("captureBonusAvailable") ~= true then
		return false, "No capture available"
	end
	local figName = player:GetAttribute("captureBonusFigureName")
	local fig = figName and findFigureByName(figName) or nil
	if not fig then return false, "No valid target" end
	if not isPlayersFigure(player, fig) then return false, "Not your figure" end
	return true
end

function Card.OnUse(player, _)
	local figName = player and player:GetAttribute("captureBonusFigureName")
	local fig = figName and findFigureByName(figName) or nil
	if not fig then return false end
	player:SetAttribute("captureBonusAvailable", false)
	player:SetAttribute("captureBonusFigureName", "")
	return { effect = "moveOne", targetFigure = fig, steps = 1 }
end

return Card
