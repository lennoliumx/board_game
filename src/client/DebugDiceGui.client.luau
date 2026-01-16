-- Debug GUI for setting dice result (testing only)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Only enable in Studio
if not RunService:IsStudio() then return end

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

-- Create GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DebugDiceGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = PlayerGui

local frame = Instance.new("Frame")
frame.Name = "DebugFrame"
frame.Size = UDim2.new(0, 160, 0, 140)
frame.Position = UDim2.new(0, 10, 0.5, -70)
frame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
frame.BorderSizePixel = 0
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 25)
title.Position = UDim2.new(0, 0, 0, 5)
title.BackgroundTransparency = 1
title.Text = "🎲 Debug Dice"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 14
title.Font = Enum.Font.GothamBold
title.Parent = frame

local currentLabel = Instance.new("TextLabel")
currentLabel.Name = "CurrentLabel"
currentLabel.Size = UDim2.new(1, -20, 0, 20)
currentLabel.Position = UDim2.new(0, 10, 0, 30)
currentLabel.BackgroundTransparency = 1
currentLabel.Text = "Next roll: Random"
currentLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
currentLabel.TextSize = 12
currentLabel.Font = Enum.Font.Gotham
currentLabel.TextXAlignment = Enum.TextXAlignment.Left
currentLabel.Parent = frame

-- Number buttons
local buttonContainer = Instance.new("Frame")
buttonContainer.Name = "Buttons"
buttonContainer.Size = UDim2.new(1, -20, 0, 50)
buttonContainer.Position = UDim2.new(0, 10, 0, 55)
buttonContainer.BackgroundTransparency = 1
buttonContainer.Parent = frame

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0, 40, 0, 22)
gridLayout.CellPadding = UDim2.new(0, 5, 0, 5)
gridLayout.Parent = buttonContainer

local forcedValue = nil

for i = 1, 6 do
	local btn = Instance.new("TextButton")
	btn.Name = "Btn" .. i
	btn.Text = tostring(i)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 14
	btn.Font = Enum.Font.GothamBold
	btn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	btn.Parent = buttonContainer
	
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 4)
	btnCorner.Parent = btn
	
	btn.MouseButton1Click:Connect(function()
		forcedValue = i
		currentLabel.Text = "Next roll: " .. i
		currentLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
		remoteEvent:FireServer("DebugSetDice", i)
		
		-- Highlight selected button
		for _, b in ipairs(buttonContainer:GetChildren()) do
			if b:IsA("TextButton") then
				b.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
			end
		end
		btn.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
	end)
end

-- Clear button
local clearBtn = Instance.new("TextButton")
clearBtn.Name = "ClearBtn"
clearBtn.Size = UDim2.new(1, -20, 0, 25)
clearBtn.Position = UDim2.new(0, 10, 0, 110)
clearBtn.Text = "Clear (Random)"
clearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
clearBtn.TextSize = 12
clearBtn.Font = Enum.Font.GothamBold
clearBtn.BackgroundColor3 = Color3.fromRGB(150, 60, 60)
clearBtn.Parent = frame

local clearCorner = Instance.new("UICorner")
clearCorner.CornerRadius = UDim.new(0, 4)
clearCorner.Parent = clearBtn

clearBtn.MouseButton1Click:Connect(function()
	forcedValue = nil
	currentLabel.Text = "Next roll: Random"
	currentLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	remoteEvent:FireServer("DebugSetDice", nil)
	
	for _, b in ipairs(buttonContainer:GetChildren()) do
		if b:IsA("TextButton") then
			b.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		end
	end
end)
