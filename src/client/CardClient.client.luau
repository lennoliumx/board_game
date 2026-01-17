-- Client-side Card GUI handler
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer
local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

local PlayerGui = script.Parent.Parent:WaitForChild("PlayerGui")
local cardGui = PlayerGui:WaitForChild("CardGui")

local isTouch = UserInputService.TouchEnabled

local slotConnections = {}
local slotStates = {} -- slot -> {expanded = bool, collapseTimer = RBXScriptConnection or nil}
local COLLAPSE_DELAY = 0.12
local useConnections = {} -- map slot -> connection for UseButton
local playableCardIds = {}

-- Error feedback sound
local errorSound = Instance.new("Sound")
errorSound.SoundId = "rbxassetid://9113869786" -- UI error/denial sound
errorSound.Volume = 0.5
errorSound.Parent = SoundService

local CARD_REQUIRES_TARGET = {
	starter_move_one = true,
	starter_protect_start = true,
	starter_start_plus_one = true,
}

local function tweenSlot(slot, toExpanded)
	if not slot then return end
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
	elseif isHinted then
		goalPos = UDim2.new(0.5, offset, 1, hintY)
		goalSize = UDim2.new(0, hW, 0, hH)
	else
		goalPos = UDim2.new(0.5, offset, 1, hiddenY)
		goalSize = UDim2.new(0, hW, 0, hH)
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
	if not slot then return end
	slotStates[slot] = slotStates[slot] or {}
	slotStates[slot].hinted = on
	if slotStates[slot].expanded then return end
	tweenSlotHint(slot, on)
end

local function updatePlayableHints()
	if not cardGui then return end
	local handFrame = cardGui:FindFirstChild("HandFrame")
	if not handFrame then return end
	for i = 1, 3 do
		local slot = handFrame:FindFirstChild("Slot"..i)
		if slot and slot.Visible then
			local cardId = slot:GetAttribute("cardId")
			local shouldHint = cardId and playableCardIds[cardId] == true
			setSlotHint(slot, shouldHint)
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

local function requestUseCard(slot)
	if not slot then return end
	local uid = slot:GetAttribute("cardUid")
	if not uid or uid == "" then return end
	local cardId = slot:GetAttribute("cardId")
	
	-- Check if card is playable; if not, show error feedback
	if not isCardPlayable(cardId) then
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

local eventHandlers = {
	["CardTilesUpdate"] = function(p)
		-- Clients may show markers; implementation depends on map UI
		-- p.Tiles is a list of part names
	end,
	["CardHandUpdate"] = function(p)
		renderHand(p.Cards)
	end,
	["CardGranted"] = function(p)
		-- show popup
	end,
	["CardUseResult"] = function(p)
		-- Show error feedback if server rejected the card use
		if p.Success == false then
			local handFrame = cardGui and cardGui:FindFirstChild("HandFrame")
			if handFrame then
				-- Find the slot that matches the failed card
				for i = 1, 3 do
					local slot = handFrame:FindFirstChild("Slot"..i)
					if slot and slot.Visible and slot:GetAttribute("cardUid") == p.CardUid then
						shakeSlotError(slot)
						break
					end
				end
				-- If no specific slot found but still failed, shake first visible slot as fallback
				if not p.CardUid then
					for i = 1, 3 do
						local slot = handFrame:FindFirstChild("Slot"..i)
						if slot and slot.Visible then
							shakeSlotError(slot)
							break
						end
					end
				end
			end
		end
	end,
	["CardPlayableUpdate"] = function(p)
		local ids = p.CardIds or {}
		local active = p.Active == true
		for _, id in ipairs(ids) do
			playableCardIds[id] = active
		end
		updatePlayableHints()
	end
}

remoteEvent.OnClientEvent:Connect(function(params)
	if not params or not params.Msg then return end
	local fn = eventHandlers[params.Msg]
	if fn then pcall(fn, params) end
end)
