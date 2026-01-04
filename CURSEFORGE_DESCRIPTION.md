# 🎰 Chairface's Casino

**The ultimate multiplayer casino addon for WoW Classic!**

Host blackjack tables, poker nights, and dice games with your guild, party, or raid. Featuring Trixie, your animated bunny dealer who brings Vegas to Azeroth with voice lines, reactions, and style!

---

## 📋 Table of Contents

1. [Requirements](#requirements)
2. [Installation](#installation)
3. [Games](#games)
4. [Meet Trixie](#meet-trixie)
5. [Features](#features)
6. [Commands](#commands)
7. [How to Play](#how-to-play)
8. [Settings](#settings)
9. [FAQ](#faq)
10. [Changelog](#changelog)

---

## ⚙️ Requirements

| Dependency | Required | Link |
|------------|----------|------|
| **Ace3** | ✅ Yes | [Download](https://www.curseforge.com/wow/addons/ace3) |

**Important:** Install Ace3 before installing Chairface's Casino!

**Compatible with:** WoW Classic (Season of Discovery, Classic Era, Hardcore)

---

## 📥 Installation

1. Download and install [Ace3](https://www.curseforge.com/wow/addons/ace3)
2. Download Chairface's Casino
3. Extract to your `Interface/AddOns` folder
4. Restart WoW or `/reload`
5. Type `/cc` to open the casino!

---

## 🎰 Games

### ♠️ Blackjack

*Classic Vegas-style blackjack for up to 20 players!*

| Feature | Details |
|---------|---------|
| **Players** | 1-20 per table |
| **Actions** | Hit, Stand, Double Down, Split |
| **Payouts** | Blackjack 3:2, Regular wins 1:1 |
| **Special Rules** | 5-Card Charlie (auto-win), Split Aces (one card each) |
| **Deck Options** | 1, 2, 4, 6, or 8 deck shoe |
| **Dealer Rules** | Configurable - hits or stands on soft 17 |

**Rules:**
- Beat the dealer without going over 21
- Face cards = 10, Aces = 1 or 11
- Double down on first two cards only
- Split pairs up to 4 hands
- Blackjack (Ace + 10-value) pays 3:2
- 5-Card Charlie - 5 cards without busting is an automatic win

**Host Options:**
- Ante amount (1-1000g)
- Number of decks (1-8)
- Dealer hits/stands on soft 17
- Bet multiplier (1x-10x)

---

### 🃏 5 Card Stud Poker

*Classic poker with four betting rounds!*

| Feature | Details |
|---------|---------|
| **Players** | 2-8 per table |
| **Betting Rounds** | 4 (after 2nd, 3rd, 4th, and 5th card) |
| **Actions** | Check, Call, Raise, Fold |
| **Hand Rankings** | Standard poker (Royal Flush to High Card) |

**Hand Rankings (Highest to Lowest):**
1. 🏆 Royal Flush (A-K-Q-J-10 suited)
2. Straight Flush (5 sequential suited cards)
3. Four of a Kind
4. Full House (3 of a kind + pair)
5. Flush (5 suited cards)
6. Straight (5 sequential cards)
7. Three of a Kind
8. Two Pair
9. One Pair
10. High Card

**Features:**
- Automatic pot splitting for ties
- Kicker display for tiebreakers
- Combined Check/Call button for streamlined play
- Raise input auto-fills with max amount
- Seed-based deck for perfect synchronization
- Visual card count display

**Host Options:**
- Ante amount
- Max raise per round

---

### 🎲 High-Lo Dice

*Fast-paced dice rolling for any group size!*

| Feature | Details |
|---------|---------|
| **Players** | 2-40+ |
| **How to Win** | Roll highest number |
| **Ties** | Automatic /roll 100 tiebreaker |
| **Speed** | Games complete in under 2 minutes |

**How It Works:**
1. Host sets max roll (e.g., 100, 1000)
2. Players join during countdown (20-120 seconds)
3. Everyone types `/roll <max>` or clicks the Roll button
4. Highest roll wins, lowest roll loses
5. Winner = High Roll - Low Roll in gold
6. Ties trigger automatic /roll 100 tiebreakers

**Quick Start:** Use `/hilo 1000 60` to instantly host a game with max roll 1000 and 60 second join window!

**Settlement Display:**
- Clear winner/loser announcement
- Math breakdown (High - Low = Payout)
- Highlighted payout line for easy reading

---

## 🐰 Meet Trixie

*Your animated dealer brings the casino to life!*

Trixie is more than just eye candy - she's your guide to the casino experience with:

| Feature | Description |
|---------|-------------|
| **Animated Poses** | Dealing, shuffling, waiting, celebrating, disappointed |
| **Voice Lines** | Reacts to blackjacks, busts, big wins, and more |
| **Personality** | Encouraging when you win, sympathetic when you lose |
| **Customizable** | Adjust voice frequency or hide her entirely |
| **Welcome Intro** | Full introduction sequence with voice on first launch |

**Voice Frequency Options:**
- Always (every event)
- Frequent
- Normal (default)
- Occasional
- Rare

**Trixie's Reactions:**
- 🎉 Cheers for blackjacks and big wins
- 😢 Sympathizes when you bust or lose
- 💕 Special "love" pose for huge wins
- 🎲 Dice sound effects for High-Lo rolls

---

## ✨ Features

### 🎮 Gameplay
- **True Multiplayer** - Real-time sync across your party/raid
- **Settlement Ledger** - Clear breakdown of who owes who
- **Game History** - Track your last 5 hands
- **Auto-Recovery** - Rejoin games after disconnect/reload
- **Seed-Based Decks** - Perfect card synchronization across all clients
- **Visual Card Count** - See remaining cards in shoe

### 🔄 Synchronization
- **State Sync** - Automatic recovery if you disconnect
- **Host Recovery** - Blackjack/Poker: 2-minute grace period for host to return
- **Host Transfer** - High-Lo: Seamless host transfer if host disconnects
- **Version Checking** - Warns if players have mismatched versions
- **Reconnect Support** - Full game state restored on login/reload

### 🎨 Customization
- **4 Card Back Designs** - Blue, Red, MTG, Hearthstone
- **Window Scaling** - Resize UI from 60% to 120%
- **Minimap Icon** - Adjustable size (1.5x-5x) or hide completely
- **Sound Controls** - Toggle SFX and voice separately
- **Show/Hide Lobby Trixie** - Toggle Trixie visibility in lobby

### 💬 Social
- **Clickable Chat Links** - Click [Blackjack], [5 Card Stud], or [High-Lo] in chat to open the game
- **Join Announcements** - Countdown timers broadcast to party chat
- **Settlement Reports** - Clear payout instructions after each game
- **Game Start Sound** - Audio notification when someone opens a table

### 🔊 Audio
- **Card Sounds** - Shuffle, deal, flip
- **Chip Sounds** - Ante, betting
- **Dice Sounds** - Roll sound effect for High-Lo
- **Fanfare** - Win celebration
- **Trixie Voice Lines** - Multiple voice clips for various events

---

## 📝 Commands

### Main Commands

| Command | Description |
|---------|-------------|
| `/cc` | Open the casino lobby |
| `/casino` | Same as /cc |
| `/cc help` | Show all commands in chat |
| `/cc default` | Reset all settings to defaults |
| `/cc intro` | Replay Trixie's introduction |

### Quick Start

| Command | Description |
|---------|-------------|
| `/hilo <max> [timer]` | Quick start High-Lo game |

**Examples:**
- `/hilo 100` - Max roll 100, 60 sec join window
- `/hilo 1000 30` - Max roll 1000, 30 sec join window
- `/hilo 500 120` - Max roll 500, 2 minute join window

*Timer range: 20-120 seconds (default: 60)*

---

## 🎮 How to Play

### Getting Started

1. **Open the Casino**
   - Click the minimap button (chip icon)
   - Or type `/cc`

2. **Choose Your Game**
   - Click Blackjack, 5 Card Stud, or High-Lo

3. **Host or Join**
   - **To Host:** Click the HOST button, configure settings, start the game
   - **To Join:** Click JOIN or ANTE when someone else hosts

4. **Play!**
   - Use the action buttons when it's your turn
   - Watch Trixie for reactions and tips

5. **Settle Up**
   - Check the settlement ledger after each game
   - Trade gold to settle debts

### Hosting Tips

- **Blackjack:** Set ante amount, deck count, and dealer rules
- **Poker:** Configure ante and max raise per round
- **High-Lo:** Set max roll value and join timer

### Player Tips

- Join games quickly - countdown timers are real!
- Watch for clickable [game links] in chat
- Use `/cc help` if you forget commands
- If you disconnect, just log back in - the addon will sync you

---

## ⚙️ Settings

Access settings by clicking the ⚙️ gear icon in the lobby.

### Audio

| Setting | Options |
|---------|---------|
| **SFX** | On/Off - Card sounds, chips, shuffling, dice |
| **Voice** | On/Off - Trixie's voice lines |
| **Voice Frequency** | Always / Frequent / Normal / Occasional / Rare |

### Appearance

| Setting | Options |
|---------|---------|
| **Card Back** | Blue, Red, MTG, Hearthstone |
| **Card Face** | Default (more coming soon) |
| **Dice** | Default (more coming soon) |
| **Show Lobby Trixie** | Toggle Trixie in lobby |

### UI Scale

| Setting | Range |
|---------|-------|
| **Minimap Icon** | 1.5x - 5.0x |
| **Hide Minimap** | Checkbox to hide icon |
| **Window Scale** | 60% - 120% |

### Other

| Setting | Description |
|---------|-------------|
| **Replay Intro** | Watch Trixie's welcome sequence again |

---

## ❓ FAQ

**Q: Do I need to be in a group to play?**
A: Yes! You need to be in a party or raid to host or join games.

**Q: Does gold transfer automatically?**
A: No. This addon tracks bets and shows who owes who, but players must trade gold manually. Play with friends you trust!

**Q: Can I play solo?**
A: The games require at least 2 players. However, developers can enable test mode for solo testing.

**Q: What happens if I disconnect?**
A: The addon will automatically sync you back into the game when you reconnect. Your cards and bets are preserved!

**Q: What if the host disconnects?**
A: For Blackjack and Poker, there's a 2-minute grace period for the host to return. For High-Lo, a new host is automatically assigned.

**Q: Can I resize the windows?**
A: Yes! Use the Window Scale slider in Settings (60% - 120%).

**Q: How do I hide the minimap button?**
A: Go to Settings and check "Hide minimap icon".

**Q: The HOST button disappeared, what do I do?**
A: This usually means a game is in progress. Wait for it to end or ask the host to reset.

**Q: Can different addon versions play together?**
A: The addon will warn you if versions don't match. For best results, everyone should use the same version.

**Q: How do card counts work?**
A: The host's deck state is synchronized to all players. Everyone sees the same remaining card count.

---

## 📜 Changelog

### Version 1.3.0 (Current)

**New Features:**
- 🎲 Dice sound effect for High-Lo rolls
- 🔔 Game start notification sound when tables open
- 🎬 Trixie intro plays again for returning players

**Improvements:**
- High-Lo settlement display with opaque background
- Enhanced payout line visibility with highlight markers
- Simplified High-Lo host transfer (instant, no waiting period)
- Better phase filtering for host disconnect detection
- Improved card count synchronization in Poker

**Bug Fixes:**
- Fixed seed display persistence after login/reload
- Fixed Poker card count not syncing to clients
- Fixed returning host deck position in Poker
- Fixed High-Lo settlement text readability

---

### Version 1.2.x

**Features Added:**
- Redesigned Settings panel with two-column layout
- Card face and dice preview sections
- UI Scale options: Window scale (60-120%), Minimap icon (1.5x-5x)
- Hide minimap icon checkbox
- Combined Check/Call button in poker
- Raise input auto-fills with max remaining amount
- `/hilo <max> [timer]` - Customizable join timer (20-120 seconds)
- Host disconnect recovery with 2-minute grace period
- Seed-based deck synchronization
- Visual remaining card count display

**Improvements:**
- Better state synchronization for spectators
- Minimap icon hover scaling matches set scale
- High-Lo game cancels properly when join timer expires with <2 players
- Improved help system with commands and tips

---

### Version 1.1.x

- Added 5 Card Stud Poker
- Added High-Lo Dice
- Trixie voice system with frequency controls
- Clickable game links in chat
- State sync and recovery system
- Multiple card back designs
- Sound effects system

---

### Version 1.0.x

- Initial release with Blackjack
- Multiplayer synchronization
- Settlement ledger
- Trixie dealer animations

---

## ⚠️ Important Disclaimer

**This addon facilitates gambling games between players for entertainment purposes.**

- Gold is **NOT** automatically traded
- Players must honor bets and trade manually
- Play responsibly and only with friends you trust
- Set betting limits you're comfortable with
- This is meant for fun - keep it friendly!

---

## 💬 Support & Feedback

**Found a bug?** Please report it in the comments with:
- What happened
- What you expected to happen
- Any error messages
- Your addon version (type `/cc` to see it)

**Have a suggestion?** I'd love to hear it! Leave a comment with your idea.

**Enjoying the addon?** Consider leaving a thumbs up! ⭐

---

## 🙏 Credits

- **Development:** Chairface
- **Trixie Art:** Custom designed for this addon
- **Sound Effects:** Various royalty-free sources
- **Libraries:** Ace3 (Ace Community)

---

*Good luck at the tables! May the odds be ever in your favor!* 🎲🃏♠️
