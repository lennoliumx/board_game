-- // Copyright 2026, DeutscherKaleun, All rights reserved.
local repStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local remoteEvent = repStorage:WaitForChild("RemoteEvent")
local playersReady = repStorage:WaitForChild("PlayersReady")
local roundActive = repStorage:WaitForChild("roundActive")

-- Require Modules
local roundSys = require(game.ReplicatedStorage.Shared.general.roundSys)
local gameDynamics = require(game.ReplicatedStorage.Shared.general.gameDynamics)
local cardManager = require(game.ReplicatedStorage.Shared.cardManager)

-- Handle Player Ready
remoteEvent.OnServerEvent:Connect(function(plr, msg, playerReadyBool, char)
	if msg == "ReadyButtonPressed" then
		roundSys.updateReadyCount(playerReadyBool)
		roundSys.assignColor(plr, char)
	end
end)

-- Handle Player Leaving (Cleanup)
Players.PlayerRemoving:Connect(function(plr)
	-- You should add logic in roundSys to free up the color if the game hasn't started yet
	-- Or handle AI replacement if game has started
end)

-- Main Loop
task.spawn(function()
	while true do
		task.wait(1) -- Check every second

		if not roundActive.Value then
			-- Logic: Wait for players to be ready
			if playersReady.Value > 0 then -- Changed condition slightly: 1 player allows debug testing
				-- Starting Round
				roundActive.Value = true

				remoteEvent:FireAllClients({Msg = "updateRoundGuiStartingRound"})
				task.wait(2)
				remoteEvent:FireAllClients({Msg = "changeCam"})

				local assignments = roundSys.spawnChars()
				roundSys.assignMapCollisionGroups()

				-- Initialize card system and generate card tiles
				pcall(function()
					cardManager.Initialize(assignments)
					cardManager.GenerateCardTiles(4)
				end)

				-- Give starting random cards to each assigned player (fill up to 3)
				pcall(function()
					for color, info in pairs(assignments) do
						if type(info) == "table" and info[1] and info[1].Parent then
							local plr = info[1]
							-- try to fill up to 3 cards
							for i = 1, 3 do
								local ok = cardManager.GiveRandomCardToPlayer(plr)
								if not ok then break end
							end
						end
					end
				end)

				-- Start the Game Logic Module
				gameDynamics.StartGameLoop(assignments)
				

				break -- Break the loop so we don't restart multiple games
			else
				remoteEvent:FireAllClients({Msg = "updateRoundGuiNotEnoughPlayers"})
			end
		end
	end
end)




--Turn of map/Dice collision
