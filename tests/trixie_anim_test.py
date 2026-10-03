"""Tests for UI/Trixie.lua, the shared Trixie sprite player.

Loads Trixie.lua against a tiny mocked frame API with a fake clip manifest
and checks: idle rotation, reactions going back to idle, chaining, no
back-to-back repeats, still holds, hidden widgets not advancing, and that
every real manifest entry points at a file that exists with sane texcoords.
Also checks that no window still sets a dealer texture path by hand.
Run: python tests/trixie_anim_test.py  (pip install lupa)
"""
import lupa
import os
import re
import sys

ADDON_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MOCK = r"""
math.randomseed(4242)
__now = 0
function GetTime() return __now end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
ChairfacesCasino = { }
local Obj = {}
Obj.__index = Obj
function Obj:IsVisible() return self._shown ~= false end
function Obj:IsShown() return self._shown ~= false end
function Obj:Show() self._shown = true end
function Obj:Hide() self._shown = false end
function Obj:SetScript(name, fn) self["_" .. name] = fn end
function Obj:SetTexture(f) self._file = f end
function Obj:SetTexCoord(a, b, c, d) self._tc = { a, b, c, d } end
__drivers = {}
function CreateFrame()
  local f = setmetatable({}, Obj)
  table.insert(__drivers, f)
  return f
end
function NewWidget()
  local w = setmetatable({}, Obj)
  local tex = setmetatable({}, Obj)
  return w, tex
end
function Step(secs, dt)
  dt = dt or 0.05
  local n = math.floor(secs / dt + 0.5)
  for _ = 1, n do
    __now = __now + dt
    ChairfacesCasino.Trixie.Tick()
  end
end
"""

FAKE_CLIPS = r"""
ChairfacesCasino.TrixieClips = {
  { name = "idle_a", mood = "wait", file = "idle_a", frames = 8, cols = 4, fw = 100, fh = 128, texW = 400, texH = 256, fps = 8, loop = true },
  { name = "idle_b", mood = "wait", file = "idle_b", frames = 8, cols = 4, fw = 100, fh = 128, texW = 400, texH = 256, fps = 8, loop = true },
  { name = "win_a",  mood = "win",  file = "win_a",  frames = 8, cols = 4, fw = 100, fh = 128, texW = 400, texH = 256, fps = 8 },
  { name = "win_b",  mood = "cheer", file = "win_b", frames = 8, cols = 4, fw = 100, fh = 128, texW = 400, texH = 256, fps = 8 },
  { name = "deal_a", mood = "deal", file = "deal_a", frames = 8, cols = 4, fw = 100, fh = 128, texW = 400, texH = 256, fps = 8 },
}
"""

FAILS = []


def check(cond, msg):
    if not cond:
        FAILS.append(msg)
        print("FAIL:", msg)


def runtime(clips):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    if clips:
        lua.execute(clips)
    src = open(os.path.join(ADDON_DIR, "UI", "Trixie.lua"), encoding="utf-8").read()
    lua.execute(src)
    return lua


def test_stills_only():
    lua = runtime(None)
    T = lua.eval("ChairfacesCasino.Trixie")
    check(len(list(T.order.values())) == 82, "82 stills when no clips are shipped")
    w, tex = lua.eval("NewWidget()")
    T.Attach(T, w, tex)
    first = w.trix.cur.name
    check(first.startswith("trix_wait"), "starts on a wait still")
    lua.execute("Step(30)")
    check(w.trix.cur.name == first, "with no idle clips a wait still holds (old behavior)")
    w.React(w, "win")
    check(w.trix.cur.name.startswith("trix_win"), "React win shows a win still")
    lua.execute("Step(30)")
    check(w.trix.cur.name.startswith("trix_win"), "a still reaction without hold stays until told")
    w.React(w, "lose", lua.table_from({"hold": 3}))
    lua.execute("Step(3.2)")
    check(w.trix.cur.name.startswith("trix_wait"), "a held still goes back to idle after hold")
    # Lobby:TrixieReact path, cheer alias
    w.React(w, "cheer")
    check(w.trix.cur.mood == "win", "cheer is an alias for win")
    w.SetState(w, "deal3")
    check(w.trix.cur.name == "trix_deal3", "SetState accepts old state names")


