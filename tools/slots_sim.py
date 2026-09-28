#!/usr/bin/env python3
"""Simulate the Azeroth Riches slot machine, straight from Games/Arcade.lua.

Loads the Slots and Bonus sections of the real file and plays them, scoring
the side features the way UI/SlotsFrame.lua pays them:
  chest     - the average of the three chests offered (the player picks one)
  wheel     - every wedge equally likely
  freespins - count x mult spins on the bonus strip, each paying line wins x mult
  hold&spin - played out; jackpot coins claim their progressive pot through
              the game's own ClaimJackpot; the pots grows by the wall clock (SECS_PER_SPIN per spin) and by its
              slice of each wager, and reseeds when won
Reports return to player by source, how often a spin pays anything, Gem Rush
figures, and how long a bankroll lasts.

  python tools/slots_sim.py                        # 200,000 spins, 9 lines, 1 per line
  python tools/slots_sim.py --bet 10 --lines 9     # 10 per line
"""
import argparse, os, statistics
from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SECS_PER_SPIN = 5


def load(seed, patch=None):
    src = open(os.path.join(ROOT, "Games", "Arcade.lua"), encoding="utf-8").read()
    slots = src[src.index("Arcade.Slots = {}"):src.index("Arcade.Keno = {}")]
    bonus = src[src.index("Arcade.Bonus = {}"):src.index("Arcade.Poker = {}")]
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f"math.randomseed({seed})")
    lua.execute("""
        BJ = {}; Arcade = {}
        function Arcade:Spend(n) return true end
        function Arcade:Award(n) end
        local DB = { jackpots = {} }
        function Arcade:GetDB() return DB end
        function Arcade:SaveVault() end
        function GetTime() return 0 end
        function GetServerTime() return 0 end
        function time() return 0 end
        C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
        -- Frames and the chat channel the jackpot code sets up: nothing the
        -- simulation reads, so anything asked of them does nothing.
        local function Any() return setmetatable({}, { __index = function() return function() end end }) end
        function CreateFrame() return Any() end
        C_ChatInfo = Any()
        hooksecurefunc = function() end
    """)
    lua.execute(slots)
    lua.execute(bonus)
    if patch:
        lua.execute(patch)   # try out new numbers without editing the game
    lua.execute(f"""
        local Slots = Arcade.Slots
        -- The pots live where the game keeps them (Arcade:GetDB().jackpots),
        -- claimed by the game's own ClaimJackpot. Here they grow by the wall
        -- clock ({SECS_PER_SPIN}s a spin) and by their slice of each wager.
        local pots = Arcade:GetDB().jackpots
        for tier, meta in pairs(Slots.JACKPOT_META) do pots[tier] = meta.seed end
        function Slots:AccrueJackpots() end
        function Slots:FeedJackpots(totalBet)
            for tier, meta in pairs(self.JACKPOT_META) do
                pots[tier] = pots[tier] + meta.rate * {SECS_PER_SPIN} + meta.feed * totalBet
            end
        end
        -- One whole paid spin, side features included. Returns what it paid
        -- by source: line, bonus, coins, jackpots; the total bet; and
        -- whether it was a Gem Rush.
        function SIM_SPIN(betPerLine, lines)
            local r = Slots:Spin(betPerLine, lines)
            local bonus, coins, jp = 0, 0, 0
            if r.fireshot then
                local st = Slots:FireshotStart(r.coins, r.totalBet)
                while not st.done do Slots:FireshotRespin(st) end
                for _, c in pairs(st.locked) do
                    if c.jackpot then jp = jp + Slots:ClaimJackpot(c.jackpot, st.totalBet)
                    else coins = coins + (c.value or 0) end
                end
                if st.count >= Slots.GRAND_FILL then jp = jp + Slots:ClaimJackpot("grand", st.totalBet) end
            elseif r.bonus then
                local kind = Arcade.Bonus:RandomType()
                local stake = r.totalBet
                if kind == "chest" then
                    local c = Arcade.Bonus:MakeChests(stake)
                    bonus = (c[1] + c[2] + c[3]) / 3
                elseif kind == "wheel" then
                    local w = Arcade.Bonus:MakeWheel(stake)
                    bonus = w[math.random(#w)]
                else
                    local count, mult = Arcade.Bonus:MakeFreeSpins()
                    local bpl = math.max(1, math.floor(stake / math.max(1, lines)))
                    local left = count
                    while left > 0 do
                        left = left - 1
                        local g = Slots:GridFromStops(Slots:RollStops(Slots.BONUS_STRIP), Slots.BONUS_STRIP)
                        local _, pay = Slots:EvaluateGrid(g, bpl, lines)
                        bonus = bonus + pay * mult
                        local tokens = 0
                        for reel = 1, Slots.REELS do for row = 1, Slots.ROWS do
                            if g[reel][row] == "token" then tokens = tokens + 1 end
                        end end
                        if tokens >= Slots.FREESPIN_RETRIGGER then left = left + Slots.FREESPIN_EXTRA end
                    end
                end
            end
            return r.payout, bonus, coins, jp, r.totalBet, r.rich and true or false
        end
    """)
    return lua


