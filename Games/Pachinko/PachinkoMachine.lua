--[[
    Chairface's Casino - Games/Pachinko/PachinkoMachine.lua
    The Pachinko Parlor's machines: real pachinko, as on a Japanese floor.
    Balls are bought with the arcade's fake credits (RATE credits each),
    fired one after another up into a board of pins by a handle whose
    strength the player sets, and drop. Most drain. Some fall into the
    start pocket, which pays a few balls back and spins the three-digit
    "digital". Three of a kind is a jackpot: the attacker below opens for
    a number of rounds and every ball that drops in pays. Odd-number
    jackpots leave the machine in KAKUHEN (the jackpot odds shortened
    until the next hit); even ones in JITAN (the start pocket's tulip
    held open for a while). Four spins can queue (holds) while one runs.

    Pure logic, no frame API. UI/PachinkoParlor.lua draws it and owns the
    credits through the wallet it passes to Step. tests/pachinko_test.py
    drives it headless and measures each machine's payback.

    Field pixels, origin top-left, y grows DOWNWARD.
]]

local BJ = ChairfacesCasino
BJ.Arcade = BJ.Arcade or {}
local Arcade = BJ.Arcade
Arcade.Pachinko = Arcade.Pachinko or {}
local PK = Arcade.Pachinko

PK.FIELD_W, PK.FIELD_H = 440, 600
PK.BALL_R   = 5.5
PK.PIN_R    = 2.2
PK.WIND_R   = 6
PK.GRAVITY  = 900
PK.STEP     = 1 / 120
PK.RESTITUTION = 0.45
PK.PIN_RESTITUTION = 0.45
PK.LAUNCH_INTERVAL = 0.6        -- 100 balls a minute, like the real handle
PK.HOLD_MAX = 4
PK.SPIN_SECS = 1.7              -- a spin in NORMAL
PK.SPIN_SECS_FAST = 0.55        -- a spin in KAKUHEN / JITAN
PK.REACH_EXTRA = 1.6            -- a reach stretches the spin
PK.REACH_CHANCE = 0.12          -- misses that still show a reach
PK.ROUND_GAP = 0.8              -- attacker closed between rounds
PK.CELL = 24                    -- pin grid cell

-- Display box the reels live in (balls roll off its roof)
PK.BOX = { l = PK.FIELD_W / 2 - 92, r = PK.FIELD_W / 2 + 92, t = 125, b = 318 }

PK.RATES = { 1, 5, 10, 25, 100 }   -- credits a ball

local W, H = PK.FIELD_W, PK.FIELD_H
local sin, cos, sqrt, floor, abs = math.sin, math.cos, math.sqrt, math.floor, math.abs

-- ---------------------------------------------------------------------
-- The six machines. Odds are 1 in `odds`; a jackpot has `rounds` of
-- `count` balls into the attacker at `attackerPay` each. `kakuhenRate`
-- of jackpots are the odd (kakuhen) kind; `st` limits kakuhen to that
-- many spins (nil loops until the next jackpot); `jitan` spins follow an
-- even jackpot. `gate` is the gap between the two guard pins over the
-- start pocket: wider is kinder.

