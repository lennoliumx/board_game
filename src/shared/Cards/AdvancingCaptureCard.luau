-- AdvancingCaptureCard: Move capturing piece +1 after capturing an opponent
-- Robust implementation with full validation and error handling
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Card = {}
Card.Id = "starter_capture_bonus"
Card.Name = "Starter: Capture +1"
Card.Description = "After you capture an opponent, you may move the capturing piece 1 extra square."
Card.Icon = "rbxassetid://129099854984765"

-- Helper: Safely get player's color
local function getPlayerColor(player)
	if not player or not player.Parent then return nil end
	return player:GetAttribute("playerColor")
end

-- Helper: Extract color from figure name (e.g., "Figure_red_1" -> "red")
local function getFigureColor(fig)
	if not fig or not fig.Name then return nil end
	return fig.Name:match("Figure_(%a+)_")
end

-- Helper: Validate that figure belongs to player
local function isPlayersFigure(player, fig)
	if not player or not fig then return false end
	local playerColor = getPlayerColor(player)
	local figColor = getFigureColor(fig)
	return playerColor and figColor and playerColor == figColor
end

-- Helper: Find figure by name with validation
local function findFigureByName(name)
	if not name or name == "" then return nil end
	for _, fig in ipairs(CollectionService:GetTagged("figure")) do
		if fig and fig.Parent and fig.Name == name then
			return fig
		end
	end
	return nil
end

-- Helper: Check if figure can move 1 step without overshooting goal
local function canMoveOneStep(fig)
	if not fig or not fig.Parent then return false end
	local stepsTaken = fig:GetAttribute("stepsTaken")
	if type(stepsTaken) ~= "number" or stepsTaken < 0 then return false end
	-- Goal is steps 40-43, overshoot at 44+
	if stepsTaken >= 43 then return false end
	-- Cannot move if already in final goal position
	if fig:GetAttribute("isGoal") == true and stepsTaken >= 43 then return false end
	return true
end

-- Helper: Check if player is still in the game
local function isPlayerValid(player)
	return player and player.Parent and player:IsA("Player")
end

function Card.CanUse(player, _)
	-- Validate player
	if not isPlayerValid(player) then
		return false, "Invalid player"
	end
	
	-- Check if capture bonus is available
	if player:GetAttribute("captureBonusAvailable") ~= true then
		return false, "No capture bonus available"
	end
	
	-- Get and validate the capturing figure
	local figName = player:GetAttribute("captureBonusFigureName")
	if not figName or figName == "" then
		return false, "No figure specified"
	end
	
	local fig = findFigureByName(figName)
	if not fig then
		return false, "Figure not found"
	end
	
	-- Verify ownership
	if not isPlayersFigure(player, fig) then
		return false, "Not your figure"
	end
	
	-- Check if figure can actually move
	if not canMoveOneStep(fig) then
		return false, "Figure cannot move further"
	end
	
	return true
end

function Card.OnUse(player, _)
	-- Re-validate everything (state could have changed)
	if not isPlayerValid(player) then
		return false
	end
	
	local figName = player:GetAttribute("captureBonusFigureName")
	local fig = figName and findFigureByName(figName)
	
	if not fig or not isPlayersFigure(player, fig) then
		return false
	end
	
	if not canMoveOneStep(fig) then
		return false
	end
	
	-- Clear the capture bonus state immediately to prevent double-use
	player:SetAttribute("captureBonusAvailable", false)
	player:SetAttribute("captureBonusFigureName", "")
	
	return { effect = "moveOne", targetFigure = fig, steps = 1 }
end

return Card
