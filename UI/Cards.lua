--[[
    Chairface's Casino - UI/Cards.lua
    Card rendering with custom card textures
]]

local BJ = ChairfacesCasino
BJ.UI = BJ.UI or {}
local UI = BJ.UI

UI.Cards = {}
local Cards = UI.Cards

-- Card dimensions
Cards.CARD_WIDTH = 64
Cards.CARD_HEIGHT = 90
Cards.CARD_SPACING = 25  -- Overlap for fanning cards
Cards.CARD_SCALE = 1.0

-- Dealer uses same size
Cards.DEALER_CARD_WIDTH = 64
Cards.DEALER_CARD_HEIGHT = 90
Cards.DEALER_CARD_SPACING = 25

-- Card pool for reuse
Cards.cardPool = {}
Cards.activeCards = {}

-- Texture path for cards
Cards.TEXTURE_PATH = "Interface\\AddOns\\Chairfaces Casino\\Textures\\cards\\"
Cards.TEXTURE_PATH_DARK = "Interface\\AddOns\\Chairfaces Casino\\Textures\\cards_dark\\"
Cards.TEXTURE_PATH_ALT = "Interface\\AddOns\\Chairfaces Casino\\Textures\\cards_alt\\"

-- Current card back style (default blue)
Cards.cardBackStyle = "blue"

-- Current card front/deck style (default "classic", "dark", or "warcraft")
Cards.cardDeckStyle = "classic"

-- Deck style order for UI navigation
Cards.deckStyles = { "classic", "dark", "warcraft" }
Cards.deckStyleNames = { classic = "Classic", dark = "Dark", warcraft = "Warcraft" }

-- Animated card definitions (for warcraft deck)
-- Format: { numFrames, frameTime, spriteHeight }
Cards.animatedCards = {
    ["A_spades"] = { numFrames = 50, frameTime = 0.05, spriteFile = "A_spades_anim" }
}

-- Active animated card frames (for OnUpdate)
Cards.animatingCards = {}

-- Get card texture path (and animation info if applicable)
function Cards:GetCardTexture(rank, suit)
    -- rank: A, 2-10, J, Q, K
    -- suit: hearts, diamonds, clubs, spades
    local basePath
    if self.cardDeckStyle == "warcraft" then
        basePath = self.TEXTURE_PATH_ALT
    elseif self.cardDeckStyle == "dark" then
        basePath = self.TEXTURE_PATH_DARK
    else
        basePath = self.TEXTURE_PATH
    end
    local cardKey = rank .. "_" .. suit
    
    -- Check for animated version in warcraft deck
    if self.cardDeckStyle == "warcraft" and self.animatedCards[cardKey] then
        local animInfo = self.animatedCards[cardKey]
        return basePath .. animInfo.spriteFile .. ".tga", animInfo
    end
    
    return basePath .. cardKey .. ".tga", nil
end

-- Get card back texture path
function Cards:GetCardBackTexture()
    return self.TEXTURE_PATH .. "back_" .. self.cardBackStyle .. ".tga"
end

-- Set card back style and update all existing cards
function Cards:SetCardBack(style)
    if style ~= "red" and style ~= "blue" and style ~= "mtg" and style ~= "hs" then
        style = "blue"
    end
    self.cardBackStyle = style
    
    -- Update all active cards with new back texture
    local backTexture = self:GetCardBackTexture()
    for _, card in ipairs(self.activeCards) do
        if card.back and card.back.texture then
            card.back.texture:SetTexture(backTexture)
        end
    end
    
    -- Also update the flying card if it exists
    if UI.Animation and UI.Animation.flyingCard and UI.Animation.flyingCard.backTexture then
        UI.Animation.flyingCard.backTexture:SetTexture(backTexture)
    end
end

