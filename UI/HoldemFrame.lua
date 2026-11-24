--[[
    Chairface's Casino - UI/HoldemFrame.lua
    Texas Hold'em: the shared poker table (UI/PokerTable.lua) plus Hold'em's
    rules - the community board, blinds and the dealer button, NEXT HAND,
    and tournament mode (buy-in, chip stacks, winner-take-all).
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

local Holdem = UI.PokerTable:Embed({}, {
    key = "holdem",
    name = "Texas Hold'em",
    state = "HoldemState",
    net = "HoldemMultiplayer",
    prefix = "Holdem",
    frameName = "ChairfacesCasinoHoldem",
    logFrameName = "CasinoHoldemLogFrame",
    resetPopup = "CASINO_HOLDEM_RESET",
    -- layout: the board takes the middle of the dealer area
    potLeft = true,
    settlementTop = -170,      -- below the community cards (they end at y -165)
    settlementMaxH = 300,      -- stops above the bottom-right reset button
    hostPanelHeight = 440,     -- fits the tournament block
    anteLabel = "Big Blind (2-1000g):",
    anteMin = 2,               -- the small blind is half, so >= 1
})
UI.Holdem = Holdem

-- ===== The board =====

function Holdem:CreateDealerExtras(dealerArea)
    -- Shared community cards (flop/turn/river) - a centered row of 5 slots
    local communityRow = CreateFrame("Frame", nil, dealerArea)
    local cw = UI.Cards.CARD_WIDTH or 64
    local ch = UI.Cards.CARD_HEIGHT or 90
    local gap = 8
    communityRow:SetSize(cw * 5 + gap * 4, ch)
    communityRow:SetPoint("CENTER", dealerArea, "CENTER", 60, 0)
    self.communityRow = communityRow
    self.communitySlots = {}
    for i = 1, 5 do
        local slot = UI.Cards:CreateCardFrame(communityRow, false)
        slot:ClearAllPoints()
        slot:SetPoint("LEFT", communityRow, "LEFT", (i - 1) * (cw + gap), 0)
        slot:Hide()
        self.communitySlots[i] = slot
    end

end

-- Render the shared community cards into the center row (face up)
function Holdem:RenderCommunityCards()
    if not self.communitySlots then return end
    local PS = BJ.HoldemState
    local community = (PS and PS.communityCards) or {}
    for i = 1, 5 do
        local slot = self.communitySlots[i]
        local card = community[i]
        if card then
            UI.Cards:SetCard(slot, card, true)
            slot:Show()
        else
            slot:Hide()
        end
    end
end

-- Called (host + clients) as each community card is dealt
function Holdem:OnCommunityDealt(card, onComplete)
    if UI.Lobby and UI.Lobby.PlayCardSound then UI.Lobby:PlayCardSound() end
    self:RenderCommunityCards()
    if onComplete then onComplete() end
end

function Holdem:UpdateTableExtras()
    self:RenderCommunityCards()
end

-- ===== NEXT HAND (host continues the same table; button + blinds rotate) =====

function Holdem:CreateExtraButtons(buttonArea, createButton)
    -- NEXT HAND button (host only, shown at settlement to continue the same
    -- table; the dealer button + blinds rotate one seat on the next deal).
    -- Shares the DEAL button's spot on the far left of the bar - the two are
    -- never shown in the same phase.
    local nextHandBtn = createButton(buttonArea, "nextHand", "NEXT HAND", 100, {0.15, 0.4, 0.2})
    nextHandBtn:SetPoint("RIGHT", self.buttons.fold, "LEFT", -10, 0)
    nextHandBtn:Hide()
    nextHandBtn:SetScript("OnClick", function() self:OnNextHandClick() end)
end

function Holdem:UpdateExtraButtons(PS, isHost)
    -- NEXT HAND button - host only, at settlement, to continue the same table
    -- (dealer/blinds rotate one seat on the next deal).
    if isHost and PS.phase == PS.PHASE.SETTLEMENT and #PS.playerOrder >= 2 then
        self.buttons.nextHand:SetEnabled(true)
        self.buttons.nextHand:Show()
    else
        self.buttons.nextHand:SetEnabled(false)
        self.buttons.nextHand:Hide()
    end
end

function Holdem:OnNextHandClick()
    if BJ.HoldemMultiplayer and BJ.HoldemMultiplayer.isHost then
        BJ.HoldemMultiplayer:NextHand()
    end
end

-- ===== Stakes: blinds instead of an ante =====

function Holdem:StakesText(PS)
    return string.format("Blinds: %d/%dg", PS.smallBlind or 0, PS.bigBlind or 0)
end

-- Blinds are posted at the deal, so sitting down costs nothing up front
function Holdem:AnteForJoin(PS)
    return 0
end

-- ===== Tournament =====

-- the table stays locked between tournament hands until a champion is crowned
function Holdem:BlocksNewTable(PS)
    return PS.tourney and not PS.tourney.champion
end

function Holdem:ExtendHostPanel(panel, yOffset)
    -- ===== Tournament mode =====
    yOffset = yOffset - 32

    local tourneyToggle = BJ.Theme:Check(panel, "", 16, nil)
    tourneyToggle:SetSize(22, 22)
    tourneyToggle:SetPoint("TOPLEFT", 16, yOffset + 4)
    tourneyToggle:SetChecked(BJ.HostSettings:Get("holdemTournament") or false)
    panel.tourneyToggle = tourneyToggle

    local tourneyLabel = panel:CreateFontString(nil, "OVERLAY", "CCFontNormal")
    tourneyLabel:SetPoint("LEFT", tourneyToggle, "RIGHT", 2, 0)
    tourneyLabel:SetText("|cffffd700Tournament|r (buy-in, no mid-entry)")

    local tourneyHelp = CreateFrame("Button", nil, panel)
    tourneyHelp:SetAllPoints(tourneyLabel)
    tourneyHelp:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Tournament", 1, 0.84, 0)
        GameTooltip:AddLine("One big table, locked to a buy-in: everyone", 1, 1, 1, true)
        GameTooltip:AddLine("starts with the same chip stack and the", 1, 1, 1, true)
        GameTooltip:AddLine("blinds are CHIPS. Nobody can join after the", 1, 1, 1, true)
        GameTooltip:AddLine("first deal. Bust or walk away and you're out.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("WINNER-TAKE-ALL: the champion collects the", 1, 0.84, 0, true)
        GameTooltip:AddLine("whole prize pool (every buy-in, walkouts", 1, 1, 1, true)
        GameTooltip:AddLine("included), settled via the debt ledger.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Betting each hand is capped at the shortest", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("stack, so every bet is always callable.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    tourneyHelp:SetScript("OnLeave", function() GameTooltip:Hide() end)

    yOffset = yOffset - 27

    local buyinLabel = panel:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    buyinLabel:SetPoint("TOPLEFT", 20, yOffset - 7)
    buyinLabel:SetText("Buy-in:")

    local buyinInput = CreateFrame("EditBox", nil, panel, "BackdropTemplate")
    buyinInput:SetSize(56, 24)
    buyinInput:SetPoint("LEFT", buyinLabel, "RIGHT", 6, 0)
    buyinInput:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    buyinInput:SetBackdropColor(0.1, 0.1, 0.1, 1)
    buyinInput:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    buyinInput:SetFontObject("CCFontNormal")
    buyinInput:SetJustifyH("CENTER")
    buyinInput:SetAutoFocus(false)
    buyinInput:SetNumeric(true)
    buyinInput:SetMaxLetters(4)
    buyinInput:SetText(tostring(BJ.HostSettings:Get("holdemBuyIn") or 10))
    buyinInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    buyinInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    panel.buyinInput = buyinInput

    local buyinGold = panel:CreateFontString(nil, "OVERLAY", "CCFontNormal")
    buyinGold:SetPoint("LEFT", buyinInput, "RIGHT", 3, 0)
    buyinGold:SetText("g")
    buyinGold:SetTextColor(1, 0.84, 0, 1)

    local chipsLabel = panel:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    chipsLabel:SetPoint("LEFT", buyinGold, "RIGHT", 14, 0)
    chipsLabel:SetText("Stack:")

    local chipsInput = CreateFrame("EditBox", nil, panel, "BackdropTemplate")
    chipsInput:SetSize(60, 24)
    chipsInput:SetPoint("LEFT", chipsLabel, "RIGHT", 6, 0)
    chipsInput:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    chipsInput:SetBackdropColor(0.1, 0.1, 0.1, 1)
    chipsInput:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    chipsInput:SetFontObject("CCFontNormal")
    chipsInput:SetJustifyH("CENTER")
    chipsInput:SetAutoFocus(false)
    chipsInput:SetNumeric(true)
    chipsInput:SetMaxLetters(5)
    chipsInput:SetText(tostring(BJ.HostSettings:Get("holdemStartChips") or 1000))
    chipsInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    chipsInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    panel.chipsInput = chipsInput


    return yOffset
end

function Holdem:ReadHostPanelExtras(panel)
    local tournament = panel.tourneyToggle:GetChecked() and true or false
    local buyIn = math.max(1, math.min(5000, tonumber(panel.buyinInput:GetText()) or 10))
    local startChips = math.max(10, math.min(99999, tonumber(panel.chipsInput:GetText()) or 1000))
    BJ.HostSettings:Set("holdemTournament", tournament)
    BJ.HostSettings:Set("holdemBuyIn", buyIn)
    BJ.HostSettings:Set("holdemStartChips", startChips)
    return { tournament = tournament, buyIn = buyIn, startChips = startChips }
end

-- 'ante' from the host panel is the Big Blind; small blind is half (min 1).
function Holdem:BuildTableSettings(ante, maxRaise, maxPlayers, cdOn, cdSecs, extra)
    extra = extra or {}
    local bigBlind = math.max(2, ante)
    local smallBlind = math.max(1, math.floor(bigBlind / 2))
    return {
        smallBlind = smallBlind,
        bigBlind = bigBlind,
        maxRaise = maxRaise,
        maxPlayers = maxPlayers,
        countdownEnabled = cdOn,
        countdownSeconds = cdSecs,
        tournament = extra.tournament and true or false,
        buyIn = extra.buyIn,
        startChips = extra.startChips,
    }
end

function Holdem:PotUnit(PS)
    return PS.tourney and " chips" or "g"
end

-- ===== Seats: dealer button / blind chips and tournament stacks =====

function Holdem:DecorateHand(hand)
    -- Dealer button / blind chip: the dealer.tga / sb.tga / bb.tga marker
    -- centered just above the seat's player name. Translucent, and at a
    -- high frame level so it layers on top of the tournament chip pile
    -- sharing the same centered spot.
    hand.seatChip = CreateFrame("Frame", nil, hand)
    hand.seatChip:SetSize(39, 39)
    hand.seatChip:SetPoint("BOTTOM", hand.label, "TOP", 0, 2)
    hand.seatChip:SetFrameLevel(hand:GetFrameLevel() + 30)
    hand.seatChip.icon = hand.seatChip:CreateTexture(nil, "OVERLAY")
    hand.seatChip.icon:SetAllPoints()
    hand.seatChip.icon:SetAlpha(0.7)
    hand.seatChip:Hide()
end

function Holdem:DecorateHandLabel(handDisplay, playerName, player, label)
    local PS = BJ.HoldemState
    -- Tournament: everyone's live chip stack rides with their name - the
    -- number AND a little pile of the real chip art. Chips committed to
    -- the pot this hand (blinds included) leave the stack as they're bet:
    -- the pot's chips visibly COME FROM the players.
    if PS.tourney then
        local stack = PS.tourney.chips[playerName]
        if stack then
            stack = math.max(0, stack - (player.totalBet or 0))
            label = label .. "\n|cffffcc66" .. stack .. " chips|r"
        end
        if BJ.UI.ChipPot and not handDisplay.stackChips then
            handDisplay.stackChips = BJ.UI.ChipPot:Attach(handDisplay)
            -- centered above the player; the translucent D/SB/BB marker
            -- (higher frame level) layers on top of the pile
            handDisplay.stackChips:SetPoint("BOTTOM",
                handDisplay.label, "TOP", 0, 2)
        end
        if handDisplay.stackChips then
            handDisplay.stackChips:SetAmount(stack or 0)
        end
    elseif handDisplay.stackChips then
        handDisplay.stackChips:SetAmount(0)
    end
    -- Dealer button / small & big blind chips
    self:UpdateSeatChip(handDisplay, playerName)
    return label
end

-- Show the dealer-button / blind chip on the seats that hold them. Chips are
-- only meaningful once a hand is live, so they hide outside of active phases.
function Holdem:UpdateSeatChip(handDisplay, playerName)
    local PS = BJ.HoldemState
    local chip = handDisplay.seatChip
    if not chip then return end

    local seat
    for i, name in ipairs(PS.playerOrder) do
        if name == playerName then seat = i break end
    end

    local live = PS.phase == PS.PHASE.BETTING or PS.phase == PS.PHASE.DEALING
        or PS.phase == PS.PHASE.SHOWDOWN or PS.phase == PS.PHASE.SETTLEMENT

    -- Derive the small/big-blind seats from the dealer button the same way
    -- HoldemState:PostBlinds does. Deriving locally (instead of reading
    -- PS.sbIndex/bbIndex) keeps the chips correct even after a reconnect
    -- state-sync, which restores the button but not the blind indices.
    local n = #PS.playerOrder
    local dealer = PS.dealerIndex
    local sbSeat, bbSeat
    if n == 2 then
        sbSeat = dealer
        bbSeat = (dealer % n) + 1
    elseif n >= 3 then
        sbSeat = (dealer % n) + 1
        bbSeat = ((dealer + 1) % n) + 1
    end

    local tex
    if live and seat and n >= 2 then
        if seat == dealer then
            tex = "DEALER"
        elseif seat == sbSeat then
            tex = "SB"
        elseif seat == bbSeat then
            tex = "BB"
        end
    end

    if tex then
        chip.icon:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\Poker\\" .. tex)
        chip:Show()
    else
        chip:Hide()
    end
end

function Holdem:ExtendSettlement(PS, lines)
    -- Tournament: this hand moved CHIPS, not gold - show the stacks and
    -- the standing instead of leaving the gold ledger uncorrected
    local t = PS.tourney
    if t then
        for i = #lines, 1, -1 do
            lines[i] = lines[i]:gsub("(%d+)g|r", "%1 chips|r")
        end
        table.insert(lines, "")
        if t.champion then
            table.insert(lines, "|cffffd700*** " .. t.champion .. " WINS THE TOURNAMENT! ***|r")
            local losers = 0
            for _ in pairs(t.entrants) do losers = losers + 1 end
            losers = losers - 1
            table.insert(lines, "|cffffd700Prize: " .. (t.buyIn * losers) .. "g (" ..
                losers .. " buy-ins) - recorded in the debt ledger.|r")
        else
            table.insert(lines, "|cffffffffStacks:|r")
            local standing = {}
            for name, chips in pairs(t.chips) do
                if chips > 0 then table.insert(standing, { name = name, chips = chips }) end
            end
            table.sort(standing, function(a, b) return a.chips > b.chips end)
            for _, s in ipairs(standing) do
                table.insert(lines, "  " .. s.name .. ": |cffffcc66" .. s.chips .. " chips|r")
            end
            for _, name in ipairs(t.eliminated) do
                table.insert(lines, "  |cff666666" .. name .. ": eliminated|r")
            end
        end
    end
end

function Holdem:CapRaise(PS, myPlayer, currentBet, remainingRaise)
    -- Tournament: a raise also can't push this hand's total commitment
    -- past the hand cap (the shortest stack at the deal)
    if PS.tourney and PS.tourneyHandCap and myPlayer then
        local toCall = math.max(0, currentBet - (myPlayer.currentBet or 0))
        local room = PS.tourneyHandCap - (myPlayer.totalBet or 0) - toCall
        if room < 0 then room = 0 end
        if room < remainingRaise then remainingRaise = room end
    end
    return remainingRaise
end