def test_clips():
    lua = runtime(FAKE_CLIPS)
    T = lua.eval("ChairfacesCasino.Trixie")
    check(T.HasClips(T, "wait") and T.HasClips(T, "win"), "clips land in their pools")
    check(T.byName["win_b"].mood == "win", "manifest mood aliases resolve")
    w, tex = lua.eval("NewWidget()")
    T.Attach(T, w, tex)

    # idle never sticks: over a minute it visits more than one entry
    seen = set()
    for _ in range(120):
        lua.execute("Step(0.5)")
        seen.add(w.trix.cur.name)
    check(len(seen) > 2, "idle rotates through several entries (saw %d)" % len(seen))

    # a clip reaction plays once then returns to idle
    T.CLIP_SHARE = 1
    w.React(w, "win")
    check(w.trix.cur.name in ("win_a", "win_b"), "React picks a win clip")
    check(tex._file.endswith(w.trix.cur.name), "texture is the clip sheet")
    lua.execute("Step(0.6)")
    check(w.trix.frame > 0, "clip frames advance")
    tc = tex._tc
    check(all(0 <= tc[i] <= 1 for i in range(1, 5)), "texcoords inside 0-1")
    lua.execute("Step(1.0)")
    check(w.trix.cur.mood == "wait", "clip reaction returns to idle when done")

    # no back-to-back repeat
    last = None
    for _ in range(20):
        w.React(w, "win")
        name = w.trix.cur.name
        check(name != last, "React never repeats the same clip back to back")
        last = name
        lua.execute("Step(1.2)")

    # repeated deal calls (one per card) don't restart a playing deal clip
    w.React(w, "deal")
    lua.execute("Step(0.4)")
    start = w.trix.start
    w.React(w, "deal")
    check(w.trix.start == start, "same-mood clip keeps playing on repeat calls")

    # Idle() while an idle clip plays keeps it going; Idle(true) rolls fresh
    w.Idle(w, True)
    lua.execute("Step(0.3)")
    if not w.trix.cur.still:
        start = w.trix.start
        w.Idle(w)
        check(w.trix.start == start, "Idle() does not restart a playing idle clip")

    # chaining: win_a then deal_a then idle
    w.Queue(w, "win_a", "deal_a")
    check(w.trix.cur.name == "win_a", "Queue starts with the first clip")
    lua.execute("Step(1.05)")
    check(w.trix.cur.name == "deal_a", "Queue moves to the second clip")
    lua.execute("Step(1.05)")
    check(w.trix.cur.mood == "wait", "Queue ends back on idle")

    # hidden widgets do not advance
    w.Play(w, "win_a")
    w.Hide(w)
    lua.execute("Step(0.5)")
    check(w.trix.frame == 0, "hidden widget does not step frames")
    w.Show(w)
    lua.execute("Step(2)")
    check(w.trix.cur.mood == "wait", "shown again it catches up and moves on")

    # debug browser: clips loop forever until changed
    T.ShowEverywhere(T, "deal_a")
    lua.execute("Step(10)")
    check(w.trix.cur.name == "deal_a", "debug entry stays up")


def test_manifest_files():
    lua = runtime(None)
    path = os.path.join(ADDON_DIR, "UI", "TrixieClips.lua")
    lua.execute(open(path, encoding="utf-8").read())
    clips = lua.eval("ChairfacesCasino.TrixieClips")
    for c in clips.values():
        f = os.path.join(ADDON_DIR, "Textures", "dealer", "anim", c.file)
        check(os.path.exists(f + ".tga") or os.path.exists(f + ".blp"), "clip file exists: " + c.file)
        check(c.cols * c.fw <= c.texW, "clip columns fit the sheet: " + c.name)
        rows = -(-c.frames // c.cols)
        check(rows * c.fh <= c.texH, "clip rows fit the sheet: " + c.name)
        check(c.mood in ("wait", "idle", "win", "cheer", "lose", "love", "deal", "shuf", "shuffle"), "known mood: " + c.name)


def test_no_hand_set_dealer_paths():
    bad = re.compile(r"dealer\\\\trix_")
    for root, _, files in os.walk(ADDON_DIR):
        if any(p in root for p in ("Libs", "tests", "tools", ".git")):
            continue
        for fn in files:
            if not fn.endswith(".lua") or fn == "Trixie.lua":
                continue
            text = open(os.path.join(root, fn), encoding="utf-8", errors="replace").read()
            check(not bad.search(text), "%s sets a Trixie texture by hand; use BJ.Trixie" % fn)


if __name__ == "__main__":
    test_stills_only()
    test_clips()
    test_manifest_files()
    test_no_hand_set_dealer_paths()
    if FAILS:
        print("%d failure(s)" % len(FAILS))
        sys.exit(1)
    print("trixie_anim_test: all passed")
