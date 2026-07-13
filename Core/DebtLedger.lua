--[[
    Chairface's Casino - DebtLedger.lua
    Cross-game session debt tracker ("the tab").

    Every multiplayer game reports its settlement here from the same
    host-gated spot where it records leaderboard results. Debts accumulate
    per player pair and net against each other across games, so after a
    night of gambling each pair has a single "A owes B Xg" balance.

    Gold handed over in a trade window between two players is detected and
    applied against their debt automatically (payer broadcasts it so the
    whole group's ledgers agree). Creditors can forgive debts by hand.
    Balances persist in ChairfacesCasinoDB until paid, forgiven, or reset.

    FAKE PLAY: with the toggle on, a game HOST records and broadcasts no
    debts at all - friends playing for nothing. Only the host's setting
    matters (recording is host-side), and the table gets a one-line
    notice per settlement so everyone knows the round was off the books.

    Wire protocol (prefix CCDebtLedger, "|"-delimited like other modules):
      ADD|game|debtor,creditor,amt;...   host broadcasts a game's settlement
      PAY|payer|payee|amt                payer broadcasts a detected trade payment
      FORGIVE|debtor|creditor            creditor forgives a debt
      FUN|game                           host settled a round with fake play on
      SYNC_REQ                           ask the group for their ledgers
      SYNC_FULL|a,b,balance,updated;...  whispered reply; newest update wins
]]

local BJ = ChairfacesCasino
BJ.DebtLedger = {}
local DL = BJ.DebtLedger

local CHANNEL_PREFIX = "CCDebtLedger"
local AceComm = LibStub("AceComm-3.0")

local MSG = {
    ADD = "ADD",
    PAY = "PAY",
    FORGIVE = "FORGIVE",
    FUN = "FUN",
    SYNC_REQ = "SYNC_REQ",
    SYNC_FULL = "SYNC_FULL",
}

-- Paid-off pairs are kept for a while as zero-balance tombstones so a late
-- SYNC_FULL from a stale client can't resurrect a debt that was settled
local TOMBSTONE_SECONDS = 7 * 24 * 60 * 60
local HISTORY_CAP = 12
local SYNC_PAIR_CAP = 80

-- Display names for the per-entry history tooltip
DL.GAME_LABELS = {
    blackjack = "Blackjack",
    poker = "5 Card Stud",
    holdem = "Texas Hold'em",
    hilo = "High-Lo",
    deathroll = "Death Roll",
    bingo = "Bingo",
    roulette = "Roulette",
    liarsdice = "Liar's Dice",
    crash = "Crash",
    derby = "Chair's Cup",
    trade = "Trade",
    manual = "Manual",
}

DL.data = nil  -- points at ChairfacesCasinoDB.debtLedger after Initialize

--[[
    ============================================
    HELPERS
    ============================================
]]

-- Balances live in gold; round to the silver (0.01g) to avoid float drift
local function Round2(x)
    return math.floor(x * 100 + 0.5) / 100
end

-- Full "Name-Realm" form, same convention as Leaderboard.lua
local function NormalizeName(name)
    if not name or name == "" then return nil end
    if not name:find("-") then
        name = name .. "-" .. (GetRealmName() or "")
    end
    return name
end

function DL:ShortName(full)
    if not full then return "?" end
    local name, realm = full:match("^([^-]+)-?(.*)$")
    if not name then return full end
    if realm == "" or realm == (GetRealmName() or "") then return name end
    return full
end

-- One entry per unordered pair; key is the two full names sorted.
-- entry.balance > 0 means entry.a owes entry.b; < 0 means b owes a.
local function PairKey(n1, n2)
    if n1 < n2 then return n1 .. "~" .. n2 end
    return n2 .. "~" .. n1
end

function DL:GetEntry(n1, n2, create)
    if not self.data then return nil end
    local key = PairKey(n1, n2)
    local e = self.data.pairs[key]
    if not e and create then
        local a, b = n1, n2
        if b < a then a, b = b, a end
        e = { a = a, b = b, balance = 0, updated = 0, history = {} }
        self.data.pairs[key] = e
    end
    return e, key
end

local function AddHistory(e, kind, game, from, to, amt)
    e.history = e.history or {}
    table.insert(e.history, 1, {
        t = time(), kind = kind, game = game, from = from, to = to, amt = Round2(amt),
    })
    while #e.history > HISTORY_CAP do
        table.remove(e.history)
    end
end

-- A pair SETTLED square (paid off or forgiven) starts its history over:
-- the tooltip only ever tells the current debt's story. Game debts that
-- merely NET to zero keep theirs - the back-and-forth is exactly what
-- explains the current balance, so only ApplyPayment/ApplyForgive (and
-- synced tombstones) call this, never ApplyDebt.
local function ResetHistoryIfSquare(e)
    if math.abs(e.balance or 0) < 0.01 then
        e.history = {}
    end
end

--[[
    ============================================
    LOCAL LEDGER MUTATIONS
    ============================================
]]

-- How much `debtor` currently owes `creditor` on their shared tab
function DL:GetOwed(debtor, creditor)
    local e = self:GetEntry(debtor, creditor, false)
    if not e then return 0 end
    if debtor == e.a then return math.max(e.balance, 0) end
    return math.max(-e.balance, 0)
end

function DL:ApplyDebt(game, debtor, creditor, amount)
    amount = Round2(tonumber(amount) or 0)
    if amount <= 0 or not debtor or not creditor or debtor == creditor then return end
    local e = self:GetEntry(debtor, creditor, true)
    if debtor == e.a then
        e.balance = Round2(e.balance + amount)
    else
        e.balance = Round2(e.balance - amount)
    end
    e.updated = time()
    AddHistory(e, "debt", game, debtor, creditor, amount)
end

-- Apply a payment against an existing debt, capped at what is actually owed
-- (overpaying in a trade is a gift, not a credit). Returns the amount applied.
function DL:ApplyPayment(payer, payee, amount)
    amount = Round2(tonumber(amount) or 0)
    if amount <= 0 then return 0 end
    local owed = self:GetOwed(payer, payee)
    if owed < 0.01 then return 0 end
    local applied = math.min(amount, owed)
    local e = self:GetEntry(payer, payee, true)
    if payer == e.a then
        e.balance = Round2(e.balance - applied)
    else
        e.balance = Round2(e.balance + applied)
    end
    e.updated = time()
    AddHistory(e, "pay", "trade", payer, payee, applied)
    ResetHistoryIfSquare(e)
    return applied
end

-- Zero out what `debtor` owes `creditor`. Returns the forgiven amount.
function DL:ApplyForgive(debtor, creditor)
    local owed = self:GetOwed(debtor, creditor)
    if owed < 0.01 then return 0 end
    local e = self:GetEntry(debtor, creditor, true)
    if debtor == e.a then
        e.balance = Round2(e.balance - owed)
    else
        e.balance = Round2(e.balance + owed)
    end
    e.updated = time()
    AddHistory(e, "forgive", "manual", debtor, creditor, owed)
    ResetHistoryIfSquare(e)
    return owed
end

--[[
    ============================================
    GAME-FACING API (call from the host-gated settlement spot)
    ============================================
]]

-- Fake play: games hosted by this client record no debts
function DL:IsFakePlay()
    return BJ.db and BJ.db.settings and BJ.db.settings.fakePlay or false
end

function DL:SetFakePlay(enabled)
    if not BJ.db then return end
    BJ.db.settings = BJ.db.settings or {}
    BJ.db.settings.fakePlay = enabled and true or nil
    if enabled then
        BJ:Print("|cffffff00Fake play ON|r - games you host record no debts. Toggle on /cc debts or /cc fakeplay.")
    else
        BJ:Print("|cff00ff00Fake play OFF|r - games you host record real debts again.")
    end
    local lobby = BJ.UI and BJ.UI.Lobby
    if lobby and lobby.IsAnyGameActive and lobby:IsAnyGameActive() then
        BJ:Print("|cff888888A table is in progress - it keeps the terms it opened with; the change applies to tables hosted from now on.|r")
    end
    self:NotifyChanged()
end

-- Record a batch of debts from one game round and broadcast to the group.
-- list entries: { debtor = name, creditor = name, amount = gold }
-- fakePlay (optional): explicit fun/real status for this round. Every game
-- passes the status its table OPENED with, so nobody's mid-game toggle -
-- the opener's included, or a migrated host's - can flip a real table fun
-- (or a fun table real); flipping the toggle only affects tables hosted
-- from then on. nil (legacy/unknown terms) = the recorder's live setting.
function DL:RecordDebts(game, list, fakePlay)
    if not self.data then return end
    if fakePlay == nil then fakePlay = self:IsFakePlay() end

    -- fun games are off the books: no debts, one notice to the table
    if fakePlay then
        if list and #list > 0 then
            self:Send(MSG.FUN, game)
            BJ:Print("|cff888888Fun game - fake play is on, no debts recorded.|r")
        end
        return
    end

    local wire, entries = {}, {}
    for _, d in ipairs(list or {}) do
        local debtor, creditor = NormalizeName(d.debtor), NormalizeName(d.creditor)
        local amount = Round2(tonumber(d.amount) or 0)
        if debtor and creditor and debtor ~= creditor and amount > 0 then
            self:ApplyDebt(game, debtor, creditor, amount)
            table.insert(wire, debtor .. "," .. creditor .. "," .. amount)
            table.insert(entries, { debtor = debtor, creditor = creditor, amount = amount })
        end
    end
    if #wire == 0 then return end
    self:Send(MSG.ADD, game, table.concat(wire, ";"))
    self:AnnounceGameDebts(entries)
    self:NotifyChanged()
end

function DL:RecordDebt(game, debtor, creditor, amount, fakePlay)
    self:RecordDebts(game, { { debtor = debtor, creditor = creditor, amount = amount } }, fakePlay)
end

-- Turn a zero-sum table of per-player nets ({ name = net }) into pairwise
-- debts: biggest loser pays biggest winner first. Deterministic, and for a
-- single winner it reduces to "each loser owes the winner their loss".
function DL:RecordNets(game, nets, fakePlay)
    local debtors, creditors = {}, {}
    for name, net in pairs(nets or {}) do
        net = Round2(tonumber(net) or 0)
        if net < 0 then
            table.insert(debtors, { name = name, amt = -net })
        elseif net > 0 then
            table.insert(creditors, { name = name, amt = net })
        end
    end
    local byAmt = function(x, y)
        if x.amt ~= y.amt then return x.amt > y.amt end
        return x.name < y.name
    end
    table.sort(debtors, byAmt)
    table.sort(creditors, byAmt)

    local debts, i, j = {}, 1, 1
    while i <= #debtors and j <= #creditors do
        local d, c = debtors[i], creditors[j]
        local x = math.min(d.amt, c.amt)
        if x >= 0.01 then
            table.insert(debts, { debtor = d.name, creditor = c.name, amount = x })
        end
        d.amt = Round2(d.amt - x)
        c.amt = Round2(c.amt - x)
        if d.amt < 0.01 then i = i + 1 end
        if c.amt < 0.01 then j = j + 1 end
    end
    if #debts > 0 then
        self:RecordDebts(game, debts, fakePlay)
    end
end

-- One compact chat line per counterparty whose tab with you just moved
function DL:AnnounceGameDebts(entries)
    local me = NormalizeName(UnitName("player"))
    local seen = {}
    for _, d in ipairs(entries) do
        local other
        if d.debtor == me then
            other = d.creditor
        elseif d.creditor == me then
            other = d.debtor
        end
        if other and not seen[other] then
            seen[other] = true
            local iOwe = self:GetOwed(me, other)
            local theyOwe = self:GetOwed(other, me)
            if iOwe >= 0.01 then
                BJ:Print("Tab: you owe " .. self:ShortName(other) .. " " .. BJ:FormatGold(iOwe) .. " (|cff88ff88/cc debts|r)")
            elseif theyOwe >= 0.01 then
                BJ:Print("Tab: " .. self:ShortName(other) .. " owes you " .. BJ:FormatGold(theyOwe))
            else
                BJ:Print("Tab: you're square with " .. self:ShortName(other))
            end
        end
    end
end

--[[
    ============================================
    UI-FACING QUERIES / ACTIONS
    ============================================
]]

-- All outstanding debts, biggest first: { debtor, creditor, amount, entry }
function DL:GetAllDebts()
    local out = {}
    if not self.data then return out end
    for key, e in pairs(self.data.pairs) do
        local bal = e.balance or 0
        if bal >= 0.01 then
            table.insert(out, { debtor = e.a, creditor = e.b, amount = bal, key = key, entry = e })
        elseif bal <= -0.01 then
            table.insert(out, { debtor = e.b, creditor = e.a, amount = -bal, key = key, entry = e })
        end
    end
    table.sort(out, function(x, y)
        if x.amount ~= y.amount then return x.amount > y.amount end
        if x.debtor ~= y.debtor then return x.debtor < y.debtor end
        return x.creditor < y.creditor
    end)
    return out
end

-- Your side of the ledger: what you owe, and what is owed to you
function DL:GetMyDebts()
    local me = NormalizeName(UnitName("player"))
    local iOwe, owedToMe = {}, {}
    for _, d in ipairs(self:GetAllDebts()) do
        if d.debtor == me then
            table.insert(iOwe, { name = d.creditor, amount = d.amount, entry = d.entry })
        elseif d.creditor == me then
            table.insert(owedToMe, { name = d.debtor, amount = d.amount, entry = d.entry })
        end
    end
    return iOwe, owedToMe
end

function DL:GetMyTotals()
    local iOwe, owedToMe = self:GetMyDebts()
    local o, w = 0, 0
    for _, d in ipairs(iOwe) do o = o + d.amount end
    for _, d in ipairs(owedToMe) do w = w + d.amount end
    return Round2(o), Round2(w)
end

-- Forgive what `debtorFull` owes you and tell the group
function DL:Forgive(debtorFull)
    local me = NormalizeName(UnitName("player"))
    local debtor = NormalizeName(debtorFull)
    if not debtor then return end
    local amt = self:ApplyForgive(debtor, me)
    if amt > 0 then
        self:Send(MSG.FORGIVE, debtor, me)
        BJ:Print("Forgave " .. self:ShortName(debtor) .. "'s " .. BJ:FormatGold(amt) .. " debt.")
        self:NotifyChanged()
    end
end

-- Wipe the local ledger (does not touch anyone else's)
function DL:ResetLedger()
    if not self.data then return end
    self.data.pairs = {}
    BJ:Print("Debt ledger cleared (yours only - other players keep theirs).")
    self:NotifyChanged()
end

function DL:NotifyChanged()
    local DF = BJ.UI and BJ.UI.Debts
    if not DF then return end
    if DF.UpdateFakePlayChecks then
        DF:UpdateFakePlayChecks()
    end
    if DF.Refresh then
        DF:Refresh()
    end
end

--[[
    ============================================
    NETWORK
    ============================================
]]

function DL:Send(msgType, ...)
    local parts = { msgType, ... }
    for i, v in ipairs(parts) do
        parts[i] = tostring(v)
    end
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if channel then
        AceComm:SendCommMessage(CHANNEL_PREFIX, table.concat(parts, "|"), channel)
    end
end

function DL:SendWhisper(target, msgType, ...)
    local parts = { msgType, ... }
    for i, v in ipairs(parts) do
        parts[i] = tostring(v)
    end
    AceComm:SendCommMessage(CHANNEL_PREFIX, table.concat(parts, "|"), "WHISPER", target)
end

function DL:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= CHANNEL_PREFIX or not self.data then return end
    local senderFull = NormalizeName(sender)
    local me = NormalizeName(UnitName("player"))
    if senderFull == me then return end

    local parts = { strsplit("|", message) }
    local msgType = parts[1]

    if msgType == MSG.ADD then
        self:HandleAdd(senderFull, parts[2], parts[3])
    elseif msgType == MSG.PAY then
        self:HandlePay(senderFull, parts[2], parts[3], parts[4])
    elseif msgType == MSG.FORGIVE then
        self:HandleForgive(senderFull, parts[2], parts[3])
    elseif msgType == MSG.FUN then
        local label = self.GAME_LABELS[parts[2]] or parts[2] or "?"
        BJ:Print("|cff888888" .. label .. ": fun game - the host has fake play on, no debts recorded.|r")
    elseif msgType == MSG.SYNC_REQ then
        self:HandleSyncRequest(sender)
    elseif msgType == MSG.SYNC_FULL then
        self:HandleSyncFull(parts[2])
    end
end

function DL:HandleAdd(sender, game, entriesStr)
    local entries = {}
    for chunk in string.gmatch(entriesStr or "", "[^;]+") do
        local debtor, creditor, amt = strsplit(",", chunk)
        debtor, creditor, amt = NormalizeName(debtor), NormalizeName(creditor), tonumber(amt)
        if debtor and creditor and debtor ~= creditor and amt and amt > 0 then
            self:ApplyDebt(game or "?", debtor, creditor, amt)
            table.insert(entries, { debtor = debtor, creditor = creditor, amount = amt })
        end
    end
    if #entries > 0 then
        self:AnnounceGameDebts(entries)
        self:NotifyChanged()
    end
end

function DL:HandlePay(sender, payer, payee, amt)
    payer, payee, amt = NormalizeName(payer), NormalizeName(payee), tonumber(amt)
    if not payer or not payee or not amt then return end
    local me = NormalizeName(UnitName("player"))
    -- Trade participants applied the payment from the trade window itself
    if payer == me or payee == me then return end
    -- Only the payer may report their own payment
    if sender ~= payer then return end
    if self:ApplyPayment(payer, payee, amt) > 0 then
        self:NotifyChanged()
    end
end

function DL:HandleForgive(sender, debtor, creditor)
    debtor, creditor = NormalizeName(debtor), NormalizeName(creditor)
    if not debtor or not creditor then return end
    -- Only the creditor can forgive what they are owed
    if sender ~= creditor then return end
    local amt = self:ApplyForgive(debtor, creditor)
    if amt > 0 then
        local me = NormalizeName(UnitName("player"))
        if debtor == me then
            BJ:Print(self:ShortName(creditor) .. " forgave your " .. BJ:FormatGold(amt) .. " debt.")
        end
        self:NotifyChanged()
    end
end

function DL:RequestSync()
    self:Send(MSG.SYNC_REQ)
end

function DL:HandleSyncRequest(requester)
    local chunks = {}
    for _, e in pairs(self.data.pairs) do
        table.insert(chunks, e.a .. "," .. e.b .. "," .. (e.balance or 0) .. "," .. (e.updated or 0))
        if #chunks >= SYNC_PAIR_CAP then break end
    end
    if #chunks > 0 then
        self:SendWhisper(requester, MSG.SYNC_FULL, table.concat(chunks, ";"))
    end
end

-- Merge a peer's ledger: per pair, the newest `updated` timestamp wins.
-- Zero-balance tombstones we hold locally beat older nonzero copies, which
-- is what stops a paid-off debt from coming back.
function DL:HandleSyncFull(entriesStr)
    local changed = false
    for chunk in string.gmatch(entriesStr or "", "[^;]+") do
        local a, b, balance, updated = strsplit(",", chunk)
        a, b = NormalizeName(a), NormalizeName(b)
        balance, updated = tonumber(balance), tonumber(updated)
        if a and b and a ~= b and balance and updated then
            local e = self:GetEntry(a, b, false)
            local take = false
            if not e then
                take = math.abs(balance) >= 0.01
            else
                take = updated > (e.updated or 0)
            end
            if take then
                e = self:GetEntry(a, b, true)
                -- sender's entry is stored against the same sorted a/b pair
                e.balance = Round2(balance)
                e.updated = updated
                ResetHistoryIfSquare(e)
                changed = true
            end
        end
    end
    if changed then
        self:NotifyChanged()
    end
end

--[[
    ============================================
    SETTLE BY TRADE (the button)
    ============================================
]]

-- Group unit token for a full "Name-Realm", nil if they're not in the group
local function UnitTokenFor(fullName)
    local num = GetNumGroupMembers()
    for i = 1, num do
        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
        if UnitExists(unit) then
            local n, r = UnitName(unit)
            if n then
                local full = n .. "-" .. ((r and r ~= "") and r or (GetRealmName() or ""))
                if full == fullName then return unit end
            end
        end
    end
    return nil
end

-- Open a trade with a creditor standing nearby and pre-fill exactly what
-- you owe them; the player just confirms the trade to settle the tab.
function DL:SettleWithTrade(creditorFull)
    local me = NormalizeName(UnitName("player"))
    local creditor = NormalizeName(creditorFull)
    if not creditor then return end

    local owed = self:GetOwed(me, creditor)
    if owed < 0.01 then
        BJ:Print("You don't owe " .. self:ShortName(creditor) .. " anything.")
        return
    end

    local unit = UnitTokenFor(creditor)
    if not unit then
        BJ:Print(self:ShortName(creditor) .. " must be in your group to settle by trade.")
        return
    end

    -- range check where the client allows it (trade range is ~11yd);
    -- if the check is unavailable just try - the server enforces range
    local ok, near = pcall(CheckInteractDistance, unit, 2)
    if ok and near == false then
        BJ:Print(self:ShortName(creditor) .. " is too far away to trade - walk over and try again.")
        return
    end

    self.autoFill = { partner = creditor, copper = math.floor(owed * 10000 + 0.5), at = GetTime() }
    InitiateTrade(unit)
end

--[[
    ============================================
    TRADE DETECTION
    ============================================
    Snapshot the gold on both sides while the trade window is open, then
    commit when the client confirms "Trade complete." (UI_INFO_MESSAGE).
    Both participants apply the payment locally; only the payer broadcasts,
    and receivers who were in the trade skip the echo.
]]

-- Put `copper` into the trade. The C call SetTradeMoney is what actually
-- stages the gold in the trade - it involves no UI widgets, so it is done
-- FIRST and cannot fail. Reflecting the amount in the input boxes is pure
-- cosmetics on top, and every route into those widgets has broken on some
-- client/addon mix (Blizzard's own MoneyInputFrame_SetCopper errors, and
-- trade addons hijack the name-composed globals with wrapper tables that
-- throw "bad self"), so the boxes are poked through their XML parentKey
-- references with every call pcall'd - a cosmetic miss never costs gold.
-- Returns true only if the gold VERIFIABLY landed in the trade
-- (GetPlayerTradeMoney reflects staged money synchronously); the input
-- boxes are only poked after that, so the UI never shows gold that isn't
-- really offered.
local function FillTradeMoney(copper)
    if SetTradeMoney then
        SetTradeMoney(copper)
    end
    local staged = GetPlayerTradeMoney and (tonumber(GetPlayerTradeMoney()) or 0) or 0
    if staged < copper then
        return false
    end

    local frame = _G["TradePlayerInputMoneyFrame"]
    if frame then
        local gold = math.floor(copper / 10000)
        local silver = math.floor((copper % 10000) / 100)
        local function poke(box, amount)
            if box and box.SetText then
                pcall(box.SetText, box, amount > 0 and tostring(amount) or "")
                if box.ClearFocus then
                    pcall(box.ClearFocus, box)
                end
            end
        end
        poke(frame.gold, gold)
        poke(frame.silver, silver)
    end
    return true
end

-- Addons CANNOT stage trade gold on modern clients: SetTradeMoney is
-- flagged AllowedWhenUntainted, so any call from addon code - hardware
-- event or not - is silently ignored (anti-scam hardening; the money
-- input widgets reject addon writes the same way). Typing is the only
-- path that works everywhere. The settle flow therefore makes the amount
-- unmissable instead: a banner pinned above the trade window plus a chat
-- line, with FillTradeMoney still tried first because it is free and on
-- any client where it isn't blocked the gold simply appears.
function DL:GetTradeBanner()
    if self.tradeBanner then return self.tradeBanner end
    local tradeFrame = _G["TradeFrame"]
    if not tradeFrame then return nil end

    local banner = CreateFrame("Frame", "ChairfacesCasinoTradeBanner", tradeFrame, "BackdropTemplate")
    banner:SetSize(230, 26)
    banner:SetPoint("BOTTOMLEFT", tradeFrame, "TOPLEFT", 4, 2)
    banner:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    banner:SetBackdropColor(0.08, 0.06, 0.02, 0.95)
    banner:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
    banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    banner.text:SetPoint("CENTER")
    self.tradeBanner = banner
    return banner
end

function DL:ShowTradeBanner(amountStr)
    local banner = self:GetTradeBanner()
    if not banner then return false end
    banner.text:SetText("Settle: type |cffffd700" .. amountStr .. "|r in the trade")
    banner:Show()
    return true
end

function DL:OnTradeShow()
    local name, realm = UnitName("NPC")
    if not name then return end
    local partner
    if realm and realm ~= "" then
        partner = name .. "-" .. realm
    else
        partner = NormalizeName(name)
    end
    self.trade = { partner = partner, give = 0, get = 0 }

    -- a Settle click queued this trade: try the free fill, then make the
    -- amount to type unmissable
    local fill = self.autoFill
    self.autoFill = nil
    if fill and fill.partner == partner and (GetTime() - (fill.at or 0)) < 20 then
        local amountStr = BJ:FormatGold(fill.copper / 10000)
        if FillTradeMoney(fill.copper) then
            BJ:Print(amountStr .. " placed in the trade for " ..
                self:ShortName(partner) .. " - confirm to settle your tab.")
        else
            self:ShowTradeBanner(amountStr)
            BJ:Print("Type |cffffd700" .. amountStr .. "|r into the trade - the tab clears itself when the trade completes.")
        end
        return
    end

    -- any other trade with a creditor still gets the reminder
    local me = NormalizeName(UnitName("player"))
    local owed = self:GetOwed(me, partner)
    if owed >= 0.01 then
        self:ShowTradeBanner(BJ:FormatGold(owed))
        BJ:Print("You owe " .. self:ShortName(partner) .. " " .. BJ:FormatGold(owed) .. " - gold in this trade settles your tab.")
    end
end

function DL:OnTradeMoneyChanged()
    if not self.trade then return end
    self.trade.give = tonumber(GetPlayerTradeMoney()) or 0
    self.trade.get = tonumber(GetTargetTradeMoney()) or 0
end

function DL:OnTradeClosed()
    self.autoFill = nil
    if self.tradeBanner then
        self.tradeBanner:Hide()
    end
    if not self.trade then return end
    self.trade.closedAt = GetTime()
    self.pendingTrade = self.trade
    self.trade = nil
end

function DL:OnTradeComplete()
    local t = self.pendingTrade
    self.pendingTrade = nil
    if not t or not t.partner then return end
    if (GetTime() - (t.closedAt or 0)) > 5 then return end

    local me = NormalizeName(UnitName("player"))
    local netCopper = (t.give or 0) - (t.get or 0)
    local gold = Round2(math.abs(netCopper) / 10000)
    if gold < 0.01 then return end

    local payer, payee
    if netCopper > 0 then
        payer, payee = me, t.partner
    else
        payer, payee = t.partner, me
    end

    local applied = self:ApplyPayment(payer, payee, gold)
    if applied > 0 then
        local remaining = self:GetOwed(payer, payee)
        local tail = remaining >= 0.01
            and (" (" .. BJ:FormatGold(remaining) .. " still owed)")
            or " - all square!"
        local lobby = BJ.UI and BJ.UI.Lobby
        if payer == me then
            self:Send(MSG.PAY, payer, payee, applied)
            BJ:Print("Debt paid: " .. BJ:FormatGold(applied) .. " to " .. self:ShortName(payee) .. tail)
            if lobby and lobby.PlayTrixieVoice then lobby:PlayTrixieVoice("debt", { cd = 10 }) end
        else
            BJ:Print("Debt payment received: " .. BJ:FormatGold(applied) .. " from " .. self:ShortName(payer) .. tail)
            if lobby and lobby.PlayTrixieVoice then lobby:PlayTrixieVoice("paid", { cd = 10 }) end
        end
        self:NotifyChanged()
    end
end

--[[
    ============================================
    LIFECYCLE
    ============================================
]]

function DL:Prune()
    if not self.data then return end
    local now = time()
    for key, e in pairs(self.data.pairs) do
        if math.abs(e.balance or 0) < 0.01 and now - (e.updated or 0) > TOMBSTONE_SECONDS then
            self.data.pairs[key] = nil
        end
    end
end

function DL:Initialize()
    -- Never trust BJ.db to be set this early: OnAddonLoaded historically
    -- never fired (ADDON_LOADED name mismatch), so like MinimapButton we
    -- attach to the saved-vars global ourselves. Bailing out here silently
    -- killed all debt recording.
    if not BJ.db then
        ChairfacesCasinoDB = ChairfacesCasinoDB or {}
        BJ.db = ChairfacesCasinoDB
    end
    BJ.db.debtLedger = BJ.db.debtLedger or { pairs = {} }
    self.data = BJ.db.debtLedger
    self.data.pairs = self.data.pairs or {}
    self:Prune()

    AceComm:RegisterComm(CHANNEL_PREFIX, function(prefix, message, distribution, sender)
        DL:OnCommReceived(prefix, message, distribution, sender)
    end)

    local f = CreateFrame("Frame")
    f:RegisterEvent("TRADE_SHOW")
    f:RegisterEvent("TRADE_MONEY_CHANGED")
    f:RegisterEvent("TRADE_ACCEPT_UPDATE")
    f:RegisterEvent("TRADE_CLOSED")
    f:RegisterEvent("UI_INFO_MESSAGE")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "TRADE_SHOW" then
            DL:OnTradeShow()
        elseif event == "TRADE_MONEY_CHANGED" or event == "TRADE_ACCEPT_UPDATE" then
            DL:OnTradeMoneyChanged()
        elseif event == "TRADE_CLOSED" then
            DL:OnTradeClosed()
        elseif event == "UI_INFO_MESSAGE" then
            -- Older clients pass just the message; newer pass (type, message)
            local text = arg2 or arg1
            if text == ERR_TRADE_COMPLETE then
                DL:OnTradeComplete()
            elseif text == ERR_TRADE_CANCELLED then
                DL.pendingTrade = nil
            end
        elseif event == "GROUP_ROSTER_UPDATE" then
            local inGroup = IsInGroup() or IsInRaid()
            if inGroup and not DL.wasInGroup then
                C_Timer.After(2, function() DL:RequestSync() end)
            end
            DL.wasInGroup = inGroup
        end
    end)
    self.eventFrame = f

    if IsInGroup() or IsInRaid() then
        self.wasInGroup = true
        C_Timer.After(5, function() DL:RequestSync() end)
    end

    -- sync any fake-play checkboxes built before this ran (Derby's UI
    -- is constructed at file load, before saved variables attach)
    self:NotifyChanged()

    BJ:Debug("DebtLedger initialized")
end

--[[
    ============================================
    TEST HARNESS (/cc test debt ..., gated by TestMode)
    ============================================
]]

function DL:TestCommand(arg)
    if not (BJ.TestMode and BJ.TestMode.enabled) then return end
    local cmd, a, b, c = strsplit(" ", arg or "")
    local me = UnitName("player")

    if cmd == "add" then
        -- /cc test debt add <debtor> [creditor] <amount>  (creditor defaults to you)
        local debtor, creditor, amt = a, b, tonumber(c)
        if not amt then
            amt, creditor = tonumber(b), me
        end
        if debtor and creditor and amt then
            self:RecordDebts("manual", { { debtor = debtor, creditor = creditor, amount = amt } })
        else
            BJ:Print("Usage: /cc test debt add <debtor> [creditor] <amount>")
        end
    elseif cmd == "pay" then
        -- /cc test debt pay <payer> [payee] <amount>  (payee defaults to you)
        local payer, payee, amt = a, b, tonumber(c)
        if not amt then
            amt, payee = tonumber(b), me
        end
        if payer and payee and amt then
            local applied = self:ApplyPayment(NormalizeName(payer), NormalizeName(payee), amt)
            BJ:Print("Test payment applied: " .. BJ:FormatGold(applied))
            if applied > 0 then self:NotifyChanged() end
        else
            BJ:Print("Usage: /cc test debt pay <payer> [payee] <amount>")
        end
    elseif cmd == "list" then
        local debts = self:GetAllDebts()
        if #debts == 0 then
            BJ:Print("Ledger is empty.")
        end
        for _, d in ipairs(debts) do
            BJ:Print(self:ShortName(d.debtor) .. " owes " .. self:ShortName(d.creditor) .. " " .. BJ:FormatGold(d.amount))
        end
    elseif cmd == "wipe" then
        self:ResetLedger()
    else
        BJ:Print("Debt test commands: add, pay, list, wipe")
    end
end
