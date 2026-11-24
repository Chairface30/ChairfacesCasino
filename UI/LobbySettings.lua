--[[
    Chairface's Casino - UI/LobbySettings.lua
    The Settings window (Visuals & Sound, Trixie, Auto-Open, About) and the
    card / dice / scale choices it drives.
    Part of the lobby module (UI.Lobby), split out of UI/Lobby.lua.
]]

local BJ = ChairfacesCasino
local UI = BJ.UI
local Lobby = UI.Lobby

-- Settings Panel
function Lobby:CreateSettingsPanel()
    if self.settingsFrame then return end
    
    -- Shared casino window (UI/Chrome.lua) on the tavern art
    local frame = UI.Chrome:CreateWindow({
        name = "ChairfacesCasinoSettings",
        title = "Settings",
        width = 560, height = 580,   -- the tallest page is Visuals & Sound
        strata = "DIALOG",
        art = "tavern", scrim = 0.62,
        noLobby = true,
    })
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", 200, 0)
    local title = frame.titleText
    local closeBtn = frame.closeBtn

    -- ===== tabs =====
    -- Three pages; every control below lives on exactly one, so a tab
    -- switch is just page Show/Hide. Each page's anchor offset lifts its
    -- content block up under the tab row - the controls keep the anchor
    -- coordinates they had in the old single-page layout.
    local pageVis = CreateFrame("Frame", nil, frame)
    pageVis:SetPoint("TOPLEFT", 0, -44)
    pageVis:SetPoint("BOTTOMRIGHT", 0, -44)
    local pageTrix = CreateFrame("Frame", nil, frame)
    pageTrix:SetPoint("TOPLEFT", -180, 228)
    pageTrix:SetPoint("BOTTOMRIGHT", -180, 228)
    local pageAuto = CreateFrame("Frame", nil, frame)
    pageAuto:SetPoint("TOPLEFT", 0, 498)
    pageAuto:SetPoint("BOTTOMRIGHT", 0, 498)
    -- About: who made it, and a quiet thank-you note. Last tab, so it's
    -- there for anyone who looks, and nobody else.
    local pageAbout = CreateFrame("Frame", nil, frame)
    pageAbout:SetPoint("TOPLEFT", 0, -44)
    pageAbout:SetPoint("BOTTOMRIGHT", 0, -44)
    frame.settingsPages = { pageVis, pageTrix, pageAuto, pageAbout }
    do
        local head = pageAbout:CreateFontString(nil, "OVERLAY", "CCFontLarge")
        head:SetPoint("TOP", pageAbout, "TOP", 0, -40)
        head:SetText("Chairface's Casino v" .. BJ.version)
        local by = pageAbout:CreateFontString(nil, "OVERLAY", "CCFontHighlight")
        by:SetPoint("TOP", head, "BOTTOM", 0, -8)
        by:SetText("Made by Chairface Chippendale")
        local note = pageAbout:CreateFontString(nil, "OVERLAY", "CCFontDisableSmall")
        note:SetPoint("TOP", by, "BOTTOM", 0, -24)
        note:SetWidth(380)
        note:SetJustifyH("CENTER")
        note:SetSpacing(2)
        note:SetText("If the casino has given you a good night or two and you'd like to say "
            .. "thanks, in-game gold mailed to Chairface Chippendale is always "
            .. "appreciated, and never expected.")
    end

    local tabBtns = {}
    local function selectTab(idx)
        for i, page in ipairs(frame.settingsPages) do
            page:SetShown(i == idx)
            local b = tabBtns[i]
            BJ.Theme:SetButtonVariant(b, i == idx and "primary" or "secondary")
        end
        frame.currentSettingsTab = idx
    end
    for i, name in ipairs({ "Visuals & Sound", "Trixie", "Auto-Open", "About" }) do
        local b = BJ.Theme:Button(frame, "", 126, 22, "secondary", nil)
        b:SetPoint("TOPLEFT", 10 + (i - 1) * 134, -34)
        local t = b.text
        t:SetText(name)
        b:SetScript("OnClick", function() selectTab(i) end)
        tabBtns[i] = b
    end
    frame.SelectSettingsTab = selectTab
    
    -- ========== LEFT COLUMN (Card Deck, Card Back, Dice) ==========
    local leftCol = 115  -- Center of left column
    
    -- Card Deck/Face section
    local faceLabel = pageVis:CreateFontString(nil, "OVERLAY", "CCFontNormal")
    faceLabel:SetPoint("TOP", pageVis, "TOPLEFT", leftCol, -20)
    faceLabel:SetText("Card Deck")
    
    local cardDecks = {
        { id = "classic", name = "Classic", texture = "A_spades", path = "cards" },
        { id = "dark", name = "Dark", texture = "A_spades", path = "cards_dark" },
        { id = "warcraft", name = "Warcraft", texture = "A_spades", path = "cards_alt" },
    }
    frame.cardDecks = cardDecks
    
    local savedDeck = "classic"
    if BJ.db and BJ.db.settings and BJ.db.settings.cardDeck then
        savedDeck = BJ.db.settings.cardDeck
    end
    frame.currentDeckIndex = 1
    for i, deck in ipairs(cardDecks) do
        if deck.id == savedDeck then
            frame.currentDeckIndex = i
            break
        end
    end
    
    local facePreview = CreateFrame("Frame", nil, pageVis, "BackdropTemplate")
    facePreview:SetSize(60, 84)
    facePreview:SetPoint("TOP", faceLabel, "BOTTOM", 0, -5)
    BJ.Theme:Backdrop(facePreview, "inset")
    
    local faceTex = facePreview:CreateTexture(nil, "ARTWORK")
    faceTex:SetPoint("TOPLEFT", 2, -2)
    faceTex:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.cardDeckTexture = faceTex
    frame.cardDeckPreview = facePreview
    
    -- Animation state for preview
    frame.deckAnimElapsed = 0
    frame.deckAnimFrame = 0
    frame.deckAnimInfo = nil
    
    facePreview:SetScript("OnUpdate", function(self, dt)
        if not frame.deckAnimInfo then return end
        
        frame.deckAnimElapsed = frame.deckAnimElapsed + dt
        local animInfo = frame.deckAnimInfo
        local newFrame = math.floor(frame.deckAnimElapsed / animInfo.frameTime) % animInfo.numFrames
        
        if newFrame ~= frame.deckAnimFrame then
            frame.deckAnimFrame = newFrame
            -- Vertical sprite sheet with Y-flip
            local top = (newFrame + 1) / animInfo.numFrames
            local bottom = newFrame / animInfo.numFrames
            frame.cardDeckTexture:SetTexCoord(0, 1, top, bottom)
        end
    end)
    
    -- Arrow texture for navigation
    local ARROW_TEXTURE = "Interface\\AddOns\\Chairfaces Casino\\Textures\\Widgets\\arrow_right"
    
    -- Nav buttons for card deck
    local deckPrevBtn = BJ.Theme:Button(pageVis, "", 24, 24, "secondary", nil)
    deckPrevBtn:SetPoint("RIGHT", facePreview, "LEFT", -8, 0)
    local deckPrevTex = deckPrevBtn:CreateTexture(nil, "ARTWORK")
    deckPrevTex:SetSize(14, 14)
    deckPrevTex:SetPoint("CENTER")
    deckPrevTex:SetTexture(ARROW_TEXTURE)
    deckPrevTex:SetTexCoord(1, 0, 0, 1)  -- Flip horizontally for left arrow
    deckPrevBtn.texture = deckPrevTex
    deckPrevBtn:SetScript("OnClick", function()
        frame.currentDeckIndex = frame.currentDeckIndex - 1
        if frame.currentDeckIndex < 1 then frame.currentDeckIndex = #cardDecks end
        Lobby:UpdateCardDeckPreview()
    end)
    deckPrevBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    deckPrevBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    
    local deckNextBtn = BJ.Theme:Button(pageVis, "", 24, 24, "secondary", nil)
    deckNextBtn:SetPoint("LEFT", facePreview, "RIGHT", 8, 0)
    local deckNextTex = deckNextBtn:CreateTexture(nil, "ARTWORK")
    deckNextTex:SetSize(14, 14)
    deckNextTex:SetPoint("CENTER")
    deckNextTex:SetTexture(ARROW_TEXTURE)
    deckNextBtn.texture = deckNextTex
    deckNextBtn:SetScript("OnClick", function()
        frame.currentDeckIndex = frame.currentDeckIndex + 1
        if frame.currentDeckIndex > #cardDecks then frame.currentDeckIndex = 1 end
        Lobby:UpdateCardDeckPreview()
    end)
    deckNextBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    deckNextBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    
    local deckName = pageVis:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    deckName:SetPoint("TOP", facePreview, "BOTTOM", 0, -3)
    frame.cardDeckName = deckName
    
    local deckSelectBtn = BJ.Theme:Button(pageVis, "", 70, 22, "go", nil)
    deckSelectBtn:SetPoint("TOP", deckName, "BOTTOM", 0, -3)
    local deckSelectText = deckSelectBtn.text
    deckSelectText:SetText("Select")
    deckSelectBtn:SetScript("OnClick", function()
        local deck = cardDecks[frame.currentDeckIndex]
        Lobby:SelectCardDeck(deck.id)
    end)
    deckSelectBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.5, 0.3, 1) end)
    deckSelectBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.4, 0.2, 1) end)
    
    -- Card Back section
    local backLabel = pageVis:CreateFontString(nil, "OVERLAY", "CCFontNormal")
    backLabel:SetPoint("TOP", deckSelectBtn, "BOTTOM", 0, -12)
    backLabel:SetText("Card Back")
    
    local cardBacks = {
        { id = "blue", name = "Blue", texture = "back_blue" },
        { id = "red", name = "Red", texture = "back_red" },
        { id = "mtg", name = "MTG", texture = "back_mtg" },
        { id = "hs", name = "Hearthstone", texture = "back_hs" },
        { id = "warcraft", name = "Warcraft", texture = "back_warcraft" },
    }
    frame.cardBacks = cardBacks
    
    local savedBack = "blue"
    if BJ.db and BJ.db.settings and BJ.db.settings.cardBack then
        savedBack = BJ.db.settings.cardBack
    end
    frame.currentBackIndex = 1
    for i, back in ipairs(cardBacks) do
        if back.id == savedBack then
            frame.currentBackIndex = i
            break
        end
    end
    
    local cardPreview = CreateFrame("Frame", nil, pageVis, "BackdropTemplate")
    cardPreview:SetSize(60, 84)
    cardPreview:SetPoint("TOP", backLabel, "BOTTOM", 0, -5)
    BJ.Theme:Backdrop(cardPreview, "panel")
    
    local cardTex = cardPreview:CreateTexture(nil, "ARTWORK")
    cardTex:SetPoint("TOPLEFT", 2, -2)
    cardTex:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.cardBackTexture = cardTex
    
    -- Nav buttons for card back (using arrow texture)
    local prevBtn = BJ.Theme:Button(pageVis, "", 24, 24, "secondary", nil)
    prevBtn:SetPoint("RIGHT", cardPreview, "LEFT", -8, 0)
    local prevTex = prevBtn:CreateTexture(nil, "ARTWORK")
    prevTex:SetSize(14, 14)
    prevTex:SetPoint("CENTER")
    prevTex:SetTexture(ARROW_TEXTURE)
    prevTex:SetTexCoord(1, 0, 0, 1)  -- Flip horizontally for left arrow
    prevBtn.texture = prevTex
    prevBtn:SetScript("OnClick", function()
        frame.currentBackIndex = frame.currentBackIndex - 1
        if frame.currentBackIndex < 1 then frame.currentBackIndex = #cardBacks end
        Lobby:UpdateCardBackPreview()
    end)
    prevBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    prevBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    
    local nextBtn = BJ.Theme:Button(pageVis, "", 24, 24, "secondary", nil)
    nextBtn:SetPoint("LEFT", cardPreview, "RIGHT", 8, 0)
    local nextTex = nextBtn:CreateTexture(nil, "ARTWORK")
    nextTex:SetSize(14, 14)
    nextTex:SetPoint("CENTER")
    nextTex:SetTexture(ARROW_TEXTURE)
    nextBtn.texture = nextTex
    nextBtn:SetScript("OnClick", function()
        frame.currentBackIndex = frame.currentBackIndex + 1
        if frame.currentBackIndex > #cardBacks then frame.currentBackIndex = 1 end
        Lobby:UpdateCardBackPreview()
    end)
    nextBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    nextBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    
    local cardName = pageVis:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    cardName:SetPoint("TOP", cardPreview, "BOTTOM", 0, -3)
    frame.cardBackName = cardName
    
    local selectBtn = BJ.Theme:Button(pageVis, "", 70, 22, "go", nil)
    selectBtn:SetPoint("TOP", cardName, "BOTTOM", 0, -3)
    local selectText = selectBtn.text
    selectText:SetText("Select")
    selectBtn:SetScript("OnClick", function()
        local back = cardBacks[frame.currentBackIndex]
        Lobby:SelectCardBack(back.id)
    end)
    selectBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.5, 0.3, 1) end)
    selectBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.4, 0.2, 1) end)
    
    -- Dice section
    local diceLabel = pageVis:CreateFontString(nil, "OVERLAY", "CCFontNormal")
    diceLabel:SetPoint("TOP", selectBtn, "BOTTOM", 0, -12)
    diceLabel:SetText("Dice Style")
    
    -- Shared registry (numeric, white pips, red pips, scrimshaw texture)
    local diceStyles = BJ.DiceStyles
    frame.diceStyles = diceStyles
    
    local savedDice = "numeric"
    if BJ.db and BJ.db.settings and BJ.db.settings.diceStyle then
        savedDice = BJ.db.settings.diceStyle
    end
    frame.currentDiceIndex = 1
    for i, dice in ipairs(diceStyles) do
        if dice.id == savedDice then
            frame.currentDiceIndex = i
            break
        end
    end
    
    local dicePreview = CreateFrame("Frame", nil, pageVis, "BackdropTemplate")
    dicePreview:SetSize(48, 48)
    dicePreview:SetPoint("TOP", diceLabel, "BOTTOM", 0, -5)
    BJ.Theme:Backdrop(dicePreview, "inset")
    frame.dicePreview = dicePreview
    
    local diceTex = dicePreview:CreateTexture(nil, "ARTWORK")
    diceTex:SetPoint("TOPLEFT", 4, -4)
    diceTex:SetPoint("BOTTOMRIGHT", -4, 4)
    frame.diceTexture = diceTex
    
    -- Digit for the "numeric" style
    local diceText = dicePreview:CreateFontString(nil, "OVERLAY", "CCFontLarge")
    diceText:SetPoint("CENTER")
    diceText:SetText("|cff0000001|r")  -- Show 1 for preview
    frame.dicePreviewText = diceText

    -- Pip overlay for the "pips" styles - a sample face 5 (TL/TR/C/BL/BR)
    local pf = 12
    local pipOffsets = {
        TL = { -pf, pf }, TR = { pf, pf }, C = { 0, 0 },
        BL = { -pf, -pf }, BR = { pf, -pf },
    }
    frame.dicePips = {}
    for _, key in ipairs({ "TL", "TR", "C", "BL", "BR" }) do
        local pip = dicePreview:CreateTexture(nil, "OVERLAY")
        pip:SetSize(9, 9)
        pip:SetPoint("CENTER", dicePreview, "CENTER", pipOffsets[key][1], pipOffsets[key][2])
        pip:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        pip:Hide()
        frame.dicePips[key] = pip
    end
    
    -- Nav buttons for dice (using arrow texture like leaderboard)
    local ARROW_TEXTURE = "Interface\\AddOns\\Chairfaces Casino\\Textures\\Widgets\\arrow_right"
    
    local dicePrevBtn = BJ.Theme:Button(pageVis, "", 24, 24, "secondary", nil)
    dicePrevBtn:SetPoint("RIGHT", dicePreview, "LEFT", -8, 0)
    local dicePrevTex = dicePrevBtn:CreateTexture(nil, "ARTWORK")
    dicePrevTex:SetSize(14, 14)
    dicePrevTex:SetPoint("CENTER")
    dicePrevTex:SetTexture(ARROW_TEXTURE)
    dicePrevTex:SetTexCoord(1, 0, 0, 1)  -- Flip horizontally for left arrow
    dicePrevBtn.texture = dicePrevTex
    dicePrevBtn:SetScript("OnClick", function()
        frame.currentDiceIndex = frame.currentDiceIndex - 1
        if frame.currentDiceIndex < 1 then frame.currentDiceIndex = #diceStyles end
        Lobby:UpdateDicePreview()
    end)
    dicePrevBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    dicePrevBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    
    local diceNextBtn = BJ.Theme:Button(pageVis, "", 24, 24, "secondary", nil)
    diceNextBtn:SetPoint("LEFT", dicePreview, "RIGHT", 8, 0)
    local diceNextTex = diceNextBtn:CreateTexture(nil, "ARTWORK")
    diceNextTex:SetSize(14, 14)
    diceNextTex:SetPoint("CENTER")
    diceNextTex:SetTexture(ARROW_TEXTURE)
    diceNextBtn.texture = diceNextTex
    diceNextBtn:SetScript("OnClick", function()
        frame.currentDiceIndex = frame.currentDiceIndex + 1
        if frame.currentDiceIndex > #diceStyles then frame.currentDiceIndex = 1 end
        Lobby:UpdateDicePreview()
    end)
    diceNextBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.4, 0.4, 0.4, 1) end)
    diceNextBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.3, 0.3, 0.3, 1) end)
    
    local diceName = pageVis:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    diceName:SetPoint("TOP", dicePreview, "BOTTOM", 0, -3)
    frame.diceName = diceName
    
    local diceSelectBtn = BJ.Theme:Button(pageVis, "", 70, 22, "go", nil)
    diceSelectBtn:SetPoint("TOP", diceName, "BOTTOM", 0, -3)
    local diceSelectText = diceSelectBtn.text
    diceSelectText:SetText("Select")
    diceSelectBtn:SetScript("OnClick", function()
        local dice = diceStyles[frame.currentDiceIndex]
        Lobby:SelectDiceStyle(dice.id)
    end)
    diceSelectBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.5, 0.3, 1) end)
    diceSelectBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.4, 0.2, 1) end)
    
    -- ========== RIGHT COLUMN (Audio, Interface, Trixie) ==========
    local rightCol = 325  -- Center of right column
    local rightLeft = 230  -- Left edge of right column

    -- Audio section
    local audioLabel = pageVis:CreateFontString(nil, "OVERLAY", "CCFontNormal")
    audioLabel:SetPoint("TOP", pageVis, "TOPLEFT", rightCol, -20)
    audioLabel:SetText("Audio")

    local sfxBtn = BJ.Theme:Button(pageVis, "", 85, 26, "secondary", nil)
    sfxBtn:SetPoint("TOPLEFT", rightLeft, -38)
    local sfxIcon = sfxBtn.text
    sfxIcon:SetText("SFX ON")
    frame.sfxIcon = sfxIcon
    frame.sfxBtn = sfxBtn
    sfxBtn:SetScript("OnClick", function() Lobby:ToggleSFX() end)
    sfxBtn:SetScript("OnEnter", function(self)
        if Lobby.sfxEnabled then-- Brighter green hover
        else-- Gray hover
        end
    end)
    sfxBtn:SetScript("OnLeave", function(self)
        BJ.Theme:StyleButton(self)
        if Lobby.sfxEnabled then-- Green normal
        else-- Gray normal
        end
    end)
    
    local voiceBtn = BJ.Theme:Button(pageVis, "", 85, 26, "secondary", nil)
    voiceBtn:SetPoint("LEFT", sfxBtn, "RIGHT", 10, 0)
    local voiceIcon = voiceBtn.text
    voiceIcon:SetText("VOICE ON")
    frame.voiceIcon = voiceIcon
    frame.voiceBtn = voiceBtn
    voiceBtn:SetScript("OnClick", function() Lobby:ToggleVoice() end)
    voiceBtn:SetScript("OnEnter", function(self)
        if Lobby.voiceEnabled then-- Brighter green hover
        else-- Gray hover
        end
    end)
    voiceBtn:SetScript("OnLeave", function(self)
        BJ.Theme:StyleButton(self)
        if Lobby.voiceEnabled then-- Green normal
        else-- Gray normal
        end
    end)
    
    -- Voice Frequency
    local voiceFreqLabel = pageVis:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    voiceFreqLabel:SetPoint("TOPLEFT", rightLeft, -72)
    voiceFreqLabel:SetText("Voice Frequency:")

    local voiceFreqValue = pageVis:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    voiceFreqValue:SetPoint("TOPRIGHT", -20, -72)
    voiceFreqValue:SetText("|cff88ff88Normal|r")
    frame.voiceFreqValue = voiceFreqValue

    local voiceFreqSlider = CreateFrame("Slider", nil, pageVis, "OptionsSliderTemplate")
    voiceFreqSlider:SetSize(180, 14)
    voiceFreqSlider:SetPoint("TOPLEFT", rightLeft, -87)
    voiceFreqSlider:SetMinMaxValues(1, 5)
    voiceFreqSlider:SetValueStep(1)
    voiceFreqSlider:SetObeyStepOnDrag(true)
    voiceFreqSlider.Low:SetText("")
    voiceFreqSlider.High:SetText("")
    voiceFreqSlider.Text:SetText("")
    frame.voiceFreqSlider = voiceFreqSlider
    
    local function UpdateVoiceFreqDisplay()
        local sliderVal = voiceFreqSlider:GetValue()
        local freqNames = { "Always", "Frequent", "Normal", "Occasional", "Rare" }
        local freqValues = { 1, 2, 3, 5, 10 }
        local freqColors = { "00ff00", "88ff88", "ffffff", "ffaa66", "ff6666" }
        voiceFreqValue:SetText("|cff" .. freqColors[sliderVal] .. freqNames[sliderVal] .. "|r")
        Lobby:SetVoiceFrequency(freqValues[sliderVal])
    end
    voiceFreqSlider:SetScript("OnValueChanged", UpdateVoiceFreqDisplay)
    
    local initFreq = Lobby:GetVoiceFrequency()
    local initSlider = initFreq == 1 and 1 or initFreq == 2 and 2 or initFreq == 3 and 3 or initFreq == 5 and 4 or 5
    voiceFreqSlider:SetValue(initSlider)
    UpdateVoiceFreqDisplay()
    
    -- Interface section
    local interfaceLabel = pageVis:CreateFontString(nil, "OVERLAY", "CCFontNormal")
    interfaceLabel:SetPoint("TOP", pageVis, "TOPLEFT", rightCol, -124)
    interfaceLabel:SetText("Interface")

    -- Minimap slider
    local minimapLabel = pageVis:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    minimapLabel:SetPoint("TOPLEFT", rightLeft, -142)
    minimapLabel:SetText("Minimap Icon:")

    local minimapValue = pageVis:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    minimapValue:SetPoint("TOPRIGHT", -20, -142)
    minimapValue:SetText("|cff88ff881.5x|r")
    frame.minimapValue = minimapValue

    local minimapSlider = CreateFrame("Slider", nil, pageVis, "OptionsSliderTemplate")
    minimapSlider:SetSize(180, 14)
    minimapSlider:SetPoint("TOPLEFT", rightLeft, -157)
    minimapSlider:SetMinMaxValues(1.5, 5.0)
    minimapSlider:SetValueStep(0.5)
    minimapSlider:SetObeyStepOnDrag(true)
    minimapSlider.Low:SetText("1.5x")
    minimapSlider.High:SetText("5x")
    minimapSlider.Text:SetText("")
    frame.minimapSlider = minimapSlider
    
    local savedMinimapScale = 1.5
    if BJ.db and BJ.db.settings and BJ.db.settings.minimapScale then
        savedMinimapScale = BJ.db.settings.minimapScale
    end
    minimapSlider:SetValue(savedMinimapScale)
    
    local function UpdateMinimapDisplay()
        local val = minimapSlider:GetValue()
        minimapValue:SetText(string.format("|cff88ff88%.1fx|r", val))
        Lobby:SetMinimapScale(val)
    end
    minimapSlider:SetScript("OnValueChanged", UpdateMinimapDisplay)
    UpdateMinimapDisplay()
    
    -- Hide minimap checkbox
    local hideMinimapCheck = BJ.Theme:Check(pageVis, "", 16, nil)
    hideMinimapCheck:SetSize(22, 22)
    hideMinimapCheck:SetPoint("TOPLEFT", rightLeft, -184)
    hideMinimapCheck:SetScript("OnClick", function(self)
        local hide = self:GetChecked()
        if BJ.MinimapButton then
            if hide then BJ.MinimapButton:Hide() else BJ.MinimapButton:Show() end
        end
        if ChairfacesCasinoDB then ChairfacesCasinoDB.minimapHidden = hide end
    end)
    frame.hideMinimapCheck = hideMinimapCheck
    if ChairfacesCasinoDB and ChairfacesCasinoDB.minimapHidden then
        hideMinimapCheck:SetChecked(true)
    end

    local hideMinimapLabel = pageVis:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    hideMinimapLabel:SetPoint("LEFT", hideMinimapCheck, "RIGHT", 2, 0)
    hideMinimapLabel:SetText("Hide minimap icon")

    -- Mailbox helper checkbox (the "Buy Casino Credits" button on the mail window)
    local mailHelperCheck = BJ.Theme:Check(pageVis, "", 16, nil)
    mailHelperCheck:SetSize(22, 22)
    mailHelperCheck:SetPoint("TOPLEFT", rightLeft, -206)
    mailHelperCheck:SetScript("OnClick", function(self)
        local show = self:GetChecked()
        if BJ.db and BJ.db.settings then BJ.db.settings.showMailHelper = show end
        if BJ.Arcade and BJ.Arcade.UpdateMailHelperVisibility then BJ.Arcade:UpdateMailHelperVisibility() end
    end)
    mailHelperCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Show the 'Buy Casino Credits' button on the mail window")
        GameTooltip:Show()
    end)
    mailHelperCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.mailHelperCheck = mailHelperCheck
    local mailHelperChecked = true
    if BJ.db and BJ.db.settings then mailHelperChecked = BJ.db.settings.showMailHelper ~= false end
    mailHelperCheck:SetChecked(mailHelperChecked)

    local mailHelperLabel = pageVis:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    mailHelperLabel:SetPoint("LEFT", mailHelperCheck, "RIGHT", 2, 0)
    mailHelperLabel:SetText("Mailbox credits helper")

    -- Window Scale slider
    local windowLabel = pageVis:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    windowLabel:SetPoint("TOPLEFT", rightLeft, -234)
    windowLabel:SetText("Window Scale:")

    local windowValue = pageVis:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    windowValue:SetPoint("TOPRIGHT", -20, -234)
    windowValue:SetText("|cff88ff88100%|r")
    frame.windowValue = windowValue

    local windowSlider = CreateFrame("Slider", nil, pageVis, "OptionsSliderTemplate")
    windowSlider:SetSize(180, 14)
    windowSlider:SetPoint("TOPLEFT", rightLeft, -249)
    windowSlider:SetMinMaxValues(0.6, 1.2)
    windowSlider:SetValueStep(0.05)
    windowSlider:SetObeyStepOnDrag(true)
    windowSlider.Low:SetText("60%")
    windowSlider.High:SetText("120%")
    windowSlider.Text:SetText("")
    frame.windowSlider = windowSlider

    local savedWindowScale = 1.0
    if BJ.db and BJ.db.settings and BJ.db.settings.windowScale then
        savedWindowScale = BJ.db.settings.windowScale
    end
    windowSlider:SetValue(savedWindowScale)

    local function UpdateWindowDisplayText()
        local val = windowSlider:GetValue()
        windowValue:SetText(string.format("|cff88ff88%d%%|r", math.floor(val * 100 + 0.5)))
    end
    local function ApplyWindowScale()
        local val = windowSlider:GetValue()
        Lobby:SetWindowScale(val)
    end
    windowSlider:SetScript("OnValueChanged", UpdateWindowDisplayText)
    windowSlider:SetScript("OnMouseUp", ApplyWindowScale)
    UpdateWindowDisplayText()

    -- Show Trixie section label
    local trixieLabel = pageTrix:CreateFontString(nil, "OVERLAY", "CCFontNormal")
    trixieLabel:SetPoint("TOPLEFT", rightLeft, -292)
    trixieLabel:SetText("Show Trixie")

    -- Per-game Trixie toggles, laid out in two columns of five. Lobby keeps
    -- its legacy "showLobbyTrixie" key; every other game uses "<key>ShowTrixie".
    -- Games that mount Trixie through AttachTrixie (Hold'em, Death Roll, Bingo,
    -- Roulette, Liar's Dice, Chair's Cup) refresh live via RefreshGameTrixie;
    -- the bespoke Blackjack / Poker / High-Lo frames refresh themselves.
    local trixieGames = {
        { label = "Lobby",         key = "showLobbyTrixie", apply = function()
            Lobby:UpdateLobbyTrixieVisibility(); Lobby:UpdateHelpTrixieVisibility() end },
        { label = "Blackjack",     key = "blackjackShowTrixie", apply = function(show)
            if BJ.UI and BJ.UI.SetTrixieVisibility then BJ.UI:SetTrixieVisibility(show) end end },
        { label = "5 Card Stud",   key = "pokerShowTrixie", apply = function(show)
            if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.SetTrixieVisibility then BJ.UI.Poker:SetTrixieVisibility(show) end end },
        { label = "Texas Hold'em", key = "holdemShowTrixie", apply = function(show)
            if BJ.UI and BJ.UI.Holdem and BJ.UI.Holdem.SetTrixieVisibility then BJ.UI.Holdem:SetTrixieVisibility(show) end end },
        { label = "High-Lo",       key = "hiloShowTrixie", apply = function()
            if BJ.UI and BJ.UI.HiLo and BJ.UI.HiLo.UpdateTrixieVisibility then BJ.UI.HiLo:UpdateTrixieVisibility() end end },
        { label = "Death Roll",    key = "deathrollShowTrixie", apply = function() Lobby:RefreshGameTrixie("deathroll") end },
        { label = "Bingo",         key = "bingoShowTrixie", apply = function() Lobby:RefreshGameTrixie("bingo") end },
        { label = "Roulette",      key = "rouletteShowTrixie", apply = function() Lobby:RefreshGameTrixie("roulette") end },
        { label = "Liar's Dice",   key = "liarsdiceShowTrixie", apply = function() Lobby:RefreshGameTrixie("liarsdice") end },
        { label = "Crash", key = "crashShowTrixie", apply = function() Lobby:RefreshGameTrixie("crash") end },
        { label = "Chair's Cup",   key = "derbyShowTrixie", apply = function() Lobby:RefreshGameTrixie("derby") end },
    }
    frame.trixieChecks = {}
    local TRIXIE_COL2_X = rightLeft + 112
    local trixieHalf = math.ceil(#trixieGames / 2)
    for i, g in ipairs(trixieGames) do
        local col = (i <= trixieHalf) and 0 or 1
        local row = (i <= trixieHalf) and (i - 1) or (i - trixieHalf - 1)
        local x = (col == 0) and rightLeft or TRIXIE_COL2_X
        local y = -310 - row * 22
        local cb = BJ.Theme:Check(pageTrix, "", 16, nil)
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", x, y)
        cb:SetScript("OnClick", function(self)
            local show = self:GetChecked()
            if BJ.db and BJ.db.settings then BJ.db.settings[g.key] = show end
            if g.apply then g.apply(show) end
        end)
        local checked = true
        if BJ.db and BJ.db.settings then checked = BJ.db.settings[g.key] ~= false end
        cb:SetChecked(checked)
        local lbl = pageTrix:CreateFontString(nil, "OVERLAY", "CCFontSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        lbl:SetText(g.label)
        frame.trixieChecks[g.key] = cb
    end

    -- Select / unselect all: if everything is currently on, turn it all off,
    -- otherwise turn it all on. Updates the checkboxes and applies live.
    local trixieAllBtn = BJ.Theme:Button(pageTrix, "", 100, 22, "secondary", nil)
    trixieAllBtn:SetSize(84, 18)
    trixieAllBtn:SetPoint("TOPLEFT", rightLeft + 114, -288)
    trixieAllBtn:SetText("All On/Off")
    trixieAllBtn:SetScript("OnClick", function()
        local allOn = true
        for _, g in ipairs(trixieGames) do
            if BJ.db and BJ.db.settings and BJ.db.settings[g.key] == false then
                allOn = false
                break
            end
        end
        local newVal = not allOn
        for _, g in ipairs(trixieGames) do
            if BJ.db and BJ.db.settings then BJ.db.settings[g.key] = newVal end
            if frame.trixieChecks[g.key] then frame.trixieChecks[g.key]:SetChecked(newVal) end
            if g.apply then g.apply(newVal) end
        end
    end)

    -- Replay Intro button (was "Meet Trixie!")
    local replayIntroBtn = BJ.Theme:Button(pageTrix, "", 180, 28, "danger", nil)
    replayIntroBtn:SetPoint("TOPLEFT", rightLeft, -450)
    local replayIntroText = replayIntroBtn.text
    replayIntroText:SetText("Replay Intro")
    replayIntroBtn:SetScript("OnClick", function()
        frame:Hide()
        if Lobby.frame then Lobby.frame:Hide() end
        Lobby:ShowTrixieIntro()
    end)
    replayIntroBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.5, 0.3, 0.4, 1) end)
    replayIntroBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.4, 0.2, 0.3, 1) end)

    -- Trixie chatter: her table calls, lobby greeting, and idle banter
    local chatterCb = BJ.Theme:Check(pageTrix, "", 16, nil)
    chatterCb:SetSize(22, 22)
    chatterCb:SetPoint("TOPLEFT", rightLeft + 192, -452)
    chatterCb:SetScript("OnClick", function(self)
        if BJ.db and BJ.db.settings then BJ.db.settings.trixieChatter = self:GetChecked() end
    end)
    do
        local on = true
        if BJ.db and BJ.db.settings then on = BJ.db.settings.trixieChatter ~= false end
        chatterCb:SetChecked(on)
    end
    local chatterLbl = pageTrix:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    chatterLbl:SetPoint("LEFT", chatterCb, "RIGHT", 2, 0)
    chatterLbl:SetText("Trixie table calls & banter")

    -- Announce open tables in the host's party/raid chat (reaches non-addon
    -- group members); never leaves the group.
    local yellCb = BJ.Theme:Check(pageTrix, "", 16, nil)
    yellCb:SetSize(22, 22)
    yellCb:SetPoint("TOPLEFT", rightLeft + 192, -474)
    yellCb:SetScript("OnClick", function(self)
        if BJ.db and BJ.db.settings then
            BJ.db.settings.trixiePublicChannel = self:GetChecked() and "GROUP" or "OFF"
        end
    end)
    do
        local on = true
        if BJ.db and BJ.db.settings then
            on = (BJ.db.settings.trixiePublicChannel or "GROUP") ~= "OFF"
        end
        yellCb:SetChecked(on)
    end
    local yellLbl = pageTrix:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    yellLbl:SetPoint("LEFT", yellCb, "RIGHT", 2, 0)
    yellLbl:SetText("Announce open tables in party/raid chat")

    -- Debug section (hidden unless debug mode) - positioned below Replay Intro button
    local pokeSection = CreateFrame("Frame", nil, pageTrix)
    pokeSection:SetSize(180, 40)
    pokeSection:SetPoint("TOPLEFT", rightLeft, -488)
    frame.pokeSection = pokeSection
    
    local pokeLabel = pokeSection:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    pokeLabel:SetPoint("TOPLEFT", 0, 0)
    pokeLabel:SetText("|cffff00ffDebug:|r Poke (1 in X):")
    
    local pokeInput = CreateFrame("EditBox", nil, pokeSection, "BackdropTemplate")
    pokeInput:SetSize(50, 18)
    pokeInput:SetPoint("TOPLEFT", 0, -15)
    pokeInput:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    pokeInput:SetBackdropColor(0.15, 0.15, 0.2, 1)
    pokeInput:SetBackdropBorderColor(0.5, 0.3, 0.5, 1)
    pokeInput:SetFontObject(GameFontNormalSmall)
    pokeInput:SetTextColor(1, 1, 1)
    pokeInput:SetJustifyH("CENTER")
    pokeInput:SetAutoFocus(false)
    pokeInput:SetNumeric(true)
    pokeInput:SetMaxLetters(5)
    pokeInput:SetText(tostring(Lobby:GetPokeChance()))
    pokeInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    pokeInput:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText()) or 500
        if val < 1 then val = 1 end
        Lobby:SetPokeChance(val)
        self:SetText(tostring(val))
        self:ClearFocus()
    end)
    frame.pokeInput = pokeInput
    
    if not (BJ.TestMode and BJ.TestMode.enabled) then
        pokeSection:Hide()
    end
    
    -- Debug: Clear DB button (only visible in debug mode)
    local clearDbBtn = BJ.Theme:Button(frame, "", 120, 28, "danger", nil)
    clearDbBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 15)
    
    local clearDbText = clearDbBtn.text
    clearDbText:SetText("Clear Leaderboard DB")
    
    clearDbBtn:SetScript("OnEnter", function(self)

        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Clear All Leaderboard Data", 1, 0.6, 0.3)
        GameTooltip:AddLine("DEBUG: Wipes local DB and broadcasts", 1, 1, 1)
        GameTooltip:AddLine("clear command to all group members", 1, 1, 1)
        GameTooltip:Show()
    end)
    clearDbBtn:SetScript("OnLeave", function(self)
        BJ.Theme:StyleButton(self)
        GameTooltip:Hide()
    end)
    clearDbBtn:SetScript("OnClick", function()
        StaticPopupDialogs["CASINO_CLEAR_ALL_DB"] = {
            text = "|cffff6666WARNING:|r Clear ALL leaderboard data?\n\nThis will wipe your local database AND send a clear command to all party members!\n\n|cffff9944This cannot be undone!|r",
            button1 = "Clear All",
            button2 = "Cancel",
            OnAccept = function()
                if BJ.Leaderboard then
                    BJ.Leaderboard:ClearAllData(true)
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("CASINO_CLEAR_ALL_DB")
    end)
    
    frame.clearDbBtn = clearDbBtn
    if not (BJ.TestMode and BJ.TestMode.enabled) then
        clearDbBtn:Hide()
    end
    
    -- ===== Auto-open hosted games (the aggregate list) =====
    -- One checkbox per game: when someone hosts THAT game, its window
    -- pops open for you - only the games you tick here, no others.
    -- (GameComm:MaybeAutoOpen drives it; the derby keeps its own
    -- SigmaDerbyDB.autoOpen storage, mirrored by its in-window checkbox.)
    local aoLabel = pageAuto:CreateFontString(nil, "OVERLAY", "CCFontNormal")
    aoLabel:SetPoint("TOPLEFT", 20, -562)
    aoLabel:SetText("|cffffd700Auto-open when someone hosts:|r")

    local function autoOpenGet(key)
        if key == "derby" then
            return (SigmaDerbyDB and SigmaDerbyDB.autoOpen) and true or false
        end
        local a = BJ.db and BJ.db.settings and BJ.db.settings.autoOpen
        return (a and a[key]) and true or false
    end
    local function autoOpenSet(key, val)
        if key == "derby" then
            SigmaDerbyDB = SigmaDerbyDB or {}
            SigmaDerbyDB.autoOpen = val
            return
        end
        BJ.db = BJ.db or ChairfacesCasinoDB or {}
        BJ.db.settings = BJ.db.settings or {}
        BJ.db.settings.autoOpen = BJ.db.settings.autoOpen or {}
        BJ.db.settings.autoOpen[key] = val or nil
    end

    frame.autoOpenChecks = {}
    for i, entry in ipairs(Lobby.gameList) do
        local col = (i % 2 == 1) and 0 or 1
        local row = math.floor((i - 1) / 2)
        local cb = BJ.Theme:Check(pageAuto, "", 16, nil)
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", 24 + col * 210, -582 - row * 22)
        cb:SetChecked(autoOpenGet(entry.key))
        cb:SetScript("OnClick", function(self)
            autoOpenSet(entry.key, self:GetChecked() and true or false)
        end)
        local lbl = pageAuto:CreateFontString(nil, "OVERLAY", "CCFontSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        lbl:SetText(entry.name)
        frame.autoOpenChecks[entry.key] = cb
    end

    -- minimap behavior: on (default) = left-click jumps to the hosted
    -- game; off = the original always-open-the-lobby behavior
    local mmCB = BJ.Theme:Check(pageAuto, "", 16, nil)
    mmCB:SetSize(22, 22)
    mmCB:SetPoint("TOPLEFT", 24, -700)
    mmCB:SetChecked(not (BJ.db and BJ.db.settings and
        BJ.db.settings.minimapOpensGame == false))
    mmCB:SetScript("OnClick", function(self)
        BJ.db = BJ.db or ChairfacesCasinoDB or {}
        BJ.db.settings = BJ.db.settings or {}
        BJ.db.settings.minimapOpensGame = self:GetChecked() and true or false
    end)
    local mmLbl = pageAuto:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    mmLbl:SetPoint("LEFT", mmCB, "RIGHT", 2, 0)
    mmLbl:SetText("Minimap click opens the hosted game (off = always the lobby)")
    frame.minimapOpensGameCheck = mmCB

    -- the derby's own checkbox can change autoOpen behind our back:
    -- re-read everything whenever the panel comes up
    frame:HookScript("OnShow", function()
        for key, cb in pairs(frame.autoOpenChecks) do
            cb:SetChecked(autoOpenGet(key))
        end
        mmCB:SetChecked(not (BJ.db and BJ.db.settings and
            BJ.db.settings.minimapOpensGame == false))
    end)

    selectTab(1)
    frame:Hide()
    self.settingsFrame = frame

    -- Initialize previews
    self:UpdateCardBackPreview()
    self:UpdateCardDeckPreview()
    self:UpdateDicePreview()
end

function Lobby:UpdateCardBackPreview()
    if not self.settingsFrame then return end
    
    local frame = self.settingsFrame
    local back = frame.cardBacks[frame.currentBackIndex]
    
    frame.cardBackTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\cards\\" .. back.texture)
    frame.cardBackName:SetText("|cffffffff" .. back.name .. "|r")
end

function Lobby:SelectCardBack(backId)
    -- Ensure db is initialized
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = { cardBack = "blue" } }
    end
    if not BJ.db.settings then
        BJ.db.settings = { cardBack = "blue" }
    end
    
    BJ.db.settings.cardBack = backId
    
    -- Update cards in game
    if BJ.UI and BJ.UI.Cards then
        BJ.UI.Cards:SetCardBack(backId)
    end
    
    -- Find index and update preview to show selected
    if self.settingsFrame then
        for i, back in ipairs(self.settingsFrame.cardBacks) do
            if back.id == backId then
                self.settingsFrame.currentBackIndex = i
                break
            end
        end
        self:UpdateCardBackPreview()
    end
    
    BJ:Print("Card back set to: " .. backId)
end

function Lobby:UpdateDicePreview()
    if not self.settingsFrame then return end

    local frame = self.settingsFrame
    local dice = frame.diceStyles[frame.currentDiceIndex]

    -- Reset every preview element, then show the one this style uses.
    frame.diceTexture:Hide()
    frame.dicePreviewText:Hide()
    for _, pip in pairs(frame.dicePips or {}) do pip:Hide() end

    if dice.render == "texture" and dice.folder then
        frame.diceTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\dice\\" .. dice.folder .. "\\die_1")
        frame.diceTexture:Show()
        frame.dicePreview:SetBackdropColor(0.1, 0.1, 0.1, 1)
    elseif dice.render == "pips" then
        local d, p = dice.dieColor, dice.pipColor
        frame.dicePreview:SetBackdropColor(d[1], d[2], d[3], 1)
        for _, key in ipairs({ "TL", "TR", "C", "BL", "BR" }) do
            local pip = frame.dicePips[key]
            pip:SetVertexColor(p[1], p[2], p[3], 1)
            pip:Show()
        end
    else
        -- Numeric: a digit tinted with the pip color on the die-body color.
        local d = dice.dieColor or { 1, 1, 1 }
        local p = dice.pipColor or { 0, 0, 0 }
        frame.dicePreview:SetBackdropColor(d[1], d[2], d[3], 1)
        frame.dicePreviewText:SetText(string.format("|cff%02x%02x%02x", math.floor(p[1] * 255),
            math.floor(p[2] * 255), math.floor(p[3] * 255)) .. "1|r")
        frame.dicePreviewText:Show()
    end

    frame.diceName:SetText("|cffffffff" .. dice.name .. "|r")
end

function Lobby:SelectDiceStyle(styleId)
    -- Ensure db is initialized
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = {} }
    end
    if not BJ.db.settings then
        BJ.db.settings = {}
    end
    
    BJ.db.settings.diceStyle = styleId

    -- Find index and update preview to show selected
    if self.settingsFrame then
        for i, dice in ipairs(self.settingsFrame.diceStyles) do
            if dice.id == styleId then
                self.settingsFrame.currentDiceIndex = i
                break
            end
        end
        self:UpdateDicePreview()
    end
    
    BJ:Print("Dice style set to: " .. styleId)