-- Initialize card back from saved settings
function Cards:InitializeCardBack()
    -- Try BJ.db first, then fall back to ChairfacesCasinoDB directly
    local db = BJ.db or ChairfacesCasinoDB
    if db and db.settings and db.settings.cardBack then
        self.cardBackStyle = db.settings.cardBack
    end
end

-- Set card deck/front style
function Cards:SetCardDeck(style)
    if style ~= "classic" and style ~= "dark" and style ~= "warcraft" then
        style = "classic"
    end
    self.cardDeckStyle = style
    
    -- Save to settings
    if BJ.db and BJ.db.settings then
        BJ.db.settings.cardDeck = style
    end
    
    -- Note: Existing cards won't update automatically since they cache textures
    -- New cards dealt will use the new style
end

-- Initialize card deck style from saved settings
function Cards:InitializeCardDeck()
    -- Try BJ.db first, then fall back to ChairfacesCasinoDB directly
    local db = BJ.db or ChairfacesCasinoDB
    if db and db.settings and db.settings.cardDeck then
        self.cardDeckStyle = db.settings.cardDeck
    end
end

-- Create a single card frame (player size - compact)
function Cards:CreateCardFrame(parent, isDealer)
    local cardWidth = self.CARD_WIDTH  -- Same size for all now
    local cardHeight = self.CARD_HEIGHT
    
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(cardWidth, cardHeight)
    card:SetFrameLevel(parent:GetFrameLevel() + 1)
    card.isDealer = isDealer
    
    -- No backdrop - fully transparent frame
    -- Card face texture (the actual card image)
    card.faceTexture = card:CreateTexture(nil, "ARTWORK")
    card.faceTexture:SetAllPoints()
    
    -- Card back overlay (for face-down cards)
    card.back = CreateFrame("Frame", nil, card)
    card.back:SetAllPoints()
    card.back:SetFrameLevel(card:GetFrameLevel() + 1)
    
    -- Card back texture - no backdrop, just texture
    card.back.texture = card.back:CreateTexture(nil, "ARTWORK")
    card.back.texture:SetAllPoints()
    card.back.texture:SetTexture(self:GetCardBackTexture())
    
    card.back:Hide()
    card.isFaceUp = true
    card.cardData = nil
    
    return card
end

-- Get a card from pool or create new
function Cards:GetCard(parent, isDealer)
    local poolKey = isDealer and "dealerPool" or "cardPool"
    self[poolKey] = self[poolKey] or {}
    
    local card = table.remove(self[poolKey])
    if not card then
        card = self:CreateCardFrame(parent, isDealer)
    else
        card:SetParent(parent)
    end
    table.insert(self.activeCards, card)
    card:Show()
    return card
end

-- Return card to pool
function Cards:ReleaseCard(card)
    -- Stop any animation
    self:StopCardAnimation(card)
    
    card:Hide()
    card:ClearAllPoints()
    card.cardData = nil
    
    -- Remove from active list
    for i, c in ipairs(self.activeCards) do
        if c == card then
            table.remove(self.activeCards, i)
            break
        end
    end
    
    local poolKey = card.isDealer and "dealerPool" or "cardPool"
    self[poolKey] = self[poolKey] or {}
    table.insert(self[poolKey], card)
end

-- Release all active cards
function Cards:ReleaseAllCards()
    while #self.activeCards > 0 do
        self:ReleaseCard(self.activeCards[1])
    end
end

-- Set card display
function Cards:SetCard(cardFrame, cardData, faceUp)
    cardFrame.cardData = cardData
    cardFrame.isFaceUp = faceUp
    
    -- Stop any existing animation on this card
    self:StopCardAnimation(cardFrame)
    
    -- Always update back texture to current style
    if cardFrame.back and cardFrame.back.texture then
        cardFrame.back.texture:SetTexture(self:GetCardBackTexture())
    end
    
    if not faceUp then
        cardFrame.back:Show()
        return
    end
    
    cardFrame.back:Hide()
    
    local rank = cardData.rank
    local suit = cardData.suit
    
    -- Set card face texture (may be animated)
    local texturePath, animInfo = self:GetCardTexture(rank, suit)
    cardFrame.faceTexture:SetTexture(texturePath)
    
    -- Start animation if this is an animated card
    if animInfo then
        self:StartCardAnimation(cardFrame, animInfo)
    else
        -- Static card - reset tex coords
        cardFrame.faceTexture:SetTexCoord(0, 1, 0, 1)
    end
