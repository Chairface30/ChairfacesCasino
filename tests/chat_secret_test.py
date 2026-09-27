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


# Lua 5.1, the game's own: patterns are read the way WoW reads them.
try:
    from lupa import lua51 as _lua51
    lua = _lua51.LuaRuntime(unpack_returned_tuples=True)
except ImportError:
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
lua.execute("BJ = {}")
lua.execute(function_source("Readable"))
lua.execute(function_source("ParseRoll"))
lua.execute(function_source("SeatName"))
lua.execute(function_source("TakeName"))
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

# Names in the games: the first name, and the whole name (in a smaller
# font) when someone else there has the same first name.
seat = lambda expr: tuple(ev("{ BJ:SeatName(%s) }" % expr).values())
check(seat("'Chairface Chippendale'") == ("Chairface", False), "on its own, the first name")
check(seat("'Sewer Urchin', { 'Sewer Urchin', 'Notte Sure', 'Highley Regarded' }") == ("Sewer", False),
      "at a table where nobody shares it, the first name")
check(seat("'Highley Regarded-Classicbetapvp2'") == ("Highley", False), "the realm is never shown")
check(seat("'Chairface Chippendale', { 'Chairface Chippendale', 'Chairface Cobblestone' }")
      == ("Chairface Chippendale", True), "two Chairfaces: the whole name, flagged for the smaller font")
check(seat("'Chairface Cobblestone', { 'Chairface Chippendale', 'Chairface Cobblestone' }")
      == ("Chairface Cobblestone", True), "the other one too")
check(seat("'Sewer Urchin', { 'Chairface Chippendale', 'Chairface Cobblestone', 'Sewer Urchin' }")
      == ("Sewer", False), "someone else's shared name leaves yours alone")
check(seat("'Chairface Chippendale', { 'Chairface Chippendale', 'CHAIRFACE COBBLESTONE' }")
      == ("Chairface Chippendale", True), "case does not make two first names different")
check(seat("'Chairface Chippendale-RealmA', { 'Chairface Chippendale-RealmA', 'Chairface Chippendale-RealmB' }")
      == ("Chairface Chippendale-RealmA", True), "same name on two realms: the realm as well")
check(seat("'Marguerite Élodie', { 'Marguerite Élodie', 'Marguerite Evans' }") == ("Marguerite Élodie", True),
      "an accented surname is shown whole")
check(seat("SECRET") == ("?", False), "a secret name shows as ?")

# The font: smaller while a whole name shows, back to its own size after.
lua.execute(function_source("FitNameFont"))
lua.execute("""
FS = { font = { "Fonts\\FRIZQT__.TTF", 14, "OUTLINE" } }
function FS:GetFont() return self.font[1], self.font[2], self.font[3] end
function FS:SetFont(f, size, flags) self.font = { f, size, flags } end
""")
lua.execute("BJ:FitNameFont(FS, true)")
check(ev("FS.font[2]") == 12 and ev("FS.font[3]") == "OUTLINE", "a whole name: 85% size, same face and outline")
lua.execute("BJ:FitNameFont(FS, true)")
check(ev("FS.font[2]") == 12, "shrinking twice does not shrink further")
lua.execute("BJ:FitNameFont(FS, false)")
check(ev("FS.font[2]") == 14, "a first name again: the label's own size")
lua.execute("BJ:FitNameFont(nil, true); BJ:FitNameFont({}, true)")
check(True, "no label, or not a font string, is ignored")

# Commands that take names: each name is two words.
take = lambda text: tuple(ev("{ BJ:TakeName(%r) }" % text).values())
check(take("Sewer Urchin 50") == ("Sewer Urchin", "50"), "a name and what follows")
check(take("Sewer Urchin Chairface Chippendale 25") == ("Sewer Urchin", "Chairface Chippendale 25"), "two names in a row")
check(take("Sewer Urchin-Classicbetapvp2 50") == ("Sewer Urchin-Classicbetapvp2", "50"), "with a realm on the surname")
check(ev("(BJ:TakeName('50 Sewer'))") is None, "a number is not a name")

# The fake players in test mode look like real Forever names.
testmode = open(os.path.join(ADDON_DIR, "Core", "TestMode.lua"), encoding="utf-8").read()
at = testmode.index("TM.fakeNames = {")
fakes = re.findall(r'"([^"]+)"', testmode[at:testmode.index("}", at)])
check(len(fakes) == 60 and all(re.fullmatch(r"[A-Za-z]{2,12} [A-Za-z]{2,12}", n) for n in fakes),
      "60 fake players, every one two words of 2 to 12 letters")

