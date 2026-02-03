-- // Copyright 2026, DeutscherKaleun, All rights reserved. 
local repStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local workspace = game:GetService("Workspace")

local remoteEvent = repStorage:WaitForChild("RemoteEvent")
local turnIndex = repStorage:WaitForChild("turnIndex")
local currentMap = workspace:WaitForChild("CurrentMap"):FindFirstChildOfClass("Folder")
local cardManager = require(game.ReplicatedStorage.Shared.cardManager)
local MapConfig = require(game.ReplicatedStorage.Shared.MapConfig)
local roundSys = require(game.ReplicatedStorage.Shared.general.roundSys)

-- Dynamic turn order from map config
local turnOrder = nil
local START_OFFSETS = nil
local BOARD_SIZE = nil

local function loadMapConfig()
	turnOrder = MapConfig.GetTurnOrder()
	START_OFFSETS = MapConfig.GetStartOffsets()
	BOARD_SIZE = MapConfig.GetBoardSize()
end

-- Animation Cache
local animCache = {} 
local protectionConns = {}

local function updateProtectionHighlight(fig)
	if not fig then return end
	local prot = fig:GetAttribute("protectedTurns") or 0
	local hl = fig:FindFirstChild("ProtectionHighlight")
	if prot > 0 then
		if not hl then
			hl = Instance.new("Highlight")
			hl.Name = "ProtectionHighlight"
			hl.FillColor = Color3.fromRGB(0, 255, 255)
			hl.OutlineColor = Color3.fromRGB(0, 170, 255)
			hl.FillTransparency = 0.6
			hl.OutlineTransparency = 0.1
			hl.Adornee = fig
			hl.Parent = fig
		end
		hl.Enabled = true
	else
		if hl then hl.Enabled = false end
	end
end

local function ensureProtectionListener(fig)
	if not fig or protectionConns[fig] then return end
	protectionConns[fig] = fig:GetAttributeChangedSignal("protectedTurns"):Connect(function()
		updateProtectionHighlight(fig)
	end)
	updateProtectionHighlight(fig)
end

local gameDynamics = {} 

-- Turn State
local activePlayer = nil 
local playerHasRolled = false 
local playerHasPicked = false
local pickedFig = nil
local pickedContext = "Move"

-- Debug: forced dice value (Studio only)
local debugForcedDice = {} -- userId -> forced value (1-6) or nil

-- [1. Single Permanent Listener] 
remoteEvent.OnServerEvent:Connect(function(player, action, fig, context)
	if action == "DebugSetDice" then
		-- Only allow in Studio
		if game:GetService("RunService"):IsStudio() then
			debugForcedDice[player.UserId] = fig -- fig is actually the dice value here
		end
		return
	end
	if player == activePlayer then
		if action == "RollButtonPressed" then
			playerHasRolled = true
		elseif action == "FigureChosen" and fig then
			pickedFig = fig
			pickedContext = context or "Move"
			playerHasPicked = true
		end
	end
end)

