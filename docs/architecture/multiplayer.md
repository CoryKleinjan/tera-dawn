# Multiplayer and players together

Part of the [architecture docs](../../ARCHITECTURE.md).

## Multiplayer: server and client

Tera's Dawn is played solo or in co-op: up to `Net.MAX_PLAYERS` (4) players, one of them
hosting and the others joining with characters of their own. There is always a server, even
in single player:

```
             requests (req_*)                    events (ev_*)
TDWorld  ───────────────────────►  TDServer  ─────────────────────►  TDWorld (every player
(your game)   through Net           MapInstance per map                on that map)
```

- **Server** (`scripts/server/`): `TDServer` holds every connected player as a `SimPlayer`
  (their `Character`, position and timers) and runs one `MapInstance` per visited map: its
  `SimMob`s, the `SimDrop`s on the ground and the players on it. It decides everything that
  matters: hits, damage, kills, EXP, levels, drops, who picks what up, HP and MP, potions,
  gear, portals, fainting. It never keeps characters itself: it sends them back to their
  players' games to save (`TDServer.save`, `ev_save`). `TDServer` itself keeps the players, maps, saving and the requests about moving and
  fighting; the other requests are handled by its parts in `scripts/server/services/`
  (`ServerItems`, `ServerNpcShop`, `ServerStorage`, `ServerTravel`, `ServerQuests`,
  `ServerJobs`, `ServerScenes`, each a `ServerPart`), the way `TDSocial` splits into
  `scripts/server/social/`. `ServerMoves` (`scripts/server/server_moves.gd`) runs the server's
  side of the job movement skills.
- **Client** (`scripts/world/`, `scripts/actors/`): `TDWorld` shows the map you're on. Your own
  hero (`TDPlayer`) moves and climbs on your machine so it feels instant, like MapleStory, and
  reports where it is 20 times a second; the server checks the report is possible and puts you
  back if not. Monsters (`TDMob`), other players (`TDAvatar`) and drops (`TDDrop`) are views
  that glide to where the server's snapshots say they are (`SnapshotSync` keeps them in step;
  `WorldCamera` follows your hero). Snapshots go out 20 times a
  second as packed bytes (`SnapshotCodec`) so even a busy map fits in one network packet:
  they hold only positions, facing, HP, animation and flags, and leave out monsters that
  haven't changed (every monster goes in once a second). A player's name, level, look, gear,
  chair and pet go separately (`ev_player_info`), reliably and only when they change.
- **Net** (`scripts/autoload/net.gd`) is the whole protocol in one file. `req_*` methods go from
  a client to the server (grouped by the server part that answers them), `ev_*` methods from the server to clients. UI and actors call
  `Net.ask(&"req_…", [args])`; the server answers with events, and `Game.me` (your copy of
  your Character) is refreshed from them. Never change `Game.me` to make something happen.

The three ways to play all use the same rules: **Solo** runs a server inside the game with
an offline peer (messages never touch the network), **Co-op > Host** does the same on an
ENet port so friends can join, and **Co-op > Join** connects to a host's port.

Hosting on a home network: character select shows the host what friends type to join
(`TDHostPanel`, `scripts/ui/host_panel.gd`): this computer's home network address from
`LanHost` (`scripts/net/lan_host.gd`), with a Copy button. On Windows, `LanHost` checks for
the game's firewall rule (UDP on `Net.port`, private and work networks) and, when it's
missing, the panel offers to add it through Windows' admin prompt, on a thread. The Join
page's address box takes `address:port` (`ServerAddress`); a plain address uses
`Net.DEFAULT_PORT`.

### Characters on each computer, and character select

There are no accounts or passwords. Every player's characters are saved on their own
computer, and they bring one along to whatever game they play.

