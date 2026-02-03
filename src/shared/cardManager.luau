-- CardManager: Robust server-side card system
-- Handles card registration, player hands, usage validation, and game integration
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

local MapConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MapConfig"))

local cardManager = {}

-- ============================================================================
-- STATE
-- ============================================================================
local cardsRegistry = {}      -- cardId -> cardModule
local playerHands = {}        -- UserId -> { {uid, id, meta}, ... }
local colorToPlayer = {}      -- slotColor -> Player
local playerToColor = {}      -- UserId -> slotColor
local lastUsedTurn = {}       -- UserId -> turnIndex when card was last used
local pendingCardUse = {}     -- UserId -> {uid, cardId} for target selection
local cardUseDebounce = {}    -- UserId -> tick() of last use attempt
local activeCardTiles = {}    -- list of Parts with card pickups

local turnIndex = ReplicatedStorage:WaitForChild("turnIndex")
local TURN_ORDER = nil        -- Loaded from MapConfig
local MAX_HAND_SIZE = 3
local USE_DEBOUNCE_TIME = 0.5 -- Seconds between card use attempts

local moveApi = nil           -- Set by gameDynamics for card effects
local deckProvider = nil      -- Optional custom deck function

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local function loadTurnOrder()
	TURN_ORDER = MapConfig.GetTurnOrder()
end

local function dedupeHand(hand)
    local seen = {}
    local i = 1
    while i <= #hand do
        local id = hand[i] and hand[i].id
        if id and seen[id] then
            table.remove(hand, i)
        else
            if id then seen[id] = true end
            i += 1
        end
    end
end

function cardManager.NormalizeHand(player)
    if not player then return end
    local hand = cardManager.GetPlayerHand(player)
    local before = #hand
    dedupeHand(hand)
    if #hand ~= before then
        remoteEvent:FireClient(player, { Msg = "CardHandUpdate", Cards = hand })
    end
end

-- Utilities
local function makeUid(id)
    return id.."_"..tostring(tick()).."_"..tostring(math.random(1,99999))
end

function cardManager.RegisterCard(cardModule)
    if not cardModule or not cardModule.Id then return end
    cardsRegistry[cardModule.Id] = cardModule
end

function cardManager.Initialize(assignments)
    -- Load dynamic turn order from map config
    loadTurnOrder()
    
    -- Clear all state for new round
    table.clear(playerHands)
    table.clear(lastUsedTurn)
    table.clear(pendingCardUse)
    table.clear(cardUseDebounce)
    table.clear(colorToPlayer)
    table.clear(playerToColor)
    table.clear(activeCardTiles)

    -- Build player-color mappings
    local playerCount = 0
    for _, info in pairs(assignments or {}) do
        if type(info) == "table" and info[1] then
            playerCount += 1
        end
    end
    for slotName, info in pairs(assignments or {}) do
        if type(info) == "table" and info[1] then
            local player = info[1]
            colorToPlayer[slotName] = player
            playerToColor[player.UserId] = slotName
            player:SetAttribute("playerColor", slotName)
            player:SetAttribute("activePlayerCount", playerCount)
        end
    end
end

function cardManager.SetDeckProvider(fn)
    deckProvider = fn
end

function cardManager.SetMoveApi(api)
    moveApi = api
end

function cardManager.HasCardId(player, cardId)
    if not player or not cardId then return false end
    local hand = cardManager.GetPlayerHand(player)
    for _, v in ipairs(hand) do
        if v.id == cardId then return true end
    end
    return false
end

-- Reset card usage tracking for a player (call at start of their turn)
function cardManager.ResetTurnCardUsage(player)
    if not player then return end
    lastUsedTurn[player.UserId] = nil
end

function cardManager.GetPlayerHand(player)
    if not player then return {} end
    local u = player.UserId
    playerHands[u] = playerHands[u] or {}
    return playerHands[u]
end

