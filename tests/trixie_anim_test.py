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
unpack = unpack or table.unpack
__now = 0
function GetTime() return __now end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
ChairfacesCasino = { }
ChairfacesCasinoDB = { }
UISpecialFrames = { }
tinsert = table.insert
local Obj = {}
-- widget methods (CapitalCase) the mock doesn't model are no-ops
Obj.__index = function(t, k)
  local v = rawget(Obj, k)
  if v ~= nil then return v end
  if type(k) == "string" and k:match("^%u") then return function() end end
end
function Obj:IsVisible() return self._shown ~= false and (not self._parent or self._parent:IsVisible()) end
function Obj:IsShown() return self._shown ~= false end
function Obj:Show() self._shown = true end
function Obj:Hide() self._shown = false end
function Obj:SetScript(name, fn) self["_" .. name] = fn end
function Obj:SetTexture(f) self._file = f; self._setAt = __now end
function Obj:SetTexCoord(a, b, c, d) self._tc = { a, b, c, d } end
function Obj:SetAlpha(a) self._alpha = a end
function Obj:CreateTexture() return setmetatable({ _parent = self }, Obj) end
function Obj:CreateFontString() return setmetatable({ _parent = self }, Obj) end
__drivers = {}
function CreateFrame(kind, name, parent)
  local f = setmetatable({ _parent = parent }, Obj)
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
  { name = "idle_rest", mood = "wait", file = "idle_rest", frames = 8, cols = 4, fw = 100, fh = 128, texW = 400, texH = 256, fps = 8, loop = true },
  { name = "idle_rest2", mood = "wait", file = "idle_rest2", frames = 8, cols = 4, fw = 100, fh = 128, texW = 400, texH = 256, fps = 8, loop = true },
  { name = "idle_a", mood = "wait", file = "idle_a", frames = 8, cols = 4, fw = 100, fh = 128, texW = 400, texH = 256, fps = 8, loop = true },
  { name = "idle_c", mood = "wait", file = "idle_c", frames = 8, cols = 4, fw = 100, fh = 128, texW = 400, texH = 256, fps = 8, loop = true },
  { name = "idle_d", mood = "wait", file = "idle_d", frames = 8, cols = 4, fw = 100, fh = 128, texW = 400, texH = 256, fps = 8, loop = true },
  { name = "idle_b", mood = "wait", file = "idle_b", frames = 8, cols = 4, fw = 100, fh = 128, texW = 400, texH = 256, fps = 8, loop = true },
  { name = "win_a",  mood = "win",  file = "win_a",  frames = 8, cols = 4, fw = 100, fh = 128, texW = 400, texH = 256, fps = 8 },
  { name = "win_b",  mood = "cheer", file = "win_b", frames = 8, cols = 4, fw = 100, fh = 128, texW = 400, texH = 256, fps = 8 },
  { name = "deal_a", mood = "deal", file = "deal_a", frames = 8, cols = 4, fw = 100, fh = 128, texW = 400, texH = 256, fps = 8 },
  { name = "talk_a", mood = "talk", file = "talk_a", frames = 8, cols = 4, fw = 100, fh = 128, texW = 400, texH = 256, fps = 8 },
  { name = "talk_b", mood = "talk", file = "talk_b", frames = 8, cols = 4, fw = 100, fh = 128, texW = 400, texH = 256, fps = 8 },
  { name = "talk_c", mood = "talk", file = "talk_c", frames = 8, cols = 4, fw = 100, fh = 128, texW = 400, texH = 256, fps = 8 },
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


def test_no_clips():
    """No clips shipped: she stands in her standing picture and reactions are
    ignored (the old stills never play)."""
    lua = runtime(None)
    T = lua.eval("ChairfacesCasino.Trixie")
    check(len(list(T.order.values())) == 0, "no stills in the pools")
    w, tex = lua.eval("NewWidget()")
    T.Attach(T, w, tex)
    check(w.trix.cur.name == "trixie_tall", "with no idle clips she shows her standing picture")
    w.React(w, "win")
    check(w.trix.cur.name == "trixie_tall", "a mood without clips is ignored")
    lua.execute("Step(30)")
    check(w.trix.cur.name == "trixie_tall", "and she stays put")


