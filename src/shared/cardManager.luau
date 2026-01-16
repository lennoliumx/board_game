-- CardManager: authoritative server-side card system
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

local cardManager = {}

local cardsRegistry = {} -- id -> module
local playerHands = {} -- userId -> { {uid=..., id=..., meta=...}, ... }
local colorToPlayer = {} -- color -> player (set at Initialize)
local activeCardTiles = {} -- list of Parts

local playerToColor = {} -- userId -> color
local turnIndex = ReplicatedStorage:WaitForChild("turnIndex")
local TURN_ORDER = {"red", "blue", "green", "yellow"}
local MAX_HAND_SIZE = 3
local lastUsedTurn = {} -- userId -> turnIndex.Value when they used a card
local pendingCardUse = {} -- userId -> {uid=..., cardId=...}
local deckProvider = nil -- optional function(player) -> {cardId,...}
local moveApi = nil

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
    -- Clear all player hands and state for new round
    for k in pairs(playerHands) do playerHands[k] = nil end
    for k in pairs(lastUsedTurn) do lastUsedTurn[k] = nil end
    for k in pairs(pendingCardUse) do pendingCardUse[k] = nil end
    for k in pairs(colorToPlayer) do colorToPlayer[k] = nil end
    for k in pairs(playerToColor) do playerToColor[k] = nil end

    -- assignments expected to be the same structure returned from roundSys.spawnChars
    -- map color -> {player, char, figures}
    local playerCount = 0
    for _, info in pairs(assignments or {}) do
        if type(info) == "table" and info[1] then
            playerCount += 1
        end
    end
    for color, info in pairs(assignments or {}) do
        if type(info) == "table" and info[1] then
            colorToPlayer[color] = info[1]
            playerToColor[info[1].UserId] = color
            info[1]:SetAttribute("playerColor", color)
            info[1]:SetAttribute("activePlayerCount", playerCount)
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
        end
    end
    activeCardTiles = {}
    -- Notify all clients to clear visuals
    remoteEvent:FireAllClients({ Msg = "CardTilesUpdate", Tiles = {} })
end

