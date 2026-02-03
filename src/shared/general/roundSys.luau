-- // Copyright 2026, DeutscherKaleun, All rights reserved. 
local repStorage = game:GetService("ReplicatedStorage")
local workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")
local playersReady = repStorage:WaitForChild("PlayersReady")

local MapConfig = require(repStorage:WaitForChild("Shared"):WaitForChild("MapConfig"))

local currentMap = workspace:WaitForChild("CurrentMap"):FindFirstChildOfClass("Folder")
local figuresFolder = workspace:WaitForChild("Figures")
local remoteEvent = repStorage.RemoteEvent

local roundSys = {} 

-- Dynamic player assignments based on map config
local playerAssignments = nil

-- Pre-register collision groups so they're available during figure spawning
local function ensureCollisionGroupsRegistered()
	local function safeRegister(name)
		pcall(function() PhysicsService:RegisterCollisionGroup(name) end)
	end
	safeRegister("MapIgnoreGroup")
	safeRegister("DiceGroup")
	safeRegister("FigureGroup")
	
	-- Set collision rules
	PhysicsService:CollisionGroupSetCollidable("DiceGroup", "FigureGroup", false)
	PhysicsService:CollisionGroupSetCollidable("DiceGroup", "MapIgnoreGroup", true)
	PhysicsService:CollisionGroupSetCollidable("FigureGroup", "FigureGroup", false)
	PhysicsService:CollisionGroupSetCollidable("FigureGroup", "MapIgnoreGroup", true)
end

-- Register collision groups immediately on module load
ensureCollisionGroupsRegistered()

-- Helper: Cleanly teleport a figure to a spawn part without physics scatter
local function teleportFigureToSpawn(figure, spawnPart)
	if not figure or not spawnPart then return end
	
	local targetCFrame = CFrame.new(spawnPart.CFrame.X, 5, spawnPart.CFrame.Z)
	
	-- Temporarily anchor all parts, reset velocities, then position
	local partsToRestore = {}
	for _, part in ipairs(figure:GetDescendants()) do
		if part:IsA("BasePart") then
			-- Store original anchor state
			partsToRestore[part] = part.Anchored
			-- Reset velocities
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
			-- Temporarily anchor
			part.Anchored = true
		end
	end
	
	-- Move the figure
	figure:PivotTo(targetCFrame)
	
	-- Wait a frame for physics to register the new position
	task.defer(function()
		-- Restore original anchor states
		for part, wasAnchored in pairs(partsToRestore) do
			if part and part.Parent then
				part.Anchored = wasAnchored
				-- Final velocity reset after unanchoring
				part.AssemblyLinearVelocity = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end)
end

-- Expose for use by other modules
roundSys.TeleportFigureToSpawn = teleportFigureToSpawn

local function initPlayerAssignments()
	if not playerAssignments then
		playerAssignments = MapConfig.CreatePlayerAssignments()
	end
	return playerAssignments
end

function roundSys.spawnChars()
	initPlayerAssignments()
	
	-- Build spawn fields dynamically from map config (new structure: scriptRelevant/spawnFields/{slot}/)
	local spawnFields = {}
	local turnOrder = MapConfig.GetTurnOrder()
	
	-- Ensure figure folders exist for each slot in turn order
	for _, slotName in ipairs(turnOrder) do
		if not figuresFolder:FindFirstChild(slotName) then
			local newFolder = Instance.new("Folder")
			newFolder.Name = slotName
			newFolder.Parent = figuresFolder
		end
	end
	
	for _, slotName in ipairs(turnOrder) do
		local slotSpawnFolder = MapConfig.GetSpawnFields(slotName)
		if slotSpawnFolder then
			spawnFields[slotName] = slotSpawnFolder:GetChildren()
		end
	end

	-- Sort Spawn Fields explicitly to match ID 1-4
	for k, v in pairs(spawnFields) do
		table.sort(v, function(a,b) return a.Name < b.Name end)
	end

	-- Get colors from map config
	local colorTable = MapConfig.GetFigureColors()

	for slotName, assignmentInfo in pairs(playerAssignments) do
		if type(assignmentInfo) == "table" then
			local charTemplate = assignmentInfo[2]
			local slotSpawns = spawnFields[slotName]
			if not slotSpawns then continue end
			
			local figuresList = {}

			charTemplate.Archivable = true

			for i = 1, 4 do
				local clone = charTemplate:Clone()
				clone.Name = "Figure_"..slotName.."_"..i
				clone.Parent = figuresFolder:FindFirstChild(slotName) or workspace

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
				outline.OutlineColor = colorTable[slotName] or Color3.fromRGB(200, 200, 200)
				outline.Adornee = clone
				outline.Parent = clone
				outline.Enabled = true 
				outline.Name = "SelectionHighlight"

				clone:AddTag("figure")

				-- Set collision group immediately on spawn to prevent figure-figure collisions
				for _, part in pairs(clone:GetDescendants()) do
					if part:IsA("BasePart") then
						part.CollisionGroup = "FigureGroup"
					end
				end
				if clone.PrimaryPart and clone.PrimaryPart:IsA("BasePart") then
					clone.PrimaryPart.CollisionGroup = "FigureGroup"
				end

				-- Use clean teleport to prevent physics scatter
				teleportFigureToSpawn(clone, slotSpawns[i])

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
	
	-- Broadcast config to clients
	MapConfig.BroadcastToClients()
	
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
	initPlayerAssignments()
	
	-- First check if player already has a slot
	for slotName, info in pairs(playerAssignments) do 
		if type(info) == "table" and info[1] == player then
			playerAssignments[slotName] = 0 
			return
		end
	end
	
	-- Assign to first available slot in turn order
	local turnOrder = MapConfig.GetTurnOrder()
	for _, slotName in ipairs(turnOrder) do
		if playerAssignments[slotName] == 0 then
			playerAssignments[slotName] = {player, char}
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

	-- Apply to Map Barriers (check both old and new structure)
	local scriptRelevant = MapConfig.GetScriptRelevant()
	local cantCollideFolder = nil
	if scriptRelevant then
		cantCollideFolder = scriptRelevant:FindFirstChild("CantCollide")
	end
	if not cantCollideFolder then
		cantCollideFolder = currentMap:FindFirstChild("CantCollide")
	end
	
	if cantCollideFolder then
		for _, v in pairs(cantCollideFolder:GetDescendants()) do
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
