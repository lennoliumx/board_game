-- SecondAttemptCard: Roll the dice again after your normal roll
-- Robust implementation with full validation and error handling
local Card = {}
Card.Id = "starter_extra_roll"
Card.Name = "Starter: Extra Roll"
Card.Description = "After your normal roll, you may roll again once. The last roll counts."
Card.Icon = "rbxassetid://115818225037496"
Card.RequiresTarget = false  -- No target selection needed

-- Helper: Check if player is valid and still in game
local function isPlayerValid(player)
	return player and player.Parent and player:IsA("Player")
end

-- Helper: Check if extra roll window is currently open
local function isExtraRollWindowOpen(player)
	if not player then return false end
	return player:GetAttribute("extraRollWindowOpen") == true
end

-- Helper: Check if player has already rolled this turn
local function hasRolledThisTurn(player)
	if not player then return false end
	return player:GetAttribute("hasRolledThisTurn") == true
end

-- Helper: Check if extra roll was already requested
local function wasExtraRollAlreadyRequested(player)
	if not player then return true end
	return player:GetAttribute("extraRollRequested") == true
end

function Card.CanUse(player, _)
	-- Debug output
	print("[SecondAttemptCard] CanUse called for", player and player.Name or "nil")
	print("  - isPlayerValid:", isPlayerValid(player))
	print("  - extraRollWindowOpen:", player and player:GetAttribute("extraRollWindowOpen"))
	print("  - extraRollRequested:", player and player:GetAttribute("extraRollRequested"))
	
	-- Validate player is still in game
	if not isPlayerValid(player) then
		print("  -> FAIL: Invalid player")
		return false, "Invalid player"
	end
	
	-- Extra roll window must be open (this implicitly means they've rolled)
	if not isExtraRollWindowOpen(player) then
		print("  -> FAIL: Extra roll window closed")
		return false, "Extra roll window has closed"
	end
	
	-- Can't request if already requested
	if wasExtraRollAlreadyRequested(player) then
		print("  -> FAIL: Already requested")
		return false, "Extra roll already requested"
	end
	
	print("  -> SUCCESS")
	return true
end

function Card.OnUse(player, _)
	-- Re-validate state (could have changed between CanUse and OnUse)
	if not isPlayerValid(player) then
		return false
	end
	
	if not isExtraRollWindowOpen(player) then
		return false
	end
	
	if wasExtraRollAlreadyRequested(player) then
		return false
	end
	
	-- Request the extra roll (gameDynamics will handle the actual re-roll)
	player:SetAttribute("extraRollRequested", true)
	
	return true
end

return Card
