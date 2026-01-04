--[[
    Chairface's Casino - UI/Animation.lua
    Card dealing animations
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.Animation = {}
local Anim = UI.Animation

-- Animation settings (slower for better visibility)
Anim.DEAL_DURATION = 0.5        -- Time for card to travel (hits, splits)
Anim.DEAL_DURATION_INITIAL = 0.4  -- Time for initial deal card travel (faster)
Anim.DEAL_DELAY = 0.7           -- Delay between cards (hits, splits)
Anim.DEAL_DELAY_INITIAL = 0.42  -- Delay between cards during initial deal (faster)
Anim.DEAL_START_X = 45          -- Start position X (under Trixie - she's at 15, width 120, center at 75)
Anim.DEAL_START_Y = -190        -- Start position Y (below Trixie - she's at -60, height 120, bottom at -180)
Anim.EFFECT_DURATION = 1.5      -- How long effects play before considered "done"

-- Animation state
Anim.queue = {}                -- Queue of animations to play
Anim.isAnimating = false
Anim.isInitialDeal = false     -- Track if we're in initial deal phase
Anim.animatingCard = nil
Anim.effectsPlaying = 0        -- Count of currently playing effects

-- Create a flying card for animation (uses player card size)
function Anim:CreateFlyingCard(parent)
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(UI.Cards.CARD_WIDTH, UI.Cards.CARD_HEIGHT)
    card:SetFrameStrata("TOOLTIP")  -- Highest strata so it flies over everything
    card:SetFrameLevel(100)
    
    -- No backdrop - transparent frame, texture only
    -- Card back texture (same as regular cards)
    card.backTexture = card:CreateTexture(nil, "ARTWORK")
    card.backTexture:SetAllPoints()
    card.backTexture:SetTexture(UI.Cards:GetCardBackTexture())
    
    -- Create rotation animation group for flick effect
    card.spinGroup = card:CreateAnimationGroup()
    card.spinAnim = card.spinGroup:CreateAnimation("Rotation")
    card.spinAnim:SetOrder(1)
    card.spinAnim:SetDuration(0.25)  -- Quick spin during deal
    card.spinAnim:SetDegrees(-360)   -- One full rotation (negative = clockwise)
    card.spinAnim:SetOrigin("CENTER", 0, 0)
    card.spinGroup:SetLooping("NONE")
    
    card:Hide()
    return card
end

-- Get or create the flying card (same size for all now)
function Anim:GetFlyingCard(isDealer)
    if not self.flyingCard and UI.mainFrame then
        self.flyingCard = self:CreateFlyingCard(UI.mainFrame)
    end
    return self.flyingCard
end

-- Queue a card deal animation
-- target: the hand display frame to deal to
-- cardData: the card being dealt
-- faceUp: whether card lands face up
-- onComplete: callback when animation finishes
-- isDealer: whether this is a dealer card
-- playerIndex: (optional) index of player for row switching
function Anim:QueueDeal(target, cardData, faceUp, onComplete, isDealer, playerIndex)
    table.insert(self.queue, {
        type = "deal",
        target = target,
        cardData = cardData,
        faceUp = faceUp,
        onComplete = onComplete,
        isDealer = isDealer,
        playerIndex = playerIndex,
    })
    
    -- Start processing if not already
    if not self.isAnimating then
        self:ProcessQueue()
    end
end

-- Process the animation queue
function Anim:ProcessQueue()
    if #self.queue == 0 then
        self.isAnimating = false
        -- Return Trixie to wait state when queue is empty
        if UI.SetTrixieWait then
            UI:SetTrixieWait()
        end
        return
    end
    
    self.isAnimating = true
    local anim = table.remove(self.queue, 1)
    
    -- Set Trixie to dealing pose when processing deal animations
    if anim.type == "deal" and UI.SetTrixieDeal then
        UI:SetTrixieDeal()
    end
    
    -- Auto-scroll to show the player being dealt to (but don't re-render)
    if anim.playerIndex and UI.playerArea and UI.playerArea.scrollToRow then
        local PLAYER_COLS = 5
        local targetRow = math.ceil(anim.playerIndex / PLAYER_COLS)
        if UI.playerArea.currentRow ~= targetRow then
            UI.playerArea.currentRow = targetRow
            UI.playerArea.scrollToRow(targetRow)
        end
    end
    
    if anim.type == "deal" then
        self:PlayDealAnimation(anim.target, anim.cardData, anim.faceUp, anim.onComplete, anim.isDealer)
    end
end

-- Play a single deal animation with rotation flick effect
function Anim:PlayDealAnimation(targetHand, cardData, faceUp, onComplete, isDealer)
    local flyingCard = self:GetFlyingCard(isDealer)
    if not flyingCard then
        -- No animation possible, just complete immediately
        if onComplete then onComplete() end
        self:ProcessQueue()
        return
    end
    
    -- Make sure target hand is valid and has position
    if not targetHand or not targetHand:GetLeft() then
        if onComplete then onComplete() end
        self:ProcessQueue()
        return
    end
    
    -- Play card flying sound
    if UI.Lobby then
        UI.Lobby:PlayCardSound()
    end
    
    -- Calculate start position (under Trixie's image)
    local startX = self.DEAL_START_X
    local startY = self.DEAL_START_Y
    
    -- Calculate end position (where the card will land in the hand)
    local cardSpacing = isDealer and UI.Cards.DEALER_CARD_SPACING or UI.Cards.CARD_SPACING
    local numCards = targetHand.cards and #targetHand.cards or 0
    local endX = targetHand:GetLeft() - UI.mainFrame:GetLeft() + (numCards * cardSpacing)
    local endY = targetHand:GetTop() - UI.mainFrame:GetTop()
    
    -- Card size
    local cardWidth = isDealer and UI.Cards.DEALER_CARD_WIDTH or UI.Cards.CARD_WIDTH
    local cardHeight = isDealer and UI.Cards.DEALER_CARD_HEIGHT or UI.Cards.CARD_HEIGHT
    
    -- Position at start
    flyingCard:ClearAllPoints()
    flyingCard:SetPoint("TOPLEFT", UI.mainFrame, "TOPLEFT", startX, startY)
    flyingCard:SetSize(cardWidth, cardHeight)
    flyingCard:Show()
    
    -- Start the rotation animation (flick effect)
    if flyingCard.spinGroup then
        flyingCard.spinGroup:Stop()
        flyingCard.spinGroup:Play()
    end
    
    -- Animate position
    local elapsed = 0
    local duration = self.isInitialDeal and self.DEAL_DURATION_INITIAL or self.DEAL_DURATION
    local dealDelay = self.isInitialDeal and self.DEAL_DELAY_INITIAL or self.DEAL_DELAY
    
    flyingCard:SetScript("OnUpdate", function(frame, dt)
        elapsed = elapsed + dt
        local progress = math.min(elapsed / duration, 1)
        
        -- Ease out cubic for smooth deceleration
        local eased = 1 - math.pow(1 - progress, 3)
        
        -- Interpolate position
        local currentX = startX + (endX - startX) * eased
        local currentY = startY + (endY - startY) * eased
        
        flyingCard:ClearAllPoints()
        flyingCard:SetPoint("TOPLEFT", UI.mainFrame, "TOPLEFT", currentX, currentY)
        
        if progress >= 1 then
            -- Animation complete
            flyingCard:SetScript("OnUpdate", nil)
            if flyingCard.spinGroup then
                flyingCard.spinGroup:Stop()
            end
            flyingCard:Hide()
            
            -- Call completion callback (this adds the actual card)
            if onComplete then
                onComplete()
            end
            
            -- Small delay before next card (but not if we're paused for blackjack)
            C_Timer.After(dealDelay - duration, function()
                if not Anim.dealPaused then
                    Anim:ProcessQueue()
                end
            end)
        end
    end)
end

-- Clear animation queue (for when game resets)
function Anim:ClearQueue()
    self.queue = {}
    self.isAnimating = false
    self.isInitialDeal = false
    self.dealPaused = false  -- Reset pause state
    if self.flyingCard then
        self.flyingCard:Hide()
        self.flyingCard:SetScript("OnUpdate", nil)
    end
end

-- Check if currently animating (cards or effects)
function Anim:IsAnimating()
    return self.isAnimating or #self.queue > 0 or (self.effectsPlaying and self.effectsPlaying > 0)
end

-- Check if any effects are still playing
function Anim:IsPlayingEffects()
    return self.effectsPlaying and self.effectsPlaying > 0
end

-- Animated deal of initial cards
-- This handles the full initial deal sequence: player1, player2, ..., dealer, player1, player2, ..., dealer
function Anim:DealInitialCards(dealerHand, playerHands, onAllComplete)
    self:ClearQueue()
    self.isInitialDeal = true  -- Use slower animation for initial deal
    
    local GS = BJ.GameState
    local dealSequence = {}
    
    -- Build deal sequence: first card to each player, then dealer, then second card to each, then dealer
    -- Round 1: One card to each player
    for i, playerName in ipairs(GS.playerOrder) do
        local player = GS.players[playerName]
        local targetHand = playerHands[i]
        if player and player.hands[1] and player.hands[1][1] and targetHand then
            table.insert(dealSequence, {
                target = targetHand,
                card = player.hands[1][1],
                faceUp = true,
                playerName = playerName,
                playerIndex = i,
                handIndex = 1,
                cardIndex = 1,
                isDealer = false,
            })
        end
    end
    
    -- Dealer's first card (face up)
    if GS.dealerHand[1] and dealerHand then
        table.insert(dealSequence, {
            target = dealerHand,
            card = GS.dealerHand[1],
            faceUp = true,
            isDealer = true,
            cardIndex = 1,
        })
    end
    
    -- Round 2: Second card to each player
    for i, playerName in ipairs(GS.playerOrder) do
        local player = GS.players[playerName]
        local targetHand = playerHands[i]
        if player and player.hands[1] and player.hands[1][2] and targetHand then
            table.insert(dealSequence, {
                target = targetHand,
                card = player.hands[1][2],
                faceUp = true,
                playerName = playerName,
                playerIndex = i,
                handIndex = 1,
                cardIndex = 2,
                isDealer = false,
            })
        end
    end
    
    -- Dealer's second card (face down - hole card)
    if GS.dealerHand[2] and dealerHand then
        table.insert(dealSequence, {
            target = dealerHand,
            card = GS.dealerHand[2],
            faceUp = false,  -- Hole card
            isDealer = true,
            cardIndex = 2,
        })
    end
    
    -- If no cards to deal, complete immediately
    if #dealSequence == 0 then
        if onAllComplete then onAllComplete() end
        return
    end
    
    -- Initialize displayed card count (actual remaining + cards about to be dealt)
    -- This gives us the count BEFORE dealing started
    UI.displayedCardCount = GS:GetRemainingCards() + #dealSequence
    
    local PLAYER_COLS = 5  -- Match MainFrame constant
    
    -- Build queue directly (don't use QueueDeal which auto-starts)
    for i, deal in ipairs(dealSequence) do
        local isLast = (i == #dealSequence)
        
        table.insert(self.queue, {
            type = "deal",
            target = deal.target,
            cardData = deal.card,
            faceUp = deal.faceUp,
            isDealer = deal.isDealer,
            playerIndex = deal.playerIndex,
            onComplete = function()
                -- Track that this card has been dealt
                if deal.isDealer then
                    UI.dealerDealtCards = (UI.dealerDealtCards or 0) + 1
                elseif deal.playerName then
                    local cardKey = deal.playerName .. "_" .. deal.handIndex
                    UI.dealtCards[cardKey] = (UI.dealtCards[cardKey] or 0) + 1
                end
                
                -- Decrement displayed card count
                UI.displayedCardCount = (UI.displayedCardCount or 0) - 1
                
                -- Update displays to show the newly dealt card
                if deal.isDealer then
                    UI:UpdateDealerDisplay()
                else
                    UI:UpdatePlayerHands()
                end
                
                -- Update card count display using displayed count during animation
                local GS = BJ.GameState
                if GS.hostName and UI.mainFrame and UI.mainFrame.infoText then
                    local multiplier = GS.maxMultiplier or 1
                    local ruleText = GS.dealerHitsSoft17 and "H17" or "S17"
                    local infoText = "Host: " .. GS.hostName .. " | Ante: " .. GS.ante .. "g with " .. multiplier .. "x multiplier | " .. ruleText
                    if UI.displayedCardCount and UI.displayedCardCount > 0 then
                        infoText = infoText .. " | Remaining Cards: " .. UI.displayedCardCount
                    elseif #GS.shoe > 0 then
                        infoText = infoText .. " | Remaining Cards: " .. GS:GetRemainingCards()
                    end
                    UI.mainFrame.infoText:SetText(infoText)
                end
                
                -- Check for blackjack after player's second card
                if deal.cardIndex == 2 and not deal.isDealer and deal.playerName then
                    local player = GS.players[deal.playerName]
                    if player and player.hands[1] then
                        local score = GS:ScoreHand(player.hands[1])
                        if score.isBlackjack then
                            -- Only trigger audio and Trixie for LOCAL player's blackjack
                            local myName = UnitName("player")
                            if deal.playerName == myName then
                                -- Play audio for blackjack
                                if UI.Lobby then
                                    UI.Lobby:PlayWinSound()
                                    UI.Lobby:PlayTrixieBlackjackVoice()
                                end
                                -- Trixie cheers for 3 seconds then returns to current state
                                if UI.SetTrixieCheer then
                                    UI:SetTrixieCheer()
                                    -- Return to dealing/wait after 3 seconds
                                    C_Timer.After(3.0, function()
                                        if UI.SetTrixieDeal then
                                            UI:SetTrixieDeal()
                                        end
                                    end)
                                end
                            end
                        end
                    end
                end
                
                -- Final callback when all cards dealt
                if isLast then
                    -- Clear displayed count so normal GetRemainingCards is used
                    UI.displayedCardCount = nil
                    -- Clear initial deal flag (return to normal speed)
                    Anim.isInitialDeal = false
                    if onAllComplete then
                        C_Timer.After(0.1, onAllComplete)
                    end
                end
            end,
        })
    end
    
    -- NOW start the sequence (all cards are queued)
    self:ProcessQueue()
end

-- Animated single card deal (for hits)
function Anim:DealSingleCard(targetHand, cardData, faceUp, onComplete, isDealer)
    self:QueueDeal(targetHand, cardData, faceUp, onComplete, isDealer)
end

-- Mark a card as dealt for a player (called after animation completes)
function Anim:MarkCardDealt(playerName, handIndex)
    local cardKey = playerName .. "_" .. handIndex
    UI.dealtCards[cardKey] = (UI.dealtCards[cardKey] or 0) + 1
end

--[[
    SPECIAL EFFECTS
]]

-- Pool of effect frames for reuse
Anim.effectPool = {}

-- Get or create an effect frame
function Anim:GetEffectFrame(parent)
    local frame = table.remove(self.effectPool)
    if not frame then
        frame = CreateFrame("Frame", nil, parent)
        frame:SetSize(100, 100)
        frame:SetFrameStrata("HIGH")
        
        -- Main texture for the effect
        frame.texture = frame:CreateTexture(nil, "OVERLAY")
        frame.texture:SetAllPoints()
        
        -- Text label (for "BLACKJACK!", "5-CARD CHARLIE!", "BUST!")
        frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        frame.text:SetPoint("CENTER", frame, "CENTER", 0, -50)
    end
    frame:SetParent(parent)
    frame:Show()
    return frame
end

-- Return effect frame to pool
function Anim:ReleaseEffectFrame(frame)
    frame:Hide()
    frame:SetScript("OnUpdate", nil)
    frame:ClearAllPoints()
    frame.isPersistent = false
    frame.playerKey = nil
    frame.effectType = nil
    frame.targetHandDisplay = nil
    table.insert(self.effectPool, frame)
end

-- Track persistent effects to clear on round end
Anim.persistentEffects = {}

-- Clear all persistent effects (called on round clear)
function Anim:ClearPersistentEffects()
    for _, frame in ipairs(self.persistentEffects) do
        self:ReleaseEffectFrame(frame)
    end
    self.persistentEffects = {}
    self.playerBustEffects = {}
    self.playerWinEffects = {}
end

-- Clear all effects immediately (called when hosting new game)
function Anim:ClearAllEffects()
    -- Clear persistent effects
    for _, frame in ipairs(self.persistentEffects) do
        self:ReleaseEffectFrame(frame)
    end
    self.persistentEffects = {}
    self.playerBustEffects = {}
    self.playerWinEffects = {}
    
    -- Also clear any flying cards
    if self.flyingCard then
        self.flyingCard:Hide()
        self.flyingCard:SetScript("OnUpdate", nil)
    end
    if self.flyingDealerCard then
        self.flyingDealerCard:Hide()
        self.flyingDealerCard:SetScript("OnUpdate", nil)
    end
    
    -- Clear queue
    self.queue = {}
    self.isAnimating = false
end

-- Play red X effect for Bust (persistent until round clears)
-- Track bust effects by player name and hand index
Anim.playerBustEffects = {}

function Anim:PlayBustEffect(handDisplay, playerName, handIndex)
    if not handDisplay then return end
    
    -- Track that an effect is playing
    self.effectsPlaying = (self.effectsPlaying or 0) + 1
    
    -- Create a unique key for this player's hand
    local effectKey = playerName and (playerName .. "_" .. (handIndex or 1)) or nil
    
    local frame = self:GetEffectFrame(handDisplay)
    frame:SetSize(100, 100)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", handDisplay, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")  -- Higher strata to be above cards
    frame:SetFrameLevel(100)  -- High frame level
    
    frame.texture:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
    frame.texture:SetTexCoord(0, 1, 0, 1)
    frame.texture:SetVertexColor(1, 0.2, 0.2, 1)
    frame.texture:SetBlendMode("BLEND")
    frame.texture:SetAlpha(0.9)
    
    if frame.texture2 then
        frame.texture2:Hide()
    end
    frame.text:Hide()
    
    frame.isPersistent = true
    frame.playerKey = effectKey
    frame.targetHandDisplay = handDisplay
    table.insert(self.persistentEffects, frame)
    
    -- Track by player key for repositioning
    if effectKey then
        self.playerBustEffects[effectKey] = frame
    end
    
    local elapsed = 0
    local effectDone = false
    
    frame:SetScript("OnUpdate", function(f, dt)
        elapsed = elapsed + dt
        local scale = 1
        if elapsed < 0.15 then
            scale = 0.3 + (elapsed / 0.15) * 0.7
        else
            scale = 1 + math.sin(elapsed * 2) * 0.05
        end
        frame:SetSize(100 * scale, 100 * scale)
        
        -- Mark effect as done after duration (but keep displaying)
        if not effectDone and elapsed >= Anim.EFFECT_DURATION then
            effectDone = true
            Anim.effectsPlaying = math.max(0, (Anim.effectsPlaying or 1) - 1)
        end
    end)
end

-- Update bust effect positions (now simpler since all players are rendered)
function Anim:UpdateBustEffectPositions()
    local GS = BJ.GameState
    if not GS or not GS.playerOrder then return end
    
    -- Build a map of playerName_handIndex -> global hand index
    local handIndexMap = {}
    local globalHandIndex = 0
    
    for _, playerName in ipairs(GS.playerOrder) do
        local playerData = GS.players[playerName]
        if playerData then
            for h = 1, #playerData.hands do
                globalHandIndex = globalHandIndex + 1
                local key = playerName .. "_" .. h
                handIndexMap[key] = globalHandIndex
            end
        end
    end
    
    -- Update bust effects - now all players are rendered so effects are always visible
    for effectKey, frame in pairs(self.playerBustEffects or {}) do
        if frame then
            local handIdx = handIndexMap[effectKey]
            if handIdx and UI.playerArea.hands[handIdx] then
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UI.playerArea.hands[handIdx], "CENTER", 0, 0)
                frame:Show()
            else
                frame:Hide()
            end
        end
    end
    
    -- Update win effects (blackjack, 5-card charlie)
    for effectKey, frame in pairs(self.playerWinEffects or {}) do
        if frame then
            local handIdx = handIndexMap[effectKey]
            if handIdx and UI.playerArea.hands[handIdx] then
                frame:ClearAllPoints()
                if frame.effectType == "blackjack" then
                    frame:SetPoint("BOTTOM", UI.playerArea.hands[handIdx], "BOTTOM", 0, 5)
                else
                    frame:SetPoint("CENTER", UI.playerArea.hands[handIdx], "CENTER", 0, 0)
                end
                frame:Show()
            else
                frame:Hide()
            end
        end
    end
end

-- Hide all player effects (no longer needed but kept for compatibility)
function Anim:HideAllPlayerEffects()
    -- With all players rendered, effects can stay visible
    -- This function now does nothing but is kept for API compatibility
end

-- Clear player bust effects
function Anim:ClearPlayerBustEffects()
    self.playerBustEffects = {}
    self.playerWinEffects = {}
end

--[[
    ANTE SOUND
    Plays when a player antes
]]

-- Play ante sound (clips previous plays)
function Anim:PlayAnteSound()
    local soundFile = "Interface\\AddOns\\Chairfaces Casino\\Sounds\\chips.ogg"
    PlaySoundFile(soundFile, "SFX")
end