PK.MACHINES = {
    {
        id = "vashjir", title = "Tales of Vashj'ir", tagline = "LIGHT TYPE - 1/99 - EASY HITS, SMALL PAYS",
        blurb = "The friendly fish machine. Jackpots come often and pay little.",
        odds = 99, kakuhenOdds = 12, kakuhenRate = 0.50, st = 50, jitan = 50,
        rounds = { { 5, 0.4 }, { 2, 0.6 } }, count = 10, attackerPay = 10,
        startPay = 2, sidePay = 1, gate = 9, heso = 9, seed = 1101,
        theme = { bg = { 0.03, 0.12, 0.2 }, bg2 = { 0.05, 0.25, 0.35 }, border = { 0.3, 0.7, 0.9 },
                  title = { 0.6, 0.95, 1 }, accent = { 0.4, 0.85, 1 } },
    },
    {
        id = "felreaver", title = "Fel Reaver Genesis", tagline = "MAX TYPE - 1/319 - 65% KAKUHEN LOOP",
        blurb = "The classic rush machine: rare hits, then a loop of them.",
        odds = 319, kakuhenOdds = 40, kakuhenRate = 0.65, st = nil, jitan = 100,
        rounds = { { 16, 0.45 }, { 8, 0.55 } }, count = 10, attackerPay = 6,
        startPay = 3, sidePay = 1, gate = 8.5, heso = 9, seed = 2202,
        theme = { bg = { 0.12, 0.03, 0.14 }, bg2 = { 0.3, 0.05, 0.3 }, border = { 0.7, 0.3, 0.9 },
                  title = { 0.9, 0.6, 1 }, accent = { 0.6, 1, 0.5 } },
    },
    {
        id = "northrend", title = "Fist of the Northrend Star", tagline = "BATTLE SPEC - 1/319 - 80% CONTINUE",
        blurb = "Win the fight and the jackpots keep coming. Lose it and you are back in the cold.",
        odds = 319, kakuhenOdds = 36, kakuhenRate = 0.80, st = nil, jitan = 100,
        rounds = { { 8, 0.2 }, { 2, 0.8 } }, count = 10, attackerPay = 8,
        startPay = 3, sidePay = 1, gate = 8.5, heso = 9, seed = 3303,
        theme = { bg = { 0.08, 0.08, 0.14 }, bg2 = { 0.15, 0.18, 0.3 }, border = { 0.6, 0.7, 0.9 },
                  title = { 0.85, 0.9, 1 }, accent = { 1, 0.8, 0.3 } },
    },
    {
        id = "ravenholdt", title = "Ravenholdt the Third", tagline = "MIDDLE TYPE - 1/199 - 60% KAKUHEN",
        blurb = "The rogue's machine: a heist every couple of hundred spins.",
        odds = 199, kakuhenOdds = 25, kakuhenRate = 0.60, st = nil, jitan = 100,
        rounds = { { 8, 0.3 }, { 3, 0.7 } }, count = 10, attackerPay = 8,
        startPay = 3, sidePay = 1, gate = 8.5, heso = 9, seed = 4404,
        theme = { bg = { 0.1, 0.06, 0.03 }, bg2 = { 0.25, 0.14, 0.05 }, border = { 0.9, 0.6, 0.3 },
                  title = { 1, 0.85, 0.5 }, accent = { 1, 0.5, 0.3 } },
    },
    {
        id = "hunt", title = "Beast Master's Hunt", tagline = "ST TYPE - 1/199 - 100 SPINS OF KAKUHEN",
        blurb = "Every jackpot is a hunt: 100 shortened spins to bag the next one.",
        odds = 199, kakuhenOdds = 30, kakuhenRate = 1.0, st = 100, jitan = 0,
        rounds = { { 8, 0.2 }, { 2, 0.8 } }, count = 10, attackerPay = 6,
        startPay = 2, sidePay = 1, gate = 8.5, heso = 9, seed = 5505,
        theme = { bg = { 0.04, 0.1, 0.04 }, bg2 = { 0.08, 0.22, 0.08 }, border = { 0.4, 0.8, 0.3 },
                  title = { 0.8, 1, 0.6 }, accent = { 1, 0.9, 0.4 } },
    },
    {
        id = "scourge", title = "Scourge Hazard", tagline = "MAX TYPE - 1/319 - 16R OUTBREAKS",
        blurb = "The plague machine. Long dry spells, big outbreaks.",
        odds = 319, kakuhenOdds = 45, kakuhenRate = 0.70, st = nil, jitan = 100,
        rounds = { { 16, 0.25 }, { 2, 0.75 } }, count = 10, attackerPay = 10,
        startPay = 3, sidePay = 1, gate = 8.5, heso = 9, seed = 6606,
        theme = { bg = { 0.06, 0.1, 0.06 }, bg2 = { 0.1, 0.2, 0.12 }, border = { 0.5, 0.9, 0.5 },
                  title = { 0.7, 1, 0.7 }, accent = { 0.9, 0.5, 1 } },
    },
}

function PK:GetMachine(id)
    for _, m in ipairs(self.MACHINES) do if m.id == id then return m end end
    return nil
end

-- ---------------------------------------------------------------------
-- Seeded RNG (Park-Miller, warmed up)
local function newRng(seed)
    local s = floor(seed or 1) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    local function rng(lo, hi)
        s = (s * 48271) % 2147483647
        local r = (s - 1) / 2147483646
        if lo then return lo + floor(r * (hi - lo + 1)) end
        return r
    end
    for _ = 1, 8 do rng() end
    return rng
end
PK.NewRng = newRng

