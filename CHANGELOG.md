# Chairface's Casino — Changelog

## Chairface's Casino v2.6.8 (2026-09-28)

### Changed
- **Made for WoW Forever.** The casino now lists WoW Forever as its only game version, so CurseForge offers it there and nowhere else.
- **A new welcome from Trixie.** The once-only intro now reads you the whole Welcome to the Casino panel, then ushers you in: a drink on the house, the new Slot Floor out back, and Lady Luck asking after you. About a minute long; Let's Play! still cuts her off.

## Chairface's Casino v2.6.7 (2026-09-28)

### New
- **The Slot Floor.** The lobby's Slots button now opens a floor of six machines, each with its own look, rules and bonus features:
  - **Azeroth Riches**, the house machine, with its progressive jackpots.
  - **Kodo Stampede**: 1,024 ways, stacked kodos, and stampede free games whose wilds multiply.
  - **Pharaoh of Uldum**: 20 lines, wilds that double every win they join, and free spins that pay triple.
  - **Darkmoon Wheel**: a three-reel classic with Double Diamond wilds, and a prize wheel when you play max coins.
  - **Jade Fortunes**: 243 ways, gold levels that unlock the Mini to Grand jackpots, and the Fu Bat pick.
  - **Tel'Abim Bonanza**: pay anywhere, tumbling wins, and free spins with multiplier bombs.
- **Every machine pays back about 95%**, the same as Azeroth Riches, so no machine on the floor is a better or worse bet than another. Darkmoon Wheel is balanced at max coins: its wheel only spins then, and fewer coins pay back less, as on the real thing.

## Chairface's Casino v2.6.6 (2026-09-28)

### Changed
- **Trixie has a new voice.** All 1,125 of her lines, her intro and her pokes were re-recorded with ElevenLabs' Eleven v4, each line directed for its moment: warm greetings, teasing banter, excited wins, a sigh at a push. She no longer pauses awkwardly around "sugar". The 19 lines that never got recorded before are in too.
- **Voice Frequency means what it says.** Always: she speaks every time. Frequent 60%, Normal 35%, Occasional 15%, Rare 4% of the time. Table-open calls still always play. She never talks over herself: a line that comes up while she is speaking is dropped, not queued, and the check uses each clip's real length.
- **Gem Rush** comes around about 1 pull in 11 and **always pays something** (about 4x your bet on average). No wilds on the rush reels any more. The reels start rolling a moment after the GEM RUSH blinder appears, while Trixie is still talking, instead of waiting out her whole line.
- **Azeroth Riches is rebalanced** so a session lasts: two of a kind now pays on the six best symbols (wild, skull, gold, ruby, emerald, sapphire), so nearly half of all spins pay something. The chest, wheel and free-spins bonuses pay less, and a jackpot pays at most a multiple of your bet (the rest of the pot stays for the next winner). The machine returns about 95% at every bet size: before, it paid out far more than it took in.

## Chairface's Casino v2.6.5 (2026-09-28)

### Changed
- **Credits read Chairface Chippendale** in the AddOns list and the lobby.
- **An About tab in Settings** says who makes the casino, with a quiet note
  that in-game gold mailed to Chairface Chippendale is appreciated.
- **Buying arcade credits asks how many lots to buy**, at 10g for 10,000
  credits each, rather than for a gold amount in 10g steps. Every price shown
  follows the rate.
- **First names everywhere.** Every game, the leaderboard and the debts window
  show players by first name. When two people there share a first name, both
  show their whole name ("Chairface Chippendale", "Chairface Cobblestone") in
  a slightly smaller font so it still fits. This replaces the shortened
  surnames ("Chairface Ch.").
- **Chair's Cup:** the horses are nearly twice as large and sit centered on their
  lanes, and horses 1 and 5 no longer drift over the outer rail or into the
  infield: the field starts behind the line along each lane rather than by a
  fixed nudge on screen.
- **The version reads "Chairface's Casino v2.6.4"** in the lobby's corner, the
  minimap button's tooltip and the "loaded" line in chat.

