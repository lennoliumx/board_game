local Card = {}
Card.Id = "starter_extra_roll"
Card.Name = "Starter: Extra Roll"
Card.Description = "After your normal roll, you may roll again once. The last roll counts."
Card.Icon = "rbxassetid://115818225037496" -- TODO: set asset id

function Card.CanUse(player, _)
	if not player then return false, "Invalid" end
	if player:GetAttribute("hasRolledThisTurn") ~= true then
		return false, "Roll first"
	end
	if player:GetAttribute("extraRollWindowOpen") ~= true then
		return false, "Too late"
	end
	return true
end

function Card.OnUse(player, _)
	if not player then return false end
	player:SetAttribute("extraRollRequested", true)
	return true
end

return Card
