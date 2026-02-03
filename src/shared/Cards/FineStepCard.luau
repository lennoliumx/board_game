-- FineStepCard: Move any piece on the board forward one space
-- Robust implementation with full validation and error handling
local CollectionService = game:GetService("CollectionService")

local Card = {}
Card.Id = "starter_start_plus_one"
Card.Name = "Starter: Fine Step"
Card.Description = "Move one of your pieces forward one space."
Card.Icon = "rbxassetid://129877086687729"
Card.RequiresTarget = true  -- Signals to cardManager that this card needs target selection

-- Helper: Safely get player's color
local function getPlayerColor(player)
	if not player or not player.Parent then return nil end
	return player:GetAttribute("playerColor")
end

-- Helper: Extract color from figure name
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

-- Helper: Check if player is valid
local function isPlayerValid(player)
	return player and player.Parent and player:IsA("Player")
end

-- Helper: Check if figure is valid and exists in game
local function isFigureValid(fig)
	if not fig or not fig.Parent then return false end
	return CollectionService:HasTag(fig, "figure")
end

-- Helper: Check if figure can move 1 step without overshooting
local function canMoveOneStep(fig)
	if not isFigureValid(fig) then return false end
	
	local stepsTaken = fig:GetAttribute("stepsTaken")
	if type(stepsTaken) ~= "number" then return false end
	
	-- Figure must be on the board (steps >= 0)
	if stepsTaken < 0 then return false end
	
	-- Cannot move past goal (goal slots are 40-43, overshoot at 44+)
	if stepsTaken >= 43 then return false end
	
	return true
end

-- Helper: Check if destination would be blocked by own figure
local function wouldBeBlockedByOwnFigure(player, fig)
	if not player or not fig then return true end
	
	local playerColor = getPlayerColor(player)
	if not playerColor then return true end
	
	local currentSteps = fig:GetAttribute("stepsTaken") or -1
	if currentSteps < 0 then return true end
	
	local targetSteps = currentSteps + 1
	local isGoal = targetSteps >= 40
	local checkValue = isGoal and ("G" .. (targetSteps - 39)) or nil
	
	-- Check all figures with same color
	for _, otherFig in ipairs(CollectionService:GetTagged("figure")) do
		if otherFig ~= fig and getFigureColor(otherFig) == playerColor then
			local otherTile = otherFig:GetAttribute("tileIndex")
			if isGoal and checkValue then
				if tostring(otherTile) == checkValue then
					return true
				end
			end
		end
	end
	
	return false
end

function Card.CanUse(player, ctx)
	-- Validate player
	if not isPlayerValid(player) then
		return false, "Invalid player"
	end
	
	-- Validate context and target figure
	if not ctx or type(ctx) ~= "table" then
		return false, "Select a figure"
	end
	
	local fig = ctx.targetFigure
	if not fig then
		return false, "Select a figure"
	end
	
	-- Validate figure exists
	if not isFigureValid(fig) then
		return false, "Invalid figure"
	end
	
	-- Verify ownership
	if not isPlayersFigure(player, fig) then
		return false, "Not your figure"
	end
	
	-- Check figure is on the board
	local stepsTaken = fig:GetAttribute("stepsTaken")
	if type(stepsTaken) ~= "number" or stepsTaken < 0 then
		return false, "Figure must be on the board"
	end
	
	-- Check if figure can move forward
	if not canMoveOneStep(fig) then
		return false, "Figure cannot move further"
	end
	
	-- Check for self-blocking
	if wouldBeBlockedByOwnFigure(player, fig) then
		return false, "Destination blocked by your own figure"
	end
	
	return true
end

function Card.OnUse(player, ctx)
	-- Re-validate everything
	if not isPlayerValid(player) then
		return false
	end
	
	if not ctx or type(ctx) ~= "table" then
		return false
	end
	
	local fig = ctx.targetFigure
	
	if not isFigureValid(fig) then
		return false
	end
	
	if not isPlayersFigure(player, fig) then
		return false
	end
	
	if not canMoveOneStep(fig) then
		return false
	end
	
	return { effect = "moveOne", targetFigure = fig, steps = 1 }
end

return Card