end

-- Start animating a card
function Cards:StartCardAnimation(cardFrame, animInfo)
    -- Set up animation state
    cardFrame.animInfo = animInfo
    cardFrame.animElapsed = 0
    cardFrame.animFrame = 0
    
    -- Set initial frame (Y-flipped for TGA)
    local top = 1 / animInfo.numFrames
    local bottom = 0
    cardFrame.faceTexture:SetTexCoord(0, 1, top, bottom)
    
    -- Add to animating list
    self.animatingCards[cardFrame] = true
    
    -- Ensure animation ticker is running
    self:EnsureAnimationTicker()
end

-- Stop animating a card
function Cards:StopCardAnimation(cardFrame)
    if cardFrame.animInfo then
        cardFrame.animInfo = nil
        self.animatingCards[cardFrame] = nil
    end
end

-- Animation ticker (shared by all animated cards)
function Cards:EnsureAnimationTicker()
    if self.animTicker then return end
    
    self.animTicker = CreateFrame("Frame")
    self.animTicker:SetScript("OnUpdate", function(_, dt)
        local hasAnimating = false
        
        for cardFrame, _ in pairs(Cards.animatingCards) do
            if cardFrame.animInfo and cardFrame:IsShown() then
                hasAnimating = true
                cardFrame.animElapsed = cardFrame.animElapsed + dt
                
                local animInfo = cardFrame.animInfo
                local newFrame = math.floor(cardFrame.animElapsed / animInfo.frameTime) % animInfo.numFrames
                
                if newFrame ~= cardFrame.animFrame then
                    cardFrame.animFrame = newFrame
                    -- Vertical sprite sheet with Y-flip
                    local top = (newFrame + 1) / animInfo.numFrames
                    local bottom = newFrame / animInfo.numFrames
                    cardFrame.faceTexture:SetTexCoord(0, 1, top, bottom)
                end
            end
        end
        
        -- Stop ticker if nothing animating
        if not hasAnimating then
            Cards.animTicker:SetScript("OnUpdate", nil)
            Cards.animTicker = nil
        end
    end)
end

-- Flip a card face up
function Cards:FlipCard(cardFrame)
    if cardFrame.isFaceUp then return end
    
    cardFrame.isFaceUp = true
    cardFrame.back:Hide()
    
    if cardFrame.cardData then
        self:SetCard(cardFrame, cardFrame.cardData, true)
    end
end

