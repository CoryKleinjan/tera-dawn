# NPCs, quests and shops

Part of the [architecture docs](../../ARCHITECTURE.md).

## How to add an NPC

Create `data/npcs/<id>.tres` as an **NpcDef** (name, title, sprite, a `greeting`, and the
`lines` they say when you pick Chat), then place it on a map with an **NpcPlacement**.
Pressing Up next to them opens `TDDialogueWindow`, which lists what they offer. To make NPCs
offer something new, add an option in `TDDialogueWindow._options()`.

## How to add a quest

Create `data/quests/<id>.tres` as a **QuestDef**: a title, the `giver` NPC id (and a
`turn_in` NPC if someone else takes it back), who can take it (`min_level`, `jobs`, quests it
`requires`), what the NPC says when offering it, while it's in progress and when it's handed
in, its **QuestObjective**s, and its rewards (EXP, Dawnshards, items). Objectives are:

- **KILL** `count` of a `monster`;
- **COLLECT** `count` of an `item` (taken when handed in). Give it a `drop_from` monster and a
  `drop_chance` to make a quest item that only drops for players on the quest (set
  `quest_item` on the ItemDef so it can't be sold or dropped);
- **VISIT** a `map`.

NPCs offer their quests on their own: a "!" over their head when one is available, "?" when
one is ready to hand in. `QuestLog` (in `Character`) holds progress and the rules; the
server's `on_quest_accept` / `on_quest_complete` apply them.

## How to add a shop

Create `data/shops/<id>.tres` as a **ShopDef**: a name and a list of **ShopEntry**s (an item
and its price; 0 means four times what a shop pays for it). Set it as an NpcDef's `shop` and
they offer "Open shop". Every shop also buys anything for the item's `sell_price`. The server
checks the player is standing by that NPC before buying or selling (`TDServer.on_buy`).
