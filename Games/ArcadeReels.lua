--[[
    Chairface's Casino - Games/ArcadeReels.lua
    The Slot Floor: five video reel machines, each a WoW-dressed copy of a
    famous casino floor game's MECHANICS (names and art are our own):

      kodo     Kodo Stampede     - Aristocrat "Buffalo": 5x4, 1024 ways,
                                   stacked kodos, coin scatters, free spins
                                   with x2/x3 wilds that multiply together
      pharaoh  Pharaoh of Uldum  - IGT "Cleopatra": 5x3, 20 lines, the wild
                                   doubles every win it joins, 3+ sphinx
                                   scatters = 15 free spins at x3, retriggers
      darkmoon Darkmoon Wheel    - IGT "Wheel of Fortune Double Diamond":
                                   3-reel stepper, one payline, BAR/7/cherry,
                                   x2 wilds (two = x4), SPIN on reel 3 at max
                                   coins spins the prize wheel
      jade     Jade Fortunes     - Bally "88 Fortunes": 5x3, 243 ways, bet
                                   levels 8/18/38/68/88 unlock Mini..Grand,
                                   a random Fu Bat pick-em (match 3 coins),
                                   gong scatters = free spins
      bonanza  Tel'Abim Bonanza  - Pragmatic "Sweet Bonanza": 6x5 pay
                                   anywhere (8+ of a kind), tumbling wins,
                                   4+ scatters = free spins with 2x-100x
                                   multiplier bombs, 21,100x win cap

    Pure logic, UI-free (UI/ReelsFrame.lua renders it), and money-safe: a
    spin charges and pays its WHOLE outcome - free spins, wheel, pick-em
    included - the moment it's rolled, so a /reload mid-animation never
    loses a win. The UI just hides the pending amount until it's revealed.
    Credits come from BJ.Arcade (the shared fake balance); plain
    math.random, like the rest of the arcade.

    Paytables are in COINS (the bet ladder denomination). RTPs are
    sim-tuned by tests/reels_test.py.
]]

local BJ = ChairfacesCasino
local Arcade = BJ.Arcade
Arcade.Reels = {}
local Reels = Arcade.Reels

local ICON = "Interface\\Icons\\"

-- Coin denominations every machine walks with its BET +/-.
Reels.COIN_STEPS = { 1, 2, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000 }