-- Create a hand display (multiple cards)
function Cards:CreateHandDisplay(parent, name, isDealer)
    local cardHeight = isDealer and self.DEALER_CARD_HEIGHT or self.CARD_HEIGHT
    local hand = CreateFrame("Frame", name, parent)
    hand:SetSize(150, cardHeight + 30)
    hand.isDealer = isDealer
    
    hand.cards = {}
    
    -- Label background frame (for current player highlighting)
    if not isDealer then
        local labelBg = hand:CreateTexture(nil, "BACKGROUND")
        labelBg:SetTexture("Interface\\Buttons\\WHITE8x8")
        labelBg:SetHeight(24)
        labelBg:SetPoint("BOTTOM", hand, "TOP", 0, -2)
        labelBg:SetVertexColor(0, 0, 0, 0)  -- Hidden by default
        hand.labelBg = labelBg
    end
    
    -- Player name label - doubled from 9 to 18 for players
    hand.label = hand:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hand.label:SetPoint("BOTTOM", hand, "TOP", 0, 1)
    hand.label:SetFont("Fonts\\FRIZQT__.TTF", isDealer and 11 or 18, "OUTLINE")
    
    -- Score label - same size for both dealer and players (20)
    hand.scoreLabel = hand:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hand.scoreLabel:SetPoint("TOP", hand, "BOTTOM", 0, -1)
    hand.scoreLabel:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    
    -- Bet label - doubled from 8 to 16 for players
    hand.betLabel = hand:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hand.betLabel:SetPoint("TOP", hand.scoreLabel, "BOTTOM", 0, -1)
    hand.betLabel:SetFont("Fonts\\FRIZQT__.TTF", isDealer and 10 or 16, "")
    hand.betLabel:SetTextColor(1, 0.84, 0, 1)  -- Gold
    
    -- Result label (WIN/LOSE and amount) - doubled from 8 to 16 for players
    hand.resultLabel = hand:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hand.resultLabel:SetPoint("TOP", hand.betLabel, "BOTTOM", 0, -1)
    hand.resultLabel:SetFont("Fonts\\FRIZQT__.TTF", isDealer and 10 or 16, "OUTLINE")
    hand.resultLabel:Hide()
    
    return hand
end

-- Update hand display with cards
function Cards:UpdateHandDisplay(handDisplay, cardDataList, hideSecond, score, bet, label, result, payout)
    local isDealer = handDisplay.isDealer
    local cardWidth = isDealer and self.DEALER_CARD_WIDTH or self.CARD_WIDTH
    local cardSpacing = isDealer and self.DEALER_CARD_SPACING or self.CARD_SPACING
    
    -- Release old cards
    for _, card in ipairs(handDisplay.cards) do
        self:ReleaseCard(card)
    end
    handDisplay.cards = {}
    
    -- Create new cards
    local startX = 0
    local baseLevel = handDisplay:GetFrameLevel() + 1
    
    -- Seed random with something consistent per hand for stable display
    -- Use hand display name hash for consistency
    local handName = handDisplay:GetName() or "hand"
    local seed = 0
    for c = 1, #handName do seed = seed + string.byte(handName, c) end
    
    for i, cardData in ipairs(cardDataList) do
        local card = self:GetCard(handDisplay, isDealer)
        local faceUp = not (hideSecond and i == 2)
        self:SetCard(card, cardData, faceUp)
        
        -- Each subsequent card is higher in frame level to cover previous cards
        card:SetFrameLevel(baseLevel + (i * 2))
        if card.back then
            card.back:SetFrameLevel(baseLevel + (i * 2) + 1)
        end
        
        -- Calculate random but consistent rotation and offset for this card
        -- Use card data + index for consistent randomness
        local cardSeed = seed + i + (cardData.rank and string.byte(cardData.rank, 1) or 0) + (cardData.suit and string.byte(cardData.suit, 1) or 0)
        local rotationVariance = ((cardSeed % 30) - 15) * 0.01  -- -15% to +15% as radians (-0.15 to 0.15)
        local xVariance = ((cardSeed * 7) % 11) - 5             -- -5 to +5 pixels
        local yVariance = (((cardSeed * 13) % 11) - 5)          -- -5 to +5 pixels
        
        card:SetPoint("LEFT", handDisplay, "LEFT", startX + xVariance, yVariance)
        
        -- Apply rotation via SetRotation on the textures
        if card.faceTexture then
            card.faceTexture:SetRotation(rotationVariance)
        end
        if card.back and card.back.texture then
            card.back.texture:SetRotation(rotationVariance)
        end
        
        startX = startX + cardSpacing
        
        table.insert(handDisplay.cards, card)
    end
    
    -- Resize hand display to fit cards
    local width = startX + cardWidth - cardSpacing
    if width < 60 then width = 60 end
    handDisplay:SetWidth(width)
    
    -- Update labels
    if label then
        handDisplay.label:SetText(label)
        handDisplay.label:Show()
    else
        handDisplay.label:Hide()
    end
    
    if score then
        local scoreText = tostring(score)
        if score > 21 then
            scoreText = scoreText .. " BUST"
            handDisplay.scoreLabel:SetTextColor(1, 0.2, 0.2, 1)
        elseif score == 21 and #cardDataList == 2 then
            scoreText = "BLACKJACK!"
            handDisplay.scoreLabel:SetTextColor(1, 0.84, 0, 1)
        else
            handDisplay.scoreLabel:SetTextColor(1, 1, 1, 1)
        end
        handDisplay.scoreLabel:SetText(scoreText)
        handDisplay.scoreLabel:Show()
    else
        handDisplay.scoreLabel:Hide()
    end
    
    if bet and bet > 0 then
        handDisplay.betLabel:SetText("Bet: " .. bet .. "g")
        handDisplay.betLabel:Show()
    else
        handDisplay.betLabel:Hide()
    end
    
    -- Show result if provided
    if result and payout then
        local resultText = ""
        if result == "win" or result == "blackjack" then
            resultText = "|cff00ff00WIN +" .. payout .. "g|r"
        elseif result == "lose" or result == "bust" then
            resultText = "|cffff4444LOSE " .. payout .. "g|r"
        elseif result == "push" then
            resultText = "|cffffff00PUSH|r"
        end
        handDisplay.resultLabel:SetText(resultText)
        handDisplay.resultLabel:Show()
    else
        handDisplay.resultLabel:Hide()
    end
