-- Client-side Card GUI handler
-- Handles card display, animations, and user interactions
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer
local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

local PlayerGui = script.Parent.Parent:WaitForChild("PlayerGui")
local cardGui = PlayerGui:WaitForChild("CardGui")

local isTouch = UserInputService.TouchEnabled

-- ============================================================================
-- STATE
-- ============================================================================
local slotConnections = {}    -- slot -> {enter, leave, activated}
local slotStates = {}         -- slot -> {expanded, hinted, lastClickTime}
local playableCardIds = {}    -- cardId -> true/false
local useConnections = {}     -- slot -> connection (legacy)

local COLLAPSE_DELAY = 0.12
local CLICK_DEBOUNCE = 0.3    -- Seconds between clicks on same card

-- Cards that require selecting a figure target
local CARD_REQUIRES_TARGET = {
	starter_move_one = true,
	starter_protect_start = true,
	starter_start_plus_one = true,
}

-- Error feedback sound
local errorSound = Instance.new("Sound")
errorSound.SoundId = "rbxassetid://9113869786"
errorSound.Volume = 0.5
errorSound.Parent = SoundService

-- ============================================================================
-- TWEEN HELPERS
-- ============================================================================

local function tweenSlot(slot, toExpanded)
	if not slot or not slot.Parent then return end
	
	local offset = slot:GetAttribute("hiddenPosX") or 0
	local hiddenY = slot:GetAttribute("hiddenY") or 40
	local expandedY = slot:GetAttribute("expandedY") or -160
	local hintY = slot:GetAttribute("hintY") or (hiddenY - 20)
	local hW = slot:GetAttribute("hiddenSizeX") or 120
	local hH = slot:GetAttribute("hiddenSizeY") or 160
	local eW = slot:GetAttribute("expandedSizeX") or 180
	local eH = slot:GetAttribute("expandedSizeY") or 260
	local isHinted = slotStates[slot] and slotStates[slot].hinted == true

	local goalPos
	local goalSize
	if toExpanded then
		goalPos = UDim2.new(0.5, offset, 1, expandedY)
		goalSize = UDim2.new(0, eW, 0, eH)
		-- Bring to front when expanded
		slot.ZIndex = 10
	elseif isHinted then
		goalPos = UDim2.new(0.5, offset, 1, hintY)
		goalSize = UDim2.new(0, hW, 0, hH)
		-- Normal z-index when not expanded
		slot.ZIndex = 1
	else
		goalPos = UDim2.new(0.5, offset, 1, hiddenY)
		goalSize = UDim2.new(0, hW, 0, hH)
		-- Normal z-index when not expanded
		slot.ZIndex = 1
	end
	
	-- Also update ZIndex for all descendants so card image/text stays on top
	for _, child in ipairs(slot:GetDescendants()) do
		if child:IsA("GuiObject") then
			child.ZIndex = toExpanded and 11 or 2
		end
	end

	local props = {Position = goalPos, Size = goalSize}
	local tween = TweenService:Create(slot, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)

	local ok, err = pcall(function() tween:Play() end)
	if not ok then
		-- Fallback: apply final values directly
		slot.Position = goalPos
		slot.Size = goalSize
	end

	-- no separate Use button; whole card/input is clickable

	-- also tween input hitbox if present (keep it aligned)
	local hand = slot.Parent
	local inputName = slot:GetAttribute("inputName")
	if hand and inputName then
		local input = hand:FindFirstChild(inputName)
		if input then
			local inputTween = TweenService:Create(input, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = goalPos, Size = goalSize})
			pcall(function() inputTween:Play() end)
		end
	end
end

local function tweenSlotHint(slot, toHinted)
	if not slot then return end
	local offset = slot:GetAttribute("hiddenPosX") or 0
	local hiddenY = slot:GetAttribute("hiddenY") or 40
	local hintY = slot:GetAttribute("hintY") or (hiddenY - 20)
	local hW = slot:GetAttribute("hiddenSizeX") or 120
	local hH = slot:GetAttribute("hiddenSizeY") or 160
	local goalPos = UDim2.new(0.5, offset, 1, toHinted and hintY or hiddenY)
	local goalSize = UDim2.new(0, hW, 0, hH)
	
	-- Only tween if position is actually different from current position
	if slot.Position == goalPos then return end
	
	local tween = TweenService:Create(slot, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = goalPos, Size = goalSize})
	pcall(function() tween:Play() end)

	local hand = slot.Parent
	local inputName = slot:GetAttribute("inputName")
	if hand and inputName then
		local input = hand:FindFirstChild(inputName)
		if input then
			local inputTween = TweenService:Create(input, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = goalPos, Size = goalSize})
			pcall(function() inputTween:Play() end)
		end
	end