end

function Lobby:UpdateCardDeckPreview()
    if not self.settingsFrame then return end
    
    local frame = self.settingsFrame
    local deck = frame.cardDecks[frame.currentDeckIndex]
    
    -- Check if this deck has animated cards (show Ace of Spades as preview)
    local animInfo = nil
    if deck.id == "warcraft" and BJ.UI and BJ.UI.Cards then
        animInfo = BJ.UI.Cards.animatedCards["A_spades"]
    end
    
    if animInfo then
        -- Use animated sprite sheet
        frame.cardDeckTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\" .. deck.path .. "\\" .. animInfo.spriteFile)
        frame.deckAnimInfo = animInfo
        frame.deckAnimElapsed = 0
        frame.deckAnimFrame = 0
        -- Set initial frame (Y-flipped)
        local top = 1 / animInfo.numFrames
        local bottom = 0
        frame.cardDeckTexture:SetTexCoord(0, 1, top, bottom)
    else
        -- Static texture
        frame.cardDeckTexture:SetTexture("Interface\\AddOns\\Chairfaces Casino\\Textures\\" .. deck.path .. "\\" .. deck.texture)
        frame.cardDeckTexture:SetTexCoord(0, 1, 0, 1)
        frame.deckAnimInfo = nil
    end
    
    frame.cardDeckName:SetText("|cffffffff" .. deck.name .. "|r")