### Fixed
- **The debug GRANT button** shows only while debug mode is on, and no longer
  covers anything: on the slot machine it hangs below the cabinet, and Video
  Poker grows a little taller to make room for it.
- **No more "blocked" error when opening the slot machine** on WoW Forever.
  The jackpot sync, the leaderboard's realm hello and the Table Finder send on
  the casino's hidden channel, and Forever doesn't let addons type chat into
  a channel. They now send addon messages there, which is allowed, and older
  copies elsewhere still get the chat line.
- **Fill Mail works again.** It no longer clicks the mailbox's Send Mail tab
  for you (addons can't drive Blizzard's windows). Press Fill Mail, then open
  the Send Mail tab if it isn't already open, and the mail fills in. Anything
  the client won't let it fill is named in chat so you can type it yourself.
- **Fill Mail opens the Send Mail tab for you** when you're on the inbox. The
  button clicks the tab the same way you would, then fills in the mail.
- **Buy Casino Credits mails the right banker on WoW Forever.** The mailbox
  button filled in "Chairface", which is no one on Forever; it now fills in
  "Chairface Chippendale", and a purchase mailed there by hand counts too.
- **Chair's Cup bets and debts use whole names again.** Since v2.6.4 the race
  keyed bets, debts and leaderboard results by first name only, so two bettors
  with the same first name were merged into one. The race now shows first names
  but keys everything by the whole name, as the other games do.

## v2.6.4 (2026-09-27)

Compatible with every 2.6.x.

### WoW Forever's two-word names
- **The casino knows who you are again.** On WoW Forever the game hands
  addons a character's first name and surname separately, and only the first
  name was being read ("Highley"), while everyone else sees "Highley
  Regarded". Your own seat, turns, rolls, trades, debts and test mode now use
  the whole name.
- **The games show first names.** Every Forever name is a first name and a
  surname; at the tables, on Crash parachutes and the rider list, Bingo
  cards, Liar's Dice, High-Lo, Death Roll, the Derby, and in each game's
  host line, players are shown by first name alone. Only when two share a
  first name does as much of the surname appear as it takes to tell them
  apart ("Chairface Ch." and "Chairface Co."). The leaderboard and the debts
  window keep full names, cut with "..." instead of wrapping into the next
  row.
- **Test commands take two-word names:** `/cc test arcade grant Sewer Urchin
  50`, `/cc test debt add Sewer Urchin Chairface Chippendale 25`.
- **Test mode's fake players** have two-word names, so a test table shows
  how real names lay out.
- **Test mode** (and the GRANT button and leaderboard reset it guards)
  recognizes the Forever characters it is meant for.

## v2.6.3 (2026-09-27)

Compatible with every 2.6.x — no need for everyone to update at once.

### Fixed
- **No more Lua errors from ordinary chat on WoW Forever.** Forever can hand
  addons a channel message (General, Trade, ...) that can't be read, and the
  jackpot, leaderboard and Table Finder listeners tripped over it. Chat from
  other channels is now ignored before it is read, and a message the client
  keeps private is skipped instead of throwing an error.