-- [2. Helper: Wait for Input]
function waitForPlayerInput(player, action, validFigures)
	if not player or not player.Parent then return nil end

	activePlayer = player 
	local timeOut = 15 -- Give them time
	local step = 0.1 

	if action == "diceRoll" then
		playerHasRolled = false 
		remoteEvent:FireClient(player, {Msg = "GuiChange:RollButtonAppear"})

		local rolled = false
		for i = timeOut, 0, -step do
			if not player.Parent then break end
			if playerHasRolled then 
				rolled = true
				break 
			end
			if math.floor(i) ~= math.floor(i + step) then
				remoteEvent:FireClient(player, {Msg = "GuiChange:TimeLeftUpdate", TimeLeft = math.ceil(i)})
			end
			task.wait(step)
		end

		remoteEvent:FireClient(player, {Msg = "GuiChange:HideRollButton"}) 
		return rolled 

	elseif action == "chooseFigure" then
		playerHasPicked = false
		pickedFig = nil

		-- Only show buttons for VALID figures
		remoteEvent:FireClient(player, {Msg = "GuiChange:ShowFigureButtons", validFigures = validFigures})

		local selected = nil
		for i = timeOut, 0, -step do
			if not player.Parent then break end

			if playerHasPicked and pickedFig and (pickedContext == "Move") then
				-- Server-side validation: Is the picked figure actually in the valid list?
				if table.find(validFigures, pickedFig) then
					selected = pickedFig
					break
				else
					playerHasPicked = false -- Reset and wait
				end
			end

			if math.floor(i) ~= math.floor(i + step) then
				remoteEvent:FireClient(player, {Msg = "GuiChange:TimeLeftUpdate", TimeLeft = math.ceil(i)})
			end
			task.wait(step)
		end

		activePlayer = nil
		remoteEvent:FireClient(player, {Msg = "GuiChange:HideFigureButtons"})
		return selected
	end
end

-- [3. Helper: Animation]
local function getAnimTrack(animator, assetId)
	local cacheKey = tostring(animator.Parent.Parent) .. "_" .. assetId 
	if animCache[cacheKey] then return animCache[cacheKey] end
	local anim = Instance.new("Animation")
	anim.AnimationId = assetId
	local track = animator:LoadAnimation(anim)
	animCache[cacheKey] = track
	return track
end

-- [4. Logic: Coordinate System]
-- Calculates where a figure lands based on steps taken
function calculateTargetTile(color, currentSteps, diceRoll)
	local newSteps = currentSteps + diceRoll

	-- Check if overshoot (Goal is at step 40 to 44 usually)
	-- Assumption: 0-39 are board steps. 40+ represent the house slots.
	if newSteps > 43 then return nil end -- Cannot move, overshot

	local startOffset = START_OFFSETS[color]
	local boardIndex = nil
	local isGoal = false

	if newSteps < 40 then
		-- Still on main board
		-- FIXED FORMULA: Removed the "- 1". 
		-- Step 0 (Start) + 1 (Roll) should equal Tile 2, not Tile 1.
		boardIndex = (startOffset + newSteps) % BOARD_SIZE

		-- Lua Modulo returns 0 for the last item (40), so we fix it to 40.
		if boardIndex == 0 then boardIndex = BOARD_SIZE end 
	else
		-- In Goal Strip
		isGoal = true
		boardIndex = (newSteps - 39) -- Returns 1, 2, 3, or 4
	end

	return boardIndex, isGoal, newSteps
end