def test_clips():
    lua = runtime(FAKE_CLIPS)
    T = lua.eval("ChairfacesCasino.Trixie")
    check(T.HasClips(T, "wait") and T.HasClips(T, "win"), "clips land in their pools")
    check(T.byName["win_b"].mood == "win", "manifest mood aliases resolve")
    w, tex = lua.eval("NewWidget()")
    T.Attach(T, w, tex)

    # idle rotates between the idle clips and never drops to a still (a still
    # is a different pose, so she would snap)
    seen = set()
    for _ in range(120):
        lua.execute("Step(0.5)")
        seen.add(w.trix.cur.name)
    check(seen == {"idle_rest", "idle_rest2", "idle_a", "idle_b", "idle_c", "idle_d"},
          "idle plays only its clips, all of them (saw %s)" % sorted(seen))

    # no idle plays twice in a row, except her resting breath
    # (the wrapper logs every pick and still calls the real TrixieShow)
    lua.execute("__picks = {}; __lags = {}")
    lua.eval("""function(w)
      local show = w.TrixieShow
      w.TrixieShow = function(self, e, opts)
        table.insert(__picks, { e.name, opts and opts.loops or 1 })
        local r = show(self, e, opts)
        -- how long ago the now-visible texture got this sheet
        table.insert(__lags, __now - (self.trix.tex._setAt or __now))
        return r
      end
    end""")(w)
    w.Idle(w, True)
    lua.execute("Step(600)")
    picks = [(p[1], p[2]) for p in lua.eval("__picks").values()]
    names = [n for n, _ in picks]
    repeats = [names[i] for i in range(1, len(names)) if names[i] == names[i - 1] and names[i] != "idle_rest"]
    check(len(picks) > 100, "plenty of idles in 10 minutes (%d)" % len(picks))
    check(not repeats, "no idle but the breath plays twice in a row (%s)" % repeats[:3])
    check(all(loops == 1 for n, loops in picks if n != "idle_rest"), "other idles play once each")
    rest, rest2 = names.count("idle_rest"), names.count("idle_rest2")
    flavor = max(names.count(n) for n in ("idle_a", "idle_b", "idle_c", "idle_d"))
    check(rest > rest2 > flavor, "rest plays most, rest2 second, the others as flavor (%d, %d, %d)" % (rest, rest2, flavor))
    check(rest / float(len(names)) > 0.4, "rest is the bulk of her idling (%.2f)" % (rest / float(len(names))))
    lags = list(lua.eval("__lags").values())[1:]
    check(min(lags) >= 0.4, "every switch shows a sheet loaded ahead of time (min %.2f s)" % min(lags))
    check(w.trix.tex._alpha == 1 and w.trix.back._alpha == 0, "front texture shown, back one hidden")

    def until(fn, limit=3.0):
        """Step the clock in 0.05 s ticks until fn() holds (or the limit)."""
        t = 0.0
        while not fn() and t < limit:
            lua.execute("Step(0.05)")
            t += 0.05
        return fn()

    # From here every switch the player makes on its own must land on a loop
    # seam of the clip it leaves (where every clip is on her standing pose).
    lua.execute("__seams = {}")
    lua.eval("""function(w)
      local show = w.TrixieShow
      w.TrixieShow = function(self, e, opts)
        local c = self.trix.cur
        if __logSeams and c and not c.still then
          local len = c.frames / c.fps
          local r = (__now - self.trix.start) % len
          table.insert(__seams, math.min(r, len - r))
        end
        return show(self, e, opts)
      end
    end""")(w)

    # a reaction mid-clip waits for the seam, plays once, then idles
    w.Idle(w, True)
    lua.execute("Step(0.4)")
    idle_now = w.trix.cur.name
    lua.execute("__logSeams = true")
    w.React(w, "win")
    check(w.trix.cur.name == idle_now, "a reaction does not cut the idle mid-move")
    check(until(lambda: w.trix.cur.mood == "win"), "the reaction starts at the seam")
    check(w.trix.tex._file.endswith(w.trix.cur.name), "texture is the clip sheet")
    check(until(lambda: w.trix.frame > 0), "clip frames advance")
    tc = w.trix.tex._tc
    check(all(0 <= tc[i] <= 1 for i in range(1, 5)), "texcoords inside 0-1")
    check(until(lambda: w.trix.cur.mood == "wait"), "clip reaction returns to idle when done")

    # no back-to-back repeat
    last = None
    for _ in range(20):
        w.React(w, "win")
        until(lambda: w.trix.cur.mood == "win")
        name = w.trix.cur.name
        check(name != last, "React never repeats the same clip back to back")
        last = name
        until(lambda: w.trix.cur.mood == "wait")

    # repeated deal calls (one per card) don't restart a deal clip
    w.React(w, "deal")
    w.React(w, "deal")
    until(lambda: w.trix.cur.mood == "deal")
    start = w.trix.start
    w.React(w, "deal")
    check(w.trix.start == start and not w.trix.pending, "same-mood clip keeps playing on repeat calls")
    until(lambda: w.trix.cur.mood == "wait")

    # Idle() while an idle clip plays keeps it going
    lua.execute("Step(0.3)")
    start = w.trix.start
    w.Idle(w)
    check(w.trix.start == start, "Idle() does not restart a playing idle clip")

    # a mood with no clips (lose here) is ignored: she keeps idling
    before = w.trix.cur.name
    w.React(w, "lose")
    check(w.trix.cur.name == before and w.trix.mode == "idle" and not w.trix.pending,
          "a clip-less mood leaves her idling")

    # talking: starts at the seam, talk clips run for the length of the line,
    # never the same one twice in a row, then she idles; waits don't cut her
    # off, a reaction mid-line plays (at a seam) and then she carries on
    lua.execute("Step(0.4)")
    idle_now = w.trix.cur.name
    lead = w.TrixieTalkDelay(w)
    check(lead > 0.1 and lua.eval("ChairfacesCasino.Trixie:TalkLead()") == lead,
          "mid-idle, a lined-up line has to wait for the seam (%.2f s)" % lead)
    t_ask = lua.eval("__now")
    w.Talk(w, 4.5)
    check(w.trix.cur.name == idle_now, "talking does not cut the idle mid-move")
    check(until(lambda: w.trix.mode == "talk"), "talking starts at the seam")
    waited = lua.eval("__now") - t_ask
    check(abs(waited - lead) < 0.06,
          "TrixieTalkDelay predicts when talking starts (%.2f vs %.2f s)" % (lead, waited))
    check(w.TrixieTalkDelay(w) == 0, "once talking, a new line needs no wait")
    first = w.trix.cur.name
    check(until(lambda: w.trix.cur.name != first), "next talk clip comes")
    check(w.trix.cur.mood == "talk", "and it is a different talk clip")
    w.Idle(w)
    check(w.trix.cur.mood == "talk", "a game's wait call does not cut her off mid-line")
    w.React(w, "win")
    check(until(lambda: w.trix.cur.mood == "win"), "a reaction mid-line plays")
    check(until(lambda: w.trix.cur.mood != "win"), "and finishes")
    check(w.trix.cur.mood == "talk", "then she goes back to talking")
    check(until(lambda: w.trix.cur.mood == "wait", 8), "when the line is over she idles")
    lua.execute("Step(20)")
    lua.execute("__logSeams = false")
    seams = list(lua.eval("__seams").values())
    check(len(seams) > 20 and max(seams) < 0.06,
          "every switch lands on a loop seam (%d switches, worst %.3f s off)" % (len(seams), max(seams)))

    # chaining: win_a then deal_a then idle (explicit plays start at once)
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

    # the clip viewer: steps through clips, cuts stop playing at once
    T.ToggleViewer(T)
    v = T.viewer
    check(v.current is not None and not v.current.still, "viewer opens on a clip")
    first = v.current.name
    v.cutBtn._OnClick(v.cutBtn)
    check(lua.eval("ChairfacesCasinoDB.trixieRejected")[first], "Cut saves the clip in the rejected list")
    check(all(e.name != first for e in T.pools[v.current.mood].clips.values()), "a cut clip leaves its pool")
    v.cutBtn._OnClick(v.cutBtn)
    check(not lua.eval("ChairfacesCasinoDB.trixieRejected")[first], "Keep puts it back")
    v.cutBtn._OnClick(v.cutBtn)
    n = len(list(T.ViewerList(T).values()))
    v.index = n
    T.ViewerShow(T)
    check(v.current is not None, "viewer reaches the last clip")
    lua.execute("ChairfacesCasinoDB.trixieRejected = {}")
    T.BuildPools(T)

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
        check(c.mood in ("wait", "idle", "win", "cheer", "lose", "love", "deal", "shuf", "shuffle", "talk"), "known mood: " + c.name)


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
    test_no_clips()
    test_clips()
    test_manifest_files()
    test_no_hand_set_dealer_paths()
    if FAILS:
        print("%d failure(s)" % len(FAILS))
        sys.exit(1)
    print("trixie_anim_test: all passed")
