--[[
    Chairface's Casino - UI/Trixie.lua
    Trixie the dealer: one sprite player shared by every casino window.

    Every window keeps its own Button + texture and hands them to
    Trixie:Attach(frame, texture). That gives the frame:
      frame:Idle(fresh)       endless idle rotation (fresh = roll a new pose now)
      frame:React(mood, opts) a clip for the mood, then back to idle
      frame:Play(name, opts)  one named entry; frame:Queue(a, b, ...) chains them
      frame:SetRandomWait/Deal/Shuffle/Cheer/Lose/Love/WinOrLove (old names)

    Moods: wait, talk, win, lose, love, deal, shuf. Each mood plays only the
    animated clips in BJ.TrixieClips (the hand-drawn stills are a different
    pose each and would snap); a mood with no clips is ignored and she keeps
    idling. Every clip starts and ends on the same standing pose, so any clip
    can follow any other without a jump. If no idle clips shipped at all she
    stands in her standing picture (T.FALLBACK).
]]

local BJ = ChairfacesCasino

local T = {}
BJ.Trixie = T

local DIR = "Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\"

T.ALIAS = { cheer = "win", shuffle = "shuf", idle = "wait" }
-- her standing picture: shown only if no idle clips exist at all
T.FALLBACK = { name = "trixie_tall", mood = "wait", file = DIR .. "trixie_tall", frames = 1, still = true }
-- Idling is mostly rest: her plain breathing loop most of the time, the
-- same loop with a head sway and a blink second, the other idles as flavor.
T.IDLE_BASE = "idle_rest"     -- only breathing: the only idle that may repeat back to back
T.IDLE_BASE2 = "idle_rest2"   -- the same with a slight head sway and one blink
T.IDLE_BASE_LOOPS = { 1, 3 }  -- times the resting loop plays in a row
T.IDLE_WEIGHTS = { rest = 0.55, rest2 = 0.25, flavor = 0.20 }
T.PRELOAD_SECS = 0.6          -- load the next clip this long before the cut
T.REACT_RECENT = 4           -- reaction clips she won't replay until 4 others of that mood have
T.IDLE_RECENT = 8            -- other idles she won't replay until 8 others have played

-- name -> clip, mood -> { clips = {} }, and every clip in order
T.byName, T.pools, T.order = {}, {}, {}