function cardManager.CanAddCard(player)
    local hand = cardManager.GetPlayerHand(player)
    return (#hand < MAX_HAND_SIZE)
end

-- Helper: Extract color from figure name
local function getFigureColor(figure)
    if not figure or not figure.Name then return nil end
    return figure.Name:match("Figure_(%a+)_")
end

-- Helper: Check if figure can move 1 step for FineStep card
local function canFigureMoveOneStep(player, fig)
    if not fig then return false end
    
    local stepsTaken = fig:GetAttribute("stepsTaken")
    if type(stepsTaken) ~= "number" then return false end
    
    -- Figure must be on the board (steps >= 0)
    if stepsTaken < 0 then return false end
    
    -- Cannot move past goal (goal slots are 40-43, overshoot at 44+)
    if stepsTaken >= 43 then return false end
    
    -- Check if destination would be blocked by own figure
    local playerColor = playerToColor[player.UserId]
    if not playerColor then return false end
    
    local targetSteps = stepsTaken + 1
    local isGoal = targetSteps >= 40
    
    if isGoal then
        local checkValue = "G" .. (targetSteps - 39)
        for _, otherFig in ipairs(CollectionService:GetTagged("figure")) do
            if otherFig ~= fig and getFigureColor(otherFig) == playerColor then
                local otherTile = otherFig:GetAttribute("tileIndex")
                if tostring(otherTile) == checkValue then
                    return false
                end
            end
        end
    end
    
    return true
end

-- Helper: Determine if a card should be hinted as playable based on current game state
local function shouldCardBePlayable(player, cardId)
    if not player or not cardId then return false end
    
    local playerColor = playerToColor[player.UserId]
    if not playerColor then return false end
    
    -- Get player's figures
    local myFigures = {}
    for _, fig in ipairs(CollectionService:GetTagged("figure")) do
        local figColor = fig.Name:match("Figure_(%a+)_")
        if figColor == playerColor then
            table.insert(myFigures, fig)
        end
    end
    
    if cardId == "starter_move_one" then
        -- Only playable if a figure left the house THIS turn
        for _, fig in ipairs(myFigures) do
            if fig:GetAttribute("leftHouseThisTurn") == true then
                return true
            end
        end
        return false
        
    elseif cardId == "starter_extra_roll" then
        -- Only playable during the extra roll window
        return player:GetAttribute("extraRollWindowOpen") == true
        
    elseif cardId == "starter_protect_start" then
        -- Only playable when awaiting start roll and a figure left house
        if player:GetAttribute("awaitingStartRoll") ~= true then return false end
        for _, fig in ipairs(myFigures) do
            if fig:GetAttribute("leftHouseThisTurn") == true then
                return true
            end
        end
        return false
        
    elseif cardId == "starter_start_plus_one" then
        -- Playable if any figure on the board can actually move one step
        for _, fig in ipairs(myFigures) do
            if canFigureMoveOneStep(player, fig) then
                return true
            end
        end
        return false
        
    elseif cardId == "starter_capture_bonus" then
        -- Only playable when capture bonus is available
        return player:GetAttribute("captureBonusAvailable") == true
    end
    
    return false
end

function cardManager.GiveSpecificCard(player, cardId)
    if not player then return false, "no player" end
    if not cardId or not cardsRegistry[cardId] then return false, "invalid card" end
    cardManager.NormalizeHand(player)
    if not cardManager.CanAddCard(player) then return false, "hand full" end
    -- Final duplicate check right before insert
    local hand = cardManager.GetPlayerHand(player)
    for _, v in ipairs(hand) do
        if v.id == cardId then return false, "duplicate card" end
    end

    local module = cardsRegistry[cardId]
    local uid = makeUid(cardId)
    local entry = { uid = uid, id = module.Id, meta = { Name = module.Name, Description = module.Description, Icon = module.Icon } }
    table.insert(hand, entry)

    -- Notify client
    remoteEvent:FireClient(player, { Msg = "CardGranted", Card = entry })
    remoteEvent:FireClient(player, { Msg = "CardHandUpdate", Cards = hand })
    
    -- Send correct playability hint for the newly granted card
    -- This prevents the card from appearing playable when it's not
    local isPlayable = shouldCardBePlayable(player, cardId)
    remoteEvent:FireClient(player, { Msg = "CardPlayableUpdate", CardIds = {cardId}, Active = isPlayable })
    
    if module.OnAcquire then pcall(module.OnAcquire, player, entry) end
    return true
end

function cardManager.GiveRandomCardToPlayer(player)
    if not player then return false, "no player" end
    cardManager.NormalizeHand(player)
    if not cardManager.CanAddCard(player) then return false, "hand full" end

    -- Pick random card from registry
    local keys = {}
    if deckProvider then
        local ok, list = pcall(deckProvider, player)
        if ok and type(list) == "table" then
            for _, k in ipairs(list) do table.insert(keys, k) end
        end
    end
    if #keys == 0 then
        for k, _ in pairs(cardsRegistry) do table.insert(keys, k) end
    end
    if #keys == 0 then return false, "no cards registered" end
    -- Remove any cards the player already has in hand
    local filtered = {}
    local seen = {}
    for _, k in ipairs(keys) do
        if not seen[k] and not cardManager.HasCardId(player, k) then
            seen[k] = true
            table.insert(filtered, k)
        end
    end
    if #filtered == 0 then return false, "no unique cards available" end
    local choice = filtered[math.random(1, #filtered)]
    return cardManager.GiveSpecificCard(player, choice)
end

function cardManager.ClearCardTiles()
    for _, part in ipairs(activeCardTiles) do
        if part and part:IsA("BasePart") then
            CollectionService:RemoveTag(part, "CardFillTile")
            -- Clean up visuals
            local fillIcon = part:FindFirstChild("fillIcon")
            if fillIcon then fillIcon:Destroy() end
            local sparkles = part:FindFirstChildOfClass("Sparkles")
            if sparkles then sparkles:Destroy() end
        end
    end
    table.clear(activeCardTiles)
    remoteEvent:FireAllClients({ Msg = "CardTilesUpdate", Tiles = {} })
end

function cardManager.GenerateCardTiles(count)
    count = count or 4
    cardManager.ClearCardTiles()
    
    local fieldsFolder = MapConfig.GetFields()
    if not fieldsFolder then return {} end
    
    local candidates = {}
    for _, part in ipairs(fieldsFolder:GetChildren()) do
        if part:IsA("BasePart") then
            table.insert(candidates, part)
        end
    end
    if #candidates == 0 then return {} end

    local chosen = {}
    local used = {}
    while #chosen < math.min(count, #candidates) do
        local idx = math.random(1, #candidates)
        if not used[idx] then
            used[idx] = true
            local tile = candidates[idx]
            table.insert(chosen, tile)
            CollectionService:AddTag(tile, "CardFillTile")
            table.insert(activeCardTiles, tile)
        end
    end
    
    -- Visual effects
    for _, tile in ipairs(chosen) do
        local fillIconTemplate = ReplicatedStorage:FindFirstChild("fillIcon")
        if fillIconTemplate then
            local fillIconClone = fillIconTemplate:Clone()
            fillIconClone.Parent = tile
            fillIconClone.CFrame = tile.CFrame * CFrame.new(0.3, 0, 0)
        end
        local sparkles = Instance.new("Sparkles")
        sparkles.Parent = tile
        tile.Color = Color3.new(1, 0, 0)
    end

    -- Notify clients
    local tileNames = {}
    for _, tile in ipairs(activeCardTiles) do
        table.insert(tileNames, tile.Name)
    end
    remoteEvent:FireAllClients({ Msg = "CardTilesUpdate", Tiles = tileNames })
    return activeCardTiles
end

function cardManager.GetPlayerByColor(color)
    return colorToPlayer[color]
end

local function getPlayerFigures(player)
    local color = playerToColor[player.UserId]
    if not color then return {} end
    local result = {}
    for _, fig in ipairs(CollectionService:GetTagged("figure")) do
        if getFigureColor(fig) == color then
            table.insert(result, fig)
        end
    end
    return result
end

local function getValidFiguresForCard(player, cardId)
    local figures = getPlayerFigures(player)
    local valid = {}
    if cardId == "starter_move_one" or cardId == "starter_protect_start" then
        -- These cards only work for figures that just left house
        for _, fig in ipairs(figures) do
            if fig:GetAttribute("leftHouseThisTurn") == true then
                table.insert(valid, fig)
            end
        end
    elseif cardId == "starter_start_plus_one" then
        -- Fine step works for any figure on the board that can actually move one step
        for _, fig in ipairs(figures) do
            if canFigureMoveOneStep(player, fig) then
                table.insert(valid, fig)
            end
        end
    end
    return valid
end

local function isPlayersTurn(player)
    if not player then return false end
    local userId = player.UserId
    local myColor = playerToColor[userId]
    local currentTurnIdx = (turnIndex and turnIndex.Value) or nil
    if not currentTurnIdx or not TURN_ORDER then return false end
    local currentColor = TURN_ORDER[currentTurnIdx]
    return myColor and currentColor and myColor == currentColor
end

function cardManager.GetPlayerColor(player)
    if not player then return nil end
    return playerToColor[player.UserId]
end

function cardManager.HandlePlayerLandingByFigure(figure, color, landedPart)
    if not figure or not color or not landedPart then return end
    if CollectionService:HasTag(landedPart, "CardFillTile") then
        local player = cardManager.GetPlayerByColor(color)
        if player and player.Parent then
            cardManager.GiveRandomCardToPlayer(player)
        end
    end
end

local function sendUseResult(player, success, reason, cardUid)
    if not player or not player.Parent then return end
    remoteEvent:FireClient(player, {
        Msg = "CardUseResult",
        Success = success,
        Reason = reason,
        CardUid = cardUid
    })
end

local function broadcastCardPlayed(player, cardModule)
    if not player or not cardModule then return end
    local playerColor = playerToColor[player.UserId] or "Unknown"
    remoteEvent:FireAllClients({
        Msg = "CardPlayedBroadcast",
        PlayerName = player.Name,
        PlayerColor = playerColor,
        CardName = cardModule.Name or cardModule.Id,
        CardIcon = cardModule.Icon or "",
        CardDescription = cardModule.Description or ""
    })
end

function cardManager.UseCard(player, cardUid, ctx)
    print("[cardManager.UseCard] Called with:", player and player.Name, cardUid)
    
    if not player or not cardUid then 
        print("  -> FAIL: invalid player/cardUid")
        return false, "invalid" 
    end
    
    local userId = player.UserId
    
    -- Debounce rapid clicks
    local now = tick()
    if cardUseDebounce[userId] and (now - cardUseDebounce[userId]) < USE_DEBOUNCE_TIME then
        print("  -> FAIL: debounce")
        return false, "too fast"
    end
    cardUseDebounce[userId] = now
    
    -- Find card in hand
    local hand = cardManager.GetPlayerHand(player)
    local cardIndex, cardEntry = nil, nil
    for i, entry in ipairs(hand) do
        if entry.uid == cardUid then
            cardIndex = i
            cardEntry = entry
            break
        end
    end
    
    if not cardEntry then
        print("  -> FAIL: card not in hand")
        sendUseResult(player, false, "Card not in hand", cardUid)
        return false, "not owned"
    end
    
    local cardModule = cardsRegistry[cardEntry.id]
    if not cardModule then
        print("  -> FAIL: card module not found for id:", cardEntry.id)
        sendUseResult(player, false, "Invalid card type", cardUid)
        return false, "card missing module"
    end
    
    -- Validate turn
    print("  - Checking isPlayersTurn...")
    print("    - playerToColor[userId]:", playerToColor[userId])
    print("    - turnIndex.Value:", turnIndex and turnIndex.Value)
    print("    - TURN_ORDER:", TURN_ORDER and table.concat(TURN_ORDER, ", "))
    if not isPlayersTurn(player) then
        print("  -> FAIL: not player's turn")
        sendUseResult(player, false, "Not your turn", cardUid)
        return false, "not your turn"
    end
    
    -- Validate one card per turn
    local currentTurnIdx = turnIndex and turnIndex.Value
    if currentTurnIdx and lastUsedTurn[userId] and lastUsedTurn[userId] == currentTurnIdx then
        print("  -> FAIL: already used card this turn")
        sendUseResult(player, false, "Already used a card this turn", cardUid)
        return false, "already used"
    end
    
    -- Card-specific validation
    print("  - Calling Card.CanUse...")
    if cardModule.CanUse then
        local canUse, reason = cardModule.CanUse(player, ctx or {})
        if not canUse then
            print("  -> FAIL: Card.CanUse returned false:", reason)
            sendUseResult(player, false, reason or "Cannot use now", cardUid)
            return false, reason or "cannot use"
        end
    end
    
    print("  - Calling Card.OnUse...")
    -- Execute card effect
    local success, result = pcall(function()
        return cardModule.OnUse(player, ctx or {})
    end)
    
    if not success then
        sendUseResult(player, false, "Card error: " .. tostring(result), cardUid)
        return false, tostring(result)
    end
    
    if result == false then
        sendUseResult(player, false, "Card effect failed", cardUid)
        return false, "card failed"
    end
    
    -- Apply movement effects if returned
    if type(result) == "table" and result.effect and moveApi then
        local effectOk, effectErr = pcall(function()
            moveApi.ApplyEffect(player, result)
        end)
        if not effectOk then
            sendUseResult(player, false, "Effect error: " .. tostring(effectErr), cardUid)
            return false, tostring(effectErr)
        end
    end
    
    -- SUCCESS: Remove card and update state
    table.remove(hand, cardIndex)
    if currentTurnIdx then 
        lastUsedTurn[userId] = currentTurnIdx 
    end
    
    sendUseResult(player, true, nil, cardUid)
    remoteEvent:FireClient(player, { Msg = "CardHandUpdate", Cards = hand })
    broadcastCardPlayed(player, cardModule)
    
    return true
end

-- Auto-register cards in the shared/Cards folder
local cardsFolder = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("Cards")
if cardsFolder then
    for _, v in ipairs(cardsFolder:GetChildren()) do
        if v:IsA("ModuleScript") then
            local ok, mod = pcall(require, v)
            if ok and type(mod) == "table" and mod.Id then
                cardManager.RegisterCard(mod)
            end
        end
    end
end

-- Remote handler: client requests
remoteEvent.OnServerEvent:Connect(function(player, msg, ...)
    if msg == "RequestUseCard" then
        local cardUid, ctx = ...
        cardManager.UseCard(player, cardUid, ctx or {})
        
    elseif msg == "RequestCardTarget" then
        local cardUid, cardId = ...
        if not player or not cardUid or not cardId then return end
        
        if not isPlayersTurn(player) then
            sendUseResult(player, false, "Not your turn")
            return
        end
        
        pendingCardUse[player.UserId] = { uid = cardUid, cardId = cardId }
        local valid = getValidFiguresForCard(player, cardId)
        
        if #valid == 0 then
            pendingCardUse[player.UserId] = nil
            sendUseResult(player, false, "No valid target")
            return
        end
        
        -- Auto-select if only one valid target
        if #valid == 1 then
            pendingCardUse[player.UserId] = nil
            cardManager.UseCard(player, cardUid, { targetFigure = valid[1] })
            return
        end
        
        -- Show figure selection UI
        remoteEvent:FireClient(player, { 
            Msg = "GuiChange:ShowFigureButtons", 
            validFigures = valid, 
            Context = "CardTarget" 
        })
        
    elseif msg == "FigureChosen" then
        local figure, context = ...
        if context ~= "CardTarget" then return end
        
        local pending = pendingCardUse[player.UserId]
        if not pending or not pending.uid then return end
        
        pendingCardUse[player.UserId] = nil
        cardManager.UseCard(player, pending.uid, { targetFigure = figure })
        
    elseif msg == "CancelCardTarget" then
        pendingCardUse[player.UserId] = nil
        
    elseif msg == "RequestCardList" then
        remoteEvent:FireClient(player, { 
            Msg = "CardHandUpdate", 
            Cards = cardManager.GetPlayerHand(player) 
        })
    end
end)

return cardManager
