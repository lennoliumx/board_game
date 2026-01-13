-- // Copyright 2026, DeutscherKaleun, All rights reserved. 
local repStorage = game:GetService("ReplicatedStorage")
local workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")
local playersReady = repStorage:WaitForChild("PlayersReady")

local currentMap = workspace:WaitForChild("CurrentMap"):FindFirstChildOfClass("Folder")
local figuresFolder = workspace:WaitForChild("Figures")
local remoteEvent = repStorage.RemoteEvent

local roundSys = {} 

local playerAssignments = {
	["green"] = 0, ["yellow"] = 0, ["blue"] = 0, ["red"] = 0
}

function roundSys.spawnChars()
	-- Map structure assumed: SpielfeldGruen, SpielfeldRot, etc.
	local spawnFields = {
		["green"]  = currentMap.SpielfeldGreen.spawnFields:GetChildren(),
		["red"]    = currentMap.SpielfeldRed.spawnFields:GetChildren(),
		["yellow"] = currentMap.SpielfeldYellow.spawnFields:GetChildren(),
		["blue"]   = currentMap.SpielfeldBlue.spawnFields:GetChildren()
	}

	-- Sort Spawn Fields explicitly to match ID 1-4
	for k, v in pairs(spawnFields) do
		table.sort(v, function(a,b) return a.Name < b.Name end)
	end

	local colorTable = {
		["green"] = Color3.fromRGB(4, 255, 0),
		["red"] = Color3.fromRGB(255, 0, 4),
		["yellow"] = Color3.fromRGB(255, 247, 0),
		["blue"] = Color3.fromRGB(0, 0, 255)
	}

	for color, assignmentInfo in pairs(playerAssignments) do
		if type(assignmentInfo) == "table" then
			local charTemplate = assignmentInfo[2]
			local colorSpawns = spawnFields[color]
			local figuresList = {}

			charTemplate.Archivable = true

			for i = 1, 4 do
				local clone = charTemplate:Clone()
				clone.Name = "Figure_"..color.."_"..i
				clone.Parent = figuresFolder:FindFirstChild(color) or workspace

				-- LOGIC ATTRIBUTES
				clone:SetAttribute("figureID", i)
				clone:SetAttribute("tileIndex", 0) -- 0 = Home Base
				clone:SetAttribute("stepsTaken", -1) -- -1 = In Base, 0 = On Start, 1..39 = Path
				clone:SetAttribute("isGoal", false)

				-- Cleanup & Visuals
				for _, v in pairs(clone:GetChildren()) do
					if v:IsA("Script") or v:IsA("LocalScript") then v:Destroy() end
				end
				clone.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

				local outline = Instance.new("Highlight")
				outline.FillTransparency = 1
				outline.OutlineColor = colorTable[color]
				outline.Adornee = clone
				outline.Parent = clone
				outline.Enabled = true -- Hidden by default
				outline.Name = "SelectionHighlight"

				clone:AddTag("figure")

				local spawnCF = colorSpawns[i].CFrame
				clone:PivotTo(CFrame.new(spawnCF.X, 5, spawnCF.Z))

				-- Idle Anim
				local animator = clone.Humanoid:FindFirstChild("Animator") or Instance.new("Animator", clone.Humanoid)
				local idleAnim = Instance.new("Animation")
				idleAnim.AnimationId = "rbxassetid://507766388"
				local track = animator:LoadAnimation(idleAnim)
				track.Looped = true
				track:Play()

				table.insert(figuresList, clone)
			end
			charTemplate.Archivable = false

			-- Structure: {Player, Character, ListOfFigures}
			table.insert(assignmentInfo, figuresList)
		end
	end
	return playerAssignments
end

-- (Keep the rest of roundSys - assignColor, updateReadyCount, collisionGroups - as they were)
function roundSys.updateReadyCount(PlayerReadyBool)
	if PlayerReadyBool.Value == false then
		PlayerReadyBool.Value = true
		playersReady.Value += 1
	else
		PlayerReadyBool.Value = false
		playersReady.Value -= 1
	end
end

function roundSys.assignColor(player, char)
	for color, info in pairs(playerAssignments) do 
		if type(info) == "table" and info[1] == player then
			playerAssignments[color] = 0 
			return
		end
	end
	for color, info in pairs(playerAssignments) do 
		if info == 0 then
			playerAssignments[color] = {player, char}
			return
		end
	end
end

function roundSys.assignMapCollisionGroups()
	local mapGroup = "MapIgnoreGroup" -- For invisible walls/barriers
	local diceGroup = "DiceGroup"
	local figureGroup = "FigureGroup" -- NEW: dedicated group for players

	local function safeRegister(name)
		pcall(function() PhysicsService:RegisterCollisionGroup(name) end)
	end

	safeRegister(mapGroup)
	safeRegister(diceGroup)
	safeRegister(figureGroup)

	-- 1. Dice interactions
	PhysicsService:CollisionGroupSetCollidable(diceGroup, figureGroup, false) -- Dice passes through players
	PhysicsService:CollisionGroupSetCollidable(diceGroup, mapGroup, true)    -- Dice MUST hit the map floor

	-- 2. Figure interactions
	PhysicsService:CollisionGroupSetCollidable(figureGroup, figureGroup, false) -- Figures pass through each other
	PhysicsService:CollisionGroupSetCollidable(figureGroup, mapGroup, true)    -- Figures walk on map

	-- Apply to Map Barriers
	if currentMap:FindFirstChild("CantCollide") then
		for _, v in pairs(currentMap.CantCollide:GetDescendants()) do
			if v:IsA("BasePart") then v.CollisionGroup = mapGroup end
		end
	end

	-- Apply to Figures (Use the new group)
	for _, fig in pairs(figuresFolder:GetDescendants()) do
		if fig:IsA("BasePart") then fig.CollisionGroup = figureGroup end
	end

	-- Apply to Dice
	local diceRef = repStorage:FindFirstChild("Dice")
	if diceRef and diceRef:FindFirstChild("Dice") then
		diceRef.Dice.CollisionGroup = diceGroup
	end
end

return roundSys