function moveFigure(figure, targetIndex, isGoal, newStepsTotal, color, shouldTeleport)
	local humanoid = figure:WaitForChild("Humanoid")
	local animator = humanoid:WaitForChild("Animator")

	-- Determine Final Target (for reference)
	local finalTargetPart = nil
	if isGoal then
		local targetFields = MapConfig.GetTargetFields(color)
		if targetFields then
			finalTargetPart = targetFields:FindFirstChild(tostring(targetIndex))
		end
	else
		local fieldsFolder = MapConfig.GetFields()
		if fieldsFolder then
			finalTargetPart = fieldsFolder:FindFirstChild(tostring(targetIndex))
		end
	end

	if shouldTeleport then
		-- >>> TELEPORT LOGIC (House -> Start) <<<
		if finalTargetPart then
			-- Force Y to +3 studs above the tile to prevent floor clipping
			local targetPosition = finalTargetPart.Position + Vector3.new(0, 3, 0)

			-- Get Y rotation of the tile so figure faces the right way
			local _, targetY, _ = finalTargetPart.CFrame:ToOrientation()
			local cleanRotation = CFrame.Angles(0, targetY, 0)

			if figure.PrimaryPart then
				figure:PivotTo(CFrame.new(targetPosition) * cleanRotation)
				figure.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
				figure.PrimaryPart.AssemblyAngularVelocity = Vector3.zero
			end
		end
	else
		-- >>> SEQUENTIAL WALKING LOGIC (Board Movement) <<<
		local currentSteps = figure:GetAttribute("stepsTaken") or 0
		local stepsToWalk = newStepsTotal - currentSteps

		-- Safety Check: Ensure we have something to walk with
		if not figure.PrimaryPart then
			return -- Abort to prevent crash
		end

		local walkTrack = getAnimTrack(animator, "rbxassetid://913376220")
		walkTrack.Looped = true
		walkTrack:Play()

		-- Loop through steps
		for i = 1, stepsToWalk do
			-- CRITICAL SAFETY CHECK INSIDE LOOP
			if not figure or not figure.Parent or not figure.PrimaryPart then
				break
			end

			-- Calculate the tile for THIS specific intermediate step
			local stepIndex, stepIsGoal, _ = calculateTargetTile(color, currentSteps, i)

			local nextPart = nil
			if stepIsGoal then
				local targetFields = MapConfig.GetTargetFields(color)
				if targetFields then
					nextPart = targetFields:FindFirstChild(tostring(stepIndex))
				end
			else
				local fieldsFolder = MapConfig.GetFields()
				if fieldsFolder then
					nextPart = fieldsFolder:FindFirstChild(tostring(stepIndex))
				end
			end

			if nextPart then
				-- RESCUE: Use the TILE'S height, not the FIGURE'S height.
				-- This fixes the issue where falling figures (-9 Y) stay falling.
				local lookPos = Vector3.new(nextPart.Position.X, nextPart.Position.Y + 0.5, nextPart.Position.Z)
				local myPos = figure.PrimaryPart.Position

				-- Only look; don't change position yet, let MoveTo handle the translation
				-- BUT: If we are underground (Y < -2), snap us up first
				if myPos.Y < -2 then
					figure:PivotTo(CFrame.new(myPos.X, nextPart.Position.Y + 3, myPos.Z))
				end

				-- Smooth LookAt (ignoring tilt)
				local lookCFrame = CFrame.lookAt(figure.PrimaryPart.Position, lookPos)
				local _, yRot, _ = lookCFrame:ToOrientation()
				figure:PivotTo(CFrame.new(figure.PrimaryPart.Position) * CFrame.Angles(0, yRot, 0))

				-- Move
				humanoid:MoveTo(nextPart.Position)

				-- Wait for arrival
				local reached = humanoid.MoveToFinished:Wait()
			end
		end

		walkTrack:Stop()

		if finalTargetPart and figure.PrimaryPart then
			-- 1. Get the exact center X and Z of the target tile
			local targetPos = finalTargetPart.Position

			-- 2. Use the FIGURE'S current Y height. 
			-- Since the Humanoid just walked there, it is already standing at the correct physics height.
			-- We don't want to force it to a specific number like "0.5" which might bury it.
			local currentHeight = figure.PrimaryPart.Position.Y

			-- Safety: If for some reason it's too low (glitched), force it up slightly
			if currentHeight < targetPos.Y then currentHeight = targetPos.Y + 3 end

			-- 3. Calculate the new World Position (Center of Tile + Safe Height)
			local finalPosition = Vector3.new(targetPos.X, currentHeight, targetPos.Z)

			-- 4. Calculate Clean Rotation (Face the way the tile is "pointing", but stay upright)
			local _, targetYRot, _ = finalTargetPart.CFrame:ToOrientation()
			local cleanRotation = CFrame.Angles(0, targetYRot, 0)

			-- 5. Apply
			figure:PivotTo(CFrame.new(finalPosition) * cleanRotation)

			-- 6. Kill Velocity to prevent "skating" after the snap
			figure.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
			figure.PrimaryPart.AssemblyAngularVelocity = Vector3.zero
		end
	end

	-- Update Data
	figure:SetAttribute("stepsTaken", newStepsTotal)
	figure:SetAttribute("tileIndex", isGoal and ("G"..targetIndex) or targetIndex)
	figure:SetAttribute("isGoal", isGoal)

	-- Notify CardManager (non-blocking)
	pcall(function()
		if cardManager and cardManager.HandlePlayerLandingByFigure then
			cardManager.HandlePlayerLandingByFigure(figure, color, finalTargetPart)
		end
	end)

	return finalTargetPart