def run(spin, spins, bet, lines):
    src = {"line (normal spins)": 0, "Gem Rush": 0, "3-coin bonuses": 0, "hold & spin coins": 0, "jackpots": 0}
    wagered, hits, rushes, rush_zero, rush_pay = 0, 0, 0, 0, 0
    wins = []
    for _ in range(spins):
        line, bonus, coins, jp, tb, rich = spin(bet, lines)
        total = line + bonus + coins + jp
        wagered += tb
        src["Gem Rush" if rich else "line (normal spins)"] += line
        src["3-coin bonuses"] += bonus
        src["hold & spin coins"] += coins
        src["jackpots"] += jp
        if total > 0:
            hits += 1
            wins.append(total / tb)
        if rich:
            rushes += 1
            rush_pay += total
            rush_zero += total <= 0
    paid = sum(src.values())
    tb = bet * lines
    print(f"{spins} spins, {lines} lines x {bet} = total bet {tb}")
    print(f"  return to player  {100 * paid / wagered:6.2f}%   (house edge {100 - 100 * paid / wagered:+.2f}%)")
    for k, v in src.items():
        print(f"      {k:<20} {100 * v / wagered:6.2f}%")
    print(f"  spins that pay    {100 * hits / spins:6.2f}%   (median win {statistics.median(wins):.1f}x bet)")
    print(f"  Gem Rush          1 in {spins / max(rushes, 1):.1f}, pays {rush_pay / max(rushes, 1) / tb:.1f}x bet on average,"
          f" pays nothing {100 * rush_zero / max(rushes, 1):.1f}% of the time")
    return 100 * paid / wagered


def bankroll(spin, bet, lines, players=400, cap=3000):
    tb = bet * lines
    lengths = []
    for _ in range(players):
        bank, n = 100 * tb, 0
        while bank >= tb and n < cap:
            line, bonus, coins, jp, t, _ = spin(bet, lines)
            bank += line + bonus + coins + jp - t
            n += 1
        lengths.append(n)
    lengths.sort()
    q = players // 4
    print(f"  100-bet bankroll  1 in 4 bust by {lengths[q]} spins, median {lengths[2 * q]},"
          f" {100 * sum(1 for l in lengths if l >= cap) / players:.0f}% still playing at {cap}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--spins", type=int, default=200000)
    ap.add_argument("--bet", type=int, default=1, help="per line")
    ap.add_argument("--lines", type=int, default=9)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--no-bankroll", action="store_true")
    ap.add_argument("--patch", help="a Lua file run after the game's, to try new numbers")
    args = ap.parse_args()
    patch = open(args.patch, encoding="utf-8").read() if args.patch else None
    spin = load(args.seed, patch).eval("SIM_SPIN")
    run(spin, args.spins, args.bet, args.lines)
    if not args.no_bankroll:
        bankroll(spin, args.bet, args.lines)


if __name__ == "__main__":
    main()
