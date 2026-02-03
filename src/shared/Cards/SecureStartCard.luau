-- SecureStartCard: Protect a figure that just left the house from capture
-- Robust implementation with full validation and error handling
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Card = {}
Card.Id = "starter_protect_start"
Card.Name = "Starter: Safe Start"
Card.Description = "If a piece left the house this turn, make it immune to capture until your next turn."
Card.Icon = "rbxassetid://89136599721424"
Card.RequiresTarget = true  -- Needs target selection if multiple figures eligible

-- Constants
local DEFAULT_PLAYER_COUNT = 4
local MIN_PROTECTION_TURNS = 1
local MAX_PROTECTION_TURNS = 6  -- Safety cap

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

-- Helper: Check if figure is already protected
local function isFigureAlreadyProtected(fig)
	if not fig then return true end
	local protectedTurns = fig:GetAttribute("protectedTurns")
	return type(protectedTurns) == "number" and protectedTurns > 0
end

-- Helper: Check if the start roll window is open
local function isStartRollWindowOpen(player)
	if not player then return false end
	return player:GetAttribute("awaitingStartRoll") == true
end

-- Helper: Calculate protection duration based on active players
local function calculateProtectionDuration(player)
	local activeCount = player:GetAttribute("activePlayerCount")
	
	-- Validate and default if not set or invalid
	if type(activeCount) ~= "number" or activeCount < 2 then
		activeCount = DEFAULT_PLAYER_COUNT
	end
	
	-- Protection lasts until it's your turn again (skip N-1 other players)
	local turns = math.max(MIN_PROTECTION_TURNS, activeCount - 1)
	turns = math.min(turns, MAX_PROTECTION_TURNS)  -- Safety cap
	
	return turns
end

function Card.CanUse(player, ctx)
	-- Validate player
	if not isPlayerValid(player) then
		return false, "Invalid player"
	end
	
	-- Validate start roll window is open
	if not isStartRollWindowOpen(player) then
		return false, "Can only use right after a piece leaves the house"
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
	
	-- Check figure left house this turn
	if not didFigureJustLeaveHouse(fig) then
		return false, "Figure did not just leave the house"
	end
	
	-- Check if already protected
	if isFigureAlreadyProtected(fig) then
		return false, "Figure is already protected"
	end
	
	return true
end

function Card.OnUse(player, ctx)
	-- Re-validate everything
	if not isPlayerValid(player) then
		return false
	end
	
	if not isStartRollWindowOpen(player) then
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
	
	if isFigureAlreadyProtected(fig) then
		return false
	end
	
	-- Apply protection
	local protectionDuration = calculateProtectionDuration(player)
	fig:SetAttribute("protectedTurns", protectionDuration)
	
	return true
end

return Card
