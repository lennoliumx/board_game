-- // Copyright 2026, DeutscherKaleun, All rights reserved.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local LocalPlayer = Players.LocalPlayer
local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

local GUIs = script.Parent.Parent:WaitForChild("PlayerGui")
local readyGui = GUIs:WaitForChild("ReadyGui")
local readyBttn = readyGui:WaitForChild("PlayButton")
local readyStatus = readyGui:WaitForChild("ReadyStatus")
local roundStatus = readyGui:WaitForChild("RoundStatus")
local rollButton = readyGui:WaitForChild("RollButton")
local timerGUI = readyGui:WaitForChild("timerGUI")
local figureGuis = GUIs:WaitForChild("FigureGui") -- Ensure this ScreenGui exists

local remoteEvent = game.ReplicatedStorage:WaitForChild("RemoteEvent")
local PlayerReadyBool = LocalPlayer:WaitForChild("Backpack"):WaitForChild("Ready")

local selectionContext = "Move"

local function clearSelectors()
	-- 1. Remove the active billboard clones
	for _, child in pairs(figureGuis:GetChildren()) do
		if child.Name:match("ActiveSelector_") then
			child:Destroy()
		end
	end
end


-- [Input Handlers]
local eventHandlers = {
	["updateRoundGuiStartingRound"] = function(p) 
		roundStatus.Text = "Game Starting!" 
		readyBttn.Visible = false
		readyStatus.Visible = false
	end,
	["GuiChange:DiceResult"] = function(p) 
		roundStatus.Text = p.PlrColor .. " rolled a " .. p.DiceResult 
	end,
	["GuiChange:RollButtonAppear"] = function(p) 
		rollButton.Visible = true 
		timerGUI.Visible = true 
		roundStatus.Text = "Your Turn!"
	end,
	["GuiChange:TimeLeftUpdate"] = function(p) timerGUI.Text = tostring(p.TimeLeft) end,
	["GuiChange:HideRollButton"] = function(p) 
		rollButton.Visible = false 
		timerGUI.Visible = false 
	end,
	["GuiChange:ShowFigureButtons"] = function(p) 
		clearSelectors() -- Safety wipe before showing new ones
		selectionContext = p.Context or "Move"

		local validFigures = p.validFigures or {}
		local template = figureGuis:WaitForChild("SelectionBillboard") -- We will create this below

		for _, fig in ipairs(validFigures) do
			-- A. Visual Highlight (Optional, keeps the neon outline)
			local hl = fig:FindFirstChild("SelectionHighlight")
			if hl then hl.Enabled = true end

			-- B. Billboard Button Logic
			local bbClone = template:Clone()
			bbClone.Name = "ActiveSelector_" .. fig.Name -- Unique name for cleanup

			-- Attach to the figure's Head or PrimaryPart so it floats above
			bbClone.Adornee = fig:FindFirstChild("Head") or fig.PrimaryPart
			bbClone.Enabled = true
			bbClone.Parent = figureGuis -- Must be in PlayerGui to be clickable

			-- Connect the specific button inside this billboard
			local actionBtn = bbClone:FindFirstChild("SelectButton")
			if actionBtn then
				actionBtn.Activated:Connect(function()
					-- Fire the specific figure instance to server
					remoteEvent:FireServer("FigureChosen", fig, selectionContext)

					-- Instant feedback: Hide all buttons immediately
					clearSelectors()
				end)
			else
				-- Selection template missing button
			end
		end

		timerGUI.Visible = true 
		roundStatus.Text = "Choose a piece!"
	end,

	["GuiChange:HideFigureButtons"] = function(p) 
		clearSelectors()
		selectionContext = "Move"
		timerGUI.Visible = false
	end,
	["GuiChange:BonusTurn"] = function(p)
		roundStatus.Text = "Rolled a 6! Roll again!"
	end,
	["GuiChange:Winner"] = function(p)
		roundStatus.Text = p.Winner .. " WINS!"
	end,
	["changeCam"] = function(p) setupCamera() end,
	["updateRoundGuiNotEnoughPlayers"] = function(p) roundStatus.Text = "Not enough players!" end
}

remoteEvent.OnClientEvent:Connect(function(params)
	if eventHandlers[params.Msg] then
		eventHandlers[params.Msg](params)
	end
end)