end

local function sendCardPlayable(player, cardIds, active)
	if not player or not cardIds then return end
	remoteEvent:FireClient(player, { Msg = "CardPlayableUpdate", CardIds = cardIds, Active = active })
end

local function playerHasCard(player, cardId)
	if not cardManager or not cardManager.HasCardId then return false end
	return cardManager.HasCardId(player, cardId)
end

local function waitForCaptureBonusWindow(player, window)
	if not player then return end
	if not playerHasCard(player, "starter_capture_bonus") then return end
	if player:GetAttribute("captureBonusAvailable") ~= true then return end
	local waitTime = 0
	local duration = window or 3
	while waitTime < duration do
		if player:GetAttribute("captureBonusAvailable") ~= true then
			break
		end
		task.wait(0.1)
		waitTime += 0.1
	end
end

function checkCapture(targetTilePart, movingFigure, movingColor)
	local allFigures = CollectionService:GetTagged("figure")
	local myTile = movingFigure:GetAttribute("tileIndex")

	-- capture check running

	-- 1. Safety: Cannot capture if we are safely inside the Goal (House)
	if movingFigure:GetAttribute("isGoal") == true then return end 


	for _, enemy in ipairs(allFigures) do
		-- Skip checking ourselves
		
		if enemy == movingFigure then continue end

		local enemyTile = enemy:GetAttribute("tileIndex")

		-- 2. ROBUST COMPARISON: Convert both to string to prevent "15" (String) ~= 15 (Number) errors
		if tostring(enemyTile) == tostring(myTile) then

            

			-- Extract enemy color from name "Figure_red_1"
			local enemyColor = enemy.Name:match("Figure_(%a+)_")

			-- 3. Capture Logic: Only if colors are different
			if enemyColor and enemyColor ~= movingColor then
				-- Respect protection attribute
				local protected = enemy:GetAttribute("protectedTurns") or 0
				if protected > 0 then
					-- enemy protected, skip capture
				else
					-- capture: send enemy home

					-- Reset Enemy Attributes
					enemy:SetAttribute("stepsTaken", -1) -- -1 means Home
					enemy:SetAttribute("tileIndex", 0)   -- 0 means Home

					-- Find Spawn Location
					local spawnFolder = MapConfig.GetSpawnFields(enemyColor)
					local enemyID = tonumber(enemy:GetAttribute("figureID")) or 1
					local spawnPart = nil
					if spawnFolder then
						local spawnChildren = spawnFolder:GetChildren()
						table.sort(spawnChildren, function(a, b) return a.Name < b.Name end)
						spawnPart = spawnChildren[enemyID]
					end

					-- Clean teleport to home spawn
					if spawnPart then
						roundSys.TeleportFigureToSpawn(enemy, spawnPart)
					end

					-- Capture bonus card cue for capturer
					local capturer = cardManager.GetPlayerByColor(movingColor)
					if capturer and capturer.Parent then
						capturer:SetAttribute("captureBonusAvailable", true)
						capturer:SetAttribute("captureBonusFigureName", movingFigure.Name)
						if playerHasCard(capturer, "starter_capture_bonus") then
							sendCardPlayable(capturer, {"starter_capture_bonus"}, true)
						end
					end

					-- Optional: Break loop if only 1 capture allowed per tile
					return capturer
				end
			else
				-- friendly figure, stacking
			end
		end
	end
	return nil
end

