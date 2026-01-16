Card System — How to Add Cards and Test
======================================

Overview
--------
Cards live as small ModuleScripts under `ReplicatedStorage.Shared.Cards`. Each card module must return a table with a minimum API:

- `Id` (string): unique identifier
- `Name` (string): display name
- `Description` (string)
- `Icon` (string): asset id for client UI
- `CanUse(player, ctx)` (optional): return `true` or `false, reason`
- `OnUse(player, ctx)` (required): performs effect server-side and returns `true` on success

Example template:

```lua
local Card = {}
Card.Id = "example"
Card.Name = "Example Card"
Card.Description = "Does something interesting"
Card.Icon = "rbxassetid://123"

function Card.CanUse(player, ctx)
    return true
end

function Card.OnUse(player, ctx)
    -- Server-side effect here
    return true
end

return Card
```

Integration
-----------
- Card registration: `cardManager` automatically requires modules in `ReplicatedStorage.Shared.Cards` on server start.
 - Acquisition: `cardManager.GenerateCardTiles(n)` chooses `n` random `Fields` parts, tags them with `CardFillTile`. When a figure lands on a tagged part, `cardManager` gives a random card if the player's hand has < 3 cards.
- Usage: clients call `remoteEvent:FireServer("RequestUseCard", cardUid, ctx)`; `cardManager` validates and calls the card's `CanUse`/`OnUse`.
- Deck hook: `cardManager.SetDeckProvider(function(player) return {"card_id_1", "card_id_2"} end)` lets you constrain random cards to a player-defined deck (e.g., 10 cards chosen in lobby).

State & Attributes
------------------
- Player hand: kept server-side in `cardManager` (max 3 items). Clients receive updates via `{Msg="CardHandUpdate", Cards = ...}`.
- Cards are consumable by default. If a card implements persistent effects (like protection), use attributes on Figures (e.g., `protectedTurns`) and ensure `gameDynamics` checks/updates them.

Testing
-------
1. Quick manual test in Studio:
   - Start a server in Studio, join as multiple players.
   - Ensure `CardGuiCreator.client.luau` runs (it creates a `CardGui` in `PlayerGui`).
    - Start the round — `cardManager` will call `GenerateCardTiles(4)` and clients receive `CardTilesUpdate`.
    - Move a piece onto a tile named in `CardTilesUpdate` and land on a `CardFillTile` to receive a card.

2. Scripted test helper (manual run):
   - Create a ServerScript that requires `ReplicatedStorage.Shared.cardManager` and calls `GiveSpecificCard(player, "protect")` for a target player to verify client receives `CardGranted` and `CardHandUpdate`.

Edge Cases
----------
- Clients must not be trusted; all validation is implemented server-side in `cardManager` and in card modules.
-- If you want card tiles to be consumable (disappear when used), modify `cardManager.HandlePlayerLandingByFigure` to `CollectionService:RemoveTag(part, "CardFillTile")` and call `GenerateCardTiles(1)` to respawn.
- Cards that require a target figure use `RequestCardTarget` and the existing figure selector UI (context = `CardTarget`).

Adding New Card Types
---------------------
1. Create a ModuleScript in `ReplicatedStorage.Shared.Cards` using the template above.
2. Implement `CanUse` to validate targets and `OnUse` to perform authoritative effects.
3. Use attributes and existing `gameDynamics` functions (or add small helper APIs) to interact with the board.

If you want, provide a new card spec and I'll implement it as an example.
