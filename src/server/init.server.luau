-- // Copyright 2026, DeutscherKaleun, All rights reserved.
local repStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local remoteEvent = repStorage:WaitForChild("RemoteEvent")
local playersReady = repStorage:WaitForChild("PlayersReady")
local roundActive = repStorage:WaitForChild("roundActive")

-- Require Modules
local roundSys = require(game.ReplicatedStorage.Shared.roundSys)
local gameDynamics = require(game.ReplicatedStorage.Shared.gameDynamics)

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
			if playersReady.Value > 1 then -- Changed condition slightly: 1 player allows debug testing
				print("Starting Round...")
				roundActive.Value = true

				remoteEvent:FireAllClients({Msg = "updateRoundGuiStartingRound"})
				task.wait(2)
				remoteEvent:FireAllClients({Msg = "changeCam"})

				local assignments = roundSys.spawnChars()
				roundSys.assignMapCollisionGroups()

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