end

function Lobby:SelectCardDeck(deckId)
    -- Ensure db is initialized
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = { cardDeck = "classic" } }
    end
    if not BJ.db.settings then
        BJ.db.settings = { cardDeck = "classic" }
    end
    
    BJ.db.settings.cardDeck = deckId
    
    -- Update cards system
    if BJ.UI and BJ.UI.Cards then
        BJ.UI.Cards:SetCardDeck(deckId)
    end
    
    -- Find index and update preview to show selected
    if self.settingsFrame then
        for i, deck in ipairs(self.settingsFrame.cardDecks) do
            if deck.id == deckId then
                self.settingsFrame.currentDeckIndex = i
                break
            end
        end
        self:UpdateCardDeckPreview()
    end
    
    BJ:Print("Card deck set to: " .. deckId)
end

function Lobby:SetMinimapScale(scale)
    -- Ensure db is initialized
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = {} }
    end
    if not BJ.db.settings then
        BJ.db.settings = {}
    end
    
    BJ.db.settings.minimapScale = scale
    
    -- Apply to minimap button
    if BJ.MinimapButton and BJ.MinimapButton.button then
        local baseSize = 32
        local newSize = baseSize * scale
        BJ.MinimapButton.button:SetSize(newSize, newSize)
        BJ.MinimapButton.currentScale = scale  -- Store for hover sizing
        
        -- Scale the overlay and background textures
        if BJ.MinimapButton.button.overlay then
            local overlaySize = 53 * scale
            BJ.MinimapButton.button.overlay:SetSize(overlaySize, overlaySize)
        end
        if BJ.MinimapButton.button.background then
            local bgSize = 20 * scale
            BJ.MinimapButton.button.background:SetSize(bgSize, bgSize)
        end
    end