local function addEntry(e, cut)
    T.byName[e.name] = e
    T.order[#T.order + 1] = e
    if cut then return end   -- the viewer can still show it; nothing plays it
    local pool = T.pools[e.mood]
    if not pool then
        pool = { clips = {} }
        T.pools[e.mood] = pool
    end
    table.insert(pool.clips, e)
end

-- Clips marked "cut" in the clip viewer (/cc trix): kept in the viewer, never
-- played. Saved in ChairfacesCasinoDB.trixieRejected so the tool can delete them.
function T:Rejected()
    local db = ChairfacesCasinoDB
    if type(db) ~= "table" then return {} end
    db.trixieRejected = db.trixieRejected or {}
    return db.trixieRejected
end

function T:BuildPools()
    self.byName, self.pools, self.order = {}, {}, {}
    local rejected = self:Rejected()
    for _, c in ipairs(BJ.TrixieClips or {}) do
        local mood = self.ALIAS[c.mood] or c.mood
        addEntry({
            name = c.name, mood = mood, file = DIR .. "anim\\" .. c.file,
            frames = c.frames, cols = c.cols, fw = c.fw, fh = c.fh,
            sx = c.sx, sy = c.sy, ox = c.ox, oy = c.oy,
            texW = c.texW, texH = c.texH, fps = c.fps or 12, loop = c.loop,
        }, rejected[c.name])
    end
end
T:BuildPools()

function T:HasClips(mood)
    local pool = self.pools[mood]
    return pool and #pool.clips > 0 or false
end

-- A random clip for the mood, never the one this widget showed last for it.
-- recent: names played lately, skipped too while anything else is left.
function T:Pick(mood, last, recent)
    local pool = self.pools[mood]
    local list = pool and pool.clips
    if not list or #list == 0 then return nil end
    local skip = {}
    if last then skip[last] = true end
    for _, n in ipairs(recent or {}) do skip[n] = true end
    local fresh = {}
    for _, e in ipairs(list) do
        if not skip[e.name] then fresh[#fresh + 1] = e end
    end
    if #fresh == 0 then       -- small pool: only avoid the very last one
        for _, e in ipairs(list) do
            if e.name ~= last then fresh[#fresh + 1] = e end
        end
    end
    if #fresh == 0 then fresh = list end
    return fresh[math.random(1, #fresh)]
end

-- The texcoords of one clip frame. Cells are sx x sy apart (a 4-pixel grid,
-- for DXT) with the fw x fh picture ox, oy into each.
function T:FrameCoords(e, idx)
    local col = idx % e.cols
    local row = math.floor(idx / e.cols)
    local x = col * (e.sx or e.fw) + (e.ox or 0)
    local y = row * (e.sy or e.fh) + (e.oy or 0)
    return x / e.texW, (x + e.fw) / e.texW, y / e.texH, (y + e.fh) / e.texH
end

------------------------------------------------------------------------
-- Driver: one OnUpdate steps every visible widget that is mid-clip or
-- waiting out a hold. Hidden widgets don't advance; when one shows again
-- the clock catches it up (a finished clip just moves on).
------------------------------------------------------------------------
T.widgets = {}

local driver
local function tick()
    local now = GetTime()
    for _, w in ipairs(T.widgets) do
        local s = w.trix
        if s.cur and w:IsVisible() then
            local e = s.cur
            if not e.still then
                local idx = math.floor((now - s.start) * e.fps)
                if s.untilT and now >= s.untilT then idx = e.frames - 1 end
                idx = idx % e.frames
                if idx ~= s.frame then
                    s.frame = idx
                    s.tex:SetTexCoord(T:FrameCoords(e, idx))
                end
            end
            -- just before the cut, decide what comes next and load its sheet
            -- into the hidden texture, so the switch has no blank frame
            if s.untilT and not s.plan and s.untilT - now <= T.PRELOAD_SECS then
                w:TrixiePlan()
            end
            if s.untilT and now >= s.untilT then
                s.untilT = nil
                w:TrixieNext()
            end
        end
    end
end

local function wake()
    if driver then return end
    driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", tick)
end
T.Tick = tick

------------------------------------------------------------------------
-- Widget methods (mixed into each attached frame)
------------------------------------------------------------------------
local W = {}

-- Draw an entry. opts.hold = seconds a still stays (nil = until told);
-- opts.loops = times a clip plays (math.huge = forever).
function W:TrixieShow(e, opts)
    opts = opts or {}
    local s = self.trix
    local now = GetTime()
    s.cur, s.start, s.frame, s.plan, s.pending = e, now, 0, nil, nil
    s.last[e.mood] = e.name
    if s.back.trixFile == e.file then
        -- already loaded behind her: swap the two textures in the same frame
        s.back:SetAlpha(1)
        s.tex:SetAlpha(0)
        s.tex, s.back = s.back, s.tex
    elseif s.tex.trixFile ~= e.file then
        s.tex:SetTexture(e.file)
        s.tex.trixFile = e.file
    end
    if e.still then
        s.tex:SetTexCoord(0, 1, 0, 1)
        s.untilT = opts.hold and (now + opts.hold) or nil
    else
        s.tex:SetTexCoord(T:FrameCoords(e, 0))
        local loops = opts.loops or 1
        s.untilT = loops ~= math.huge and (now + e.frames * loops / e.fps) or nil
    end
    if BJ.TestMode and BJ.TestMode.enabled and BJ.TestMode.trixieDebugActive and self.debugLabel then
        self.debugLabel:SetText(e.name)
        self.debugLabel:Show()
    end
end

-- The current entry is done: next queued entry, else back to idle.
function W:TrixieNext()
    local s = self.trix
    local plan = s.plan
    s.plan = nil
    local p = s.pending
    if p then
        s.pending = nil
        s.mode, s.held = p.mode, p.held
        self:TrixieShow(p.e)
        return
    end
    local nextE = table.remove(s.queue, 1)
    if nextE then
        s.mode = "chain"
        self:TrixieShow(nextE)
    elseif self:TrixieTalking() then
        self:TrixieTalkNext(plan and plan.kind == "talk" and plan or nil)
    elseif s.cur and s.cur.still and s.mode ~= "idle" and not s.held then
        -- a still reaction with no hold stays until the game says otherwise
    else
        self:Idle(true, plan and plan.kind == "idle" and plan or nil)
    end
end

-- Pick what TrixieNext is about to play (same branches) and load it into
-- the hidden texture. Anything shown in the meantime drops the plan.
function W:TrixiePlan()
    local s = self.trix
    local kind, e, opts
    if s.pending then
        kind, e = "pending", s.pending.e
    elseif s.queue[1] then
        kind, e = "queue", s.queue[1]
    elseif s.talkUntil and s.untilT and s.untilT < s.talkUntil and T:HasClips("talk") then
        kind = "talk"
        e, opts = self:TrixiePickTalk()
    elseif s.cur and s.cur.still and s.mode ~= "idle" and not s.held then
        return
    else
        kind = "idle"
        e, opts = self:TrixiePickIdle()
    end
    if not e then return end
    s.plan = { kind = kind, e = e, opts = opts }
    if s.back.trixFile ~= e.file and s.tex.trixFile ~= e.file then
        s.back:SetTexture(e.file)
        s.back.trixFile = e.file
    end
end

-- Talking: while one of her voice lines plays she runs talk clips, a
-- different one each time, then goes back to idling. A reaction that is
-- already playing finishes first; one that starts mid-line plays, and then
-- she carries on talking.
function W:TrixieTalking()
    local s = self.trix
    return s.talkUntil ~= nil and GetTime() < s.talkUntil and T:HasClips("talk")
end

function W:TrixiePickTalk()
    local s = self.trix
    s.recentMood = s.recentMood or {}
    local recent = s.recentMood.talk or {}
    s.recentMood.talk = recent
    local e = T:Pick("talk", s.last.talk, recent)
    if not e then return nil end
    table.insert(recent, e.name)
    while #recent > math.min(T.REACT_RECENT, #T.pools.talk.clips - 1) do table.remove(recent, 1) end
    return e, { loops = 1 }
end

function W:TrixieTalkNext(plan)
    local s = self.trix
    local e, opts
    if plan then e, opts = plan.e, plan.opts else e, opts = self:TrixiePickTalk() end
    if not e then return end
    wipe(s.queue)
    s.mode, s.held = "talk", nil
    self:TrixieShow(e, opts)
end

function W:Talk(seconds)
    if not T:HasClips("talk") then return end
    local s = self.trix
    s.talkUntil = GetTime() + (seconds or 3)
    if s.mode == "talk" then return end
    if s.mode == "react" and s.cur and not s.cur.still and s.untilT then return end
    -- mid-clip: start talking where this loop comes back to her standing pose
    if self:TrixieCutAtSeam() then return end
    self:TrixieTalkNext()
end

-- Seconds until Talk() called now would have her on a talk clip: the wait
-- for this clip's seam (a reaction plays out in full), plus anything already
-- lined up behind it. Same branches as Talk().
function W:TrixieTalkDelay()
    if not T:HasClips("talk") then return 0 end
    local s = self.trix
    local e = s.cur
    if s.mode == "talk" or not e or e.still then return 0 end
    local now = GetTime()
    local wait
    if s.mode == "react" and s.untilT then
        wait = s.untilT - now
    else
        local loopLen = e.frames / e.fps
        local played = now - s.start
        if played < 1 / e.fps then return 0 end
        local seam = s.start + math.ceil(played / loopLen) * loopLen
        wait = math.min(seam, s.untilT or seam) - now
    end
    local p = s.pending and s.pending.e
    if p and not p.still then wait = wait + p.frames / p.fps end
    for _, q in ipairs(s.queue) do
        if not q.still then wait = wait + q.frames / q.fps end
    end
    return math.max(0, wait)
end

-- A clip is playing: make it end at its next loop seam (where every clip is
-- back on her standing pose) instead of cutting away mid-move. Returns true
-- if the switch now waits for that seam; false if it can happen right away.
function W:TrixieCutAtSeam()
    local s = self.trix
    local e = s.cur
    if not e or e.still then return false end
    local now = GetTime()
    local loopLen = e.frames / e.fps
    local played = now - s.start
    if played < 1 / e.fps then return false end   -- still on the first frame: switch now
    local seam = s.start + math.ceil(played / loopLen) * loopLen
    if s.untilT and s.untilT <= seam then return true end   -- it ends sooner anyway
    s.untilT = seam
    s.plan = nil
    return true
end

function W:Idle(fresh, plan)
    local s = self.trix
    -- mid-line: the talk clips run until her voice stops
    if self:TrixieTalking() then return end
    -- already idling on a clip: let it play out rather than jump
    if not fresh and s.mode == "idle" and s.cur and not s.cur.still then return end
    wipe(s.queue)
    s.mode, s.held = "idle", nil
    local e, opts
    if plan then e, opts = plan.e, plan.opts else e, opts = self:TrixiePickIdle() end
    if e then self:TrixieShow(e, opts) end
end

-- Once idle clips exist she idles on clips only: they all start and end on
-- her standing pose, so one flows into the next, while a still would snap.
-- Every idle is a one-off except her resting breath: that one may run a
-- few times in a row, and she drops back into it between the others.
function W:TrixiePickIdle()
    local s = self.trix
    s.recent = s.recent or {}
    if not T:HasClips("wait") then
        return T.FALLBACK, nil        -- no idle clips shipped: her standing picture
    end
    local base, base2 = T.byName[T.IDLE_BASE], T.byName[T.IDLE_BASE2]
    local pool = T.pools.wait.clips
    local inPool = {}
    for _, e in ipairs(pool) do inPool[e] = true end
    if not inPool[base] then base = nil end      -- cut in the viewer
    if not inPool[base2] then base2 = nil end
    local last = s.last.wait
    -- the rest loops never follow themselves (rest repeats inside its own
    -- pick instead); flavor only if there is any
    local wt = T.IDLE_WEIGHTS
    local choices = {}
    if base and last ~= base.name then choices[#choices + 1] = { "rest", wt.rest } end
    if base2 and last ~= base2.name then choices[#choices + 1] = { "rest2", wt.rest2 } end
    if #pool > (base and 1 or 0) + (base2 and 1 or 0) then choices[#choices + 1] = { "flavor", wt.flavor } end
    local total = 0
    for _, c in ipairs(choices) do total = total + c[2] end
    local r, kind = math.random() * total, nil
    for _, c in ipairs(choices) do
        if r < c[2] then kind = c[1] break end
        r = r - c[2]
    end
    kind = kind or (choices[1] and choices[1][1])
    local e
    if kind == "rest" then
        return base, { loops = math.random(T.IDLE_BASE_LOOPS[1], T.IDLE_BASE_LOOPS[2]) }
    elseif kind == "rest2" then
        return base2, { loops = 1 }
    end
    local skip = { unpack(s.recent) }
    if base then skip[#skip + 1] = base.name end
    if base2 then skip[#skip + 1] = base2.name end
    e = T:Pick("wait", last, skip)
    if not e then return base or base2, { loops = 1 } end
    table.insert(s.recent, e.name)
    while #s.recent > T.IDLE_RECENT do table.remove(s.recent, 1) end
    return e, { loops = 1 }
end

function W:React(mood, opts)
    mood = T.ALIAS[mood] or mood
    if mood == "wait" then return self:Idle() end
    local s = self.trix
    -- the same mood's clip is already playing (deals fire per card): keep it going
    if s.cur and s.cur.mood == mood and not s.cur.still and s.untilT then return end
    if s.pending and s.pending.e.mood == mood then return end
    -- same rules as idling: clips only (a mood without any, like dealing for
    -- now, is ignored and she keeps idling), and none of the last few again
    if not T:HasClips(mood) then return end
    s.recentMood = s.recentMood or {}
    local recent = s.recentMood[mood] or {}
    s.recentMood[mood] = recent
    local e = T:Pick(mood, s.last[mood], recent)
    if not e then return end
    table.insert(recent, e.name)
    local pool = T.pools[mood]
    local keep = math.min(T.REACT_RECENT, math.max(0, #pool.clips - 1))
    while #recent > keep do table.remove(recent, 1) end
    wipe(s.queue)
    local held = opts and opts.hold and true or nil
    -- mid-clip: the reaction starts at the seam, so she never snaps
    if self:TrixieCutAtSeam() then
        s.pending = { e = e, mode = "react", held = held }
        s.plan = nil
        return
    end
    s.mode, s.held = "react", held
    self:TrixieShow(e)
end

-- Play entries by name, one after another, then idle.
function W:Queue(...)
    local s = self.trix
    wipe(s.queue)
    for i = 1, select("#", ...) do
        local e = T.byName[select(i, ...)]
        if e then s.queue[#s.queue + 1] = e end
    end
    s.held = true
    self:TrixieNext()
end

function W:Play(name, opts)
    local e = T.byName[name]
    if not e then return end
    wipe(self.trix.queue)
    self.trix.mode, self.trix.held = "chain", true
    self:TrixieShow(e, opts)
end

-- A named clip (old still names like "wait5" no longer play).
function W:SetState(state)
    local e = T.byName[state]
    if not e then return end
    self.trix.mode, self.trix.held = (e.mood == "wait") and "idle" or "react", nil
    wipe(self.trix.queue)
    self:TrixieShow(e)
end

function W:SetRandomWait() self:Idle() end
function W:SetRandomDeal() self:React("deal") end
function W:SetRandomShuffle() self:React("shuf") end
function W:SetRandomCheer() self:React("win") end
function W:SetRandomLose() self:React("lose") end
function W:SetRandomLove() self:React("love") end
-- big wins: one time in ten she blows a kiss instead of cheering
function W:SetRandomWinOrLove()
    if math.random(1, 10) == 1 then self:React("love") else self:React("win") end
end

-- Hand Trixie a frame and its texture. She starts idling straight away.
-- A second texture sits behind it, invisible, to load the next clip into.
function T:Attach(frame, texture)
    if not self.svApplied then   -- saved variables are in by now: drop cut clips
        self.svApplied = true
        self:BuildPools()
    end
    frame.texture = frame.texture or texture
    local back = frame:CreateTexture(nil, "ARTWORK")
    back:SetAllPoints(texture)
    back:SetAlpha(0)
    texture:SetAlpha(1)
    frame.trix = { tex = texture, back = back, queue = {}, last = {}, frame = 0 }
    for k, fn in pairs(W) do frame[k] = fn end
    table.insert(self.widgets, frame)
    wake()
    frame:Idle(true)
    return frame
end

-- Her voice started (Lobby:PlayTrixieClip): every Trixie on screen talks.
function T:TalkEverywhere(seconds)
    for _, w in ipairs(self.widgets) do
        if w:IsVisible() and not w.trixViewer then w:Talk(seconds) end
    end
end

-- How long until every Trixie on screen can be talking: the longest of their
-- waits for a seam. A line that can wait starts after this, so her mouth
-- moves with the first word instead of catching up mid-line.
function T:TalkLead()
    local lead = 0
    for _, w in ipairs(self.widgets) do
        if w:IsVisible() and not w.trixViewer then lead = math.max(lead, w:TrixieTalkDelay()) end
    end
    return lead
end

-- A lined-up line didn't play after all: stop the talk it started.
function T:StopTalkEverywhere()
    for _, w in ipairs(self.widgets) do w.trix.talkUntil = nil end
end

------------------------------------------------------------------------
-- Clip viewer (/cc trix, test-mode names only): step through every clip,
-- loop it, and mark the ones to cut. Cut clips stop playing at once and are
-- saved in ChairfacesCasinoDB.trixieRejected; tools/gen_trixie_anims.py
-- --drop-rejected deletes them for good. "Live" lets her idle on her own
-- here, to watch the joins between clips.
------------------------------------------------------------------------
local VIEW_MOODS = { "all", "wait", "talk", "win", "love", "lose", "deal", "shuf" }

function T:ViewerList()
    local v = self.viewer
    local list = {}
    for _, e in ipairs(self.order) do
        if not e.still and (v.mood == "all" or e.mood == v.mood) then list[#list + 1] = e end
    end
    return list
end

function T:ViewerShow()
    local v = self.viewer
    local list = self:ViewerList()
    if #list == 0 then
        v.info:SetText("no clips")
        return
    end
    v.index = math.max(1, math.min(v.index, #list))
    local e = list[v.index]
    v.current = e
    local cut = self:Rejected()[e.name]
    v.live = false
    v.liveBtn:SetText("Live")
    v.trixie:Play(e.name, { loops = math.huge })
    v.info:SetText(string.format("%s%s|r   %s   %d / %d",
        cut and "|cffff5555" or "|cffffffff", e.name, e.mood, v.index, #list))
    v.cutBtn:SetText(cut and "Keep" or "Cut")
    local n = 0
    for _ in pairs(self:Rejected()) do n = n + 1 end
    v.cutCount:SetText(n > 0 and ("|cffff8888" .. n .. " cut|r") or "")
end

function T:ToggleViewer()
    if self.viewer then
        if self.viewer.frame:IsShown() then self.viewer.frame:Hide() else
            self.viewer.frame:Show()
            self:ViewerShow()
        end
        return
    end
    local v = { index = 1, mood = "all" }
    self.viewer = v
    local f = CreateFrame("Frame", "ChairfacesTrixieViewer", UIParent, "BackdropTemplate")
    v.frame = f
    f:SetSize(310, 470)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    f:SetBackdropColor(0.06, 0.05, 0.08, 0.97)
    f:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    tinsert(UISpecialFrames, "ChairfacesTrixieViewer")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -8)
    title:SetText("Trixie's clips")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local holder = CreateFrame("Button", nil, f)
    holder:SetSize(274, 350)
    holder:SetPoint("TOP", 0, -26)
    local tex = holder:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    holder.trixViewer = true
    v.trixie = self:Attach(holder, tex)

    v.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    v.info:SetPoint("TOP", holder, "BOTTOM", 0, -6)

    local function button(text, w, point, x, y, onClick)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetPoint(point, f, point, x, y)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        return b
    end
    button("< Prev", 64, "BOTTOMLEFT", 10, 36, function()
        v.index = v.index - 1
        if v.index < 1 then v.index = #T:ViewerList() end
        T:ViewerShow()
    end)
    button("Next >", 64, "BOTTOMRIGHT", -10, 36, function()
        v.index = v.index % math.max(1, #T:ViewerList()) + 1
        T:ViewerShow()
    end)
    v.cutBtn = button("Cut", 64, "BOTTOM", 0, 36, function()
        local e = v.current
        if not e then return end
        local rejected = T:Rejected()
        rejected[e.name] = (not rejected[e.name]) or nil
        T:BuildPools()
        T:ViewerShow()
    end)
    v.moodBtn = button("Mood: all", 96, "BOTTOMLEFT", 10, 10, function(self)
        local i = 1
        for k, m in ipairs(VIEW_MOODS) do if m == v.mood then i = k end end
        v.mood = VIEW_MOODS[i % #VIEW_MOODS + 1]
        self:SetText("Mood: " .. v.mood)
        v.index = 1
        T:ViewerShow()
    end)
    v.liveBtn = button("Live", 64, "BOTTOM", 0, 10, function(self)
        v.live = not v.live
        self:SetText(v.live and "Stop" or "Live")
        if v.live then
            v.info:SetText("|cff88ff88live: idling on her own|r")
            v.trixie:Idle(true)
        else
            T:ViewerShow()
        end
    end)
    v.cutCount = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    v.cutCount:SetPoint("BOTTOMRIGHT", -14, 15)

    self:ViewerShow()
end

-- Debug browser (test mode): every clip in order.
function T:Entries() return self.order end

function T:ShowEverywhere(name)
    local e = self.byName[name]
    if not e then return end
    for _, w in ipairs(self.widgets) do
        if w:IsVisible() and not w.trixViewer then
            wipe(w.trix.queue)
            w.trix.mode, w.trix.held = "debug", true
            w:TrixieShow(e, { loops = math.huge })
        end
    end
end