- **Death Roll and High-Lo read rolls from two-word names.** Every Forever
  name has a first name and a surname ("Chairface Chippendale rolls 42
  (1-100)"), and only the surname was being read, so the roll went to nobody.

## v2.6.2 (2026-07-15)

Compatible with 2.6.0 and 2.6.1 — no need for everyone to update at once
(but hands recorded by hosts on older versions still count instantly; the
new settle-up rule applies to tables hosted on 2.6.2).

### The leaderboard now runs on settled gold — and a fresh season
- **New leaderboard season!** The all-time board resets for everyone on
  first login with 2.6.2. Your personal stats panel (best win, worst loss,
  pushes) is kept. Old-season boards can't leak back in, even from players
  who haven't updated.
- **Hands only count once the debt is settled.** A win lands on the shared
  board when the gold behind it actually moves: the loser pays up by trade,
  or later results square the pair's tab on their own. No more padding the
  board with wins nobody ever intends to pay.
- **Forgiven debts never count.** If a creditor forgives a tab, the hands
  waiting on it are voided, not counted.
- **Free-play games stay off the board.** FREE PLAY rounds record no debts,
  so they no longer feed the shared leaderboard either — play for fun
  without touching the rankings. Your personal stats panel still tracks
  everything, settled or not, fun or real.
- Pushes and break-even hands count immediately (nothing was owed), and
  unsettled hands are remembered across logouts — pay a tab three days
  later and the hands it was holding back appear on the board.

### Hardening
- **The board can't be griefed from across the realm.** All incoming
  leaderboard data is now sanity-checked (garbage payloads and absurd
  numbers are dropped), unsolicited data pushes are ignored, and the remote
  stats-wipe debug command only works from authorized characters.
- **Fixed a channel-spam buildup**: idle sessions could queue up dozens of
  identical realm announcements and dump them all on your next casino
  click.
- **Smoother settlements**: the board's encrypted save no longer runs twice
  per hand during a big table's payout (it batches now), so multi-seat
  blackjack settlements won't hitch.
- **"Reset My Data" is now "Reset My Stats"**: it clears your personal
  stats panel. (The shared board rows live on every player's client, so a
  local delete never really removed them — now the button is honest about
  what it does.)
- **Trixie's GEM RUSH intro line plays again** — it went quiet when her
  voice clips were converted to a new audio format.

## v2.6.1 (2026-07-12)

Compatible with 2.6.0 — no need for everyone to update at once.

### Fixed
- **Poker windows no longer reserve Trixie's space when she's turned off.**
  If you had the dealer hidden on 5 Card Stud or Texas Hold'em, the window
  still opened at full width with a blank column where she would have stood,
  until you toggled the setting off and on again. Both tables now size
  themselves correctly the first time they open.

## v2.6.0 (2026-07-12)

**Please update everyone in your group to 2.6.0** — this is a new major
version, so 2.5.x clients can't sit at your tables. (All of the v2.5.4 notes
below ship in 2.6.0 too; 2.5.4 was never released on its own.)

### Trixie has a lot more to say
- **She calls the room.** When you open a table, Trixie now *says the game
  out loud* — "Blackjack's open!", "Crash is boarding!" — so groupmates with
  the addon know to jump in. (This alert always plays when unmuted, ignoring
  your voice-frequency setting, so it's reliable.)
- **10× the variety.** Wins, busts, blackjacks, jackpots, big slot hits,
  paying and collecting debts, Death Roll's final "1", Crash bail-outs and
  booms, Roulette's "no more bets", Bingo wins, Liar's Dice reveals,
  Hold'em tournament crownings and bust-outs, climbing high on the zeppelin,
  folding, turn nudges, the pre-deal countdown — dozens of fresh lines for
  the moments that matter.
- **One line at a time.** Back-to-back events (pay a debt, then close a
  window) no longer stack two or three overlapping voice clips over each
  other.
- Every line still respects your **mute** and **voice-frequency** settings.

### A cozier casino
- **Tavern backdrop on the utility windows.** Settings, How to Play, the
  Leaderboard, Debts, and the Table Finder now sit on the casino artwork
  instead of a flat panel, and each window was reshaped to show it off.
- **Felt tables everywhere.** Liar's Dice, Death Roll, Roulette, and Bingo
  now play on the same green felt as poker and High-Lo.
- **Lobby facelift.** The game grid is laid out 3 tall × 4 wide (dice games
  in the first column, card games in the second, and so on), and the lobby
  and utility buttons have a lighter, see-through look.
- **Tidier navigation.** Opening Settings, How to Play, the Leaderboard, or
  Debts now hides the lobby and returns to it when you close them.

### How to Play
- The **Texas Hold'em** page now lists the full hand rankings (Royal Flush
  down to High Card) instead of pointing you at the 5 Card Stud page.

### Fixes
- Fixed a crash-spam bug where the realm-wide leaderboard sync and the
  shared slots jackpots could throw "Invalid escape code in chat message"
  when talking over the shared channel.