function cardManager.GenerateCardTiles(n)
    n = n or 4
    cardManager.ClearCardTiles()
    local currentMap = Workspace:WaitForChild("CurrentMap"):FindFirstChildOfClass("Folder")
    if not currentMap then return {} end

    local fields = currentMap:FindFirstChild("Fields")
    if not fields then return {} end
    local candidates = {}
    for _, v in ipairs(fields:GetChildren()) do
        if v:IsA("BasePart") then table.insert(candidates, v) end
    end
    if #candidates == 0 then return {} end

    local chosen = {}
    local used = {}
    while #chosen < math.min(n, #candidates) do
        local idx = math.random(1, #candidates)
        if not used[idx] then
            used[idx] = true
            local p = candidates[idx]
            table.insert(chosen, p)
            CollectionService:AddTag(p, "CardFillTile")
            table.insert(activeCardTiles, p)
        end
    end
    
    -- Visual effects

    for _, tile in chosen do
        local fillIconClone = ReplicatedStorage.fillIcon:Clone()
        local sparkles = Instance.new("Sparkles", tile)
        tile.Color = Color3.new(1, 0, 0)
        fillIconClone.Parent = tile
        fillIconClone.CFrame = tile.CFrame * CFrame.new(0.3,0,0)
    end

    -- Send indices (names) to clients so they can show markers
    local tileNames = {}
    for _, p in ipairs(activeCardTiles) do table.insert(tileNames, p.Name) end
    remoteEvent:FireAllClients({ Msg = "CardTilesUpdate", Tiles = tileNames })
    return activeCardTiles
end

function cardManager.GetPlayerByColor(color)
    return colorToPlayer[color]
end

local function getFigureColor(figure)
    if not figure or not figure.Name then return nil end
    return figure.Name:match("Figure_(%a+)_")
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
    if cardId == "starter_move_one" then
        for _, fig in ipairs(figures) do
            local steps = fig:GetAttribute("stepsTaken") or -1
            if steps >= 0 then
                table.insert(valid, fig)
            end
        end
    elseif cardId == "starter_protect_start" or cardId == "starter_start_plus_one" then
        for _, fig in ipairs(figures) do
            if fig:GetAttribute("leftHouseThisTurn") == true then
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
    local currentColor = nil
    if currentTurnIdx and TURN_ORDER[currentTurnIdx] then currentColor = TURN_ORDER[currentTurnIdx] end
    return myColor and currentColor and myColor == currentColor
end

function cardManager.HandlePlayerLandingByFigure(figure, color, landedPart)
    if not figure or not color then return end
    -- Check if landedPart is a card tile
    if not landedPart then return end
        if CollectionService:HasTag(landedPart, "CardFillTile") then
        local player = cardManager.GetPlayerByColor(color)
        if player and player.Parent then
            -- Give at most one card
            cardManager.GiveRandomCardToPlayer(player)
            -- Optionally regenerate that tile to another position
        end
    end
end

function cardManager.UseCard(player, cardUid, ctx)
    if not player or not cardUid then return false, "invalid" end
    local hand = cardManager.GetPlayerHand(player)
    local idx = nil
    local entry = nil
    for i, v in ipairs(hand) do if v.uid == cardUid then idx = i; entry = v; break end end
    if not entry then
        remoteEvent:FireClient(player, { Msg = "CardUseResult", Success = false, Reason = "not owned" })
        return false, "not owned"
    end

    local module = cardsRegistry[entry.id]
    if not module then
        remoteEvent:FireClient(player, { Msg = "CardUseResult", Success = false, Reason = "card missing module" })
        return false, "card missing module"
    end

        -- Enforce turn: only allow use on player's turn
        local userId = player.UserId
        local myColor = playerToColor[userId]
        local currentTurnIdx = (turnIndex and turnIndex.Value) or nil
        local currentColor = nil
        if currentTurnIdx and TURN_ORDER[currentTurnIdx] then currentColor = TURN_ORDER[currentTurnIdx] end
        if not myColor or not currentColor or myColor ~= currentColor then
            remoteEvent:FireClient(player, { Msg = "CardUseResult", Success = false, Reason = "Not your turn" })
            return false, "not your turn"
        end

        -- Prevent multiple uses in the same turn
        if currentTurnIdx and lastUsedTurn[userId] and lastUsedTurn[userId] == currentTurnIdx then
            remoteEvent:FireClient(player, { Msg = "CardUseResult", Success = false, Reason = "Already used a card this turn" })
            return false, "already used"
        end

    if module.CanUse then
        local ok, reason = module.CanUse(player, ctx)
        if not ok then
            remoteEvent:FireClient(player, { Msg = "CardUseResult", Success = false, Reason = reason or "cannot use" })
            return false, reason or "cannot use"
        end
    end

    local success, resultOrErr = pcall(function()
        return module.OnUse(player, ctx)
    end)

    if not success then
        remoteEvent:FireClient(player, { Msg = "CardUseResult", Success = false, Reason = tostring(resultOrErr) })
        return false, tostring(resultOrErr)
    end

    if resultOrErr == false then
        remoteEvent:FireClient(player, { Msg = "CardUseResult", Success = false, Reason = "card failed" })
        return false, "card failed"
    end

    if type(resultOrErr) == "table" and resultOrErr.effect and moveApi then
        local ok, effectErr = pcall(function()
            moveApi.ApplyEffect(player, resultOrErr)
        end)
        if not ok then
            remoteEvent:FireClient(player, { Msg = "CardUseResult", Success = false, Reason = tostring(effectErr) })
            return false, tostring(effectErr)
        end
    end

    -- Remove card from hand (consumable)
    table.remove(hand, idx)
    -- mark used for this turn
    if currentTurnIdx then lastUsedTurn[userId] = currentTurnIdx end
    remoteEvent:FireClient(player, { Msg = "CardUseResult", Success = true, CardUid = cardUid })
    remoteEvent:FireClient(player, { Msg = "CardHandUpdate", Cards = hand })
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

-- Remote handler: client requests use
remoteEvent.OnServerEvent:Connect(function(player, msg, ...)
    if msg == "RequestUseCard" then
        local cardUid, ctx = ...
        cardManager.UseCard(player, cardUid, ctx)
    elseif msg == "RequestCardTarget" then
        local cardUid, cardId = ...
        if not player or not cardUid or not cardId then return end
        if not isPlayersTurn(player) then
            remoteEvent:FireClient(player, { Msg = "CardUseResult", Success = false, Reason = "Not your turn" })
            return
        end
        pendingCardUse[player.UserId] = { uid = cardUid, cardId = cardId }
        local valid = getValidFiguresForCard(player, cardId)
        if #valid == 0 then
            pendingCardUse[player.UserId] = nil
            remoteEvent:FireClient(player, { Msg = "CardUseResult", Success = false, Reason = "No valid target" })
            return
        end
        if #valid == 1 then
            local ctx = { targetFigure = valid[1] }
            pendingCardUse[player.UserId] = nil
            cardManager.UseCard(player, cardUid, ctx)
            return
        end
        remoteEvent:FireClient(player, { Msg = "GuiChange:ShowFigureButtons", validFigures = valid, Context = "CardTarget" })
    elseif msg == "FigureChosen" then
        local fig, context = ...
        if context ~= "CardTarget" then return end
        local pending = pendingCardUse[player.UserId]
        if not pending or not pending.uid then return end
        pendingCardUse[player.UserId] = nil
        cardManager.UseCard(player, pending.uid, { targetFigure = fig })
    elseif msg == "RequestCardList" then
        remoteEvent:FireClient(player, { Msg = "CardHandUpdate", Cards = cardManager.GetPlayerHand(player) })
    end
end)

return cardManager
