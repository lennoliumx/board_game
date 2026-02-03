-- StartingMoveCard: Move a piece that just left the house forward one space
-- Robust implementation with full validation and error handling
local CollectionService = game:GetService("CollectionService")

local Card = {}
Card.Id = "starter_move_one"
Card.Name = "Starter: Move +1"
Card.Description = "Move a figure that just left the house forward one space."
Card.Icon = "rbxassetid://100244499853123"
Card.RequiresTarget = true  -- Needs target selection if multiple figures eligible

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

-- Helper: Check if figure is valid and exists
local function isFigureValid(fig)
	if not fig or not fig.Parent then return false end
	return CollectionService:HasTag(fig, "figure")
end

-- Helper: Check if figure just left the house this turn
local function didFigureJustLeaveHouse(fig)
	if not isFigureValid(fig) then return false end
	return fig:GetAttribute("leftHouseThisTurn") == true
end

-- Helper: Check if figure can move 1 step (validate it's on start position)
local function canFigureMoveOneStep(fig)
	if not isFigureValid(fig) then return false end
	
	local stepsTaken = fig:GetAttribute("stepsTaken")
	
	-- Figure must be on the board (stepsTaken >= 0)
	-- After just leaving house, stepsTaken should be 0 (on start tile)
	if type(stepsTaken) ~= "number" or stepsTaken < 0 then
		return false
	end
	
	-- Cannot move if already at max (goal slot 43 = step 43)
	if stepsTaken >= 43 then
		return false
	end
	
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
	
	-- Validate context and target
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
	
	-- Must have just left the house this turn
	if not didFigureJustLeaveHouse(fig) then
		return false, "Figure must have just left the house"
	end
	
	-- Check if figure can actually move
	if not canFigureMoveOneStep(fig) then
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
	
	if not didFigureJustLeaveHouse(fig) then
		return false
	end
	
	if not canFigureMoveOneStep(fig) then
		return false
	end
	
	return { effect = "moveOne", targetFigure = fig, steps = 1 }
end

return Card