-- Button Setup
readyBttn.Activated:Connect(function()
	PlayerReadyBool.Value = not PlayerReadyBool.Value
	readyStatus.Text = PlayerReadyBool.Value and "Ready" or "Not Ready"
	remoteEvent:FireServer("ReadyButtonPressed", PlayerReadyBool, char)
end)

rollButton.Activated:Connect(function()
	rollButton.Visible = false
	remoteEvent:FireServer("RollButtonPressed")
end)


function setupCamera()
	local camera = workspace.CurrentCamera
	local focusPart = workspace:WaitForChild("CameraFocus") -- Ensure this part exists!

	-- Disable default controls
	local playerModule = require(LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
	playerModule:GetControls():Disable()

	-- Config
	local CFG = {
		ROT_SPEED = 5,
		SENSITIVITY = 0.005,
		ZOOM_SPEED = 5,
		MIN_DIST = 10,
		MAX_DIST = 200,
		MIN_ELEV = math.rad(10),
		MAX_ELEV = math.rad(80)
	}

	-- State
	local state = {
		dist = 70,
		azimuth = 0,
		elevation = math.rad(45),
		turnInput = 0,
		pitchInput = 0,
		isRightDown = false
	}

	camera.CameraType = Enum.CameraType.Scriptable

	-- Keyboard Input
	local function handleKey(actionName, inputState, _)
		local val = (inputState == Enum.UserInputState.Begin) and 1 or 0
		if actionName == "CamRight" then state.turnInput = val 
		elseif actionName == "CamLeft" then state.turnInput = -val 
		elseif actionName == "CamUp" then state.pitchInput = val 
		elseif actionName == "CamDown" then state.pitchInput = -val end
	end

	ContextActionService:BindAction("CamRight", handleKey, false, Enum.KeyCode.D)
	ContextActionService:BindAction("CamLeft", handleKey, false, Enum.KeyCode.A)
	ContextActionService:BindAction("CamUp", handleKey, false, Enum.KeyCode.W)
	ContextActionService:BindAction("CamDown", handleKey, false, Enum.KeyCode.S)

	-- Mouse/Touch Input
	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.UserInputType == Enum.UserInputType.MouseWheel then
			state.dist = math.clamp(state.dist - (input.Position.Z * CFG.ZOOM_SPEED), CFG.MIN_DIST, CFG.MAX_DIST)
		elseif (input.UserInputType == Enum.UserInputType.MouseMovement and state.isRightDown) or input.UserInputType == Enum.UserInputType.Touch then
			state.azimuth = state.azimuth - (input.Delta.X * CFG.SENSITIVITY)
			state.elevation = math.clamp(state.elevation + (input.Delta.Y * CFG.SENSITIVITY), CFG.MIN_ELEV, CFG.MAX_ELEV)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gp)
		if not gp and input.UserInputType == Enum.UserInputType.MouseButton2 then
			state.isRightDown = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			state.isRightDown = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end)

	-- Render Loop
	RunService.RenderStepped:Connect(function(dt)
		if not focusPart then return end

		-- Update Keyboard State
		state.azimuth += state.turnInput * CFG.ROT_SPEED * dt
		state.elevation = math.clamp(state.elevation + (state.pitchInput * CFG.ROT_SPEED * dt), CFG.MIN_ELEV, CFG.MAX_ELEV)

		-- Calculate Spherical Coordinates
		local hRadius = state.dist * math.cos(state.elevation)
		local x = focusPart.Position.X + (hRadius * math.sin(state.azimuth))
		local z = focusPart.Position.Z + (hRadius * math.cos(state.azimuth))
		local y = focusPart.Position.Y + (state.dist * math.sin(state.elevation))

		camera.CFrame = CFrame.lookAt(Vector3.new(x, y, z), focusPart.Position)
	end)
end

function MaxDistanceForHighlights()
	local MAX_DISTANCE = 200
	local HIGHLIGHT_TAG = "outline"

	-- Optimized: Use Stepped or perform check less frequently if lagging
	RunService.Heartbeat:Connect(function()
		local camera = workspace.CurrentCamera
		if not camera then return end
		local camPos = camera.CFrame.Position

		for _, highlight in CollectionService:GetTagged(HIGHLIGHT_TAG) do
			if highlight.Parent then
				local dist = (camPos - highlight.Parent:GetPivot().Position).Magnitude
				highlight.Enabled = (dist <= MAX_DISTANCE)
			end
		end
	end)
end

MaxDistanceForHighlights()