end

-- Add single card to existing hand display
function Cards:AddCardToDisplay(handDisplay, cardData, faceUp)
    local isDealer = handDisplay.isDealer
    local cardWidth = isDealer and self.DEALER_CARD_WIDTH or self.CARD_WIDTH
    local cardSpacing = isDealer and self.DEALER_CARD_SPACING or self.CARD_SPACING
    
    local card = self:GetCard(handDisplay, isDealer)
    self:SetCard(card, cardData, faceUp ~= false)
    
    local cardIndex = #handDisplay.cards + 1
    local baseLevel = handDisplay:GetFrameLevel() + 1
    
    -- Set frame level higher than previous cards
    card:SetFrameLevel(baseLevel + (cardIndex * 2))
    if card.back then
        card.back:SetFrameLevel(baseLevel + (cardIndex * 2) + 1)
    end
    
    -- Calculate random but consistent rotation and offset for this card
    local handName = handDisplay:GetName() or "hand"
    local seed = 0
    for c = 1, #handName do seed = seed + string.byte(handName, c) end
    local cardSeed = seed + cardIndex + (cardData.rank and string.byte(cardData.rank, 1) or 0) + (cardData.suit and string.byte(cardData.suit, 1) or 0)
    local rotationVariance = ((cardSeed % 30) - 15) * 0.01  -- -15% to +15% as radians
    local xVariance = ((cardSeed * 7) % 11) - 5             -- -5 to +5 pixels
    local yVariance = (((cardSeed * 13) % 11) - 5)          -- -5 to +5 pixels
    
    local startX = #handDisplay.cards * cardSpacing
    card:SetPoint("LEFT", handDisplay, "LEFT", startX + xVariance, yVariance)
    
    -- Apply rotation via SetRotation on the textures
    if card.faceTexture then
        card.faceTexture:SetRotation(rotationVariance)
    end
    if card.back and card.back.texture then
        card.back.texture:SetRotation(rotationVariance)
    end
    
    table.insert(handDisplay.cards, card)
    
    -- Resize
    local width = startX + cardWidth
    if width < 60 then width = 60 end
    handDisplay:SetWidth(width)
    
    return card
end

-- Flip hole card in hand display
function Cards:FlipHoleCard(handDisplay)
    if handDisplay.cards[2] then
        self:FlipCard(handDisplay.cards[2])
    end
end