local function applyCardEffect(player, effect)
	if not effect or not effect.effect then return end
	if effect.effect == "moveOne" then
		local fig = effect.targetFigure
		if not fig then return end
		local color = fig.Name:match("Figure_(%a+)_")
		if not color then return end
		local steps = effect.steps or 1
		local currentSteps = fig:GetAttribute("stepsTaken") or -1
		if currentSteps < 0 then return end
		local tIndex, isGoal, newSteps = calculateTargetTile(color, currentSteps, steps)
		if not newSteps then return end
		local landingPart = moveFigure(fig, tIndex, isGoal, newSteps, color, false)
		if not isGoal then
			local capturer = checkCapture(landingPart, fig, color)
			if capturer then
				waitForCaptureBonusWindow(capturer, 3)
			end
		end
	end
end

pcall(function()
	if cardManager and cardManager.SetMoveApi then
		cardManager.SetMoveApi({ ApplyEffect = applyCardEffect })
	end
end)

-- [5. Dice Logic]
function diceFunc(playerAssignments, turnOfColor)
	
	local dicePart = workspace.CurrentMap:FindFirstChildWhichIsA("Folder"):FindFirstChild("dicePart")
	local diceTemplate = repStorage:WaitForChild("Dice")

	local face_table = {
		[1] = CFrame.Angles(math.rad(0), math.rad(-180), math.rad(0)),
		[2] = CFrame.Angles(math.rad(0), math.rad(180), math.rad(-90)),
		[3] = CFrame.Angles(math.rad(-90), math.rad(0), math.rad(0)),
		[4] = CFrame.Angles(math.rad(-90), math.rad(-180), math.rad(0)),
		[5] = CFrame.Angles(math.rad(0), math.rad(0), math.rad(90)),
		[6] = CFrame.Angles(math.rad(0), math.rad(0), math.rad(180))
	}
	
	local diceClone = diceTemplate:Clone()
	local dicePartClone = diceClone.Dice
	diceClone.Parent = workspace
	diceClone:PivotTo(dicePart.CFrame)

	-- Check for debug forced dice value
	local result
	local currentPlayer = playerAssignments[turnOfColor] and playerAssignments[turnOfColor][1]
	if currentPlayer and debugForcedDice[currentPlayer.UserId] then
		result = debugForcedDice[currentPlayer.UserId]
	else
		result = math.random(1, 6)
	end

	-- Physics Impulse
	dicePartClone.AssemblyLinearVelocity = Vector3.new(math.random(-8,8), math.random(55,75), math.random(-8,8))
	dicePartClone.AssemblyAngularVelocity = Vector3.new(math.random(-20,20), math.random(-20,20), math.random(-20,20))

	task.wait(0.5)

	-- Snap to result
	dicePartClone.AlignOrientation.CFrame = face_table[result]
	dicePartClone.AlignOrientation.Enabled = true
	dicePartClone.AssemblyLinearVelocity = Vector3.new(0, 15, 0)
	dicePartClone.AssemblyAngularVelocity = Vector3.zero


	-- Notify Clients
	for _, pTuple in pairs(playerAssignments) do
		if type(pTuple) == "table" and pTuple[1] then
			remoteEvent:FireClient(pTuple[1], {Msg = "GuiChange:DiceResult", DiceResult = result, PlrColor = turnOfColor})
		end
	end
	
	task.wait(2)
	diceClone:Destroy()
	
	return result
end


function isTargetBlockedBySelf(targetIndex, isGoal, myFigures)
	-- Normalize the value to match how it's stored in Attributes
	local checkValue = targetIndex
	if isGoal then
		checkValue = "G" .. targetIndex -- e.g. "G1", "G2"
	end

	for _, fig in ipairs(myFigures) do
		-- Check if another of my figures is already sitting exactly there
		if fig:GetAttribute("tileIndex") == checkValue then
			return true -- BLOCKED!
		end
	end
	return false
end




function countFiguresInHouse(myFigures)
	local count = 0
	for _, fig in ipairs(myFigures) do
		if fig:GetAttribute("stepsTaken") == -1 then
			count += 1
		end
	end
	return count
