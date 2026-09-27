"""Chat reading on the Forever client: secret strings and two-word names.

On Forever a chat message or sender can arrive as a secret string: it still
answers type() == "string", then throws when indexed, compared or matched.
And every player name is a first name and a surname ("Chairface Chippendale").

Takes BJ:Readable and BJ:ParseRoll straight out of Core.lua and checks them,
then checks that no chat handler goes back to trusting type() alone.
Run: python tests/chat_secret_test.py  (pip install lupa)
"""
import lupa
import os
import re

ADDON_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
passed = 0


def check(cond, label):
    global passed
    if not cond:
        raise SystemExit("FAIL " + label)
    passed += 1
    print("PASS " + label)


core = open(os.path.join(ADDON_DIR, "Core.lua"), encoding="utf-8").read()


def function_source(name):
    m = re.search(r"^function BJ:" + name + r"\(.*?^end$", core, re.M | re.S)
    if not m:
        raise SystemExit("FAIL Core.lua has no BJ:" + name)
    return m.group(0)


lua = lupa.LuaRuntime(unpack_returned_tuples=True)
lua.execute("BJ = {}")
lua.execute(function_source("Readable"))
lua.execute(function_source("ParseRoll"))
# A stand-in for a secret string: reading it in any way throws.
lua.execute('SECRET = setmetatable({}, { __tostring = function() error("secret string value") end })')
ev = lua.eval

check(ev('BJ:Readable("hello")') == "hello", "a plain string reads as itself")
check(ev("BJ:Readable(SECRET)") is None, "a secret reads as nil, not an error")
check(ev('BJ:Readable("")') is None and ev("BJ:Readable(nil)") is None, "empty and nil read as nil")


def roll(line):
    return ev('{ BJ:ParseRoll(%r) }' % line)


r = roll("Chairface Chippendale rolls 42 (1-100)")
check(r[1] == "Chairface Chippendale" and r[2] == 42 and r[3] == 100,
      "a two-word Forever name rolls under the whole name")
r = roll("Sewer Urchin-Classicbetapvp2 rolls 7 (1-50)")
check(r[1] == "Sewer Urchin" and r[2] == 7 and r[3] == 50,
      "a realm after the name is dropped, to match UnitName keys")
r = roll("Arthas rolls 3 (1-10)")
check(r[1] == "Arthas", "a one-word name still parses")
check(ev("BJ:ParseRoll(SECRET)") is None, "a secret roll line is skipped, not an error")
check(ev('BJ:ParseRoll("Chairface Chippendale says hi")') is None, "a line that is not a roll is nil")

# No chat handler may trust type() == "string" on its own again: every one
# reads through BJ:Readable or BJ:ParseRoll.
handlers = {
    "Games/Arcade.lua": "BJ:Readable(text)",
    "Core/Leaderboard.lua": "BJ:Readable(text)",
    "Core/TableFinder.lua": "BJ:Readable(text)",
    "Games/HiLo/HiLoMultiplayer.lua": "BJ:Readable(message)",
    "Games/DeathRoll/DeathRollMultiplayer.lua": "BJ:ParseRoll(msg)",
    "UI/HiLoFrame.lua": "BJ:ParseRoll(msg)",
}
for path, needle in handlers.items():
    src = open(os.path.join(ADDON_DIR, path), encoding="utf-8").read()
    check(needle in src, path + " reads chat through " + needle.split("(")[0])
    check('(%S+) rolls' not in src, path + " has no one-word roll pattern")

print(f"\nAll {passed} checks passed.")
