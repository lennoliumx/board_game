-- Creates a minimal Card GUI at runtime so CardClient can find it
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

local function createGui()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    if playerGui:FindFirstChild("CardGui") then return end

    local screen = Instance.new("ScreenGui")
    screen.Name = "CardGui"
    screen.ResetOnSpawn = false

    -- Hand frame, bottom-center
    local hand = Instance.new("Frame")
    hand.Name = "HandFrame"
    hand.Size = UDim2.new(0,480,0,200)
    hand.AnchorPoint = Vector2.new(0.5, 1)
    hand.Position = UDim2.new(0.5, 0, 1, -20)
    hand.BackgroundTransparency = 1
    hand.Parent = screen

    -- Create 3 overlapping card slots
    for i = 1, 3 do
        local slot = Instance.new("ImageButton")
        slot.Name = "Slot"..i
        slot.BackgroundTransparency = 0
        slot.AutoButtonColor = false
        slot.AnchorPoint = Vector2.new(0.5, 1)

        local offset = (i - 2) * 120 -- spread
        slot.Position = UDim2.new(0.5, offset, 1, 40) -- hidden slightly below bottom
        slot.Size = UDim2.new(0, 120, 0, 160) -- hidden size
        slot.Parent = hand
        slot.ZIndex = 1

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = slot

        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 1
        stroke.Parent = slot

        local img = Instance.new("ImageLabel")
        img.Name = "CardImage"
        img.BackgroundTransparency = 1
        img.Size = UDim2.new(1,0,1,0)
        img.Position = UDim2.new(0,0,0,0)
        img.Parent = slot

        local useBtn = Instance.new("TextButton")
        useBtn.Name = "UseButton"
        useBtn.Size = UDim2.new(0, 80, 0, 30)
        useBtn.AnchorPoint = Vector2.new(0.5, 0)
        useBtn.Position = UDim2.new(0.5, 0, 0, 8)
        useBtn.Text = "Use"
        useBtn.Visible = false
        useBtn.Parent = slot

        -- Store tween properties for script consumers
        slot:SetAttribute("hiddenPosX", offset)
        slot:SetAttribute("hiddenY", 40)
        -- Small lift to avoid mouse leaving the slot while expanding
        slot:SetAttribute("expandedY", -120)
        slot:SetAttribute("hiddenSizeX", 160)
        slot:SetAttribute("hiddenSizeY", 220)
        slot:SetAttribute("expandedSizeX", 240)
        slot:SetAttribute("expandedSizeY", 340)
        
        -- Create a separate invisible input hitbox so overlapping visuals don't block input
        local input = Instance.new("TextButton")
        input.Name = "Input"..i
        input.AnchorPoint = Vector2.new(0.5, 1)
        input.Position = UDim2.new(0.5, offset, 1, 40)
        input.Size = UDim2.new(0, 100, 0, 160)
        input.BackgroundTransparency = 1
        input.AutoButtonColor = false
        input.ZIndex = 20
        input.Parent = hand

        -- Link names for client logic
        slot:SetAttribute("inputName", input.Name)
    end

    screen.Parent = playerGui
end

createGui()
