--[[
    Chairface's Casino - UI/HowToPlay.lua
    How to Play: every game's rules (Lobby.helpContent), the help window,
    and the header button each game window carries to open its page.
    Part of the lobby module (UI.Lobby), split out of UI/Lobby.lua.
]]

local BJ = ChairfacesCasino
local UI = BJ.UI
local Lobby = UI.Lobby

local HELP_HEIGHT = 730   -- tall enough for the full game-button column
local HELP_WIDTH = 720    -- content area fills the width beside the buttons

--[[
    HELP PANEL
    Shows Trixie explaining game rules with scrollable content
]]

-- Help text content
Lobby.helpContent = {
    blackjack = {
        title = "Blackjack",
        text = [[|cffffd700Welcome to Blackjack!|r

|cff88ffffObjective:|r
Beat the dealer by getting a hand value closer to 21 without going over.

|cff88ffffCard Values:|r
- Number cards (2-10): Face value
- Face cards (J, Q, K): 10 points
- Aces: 1 or 11 points (whichever is better)

|cff88ffffHow to Play:|r
1. The host opens a table and sets the ante
2. Players join by clicking ANTE
3. Everyone gets 2 cards; dealer shows one card face-up
4. On your turn, choose:
   - |cff00ff00HIT|r: Take another card
   - |cff00ff00STAND|r: Keep your current hand
   - |cff00ff00DOUBLE|r: Double your bet, take one card, then stand
   - |cff00ff00SPLIT|r: If you have a pair, split into two hands

|cff88ffffWinning:|r
- Get closer to 21 than the dealer without busting
- |cffffd700Blackjack|r (Ace + 10-value card) pays 3:2
- Regular wins pay 1:1
- Tie (Push) returns your bet

|cff88ffffDealer Rules (H17 vs S17):|r
The host chooses one of two dealer rules:
- |cff00ff00H17|r: Dealer HITS on Soft 17 (Ace counted as 11)
- |cff00ff00S17|r: Dealer STANDS on Soft 17
Both rules: Dealer always stands on hard 17+ and hits on 16 or less.
S17 is slightly better for players.

|cff88ffffSpecial Rules:|r
- |cffffd7005-Card Charlie|r: 5 cards without busting is an automatic win!
- Split Aces only get one card each and pay 1:1

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    },
    poker = {
        title = "5 Card Stud",
        text = [[|cffffd700Welcome to 5 Card Stud Poker!|r

|cff88ffffObjective:|r
Make the best 5-card poker hand and win the pot through betting or showdown.

|cff88ffffHand Rankings (Best to Worst):|r
1. |cffffd700Royal Flush|r - A, K, Q, J, 10 of same suit
2. |cffffd700Straight Flush|r - 5 consecutive cards, same suit
3. |cffffd700Four of a Kind|r - 4 cards of same rank
4. |cffffd700Full House|r - 3 of a kind + a pair
5. |cffffd700Flush|r - 5 cards of same suit
6. |cffffd700Straight|r - 5 consecutive cards
7. |cffffd700Three of a Kind|r - 3 cards of same rank
8. |cffffd700Two Pair|r - 2 different pairs
9. |cffffd700One Pair|r - 2 cards of same rank
10. |cffffd700High Card|r - Highest card wins

|cff88ffffHow to Play:|r
1. Host opens table, sets ante and max raise
2. Players join by clicking JOIN
3. Everyone antes and gets one card face-down
4. Four betting rounds, each with a new face-up card
5. After all cards are dealt, showdown determines winner

|cff88ffffBetting Options:|r
- |cff00ff00CHECK|r: Pass (if no bet to call)
- |cff00ff00CALL|r: Match the current bet
- |cff00ff00RAISE|r: Increase the bet
- |cffff4444FOLD|r: Give up your hand and bets

|cff88ffffTips:|r
- Watch opponents' face-up cards for clues
- Fold weak hands early to save gold
- Bluffing can work, but be careful!

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    },
    hilo = {
        title = "High-Lo",
        text = [[|cffffd700Welcome to High-Lo!|r

|cff88ffffObjective:|r
Roll the highest number to win gold from the player with the lowest roll!

|cff88ffffHow to Play:|r
1. One player hosts and sets the max roll value
2. Other players click JOIN to enter the game
3. When ready, host clicks START
4. Everyone types /roll X (or click the Roll button)
5. Highest roller wins the difference from lowest roller

|cff88ffffExample:|r
- Max roll is set to 100
- Alice rolls 82, Bob rolls 45, Carol rolls 67
- Alice |cff00ff00wins|r and Bob |cffff4444loses|r
- |cffffd70082 - 45 = 37g|r
- Bob pays Alice 37 gold!

|cff88ffffSettings:|r
- |cffffd700Max Roll|r: The maximum number for /roll (default 100)
- |cffffd700Join Timer|r: Optional countdown for join phase (0 = manual start)

|cff88ffffRules:|r
- All players have 2 minutes to roll
- Players who don't roll in time are skipped
- If only one person rolls, no settlement occurs
- Ties for high or low trigger a /roll 100 tiebreaker

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    },
    holdem = {
        title = "Texas Hold'em",
        text = [[|cffffd700Welcome to Texas Hold'em!|r

|cff88ffffObjective:|r
Make the best 5-card hand from your 2 hole cards and the 5 community cards.

|cff88ffffHow to Play:|r
1. Host opens the table and sets the blinds
2. Players join; the dealer button rotates each hand
3. Everyone gets 2 face-down hole cards
4. Betting rounds: pre-flop, flop (3 cards), turn, river
5. Showdown - best 5 of your 7 cards wins the pot

|cff88ffffBetting Options:|r
- |cff00ff00CHECK|r: Pass (if no bet to call)
- |cff00ff00CALL|r: Match the current bet
- |cff00ff00RAISE|r: Increase the bet
- |cffff4444FOLD|r: Give up your hand and bets

|cff88ffffHand Rankings (Best to Worst):|r
1. |cffffd700Royal Flush|r - A, K, Q, J, 10 of same suit
2. |cffffd700Straight Flush|r - 5 consecutive cards, same suit
3. |cffffd700Four of a Kind|r - 4 cards of same rank
4. |cffffd700Full House|r - 3 of a kind + a pair
5. |cffffd700Flush|r - 5 cards of same suit
6. |cffffd700Straight|r - 5 consecutive cards
7. |cffffd700Three of a Kind|r - 3 cards of same rank
8. |cffffd700Two Pair|r - 2 different pairs
9. |cffffd700One Pair|r - 2 cards of same rank
10. |cffffd700High Card|r - Highest card wins

|cff88ffffTips:|r
- Position matters: acting last is an advantage
- Suited connectors and pairs play well multiway
- Don't chase draws when the price is wrong!

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    },
    deathroll = {
        title = "Death Roll",
        text = [[|cffffd700Welcome to Death Roll!|r

|cff88ffffObjective:|r
Don't roll the 1. Whoever rolls it pays the other player the stake.

|cff88ffffHow to Play:|r
1. The host sets the stake and the first roll ceiling
   (defaults to 10x the stake - groups have their own traditions)
2. One opponent clicks ACCEPT to take the seat
3. The host rolls first: /roll <ceiling> (or click ROLL)
4. Each roll sets the next player's maximum
5. Rolling a |cffff44441|r loses - pay the winner the stake!

|cff88ffffExample:|r
- Stake 100g, first roll 1-1000
- Host rolls 412, opponent rolls 1-412 and gets 87
- Host rolls 1-87... down and down until someone hits 1

|cff88ffffFair Play:|r
Rolls are real server-verified /rolls that everyone in the
group can see in chat - no addon trust required.

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    },
    bingo = {
        title = "Bingo",
        text = [[|cffffd700Welcome to Bingo!|r

|cff88ffffObjective:|r
Be the first to complete a line - across, down, or diagonal.

|cff88ffffHow to Play:|r
1. The host opens the game and sets the card price
2. Players buy a card (everyone can see everyone's card)
3. The host starts the draw - numbers are called automatically
4. Your card daubs itself as numbers come up
5. First completed line wins the whole pot!

|cff88ffffThe Card:|r
- 5x5 grid: B (1-15), I (16-30), N (31-45), G (46-60), O (61-75)
- The center square is FREE
- Ties split the pot evenly

|cff88ffffFair Play:|r
Cards and the draw order come from a shared seed, so every
player's addon shows identical cards and calls.

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    },
    roulette = {
        title = "Roulette",
        text = [[|cffffd700Welcome to Roulette!|r

|cff88ffffObjective:|r
Bet on where the ball lands. The host is the bank; winners collect
from the host, losers pay the host.

|cff88ffffHow to Play:|r
1. The host opens the table, setting the chip value and how
   many chips each player may place
2. Players JOIN, then left-click board spots to stack chips
   (right-click takes a chip back)
3. The host calls the spin - no more bets!
4. The wheel and ball run the same animation on every screen,
   and the ball lands on the same number for everyone
5. Winners are paid by the odds; the host can spin again or close

|cff88ffffBets and Payouts:|r
- Straight number (including 0): |cffffd70035:1|r
- Red/Black, Dozens and columns: |cffffd7002:1|r
- Odd/Even, 1-18/19-36: |cffffd7001:1|r
- Zero wins only straight bets on 0 - every outside bet loses

|cff88ffffFair Play:|r
This is a European wheel (single zero). The winning number is
computed from a seed the host broadcasts, with the same math on
every client - the host cannot pick the result.

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    },
    liarsdice = {
        title = "Liar's Dice",
        text = [[|cffffd700Welcome to Liar's Dice!|r

|cff88ffffObjective:|r
Be the last player holding dice. Everyone rolls in secret and bluffs
about how many of each face are hidden across ALL the cups on the table.

|cff88ffffHow to Play:|r
1. The host opens a table (buy-in) and players JOIN. Everyone starts
   with 3 dice (the host can bump the table up to 5).
2. Each round every player is dealt a hidden hand - you can see only
   your own dice.
3. On your turn you must either RAISE the bid or CALL LIAR:
   - A bid is a claim about the whole table, e.g. "three 5s" means at
     least three 5s exist among everyone's dice.
   - A raise must beat the standing bid: a higher count of any face, or
     the same count of a higher face.
4. Instead of raising you can CALL LIAR on the previous bid. All cups
   lift and the bid face is counted:
   - If there are at least as many as bid, the bid holds and the
     |cffff4444caller|r loses a die.
   - If there are fewer, the |cffff4444bidder|r loses a die.
5. Lose all your dice and you're out. Last player standing wins the pot.

|cff88ffffOnes Are Wild:|r
When the host enables it (default), every |cffffd7001|r counts as the
face in the current bid - so totals run higher than you'd expect. You
cannot bid ones while they're wild.

|cff88ffffFair Play:|r
The host deals from a seed that is revealed the moment a challenge is
called, so every player can verify the hand they were dealt was honest
and nobody could peek at your cup.

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    },
    crash = {
        title = "Crash",
        text = [[|cffffd700Welcome to Crash!|r

|cff88ffffObjective:|r
A GAME OF CHICKEN. Everyone antes into a pot and boards a goblin
zeppelin that is 100% guaranteed to explode - the only question is
when. Parachute out before the blast, but AFTER everyone else: the
last rider to jump takes the whole pot.

|cff88ffffHow to Play:|r
1. The host opens the table and sets the ante; the host is the
   pilot - they know the fate, so they do not ride.
2. Board by anteing into the pot. You can set an |cff00ff00auto-jump
   distance|r (e.g. 450m) - it fires with zero lag the instant the
   odometer reaches it, exactly like clicking that tick yourself.
3. The host LAUNCHES: boarding locks and the zeppelin leaves the tower.
4. The odometer climbs - 100m in the first 5 seconds, then the sky
   is the limit. Smash |cffff4444JUMP!|r any time. Jumping realizes
   nothing by itself: it just stakes your claim as the latest one out.
5. When she blows, everyone still aboard loses their ante to the pot.
   Among the jumpers, the LAST tick out wins it all (a tie on the
   same tick splits it). If nobody jumped, the antes push back.
6. After the crash, ANYONE can claim the next flight - whoever
   clicks becomes the new pilot and presses LAUNCH. The sitting
   pilot keeps the chair by clicking it themselves.

|cff88ffffThe Nerve:|r
Past the climb-out the explosion odds are the same every tick - the
flight so far tells you NOTHING about the flight left. The average
flight runs long (most blow past 400m; about one in eight runs the
full 1000m and explodes at the cap), so the pot is pure nerve:
outwait the table, don't outwait the zeppelin. Disconnecting won't
save your ante - a vanished rider goes down with the ship.

|cff88ffffProvably Fair:|r
At launch the host broadcasts a fingerprint (hash) of a secret that
decides the crash point. Nobody can predict it mid-flight (the
secret stays hidden), and the host cannot change it once the flight
is up (the fingerprint is already on record). After the crash the
secret is revealed and your client verifies it automatically -
a tampered reveal is called out in red.

|cff88ffffDisconnects:|r
A rider who disconnects mid-flight gets their ante voided. If the
pilot (host) vanishes mid-flight, the whole round is voided - no
gold changes hands.

|cffff8888Remember:|r This is for fun! Trade gold honorably with other players to settle bets.]]
    },
    slots = {
        title = "Slots (Solo)",
        text = [[|cffffd700Welcome to Azeroth Riches - 5-Reel Slots!|r

|cff88ffffThe Arcade:|r
A solo machine played on |cffcc88fffake credits|r, like the old
handheld Vegas games. No gold, no group, no trades - your credit
balance is saved on this character and follows you around.

|cff88ffffHow to Play:|r
1. Pick how many |cffffd700lines|r are active (1-9) and your
   |cffffd700bet per line|r (1-5). Total bet = lines x bet.
2. Five reels spin, five symbols tall (a 5x5 grid).
3. Wins pay on active lines for 3+ matching symbols from the
   leftmost reel.

|cff88ffffThe nine lines|r (activation order): Middle, Row 2, Row 4,
Top, Bottom, Slash /, Backslash \, Top V, Bottom ^.
The markers around the reels show the bet riding each line
(0 = line off). Click any marker to play up to that line.

|cff88ffffPays (per line, per credit - 3 / 4 / 5):|r
WILD |cffffd70060/300/1500|r - Skull |cffffd70050/200/1000|r - Gold |cffffd70020/60/250|r
Ruby |cffffd70010/30/100|r - Emerald |cffffd7006/18/60|r - Sapphire |cffffd7004/12/40|r
Die |cffffd7005/15/50|r - Shroom/Melon/Apple and Silver/Copper fill the low end

|cff88ffffCOINS - the WoW Token:|r
Every Token that lands is a |cffffd700coin|r with a credit value on it
(scaled by your total bet). Exactly |cffffd7003 coins|r in view triggers
a random side bonus: Loot Chest, Bonus Wheel, or Free Spins.

|cffff9933HOLD & SPIN:|r Land |cffffd7004+ coins|r and they LOCK in place
with 3 respins - every new coin resets the respins to 3, and all
|cffffd70025|r positions are in play. When they run out you collect every
locked coin. Special coins pay the |cff55ff55MINI|r / |cff55aaffMINOR|r / |cffcc66ffMAJOR|r
jackpots, and locking |cffffd70020+|r of the 25 positions wins the
progressive |cffff3333GRAND JACKPOT|r. Every jackpot is a live pot -
they grow with every wager (yours and the rest of the realm's)
until somebody hits them. You need a total bet of |cffffd7005+|r to be
riding for the pots (smaller bets win the old fixed multiples),
and the million-seeded |cffff4455MEGA|r pot needs a total bet of |cffffd700100+|r.

|cffff77ffGEM RUSH:|r 1 in 20 pulls strips everything below the gems
off the reels - only high symbols, pure line pay.

|cff88ffffBroke?|r
When you hit zero the pit boss will comp you back in. She keeps
count of your refills, though. Forever.]]
    },
    videopoker = {
        title = "Video Poker & Blackjack (Solo)",
        text = [[|cffffd700Welcome to the video card cabinet!|r

|cff88ffffThe Arcade:|r
A solo machine played on |cffcc88fffake credits|r, like the old
handheld Vegas games. No gold, no group, no trades - your credit
balance is saved on this character and follows you around.

|cff88ffffThree games, one cabinet:|r Use the tabs up top to switch
between |cffffd700Video Poker|r, |cffffd700Video Blackjack|r and |cffffd700Video Keno|r.

|cff88ffffVideo Keno:|r Pick 1-10 numbers on the 80-number board,
set your bet and DRAW - 20 numbers are called and matches pay
by how many you picked. The pay ladder updates live.

|cff88ffffVideo Poker:|r
1. Set your bet (1-5) and DEAL. Click cards to HOLD.
2. DRAW replaces the rest and the table pays you.
3. Click the game name to switch variation:
   |cffffd700Jacks or Better|r, |cffffd700Bonus Poker|r,
   |cffffd700Double Double Bonus|r, or |cffffd700Deuces Wild|r.
Bet 5 for the |cffffd700800x|r royal jackpot.

|cff88ffffVideo Blackjack:|r
1. Set your bet and DEAL - you get two cards, dealer shows one.
2. HIT for another card, STAND to hold, DOUBLE (one card, double
   the wager), or SPLIT a pair into two hands - resplit up to
   four hands if another pair shows up.
3. Dealer draws to 17. Blackjack pays |cffffd7003:2|r; a win pays even.

|cff88ffffShow Off / Send:|r Brag your credit total to chat with
|cffffd700Show Off|r, or gift credits to a friend (one-way) with
|cffffd700Send Credits|r.

|cff88ffffBroke?|r
When you hit zero the pit boss will comp you back in. She keeps
count of your refills, though. Forever.]]
    },
    derby = {
        title = "Chair's Cup (Derby)",
        text = [[|cffffd700Welcome to Chair's Cup!|r

|cff88ffffObjective:|r
Bet on which TWO horses finish first and second (a quinella) -
order doesn't matter.

|cff88ffffHow to Play:|r
1. Whoever presses NEW RACE becomes the bank for that race
2. The host sets the stake size and bets allowed per player
3. Left-click a combo line to bet, right-click to take one back
4. The host presses RUN RACE: 10s last call, 3s countdown, go!
5. After the race, everyone sees one net figure to collect or pay

|cff88ffffBetting:|r
- Left-click a pairing to place one bet of the bank's stake on it;
  right-click to take one back.
- Stack several bets on one pairing or spread them around, up to
  your bet allotment. Stake and bet count lock once betting begins.

|cff88ffffOdds and payout:|r
Each line shows its payout odds up front (capped at 33 to 1) -
longshots pay more. A pairing that finishes 1-2 in either order
pays stake times odds, and stays highlighted in gold until the
next race. After the race you see one net for the round: a
positive net you collect, a negative net you pay.

|cff88ffffFair Play:|r
The race is built from a shared seed, so every player in your
party or raid watches the identical race and sees identical
payouts. The addon never touches gold - settle up by trade
afterwards. Same seed, same race, on every screen.]]
    },
    debug = {
        title = "Debug / Test Commands",
        text = [[|cffff00ffDEBUG MODE|r - visible only to authorized characters.
Enable with |cff88ff88/cc db|r first; all commands below need it on.

|cff88ffffTable games (Blackjack / Poker bots):|r
|cff88ff88/cc test add [name]|r - add a fake player
|cff88ff88/cc test remove <name>|r - remove a fake player
|cff88ff88/cc test list|r / |cff88ff88clear|r - list / remove all bots
|cff88ff88/cc test auto|r - toggle bot auto-play
|cff88ff88/cc test deal|r - force the deal
|cff88ff88/cc test dealer|r - make the dealer act
|cff88ff88/cc test hit/stand/double/split [name]|r - force a bot action

|cff88ffffOther multiplayer games:|r
|cff88ff88/cc test drjoin [name]|r - bot accepts the open Death Roll
|cff88ff88/cc test bingo <n>|r - add N fake bingo card buyers
|cff88ff88/cc test bingospeed <sec>|r - adjust bingo call speed live
|cff88ff88/cc test roulette <n>|r - add N fake roulette bettors
|cff88ff88/cc test ld <n>|r - add N fake Liar's Dice players
|cff88ff88/cc test ldact|r - nudge the Liar's Dice bot on turn

|cff88ffffArcade (solo games):|r
|cff88ff88/cc test arcade reset|r - credits back to 1,000
|cff88ff88/cc test arcade credits <n>|r - set the balance outright
|cff88ff88/cc test arcade refills|r - zero refill counters (incl. lifetime)

|cff88ffffSlots rigging (next spin only, one-shot):|r
|cff88ff88/cc test slots bonus|r - exactly 3 coins (side bonus)
|cff88ff88/cc test slots fireshot|r - 5 coins (HOLD & SPIN)
|cff88ff88/cc test slots <sym> <count> [line]|r - force a line win
|cff88ff88/cc test bj pair|r - next video blackjack deal is a pair
Symbols: skull gold ruby emerald sapphire die shroom
melon apple silver copper wild (count 3-5, line 1-9)]]
    }
}

function Lobby:ShowHelp()
    -- Hide the lobby while help is showing
    if self.frame then
        self.frame:Hide()
    end
    
    if self.helpPanel then
        self.helpPanel:Show()
        self:UpdateHelpTrixieVisibility()
        return
    end
    
    self:CreateHelpPanel()
    self.helpPanel:Show()
    self:UpdateHelpTrixieVisibility()
end

function Lobby:HideHelp(dontShowLobby)
    if self.helpPanel then
        self.helpPanel:Hide()
    end
    -- Hide help Trixie
    if self.helpTrixie then
        self.helpTrixie:Hide()
    end
    -- Opened from a game window's How to Play button: closing help should
    -- reopen that game window, not pop the lobby over it
    if self.helpFromGame then
        self.helpFromGame = false
        local mod = self.helpReturnModule
        self.helpReturnModule = nil
        if mod and mod.Show then mod:Show() end
        return
    end
    -- Show the lobby again (unless told not to)
    if not dontShowLobby and self.frame then
        self.frame:Show()
    end
end

-- Update Help Trixie visibility based on setting
function Lobby:UpdateHelpTrixieVisibility()
    if not self.helpTrixie then return end
    
    local showTrixie = true
    if BJ.db and BJ.db.settings then
        showTrixie = BJ.db.settings.showLobbyTrixie ~= false
    end
    
    -- Only show Trixie if setting is enabled AND help panel is visible
    if showTrixie and self.helpPanel and self.helpPanel:IsShown() then
        self.helpTrixie:Show()
    else
        self.helpTrixie:Hide()
    end
end

function Lobby:CreateHelpPanel()
    -- Shared casino window (UI/Chrome.lua) on the tavern art. Its X is the
    -- old "Back": HideHelp returns to the lobby or the game it came from.
    local panel = UI.Chrome:CreateWindow({
        name = "ChairfacesCasinoHelp",
        title = "How to Play",
        width = HELP_WIDTH, height = HELP_HEIGHT,
        art = "tavern", scrim = 0.62,
        onClose = function() Lobby:HideHelp() end,
    })
    panel:SetFrameLevel(self.frame:GetFrameLevel() + 10)
    local T = BJ.Theme

    -- Game selection buttons (left side) - every game gets a listing
    local btnFrame = CreateFrame("Frame", nil, panel)
    btnFrame:SetSize(120, 400)
    btnFrame:SetPoint("TOPLEFT", 15, panel.BODY_TOP - 10)

    local helpGameList = {
        { key = "blackjack", label = "Blackjack" },
        { key = "poker",     label = "5 Card Stud" },
        { key = "holdem",    label = "Texas Hold'em" },
        { key = "hilo",      label = "High-Lo" },
        { key = "deathroll", label = "Death Roll" },
        { key = "bingo",     label = "Bingo" },
        { key = "roulette",  label = "Roulette" },
        { key = "liarsdice", label = "Liar's Dice" },
        { key = "crash",     label = "Crash" },
        { key = "derby",     label = "Chair's Cup" },
        { key = "slots",     label = "Slots (solo)" },
        { key = "videopoker", label = "Video Poker" },
    }

    -- Debug command reference: only characters on the debug allow-list see it
    if BJ.TestMode and BJ.TestMode.CanUseDebugMode and BJ.TestMode:CanUseDebugMode() then
        table.insert(helpGameList, { key = "debug", label = "Debug Cmds" })
    end

    local prevBtn
    for _, entry in ipairs(helpGameList) do
        local gameBtn = T:Button(btnFrame, entry.label, 110, 26, "secondary")
        if prevBtn then
            gameBtn:SetPoint("TOP", prevBtn, "BOTTOM", 0, -6)
        else
            gameBtn:SetPoint("TOP", 0, 0)
        end
        local key = entry.key
        gameBtn:SetScript("OnClick", function() Lobby:ShowHelpContent(key) end)
        prevBtn = gameBtn
    end

    -- Back button (hidden by default, shown when viewing game help)
    local backBtn = T:Button(btnFrame, "< Back", 110, 26, "primary")
    backBtn:SetPoint("TOP", prevBtn, "BOTTOM", 0, -12)
    backBtn:SetScript("OnClick", function() Lobby:ShowMainHelp() end)
    backBtn:Hide()
    panel.backBtn = backBtn
    
    -- Content area (middle with scroll)
    local contentFrame = T:Panel(panel, "inset", 560, HELP_HEIGHT - 60)  -- fills the widened panel
    contentFrame:SetPoint("TOPLEFT", btnFrame, "TOPRIGHT", 10, 5)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, contentFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)
    T:StyleScrollBar(scrollFrame)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(500, 1)
    scrollFrame:SetScrollChild(scrollChild)

    local contentText = scrollChild:CreateFontString(nil, "OVERLAY", "CCFontNormal")
    contentText:SetPoint("TOPLEFT", 0, 0)
    contentText:SetWidth(500)
    contentText:SetJustifyH("LEFT")
    contentText:SetJustifyV("TOP")
    contentText:SetSpacing(2)
    
    -- Default content with commands and tips
    local defaultHelp = "|cffffd700=== Slash Commands ===|r\n\n"
    defaultHelp = defaultHelp .. "|cff88ff88/cc|r or |cff88ff88/casino|r - Open lobby\n"
    defaultHelp = defaultHelp .. "|cff88ff88/cc help|r - Show commands in chat\n"
    defaultHelp = defaultHelp .. "|cff88ff88/cc default|r - Reset settings\n"
    defaultHelp = defaultHelp .. "|cff88ff88/cc intro|r - Replay Trixie intro\n"
    defaultHelp = defaultHelp .. "|cff88ff88/hilo <max> [timer]|r - Quick start High-Lo\n"
    defaultHelp = defaultHelp .. "   max = max roll, timer = 20-120 sec (default 60)\n"
    defaultHelp = defaultHelp .. "   Example: /hilo 1000 30\n"
    defaultHelp = defaultHelp .. "|cff88ff88/cup|r, |cff88ff88/derby|r or |cff88ff88/chairscup|r - Open the Chair's Cup derby\n\n"
    defaultHelp = defaultHelp .. "|cffffd700=== Tips ===|r\n\n"
    defaultHelp = defaultHelp .. "|cffcccccc\226\128\162|r Click |cff00ff00[game names]|r in chat to open that game directly\n\n"
    defaultHelp = defaultHelp .. "|cffcccccc\226\128\162|r Games require a party or raid - invite friends!\n\n"
    defaultHelp = defaultHelp .. "|cffcccccc\226\128\162|r One person hosts, others join. The host is the 'house'.\n\n"
    defaultHelp = defaultHelp .. "|cffcccccc\226\128\162|r Settle debts with in-game gold trades after games.\n\n"
    defaultHelp = defaultHelp .. "|cff888888Select a game on the left to see its rules.|r"
    
    contentText:SetText(defaultHelp)
    
    -- Store default help text for back button
    panel.defaultHelpText = defaultHelp
    
    panel.contentText = contentText
    panel.scrollChild = scrollChild
    panel.scrollFrame = scrollFrame
    
    -- Set initial scroll height after a frame delay (text needs to render)
    C_Timer.After(0.01, function()
        if panel.contentText then
            local textHeight = panel.contentText:GetStringHeight()
            panel.scrollChild:SetHeight(math.max(340, textHeight + 20))
        end
    end)
    
    self.helpPanel = panel
    
    -- Tall Trixie on the right side (same dimensions as lobby Trixie)
    local TRIXIE_WIDTH = 274
    local TRIXIE_HEIGHT = 350
    
    local helpTrixieFrame = CreateFrame("Button", "HelpTrixieFrame", UIParent)
    helpTrixieFrame:SetSize(TRIXIE_WIDTH, TRIXIE_HEIGHT)
    helpTrixieFrame:SetPoint("LEFT", panel, "RIGHT", 0, 0)
    helpTrixieFrame:SetFrameStrata("HIGH")
    
    local helpTrixieTexture = helpTrixieFrame:CreateTexture(nil, "ARTWORK")
    helpTrixieTexture:SetAllPoints()
    BJ.Trixie:Attach(helpTrixieFrame, helpTrixieTexture)
    
    -- Click for easter egg poke
    helpTrixieFrame:SetScript("OnClick", function()
        Lobby:TryPlayPoke()
    end)
    
    -- Fresh pose each time help is shown
    panel:HookScript("OnShow", function()
        helpTrixieFrame:Idle(true)
    end)
    
    helpTrixieFrame:Hide()
    self.helpTrixie = helpTrixieFrame
end

-- Show main help page (called by back button)
function Lobby:ShowMainHelp()
    if not self.helpPanel then return end
    
    -- Reset content to default
    self.helpPanel.contentText:SetText(self.helpPanel.defaultHelpText)
    
    -- Resize scroll child
    local textHeight = self.helpPanel.contentText:GetStringHeight()
    self.helpPanel.scrollChild:SetHeight(math.max(340, textHeight + 20))
    
    -- Scroll to top
    self.helpPanel.scrollFrame:SetVerticalScroll(0)
    
    -- Hide back button
    self.helpPanel.backBtn:Hide()
end

-- Which UI module owns a game's window (blackjack lives on UI itself)
local function gameUIModule(game)
    if game == "blackjack" then return UI end
    if game == "poker" then return UI.Poker end
    if game == "holdem" then return UI.Holdem end
    if game == "hilo" then return UI.HiLo end
    if game == "deathroll" then return UI.DeathRoll end
    if game == "bingo" then return UI.Bingo end
    if game == "roulette" then return UI.Roulette end
    if game == "liarsdice" then return UI.LiarsDice end
    if game == "crash" then return UI.Crash end
    if game == "slots" then return UI.Slots end
    if game == "videopoker" then return UI.VideoPoker end
    if game == "derby" then return UI.Derby end
end

-- Open the help panel directly on one game's rules (used by the
-- "How to Play" button each game window carries). The game window is
-- hidden while help is up and restored when it closes.
function Lobby:ShowHowToPlay(game)
    local mod = gameUIModule(game)
    if mod and mod.Hide then mod:Hide() end
    self:ShowHelp()
    self:ShowHelpContent(game)
    self.helpFromGame = true
    self.helpReturnModule = mod
end

-- Attach a small "How to Play" button to a game window (same style as
-- the Derby's). Returns the button so callers can reposition it.
function Lobby:AttachHowToPlayButton(parent, gameKey, x, y)
    local btn = BJ.Theme:Button(parent, "How to Play", 86, 20, "secondary")
    btn:SetPoint("TOPLEFT", x or 10, y or -10)
    btn:SetFrameLevel(parent:GetFrameLevel() + 20)
    btn:SetScript("OnClick", function()
        Lobby:ShowHowToPlay(gameKey)
    end)
    return btn
end

function Lobby:ShowHelpContent(game)
    if not self.helpPanel then return end
    
    local content = self.helpContent[game]
    if not content then return end
    
    -- Update content
    self.helpPanel.contentText:SetText(content.text)
    
    -- Resize scroll child to fit content
    local textHeight = self.helpPanel.contentText:GetStringHeight()
    self.helpPanel.scrollChild:SetHeight(math.max(340, textHeight + 20))
    
    -- Scroll to top
    self.helpPanel.scrollFrame:SetVerticalScroll(0)
    
    -- Show back button
    self.helpPanel.backBtn:Show()
end
