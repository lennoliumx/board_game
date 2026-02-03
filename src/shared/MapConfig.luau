-- MapConfig: Dynamic map configuration system
-- Reads player slots, colors, and start offsets from the current map's Config folder
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = {}

-- Cache for current map config
local cachedConfig = nil
local cachedMapName = nil

-- Default fallback configuration (classic Ludo)
local DEFAULT_CONFIG = {
	turnOrder = {"red", "blue", "green", "yellow"},
	startOffsets = {
		["red"] = 1,
		["blue"] = 11,
		["green"] = 21,
		["yellow"] = 31
	},
	displayColors = {
		["red"] = Color3.fromRGB(255, 0, 0),
		["blue"] = Color3.fromRGB(0, 0, 255),
		["green"] = Color3.fromRGB(0, 255, 0),
		["yellow"] = Color3.fromRGB(255, 255, 0)
	},
	figureColors = {
		["red"] = Color3.fromRGB(255, 0, 0),
		["blue"] = Color3.fromRGB(0, 0, 255),
		["green"] = Color3.fromRGB(0, 255, 0),
		["yellow"] = Color3.fromRGB(255, 255, 0)
	},
	boardSize = 40
}

-- Read configuration from map's scriptRelevant/Config folder
local function readMapConfig(mapFolder)
	if not mapFolder then return nil end
	
	-- Look for Config inside scriptRelevant folder
	local scriptRelevant = mapFolder:FindFirstChild("scriptRelevant")
	if not scriptRelevant then return nil end
	
	local configFolder = scriptRelevant:FindFirstChild("Config")
	if not configFolder then return nil end
	
	local config = {}
	
	-- Read TurnOrder (StringValue children in order, or a single comma-separated StringValue)
	local turnOrderFolder = configFolder:FindFirstChild("TurnOrder")
	if turnOrderFolder then
		if turnOrderFolder:IsA("Folder") then
			local slots = {}
			for _, child in ipairs(turnOrderFolder:GetChildren()) do
				if child:IsA("StringValue") then
					table.insert(slots, {name = child.Name, value = child.Value, order = tonumber(child.Name:match("%d+")) or 999})
				end
			end
			table.sort(slots, function(a, b) return a.order < b.order end)
			config.turnOrder = {}
			for _, slot in ipairs(slots) do
				table.insert(config.turnOrder, slot.value)
			end
		elseif turnOrderFolder:IsA("StringValue") then
			config.turnOrder = {}
			for slot in turnOrderFolder.Value:gmatch("[^,]+") do
				table.insert(config.turnOrder, slot:match("^%s*(.-)%s*$")) -- trim whitespace
			end
		end
	end
	
	-- Read StartOffsets (NumberValue children named by slot)
	local startOffsetsFolder = configFolder:FindFirstChild("StartOffsets")
	if startOffsetsFolder and startOffsetsFolder:IsA("Folder") then
		config.startOffsets = {}
		for _, child in ipairs(startOffsetsFolder:GetChildren()) do
			if child:IsA("NumberValue") then
				config.startOffsets[child.Name:lower()] = child.Value
			end
		end
	end
	
	-- Read DisplayColors (Color3Value children named by slot)
	local displayColorsFolder = configFolder:FindFirstChild("DisplayColors")
	if displayColorsFolder and displayColorsFolder:IsA("Folder") then
		config.displayColors = {}
		for _, child in ipairs(displayColorsFolder:GetChildren()) do
			if child:IsA("Color3Value") then
				config.displayColors[child.Name:lower()] = child.Value
			end
		end
	end
	
	-- Read FigureColors (Color3Value children named by slot)
	local figureColorsFolder = configFolder:FindFirstChild("FigureColors")
	if figureColorsFolder and figureColorsFolder:IsA("Folder") then
		config.figureColors = {}
		for _, child in ipairs(figureColorsFolder:GetChildren()) do
			if child:IsA("Color3Value") then
				config.figureColors[child.Name:lower()] = child.Value
			end
		end
	end
	
	-- Read BoardSize
	local boardSizeValue = configFolder:FindFirstChild("BoardSize")
	if boardSizeValue and boardSizeValue:IsA("NumberValue") then
		config.boardSize = boardSizeValue.Value
	end
	
	return config
end

-- Merge map config with defaults
local function mergeWithDefaults(mapConfig)
	local result = {}
	
	-- Copy defaults first
	for key, value in pairs(DEFAULT_CONFIG) do
		if type(value) == "table" then
			result[key] = {}
			for k, v in pairs(value) do
				result[key][k] = v
			end
		else
			result[key] = value
		end
	end
	
	-- Override with map config
	if mapConfig then
		for key, value in pairs(mapConfig) do
			if type(value) == "table" then
				result[key] = result[key] or {}
				for k, v in pairs(value) do
					result[key][k] = v
				end
			else
				result[key] = value
			end
		end
	end
	
	return result