# UnitName on Forever: the surname comes back as the second value, where
# other clients put a realm. "Is this me?" needs both, as chat gives them.
_a = core.index("BJ.isForever = ")
_b = core.index("-- Utility: a server /roll system line")
def names_on(toc, first, second):
    rt = (_lua51.LuaRuntime(unpack_returned_tuples=True) if "_lua51" in globals()
          else lupa.LuaRuntime(unpack_returned_tuples=True))
    rt.execute("BJ = {}")
    rt.execute(function_source("Readable"))
    rt.globals().TOC, rt.globals().FIRST, rt.globals().SECOND = toc, first, second
    rt.execute("function GetBuildInfo() return '1', '1', 'x', TOC end "
               "function UnitName(u) return FIRST, SECOND end")
    rt.execute(core[_a:_b])
    return rt.eval("BJ:MyName()"), rt.eval("BJ:UnitFullName('party1')")
check(names_on(16001, "Highley", "Regarded") == ("Highley Regarded", "Highley Regarded"),
      "on Forever, your name is the first name and the surname together")
check(names_on(11507, "Highley", "Realmname") == ("Highley", "Highley"),
      "on other clients the second value is a realm, and is left off as before")
check(names_on(16001, "Solo", None) == ("Solo", "Solo"), "no second value: the name as it is")
import glob as _glob
_direct = []
for _path in _glob.glob(os.path.join(ADDON_DIR, "**", "*.lua"), recursive=True):
    if os.sep + "Libs" + os.sep in _path:
        continue
    for _n, _line in enumerate(open(_path, encoding="utf-8"), 1):
        if "UnitName(" in _line and "BJ:UnitFullName(\"player\") or UnitName(\"player\")" not in _line \
                and "local n, r = UnitName(unit)" not in _line and "local name, realm = UnitName(\"NPC\")" not in _line:
            _direct.append(os.path.relpath(_path, ADDON_DIR) + ":" + str(_n))
check(not _direct, "no code reads UnitName's first value alone (use BJ:MyName / BJ:UnitFullName)")
if _direct:
    print("   ", _direct[:10])

# Test mode's allowlist knows the two-word names, and not a lookalike.
head = testmode[:testmode.index("-- Test mode state")]
lua.execute("ChairfacesCasino = {} " + head + " TEST_V = V")
allowed = lambda n: ev("TEST_V[%r] == 1" % n)
check(all(allowed(n) for n in ("Chairface Chippendale", "Highley Regarded", "Notte Sure", "Sewer Urchin")),
      "test mode allows your two-word Forever characters")
check(not allowed("Chairface Carter") and not allowed("Sewer"), "but not someone who only shares a first name")

# No chat handler may trust type() == "string" on its own again: every one
# reads through BJ:Readable or BJ:ParseRoll.
handlers = {
    "Games/Arcade.lua": "BJ:Readable(text)",
    "Core/Leaderboard.lua": "BJ:Readable(text)",
    "Core/TableFinder.lua": "BJ:Readable(text)",
    "Games/HiLo/HiLoMultiplayer.lua": "BJ:Readable(message)",
    "Games/DeathRoll/DeathRollMultiplayer.lua": "BJ:ParseRoll(msg)",
    "UI/PokerFrame.lua": "BJ:FitNameFont(handDisplay.label, wholeName)",
    "UI/HoldemFrame.lua": "BJ:FitNameFont(handDisplay.label, wholeName)",
    "UI/MainFrame.lua": "BJ:FitNameFont(handDisplay.label, wholeName)",
    "UI/CrashFrame.lua": "BJ:FitNameFont(chute.label, wholeName)",
    "UI/BingoFrame.lua": "BJ:FitNameFont(cf.nameText, wholeName)",
    "UI/LiarsDiceFrame.lua": "BJ:FitNameFont(row.label, wholeName)",
    "UI/DeathRollFrame.lua": "BJ:FitNameFont(self.oppText",
    "Games/Derby/SigmaDerbyUI.lua": "CC:SeatName(shortName(name), names)",
    "UI/HiLoFrame.lua": "BJ:ParseRoll(msg)",
    "UI/LeaderboardUI.lua": "BJ:FitNameFont(row.name, wholeName)",
    "UI/DebtsFrame.lua": "BJ:FitNameFont(row.left, rowWhole)",
}
for path, needle in handlers.items():
    src = open(os.path.join(ADDON_DIR, path), encoding="utf-8").read()
    check(needle in src, path + " uses " + needle.split("(")[0])
    check('(%S+) rolls' not in src, path + " has no one-word roll pattern")

derby = open(os.path.join(ADDON_DIR, "Games", "Derby", "SigmaDerbyUI.lua"), encoding="utf-8").read()
_k = derby.index("local function shortName(name)")
check("SeatName" not in derby[_k:derby.index("\n", _k)], "Chair's Cup keys players by the whole name")
check("RecordHandResult(\"chairscup\", pl.name" in derby and "name = shortName(player)" in derby,
      "Chair's Cup debts and hands use those keys")

print(f"\nAll {passed} checks passed.")