-- ---------------------------------------------------------------------
-- The board: pins, pockets, the attacker, laid out from the machine seed.

local function buildBoard(m)
    local rng = newRng(m.seed)
    local pins = {}
    local minGap = 15
    local function add(x, y, opts)
        if x < 12 or x > W - 12 or y < 30 or y > H - 40 then return false end
        local box = PK.BOX
        if not (opts and opts.roof) and x > box.l - 8 and x < box.r + 8 and y > box.t - 8 and y < box.b + 8 then return false end
        local gap = (opts and opts.gap) or minGap
        for _, p in ipairs(pins) do
            local dx, dy = p.x - x, p.y - y
            if dx * dx + dy * dy < gap * gap then return false end
        end
        local pin = { x = x, y = y }
        if opts then for k, v in pairs(opts) do pin[k] = v end end
        pins[#pins + 1] = pin
        return true
    end
    local function hexBand(x0, x1, y0, y1, spacing, holes)
        local rowH = spacing * 0.866
        local r = 0
        local y = y0
        while y <= y1 do
            local offset = (r % 2) * spacing / 2
            local x = x0 + offset
            while x <= x1 do
                if rng() > (holes or 0) then add(x + (rng() - 0.5) * 3, y + (rng() - 0.5) * 2) end
                x = x + spacing
            end
            y = y + rowH
            r = r + 1
        end
    end
    -- opts.holes: how many pins along the line to leave out (never the
    -- ends), chosen from the seed; a rolling ball can drop through a hole
    local rails = {}
    -- A smooth rail from (x0,y0) to (x1,y1), broken by `holes` gaps a ball
    -- can drop through. The UI draws it as a row of pins.
    local function rail(x0, y0, x1, y1, holes)
        local len = sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
        -- holes spread evenly along the rail, each jittered by the seed
        local cuts = {}
        local n = holes or 0
        for k = 1, n do
            local slot = 0.8 / n
            cuts[k] = 0.1 + slot * (k - 0.5) + (rng() - 0.5) * slot * 0.5
        end
        local gapF = 17 / len
        local f0 = 0
        for _, c in ipairs(cuts) do
            rails[#rails + 1] = { x0 = x0 + (x1 - x0) * f0, y0 = y0 + (y1 - y0) * f0,
                                  x1 = x0 + (x1 - x0) * (c - gapF / 2), y1 = y0 + (y1 - y0) * (c - gapF / 2) }
            f0 = c + gapF / 2
        end
        rails[#rails + 1] = { x0 = x0 + (x1 - x0) * f0, y0 = y0 + (y1 - y0) * f0, x1 = x1, y1 = y1 }
    end
    local function line(x0, y0, x1, y1, spacing, opts)
        local len = sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
        local n = floor(len / spacing)
        local skip = {}
        if opts and opts.holes and n > 4 then
            local made = 0
            while made < opts.holes do
                local k = rng(2, n - 2)
                if not skip[k] and not skip[k - 1] and not skip[k + 1] then skip[k] = true; made = made + 1 end
            end
        end
        for k = 0, n do
            if not skip[k] then
                local f = (n == 0) and 0 or k / n
                add(x0 + (x1 - x0) * f, y0 + (y1 - y0) * f, opts)
            end
        end
    end

    local box = PK.BOX
    local cx = W / 2

    -- Rails first (they must be continuous), bands fill in around them.

    -- roof over the display: a peak from corner to corner, so a ball
    -- lands on it and rolls off either side
    rail(cx, box.t - 28, box.l - 2, box.t - 1)
    rail(cx, box.t - 28, box.r + 2, box.t - 1)

    -- the big V under the display: everything rolls toward the start gate,
    -- except what drops through the holes (where most balls are lost)
    local vTop, vBot = box.b + 24, 440
    rail(16, vTop, cx - 26, vBot, m.vHoles or 7)
    rail(W - 16, vTop, cx + 26, vBot, m.vHoles or 7)

    -- the guard pins over the start pocket (the gate)
    add(cx - m.gate, 455)
    add(cx + m.gate, 455)

    -- the lower V: whatever falls past the gate funnels into the attacker
    local aTop, aBot = 494, 548
    rail(16, aTop, cx - 58, aBot)
    rail(W - 16, aTop, cx + 58, aBot)

    -- side pockets at the top of the lower V, with their own guards
    for _, px in ipairs({ 42, W - 42 }) do
        add(px - 8, 468)
        add(px + 8, 468)
    end

    -- windmills (spinning pins) at the head of each road
    add(box.l - 32, box.t + 60, { wind = true })
    add(box.r + 32, box.t + 60, { wind = true })

    -- top band: the ball lands here and scatters
    hexBand(22, W - 22, 44, 94, 21, 0.12)

    -- side roads either side of the display
    hexBand(18, box.l - 14, box.t + 2, box.b, 23, 0.22)
    hexBand(box.r + 14, W - 18, box.t + 2, box.b, 23, 0.22)

    -- a loose scatter just below the display so balls hop onto the V
    hexBand(box.l + 10, box.r - 10, box.b + 12, box.b + 40, 30, 0.4)


    -- pin grid
    local grid = {}
    for i, p in ipairs(pins) do
        local gx, gy = floor(p.x / PK.CELL), floor(p.y / PK.CELL)
        local key = gx + gy * 1000
        grid[key] = grid[key] or {}
        grid[key][#grid[key] + 1] = i
    end

    return {
        pins = pins,
        rails = rails,
        grid = grid,
        start = { x = cx, y = 472, w = m.heso or 13, wOpen = 30 },
        attacker = { x = cx, y = 556, w = 114 },
        sides = { { x = 42, y = 484, w = 11 }, { x = W - 42, y = 484, w = 11 } },
    }
end

-- ---------------------------------------------------------------------
-- Machine state

function PK:NewMachineState(m, seed)
    local board = buildBoard(m)
    return {
        m = m,
        board = board,
        rng = newRng(seed or (m.seed * 31 + 7)),
        balls = {},
        firing = false,
        handle = 0.62,
        launchAcc = 0,
        time = 0,
        acc = 0,
        -- lottery
        mode = "normal",           -- normal | kakuhen | jitan
        modeSpins = 0,
        holds = {},
        spin = nil,                -- { t, dur, result, reach }
        jackpot = nil,             -- { rounds, round, count, kind, open, gap, paid }
        reels = { 7, 7, 7 },
        -- session tallies
        launched = 0,
        paidBalls = 0,
        starts = 0,
        spins = 0,
        jackpots = 0,
        bestJackpot = 0,
        windmills = {},
    }
end

function PK:SetHandle(st, strength)
    if strength < 0 then strength = 0 elseif strength > 1 then strength = 1 end
    st.handle = strength
end

function PK:SetFiring(st, on)
    st.firing = on and true or false
    if on then st.launchAcc = PK.LAUNCH_INTERVAL end
end

function PK:StartPocketWidth(st)
    if st.mode == "normal" then return st.board.start.w end
    return st.board.start.wOpen
end

function PK:CurrentOdds(st)
    if st.mode == "kakuhen" then return st.m.kakuhenOdds end
    return st.m.odds
end

-- ---------------------------------------------------------------------
-- Lottery

local function push(events, ev)
    if events then events[#events + 1] = ev end
end

local function rollRounds(st)
    local total = 0
    for _, r in ipairs(st.m.rounds) do total = total + r[2] end
    local pick = st.rng() * total
    for _, r in ipairs(st.m.rounds) do
        pick = pick - r[2]
        if pick <= 0 then return r[1] end
    end
    return st.m.rounds[#st.m.rounds][1]
end

-- Decide a spin the moment the ball drops in, as the real machine does.
local function drawSpin(st)
    local rng = st.rng
    local hit = rng() < 1 / PK:CurrentOdds(st)
    local res = { hit = hit }
    if hit then
        res.kakuhen = rng() < st.m.kakuhenRate
        res.rounds = rollRounds(st)
        local n
        if res.kakuhen then n = ({ 1, 3, 5, 7, 9 })[rng(1, 5)] else n = ({ 2, 4, 6, 8 })[rng(1, 4)] end
        res.reels = { n, n, n }
        res.reach = true
    else
        local a, b, c = rng(1, 9), rng(1, 9), rng(1, 9)
        res.reach = rng() < PK.REACH_CHANCE
        if res.reach then
            c = a
            if b == a then b = (a % 9) + 1 end
        elseif a == c and b == a then
            b = (a % 9) + 1
        end
        res.reels = { a, b, c }
    end
    return res
end

local function beginJackpot(st, res, events)
    st.jackpot = { rounds = res.rounds, round = 1, count = 0, kind = res.kakuhen and "kakuhen" or "normal",
                   open = true, gap = 0, paid = 0 }
    st.jackpots = st.jackpots + 1
    push(events, { type = "jackpot_start", rounds = res.rounds, kind = st.jackpot.kind })
end

local function endJackpot(st, events)
    local jp = st.jackpot
    st.jackpot = nil
    if jp.paid > st.bestJackpot then st.bestJackpot = jp.paid end
    local before = st.mode
    if jp.kind == "kakuhen" or st.m.kakuhenRate >= 1 then
        st.mode = "kakuhen"
        st.modeSpins = st.m.st or 0        -- 0 = until the next jackpot
    elseif (st.m.jitan or 0) > 0 then
        st.mode = "jitan"
        st.modeSpins = st.m.jitan
    else
        st.mode = "normal"
        st.modeSpins = 0
    end
    push(events, { type = "jackpot_end", paid = jp.paid, mode = st.mode, spins = st.modeSpins })
    if st.mode ~= before then push(events, { type = "mode", mode = st.mode, spins = st.modeSpins }) end
end

local function finishSpin(st, events)
    local res = st.spin.result
    st.spin = nil
    st.spins = st.spins + 1
    st.reels = res.reels
    push(events, { type = "spin_end", hit = res.hit, reels = res.reels, kakuhen = res.kakuhen })
    if res.hit then
        beginJackpot(st, res, events)
        return
    end
    -- a miss burns a spin of a limited mode
    if st.mode ~= "normal" and st.modeSpins > 0 then
        st.modeSpins = st.modeSpins - 1
        if st.modeSpins == 0 then
            st.mode = "normal"
            push(events, { type = "mode", mode = "normal", spins = 0 })
        end
    end
end

local function startNextSpin(st, events)
    local res = table.remove(st.holds, 1)
    local dur = (st.mode == "normal") and PK.SPIN_SECS or PK.SPIN_SECS_FAST
    if res.reach then dur = dur + PK.REACH_EXTRA end
    st.spin = { t = 0, dur = dur, result = res, reach = res.reach, stopped = 0 }
    push(events, { type = "spin_start", reach = res.reach, dur = dur, holds = #st.holds })
end

local function onStart(st, events, wallet)
    st.starts = st.starts + 1
    local pay = st.m.startPay
    st.paidBalls = st.paidBalls + pay
    if wallet then wallet.award(pay) end
    push(events, { type = "start", pay = pay })
    if #st.holds < PK.HOLD_MAX then
        st.holds[#st.holds + 1] = drawSpin(st)
        push(events, { type = "holds", holds = #st.holds })
    end
end

local function onAttacker(st, events, wallet)
    local jp = st.jackpot
    local pay = st.m.attackerPay
    jp.paid = jp.paid + pay
    jp.count = jp.count + 1
    st.paidBalls = st.paidBalls + pay
    if wallet then wallet.award(pay) end
    push(events, { type = "attacker", pay = pay, count = jp.count, round = jp.round, rounds = jp.rounds })
    if jp.count >= st.m.count then
        jp.count = 0
        jp.open = false
        jp.gap = PK.ROUND_GAP
        push(events, { type = "round_end", round = jp.round, rounds = jp.rounds })
        if jp.round >= jp.rounds then
            endJackpot(st, events)
        else
            jp.round = jp.round + 1
        end
    end
end

local function tickLottery(st, dt, events)
    local jp = st.jackpot
    if jp then
        if not jp.open then
            jp.gap = jp.gap - dt
            if jp.gap <= 0 then
                jp.open = true
                push(events, { type = "round_start", round = jp.round, rounds = jp.rounds })
            end
        end
        return
    end
    if st.spin then
        local sp = st.spin
        sp.t = sp.t + dt
        -- left reel stops at 40%, right at 70% (that is the reach), centre last
        if sp.stopped == 0 and sp.t >= sp.dur * 0.4 then sp.stopped = 1; push(events, { type = "reel_stop", reel = 1 }) end
        if sp.stopped == 1 and sp.t >= sp.dur * 0.7 then sp.stopped = 2; push(events, { type = "reel_stop", reel = 3, reach = sp.reach }) end
        if sp.t >= sp.dur then
            push(events, { type = "reel_stop", reel = 2 })
            finishSpin(st, events)
        end
    elseif #st.holds > 0 then
        startNextSpin(st, events)
    end
end

-- ---------------------------------------------------------------------
-- Physics

local function collidePins(st, ball, events)
    local R = PK.BALL_R
    local pins, grid = st.board.pins, st.board.grid
    local gx, gy = floor(ball.x / PK.CELL), floor(ball.y / PK.CELL)
    for cy = gy - 1, gy + 1 do
        for cx = gx - 1, gx + 1 do
            local cell = grid[cx + cy * 1000]
            if cell then
                for _, idx in ipairs(cell) do
                    local p = pins[idx]
                    local pr = p.wind and PK.WIND_R or PK.PIN_R
                    local rr = R + pr
                    local dx, dy = ball.x - p.x, ball.y - p.y
                    local d2 = dx * dx + dy * dy
                    if d2 < rr * rr then
                        local d = sqrt(d2)
                        local nx, ny
                        if d < 0.0001 then nx, ny = 0, -1 else nx, ny = dx / d, dy / d end
                        ball.x, ball.y = p.x + nx * rr, p.y + ny * rr
                        local vn = ball.vx * nx + ball.vy * ny
                        if vn < 0 then
                            local k = (1 + PK.PIN_RESTITUTION) * vn
                            ball.vx = ball.vx - k * nx
                            ball.vy = ball.vy - k * ny
                            if p.wind then
                                -- a windmill flicks the ball sideways
                                ball.vx = ball.vx + (st.rng() - 0.5) * 220
                                st.windmills[idx] = (st.windmills[idx] or 0) + 1
                                push(events, { type = "windmill", x = p.x, y = p.y })
                            elseif -vn > 90 then
                                push(events, { type = "pin", x = ball.x, y = ball.y, speed = -vn })
                            end
                        end
                    end
                end
            end
        end
    end
end

local RAIL_R = 2
local function collideRails(st, ball)
    local R = PK.BALL_R + RAIL_R
    for _, r in ipairs(st.board.rails) do
        local ex, ey = r.x1 - r.x0, r.y1 - r.y0
        local len2 = ex * ex + ey * ey
        local t = 0
        if len2 > 0 then
            t = ((ball.x - r.x0) * ex + (ball.y - r.y0) * ey) / len2
            if t < 0 then t = 0 elseif t > 1 then t = 1 end
        end
        local px, py = r.x0 + ex * t, r.y0 + ey * t
        local dx, dy = ball.x - px, ball.y - py
        local d2 = dx * dx + dy * dy
        if d2 < R * R then
            local d = sqrt(d2)
            local nx, ny
            if d < 0.0001 then nx, ny = 0, -1 else nx, ny = dx / d, dy / d end
            ball.x, ball.y = px + nx * R, py + ny * R
            local vn = ball.vx * nx + ball.vy * ny
            if vn < 0 then
                local k = (1 + PK.RESTITUTION) * vn
                ball.vx = ball.vx - k * nx
                ball.vy = ball.vy - k * ny
            end
        end
    end
end

local function collideBox(ball)
    local box = PK.BOX
    local R = PK.BALL_R
    -- closest point on the box to the ball
    local cx = ball.x < box.l and box.l or (ball.x > box.r and box.r or ball.x)
    local cy = ball.y < box.t and box.t or (ball.y > box.b and box.b or ball.y)
    local dx, dy = ball.x - cx, ball.y - cy
    local d2 = dx * dx + dy * dy
    if d2 >= R * R then return end
    local nx, ny
    if d2 > 0.0001 then
        local d = sqrt(d2)
        nx, ny = dx / d, dy / d
        ball.x, ball.y = cx + nx * R, cy + ny * R
    else
        -- inside: eject through the nearest face
        local toL, toR, toT, toB = ball.x - box.l, box.r - ball.x, ball.y - box.t, box.b - ball.y
        local m = math.min(toL, toR, toT, toB)
        if m == toL then nx, ny = -1, 0; ball.x = box.l - R
        elseif m == toR then nx, ny = 1, 0; ball.x = box.r + R
        elseif m == toT then nx, ny = 0, -1; ball.y = box.t - R
        else nx, ny = 0, 1; ball.y = box.b + R end
    end
    local vn = ball.vx * nx + ball.vy * ny
    if vn < 0 then
        local k = (1 + PK.RESTITUTION) * vn
        ball.vx = ball.vx - k * nx
        ball.vy = ball.vy - k * ny
    end
end

local function inPocket(ball, px, py, pw)
    local R = PK.BALL_R
    return ball.vy > 0 and ball.y + R >= py and ball.y - R <= py + 10 and abs(ball.x - px) <= pw / 2 - 1
end

local function integrateBall(st, ball, dt, events, wallet)
    ball.vy = ball.vy + PK.GRAVITY * dt
    ball.x = ball.x + ball.vx * dt
    ball.y = ball.y + ball.vy * dt
    local R = PK.BALL_R
    if ball.x < R then ball.x = R; if ball.vx < 0 then ball.vx = -ball.vx * PK.RESTITUTION end end
    if ball.x > W - R then ball.x = W - R; if ball.vx > 0 then ball.vx = -ball.vx * PK.RESTITUTION end end
    if ball.y < R then ball.y = R; if ball.vy < 0 then ball.vy = -ball.vy * PK.RESTITUTION end end

    collideBox(ball)
    collideRails(st, ball)
    collidePins(st, ball, events)

    local b = st.board
    if inPocket(ball, b.start.x, b.start.y, PK:StartPocketWidth(st)) then
        onStart(st, events, wallet)
        push(events, { type = "pocket", which = "start", x = ball.x, y = b.start.y })
        return false
    end
    for _, s in ipairs(b.sides) do
        if inPocket(ball, s.x, s.y, s.w) then
            local pay = st.m.sidePay
            st.paidBalls = st.paidBalls + pay
            if wallet then wallet.award(pay) end
            push(events, { type = "side", pay = pay, x = s.x, y = s.y })
            return false
        end
    end
    local jp = st.jackpot
    if jp and jp.open and inPocket(ball, b.attacker.x, b.attacker.y, b.attacker.w) then
        onAttacker(st, events, wallet)
        push(events, { type = "pocket", which = "attacker", x = ball.x, y = b.attacker.y })
        return false
    end
    if ball.y - R > H then
        push(events, { type = "drain", x = ball.x })
        return false
    end
    -- a ball that has lived far too long is wedged somewhere: let it go
    ball.age = (ball.age or 0) + dt
    if ball.age > 20 then
        push(events, { type = "drain", x = ball.x, stuck = true })
        return false
    end
    -- a ball resting on pins is nudged along
    local speed2 = ball.vx * ball.vx + ball.vy * ball.vy
    if speed2 < 400 then
        ball.slow = (ball.slow or 0) + dt
        if ball.slow > 0.6 then
            ball.vx = ball.vx + (st.rng() - 0.5) * 160
            ball.vy = ball.vy - 140
            ball.slow = 0
        end
    else
        ball.slow = 0
    end
    return true
end

local function launch(st, events)
    local rng = st.rng
    local s = st.handle
    local x = 24 + s * (W - 48) + (rng() - 0.5) * 18
    if x < PK.BALL_R + 1 then x = PK.BALL_R + 1 elseif x > W - PK.BALL_R - 1 then x = W - PK.BALL_R - 1 end
    st.balls[#st.balls + 1] = { x = x, y = 12, vx = (s - 0.5) * 60 + (rng() - 0.5) * 20, vy = 40, slow = 0 }
    st.launched = st.launched + 1
    push(events, { type = "launch", x = x })
end

local function substep(st, dt, events, wallet)
    st.time = st.time + dt
    if st.firing then
        st.launchAcc = st.launchAcc + dt
        if st.launchAcc >= PK.LAUNCH_INTERVAL then
            st.launchAcc = st.launchAcc - PK.LAUNCH_INTERVAL
            if wallet and not wallet.spend(1) then
                st.firing = false
                push(events, { type = "broke" })
            else
                launch(st, events)
            end
        end
    end
    for i = #st.balls, 1, -1 do
        if not integrateBall(st, st.balls[i], dt, events, wallet) then
            table.remove(st.balls, i)
        end
    end
    tickLottery(st, dt, events)
end

-- Advance by dt seconds. wallet = { spend = function(balls) -> bool,
-- award = function(balls) } in BALLS (the UI converts at the rate).
function PK:Step(st, dt, events, wallet)
    if dt > 0.1 then dt = 0.1 end
    st.acc = st.acc + dt
    local step = PK.STEP
    local guard = 0
    while st.acc >= step and guard < 60 do
        substep(st, step, events, wallet)
        st.acc = st.acc - step
        guard = guard + 1
    end
    return events
end

-- Expected balls paid per jackpot for the pay-table readout.
function PK:JackpotBalls(m, rounds)
    return rounds * m.count * m.attackerPay
end
