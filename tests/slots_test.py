"""Azeroth Riches: the promises the balance rests on.

Loads the slot machine from Games/Arcade.lua (the same way tools/slots_sim.py
does) and checks:
  - a GEM RUSH always pays something, even on a single line;
  - there are no wilds on the rush strip;
  - two of a kind pays on the six best symbols, and on nothing else;
  - a jackpot pays at most its cap times the total bet, and what the cap
    leaves stays in the pot; one that empties the pot reseeds it;
  - a bet under a tier's minimum still gets only the floor.
The return to player itself is measured by tools/slots_sim.py, not here: it
needs millions of spins.
Run: python tests/slots_test.py  (pip install lupa)
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
import slots_sim  # noqa: E402

passed = 0


def check(cond, label):
    global passed
    if not cond:
        raise SystemExit("FAIL " + label)
    passed += 1
    print("PASS " + label)


lua = slots_sim.load(3)
ev = lua.eval

# --- Gem Rush ------------------------------------------------------------------
check(ev("Arcade.Slots.RICH_WEIGHTS.wild") == 0, "no wilds on the Gem Rush strip")
lua.execute("""
    local Slots = Arcade.Slots
    Slots.RICH_CHANCE = 1          -- every pull a rush
    RUSHES, EMPTY_ONE, EMPTY_NINE = 0, 0, 0
    for _ = 1, 3000 do
        local r = Slots:Spin(1, 1)
        RUSHES = RUSHES + (r.rich and 1 or 0)
        if r.payout <= 0 then EMPTY_ONE = EMPTY_ONE + 1 end
        r = Slots:Spin(1, 9)
        if r.payout <= 0 then EMPTY_NINE = EMPTY_NINE + 1 end
    end
    Slots.RICH_CHANCE = 1 / 11
""")
check(ev("RUSHES") == 3000, "the test forced every pull to be a rush")
check(ev("EMPTY_ONE") == 0, "a Gem Rush on a single line always pays (3,000 rushes)")
check(ev("EMPTY_NINE") == 0, "a Gem Rush on nine lines always pays (3,000 rushes)")

# --- two of a kind -----------------------------------------------------------------
pays2 = {s: ev(f"Arcade.Slots.LINE_PAY.{s}[2]") for s in
         ["wild", "skull", "gold", "ruby", "emerald", "sapphire", "die", "shroom", "melon", "apple", "silver", "copper"]}
check(all(pays2[s] for s in ["wild", "skull", "gold", "ruby", "emerald", "sapphire"]),
      "two of a kind pays on the six best symbols")
check(not any(pays2[s] for s in ["die", "shroom", "melon", "apple", "silver", "copper"]),
      "and on nothing below them")
check(ev("(select(1, Arcade.Slots:EvaluateLine({ 'ruby', 'ruby', 'apple', 'melon', 'die' })))") == 2,
      "ruby, ruby, then anything pays the two-of-a-kind")
check(ev("(select(1, Arcade.Slots:EvaluateLine({ 'apple', 'apple', 'ruby', 'melon', 'die' })))") == 0,
      "apple, apple pays nothing")

# --- the jackpot cap -----------------------------------------------------------------
lua.execute("""
    local Slots = Arcade.Slots
    local pots = Arcade:GetDB().jackpots
    pots.minor = 100000
    PAID_SMALL = Slots:ClaimJackpot("minor", 9)
    LEFT_SMALL = pots.minor
    pots.minor = 30000
    PAID_BIG = Slots:ClaimJackpot("minor", 1000)
    LEFT_BIG = pots.minor
    pots.mini = 70000
    PAID_TINY = Slots:ClaimJackpot("mini", 2)
    LEFT_TINY = pots.mini
""")
cap_minor = ev("Arcade.Slots.JACKPOT_CAP.minor")
check(ev("PAID_SMALL") == cap_minor * 9, f"a 9-credit bet wins at most {cap_minor}x its bet from the minor pot")
check(ev("LEFT_SMALL") == 100000 - cap_minor * 9, "and the rest stays in the pot for the next winner")
check(ev("PAID_BIG") == 30000 and ev("LEFT_BIG") == ev("Arcade.Slots.JACKPOT_META.minor.seed"),
      "a bet big enough takes the whole pot, which reseeds")
check(ev("PAID_TINY") == ev("Arcade.Slots.JACKPOT_PAY.mini") * 2 and ev("LEFT_TINY") == 70000,
      "a bet under the minimum gets the floor and leaves the pot alone")

print(f"\nAll {passed} checks passed.")
