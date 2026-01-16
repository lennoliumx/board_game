-- Client-side Card GUI handler
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

local PlayerGui = script.Parent.Parent:WaitForChild("PlayerGui")
local cardGui = PlayerGui:WaitForChild("CardGui")

local function tweenSlot(slot, toExpanded)
	if not slot then return end
	local offset = slot:GetAttribute("hiddenPosX") or 0
	local hiddenY = slot:GetAttribute("hiddenY") or 40
	local expandedY = slot:GetAttribute("expandedY") or -160
	local hW = slot:GetAttribute("hiddenSizeX") or 120
	local hH = slot:GetAttribute("hiddenSizeY") or 160
	local eW = slot:GetAttribute("expandedSizeX") or 180
	local eH = slot:GetAttribute("expandedSizeY") or 260

	local goalPos = toExpanded and UDim2.new(0.5, offset, 1, expandedY) or UDim2.new(0.5, offset, 1, hiddenY)
	local goalSize = toExpanded and UDim2.new(0, eW, 0, eH) or UDim2.new(0, hW, 0, hH)

	local props = {Position = goalPos, Size = goalSize}
	local tween = TweenService:Create(slot, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)

	print("[CardClient] Starting tween for", slot and slot.Name, "toExpanded=", toExpanded)
	local ok, err = pcall(function() tween:Play() end)
	if not ok then
		warn("[CardClient] TweenService:Play failed:", err)
		-- Fallback: apply final values directly
		slot.Position = goalPos
		slot.Size = goalSize
	else
		tween.Completed:Connect(function(status)
			print("[CardClient] Tween completed for", slot and slot.Name, "status=", tostring(status))
		end)
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

local isTouch = UserInputService.TouchEnabled

local slotConnections = {}
local slotStates = {} -- slot -> {expanded = bool, collapseTimer = RBXScriptConnection or nil}
local COLLAPSE_DELAY = 0.12
local useConnections = {} -- map slot -> connection for UseButton

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
	if not isTouch then
		local target = input or slot
		conns.enter = target.MouseEnter:Connect(function()
			print("[CardClient] MouseEnter on", target.Name, "-> slot", slot.Name)
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
			print("[CardClient] MouseLeave on", target.Name, "-> slot", slot.Name)
			slotStates[slot] = slotStates[slot] or {}
			task.delay(COLLAPSE_DELAY, function()
				if not slot or not slot.Parent then return end
				slotStates[slot].expanded = false
				tweenSlot(slot, false)
			end)
		end)
	else
		-- Mobile: toggle on tap; first tap expands (collapsing others), second tap uses the card
		local target = input or slot
		conns.activated = target.Activated:Connect(function()
			slotStates[slot] = slotStates[slot] or {}
			local st = slotStates[slot]
			local isExpanded = st.expanded
			if not isExpanded then
				-- collapse other expanded slots
				local parent = slot.Parent
				if parent then
					for _, other in ipairs(parent:GetChildren()) do
						if other ~= slot and slotStates[other] and slotStates[other].expanded then
							slotStates[other].expanded = false
							tweenSlot(other, false)
						end
					end
				end
				st.expanded = true
				tweenSlot(slot, true)
			else
				-- already expanded -> treat as use
				local uid = slot:GetAttribute("cardUid")
				if uid and uid ~= "" then
					remoteEvent:FireServer("RequestUseCard", uid, {})
				end
				st.expanded = false
				tweenSlot(slot, false)
			end
		end)
	end
	slotConnections[slot] = conns
end

local function renderHand(cards)
	print("reached")
	if not cardGui then return end
	local handFrame = cardGui:WaitForChild("HandFrame")
	for i = 1, 3 do
		local slot = handFrame and handFrame:FindFirstChild("Slot"..i)
		print(slot)
		print(i)
		if slot then
			attachSlotInput(slot)
			local img = slot:FindFirstChild("CardImage")
			local useBtn = slot:FindFirstChild("UseButton")
			-- disconnect previous use connection (do not attach properties to Roblox Instances)
			if useConnections[slot] then
				useConnections[slot]:Disconnect()
				useConnections[slot] = nil
			end

			local card = cards and cards[i]
			if card then
				if img then img.Image = card.meta.Icon or "" end
				-- store card uid on slot for activation handler
				slot:SetAttribute("cardUid", card.uid)
			else
				if img then img.Image = "" end
				slot:SetAttribute("cardUid", "")
			end
		end
	end
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
		--print("Card granted:", p.Card and p.Card.id)
	end,
	["CardUseResult"] = function(p)
		if p.Success then print("Card used successfully") else print("Card use failed") end
	end
}

remoteEvent.OnClientEvent:Connect(function(params)
	if not params or not params.Msg then return end
	local fn = eventHandlers[params.Msg]
	if fn then pcall(fn, params) end
end)
