-- CardManager: authoritative server-side card system
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local remoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

local cardManager = {}

-- Internal state
local cardsRegistry = {} -- id -> module
local playerHands = {} -- userId -> { {uid=..., id=..., meta=...}, ... }
local colorToPlayer = {} -- color -> player (set at Initialize)
local activeCardTiles = {} -- list of Parts

local MAX_HAND_SIZE = 3

-- Utilities
local function makeUid(id)
    return id.."_"..tostring(tick()).."_"..tostring(math.random(1,99999))
end

function cardManager.RegisterCard(cardModule)
    if not cardModule or not cardModule.Id then return end
    cardsRegistry[cardModule.Id] = cardModule
end

function cardManager.Initialize(assignments)
    -- assignments expected to be the same structure returned from roundSys.spawnChars
    -- map color -> {player, char, figures}
    for color, info in pairs(assignments or {}) do
        if type(info) == "table" and info[1] then
            colorToPlayer[color] = info[1]
        end
    end
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
    if not cardManager.CanAddCard(player) then return false, "hand full" end

    local module = cardsRegistry[cardId]
    local uid = makeUid(cardId)
    local entry = { uid = uid, id = module.Id, meta = { Name = module.Name, Description = module.Description, Icon = module.Icon } }
    table.insert(playerHands[player.UserId], entry)

    -- Notify client
    remoteEvent:FireClient(player, { Msg = "CardGranted", Card = entry })
    remoteEvent:FireClient(player, { Msg = "CardHandUpdate", Cards = playerHands[player.UserId] })
    if module.OnAcquire then pcall(module.OnAcquire, player, entry) end
    return true
end

function cardManager.GiveRandomCardToPlayer(player)
    if not player then return false, "no player" end
    if not cardManager.CanAddCard(player) then return false, "hand full" end

    -- Pick random card from registry
    local keys = {}
    for k, _ in pairs(cardsRegistry) do table.insert(keys, k) end
    if #keys == 0 then return false, "no cards registered" end
    local choice = keys[math.random(1, #keys)]
    return cardManager.GiveSpecificCard(player, choice)
end

function cardManager.ClearCardTiles()
    for _, part in ipairs(activeCardTiles) do
        if part and part:IsA("BasePart") then
            CollectionService:RemoveTag(part, "CardTile")
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
            CollectionService:AddTag(p, "CardTile")
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

function cardManager.HandlePlayerLandingByFigure(figure, color, landedPart)
    if not figure or not color then return end
    -- Check if landedPart is a card tile
    if not landedPart then return end
    if CollectionService:HasTag(landedPart, "CardTile") then
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
    if not entry then return false, "not owned" end

    local module = cardsRegistry[entry.id]
    if not module then return false, "card missing module" end

    if module.CanUse then
        local ok, reason = module.CanUse(player, ctx)
        if not ok then return false, reason or "cannot use" end
    end

    local success, err = pcall(function()
        return module.OnUse(player, ctx)
    end)

    if not success then
        return false, tostring(err)
    end

    -- Remove card from hand (consumable)
    table.remove(hand, idx)
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
    elseif msg == "RequestCardList" then
        remoteEvent:FireClient(player, { Msg = "CardHandUpdate", Cards = cardManager.GetPlayerHand(player) })
    end
end)

return cardManager