function Reels:NextCoin(current, dir)
    local steps = self.COIN_STEPS
    local idx = 1
    for i, v in ipairs(steps) do
        if v == current then idx = i break end
        if v > current then idx = (dir > 0) and (i - 1) or i break end
    end
    idx = math.max(1, math.min(#steps, idx + dir))
    return steps[idx]
end

Reels.machines = {}   -- floor order
Reels.byId = {}

local function register(m)
    Reels.machines[#Reels.machines + 1] = m
    Reels.byId[m.id] = m
    m.symbolById = {}
    for _, s in ipairs(m.symbols) do m.symbolById[s.id] = s end
    return m
end

--[[ ============ shared helpers ============ ]]

local function key(reel, row) return reel .. ":" .. row end

-- Pick from { {value, weight}, ... }
local function pickWeighted(list)
    local total = 0
    for _, e in ipairs(list) do total = total + e[2] end
    local r = math.random() * total
    for _, e in ipairs(list) do
        r = r - e[2]
        if r <= 0 then return e[1] end
    end
    return list[#list][1]
end

-- Strip layout uses its own seeded generator, so every client (and the
-- RTP sim) gets the SAME reel bands every load - a machine's payback is a
-- property of its strips, and it shouldn't drift per session.
local stripSeed = 88
local function seedStrips(n) stripSeed = n end
local function stripRandom(n)
    stripSeed = (stripSeed * 1103515245 + 12345) % 2147483648
    return (math.floor(stripSeed / 65536) % n) + 1
end

-- A reel strip from { {sym, copies, stack} }: each entry is laid down as
-- blocks of `stack` (default 1) identical symbols, the blocks shuffled so
-- stacks stay together but land anywhere.
local function buildStrip(spec)
    local blocks = {}
    for _, e in ipairs(spec) do
        local sym, copies, stack = e[1], e[2], e[3] or 1
        local left = copies
        while left > 0 do
            local n = math.min(stack, left)
            blocks[#blocks + 1] = { sym = sym, n = n }
            left = left - n
        end
    end
    for i = #blocks, 2, -1 do
        local j = stripRandom(i)
        blocks[i], blocks[j] = blocks[j], blocks[i]
    end
    local strip = {}
    for _, b in ipairs(blocks) do
        for _ = 1, b.n do strip[#strip + 1] = b.sym end
    end
    return strip
end

-- Window of `rows` consecutive stops per reel, from random stops.
local function spinStrips(strips, rows)
    local grid, stops = {}, {}
    for r, strip in ipairs(strips) do
        local n = #strip
        local stop = math.random(n)
        stops[r] = stop
        grid[r] = {}
        for row = 1, rows do
            grid[r][row] = strip[((stop + row - 2) % n) + 1]
        end
    end
    return grid, stops
end

local function copyGrid(grid)
    local g = {}
    for r, col in ipairs(grid) do
        g[r] = {}
        for row, v in ipairs(col) do g[r][row] = v end
    end
    return g
end

-- Every cell holding `sym` (scatters pay/trigger anywhere).
local function findCells(grid, sym)
    local cells = {}
    for r, col in ipairs(grid) do
        for row, v in ipairs(col) do
            if v == sym then cells[#cells + 1] = { reel = r, row = row } end
        end
    end
    return cells
end

-- Ways evaluation (243/1024-ways games): for each paying symbol, the run of
-- consecutive reels from the left that hold it (or a wild allowed on that
-- reel) - each reel contributes the SUM of its matching positions' weights
-- (1, or a wild's multiplier), so the product is ways x every multiplier
-- combination at once. Returns wins, total units.
local function evalWays(m, grid, cellMult)
    local wins, total = {}, 0
    for _, s in ipairs(m.symbols) do
        local pays = m.pays[s.id]
        if pays and not s.wild and not s.scatter then
            local product, count, cells = 1, 0, {}
            for r = 1, #grid do
                local sum, reelCells = 0, {}
                for row, v in ipairs(grid[r]) do
                    if v == s.id then
                        sum = sum + 1
                        reelCells[#reelCells + 1] = { reel = r, row = row }
                    elseif v == m.wild and r > 1 then
                        sum = sum + ((cellMult and cellMult[key(r, row)]) or 1)
                        reelCells[#reelCells + 1] = { reel = r, row = row }
                    end
                end
                -- reel 1 must hold the symbol itself (wilds never start a way)
                if sum == 0 then break end
                product = product * sum
                count = count + 1
                for _, c in ipairs(reelCells) do cells[#cells + 1] = c end
            end
            local p = pays[count]
            if p then
                local units = p * product
                total = total + units
                wins[#wins + 1] = { sym = s.id, count = count, ways = product,
                                    units = units, cells = cells }
            end
        end
    end
    return wins, total
end

-- Scale a spin record's units into credits (rounded once, at the end).
local function toCredits(units, coin)
    return math.floor(units * coin + 0.5)
end

--[[ ============ KODO STAMPEDE (Buffalo) ============ ]]

local kodo = register({
    id = "kodo",
    title = "Kodo Stampede",
    tagline = "1024 WAYS - STAMPEDE FREE GAMES",
    reels = 5, rows = 4,
    wild = "sun",
    wildReels = { [2] = true, [3] = true, [4] = true },
    scatter = "coin",
    costCoins = 40,
    theme = {
        bg = { 0.20, 0.09, 0.03 }, bg2 = { 0.45, 0.20, 0.05 },
        border = { 0.95, 0.55, 0.15 }, title = { 1.0, 0.72, 0.2 },
        reel = { 0.06, 0.03, 0.01 }, accent = { 1.0, 0.45, 0.1 },
    },
    symbols = {
        { id = "kodo",  name = "Kodo",       icon = ICON .. "Ability_Mount_Kodo_01",       glyph = "KODO", color = { 0.85, 0.6, 0.35 } },
        { id = "wyv",   name = "Wyvern",     icon = ICON .. "Ability_Hunter_Pet_WindSerpent", glyph = "WYV", color = { 0.4, 0.8, 1 } },
        { id = "cat",   name = "Cougar",     icon = ICON .. "Ability_Hunter_Pet_Cat",      glyph = "CAT",  color = { 1, 0.8, 0.3 } },
        { id = "wolf",  name = "Wolf",       icon = ICON .. "Ability_Hunter_Pet_Wolf",     glyph = "WOLF", color = { 0.7, 0.7, 0.8 } },
        { id = "elk",   name = "Plainstrider", icon = ICON .. "Ability_Hunter_Pet_Tallstrider", glyph = "ELK", color = { 0.7, 0.9, 0.4 } },
        { id = "A",  name = "Ace",   glyph = "A",  color = { 1, 0.3, 0.25 } },
        { id = "K",  name = "King",  glyph = "K",  color = { 0.35, 0.6, 1 } },
        { id = "Q",  name = "Queen", glyph = "Q",  color = { 0.8, 0.4, 1 } },
        { id = "J",  name = "Jack",  glyph = "J",  color = { 0.35, 0.9, 0.4 } },
        { id = "T",  name = "Ten",   glyph = "10", color = { 1, 0.6, 0.2 } },
        { id = "N",  name = "Nine",  glyph = "9",  color = { 0.9, 0.9, 0.5 } },
        { id = "sun",  name = "Sunset WILD", icon = ICON .. "Spell_Holy_InnerFire", glyph = "WILD", color = { 1, 0.55, 0.1 }, wild = true },
        { id = "coin", name = "Gold Coin",   icon = ICON .. "INV_Misc_Coin_01",    glyph = "$",    color = { 1, 0.85, 0.1 }, scatter = true },
    },
    -- per way, in coins (a spin costs 40 coins)
    pays = {
        kodo = { [3] = 10, [4] = 30, [5] = 145 },   -- 145, not 150: 95.3% like the rest
        wyv  = { [3] = 8,  [4] = 20, [5] = 75 },
        cat  = { [3] = 6,  [4] = 15, [5] = 60 },
        wolf = { [3] = 5,  [4] = 12, [5] = 50 },
        elk  = { [3] = 4,  [4] = 10, [5] = 40 },
        A    = { [3] = 3,  [4] = 8,  [5] = 25 },
        K    = { [3] = 3,  [4] = 8,  [5] = 25 },
        Q    = { [3] = 2,  [4] = 5,  [5] = 20 },
        J    = { [3] = 2,  [4] = 5,  [5] = 20 },
        T    = { [3] = 2,  [4] = 4,  [5] = 15 },
        N    = { [3] = 2,  [4] = 4,  [5] = 15 },
    },
    scatterPays = { [3] = 2, [4] = 10, [5] = 20 },   -- x total bet
    freeSpins   = { [3] = 8, [4] = 15, [5] = 20 },
    retrigger   = { [2] = 5, [3] = 8, [4] = 15, [5] = 20 },
    maxFree = 200,
})

do
    local function reelSpec(r, free)
        local s = {
            { "kodo", free and 12 or 12, 4 },
            { "wyv", 6, 2 }, { "cat", 6, 2 }, { "wolf", 7, 2 }, { "elk", 7, 2 },
            { "A", 7 }, { "K", 7 }, { "Q", 8 }, { "J", 8 }, { "T", 7 }, { "N", 7 },
            -- free games run thin on coins, or "2 coins = +5 spins" would
            -- retrigger forever
            { "coin", free and 1 or 2 },
        }
        if kodo.wildReels[r] then s[#s + 1] = { "sun", free and 5 or 3 } end
        return s
    end
    kodo.strips, kodo.freeStrips = {}, {}
    seedStrips(1001)
    for r = 1, 5 do kodo.strips[r] = buildStrip(reelSpec(r, false)) end
    seedStrips(1002)
    for r = 1, 5 do kodo.freeStrips[r] = buildStrip(reelSpec(r, true)) end
end

function kodo:SpinOnce(free)
    local grid = spinStrips(free and self.freeStrips or self.strips, self.rows)
    return grid
end

function kodo:Evaluate(grid, free)
    local rec = { grid = grid }
    -- free games: every sunset wild lands as x2 or x3, and they multiply
    if free then
        rec.cellMult = {}
        for r = 2, 4 do
            for row = 1, self.rows do
                if grid[r][row] == self.wild then
                    rec.cellMult[key(r, row)] = (math.random(2) == 1) and 2 or 3
                end
            end
        end
    end
    rec.wins, rec.units = evalWays(self, grid, rec.cellMult)
    rec.scatterCells = findCells(grid, self.scatter)
    local n = #rec.scatterCells
    local sp = self.scatterPays[math.min(n, 5)]
    if sp then
        rec.scatterUnits = sp * self.costCoins
        rec.units = rec.units + rec.scatterUnits
    end
    if free then
        rec.freeAdded = self.retrigger[math.min(n, 5)]
    else
        rec.freeAdded = self.freeSpins[math.min(n, 5)]
    end
    return rec
end

--[[ ============ PHARAOH OF ULDUM (Cleopatra) ============ ]]

local pharaoh = register({
    id = "pharaoh",
    title = "Pharaoh of Uldum",
    tagline = "20 LINES - WILDS PAY DOUBLE - FREE SPINS PAY TRIPLE",
    reels = 5, rows = 3,
    wild = "pharaoh",
    scatter = "sphinx",
    costCoins = 20,
    theme = {
        bg = { 0.05, 0.08, 0.20 }, bg2 = { 0.10, 0.28, 0.45 },
        border = { 0.95, 0.80, 0.30 }, title = { 1.0, 0.85, 0.35 },
        reel = { 0.02, 0.03, 0.08 }, accent = { 0.2, 0.75, 0.85 },
    },
    symbols = {
        { id = "pharaoh", name = "Pharaoh WILD", icon = ICON .. "INV_Crown_01",               glyph = "WILD", color = { 1, 0.85, 0.3 }, wild = true },
        { id = "sphinx",  name = "Sphinx",       icon = ICON .. "INV_Misc_Statue_04",         glyph = "SPHX", color = { 0.95, 0.75, 0.4 }, scatter = true },
        { id = "mask",    name = "Golden Mask",  icon = ICON .. "INV_Misc_Idol_03",           glyph = "MASK", color = { 1, 0.8, 0.2 } },
        { id = "scarab",  name = "Scarab",       icon = ICON .. "INV_Misc_AhnQirajTrinket_01", glyph = "SCRB", color = { 0.3, 0.8, 0.6 } },
        { id = "eye",     name = "Eye of Uldum", icon = ICON .. "INV_Misc_Eye_01",            glyph = "EYE",  color = { 0.4, 0.7, 1 } },
        { id = "ankh",    name = "Ankh",         icon = ICON .. "INV_Jewelry_Talisman_07",    glyph = "ANKH", color = { 1, 0.9, 0.5 } },
        { id = "lotus",   name = "Lotus",        icon = ICON .. "INV_Misc_Flower_02",         glyph = "LOTUS", color = { 1, 0.5, 0.8 } },
        { id = "A",  name = "Ace",   glyph = "A",  color = { 1, 0.3, 0.25 } },
        { id = "K",  name = "King",  glyph = "K",  color = { 0.35, 0.6, 1 } },
        { id = "Q",  name = "Queen", glyph = "Q",  color = { 0.8, 0.4, 1 } },
        { id = "J",  name = "Jack",  glyph = "J",  color = { 0.35, 0.9, 0.4 } },
        { id = "T",  name = "Ten",   glyph = "10", color = { 1, 0.6, 0.2 } },
        { id = "N",  name = "Nine",  glyph = "9",  color = { 0.9, 0.9, 0.5 } },
    },
    -- per line, in coins (1 coin per line x 20 lines)
    pays = {
        pharaoh = { [2] = 10, [3] = 200, [4] = 2000, [5] = 10000 },
        mask    = { [2] = 2, [3] = 25, [4] = 100, [5] = 750 },
        scarab  = { [2] = 2, [3] = 25, [4] = 100, [5] = 750 },
        eye     = { [3] = 20, [4] = 75,  [5] = 250 },
        ankh    = { [3] = 15, [4] = 50,  [5] = 250 },
        lotus   = { [3] = 15, [4] = 50,  [5] = 250 },
        A       = { [3] = 10, [4] = 50,  [5] = 125 },
        K       = { [3] = 10, [4] = 50,  [5] = 125 },
        Q       = { [3] = 5,  [4] = 25,  [5] = 100 },
        J       = { [3] = 5,  [4] = 25,  [5] = 100 },
        T       = { [3] = 5,  [4] = 25,  [5] = 100 },
        N       = { [2] = 2, [3] = 5,  [4] = 25,  [5] = 100 },
    },
    scatterPays = { [2] = 2, [3] = 5, [4] = 20, [5] = 100 },   -- x total bet
    freeSpins = 15, freeMult = 3, maxFree = 180,
    -- the classic 20-line pattern (rows 1 top .. 3 bottom)
    lines = {
        { 2, 2, 2, 2, 2 }, { 1, 1, 1, 1, 1 }, { 3, 3, 3, 3, 3 }, { 1, 2, 3, 2, 1 },
        { 3, 2, 1, 2, 3 }, { 2, 1, 1, 1, 2 }, { 2, 3, 3, 3, 2 }, { 1, 1, 2, 3, 3 },
        { 3, 3, 2, 1, 1 }, { 2, 3, 2, 1, 2 }, { 2, 1, 2, 3, 2 }, { 1, 2, 2, 2, 1 },
        { 3, 2, 2, 2, 3 }, { 1, 2, 1, 2, 1 }, { 3, 2, 3, 2, 3 }, { 2, 2, 1, 2, 2 },
        { 2, 2, 3, 2, 2 }, { 1, 1, 3, 1, 1 }, { 3, 3, 1, 3, 3 }, { 1, 3, 3, 3, 1 },
    },
})

do
    local function reelSpec(r)
        return {
            { "pharaoh", 2 }, { "sphinx", 2 },
            { "mask", 3 }, { "scarab", 3 }, { "eye", 4 }, { "ankh", 4 }, { "lotus", 4 },
            { "A", 6 }, { "K", 6 }, { "Q", 8 }, { "J", 8 }, { "T", 7 }, { "N", 7 },
        }
    end
    pharaoh.strips = {}
    seedStrips(2001)
    for r = 1, 5 do pharaoh.strips[r] = buildStrip(reelSpec(r)) end
end

function pharaoh:SpinOnce()
    return (spinStrips(self.strips, self.rows))
end

-- One payline's symbols -> units, count, symbol, doubled?
function pharaoh:EvalLine(syms)
    local wild = self.wild
    local wildRun = 0
    for i = 1, #syms do
        if syms[i] == wild then wildRun = wildRun + 1 else break end
    end
    local best, bestCount, bestSym, doubled = 0, nil, nil, false
    local wt = self.pays[wild]
    if wt[wildRun] then best, bestCount, bestSym = wt[wildRun], wildRun, wild end

    local target
    for i = 1, #syms do
        if syms[i] ~= wild then target = syms[i] break end
    end
    if target and target ~= self.scatter then
        local count, usedWild = 0, false
        for i = 1, #syms do
            if syms[i] == target then count = count + 1
            elseif syms[i] == wild then count = count + 1; usedWild = true
            else break end
        end
        local tab = self.pays[target]
        local p = tab and tab[count]
        if p then
            -- the wild doubles any win it substitutes in
            if usedWild then p = p * 2 end
            if p > best then best, bestCount, bestSym, doubled = p, count, target, usedWild end
        end
    end
    return best, bestCount, bestSym, doubled
end

function pharaoh:Evaluate(grid, free)
    local rec = { grid = grid, wins = {}, units = 0 }
    local mult = free and self.freeMult or 1
    for li, rows in ipairs(self.lines) do
        local syms = {}
        for r = 1, 5 do syms[r] = grid[r][rows[r]] end
        local p, count, sym, doubled = self:EvalLine(syms)
        if p > 0 then
            local cells = {}
            for r = 1, count do cells[r] = { reel = r, row = rows[r] } end
            local units = p * mult
            rec.wins[#rec.wins + 1] = { line = li, sym = sym, count = count,
                                        units = units, cells = cells, doubled = doubled }
            rec.units = rec.units + units
        end
    end
    rec.scatterCells = findCells(grid, self.scatter)
    local n = #rec.scatterCells
    local sp = self.scatterPays[math.min(n, 5)]
    if sp then
        rec.scatterUnits = sp * self.costCoins * mult
        rec.units = rec.units + rec.scatterUnits
    end
    if n >= 3 then rec.freeAdded = self.freeSpins end
    rec.mult = mult
    return rec
end

--[[ ============ DARKMOON WHEEL (Wheel of Fortune Double Diamond) ============ ]]

local darkmoon = register({
    id = "darkmoon",
    title = "Darkmoon Wheel",
    tagline = "DOUBLE DIAMONDS - SPIN THE WHEEL AT MAX COINS",
    reels = 3, rows = 3, payRow = 2,
    wild = "dd",
    costCoins = 1,      -- per coin played; 1-3 coins
    maxCoins = 3,
    theme = {
        bg = { 0.14, 0.03, 0.18 }, bg2 = { 0.35, 0.05, 0.35 },
        border = { 0.85, 0.35, 1.0 }, title = { 1.0, 0.85, 0.3 },
        reel = { 0.95, 0.93, 0.88 }, accent = { 1.0, 0.25, 0.55 },
        lightReels = true,
    },
    symbols = {
        { id = "dd",    name = "Double Diamond WILD", icon = ICON .. "INV_Misc_Gem_Diamond_01", glyph = "DD", color = { 0.4, 0.8, 1 }, wild = true },
        { id = "seven", name = "Red 7",     glyph = "7",   color = { 0.9, 0.08, 0.1 }, big = true },
        { id = "bar3",  name = "Triple BAR", glyph = "BAR\nBAR\nBAR", color = { 0.1, 0.1, 0.1 } },
        { id = "bar2",  name = "Double BAR", glyph = "BAR\nBAR", color = { 0.1, 0.1, 0.1 } },
        { id = "bar1",  name = "Single BAR", glyph = "BAR", color = { 0.1, 0.1, 0.1 } },
        { id = "cherry", name = "Cherry",   icon = ICON .. "INV_Misc_Food_19", glyph = "CH", color = { 0.85, 0.1, 0.2 } },
        { id = "spin",  name = "SPIN",      glyph = "SPIN", color = { 0.7, 0.1, 0.8 }, scatter = true },
        { id = "blank", name = "",          glyph = "", color = { 0, 0, 0 }, blank = true },
    },
    -- per coin played
    pays = {
        seven = 80, bar3 = 40, bar2 = 25, bar1 = 10, anybar = 5,
        cherry = { [1] = 2, [2] = 5, [3] = 10 },
        ddOne = 2, ddTwo = 10,
        ddThree = { [1] = 800, [2] = 1600, [3] = 2500 },   -- by coins played
    },
    -- the prize wheel, in coins (it only spins on a max-coin bet)
    wheel = {
        { 25, 14 }, { 30, 12 }, { 35, 11 }, { 40, 10 }, { 45, 8 }, { 50, 8 },
        { 60, 6 }, { 75, 6 }, { 80, 5 }, { 100, 5 }, { 120, 3 }, { 150, 3 },
        { 200, 2 }, { 250, 2 }, { 300, 1.2 }, { 400, 1 }, { 500, 0.6 },
        { 750, 0.35 }, { 1000, 0.15 },
    },
})

do
    -- Virtual stops: a stepper's odds live in these weights, while the
    -- physical strip (what you see above/below the line) alternates symbol
    -- and blank like a real reel band.
    darkmoon.weights = {
        { dd = 1, seven = 3, bar3 = 4, bar2 = 6, bar1 = 9, cherry = 3, blank = 38 },
        { dd = 1, seven = 3, bar3 = 4, bar2 = 6, bar1 = 9, cherry = 3, blank = 38 },
        -- SPIN 0.645 (was 0.6): the wheel about 1 in 99, and 95.3% at max coins
        { dd = 1, seven = 3, bar3 = 4, bar2 = 6, bar1 = 9, cherry = 3, spin = 0.645, blank = 37.355 },
    }
    local order = { "seven", "bar1", "cherry", "bar2", "dd", "bar1", "bar3", "cherry", "bar1", "bar2", "seven" }
    darkmoon.strips = {}
    for r = 1, 3 do
        local strip = {}
        for i, s in ipairs(order) do
            if r == 3 and i == 6 then s = "spin" end
            strip[#strip + 1] = s
            strip[#strip + 1] = "blank"
        end
        darkmoon.strips[r] = strip
    end
end

function darkmoon:SpinOnce()
    local grid = {}
    for r = 1, 3 do
        local wlist = {}
        for sym, w in pairs(self.weights[r]) do wlist[#wlist + 1] = { sym, w } end
        table.sort(wlist, function(a, b) return a[1] < b[1] end)
        local sym = pickWeighted(wlist)
        -- land the band so that symbol sits on the payline
        local strip, spots = self.strips[r], {}
        for i, s in ipairs(strip) do
            if s == sym or (sym == "blank" and s == "blank") then spots[#spots + 1] = i end
        end
        if #spots == 0 then   -- symbol not on this band's art (never, but safe)
            for i, s in ipairs(strip) do if s == "blank" then spots[#spots + 1] = i end end
        end
        local at = spots[math.random(#spots)]
        local n = #strip
        grid[r] = {
            strip[((at - 2) % n) + 1],
            sym,
            strip[(at % n) + 1],
        }
    end
    return grid
end

function darkmoon:EvalLine(line, coins)
    local P = self.pays
    local nDD, nCH, nBar = 0, 0, 0
    for _, s in ipairs(line) do
        if s == "dd" then nDD = nDD + 1
        elseif s == "cherry" then nCH = nCH + 1
        elseif s == "bar1" or s == "bar2" or s == "bar3" then nBar = nBar + 1 end
    end
    if nDD == 3 then return P.ddThree[coins] / coins, "3x Double Diamond" end
    local mult = (nDD == 2) and 4 or ((nDD == 1) and 2 or 1)
    local best, label = 0, nil
    local function allOf(target)
        for _, s in ipairs(line) do
            if s ~= target and s ~= "dd" then return false end
        end
        return true
    end
    for _, t in ipairs({ "seven", "bar3", "bar2", "bar1" }) do
        if allOf(t) and P[t] * mult > best then
            best, label = P[t] * mult, self.symbolById[t].name
        end
    end
    if nBar + nDD == 3 and nBar > 0 and P.anybar * mult > best then
        best, label = P.anybar * mult, "Any BAR"
    end
    if nCH > 0 then
        local c = P.cherry[math.min(3, nCH + nDD)] * mult
        if c > best then best, label = c, "Cherries" end
    end
    if nDD == 1 and P.ddOne > best then best, label = P.ddOne, "Double Diamond" end
    if nDD == 2 and P.ddTwo > best then best, label = P.ddTwo, "Two Double Diamonds" end
    if best > 0 and nDD > 0 and label and not label:find("Diamond") then
        label = label .. " x" .. mult
    end
    return best, label
end

function darkmoon:Evaluate(grid, _, coins)
    local line = { grid[1][2], grid[2][2], grid[3][2] }
    local rec = { grid = grid, wins = {}, units = 0 }
    local per, label = self:EvalLine(line, coins)
    if per > 0 then
        local units = per * coins
        rec.units = units
        rec.wins[1] = { line = 1, label = label, units = units,
            cells = { { reel = 1, row = 2 }, { reel = 2, row = 2 }, { reel = 3, row = 2 } } }
    end
    if line[3] == "spin" then
        rec.spinSymbol = true
        rec.scatterCells = { { reel = 3, row = 2 } }
    end
    return rec
end

--[[ ============ JADE FORTUNES (88 Fortunes) ============ ]]

local jade = register({
    id = "jade",
    title = "Jade Fortunes",
    tagline = "243 WAYS - GOLD SYMBOLS UNLOCK THE JACKPOTS",
    reels = 5, rows = 3,
    wild = "fu",
    scatter = "gong",
    levels = { 8, 18, 38, 68, 88 },   -- coins per spin at each gold level
    theme = {
        bg = { 0.22, 0.02, 0.02 }, bg2 = { 0.50, 0.05, 0.04 },
        border = { 1.0, 0.78, 0.2 }, title = { 1.0, 0.82, 0.25 },
        reel = { 0.08, 0.01, 0.01 }, accent = { 0.25, 0.85, 0.45 },
    },
    symbols = {
        { id = "dragon", name = "Jade Dragon",  icon = ICON .. "INV_Misc_Head_Dragon_01", glyph = "DRGN", color = { 0.3, 0.9, 0.5 } },
        { id = "turtle", name = "Turtle",       icon = ICON .. "Ability_Hunter_Pet_Turtle", glyph = "TURT", color = { 0.5, 0.85, 0.4 } },
        { id = "koi",    name = "Golden Koi",   icon = ICON .. "INV_Misc_Fish_02",        glyph = "KOI",  color = { 1, 0.6, 0.2 } },
        { id = "ingot",  name = "Gold Ingot",   icon = ICON .. "INV_Ingot_03",            glyph = "INGT", color = { 1, 0.85, 0.2 } },
        { id = "jade",   name = "Jade",         icon = ICON .. "INV_Misc_Gem_Emerald_01", glyph = "JADE", color = { 0.2, 1, 0.5 } },
        { id = "A",  name = "Ace",   glyph = "A",  color = { 1, 0.3, 0.25 } },
        { id = "K",  name = "King",  glyph = "K",  color = { 0.35, 0.6, 1 } },
        { id = "Q",  name = "Queen", glyph = "Q",  color = { 0.8, 0.4, 1 } },
        { id = "J",  name = "Jack",  glyph = "J",  color = { 0.35, 0.9, 0.4 } },
        { id = "T",  name = "Ten",   glyph = "10", color = { 1, 0.6, 0.2 } },
        { id = "fu",   name = "FU WILD", glyph = "FU", color = { 1, 0.2, 0.15 }, wild = true },
        { id = "gong", name = "Gong",    icon = ICON .. "INV_Misc_Bell_01", glyph = "GONG", color = { 1, 0.8, 0.2 }, scatter = true },
    },
    -- per way, in coins AT THE 88-COIN LEVEL (lower levels pay pro rata)
    pays = {
        dragon = { [3] = 160, [4] = 480, [5] = 2000 },
        turtle = { [3] = 120, [4] = 360, [5] = 1200 },
        koi    = { [3] = 100, [4] = 240, [5] = 800 },
        ingot  = { [3] = 80,  [4] = 200, [5] = 600 },
        jade   = { [3] = 60,  [4] = 160, [5] = 480 },
        A      = { [3] = 40,  [4] = 100, [5] = 320 },
        K      = { [3] = 40,  [4] = 100, [5] = 320 },
        Q      = { [3] = 32,  [4] = 80,  [5] = 240 },
        J      = { [3] = 32,  [4] = 80,  [5] = 240 },
        T      = { [3] = 24,  [4] = 60,  [5] = 200 },
    },
    scatterPays = { [3] = 2, [4] = 10, [5] = 50 },   -- x total bet
    freeSpins = 10, maxFree = 100,
    -- Fu Bat jackpots, in coins (fixed per denomination, like the floor
    -- machine: cheap levels chase the same Mini a max bettor does)
    jackpots = {
        { key = "mini",  label = "MINI",  coins = 880,    level = 1, weight = 70, color = { 0.4, 0.8, 1 } },
        { key = "minor", label = "MINOR", coins = 2640,   level = 2, weight = 22, color = { 0.4, 1, 0.5 } },
        { key = "major", label = "MAJOR", coins = 13200,  level = 3, weight = 7,  color = { 0.8, 0.4, 1 } },
        { key = "grand", label = "GRAND", coins = 132000, level = 4, weight = 1,  color = { 1, 0.35, 0.3 } },
    },
    jackpotShare = 0.08,   -- slice of each bet level's price that funds the Fu Bat
    pickCoins = 12,
})

do
    local function reelSpec(r, free)
        local s = {
            { "dragon", 3 }, { "turtle", 3 }, { "koi", 4 }, { "ingot", 4 }, { "jade", 5 },
            { "A", 6 }, { "K", 6 }, { "Q", 7 }, { "J", 7 }, { "T", 7 },
        }
        if r > 1 then s[#s + 1] = { "fu", free and 4 or 2 } end
        if r <= 3 then s[#s + 1] = { "gong", 3 } end
        return s
    end
    jade.strips, jade.freeStrips = {}, {}
    seedStrips(4001)
    for r = 1, 5 do jade.strips[r] = buildStrip(reelSpec(r, false)) end
    seedStrips(4002)
    for r = 1, 5 do jade.freeStrips[r] = buildStrip(reelSpec(r, true)) end
end

function jade:SpinOnce(free)
    return (spinStrips(free and self.freeStrips or self.strips, self.rows))
end

function jade:Evaluate(grid, free, level)
    local rec = { grid = grid }
    local wins, units = evalWays(self, grid, nil)
    local scale = self.levels[level] / 88
    for _, w in ipairs(wins) do w.units = w.units * scale end
    rec.wins, rec.units = wins, units * scale
    rec.scatterCells = findCells(grid, self.scatter)
    local n = #rec.scatterCells
    local sp = self.scatterPays[math.min(n, 5)]
    if sp then
        rec.scatterUnits = sp * self.levels[level]
        rec.units = rec.units + rec.scatterUnits
    end
    if n >= 3 then rec.freeAdded = self.freeSpins end
    return rec
end

function jade:UnlockedJackpots(level)
    local list = {}
    for _, j in ipairs(self.jackpots) do
        if level >= j.level then list[#list + 1] = j end
    end
    return list
end

-- Chance per spin that the Fu Bat flies, sized so the jackpots return
-- exactly jackpotShare of each level's price (higher levels: more flights,
-- bigger pots - just like the floor machine).
function jade:FuBatChance(level)
    local unlocked = self:UnlockedJackpots(level)
    local wsum, ev = 0, 0
    for _, j in ipairs(unlocked) do wsum = wsum + j.weight end
    for _, j in ipairs(unlocked) do ev = ev + j.coins * j.weight / wsum end
    return self.jackpotShare * self.levels[level] / ev
end

-- The pick-em board: 12 face-down coins; the player flips until three of
-- one jackpot match. The winner is decided up front (weighted over the
-- unlocked tiers); `order` is the sequence the flips reveal, built so every
-- other tier shows at most two and the third winner is the last flip.
function jade:BuildPick(level)
    local unlocked = self:UnlockedJackpots(level)
    local wl = {}
    for _, j in ipairs(unlocked) do wl[#wl + 1] = { j, j.weight } end
    local winner = pickWeighted(wl)
    -- decoys: up to two of every OTHER tier (locked tiers still show, as
    -- on the real machine, so near-misses tease the Grand)
    local pool = {}
    for _, j in ipairs(self.jackpots) do
        if j ~= winner then
            for _ = 1, math.random(0, 2) do pool[#pool + 1] = j.key end
        end
    end
    for i = #pool, 2, -1 do
        local k = math.random(i)
        pool[i], pool[k] = pool[k], pool[i]
    end
    local order = {}
    for _, k in ipairs(pool) do order[#order + 1] = k end
    -- two winners scattered through the decoys, the third closes it out
    for _ = 1, 2 do
        table.insert(order, math.random(#order + 1), winner.key)
    end
    order[#order + 1] = winner.key
    -- the rest of the board (shown after the win) is filler that never
    -- completes a second set
    local counts = {}
    for _, k in ipairs(order) do counts[k] = (counts[k] or 0) + 1 end
    local rest = {}
    while #order + #rest < self.pickCoins do
        local j = self.jackpots[math.random(#self.jackpots)]
        if (counts[j.key] or 0) < 2 then
            counts[j.key] = (counts[j.key] or 0) + 1
            rest[#rest + 1] = j.key
        elseif j == winner then
            -- winner already has 3; pick again
        else
            -- tier full; find any with room
            local found = false
            for _, jj in ipairs(self.jackpots) do
                if jj ~= winner and (counts[jj.key] or 0) < 2 then
                    counts[jj.key] = (counts[jj.key] or 0) + 1
                    rest[#rest + 1] = jj.key
                    found = true
                    break
                end
            end
            if not found then break end
        end
    end
    return { winner = winner.key, order = order, rest = rest,
             label = winner.label, coins = winner.coins }
end

--[[ ============ TEL'ABIM BONANZA (Sweet Bonanza) ============ ]]

local bonanza = register({
    id = "bonanza",
    title = "Tel'Abim Bonanza",
    tagline = "PAY ANYWHERE - TUMBLING WINS - MULTIPLIER BOMBS",
    reels = 6, rows = 5,
    scatter = "idol",
    costCoins = 20,
    minCount = 8,
    maxWinX = 21100,   -- the real machine's cap, x total bet
    theme = {
        bg = { 0.10, 0.03, 0.14 }, bg2 = { 0.95, 0.45, 0.65 },
        border = { 1.0, 0.55, 0.85 }, title = { 1.0, 0.95, 0.4 },
        reel = { 0.25, 0.08, 0.28 }, accent = { 0.45, 0.95, 1.0 },
    },
    symbols = {
        { id = "heart",  name = "Heart Ruby",     icon = ICON .. "INV_Misc_Gem_Ruby_01",     glyph = "RUBY", color = { 1, 0.2, 0.3 } },
        { id = "purple", name = "Amethyst",       icon = ICON .. "INV_Misc_Gem_Amethyst_02", glyph = "AMY",  color = { 0.8, 0.4, 1 } },
        { id = "green",  name = "Emerald",        icon = ICON .. "INV_Misc_Gem_Emerald_01",  glyph = "EMR",  color = { 0.3, 1, 0.4 } },
        { id = "blue",   name = "Sapphire",       icon = ICON .. "INV_Misc_Gem_Sapphire_01", glyph = "SAP",  color = { 0.3, 0.6, 1 } },
        { id = "apple",  name = "Apple",          icon = ICON .. "INV_Misc_Food_19",         glyph = "APL",  color = { 0.9, 0.2, 0.2 } },
        { id = "plum",   name = "Plum",           icon = ICON .. "INV_Misc_Food_02",         glyph = "PLUM", color = { 0.6, 0.3, 0.8 } },
        { id = "melon",  name = "Melon",          icon = ICON .. "INV_Misc_Food_22",         glyph = "MELN", color = { 0.4, 0.9, 0.3 } },
        { id = "grape",  name = "Grapes",         icon = ICON .. "INV_Misc_Food_15",         glyph = "GRPE", color = { 0.5, 0.3, 0.9 } },
        { id = "banana", name = "Tel'Abim Banana", icon = ICON .. "INV_Misc_Food_24",        glyph = "NANA", color = { 1, 0.95, 0.3 } },
        { id = "idol",   name = "Monkey Idol",    icon = ICON .. "INV_Misc_Idol_02",         glyph = "IDOL", color = { 1, 0.75, 0.2 }, scatter = true },
        { id = "bomb",   name = "Multiplier Bomb", icon = ICON .. "INV_Misc_Bomb_05",        glyph = "BOMB", color = { 1, 0.4, 0.1 }, bomb = true },
    },
    -- x total bet by count: 8-9, 10-11, 12+
    pays = {
        heart  = { 10,   25,   50 },
        purple = { 2.5,  10,   25 },
        green  = { 2,    5,    15 },
        blue   = { 1.5,  2,    12 },
        apple  = { 1,    1.5,  10 },
        plum   = { 0.8,  1.2,  8 },
        melon  = { 0.5,  1,    5 },
        grape  = { 0.4,  0.9,  4 },
        banana = { 0.25, 0.75, 2 },
    },
    scatterPays = { [4] = 3, [5] = 5, [6] = 100 },   -- x total bet
    freeSpins = 10, retriggerAt = 3, retriggerAdd = 5, maxFree = 100,
    weights = {
        heart = 3, purple = 4, green = 5, blue = 6, apple = 8, plum = 10,
        melon = 14, grape = 17, banana = 21, idol = 1.5,
    },
    freeWeights = {
        heart = 3, purple = 4, green = 5, blue = 6, apple = 8, plum = 10,
        melon = 14, grape = 17, banana = 21, idol = 1.2, bomb = 1.6,
    },
    bombValues = {
        { 2, 30 }, { 3, 22 }, { 4, 16 }, { 5, 12 }, { 6, 8 }, { 8, 6 }, { 10, 5 },
        { 12, 3 }, { 15, 2.5 }, { 20, 1.8 }, { 25, 1.2 }, { 50, 0.5 }, { 100, 0.2 },
    },
})

do
    local function toList(w)
        local l = {}
        for _, s in ipairs(bonanza.symbols) do
            if w[s.id] then l[#l + 1] = { s.id, w[s.id] } end
        end
        return l
    end
    bonanza.weightList = toList(bonanza.weights)
    bonanza.freeWeightList = toList(bonanza.freeWeights)
end

function bonanza:Draw(free)
    return pickWeighted(free and self.freeWeightList or self.weightList)
end

function bonanza:SpinOnce(free)
    local grid = {}
    for r = 1, self.reels do
        grid[r] = {}
        for row = 1, self.rows do grid[r][row] = self:Draw(free) end
    end
    return grid
end

local function payTier(n)
    if n >= 12 then return 3 elseif n >= 10 then return 2 end
    return 1
end

-- Resolve a whole tumble sequence from a starting grid. Each step records
-- the grid it was evaluated on, its wins, and the cells that burst; bombs
-- (free spins only) stay put and multiply the sequence's win at the end.
function bonanza:Evaluate(grid, free)
    local rec = { grid = grid, tumbles = {}, units = 0, bombs = {} }
    local cur = copyGrid(grid)
    local bombVals = {}   -- "r:row" in the CURRENT grid -> value (moves as things fall)
    local function tagBombs(g, fresh)
        for r = 1, self.reels do
            for row = 1, self.rows do
                if g[r][row] == "bomb" and fresh[key(r, row)] then
                    bombVals[key(r, row)] = pickWeighted(self.bombValues)
                end
            end
        end
    end
    if free then
        local all = {}
        for r = 1, self.reels do for row = 1, self.rows do all[key(r, row)] = true end end
        tagBombs(cur, all)
    end
    rec.firstBombs = {}
    for k, v in pairs(bombVals) do rec.firstBombs[k] = v end

    local seqUnits = 0
    for _ = 1, 50 do
        local counts, cellsBy = {}, {}
        for r = 1, self.reels do
            for row = 1, self.rows do
                local s = cur[r][row]
                if self.pays[s] then
                    counts[s] = (counts[s] or 0) + 1
                    cellsBy[s] = cellsBy[s] or {}
                    table.insert(cellsBy[s], { reel = r, row = row })
                end
            end
        end
        local step = { grid = copyGrid(cur), wins = {}, bombs = {} }
        for k, v in pairs(bombVals) do step.bombs[k] = v end
        local burst = {}
        for _, s in ipairs(self.symbols) do
            local n = counts[s.id]
            if n and n >= self.minCount then
                local units = self.pays[s.id][payTier(n)] * self.costCoins
                step.wins[#step.wins + 1] = { sym = s.id, count = n, units = units, cells = cellsBy[s.id] }
                seqUnits = seqUnits + units
                for _, c in ipairs(cellsBy[s.id]) do burst[key(c.reel, c.row)] = true end
            end
        end
        rec.tumbles[#rec.tumbles + 1] = step
        if #step.wins == 0 then break end
        -- burst, fall, refill from the top
        local nextGrid, newBombs, fresh = {}, {}, {}
        for r = 1, self.reels do
            local keep, keepBomb = {}, {}
            for row = self.rows, 1, -1 do
                if not burst[key(r, row)] then
                    table.insert(keep, 1, cur[r][row])
                    table.insert(keepBomb, 1, bombVals[key(r, row)] or false)
                end
            end
            local missing = self.rows - #keep
            nextGrid[r] = {}
            for row = 1, missing do
                nextGrid[r][row] = self:Draw(free)
                fresh[key(r, row)] = true
            end
            for i, v in ipairs(keep) do
                nextGrid[r][missing + i] = v
                if keepBomb[i] then newBombs[key(r, missing + i)] = keepBomb[i] end
            end
        end
        bombVals = newBombs
        cur = nextGrid
        if free then tagBombs(cur, fresh) end
        step.after = copyGrid(cur)
    end
    rec.final = cur
    rec.finalBombs = bombVals

    -- the sequence's win is multiplied by every bomb on screen at the end
    local bombSum = 0
    for _, v in pairs(bombVals) do bombSum = bombSum + v end
    rec.bombSum = bombSum
    if free and seqUnits > 0 and bombSum > 0 then
        seqUnits = seqUnits * bombSum
        rec.bombApplied = true
    end
    rec.tumbleUnits = seqUnits
    rec.units = seqUnits

    -- scatters pay (and trigger) on the final screen
    rec.scatterCells = findCells(cur, self.scatter)
    local n = #rec.scatterCells
    local sp = self.scatterPays[math.min(n, 6)]
    if sp then
        rec.scatterUnits = sp * self.costCoins
        rec.units = rec.units + rec.scatterUnits
    end
    if free then
        if n >= self.retriggerAt then rec.freeAdded = self.retriggerAdd end
    elseif n >= 4 then
        rec.freeAdded = self.freeSpins
    end
    -- flat list of every win across tumbles (for the UI's summary)
    rec.wins = {}
    for _, st in ipairs(rec.tumbles) do
        for _, w in ipairs(st.wins) do rec.wins[#rec.wins + 1] = w end
    end
    return rec
end

--[[ ============ the shared spin flow ============ ]]

-- Coins a spin costs on this machine at this level (level = coins played on
-- Darkmoon, gold level on Jade, ignored elsewhere).
function Reels:CostCoins(m, level)
    if m.levels then return m.levels[level or 1] end
    if m.maxCoins then return m.costCoins * (level or 1) end
    return m.costCoins
end

function Reels:MaxLevel(m)
    if m.levels then return #m.levels end
    if m.maxCoins then return m.maxCoins end
    return 1
end

-- Test rig (/cc test reels <feature>): one-shot, per machine.
Reels.forceNext = nil

local function forceScatters(m, grid, n)
    local placed = 0
    local reelsOrder = {}
    for r = 1, #grid do reelsOrder[r] = r end
    for _, r in ipairs(reelsOrder) do
        if placed >= n then break end
        local ok = true
        if m.id == "jade" and r > 3 then ok = false end
        if ok then
            grid[r][math.random(#grid[r])] = m.scatter
            placed = placed + 1
        end
    end
end

-- Play one machine spin, start to finish (base game + every free spin +
-- wheel / pick-em). Charges the cost and pays the total immediately.
-- Returns the result, or nil + error.
function Reels:Play(id, coin, level)
    local m = self.byId[id]
    if not m then return nil, "Unknown machine" end
    coin = math.max(1, math.floor(tonumber(coin) or 1))
    level = math.max(1, math.min(self:MaxLevel(m), math.floor(tonumber(level) or 1)))
    local costCoins = self:CostCoins(m, level)
    local cost = costCoins * coin
    if not Arcade:Spend(cost) then return nil, "Not enough credits" end

    local force = self.forceNext
    if force and force.id ~= id then force = nil end
    if force then self.forceNext = nil end

    local result = { id = id, coin = coin, level = level, cost = cost,
                     costCoins = costCoins, free = {} }

    -- base spin
    local grid = m:SpinOnce(false)
    if force and force.kind == "free" and m.scatter then
        local n = (m.id == "bonanza") and 4 or 3
        for r = 1, #grid do
            for row = 1, #grid[r] do
                if grid[r][row] == m.scatter then grid[r][row] = m.symbols[1].id end
            end
        end
        forceScatters(m, grid, n)
    elseif force and force.kind == "wheel" and m.id == "darkmoon" then
        grid[3][2] = "spin"
    end
    local base = m:Evaluate(grid, false, level)
    base.credits = toCredits(base.units, coin)
    result.base = base
    local total = base.credits

    -- free spins (any machine that has them)
    local freeLeft = base.freeAdded or 0
    if freeLeft > 0 then
        result.freeAwarded = freeLeft
        local played, cap = 0, m.maxFree or 100
        local freeTotal = 0
        while freeLeft > 0 and played < cap do
            freeLeft = freeLeft - 1
            played = played + 1
            local g = m:SpinOnce(true)
            local rec = m:Evaluate(g, true, level)
            rec.credits = toCredits(rec.units, coin)
            if rec.freeAdded and rec.freeAdded > 0 then
                local room = cap - (played + freeLeft)
                rec.freeAdded = math.max(0, math.min(rec.freeAdded, room))
                freeLeft = freeLeft + rec.freeAdded
            end
            rec.index = played
            result.free[#result.free + 1] = rec
            freeTotal = freeTotal + rec.credits
        end
        result.freeTotal = freeTotal
        total = total + freeTotal
    end

    -- Darkmoon: the SPIN symbol turns the wheel, only at max coins
    if m.id == "darkmoon" and base.spinSymbol then
        if level == m.maxCoins then
            local idx = nil
            local list = {}
            for i, w in ipairs(m.wheel) do list[i] = { i, w[2] } end
            idx = pickWeighted(list)
            result.wheel = { index = idx, coins = m.wheel[idx][1],
                             credits = m.wheel[idx][1] * coin }
            total = total + result.wheel.credits
        else
            result.wheelMissed = true   -- SPIN landed but not at max coins
        end
    end

    -- Jade: the Fu Bat may fly after any paid spin
    if m.id == "jade" then
        local fly = (force and force.kind == "pick") or (math.random() < m:FuBatChance(level))
        if fly then
            local pick = m:BuildPick(level)
            pick.credits = pick.coins * coin
            result.pick = pick
            total = total + pick.credits
        end
    end

    -- the real machine's max-win cap
    if m.maxWinX and total > m.maxWinX * cost then
        total = m.maxWinX * cost
        result.capped = true
    end

    result.total = total
    if total > 0 then Arcade:Award(total) end

    local db = Arcade:GetDB()
    db.reels = db.reels or {}
    local st = db.reels[id] or {}
    db.reels[id] = st
    st.spins = (st.spins or 0) + 1
    st.wagered = (st.wagered or 0) + cost
    st.won = (st.won or 0) + total
    if total > (st.best or 0) then st.best = total end
    return result
end

function Reels:GetStats(id)
    local db = Arcade:GetDB()
    return (db.reels and db.reels[id]) or {}
end