- **`CharacterStore`** (`scripts/systems/character_store.gd`, on the client) keeps one JSON
  file per character name in `Net.save_dir` and the order they were made in `order.json`.
  It makes characters (`create`: a clean name not already used on this computer, in any
  case; a name whose file another name already uses, like `Al pha` and `Al_pha`, is refused
  as too close; at most `MAX_CHARACTERS`), lists them for character select (`slots`), and
  moves a deleted character's file to `deleted/`. `Net.saves` is the one character select
  shows (`Net.open_saves`: this computer's own, or the test characters with the Developer
  setting on, see [windows and settings](ui.md#settings)).
- Making, deleting and listing characters never touches the server: `Net.create_character`,
  `Net.delete_character` (the player must type the name) and `characters_changed`.
- **`TDLobby`** (`scripts/server/lobby.gd`, owned by the server) handles a player before
  they're in the world. A friend who connects gets `ev_welcome` (on to their character
  select), or, when the game already has `Net.MAX_PLAYERS` counting the host, `ev_refused`
  ("This game is full") and is dropped. `Net.play` sends the picked character's data with
  `req_play`; `TDLobby.on_play` reads it (`CharacterStore.from_dict`, which also settles its
  Skill Points), puts it on the starting map if the game doesn't have the map it was on, and
  `TDServer.enter_game` refuses a name that's already playing. `req_leave_character` saves
  and answers `ev_left_world` (back to character select, still in the game; leaving while
  fainted wakes you in town first). Every other request is ignored until a character is in
  the world, because the server finds the player by peer first.
- **Saving**: the server sends each player their character (`ev_save`) every
  `TDServer.SAVE_EVERY` ticks, on map changes, level ups and other big moments, when they
  leave the world, and when the host stops. `Net.ev_save` writes it to `Net.saves`, only for
  the character being played. The host's own character goes the same way, to itself.
- **Encryption** (`TDTls`): a host turns on DTLS for ENet with the key and certificate in
  `<save folder>/tls/` (a self-signed pair is made the first time). Joining always
  encrypts, but checks the host's identity only when the game ships its certificate as
  `res://certs/<address>.crt`, so hosts are encrypted but not verified.
- On the client, the title screen (`TDTitleScreen`, `scripts/ui/title_screen.gd`) has Play
  (Solo, or Co-op with Host and Join, which asks for the host's address), answers `Net.welcomed`,
  `characters_changed`, `refused`, `joined` and `disconnected`; `TDCharacterSelect` (on it)
  shows the list and `TDDeleteConfirm` asks before deleting. `TDHud` only shows and hides it
  and handles Esc. `settings.cfg` remembers the last host address.
- A host that leaves with friends connected is asked first (`TDConfirm`). Whenever a host
  stops, it saves everyone (their `ev_save`), then its friends get `ev_host_ended` ("The
  host ended the game."), and the connection stays open a moment (`Net.GOODBYE_TICKS`) so
  it gets there.

Shared pieces both sides use: `MapLayout` (a map's platforms, ropes, portals), `DropFlight`
(how a drop flies and lands, run identically everywhere), `Combat` and `CharacterStats`.
Monster index `i` is the same monster on both sides because both build them from
`MapDef.roster()`: the map's spawns in order, each monster that splits followed by the
monsters it splits into (those sleep, dead, until their parent is defeated).

### Players together

`TDSocial` (`scripts/server/social.gd`, owned by the server) runs everything players do with
each other: chat and its slash commands, invitations (`ev_invite` / `req_invite_answer`),
buddies (kept on the Character), parties (server memory only; `party_shares` hands out kill
EXP), trades (offers are held by the server until both press Trade, then swapped, or handed
back on cancel), guilds (saved in `guilds.data` next to the character saves) and fame. Each player gets a summary of their buddies, party and
guild through `ev_social` whenever it changes (`Game.social`); the community window, the
player menu, the party HP list and the trade window (`scripts/ui/windows/`) read it.

`TDSocial` holds the shared state and is what the server and `Net` call; the work is done by
its parts in `scripts/server/social/`, one per section: `SocialChat` (chat and slash commands),
`SocialParties` (invitations, buddies, parties), `SocialTrade` and `SocialGuilds` (guilds and
fame). A new social feature gets its own part (extend `SocialPart`)
and a forwarding method on `TDSocial`.