end

local function setSlotHint(slot, on)
	if not slot or not slot.Parent then return end
	slotStates[slot] = slotStates[slot] or {}
	slotStates[slot].hinted = on
	if slotStates[slot].expanded then return end
	tweenSlotHint(slot, on)
end

local function clearAllPlayableHints()
	-- Clear all playable states
	table.clear(playableCardIds)
	
	if not cardGui then return end
	local handFrame = cardGui:FindFirstChild("HandFrame")
	if not handFrame then return end
	
	for i = 1, 3 do
		local slot = handFrame:FindFirstChild("Slot"..i)
		if slot then
			setSlotHint(slot, false)
		end
	end
end

local function updatePlayableHints()
	if not cardGui then return end
	local handFrame = cardGui:FindFirstChild("HandFrame")
	if not handFrame then return end
	
	for i = 1, 3 do
		local slot = handFrame:FindFirstChild("Slot"..i)
		if slot and slot.Visible then
			local cardId = slot:GetAttribute("cardId")
			local shouldHint = cardId and cardId ~= "" and playableCardIds[cardId] == true
			setSlotHint(slot, shouldHint)
		else
			setSlotHint(slot, false)
		end
	end
end

-- Shake animation and sound for unplayable card
local function shakeSlotError(slot)
	if not slot then return end
	
	-- Play error sound
	errorSound:Play()
	
	-- Show "Not Available" text briefly
	local handFrame = slot.Parent
	local errorLabel = handFrame and handFrame:FindFirstChild("CardErrorLabel")
	if not errorLabel then
		errorLabel = Instance.new("TextLabel")
		errorLabel.Name = "CardErrorLabel"
		errorLabel.Size = UDim2.new(0, 200, 0, 40)
		errorLabel.Position = UDim2.new(0.5, -100, 1, -220)
		errorLabel.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
		errorLabel.BackgroundTransparency = 0.2
		errorLabel.BorderSizePixel = 0
		errorLabel.TextColor3 = Color3.new(1, 1, 1)
		errorLabel.TextSize = 18
		errorLabel.Font = Enum.Font.GothamBold
		errorLabel.Text = "Not available right now!"
		errorLabel.TextStrokeTransparency = 0.5
		errorLabel.ZIndex = 10
		local corner = Instance.new("UICorner", errorLabel)
		corner.CornerRadius = UDim.new(0, 8)
		errorLabel.Parent = handFrame
	end
	errorLabel.Visible = true
	errorLabel.TextTransparency = 0
	errorLabel.BackgroundTransparency = 0.2
	
	-- Shake animation
	local originalPos = slot.Position
	local shakeAmount = 8
	local shakeDuration = 0.05
	
	for _ = 1, 4 do
		local offsetX = math.random(-shakeAmount, shakeAmount)
		local tweenInfo = TweenInfo.new(shakeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(slot, tweenInfo, {
			Position = UDim2.new(originalPos.X.Scale, originalPos.X.Offset + offsetX, originalPos.Y.Scale, originalPos.Y.Offset)
		})
		tween:Play()
		tween.Completed:Wait()
	end
	
	-- Return to original position
	local returnTween = TweenService:Create(slot, TweenInfo.new(0.05), {Position = originalPos})
	returnTween:Play()
	
	-- Flash red tint on the card
	local cardImage = slot:FindFirstChild("CardImage")
	if cardImage then
		local originalColor = cardImage.ImageColor3
		cardImage.ImageColor3 = Color3.fromRGB(255, 100, 100)
		task.delay(0.2, function()
			if cardImage and cardImage.Parent then
				cardImage.ImageColor3 = originalColor
			end
		end)
	end
	
	-- Fade out error label
	task.delay(1.2, function()
		if errorLabel and errorLabel.Parent then
			local fadeInfo = TweenInfo.new(0.3)
			local fadeTween = TweenService:Create(errorLabel, fadeInfo, {
				TextTransparency = 1,
				BackgroundTransparency = 1
			})
			fadeTween:Play()
			fadeTween.Completed:Connect(function()
				if errorLabel and errorLabel.Parent then
					errorLabel.Visible = false
				end
			end)
		end
	end)
end

local function isCardPlayable(cardId)
	return cardId and playableCardIds[cardId] == true
end

-- Cards that should bypass client-side playability check and let server validate
-- These cards have tight timing windows where client state might be stale
local BYPASS_CLIENT_CHECK = {
	starter_extra_roll = true,
	starter_capture_bonus = true,
}

local function requestUseCard(slot)
	if not slot or not slot.Parent then return end
	
	local uid = slot:GetAttribute("cardUid")
	if not uid or uid == "" then return end
	
	local cardId = slot:GetAttribute("cardId")
	if not cardId or cardId == "" then return end
	
	-- Debounce rapid clicks on same card
	slotStates[slot] = slotStates[slot] or {}
	local now = tick()
	if slotStates[slot].lastClickTime and (now - slotStates[slot].lastClickTime) < CLICK_DEBOUNCE then
		return
	end
	slotStates[slot].lastClickTime = now
	
	-- Check if card is playable; if not, show error feedback
	-- Some cards with tight timing windows bypass this check and let server validate
	if not BYPASS_CLIENT_CHECK[cardId] and not isCardPlayable(cardId) then
		shakeSlotError(slot)
		return
	end
	
	if cardId and CARD_REQUIRES_TARGET[cardId] then
		remoteEvent:FireServer("RequestCardTarget", uid, cardId)
	else
		remoteEvent:FireServer("RequestUseCard", uid, {})
	end
end

 

local function collapseOtherSlots(activeSlot)
	local parent = activeSlot and activeSlot.Parent
	if not parent then return end
	for _, other in ipairs(parent:GetChildren()) do
		if other ~= activeSlot and other.Name and other.Name:match("^Slot") then
			local st = slotStates[other]
			if st and st.expanded then
				st.expanded = false
				tweenSlot(other, false)
			end
		end
	end
end

local function clearSlotConnections(slot)
	if not slot then return end
	local conn = slotConnections[slot]
	if conn then
		if conn.enter then conn.enter:Disconnect() end
		if conn.leave then conn.leave:Disconnect() end
		if conn.activated then conn.activated:Disconnect() end
	end
	slotConnections[slot] = nil
end

local function attachSlotInput(slot)
	if not slot then return end
	clearSlotConnections(slot)
	local conns = {}
	local hand = slot.Parent
	-- prefer input hitbox if present
	local inputName = slot:GetAttribute("inputName")
	local input = hand and inputName and hand:FindFirstChild(inputName) or nil
	local target = (input and input.Visible ~= false) and input or slot
	if not isTouch then
		conns.enter = target.MouseEnter:Connect(function()
			collapseOtherSlots(slot)
			local st = slotStates[slot]
			if st and st.collapseTimer then
				st.collapseTimer = nil
			end
			if not st or not st.expanded then
				slotStates[slot] = slotStates[slot] or {}
				slotStates[slot].expanded = true
				tweenSlot(slot, true)
			end
		end)

		conns.leave = target.MouseLeave:Connect(function()
			slotStates[slot] = slotStates[slot] or {}
			task.delay(COLLAPSE_DELAY, function()
				if not slot or not slot.Parent then return end
				slotStates[slot].expanded = false
				tweenSlot(slot, false)
			end)
		end)

		-- Desktop: click to use when expanded; click once to expand otherwise
		conns.activated = target.Activated:Connect(function()
			local uid = slot:GetAttribute("cardUid")
			if not uid or uid == "" then return end
			slotStates[slot] = slotStates[slot] or {}
			if not slotStates[slot].expanded then
				collapseOtherSlots(slot)
				slotStates[slot].expanded = true
				tweenSlot(slot, true)
				return
			end
			requestUseCard(slot)
		end)
	else
		-- Mobile: toggle on tap; first tap expands (collapsing others), second tap uses the card
		conns.activated = target.Activated:Connect(function()
			slotStates[slot] = slotStates[slot] or {}
			local st = slotStates[slot]
			local isExpanded = st.expanded
			if not isExpanded then
				collapseOtherSlots(slot)
				st.expanded = true
				tweenSlot(slot, true)
			else
				-- already expanded -> treat as use
				requestUseCard(slot)
				st.expanded = false
				tweenSlot(slot, false)
			end
		end)
	end
	slotConnections[slot] = conns
end

local function renderHand(cards)
	if not cardGui then return end
	local handFrame = cardGui:WaitForChild("HandFrame")
	for i = 1, 3 do
		local slot = handFrame and handFrame:FindFirstChild("Slot"..i)
		if slot then
			local img = slot:FindFirstChild("CardImage")
			-- disconnect previous use connection (do not attach properties to Roblox Instances)
			if useConnections[slot] then
				useConnections[slot]:Disconnect()
				useConnections[slot] = nil
			end

			local inputName = slot:GetAttribute("inputName")
			local hand = slot.Parent
			local input = (hand and inputName) and hand:FindFirstChild(inputName) or nil

			local card = cards and cards[i]
			if card then
				slot.Visible = true
				if input then
					input.Visible = true
					input.Position = slot.Position
					input.Size = slot.Size
				end
				if img then img.Image = card.meta.Icon or "" end
				slot:SetAttribute("cardUid", card.uid)
				slot:SetAttribute("cardId", card.id)
			else
				-- hide empty slot and collapse if expanded
				slotStates[slot] = slotStates[slot] or {}
				slotStates[slot].expanded = false
				tweenSlot(slot, false)
				slot.Visible = false
				if input then input.Visible = false end
				if img then img.Image = "" end
				slot:SetAttribute("cardUid", "")
				slot:SetAttribute("cardId", "")
			end

			-- Important: bind input AFTER visibility updates so we don't bind to an invisible hitbox
			attachSlotInput(slot)
		end
	end

	updatePlayableHints()
end

-- Dynamic color lookup for player colors (updated from server)
local COLOR_MAP = {
	-- Default fallback colors
	red = Color3.fromRGB(220, 60, 60),
	blue = Color3.fromRGB(60, 120, 220),
	green = Color3.fromRGB(60, 180, 60),
	yellow = Color3.fromRGB(220, 200, 60),
}

-- Function to get display color (with fallback)
local function getDisplayColor(slotName)
	if not slotName then return Color3.fromRGB(150, 150, 150) end
	return COLOR_MAP[slotName:lower()] or Color3.fromRGB(150, 150, 150)
end

-- Show card played notification to all players
local function showCardPlayedNotification(playerName, playerColor, cardName, cardIcon, cardDescription)
	-- Create notification container
	local notification = Instance.new("Frame")
	notification.Name = "CardPlayedNotification"
	notification.Size = UDim2.new(0, 320, 0, 120)
	notification.Position = UDim2.new(0.5, -160, 0, -130) -- Start above screen
	notification.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	notification.BackgroundTransparency = 0.1
	notification.BorderSizePixel = 0
	notification.ZIndex = 100
	notification.Parent = PlayerGui:FindFirstChild("CardGui") or PlayerGui
	
	local corner = Instance.new("UICorner", notification)
	corner.CornerRadius = UDim.new(0, 12)
	
	-- Color accent bar on left
	local colorBar = Instance.new("Frame", notification)
	colorBar.Name = "ColorBar"
	colorBar.Size = UDim2.new(0, 6, 1, -16)
	colorBar.Position = UDim2.new(0, 8, 0, 8)
	colorBar.BackgroundColor3 = getDisplayColor(playerColor)
	colorBar.BorderSizePixel = 0
	local colorBarCorner = Instance.new("UICorner", colorBar)
	colorBarCorner.CornerRadius = UDim.new(0, 3)
	
	-- Card icon
	local iconFrame = Instance.new("ImageLabel", notification)
	iconFrame.Name = "CardIcon"
	iconFrame.Size = UDim2.new(0, 70, 0, 90)
	iconFrame.Position = UDim2.new(0, 22, 0.5, -45)
	iconFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
	iconFrame.BackgroundTransparency = 0.5
	iconFrame.BorderSizePixel = 0
	iconFrame.Image = cardIcon or ""
	iconFrame.ScaleType = Enum.ScaleType.Fit
	iconFrame.ZIndex = 101
	local iconCorner = Instance.new("UICorner", iconFrame)
	iconCorner.CornerRadius = UDim.new(0, 6)
	
	-- Header text
	local headerLabel = Instance.new("TextLabel", notification)
	headerLabel.Name = "Header"
	headerLabel.Size = UDim2.new(0, 210, 0, 24)
	headerLabel.Position = UDim2.new(0, 100, 0, 12)
	headerLabel.BackgroundTransparency = 1
	headerLabel.Text = playerName .. " played:"
	headerLabel.TextColor3 = getDisplayColor(playerColor)
	headerLabel.TextSize = 16
	headerLabel.Font = Enum.Font.GothamBold
	headerLabel.TextXAlignment = Enum.TextXAlignment.Left
	headerLabel.ZIndex = 101
	
	-- Card name
	local nameLabel = Instance.new("TextLabel", notification)
	nameLabel.Name = "CardName"
	nameLabel.Size = UDim2.new(0, 210, 0, 28)
	nameLabel.Position = UDim2.new(0, 100, 0, 36)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = cardName or "Unknown Card"
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextSize = 20
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.ZIndex = 101
	
	-- Card description
	local descLabel = Instance.new("TextLabel", notification)
	descLabel.Name = "Description"
	descLabel.Size = UDim2.new(0, 210, 0, 40)
	descLabel.Position = UDim2.new(0, 100, 0, 66)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = cardDescription or ""
	descLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	descLabel.TextSize = 12
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.TextWrapped = true
	descLabel.TextTruncate = Enum.TextTruncate.AtEnd
	descLabel.ZIndex = 101
	
	-- Slide in animation
	local slideIn = TweenService:Create(notification, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, -160, 0, 20)
	})
	slideIn:Play()
	
	-- Hold for 2.5 seconds, then slide out and destroy
	task.delay(2.5, function()
		if notification and notification.Parent then
			local slideOut = TweenService:Create(notification, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(0.5, -160, 0, -130)
			})
			slideOut:Play()
			slideOut.Completed:Connect(function()
				if notification and notification.Parent then
					notification:Destroy()
				end
			end)
		end
	end)