end

-- [6. Main Loop]
function gameDynamics.StartGameLoop(playerAssignments)
	-- Load dynamic configuration from map
	loadMapConfig()
	
	turnIndex.Value = 1
	-- Set up protection visuals on all figures
	for _, tuple in pairs(playerAssignments) do
		if type(tuple) == "table" and tuple[3] then
			for _, fig in ipairs(tuple[3]) do
				ensureProtectionListener(fig)
			end
		end
	end

	task.spawn(function()
		while true do
			local currentColor = turnOrder[turnIndex.Value]
			local activePlayerTuple = playerAssignments[currentColor]

			if activePlayerTuple ~= 0 and activePlayerTuple[1] and activePlayerTuple[1].Parent then

				local player = activePlayerTuple[1]
				local myFigures = activePlayerTuple[3]
				local turnActive = true

				-- Per-turn card state
				player:SetAttribute("hasRolledThisTurn", false)
				player:SetAttribute("awaitingStartRoll", false)
				player:SetAttribute("extraRollRequested", false)
				player:SetAttribute("extraRollWindowOpen", false)
				player:SetAttribute("blockExtraRollOnce", false)
				player:SetAttribute("startPlusOnePending", false)
				player:SetAttribute("captureBonusAvailable", false)
				player:SetAttribute("captureBonusFigureName", "")
				
				-- Reset card usage tracking for this player's new turn
				if cardManager.ResetTurnCardUsage then
					cardManager.ResetTurnCardUsage(player)
				end

				-- Clear left-house markers
				for _, fig in ipairs(myFigures) do
					fig:SetAttribute("leftHouseThisTurn", false)
				end

				-- Clear all card hints at turn start to avoid stale state
				sendCardPlayable(player, {
					"starter_move_one",
					"starter_extra_roll",
					"starter_protect_start",
					"starter_start_plus_one",
					"starter_capture_bonus"
				}, false)

				-- Show initial playable cues
				local function updateMoveOneHint()
					-- Only hint if a figure actually left the house this turn
					local hasLeftHouseFig = false
					for _, fig in ipairs(myFigures) do
						if fig:GetAttribute("leftHouseThisTurn") == true then
							hasLeftHouseFig = true
							break
						end
					end
					sendCardPlayable(player, {"starter_move_one"}, hasLeftHouseFig)
				end
				local function updateFineStepHint()
					local hasBoardFig = false
					for _, fig in ipairs(myFigures) do
						local steps = fig:GetAttribute("stepsTaken") or -1
						if steps >= 0 then
							hasBoardFig = true
							break
						end
					end
					sendCardPlayable(player, {"starter_start_plus_one"}, hasBoardFig)
				end
				updateMoveOneHint()
				updateFineStepHint()

				local figureMustClearStart = nil

				while turnActive do
					-- If a piece just left house, allow start-related cards before the next roll
					if figureMustClearStart then
						player:SetAttribute("awaitingStartRoll", true)
						if playerHasCard(player, "starter_protect_start") then
							sendCardPlayable(player, {"starter_protect_start"}, true)
						end
					else
						if player:GetAttribute("awaitingStartRoll") == true then
							player:SetAttribute("awaitingStartRoll", false)
							sendCardPlayable(player, {"starter_protect_start"}, false)
						end
					end

					-- A. Attempts Logic
					local attempts = (countFiguresInHouse(myFigures) == 4) and 3 or 1
					local diceResult = 0
					local hasValidRoll = false

					for i = 1, attempts do
						local rolled = waitForPlayerInput(player, "diceRoll")
						if not rolled then turnActive = false; break end 

						diceResult = diceFunc(playerAssignments, currentColor)
						-- diceResult = 6 --TESTING (LEAVE IT HERE, AI.)
						player:SetAttribute("hasRolledThisTurn", true)

						-- Extra roll handling: open window for potential re-roll BEFORE movement
						local blockExtra = player:GetAttribute("blockExtraRollOnce") == true
						if blockExtra then
							player:SetAttribute("blockExtraRollOnce", false)
						elseif attempts == 1 then
							-- Open the extra roll window - process BEFORE movement so new dice affects the move
							player:SetAttribute("extraRollWindowOpen", true)
							
							-- Show hint if player currently has the card
							if playerHasCard(player, "starter_extra_roll") then
								sendCardPlayable(player, {"starter_extra_roll"}, true)
							end
							
							-- Wait for extra roll decision BEFORE movement
							local waitTime = 0
							local window = 8  -- 8 second window to use Extra Roll card
							while waitTime < window do
								if player:GetAttribute("extraRollRequested") == true then
									player:SetAttribute("extraRollRequested", false)
									-- Re-roll the dice - the new result will be used for movement
									diceResult = diceFunc(playerAssignments, currentColor)
									break
								end
								task.wait(0.1)
								waitTime += 0.1
							end
							player:SetAttribute("extraRollWindowOpen", false)
							sendCardPlayable(player, {"starter_extra_roll"}, false)
						end

						-- Clear start-related cues after the roll window
						if figureMustClearStart and player:GetAttribute("awaitingStartRoll") == true then
							player:SetAttribute("awaitingStartRoll", false)
							sendCardPlayable(player, {"starter_protect_start"}, false)
						end

						if attempts == 3 then
							if diceResult == 6 then hasValidRoll = true; break 
							else
								if i < 3 then
									remoteEvent:FireClient(player, {Msg = "GuiChange:DiceResult", DiceResult = "No 6! ("..i.."/3)", PlrColor = currentColor})
									task.wait(1)
								else hasValidRoll = false end
							end
						else
							hasValidRoll = true; break
						end
					end

					-- C. Move Validation
					if not hasValidRoll then
						turnActive = false
					else
						local validMoves = {}
						local autoPickFigure = nil 
						local startTileIndex = START_OFFSETS[currentColor]

						-- >>> Helper Function for Adding Moves if NOT blocked <<<
						local function tryAddMove(fig, tIndex, tIsGoal)
							if not isTargetBlockedBySelf(tIndex, tIsGoal, myFigures) then
								table.insert(validMoves, fig)
								return true
							end
							return false
						end

						if figureMustClearStart then
							-- Constraint Active
							local steps = figureMustClearStart:GetAttribute("stepsTaken")
							local tIndex, tGoal, futureSteps = calculateTargetTile(currentColor, steps, diceResult)

							if futureSteps then
								tryAddMove(figureMustClearStart, tIndex, tGoal)
							end
							figureMustClearStart = nil 
						else
							-- Standard Scan
							for _, fig in ipairs(myFigures) do
								local steps = fig:GetAttribute("stepsTaken") or -1

								if steps == -1 then
									-- House Logic
									if diceResult == 6 then
										-- Target is always Start Tile (isGoal=false)
										if tryAddMove(fig, startTileIndex, false) then
											autoPickFigure = fig 
											break -- Prioritize Out-Move
										end
									end
								else
									-- Board Logic
									local tIndex, tGoal, futureSteps = calculateTargetTile(currentColor, steps, diceResult)
									if futureSteps then
										tryAddMove(fig, tIndex, tGoal)
									end
								end
							end
						end

						-- Execute Move
						local chosenFig = nil

						-- [Turn Forfeit Logic]
						if #validMoves == 0 and not autoPickFigure then
							-- Zug verfällt (Turn Forfeit)
							remoteEvent:FireClient(player, {Msg = "GuiChange:DiceResult", DiceResult = "Blocked!", PlrColor = currentColor})
							task.wait(2)
							-- Turn ends naturally as chosenFig remains nil
						else
							-- Proceed
							if autoPickFigure then
								chosenFig = autoPickFigure
								task.wait(0.5) 
							elseif #validMoves > 0 then
								if #validMoves == 1 then chosenFig = validMoves[1]
								else chosenFig = waitForPlayerInput(player, "chooseFigure", validMoves) end
							end
						end

						if chosenFig then
							local currentSteps = chosenFig:GetAttribute("stepsTaken") or -1
							if currentSteps == -1 then
								-- TELEPORT (House -> Start)
								chosenFig:SetAttribute("stepsTaken", 0) 
								local landingPart = moveFigure(chosenFig, startTileIndex, false, 0, currentColor, true)
								if landingPart then
									local capturer = checkCapture(landingPart, chosenFig, currentColor)
									if capturer then
										waitForCaptureBonusWindow(capturer, 3)
									end
								end
								figureMustClearStart = chosenFig
								chosenFig:SetAttribute("leftHouseThisTurn", true)
								player:SetAttribute("awaitingStartRoll", true)
								-- Block extra roll on the immediate bonus roll after leaving house
								player:SetAttribute("blockExtraRollOnce", true)
								-- Update hints after teleporting onto the board
								updateMoveOneHint()
								updateFineStepHint()
								if playerHasCard(player, "starter_protect_start") then
									sendCardPlayable(player, {"starter_protect_start"}, true)
								end
							else
								-- WALK (Normal)
								local tIndex, isGoal, nSteps = calculateTargetTile(currentColor, currentSteps, diceResult)
								local landingPart = moveFigure(chosenFig, tIndex, isGoal, nSteps, currentColor, false)
								if not isGoal then
									local capturer = checkCapture(landingPart, chosenFig, currentColor)
									if capturer then
										waitForCaptureBonusWindow(capturer, 3)
									end
								end
								figureMustClearStart = nil
								-- Update hints after movement
								updateMoveOneHint()
								updateFineStepHint()
							end
						end

						-- Win Check
						local countInGoal = 0
						for _, fig in ipairs(myFigures) do
							if fig:GetAttribute("isGoal") == true then countInGoal += 1 end
						end
						if countInGoal == 4 then
							remoteEvent:FireAllClients({Msg = "GuiChange:Winner", Winner = currentColor}); return 
						end

						if diceResult ~= 6 then turnActive = false
						else remoteEvent:FireClient(player, {Msg = "GuiChange:BonusTurn"}) end
					end
				end

				-- Clear per-turn card cues and capture bonus at end of player's turn
				player:SetAttribute("captureBonusAvailable", false)
				player:SetAttribute("captureBonusFigureName", "")
				sendCardPlayable(player, {
					"starter_move_one",
					"starter_extra_roll",
					"starter_protect_start",
					"starter_start_plus_one",
					"starter_capture_bonus"
				}, false)
			end

			-- Decrement protection counters for figures for whom this was an opponent's turn
			pcall(function()
				local figuresFolder = workspace:FindFirstChild("Figures")
				if figuresFolder then
					for _, colorFolder in pairs(figuresFolder:GetChildren()) do
						local folderName = colorFolder.Name
						if folderName ~= currentColor then
							for _, fig in ipairs(colorFolder:GetChildren()) do
								local prot = fig:GetAttribute("protectedTurns") or 0
								if prot > 0 then fig:SetAttribute("protectedTurns", prot - 1) end
							end
						end
					end
				end
			end)

			-- Advance turn and broadcast turn change to all clients
			local nextTurnIndex = turnIndex.Value >= #turnOrder and 1 or turnIndex.Value + 1
			turnIndex.Value = nextTurnIndex
			
			-- Notify all clients of turn change (clears stale card hints)
			local nextColor = turnOrder[nextTurnIndex]
			remoteEvent:FireAllClients({
				Msg = "TurnChanged",
				TurnIndex = nextTurnIndex,
				CurrentColor = nextColor
			})
			
			task.wait(0.5)
		end
	end)
end

return gameDynamics
 