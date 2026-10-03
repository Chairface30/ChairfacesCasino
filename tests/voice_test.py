"""Trixie's voice: the frequency slider, and one line at a time.

Takes the voice functions straight out of UI/Lobby.lua and checks:
  - Always speaks every time; Rare only very rarely; the stops in between
    are the chances they say;
  - while a line is playing (for its measured length), a new one is dropped,
    not queued and never played over her;
  - only the table-open call skips the slider;
  - pokes and the intro follow the same rule.
Run: python tests/voice_test.py  (pip install lupa)
"""
import os
import re

from lupa import lua51

ADDON_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
passed = 0


def check(cond, label):
    global passed
    if not cond:
        raise SystemExit("FAIL " + label)
    passed += 1
    print("PASS " + label)


lobby = open(os.path.join(ADDON_DIR, "UI", "Lobby.lua"), encoding="utf-8").read()


def block(start, end_marker):
    i = lobby.index(start)
    j = lobby.index(end_marker, i)
    return lobby[i:j]


def function_source(name):
    m = re.search(r"^function Lobby:" + name + r"\(.*?^end$", lobby, re.M | re.S)
    if not m:
        raise SystemExit("FAIL Lobby.lua has no Lobby:" + name)
    return m.group(0)


lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
NOW = 100
function GetTime() return NOW end
PLAYED, STOPPED = {}, {}
local handle = 0
function PlaySoundFile(path, channel)
    handle = handle + 1
    table.insert(PLAYED, path)
    return true, handle
end
function StopSound(h) table.insert(STOPPED, h) end
RANDOM = nil               -- when set, math.random() returns it
local realRandom = math.random
math.random = function(a, b)
    if a == nil then return RANDOM or realRandom() end
    if b == nil then return realRandom(a) end
    return realRandom(a, b)
end
BJ = { TRIXIE_LENGTHS = { trix_win1 = 3.0, trix_win2 = 3.0, trix_lose1 = 2.0, trix_lose2 = 2.0,
                          trix_open_blackjack1 = 2.5, trix_intro = 14.0, trix_poke1 = 1.5,
                          trix_poke2 = 1.5, trix_poke3 = 1.5, trix_poke4 = 1.5 },
       db = { settings = {} } }
Lobby = { voiceEnabled = true, TRIXIE_VOICE = { win = 2, lose = 2, open_blackjack = 1 } }
function Lobby:GetVoiceFrequency() return BJ.db.settings.voiceFrequency or 3 end
function Lobby:GetPokeChance() return 1 end
''')
lua.execute(block("Lobby.VOICE_CHANCE", "function Lobby:TryPlayPokeSound()"))
lua.execute(block("Lobby.lastVoiceAt = {}", "-- Back-compat wrappers"))
lua.execute(function_source("TryPlayPoke"))
lua.execute(function_source("PlayTrixieIntroVoice"))
ev = lua.eval


def played():
    return [ev(f"PLAYED[{i}]") for i in range(1, ev("#PLAYED") + 1)]


def reset(freq):
    lua.execute(f"PLAYED, STOPPED = {{}}, {{}} Lobby.voiceEndsAt = nil Lobby.lastVoiceAt = {{}} "
                f"BJ.db.settings.voiceFrequency = {freq} RANDOM = nil")


# --- Always -------------------------------------------------------------------
reset(1)
for _ in range(20):
    lua.execute("NOW = NOW + 5 Lobby:PlayTrixieVoice('win')")
check(len(played()) == 20, "Always: she speaks every time")

reset(1)
lua.execute("Lobby:PlayTrixieVoice('win') NOW = NOW + 1 Lobby:PlayTrixieVoice('lose')")
check(len(played()) == 1 and ev("#STOPPED") == 0, "while she is speaking, a new line is dropped, not played over her")
lua.execute("NOW = NOW + 5")
check(len(played()) == 1, "and it is not queued: nothing plays later on its own")
lua.execute("Lobby:PlayTrixieVoice('lose')")
check(len(played()) == 2, "once her line has run its length, the next one plays")
lua.execute("NOW = NOW + 1.5 Lobby:PlayTrixieVoice('win')")
check(len(played()) == 2, "the check uses each clip's measured length, not a fixed wait")
lua.execute("NOW = NOW + 1 Lobby:PlayTrixieVoice('win')")
check(len(played()) == 3, "a short clip frees her sooner than a long one")

# --- the slider's odds ----------------------------------------------------------
for freq, name, chance in [(2, "Frequent", 0.6), (3, "Normal", 0.35), (5, "Occasional", 0.15), (10, "Rare", 0.04)]:
    reset(freq)
    lua.execute(f"RANDOM = {chance - 0.001} Lobby:PlayTrixieVoice('win')")
    lua.execute(f"NOW = NOW + 5 RANDOM = {chance + 0.001} Lobby:PlayTrixieVoice('win')")
    check(len(played()) == 1, f"{name}: she speaks {int(chance * 100)}% of the time")

reset(10)
lua.execute("RANDOM = nil")
n = 0
for _ in range(2000):
    lua.execute("NOW = NOW + 20 Lobby:PlayTrixieVoice('win')")
n = len(played())
check(20 <= n <= 150, f"Rare really is rare: {n} lines in 2000 chances")

# --- the table-open call ----------------------------------------------------------
reset(10)
lua.execute("RANDOM = 0.99 Lobby:PlayTrixieVoice('open_blackjack', { noFreq = true })")
check(played() and played()[-1].endswith("trix_open_blackjack1.ogg"), "a table-open call skips the slider, even at Rare")
lua.execute("NOW = NOW + 1 Lobby:PlayTrixieVoice('open_blackjack', { noFreq = true })")
check(len(played()) == 1, "but still never plays over her")

# --- mute, pokes, the intro --------------------------------------------------------
reset(1)
lua.execute("Lobby.voiceEnabled = false Lobby:PlayTrixieVoice('win') Lobby.voiceEnabled = true")
check(len(played()) == 0, "muted, nothing plays")
lua.execute("Lobby:PlayTrixieVoice('win') NOW = NOW + 1 Lobby:TryPlayPoke()")
check(len(played()) == 1, "a poke while she is speaking is dropped")
lua.execute("NOW = NOW + 5 Lobby:TryPlayPoke()")
check(len(played()) == 2 and "trix_poke" in played()[-1], "a poke when she is quiet plays")
lua.execute("NOW = NOW + 5 Lobby:PlayTrixieVoice('win') NOW = NOW + 1 Lobby:PlayTrixieIntroVoice()")
check(played()[-1].endswith("trix_intro.ogg") and ev("#STOPPED") == 1, "the intro stops her line and plays")
lua.execute("NOW = NOW + 10 Lobby:PlayTrixieVoice('win')")
check(not played()[-1].endswith("win1.ogg") and not played()[-1].endswith("win2.ogg"),
      "and counts as speaking for its full fourteen seconds")

# --- nothing else skips the slider --------------------------------------------------
src = ""
for base, _, files in os.walk(ADDON_DIR):
    if os.sep + "tests" in base or os.sep + "tools" in base or os.sep + "Libs" in base:
        continue
    for f in files:
        if f.endswith(".lua"):
            src += open(os.path.join(base, f), encoding="utf-8").read()
check(len(re.findall(r"noFreq\s*=\s*true", src)) == 1, "only the table-open call skips the slider")

# --- lines that wait for her talk animation ------------------------------------------
lua.execute(block("function Lobby:StopTrixieIntroVoice()", "--[[\n    CENTRAL TRIXIE VOICE POOLS"))
lua.execute(r'''
TIMERS, TALKS, STOPS = {}, {}, 0
C_Timer = { After = function(s, fn) table.insert(TIMERS, { at = NOW + s, fn = fn }) end }
function RunTimers()
    for i = #TIMERS, 1, -1 do
        local t = TIMERS[i]
        if NOW >= t.at then table.remove(TIMERS, i) t.fn() end
    end