end

local eventHandlers = {
	["MapConfigUpdate"] = function(p)
		-- Update color map with dynamic colors from server
		if p.DisplayColors then
			for slotName, color in pairs(p.DisplayColors) do
				COLOR_MAP[slotName:lower()] = color
			end
		end
	end,
	
	["CardTilesUpdate"] = function(p)
		-- Clients may show markers; implementation depends on map UI
		-- p.Tiles is a list of part names
	end,
	
	["CardHandUpdate"] = function(p)
		renderHand(p.Cards)
	end,
	
	["CardGranted"] = function(p)
		-- Could show popup notification when card is granted
	end,
	
	["CardUseResult"] = function(p)
		if p.Success == false then
			-- Show error feedback
			local handFrame = cardGui and cardGui:FindFirstChild("HandFrame")
			if not handFrame then return end
			
			-- Find the slot that matches the failed card
			local foundSlot = nil
			if p.CardUid then
				for i = 1, 3 do
					local slot = handFrame:FindFirstChild("Slot"..i)
					if slot and slot.Visible and slot:GetAttribute("cardUid") == p.CardUid then
						foundSlot = slot
						break
					end
				end
			end
			
			-- Fallback to first visible slot if no specific match
			if not foundSlot then
				for i = 1, 3 do
					local slot = handFrame:FindFirstChild("Slot"..i)
					if slot and slot.Visible then
						foundSlot = slot
						break
					end
				end
			end
			
			if foundSlot then
				shakeSlotError(foundSlot)
			end
		end
	end,
	
	["CardPlayableUpdate"] = function(p)
		local ids = p.CardIds or {}
		local active = p.Active == true
		
		for _, cardId in ipairs(ids) do
			if active then
				playableCardIds[cardId] = true
			else
				playableCardIds[cardId] = nil
			end
		end
		
		updatePlayableHints()
	end,
	
	["CardPlayableClearAll"] = function(p)
		-- Clear all playable hints (sent at turn end)
		clearAllPlayableHints()
	end,
	
	["CardPlayedBroadcast"] = function(p)
		showCardPlayedNotification(p.PlayerName, p.PlayerColor, p.CardName, p.CardIcon, p.CardDescription)
	end,
	
	["TurnChanged"] = function(p)
		-- Clear card playable hints when turn changes
		clearAllPlayableHints()
	end
}

remoteEvent.OnClientEvent:Connect(function(params)
	if not params or not params.Msg then return end
	local fn = eventHandlers[params.Msg]
	if fn then pcall(fn, params) end
end)