end

function Lobby:SetWindowScale(scale)
    -- Ensure db is initialized
    if not BJ.db then
        BJ.db = ChairfacesCasinoDB or { settings = {} }
    end
    if not BJ.db.settings then
        BJ.db.settings = {}
    end
    
    BJ.db.settings.windowScale = scale
    
    -- Apply to all casino windows
    local windows = {}
    
    -- Lobby
    if self.frame then
        table.insert(windows, self.frame)
    end
    
    -- Blackjack (uses mainFrame)
    if BJ.UI and BJ.UI.mainFrame then
        table.insert(windows, BJ.UI.mainFrame)
    end
    
    -- Poker
    if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.mainFrame then
        table.insert(windows, BJ.UI.Poker.mainFrame)
    end
    
    -- High-Lo (uses container as outer frame)
    if BJ.UI and BJ.UI.HiLo and BJ.UI.HiLo.container then
        table.insert(windows, BJ.UI.HiLo.container)
    end
    
    -- Settings panel
    if self.settingsFrame then
        table.insert(windows, self.settingsFrame)
    end
    
    -- Lobby Trixie
    if self.lobbyTrixie then
        table.insert(windows, self.lobbyTrixie)
    end
    
    for _, window in ipairs(windows) do
        if window and window.SetScale then
            window:SetScale(scale)
        end
    end
    