end

-- Get current map folder
function MapConfig.GetCurrentMap()
	local currentMap = Workspace:FindFirstChild("CurrentMap")
	if currentMap then
		return currentMap:FindFirstChildOfClass("Folder")
	end
	return nil
end

-- Load and cache configuration for current map
function MapConfig.Load()
	local mapFolder = MapConfig.GetCurrentMap()
	local mapName = mapFolder and mapFolder.Name or "default"
	
	-- Return cached if same map
	if cachedConfig and cachedMapName == mapName then
		return cachedConfig
	end
	
	local mapConfig = readMapConfig(mapFolder)
	cachedConfig = mergeWithDefaults(mapConfig)
	cachedMapName = mapName
	
	return cachedConfig
end

-- Force reload configuration
function MapConfig.Reload()
	cachedConfig = nil
	cachedMapName = nil
	return MapConfig.Load()
end

-- Get turn order array
function MapConfig.GetTurnOrder()
	local config = MapConfig.Load()
	return config.turnOrder
end

-- Get start offset for a slot
function MapConfig.GetStartOffset(slotName)
	local config = MapConfig.Load()
	return config.startOffsets[slotName:lower()] or 1
end

-- Get all start offsets
function MapConfig.GetStartOffsets()
	local config = MapConfig.Load()
	return config.startOffsets
end

-- Get display color for a slot (for UI)
function MapConfig.GetDisplayColor(slotName)
	local config = MapConfig.Load()
	return config.displayColors[slotName:lower()] or Color3.fromRGB(150, 150, 150)
end

-- Get all display colors
function MapConfig.GetDisplayColors()
	local config = MapConfig.Load()
	return config.displayColors
end

-- Get figure color for a slot (for figure highlights)
function MapConfig.GetFigureColor(slotName)
	local config = MapConfig.Load()
	return config.figureColors[slotName:lower()] or Color3.fromRGB(200, 200, 200)
end

-- Get all figure colors
function MapConfig.GetFigureColors()
	local config = MapConfig.Load()
	return config.figureColors
end

-- Get board size
function MapConfig.GetBoardSize()
	local config = MapConfig.Load()
	return config.boardSize
end

-- Get the scriptRelevant folder
function MapConfig.GetScriptRelevant()
	local mapFolder = MapConfig.GetCurrentMap()
	if not mapFolder then return nil end
	return mapFolder:FindFirstChild("scriptRelevant")
end

-- Get spawn fields folder for a slot
function MapConfig.GetSpawnFields(slotName)
	local scriptRelevant = MapConfig.GetScriptRelevant()
	if not scriptRelevant then return nil end
	
	local spawnFieldsFolder = scriptRelevant:FindFirstChild("spawnFields")
	if not spawnFieldsFolder then return nil end
	
	return spawnFieldsFolder:FindFirstChild(slotName:lower())
end

-- Get target/goal fields folder for a slot
function MapConfig.GetTargetFields(slotName)
	local scriptRelevant = MapConfig.GetScriptRelevant()
	if not scriptRelevant then return nil end
	
	local targetFieldsFolder = scriptRelevant:FindFirstChild("TargetFields")
	if not targetFieldsFolder then return nil end
	
	return targetFieldsFolder:FindFirstChild(slotName:lower())
end

-- Get main board fields folder
function MapConfig.GetFields()
	local scriptRelevant = MapConfig.GetScriptRelevant()
	if not scriptRelevant then return nil end
	return scriptRelevant:FindFirstChild("Fields")
end

-- Get Config folder
function MapConfig.GetConfigFolder()
	local scriptRelevant = MapConfig.GetScriptRelevant()
	if not scriptRelevant then return nil end
	return scriptRelevant:FindFirstChild("Config")
end

-- Create empty player assignments table based on turn order
function MapConfig.CreatePlayerAssignments()
	local assignments = {}
	for _, slotName in ipairs(MapConfig.GetTurnOrder()) do
		assignments[slotName] = 0
	end
	return assignments
end

-- Get number of player slots
function MapConfig.GetSlotCount()
	return #MapConfig.GetTurnOrder()
end

-- Check if a slot name is valid
function MapConfig.IsValidSlot(slotName)
	local turnOrder = MapConfig.GetTurnOrder()
	for _, slot in ipairs(turnOrder) do
		if slot:lower() == slotName:lower() then
			return true
		end
	end
	return false
end

-- Broadcast config to all clients (call after map loads)
function MapConfig.BroadcastToClients()
	local remoteEvent = ReplicatedStorage:FindFirstChild("RemoteEvent")
	if remoteEvent then
		local config = MapConfig.Load()
		remoteEvent:FireAllClients({
			Msg = "MapConfigUpdate",
			TurnOrder = config.turnOrder,
			DisplayColors = config.displayColors,
			FigureColors = config.figureColors,
			BoardSize = config.boardSize
		})
	end
end

return MapConfig