- Table-open callouts to non-addon players are limited to the host's own
  party or raid.

## v2.5.4 (2026-07-12)

Wire-compatible with 2.5.0–2.5.3 — no forced update.

### Free play is now impossible to miss
- When you go to join a table that was opened on **fake play**, a loud red
  **"⚠ FREE PLAY — NO DEBTS ⚠"** banner pulses over the join button — in
  every game (the derby, which has no single join button, shows it across
  the top of the board). No more finding out after the fact that a game
  wasn't recording because someone left fake play on.
- The fake-play checkbox itself now reads a bright red **"FREE PLAY ON"**
  when it's checked, so a host notices before opening a table.
- Reaffirmed: a table's fun/real status is fixed at the **host's** setting
  the moment they open it. No other player's toggle, and no mid-game flip,
  can ever change whether a running table records debts.

### Leaderboard: new season + realm-wide sync + two more games
- **Crash and Chair's Cup now have leaderboards.** Crash was already being
  recorded but had no tab; the Chair's Cup (derby) now records every race's
  net (each bettor and the house) and both games have their own board.
- **Fresh season.** The all-time leaderboard resets once for a clean,
  server-wide start. Your personal stats (best win / worst loss) are kept.
- **Syncs across the whole server.** Boards no longer sync only within your
  party/raid: casino players anywhere on the realm now reconcile their
  all-time boards with each other (discovery over the shared hidden channel,
  the actual data over whisper), so you'll see players you've never grouped
  with. Hit **Sync Now** on the leaderboard to announce yourself.
- Season-tagged sync keeps the reset from being undone: buckets from a
  different season (or a not-yet-updated client) are ignored.
- Tests: `tests/leaderboard_season_test.py` (season reset, season isolation,
  never-seen-peer realm reconcile).

### Slots: shared progressive jackpots
- The progressive pots now **sync across players**. The first time you open
  the machine, your client pulls a shared baseline (the biggest pot each
  peer has for every tier) so everyone starts from the same numbers, then
  each client accrues on its own from there.
- **The pot resets for everyone when someone hits it.** Claim a Mini / Major
  / Mega and every other player's copy of that tier drops back to its seed,
  just like a real bank of linked machines.
- Reach is guild + party/raid (instant) plus the shared hidden realm channel
  (so realm-wide players see resets too); it's a light one-time-then-local
  scheme, so it never spams the network.

