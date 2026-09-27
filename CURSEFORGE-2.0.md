# Chairface's Casino 2.0

Welcome to the finest tables in Azeroth. Chairface's Casino turns your party or raid into a full gambling hall: seven multiplayer games, an animated Blood-Elf dealer, leaderboards, and provably fair results, all settled the honorable way with player-to-player trades. The addon never touches your gold. It tells everyone exactly who owes who, and you settle up like adults.

Version 2.0 is a ground-up expansion of the casino floor. Four new games, reconnect recovery, and a lot of polish.

## The Games

**Blackjack** - Hit, stand, double, split. Blackjack pays 3:2, host picks H17 or S17, and 5-Card Charlie is an automatic win. Animated dealing with every player's hand visible live.

**Texas Hold'em** (NEW) - The classic. Blinds, a rotating dealer button, community cards, and best five of seven at showdown.

**5 Card Stud** - Old-school stud with exposed cards, four betting rounds, and a bring-in decided by the highest visible hand.

**High-Lo** - Everyone rolls, highest pays lowest the difference. Quick-start it with /hilo, ties go to a roll-off.

**Death Roll** (NEW) - The oldest wager in Azeroth. Host sets the stake and the opening roll (your group's tradition, or the 10x default), then you roll each other down until someone hits 1. Built on real server-verified /roll results, so nobody has to trust anybody.

**Bingo** (NEW) - The host calls the balls, cards daub themselves, first line takes the pot. You can watch every player's card sweat in real time, sorted by who is closest to winning.

**Chair's Cup** (NEW) - A Sigma Derby style horse race betting parlor. Five horses, live odds, quinella lines plus single-horse win bets, a 45 second animated race, and a printed ledger when the dust settles. Every client builds the identical race from a shared seed.

## Why You Can Trust It

- Decks are shuffled from a seed shared with every client, so every player's addon deals the identical cards. The host cannot stack the deck.
- Death Roll and High-Lo use real /roll results verified by the server and visible to the whole group in chat.
- Bingo cards and the call order are deterministic from a shared seed. Your card is your card on every screen.
- Chair's Cup odds, results, and payouts are computed identically on every client from one seed. Nobody has to trust the host's dice.

## Quality of Life

- Trixie, your animated Blood-Elf dealer, now deals at every table, including Death Roll, Bingo, and the races. Poke her at your own risk.
- Disconnect protection: a 2 minute turn timer and host-recovery flow, plus full state resync when you reload or reconnect mid-game. Even a finished horse race will show you the results you missed.
- One game at a time per group, with the lobby clearly showing which table is live.
- A How to Play button on every game window, with full rules for all seven games.
- Session and all-time leaderboards across every game.
- Clickable game links in chat, minimap button, ESC to close, five card back styles, and host-configurable stakes, timers, and rules for every game.

## Slash Commands

- /cc or /casino - open the lobby
- /cc help - list commands
- /hilo <max> [timer] - quick-start a High-Lo round
- /cup - open Chair's Cup directly

## Removed in 2.0

Caribbean Stud Poker and Craps have been retired. They were the two tables that saw the least play, and the effort went into the four new games instead. If you miss them, say so in the comments and they may ride again in a future version.

## Changes in 2.0

- New games: Texas Hold'em, Death Roll, Bingo, and the Chair's Cup racing parlor
- Removed: Caribbean Stud Poker, Craps
- Seeded, client-verified shuffling and race generation across all games
- Full reconnect and reload recovery with versioned state sync
- Turn timer extended to 2 minutes so a disconnected player can get back in
- Leaderboard support for all new games
- Redesigned lobby with one-game-at-a-time gating
- How to Play rules pages for every game, reachable from every game window
- Countless UI, settlement, and sound fixes

As always: this is entertainment for fake internet money. Wager what you would trade away with a smile, and settle your debts. Trixie remembers.