end

-- Open an auxiliary window (Settings/Leaderboard/Debts) FROM the lobby: hide
-- the lobby, show the window, and hook it (once) so closing it reopens the
-- lobby. The per-frame flag means closing that window from a game or a slash
-- command (where it wasn't opened from the lobby) won't pop the lobby.
function Lobby:OpenFromLobby(show, getFrame)
    if self.frame then self.frame:Hide() end
    self:HideHelp(true)
    show()
    local f = getFrame()
    if f then
        if not f.__lobbyReturnHooked then
            f.__lobbyReturnHooked = true
            f:HookScript("OnHide", function()
                if f.__returnToLobby then
                    f.__returnToLobby = false
                    Lobby:Show()
                end
            end)
        end
        f.__returnToLobby = true
    end
end

function Lobby:ToggleSettings()
    if not self.settingsFrame then
        self:CreateSettingsPanel()
    end
    
    if self.settingsFrame:IsShown() then
        self.settingsFrame:Hide()
    else
        self:ShowSettings()
    end
end

function Lobby:ShowSettings()
    if not self.settingsFrame then
        self:CreateSettingsPanel()
    end
    
    -- Set current index to match saved setting
    local currentBack = "blue"
    if BJ.db and BJ.db.settings and BJ.db.settings.cardBack then
        currentBack = BJ.db.settings.cardBack
    end
    for i, back in ipairs(self.settingsFrame.cardBacks) do
        if back.id == currentBack then
            self.settingsFrame.currentBackIndex = i
            break
        end
    end
    
    -- Update deck selection to match current setting
    local currentDeck = "classic"
    if BJ.db and BJ.db.settings and BJ.db.settings.cardDeck then
        currentDeck = BJ.db.settings.cardDeck
    end
    for i, deck in ipairs(self.settingsFrame.cardDecks) do
        if deck.id == currentDeck then
            self.settingsFrame.currentDeckIndex = i
            break
        end
    end
    
    self:UpdateCardBackPreview()
    self:UpdateCardDeckPreview()
    self:UpdateAudioControls()
    
    -- Update debug section visibility
    if self.settingsFrame.pokeSection then
        if BJ.TestMode and BJ.TestMode.enabled then
            self.settingsFrame.pokeSection:Show()
            -- Update the poke input value
            if self.settingsFrame.pokeInput then
                self.settingsFrame.pokeInput:SetText(tostring(self:GetPokeChance()))
            end
        else
            self.settingsFrame.pokeSection:Hide()
        end
    end
    
    self.settingsFrame:Show()
end