### Trixie takes the mic — now with a voice
- **She calls the game the moment it opens.** When anyone in your group hosts,
  Trixie *speaks* it — "Blackjack's open!", "The zeppelin's leavin' — Crash is
  open!" — a different line for every one of the nine games, so other addon
  players in the group/raid hear a table went live (with the old coin chime as
  a fallback when she's quiet).
- **She tells your group when you host.** Opening a table also posts it in your
  **party/raid chat**, so groupmates who don't run the addon see it too. Stays
  inside your group; throttled to once per 5 min per game.
- **A LOT more to say.** Her voice lines are expanded roughly ten-fold across
  every occasion — greetings, banter, farewells, wins, losses, busts, naturals,
  jackpots, big wins, and settling debts — plus **situation-specific** lines
  like rolling the fatal one in Death Roll, bailing out of Crash in time, or
  riding the zeppelin into the ground.
- **Everything obeys your Voice settings.** Every spoken line now respects the
  **mute** toggle and the **Voice Frequency** slider (Always → Rare), so you're
  fully in control of how chatty she is. Set it to Always if you want her to
  call every table.
- Chat chatter still toggles under **Settings → Trixie**; the party/raid
  announce has its own checkbox.

### A proper casino for a backdrop
- The lobby now sits in front of a **rowdy Azerothian casino** scene — a warm
  chandelier, hanging pennants, moonlit arches, a boozy crowd raising mugs,
  and cards and dice in the air — dimmed behind the game grid so everything
  stays readable.

### Lobby: condensed game grid
- The lobby is now a tight **4 × 3 grid** — one icon to the left of each
  name, no gaps between buttons, and it sits right under the animated logo.
  Row 1 dice (High-Lo / Death Roll / Liar's Dice), row 2 cards (Texas
  Hold'em / 5 Card Stud / Blackjack), row 3 Chair's Cup / Roulette / Crash,
  row 4 Bingo / Slots / Video Poker. Slots is now titled **Azeroth Riches**.

## v2.5.3 (2026-07-11)

Wire-compatible with 2.5.0–2.5.2 — no forced update.

### Crash: fly-away hardened
- The fly-away ending is now decided by the pilot's flight ticker, which
  **re-verifies the ship is empty on every pass for the whole escape run**.
  Previously a one-shot 3-second timer judged "everyone's out" once when a
  jump emptied the ship and never checked again before ending the round.
- Final safety net: even if a fly-away is requested with riders still
  aboard, she **explodes on schedule instead** — a fly-away can never end a
  round while anyone is on the ship.
- The close call is unchanged: a crash tick that lands during the escape
  run still blows her up on screen, and riders with pending auto-jumps
  still count as aboard.
- New regression suite (`tests/crash_flyaway_test.py`) drives whole flights
  through the real ticker: first-of-three jumps, all-out fly-away, the
  close call, pending auto-targets, and the illegal-fly-away downgrade.

## v2.5.2 (2026-07-10)

Wire-compatible with 2.5.0/2.5.1 — no forced update, but hosts want this one.

### Fake play locks in when the table opens
- A table's fun/real status is now **frozen the moment it's hosted**, for
  every game. Flipping the fake-play toggle mid-game no longer changes how
  the running table settles — the change applies to the next table you host.
- Joiners see what they're sitting down to: every game's table announcement
  carries a **(fun game — no debts)** tag when it applies, and the table's
  terms survive host transfers, host reloads, and mid-game rejoins.
- Toggling while a table is running prints a reminder that the running
  table keeps the terms it opened with.

### Hold'em tournament: winner-take-all
- The champion now collects the **entire prize pool** (every buy-in,
  walkouts included). The 50/30/20 top-three split from 2.5.0 was sized
  for multi-table fields; with one table it mostly refunded the
  runners-up. Multi-table tournaments may return if there's demand.
- Mixed tables: the debts always follow the HOST's version, so have the
  host update first.

### Quality of life
- **Rejoin reopens your window.** Reload or crash mid-game and, once you're
  synced back in, your seat's window pops back up on its own (only if you
  were actually seated — watching a sync never opens windows).
- **Stake memory.** Every host panel now remembers what you last hosted
  with — stakes, antes, card price, max roll, roulette chip and bet cap,
  Hold'em settings — and pre-fills it next time. (Also fixed a long-standing
  bug where some saved settings were silently dropped every login.)
- **Timeout notices.** When the host's watchdog force-plays someone who
  disconnected or left, everyone at the table sees a one-line notice saying
  who and why.

### Under the hood
- High-Lo host transfers now carry an epoch, so a stale ex-host coming back
  from a disconnect can never hijack or double-settle a table that already
  moved on.

## v2.5.1 (2026-07-10)

Wire-compatible with 2.5.0. A hardening pass over every game's disconnect
and host-recovery behavior:

- **No more stalled tables.** If the player whose turn it is disconnects or
  leaves the group, the host now force-plays the safe default for them
  (stand in Blackjack, check/fold in the poker games, the minimal call in
  Liar's Dice) instead of the table waiting forever.
- **Host recovery actually recovers.** Poker and Hold'em clients no longer
  void a live game when the host returns; temp-host recovery broadcasts
  are accepted properly in all three card games; version bookkeeping after
  a host reclaim no longer desyncs later broadcasts.
- **Cleaner voids.** Roulette and the Chair's Cup void the round if the
  host stays offline past a 2-minute grace (instead of hanging); High-Lo
  voids cleanly when nobody can take over (instead of erroring); Crash
  gives the pilot a 15-second grace on a connection blip before voiding.

## v2.5.0 (2026-07-10)

**Everyone must update: 2.5.0 tables reject 2.4.x clients** (the crash-point
math and the tournament wire changed — a clean version wall beats a desync).
Manual installers: delete the old folder before extracting (the file layout
was reorganized).

### Crash — the big one
- **The real zeppelin flies.** The hand-drawn ship is replaced by a
  pre-rendered animated sprite of the actual transport zeppelin — spinning
  propellers and all — at twice the old size, departing from the real
  zeppelin tower.
- **Welcome to Tirisfal.** A hand-authored forest track (eight rendered
  Tirisfal trees — pines, dead spindles, stumps, one lone oak), a dense
  deep-forest parallax wall, and craggy snowcapped mountains filling the
  background. Every flight passes the same fixed world.
- **A story per flight**: she lifts off clean, catches fire at 50m, trails
  smoke from 70m, and the smoke now streams a long way behind her.
- **Bigger boom**: the explosion is a two-depth burst — debris behind AND in
  front of the ship — in full fire colors.
- **Fly-away and the close call**: if every rider jumps, the ship makes an
  accelerating run for the edge of the screen. Riders are safe — but her
  fate stays live: if she was destined to blow before clearing the screen,
  everyone sees it. Survive the run and she's gone into the night, crash
  point never revealed.
- **The pilot rides too**: the host can ante into their own flight.
- **Goblin sounds**: comical goblin voice lines on every bail-out, and the
  bail spawns a real (textured!) goblin swinging under a real parachute
  that drifts behind the still-moving ship.
- **Flights are more erratic**: crashes cluster low-and-mid, ~7% of flights
  clear 600m, and the 1000m cap is a once-in-a-thousand spectacle.
- Smooth, uniform scrolling (no more per-tick lurch); mountains no longer
  vanish mid-flight; the odometer and status text always draw above the
  scenery.

### Texas Hold'em — Tournament Mode
- **One big table, locked to a buy-in.** Everyone starts with the same chip
  stack, blinds are chips, and nobody can join after the first deal. Bust
  or walk away and you're out.
- **Top three cash**: the prize pool (every buy-in) pays 50% / 30% / 20% by
  finish order — heads-up is winner-take-all — settled through the debt
  ledger in one zero-sum entry when the tournament ends.
- **Table stakes**: betting each hand is capped at the shortest stack, so
  every bet is always callable (no side pots, no arguments).
- Live chip stacks (number + a real pile of chip art) above every player,
  shrinking as chips go into the pot — blinds included. The dealer/SB/BB
  markers are translucent and sit on top of the piles.
- Mid-tournament rejoins restore chips; the HOST button stays hidden
  between tournament hands.

### Visual chip pots
- Poker, Hold'em and Blackjack render the money on the table as stacks of
  denomination chips (1g–1000g), sitting beside the pot box / dealer.

### Chair's Cup
- **Goblin Speedway theme**: one click swaps the horses for goblin rocket
  cars on asphalt, with real rocket-engine race audio. Per-player cosmetic —
  bet the same race in either theme (`/cup theme`).

### Slots
- Medium wins (2–25x) now land about every 13 spins instead of every 25,
  funded by trimming the top shelf — total RTP still just under break-even.
- GEM RUSH shows a lifetime counter in its banner and can no longer be
  eaten by a UI hiccup.

### Lobby & quality of life
- **Auto-open**: opt in per game (Settings → Auto-Open) and that game's
  window opens the moment someone hosts it, closing your other casino
  windows. Only fresh tables trigger it.
- **Minimap click**: while a game is being hosted, left-click jumps straight
  to it (Settings can restore always-lobby).
- **Settings panel is tabbed**: Visuals & Sound / Trixie / Auto-Open.
- The Crash lobby button flies two little animated zeppelins.
- **Events calendar removed**; the Find Game button is now **LFG**, and LFG
  listings disappear the moment the lister logs out, for any reason.
- TBC interface updated for 2.5.6.

### Under the hood
- Files reorganized into `Core/`, `Games/<Game>/`, and per-purpose media
  folders; ~4MB of dead assets removed.
- New tournament test suite (25 checks) alongside the crash, debt-ledger
  and LFG suites.
