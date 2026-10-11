# Multiplayer, accounts and players together

Part of the [architecture docs](../../ARCHITECTURE.md).

## Multiplayer: server and client

Tera's Dawn is online, and there is always a server, even in single player. One codebase plays
three roles:

```
             requests (req_*)                    events (ev_*)
TDWorld  ───────────────────────►  TDServer  ─────────────────────►  TDWorld (every player
(your game)   through Net           MapInstance per map                on that map)
```

- **Server** (`scripts/server/`): `TDServer` holds every connected player as a `SimPlayer`
  (their `Character`, position and timers) and runs one `MapInstance` per visited map: its
  `SimMob`s, the `SimDrop`s on the ground and the players on it. It decides everything that
  matters: hits, damage, kills, EXP, levels, drops, who picks what up, HP and MP, potions,
  gear, portals, fainting. `CharacterStore` saves characters, one JSON file per name.
  `TDServer` itself keeps the players, maps, saving and the requests about moving and
  fighting; the other requests are handled by its parts in `scripts/server/services/`
  (`ServerItems`, `ServerNpcShop`, `ServerStorage`, `ServerTravel`, `ServerQuests`,
  `ServerJobs`, each a `ServerPart`), the way `TDSocial` splits into `scripts/server/social/`.
- **Client** (`scripts/world/`, `scripts/actors/`): `TDWorld` shows the map you're on. Your own
  hero (`TDPlayer`) moves and climbs on your machine so it feels instant, like MapleStory, and
  reports where it is 20 times a second; the server checks the report is possible and puts you
  back if not. Monsters (`TDMob`), other players (`TDAvatar`) and drops (`TDDrop`) are views
  that glide to where the server's snapshots say they are (`SnapshotSync` keeps them in step;
  `WorldCamera` follows your hero). Snapshots go out 20 times a
  second as packed bytes (`SnapshotCodec`) so even a busy map fits in one network packet:
  they hold only positions, facing, HP, animation and flags, and leave out monsters that
  haven't changed (every monster goes in once a second). A player's name, level, look, gear,
  chair, pet and shop sign go separately (`ev_player_info`), reliably and only when they change.
- **Net** (`scripts/autoload/net.gd`) is the whole protocol in one file. `req_*` methods go from
  a client to the server (grouped by the server part that answers them), `ev_*` methods from the server to clients. UI and actors call
  `Net.ask(&"req_…", [args])`; the server answers with events, and `Game.me` (your copy of
  your Character) is refreshed from them. Never change `Game.me` to make something happen.

The three ways to play all use the same rules: **Play solo** runs a server inside the game with
an offline peer (messages never touch the network), **Host** does the same on an ENet port so
others can join, and `-- --server` (see `scripts/boot.gd`) runs a server with no player.

### Accounts and character select

Every server has its own accounts, and every character belongs to one account on the server
it was made on. Nothing is shared between servers, so characters never move to another one.

- **`TDLobby`** (`scripts/server/lobby.gd`, owned by the server) handles a connection before
  it's in the world: `req_register` / `req_login` (answered with `ev_logged_in` or
  `ev_refused`), then character select: `req_create_character`, `req_delete_character`
  (the player must type the name), `req_play` (into the world, `ev_joined`) and
  `req_leave_character` (back to the list; leaving while fainted wakes you in town first).
  `ev_characters` sends the list again. Every other request is ignored until a character is
  in the world, because the server finds the player by peer first. An account has at most `TDLobby.MAX_CHARACTERS` characters. Logging in
  with the right password while the account is logged in somewhere else (a crashed game,
  say) takes over: the old connection is told why, its character is saved and it's dropped.
- **`AccountStore`** keeps accounts in `<save folder>/accounts/`: the username, a
  `PasswordHash` record and the names of the account's characters. Passwords are never
  stored: `PasswordHash` is PBKDF2-HMAC-SHA256 with a random salt and 100,000 rounds (kept per
  record, so it can be raised). Checking a password runs on a worker thread.
- **`LoginGuard`** counts wrong passwords by where they come from (`Net.address_of`, the
  connection's IP address), so a stranger can't lock the owner out: it drops a connection
  after 5 wrong passwords, locks a username for 30 seconds for an address that got it wrong 5
  times in a row, and makes an address wait after each wrong password, whatever the username
  (1 s, then 2, 4... up to a minute, until it gets one right). A wrong username and a wrong
  password get the same answer and take as long.
- **The local account** (`AccountStore.LOCAL`): in single player and when hosting, the
  player at the keyboard (peer 1) logs in with `req_local_login` and no password.
  In a debug build with the Developer setting on, it asks for the test characters' account
  instead (`TestCharacters`, see [windows and settings](ui.md#settings)).
- **`CharacterStore`** still keeps one file per character name (names are unique on a
  server, in any case; a name whose file another name already uses, like `Al pha` and
  `Al_pha`, is refused as too close). A deleted character's file moves to `deleted/` for the
  server's owner, and its name comes off every character's buddy list and fame records.
- **Encryption** (`TDTls`): host and dedicated servers turn on DTLS for ENet with the key and
  certificate in `<save folder>/tls/` (a self-signed pair is made the first time). Clients
  always encrypt; they check the server's identity only when the game ships its certificate
  as `res://certs/<address>.crt`, so other servers are encrypted but not verified.
- On the client, `Net.log_in` connects and sends the username and password once the
  connection is up (the password isn't kept), the title card (`TDHud`) has the login and
  register boxes, `TDCharacterSelect` shows the list and `TDDeleteConfirm` asks before
  deleting. `settings.cfg` remembers the last username and server, never the password.
- A host that logs out with friends connected is asked first (`TDConfirm`). Whenever a host
  stops, its friends get `ev_host_ended` ("The host ended the game."), and the connection
  stays open a moment (`Net.GOODBYE_TICKS`) so it gets there.

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
back on cancel), guilds (saved in `guilds.data` next to the character saves), fame, and player
shops on maps with `MapDef.market`. Each player gets a summary of their buddies, party and
guild through `ev_social` whenever it changes (`Game.social`); the community window, the
player menu, the party HP list and the trade and shop windows (`scripts/ui/windows/`) read it.

`TDSocial` holds the shared state and is what the server and `Net` call; the work is done by
its parts in `scripts/server/social/`, one per section: `SocialChat` (chat and slash commands),
`SocialParties` (invitations, buddies, parties), `SocialTrade`, `SocialGuilds` (guilds and fame)
and `SocialShops` (player shops). A new social feature gets its own part (extend `SocialPart`)
and a forwarding method on `TDSocial`.