end
LEAD = 1.5
BJ.Trixie = {
    TalkLead = function() return LEAD end,
    TalkEverywhere = function(_, secs) table.insert(TALKS, secs) end,
    StopTalkEverywhere = function() STOPS = STOPS + 1 end,
}
''')
reset(1)
lua.execute("TALKS = {} Lobby:PlayTrixieVoice('win', { lineUp = true })")
check(len(played()) == 0 and ev("TALKS[1]") == 4.5,
      "a lined-up line waits; her talk is set for the wait plus the line")
lua.execute("NOW = NOW + 1 Lobby:PlayTrixieVoice('lose') RunTimers()")
check(len(played()) == 0, "while it waits she counts as speaking: nothing slips in")
lua.execute("NOW = NOW + 0.5 RunTimers()")
check(len(played()) == 1 and "trix_win" in played()[0], "it plays once every Trixie reaches her seam")
lua.execute("NOW = NOW + 2.5 Lobby:PlayTrixieVoice('lose')")
check(len(played()) == 1, "and she counts as speaking for the clip's length after it starts")
lua.execute("NOW = NOW + 1 Lobby:PlayTrixieVoice('lose')")
check(len(played()) == 2, "then she is free again")

reset(1)
lua.execute("NOW = NOW + 10 Lobby:PlayTrixieVoice('win')")
check(len(played()) == 1, "a line without lineUp plays at once, whatever the animation is doing")

reset(1)
lua.execute("NOW = NOW + 10 Lobby:PlayTrixieVoice('win', { lineUp = true }) Lobby.voiceEnabled = false "
            "NOW = NOW + 2 RunTimers() Lobby.voiceEnabled = true")
check(len(played()) == 0 and not ev("Lobby:TrixieSpeaking()") and ev("STOPS") == 1,
      "muted during the wait: it never plays and her talk stops")

reset(1)
lua.execute("NOW = NOW + 10 STOPS = 0 Lobby:PlayTrixieIntroVoice() Lobby:StopTrixieIntroVoice() "
            "NOW = NOW + 2 RunTimers()")
check(len(played()) == 0 and ev("STOPS") == 1, "Let's Play! during the intro's wait cancels it")

reset(1)
lua.execute("LEAD = 0 NOW = NOW + 10 Lobby:PlayTrixieVoice('win', { lineUp = true })")
check(len(played()) == 1, "no wait needed: a lined-up line plays at once")

print(f"\nAll {passed} checks passed.")
