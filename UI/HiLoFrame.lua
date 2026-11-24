--[[
    Chairface's Casino - UI/HiLoFrame.lua
    High-Lo game window with Trixie tall beside it
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.HiLo = {}
local HiLo = UI.HiLo

-- Frame dimensions
local FRAME_WIDTH = 320       -- room for the standard title band
local FRAME_WIDTH_WIDE = 520  -- Width when using 2 columns (20+ players)
local FRAME_MIN_HEIGHT = 384  -- Covers the LOG button and the taller header band
local PLAYER_ROW_HEIGHT = 18  -- Reduced from 28 to fit more players
local DUAL_COLUMN_THRESHOLD = 20  -- Switch to 2 columns at this many players

-- Initialize
function HiLo:Initialize()
    if self.frame then return end
    self:CreateFrame()
    self:RegisterRollEvents()
end

-- Create the main frame
function HiLo:CreateFrame()
    -- Shared casino window (UI/Chrome.lua). Trixie stands beside it
    -- (GameWindow:EmbedTrixie) instead of sharing a container with it.
    local frame = UI.Chrome:CreateWindow({
        name = "ChairfacesCasinoHiLo",
        title = "High-Lo",
        width = FRAME_WIDTH, height = FRAME_MIN_HEIGHT,
        art = "felt", artW = 1280, artH = 714,
        howTo = "hilo",
        debts = true,
        onLog = function() HiLo:ToggleLog() end,
        leaderboard = "hilo",
        onRefresh = function()
            HiLo:Hide()
            C_Timer.After(0.05, function() HiLo:Show() end)
        end,
        onClose = function()
            HiLo:Hide()
            if UI.Lobby then UI.Lobby:Show() end
        end,
    })
    self.frame = frame
    self.container = frame          -- older code shows/hides "the container"
    self.closeBtn = frame.closeBtn
    self.sessionBtn = frame.debtsBtn
    self.allTimeBtn = frame.leaderboardBtn
    local title = frame.titleText
    self.title = title

    self:MountTrixie(frame)

    -- Status text (below title)
    local status = frame:CreateFontString(nil, "OVERLAY", "CCFontNormal")
    status:SetPoint("TOP", frame.titleBar, "BOTTOM", 0, -5)
    status:SetText("")
    self.statusText = status
    
    -- Settlement background frame (shown during settlement) - starts on the felt,
    -- just below the expanded header band so it clears the How-to-Play button.
    local settlementBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    settlementBg:SetPoint("TOP", frame, "TOP", 0, -96)  -- below the status lines
    settlementBg:SetPoint("LEFT", 15, 0)
    settlementBg:SetPoint("RIGHT", -15, 0)
    settlementBg:SetHeight(80)  -- Will auto-resize
    BJ.Theme:Backdrop(settlementBg, "inset")
    settlementBg:Hide()
    self.settlementBg = settlementBg
    
    -- Settlement text (shown during settlement) - parented to settlementBg so it's above
    local settlement = settlementBg:CreateFontString(nil, "OVERLAY", "CCFontNormal")
    settlement:SetPoint("TOP", settlementBg, "TOP", 0, -8)
    settlement:SetWidth(FRAME_WIDTH - 40)
    settlement:SetSpacing(4)  -- 4pt gap between lines
    settlement:SetText("")
    self.settlementText = settlement
    
    -- Player list container
    local listContainer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    listContainer:SetPoint("TOP", settlementBg, "BOTTOM", 0, -5)
    listContainer:SetPoint("LEFT", 10, 0)
    listContainer:SetPoint("RIGHT", -10, 0)
    listContainer:SetHeight(150)  -- Will be resized
    BJ.Theme:Backdrop(listContainer, "inset")
    self.listContainer = listContainer
    
    -- Player rows (created dynamically)
    self.playerRows = {}
    
    -- Button container at bottom (smaller now that host/join share position)
    local btnContainer = CreateFrame("Frame", nil, frame)
    btnContainer:SetSize(FRAME_WIDTH - 20, 60)
    btnContainer:SetPoint("BOTTOM", 0, 10)
    self.btnContainer = btnContainer
    
    -- Create centered action button (Host/Join) - positioned under host settings panel
    local actionBtn = BJ.Theme:Button(frame, "", 180, 54, "go", "HiLoActionButton")
    actionBtn:SetPoint("CENTER", frame, "CENTER", 0, -115)  -- Under host settings panel
    actionBtn:SetFrameLevel(frame:GetFrameLevel() + 100)  -- Above everything
    
    local actionText = actionBtn.text
    actionText:SetText("HOST")
    actionBtn.text = actionText
    
    actionBtn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
        end
    end)
    actionBtn:SetScript("OnLeave", function(self)
        BJ.Theme:StyleButton(self)
        if self:IsEnabled() then
        end
    end)
    actionBtn:SetScript("OnClick", function() HiLo:OnActionButtonClick() end)
    self.actionButton = actionBtn
    
    -- Start button (host only) - positioned above player table
    local startBtn = BJ.Theme:Button(frame, "", 120, 30, "primary", nil)
    startBtn:SetPoint("BOTTOM", listContainer, "TOP", 0, 5)  -- Above player table
    startBtn:SetFrameLevel(frame:GetFrameLevel() + 50)
    local startText = startBtn.text
    startText:SetText("START")
    startBtn:SetScript("OnClick", function() HiLo:OnStartClick() end)
    startBtn:Hide()
    self.startBtn = startBtn
    
    -- Roll button (during rolling phase) - positioned above player table
    local rollBtn = BJ.Theme:Button(frame, "", 200, 35, "arcade", nil)
    rollBtn:SetPoint("BOTTOM", listContainer, "TOP", 0, 5)  -- Above player table
    rollBtn:SetFrameLevel(frame:GetFrameLevel() + 50)
    local rollText = rollBtn.text
    rollText:SetText("/roll 100")
    self.rollBtnText = rollText
    rollBtn:SetScript("OnClick", function() HiLo:OnRollClick() end)
    rollBtn:Hide()
    self.rollBtn = rollBtn
    
    -- Reset button (host only, shown during active game)
    local resetBtn = BJ.Theme:Button(btnContainer, "", 60, 22, "danger", nil)
    resetBtn:SetPoint("BOTTOMRIGHT", btnContainer, "BOTTOMRIGHT", 0, 0)
    local resetText = resetBtn.text
    resetText:SetText("Reset")
    resetBtn:SetScript("OnClick", function() HiLo:OnResetClick() end)
    resetBtn:Hide()
    self.resetBtn = resetBtn
    
    self.logBtn = frame.logBtn

    -- Timer box (visible countdown during rolling phase)
    local timerBox = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    timerBox:SetSize(140, 40)
    timerBox:SetPoint("TOP", frame, "TOP", 0, -75)  -- Below title area, on felt
    BJ.Theme:Backdrop(timerBox, "panel")
    timerBox:SetFrameLevel(frame:GetFrameLevel() + 50)
    timerBox:Hide()
    self.timerBox = timerBox
    
    -- Timer text (inside timer box)
    local timerText = timerBox:CreateFontString(nil, "OVERLAY", "CCFontLarge")
    timerText:SetPoint("CENTER", timerBox, "CENTER", 0, 0)
    timerText:SetText("")
    self.timerText = timerText
    
    -- Create host settings panel (hidden by default)
    self:CreateHostPanel()
    
    -- Create test mode bar (hidden by default)
    self:CreateTestModeBar()
    
    -- Update timer
    frame:SetScript("OnUpdate", function(self, elapsed)
        HiLo:OnUpdate(elapsed)
    end)
end

-- Create test mode bar for High-Lo
function HiLo:CreateTestModeBar()
    local GW = UI.GameWindow
    local bar = GW:TestBar(self, self.frame, GW:Specs({
        { text = "+TEST", width = 50, onClick = function()
            if BJ.TestMode then BJ.TestMode:AddHiLoFakePlayer() end
        end },
        { text = "-TEST", width = 50, onClick = function()
            if BJ.TestMode then BJ.TestMode:RemoveHiLoFakePlayer() end
        end },
        { text = "ROLL", width = 45, onClick = function()
            -- roll for the fake players, or the tiebreaker
            local HL = BJ.HiLoState
            if not BJ.TestMode then return end
            if HL.phase == HL.PHASE.ROLLING then
                BJ.TestMode:SimulateHiLoRolls()
            elseif HL.phase == HL.PHASE.TIEBREAKER then
                BJ.TestMode:SimulateHiLoTiebreakerRolls()
            end
        end },
        { text = "CLEAR", width = 50, onClick = function()
            if BJ.TestMode then BJ.TestMode:ClearHiLoFakePlayers() end
        end },
    }, GW:CommonTestTools(self)))
    self.testModeBar = bar
    bar.trixToggleBtn = bar.buttons.trix
end

function HiLo:CreateHostPanel()
    -- the shared host settings popup (UI/HostForm.lua)
    local form = UI.HostForm:Create({
        name = "HiLoHostPanel",
        title = "High-Lo - Host",
        startText = "Open Table",
        onStart = function() HiLo:OnConfirmHost() end,
    })
    form:Number("hiloMaxRoll", "Max Roll:", { default = 100, min = 2, max = 999999, letters = 6 })
    form:Countdown("hiloTimerEnabled", "hiloTimerSeconds", "Join Timer:")
    form:Finish()
    self.hostForm = form
    self.hostPanel = form.frame
end

--[[
    TRIXIE STATE MANAGEMENT
    Trixie reacts to local player's game events
]]

-- Moods come from GameWindow:EmbedTrixie. UpdateTrixieForGameState runs on
-- every refresh, so a reaction only starts when the state changes (a clip
-- would otherwise restart on each update).
local function trixieMood(self, state, method)
    if state ~= "wait" and self.currentTrixieState == state then return end
    self.currentTrixieState = state
    UI.GameWindow.MOOD[method](self)
end

-- Update Trixie based on game phase and local player status
function HiLo:UpdateTrixieForGameState()
    if not self.trixieFrame then return end
    if not self:ShouldShowTrixie() then return end
    
    local HL = BJ.HiLoState
    local UI = BJ.UI
    local myName = BJ:MyName()
    local isInGame = HL.players[myName] ~= nil
    
    if HL.phase == HL.PHASE.IDLE then
        -- No game - waiting
        self:SetTrixieWait()
        self.settlementAudioPlayed = nil  -- Reset flag
        
    elseif HL.phase == HL.PHASE.LOBBY then
        -- Waiting for game to start
        self:SetTrixieWait()
        self.settlementAudioPlayed = nil  -- Reset flag
        
    elseif HL.phase == HL.PHASE.ROLLING then
        -- Rolling phase - waiting
        self:SetTrixieWait()
        
    elseif HL.phase == HL.PHASE.TIEBREAKER then
        -- Tiebreaker - waiting
        self:SetTrixieWait()
        
    elseif HL.phase == HL.PHASE.SETTLEMENT then
        -- Check if local player won or lost
        if HL.highPlayer == myName then
            -- Local player won!
            local winAmount = HL.winAmount or 0
            if winAmount >= 50 then
                self:SetTrixieLove()  -- Big win!
            else
                self:SetTrixieCheer()  -- Normal win
            end
            -- Play win audio once
            if not self.settlementAudioPlayed then
                self.settlementAudioPlayed = true
                if UI and UI.Lobby then
                    UI.Lobby:PlayWinSound()
                    UI.Lobby:PlayTrixieWoohooVoice()
                end
            end
        elseif HL.lowPlayer == myName then
            -- Local player lost
            self:SetTrixieLose()
            -- Play bad audio once
            if not self.settlementAudioPlayed then
                self.settlementAudioPlayed = true
                if UI and UI.Lobby then
                    UI.Lobby:PlayTrixieBadVoice()
                end
            end
        else
            -- Local player wasn't in the final (spectating or was eliminated in tie)
            self:SetTrixieWait()
        end
    end
end

-- Register for roll events
function HiLo:RegisterRollEvents()
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
    eventFrame:SetScript("OnEvent", function(self, event, msg)
        HiLo:OnChatMessage(msg)
    end)
    self.eventFrame = eventFrame
end

-- Parse roll messages
function HiLo:OnChatMessage(msg)
    local HL = BJ.HiLoState
    local HLM = BJ.HiLoMultiplayer
    
    -- Parse roll message: "First Last rolls X (1-Y)". BJ:ParseRoll reads
    -- two-word Forever names and secret lines safely.
    local playerName, roll, maxRoll = BJ:ParseRoll(msg)

    if not playerName or not roll or not maxRoll then return end
    
    -- Handle main rolling phase
    if HL.phase == HL.PHASE.ROLLING then
        -- Only accept rolls with the correct max roll value
        if maxRoll ~= HL.maxRoll then
            return  -- Ignore rolls with wrong max
        end
        
        -- Check if player is in our game
        if HL.players[playerName] then
            local prevPhase = HL.phase
            
            -- Before recording, check if local player had the high roll and might get overtaken
            local myName = BJ:MyName()
            local myPlayer = HL.players[myName]
            local myRoll = myPlayer and myPlayer.roll
            local wasLeading = false
            local myRollPercent = 0
            
            if myRoll and myRoll > 0 then
                myRollPercent = myRoll / (HL.maxRoll or 100)
                -- Check if we were leading before this roll
                wasLeading = true
                for name, p in pairs(HL.players) do
                    if name ~= myName and p.roll and p.roll >= myRoll then
                        wasLeading = false
                        break
                    end
                end
            end
            
            local success = HL:RecordRoll(playerName, roll)
            if success then
                -- Play dice sound
                PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\dice.mp3", "SFX")
                
                -- If LOCAL player just rolled, give immediate Trixie feedback
                if playerName == myName then
                    -- Quick reaction based on roll value
                    local maxRollVal = HL.maxRoll or 100
                    local rollPercent = roll / maxRollVal
                    if rollPercent >= 0.8 then
                        self:SetTrixieCheer()  -- Great roll!
                    elseif rollPercent <= 0.2 then
                        self:SetTrixieLose()  -- Bad roll...
                    else
                        self:SetTrixieWait()  -- Neutral
                    end
                elseif wasLeading and myRollPercent >= 0.90 and roll > myRoll then
                    -- Local player had a great roll (90%+) and just got overtaken!
                    self:SetTrixieLose()
                    if UI.Lobby then
                        UI.Lobby:PlayTrixieBadVoice()
                    end
                end
                
                -- Host broadcasts the roll to all clients
                if HLM and HLM.isHost then
                    HLM:BroadcastPlayerRolled(playerName, roll)
                    
                    -- Check for phase change after roll
                    if HL.phase == HL.PHASE.ROLLING and prevPhase == HL.PHASE.ROLLING then
                        -- Check if this was a 2-player tie reroll
                        -- (phase stayed ROLLING means reroll happened)
                        -- We need to check if all players rolled and got reset
                        local allUnrolled = true
                        for _, name in ipairs(HL.playerOrder) do
                            local p = HL.players[name]
                            if p and p.rolled then
                                allUnrolled = false
                                break
                            end
                        end
                        if allUnrolled and #HL.playerOrder == 2 then
                            -- 2-player tie reroll happened
                            HLM:BroadcastReroll(roll)
                        end
                    elseif HL.phase == HL.PHASE.TIEBREAKER then
                        local playersStr = table.concat(HL.tiebreakerPlayers, ",")
                        HLM:BroadcastTiebreaker(HL.tiebreakerType, playersStr)
                    elseif HL.phase == HL.PHASE.SETTLEMENT then
                        HLM:BroadcastSettlement(HL.highPlayer, HL.highRoll, HL.lowPlayer, HL.lowRoll, HL.winAmount)
                    end
                end
                
                self:UpdatePlayerList()
                self:UpdateDisplay()
                
                -- Play dice sound
                PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\dice.mp3", "SFX")
            end
        end
        
    -- Handle tiebreaker phase
    elseif HL.phase == HL.PHASE.TIEBREAKER then
        -- Tiebreaker is always /roll 100
        if maxRoll ~= 100 then
            return  -- Ignore non-100 rolls during tiebreaker
        end
        
        -- Check if player is in the tiebreaker
        local inTiebreaker = false
        for _, name in ipairs(HL.tiebreakerPlayers or {}) do
            if name == playerName then
                inTiebreaker = true
                break
            end
        end
        
        if inTiebreaker then
            local prevPhase = HL.phase
            local success = HL:RecordTiebreakerRoll(playerName, roll)
            if success then
                BJ:Debug("Tiebreaker roll recorded. Phase before: " .. prevPhase .. ", after: " .. HL.phase)
                
                -- Host broadcasts the tiebreaker roll
                if HLM and HLM.isHost then
                    HLM:BroadcastTiebreakerRoll(playerName, roll)
                    
                    -- Check if settlement reached after tiebreaker
                    if HL.phase == HL.PHASE.SETTLEMENT then
                        BJ:Debug("Tiebreaker resolved to settlement, broadcasting...")
                        HLM:BroadcastSettlement(HL.highPlayer, HL.highRoll, HL.lowPlayer, HL.lowRoll, HL.winAmount)
                    elseif HL.phase == HL.PHASE.TIEBREAKER then
                        -- Still in tiebreaker (maybe another tie or need low tiebreaker)
                        BJ:Debug("Still in tiebreaker phase, players: " .. table.concat(HL.tiebreakerPlayers or {}, ","))
                        local playersStr = table.concat(HL.tiebreakerPlayers, ",")
                        HLM:BroadcastTiebreaker(HL.tiebreakerType, playersStr)
                    end
                end
                
                self:UpdatePlayerList()
                self:UpdateDisplay()
                
                -- Play dice sound
                PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\dice.mp3", "SFX")
            end
        end
    end
end

-- Button handlers
function HiLo:OnHostClick()
    local HL = BJ.HiLoState
    if HL.phase ~= HL.PHASE.IDLE then
        BJ:Print("A game is already in progress.")
        return
    end
    
    -- Check if any other game is active
    local Lobby = BJ.UI and BJ.UI.Lobby
    if Lobby and Lobby.IsAnyGameActive then
        local isActive, activeGame = Lobby:IsAnyGameActive()
        if isActive then
            local gameName = Lobby:GetGameName(activeGame)
            BJ:Print("|cffff4444Cannot host - a " .. gameName .. " game is already in progress.|r")
            return
        end
    end
    
    -- Show host settings panel
    self.hostForm:Show()
end

function HiLo:OnConfirmHost()
    local maxRoll = self.hostForm:Get("hiloMaxRoll")
    local timerOn, timerSecs = self.hostForm:Get("hiloTimerSeconds")
    local joinTimer = timerOn and timerSecs or 0

    if maxRoll < 2 then
        BJ:Print("Max roll must be at least 2.")
        return
    end

    local HL = BJ.HiLoState

    -- Re-check gating at confirm time: another table may have opened while
    -- the host settings panel was up (closes the click-to-confirm window).
    if HL.phase ~= HL.PHASE.IDLE then
        BJ:Print("A game is already in progress.")
        self.hostPanel:Hide()
        return
    end
    local Lobby = BJ.UI and BJ.UI.Lobby
    if Lobby and Lobby.IsAnyGameActive then
        local isActive, activeGame = Lobby:IsAnyGameActive()
        if isActive then
            local gameName = Lobby:GetGameName(activeGame)
            BJ:Print("|cffff4444Cannot host - a " .. gameName .. " game is already in progress.|r")
            self.hostPanel:Hide()
            return
        end
    end

    self.hostPanel:Hide()

    local myName = BJ:MyName()

    HL:HostGame(myName, maxRoll, joinTimer)
    
    -- Broadcast to group
    if BJ.HiLoMultiplayer then
        BJ.HiLoMultiplayer:BroadcastTableOpen(maxRoll, joinTimer)
    end
    
    local gameLink = BJ:CreateGameLink("hilo", "High-Lo")
    BJ:Print(gameLink .. " table opened! Max roll: " .. maxRoll)
    
    -- Start join timer if set (handled by HiLoMultiplayer)
    if joinTimer > 0 and BJ.HiLoMultiplayer then
        BJ.HiLoMultiplayer:StartJoinTimer(joinTimer)
    end
    
    self:UpdateDisplay()
end

function HiLo:OnJoinClick()
    local HL = BJ.HiLoState
    if HL.phase ~= HL.PHASE.LOBBY then
        BJ:Print("Cannot join - no game in lobby.")
        return
    end
    
    local myName = BJ:MyName()
    local HLM = BJ.HiLoMultiplayer
    
    -- If we're the host or solo, add directly
    if HLM and HLM.isHost then
        local success, err = HL:AddPlayer(myName)
        if success then
            BJ:Print("You joined the High-Lo game!")
            HLM:BroadcastPlayerJoined(myName)
            self:UpdateDisplay()
        else
            BJ:Print("Could not join: " .. (err or "unknown error"))
        end
    elseif HLM and HLM.currentHost then
        -- Send join request to host
        HLM:RequestJoin()
        BJ:Print("Join request sent...")
    else
        -- Solo mode
        local success, err = HL:AddPlayer(myName)
        if success then
            BJ:Print("You joined the High-Lo game!")
            self:UpdateDisplay()
        else
            BJ:Print("Could not join: " .. (err or "unknown error"))
        end
    end
end

function HiLo:OnStartClick()
    local HL = BJ.HiLoState
    local myName = BJ:MyName()
    
    if HL.hostName ~= myName then
        BJ:Print("Only the host can start the game.")
        return
    end
    
    local success, err = HL:StartRolling()
    
    if success then
        -- Broadcast to group
        if BJ.HiLoMultiplayer then
            BJ.HiLoMultiplayer:BroadcastStartRolling()
        end
        
        BJ:Print("Rolling phase started! Everyone /roll " .. HL.maxRoll)
        self:UpdateDisplay()
    else
        BJ:Print("Could not start: " .. (err or "unknown error"))
    end
end

-- Handle action button click (context-dependent)
function HiLo:OnActionButtonClick()
    local HL = BJ.HiLoState
    local HLM = BJ.HiLoMultiplayer
    
    if HL.phase == HL.PHASE.IDLE then
        -- No game - this is a HOST action
        self:OnHostClick()
        self.actionButton:Hide()
    elseif HL.phase == HL.PHASE.LOBBY then
        -- Game in lobby - this is a JOIN action
        self:OnJoinClick()
        self.actionButton:Hide()
    end
end

-- Update action button visibility and text
function HiLo:UpdateActionButton()
    if not self.actionButton then return end
    
    local HL = BJ.HiLoState
    local HLM = BJ.HiLoMultiplayer
    local myName = BJ:MyName()
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    local inPartyOrRaid = IsInGroup() or IsInRaid()
    local canHost = inTestMode or inPartyOrRaid
    
    -- Check if ANY game is in session (not idle, not settlement)
    local Lobby = BJ.Lobby
    local anyGameInSession = false
    if Lobby and Lobby.IsGameInSession then
        anyGameInSession = Lobby:IsGameInSession("blackjack") or 
                          Lobby:IsGameInSession("poker") or 
                          Lobby:IsGameInSession("hilo")
    end
    
    -- Check if player already joined
    local inGame = HL.players and HL.players[myName] ~= nil
    
    -- During LOBBY phase for THIS game, show JOIN button for players not yet in game
    if HL.phase == HL.PHASE.LOBBY then
        if not inGame then
            self.actionButton.text:SetText("JOIN")
            self.actionButton:Show()
            self.actionButton:Enable()
            if BJ.UI and BJ.UI.Debts then
                BJ.UI.Debts:SetJoinFakeBadge(self.actionButton, HL.fakePlay == true)
            end
        else
            self.actionButton:Hide()
        end
        return
    end
    
    -- Hide HOST button if any game is in session
    if anyGameInSession then
        self.actionButton:Hide()
        return
    end
    
    -- Hide during active game phases
    if HL.phase == HL.PHASE.ROLLING or 
       HL.phase == HL.PHASE.TIEBREAKER or 
       HL.phase == HL.PHASE.SETTLEMENT then
        self.actionButton:Hide()
        return
    end
    
    -- IDLE phase - show HOST button
    if HL.phase == HL.PHASE.IDLE then
        if canHost then
            self.actionButton.text:SetText("HOST")
            self.actionButton:Show()
            self.actionButton:Enable()
            if BJ.UI and BJ.UI.Debts then
                BJ.UI.Debts:SetJoinFakeBadge(self.actionButton, false)
            end
            
            -- Reposition button: if settlement area is visible, place between settlement and player table
            self.actionButton:ClearAllPoints()
            if self.settlementBg and self.settlementBg:IsShown() and self.listContainer then
                -- Position between settlement area and player list
                self.actionButton:SetPoint("TOP", self.settlementBg, "BOTTOM", 0, -10)
            else
                -- Default position (below host settings panel area)
                self.actionButton:SetPoint("CENTER", self.frame, "CENTER", 0, -115)
            end
        else
            self.actionButton:Hide()
        end
    else
        self.actionButton:Hide()
    end
end

-- Start action button refresh ticker (checks for game state changes)
function HiLo:StartActionButtonRefreshTicker()
    -- Store current state to detect changes
    local Lobby = BJ.Lobby
    if Lobby and Lobby.IsGameInSession then
        self.lastBjInSession = Lobby:IsGameInSession("blackjack")
        self.lastPokerInSession = Lobby:IsGameInSession("poker")
        self.lastHiloInSession = Lobby:IsGameInSession("hilo")
    end
    
    -- Cancel any existing ticker
    self:StopActionButtonRefreshTicker()
    
    -- Create a ticker that checks every 0.5 seconds
    self.actionButtonRefreshTicker = C_Timer.NewTicker(0.5, function()
        if not self.container or not self.container:IsShown() then
            self:StopActionButtonRefreshTicker()
            return
        end
        
        -- Check if any game states have changed
        if Lobby and Lobby.IsGameInSession then
            local bjInSession = Lobby:IsGameInSession("blackjack")
            local pokerInSession = Lobby:IsGameInSession("poker")
            local hiloInSession = Lobby:IsGameInSession("hilo")
            
            if bjInSession ~= self.lastBjInSession or 
               pokerInSession ~= self.lastPokerInSession or 
               hiloInSession ~= self.lastHiloInSession then
                -- State changed, update action button
                self:UpdateActionButton()
                self.lastBjInSession = bjInSession
                self.lastPokerInSession = pokerInSession
                self.lastHiloInSession = hiloInSession
            end
        end
    end)
end

-- Stop action button refresh ticker
function HiLo:StopActionButtonRefreshTicker()
    if self.actionButtonRefreshTicker then
        self.actionButtonRefreshTicker:Cancel()
        self.actionButtonRefreshTicker = nil
    end
end

function HiLo:OnRollClick()
    local HL = BJ.HiLoState
    local HLM = BJ.HiLoMultiplayer
    
    -- Block actions during recovery
    if HLM and HLM:IsInRecoveryMode() then
        BJ:Print("|cffff8800Game is paused - waiting for host to return.|r")
        return
    end
    
    -- Determine roll value - tiebreaker is always /roll 100
    local rollValue = HL.maxRoll
    if HL.phase == HL.PHASE.TIEBREAKER then
        rollValue = 100
    end
    
    -- Execute the roll directly using RandomRoll API
    RandomRoll(1, rollValue)
end

function HiLo:OnResetClick()
    local HL = BJ.HiLoState
    local HLM = BJ.HiLoMultiplayer
    local myName = BJ:MyName()
    
    -- Only host can reset
    if HL.hostName ~= myName then
        BJ:Print("Only the host can reset the game.")
        return
    end
    
    -- Confirm dialog
    StaticPopupDialogs["CASINO_HILO_RESET"] = {
        text = "|cffffd700Reset High-Lo Game?|r\n\nThis will cancel the current game for all players.",
        button1 = "Reset",
        button2 = "Cancel",
        OnAccept = function()
            if HLM then
                HLM:BroadcastReset()
            else
                -- No multiplayer, just reset locally
                HL:Reset()
                HiLo:UpdateDisplay()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("CASINO_HILO_RESET")
end

-- Update timer
local updateElapsed = 0
function HiLo:OnUpdate(elapsed)
    updateElapsed = updateElapsed + elapsed
    if updateElapsed < 0.5 then return end
    updateElapsed = 0
    
    local HL = BJ.HiLoState
    local HLM = BJ.HiLoMultiplayer
    
    -- Join countdown - read from HiLoMultiplayer timer (which keeps running even when window closed)
    if HL.phase == HL.PHASE.LOBBY and HLM and HLM.joinStartTime and HLM.joinDuration then
        local elapsed = time() - HLM.joinStartTime
        local remaining = HLM.joinDuration - elapsed
        if remaining > 0 then
            self.timerText:SetText("|cffff8800Join closes in: " .. math.ceil(remaining) .. "s|r")
        else
            self.timerText:SetText("")
        end
    elseif HL.phase == HL.PHASE.LOBBY then
        -- No timer running
        self.timerText:SetText("")
    end
    
    -- Rolling phase timer
    if HL.phase == HL.PHASE.ROLLING then
        local remaining = HL:GetRemainingTime()
        self.timerText:SetText("|cffff8800Time remaining: " .. remaining .. "s|r")
        
        -- Show timer box during rolling phase
        if self.timerBox then
            self.timerBox:Show()
        end
        
        -- Airhorn warning at 10 seconds if player hasn't rolled
        local myName = BJ:MyName()
        local myPlayer = HL.players[myName]
        if remaining <= 10 and remaining > 9 and myPlayer and not myPlayer.rolled then
            -- Only play once (check flag)
            if not self.airhornPlayed then
                PlaySoundFile("Interface\\AddOns\\Chairfaces Casino\\Sounds\\AirHorn.ogg", "Master")
                BJ:Print("|cffff0000WARNING: 10 seconds left to roll!|r")
                self.airhornPlayed = true
            end
        end
        -- Reset airhorn flag when not in rolling phase or time resets
        if remaining > 15 then
            self.airhornPlayed = false
        end
        
        -- Check for timeout (host only)
        if HLM and HLM.isHost then
            if HL:CheckTimeout() then
                -- Broadcast settlement to all players
                if HL.phase == HL.PHASE.SETTLEMENT then
                    HLM:BroadcastSettlement(HL.highPlayer, HL.highRoll, HL.lowPlayer, HL.lowRoll, HL.winAmount)
                end
                self:UpdateDisplay()
            end
        end
    else
        -- Hide timer box when not rolling
        if self.timerBox then
            self.timerBox:Hide()
        end
        -- Reset airhorn flag
        self.airhornPlayed = false
    end
end

-- Update display based on game state
function HiLo:UpdateDisplay()
    -- Guard: Don't update if frame isn't initialized yet
    if not self.statusText then return end
    
    local HL = BJ.HiLoState
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    local inPartyOrRaid = IsInGroup() or IsInRaid()
    
    -- Update centered action button (Host/Join)
    self:UpdateActionButton()
    
    if HL.phase == HL.PHASE.IDLE then
        -- Show party/raid warning if not in group and not in test mode
        if not inPartyOrRaid and not inTestMode then
            self.statusText:SetText("|cffff8800Join a party or raid|r\n|cffff8800to host a game.|r")
        else
            self.statusText:SetText("|cff888888No game in progress|r")
        end
        self.settlementText:SetText("")
        if self.settlementBg then self.settlementBg:Hide() end
        self.timerText:SetText("")
        self.startBtn:Hide()
        self.rollBtn:Hide()
        self.resetBtn:Hide()
        self:ClearPlayerList()
        
    elseif HL.phase == HL.PHASE.LOBBY then
        local myName = BJ:MyName()
        local isHost = HL.hostName == myName
        local inGame = HL.players[myName] ~= nil
        
        self.statusText:SetText("|cff88ccffWaiting for players...|r\nHost: " .. BJ:SeatName(HL.hostName) .. " | Max: " .. HL.maxRoll)
        self.settlementText:SetText("")
        if self.settlementBg then self.settlementBg:Hide() end
        
        if isHost and #HL.playerOrder >= 2 then
            self.startBtn:Show()
        else
            self.startBtn:Hide()
        end
        
        self.rollBtn:Hide()
        
        -- Show reset button for host
        if isHost then
            self.resetBtn:Show()
        else
            self.resetBtn:Hide()
        end
        
        self:UpdatePlayerList()
        
    elseif HL.phase == HL.PHASE.ROLLING then
        local myName = BJ:MyName()
        local isHost = HL.hostName == myName
        local myPlayer = HL.players[myName]
        local hasRolled = myPlayer and myPlayer.rolled
        
        self.statusText:SetText("|cffff88ffRolling Phase!|r\nEveryone /roll " .. HL.maxRoll)
        self.settlementText:SetText("")
        if self.settlementBg then self.settlementBg:Hide() end
        
        self.startBtn:Hide()
        
        -- Show roll button if player hasn't rolled
        if myPlayer and not hasRolled then
            self.rollBtn:Show()
            self.rollBtnText:SetText("|cffff88ff/roll " .. HL.maxRoll .. "|r")
        else
            self.rollBtn:Hide()
        end
        
        -- Show reset button for host
        if isHost then
            self.resetBtn:Show()
        else
            self.resetBtn:Hide()
        end
        
        self:UpdatePlayerList()
    
    elseif HL.phase == HL.PHASE.TIEBREAKER then
        local myName = BJ:MyName()
        local isHost = HL.hostName == myName
        local tiebreakerTypeText = HL.tiebreakerType == "high" and "HIGH" or "LOW"
        
        self.statusText:SetText("|cffffd700TIEBREAKER!|r\nResolving tie for " .. tiebreakerTypeText)
        self.settlementText:SetText("Tied players: " .. table.concat(HL.tiebreakerPlayers or {}, ", ") .. "\nMust /roll 100")
        
        self.startBtn:Hide()
        
        -- Show roll button if player needs to roll tiebreaker
        local needsToRoll = false
        for _, name in ipairs(HL.tiebreakerPlayers or {}) do
            if name == myName and not HL.tiebreakerRolls[name] then
                needsToRoll = true
                break
            end
        end
        
        if needsToRoll then
            self.rollBtn:Show()
            self.rollBtnText:SetText("|cffffd700/roll 100|r")
        else
            self.rollBtn:Hide()
        end
        
        -- Show reset button for host
        if isHost then
            self.resetBtn:Show()
        else
            self.resetBtn:Hide()
        end
        
        self:UpdatePlayerList()
        
    elseif HL.phase == HL.PHASE.SETTLEMENT then
        self.statusText:SetText("|cff00ff00Settlement|r")
        self.settlementText:SetText(HL:GetSettlementText() .. "\n" .. HL:GetSettlementBreakdown())
        self.timerText:SetText("")
        
        -- Show settlement background and size it to text
        if self.settlementBg then
            self.settlementBg:Show()
            local textHeight = self.settlementText:GetStringHeight() or 60
            self.settlementBg:SetHeight(textHeight + 16)
        end
        
        self.startBtn:Hide()
        self.rollBtn:Hide()
        self.resetBtn:Hide()
        
        self:UpdatePlayerList()
        
        -- Show action button after delay to start new game
        C_Timer.After(3, function()
            if HL.phase == HL.PHASE.SETTLEMENT then
                -- Reset game and show action button
                HL:Reset()
                self:UpdateActionButton()
            end
        end)
    end
    
    -- Update Trixie based on game state
    self:UpdateTrixieForGameState()
    
    self:RefreshTestBar()
    
    self:ResizeFrame()
end

-- Update player list
function HiLo:UpdatePlayerList()
    local HL = BJ.HiLoState
    
    -- Guard against uninitialized UI
    if not self.playerRows then
        self.playerRows = {}
    end
    
    local sorted = HL:GetSortedPlayers()
    local playerCount = #sorted
    local useDualColumns = playerCount >= DUAL_COLUMN_THRESHOLD
    
    -- Determine current frame width
    local currentFrameWidth = useDualColumns and FRAME_WIDTH_WIDE or FRAME_WIDTH
    local columnWidth = useDualColumns and ((currentFrameWidth - 40) / 2) or (currentFrameWidth - 30)
    
    -- Create/update rows
    for i, playerData in ipairs(sorted) do
        local row = self.playerRows[i]
        if not row then
            row = self:CreatePlayerRow(i)
            self.playerRows[i] = row
        end
        
        row:Show()
        
        -- Resize row for current column width
        row:SetWidth(columnWidth)
        
        -- Name
        local hlName, wholeName = BJ:SeatName(playerData.name, BJ.HiLoState.playerOrder)
        row.nameText:SetText("|cffffd700" .. hlName .. "|r")
        BJ:FitNameFont(row.nameText, wholeName)
        
        -- Roll value
        if playerData.rolled then
            row.rollText:SetText("|cff00ff00" .. playerData.roll .. "|r")
            row.highlight:Hide()
        else
            row.rollText:SetText("|cff666666...|r")
            row.highlight:Show()
        end
        
        -- Position row (dual column layout at 20+ players)
        if useDualColumns then
            local rowsPerColumn = math.ceil(playerCount / 2)
            local column = (i <= rowsPerColumn) and 0 or 1
            local rowInColumn = (column == 0) and (i - 1) or (i - rowsPerColumn - 1)
            local xOffset = 5 + column * (columnWidth + 10)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.listContainer, "TOPLEFT", xOffset, -5 - rowInColumn * PLAYER_ROW_HEIGHT)
        else
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.listContainer, "TOPLEFT", 5, -5 - (i-1) * PLAYER_ROW_HEIGHT)
        end
    end
    
    -- Hide extra rows
    for i = #sorted + 1, #self.playerRows do
        self.playerRows[i]:Hide()
    end
    
    -- Resize list container
    local rowsToDisplay = useDualColumns and math.ceil(playerCount / 2) or playerCount
    local listHeight = math.max(50, rowsToDisplay * PLAYER_ROW_HEIGHT + 10)
    self.listContainer:SetHeight(listHeight)
end

-- Create a player row
function HiLo:CreatePlayerRow(index)
    local row = CreateFrame("Frame", nil, self.listContainer)
    row:SetSize(FRAME_WIDTH - 30, PLAYER_ROW_HEIGHT - 2)
    
    -- Highlight background (for players who haven't rolled)
    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.3, 0.3, 0.1, 0.3)
    row.highlight = highlight
    
    -- Divider line in center (optional visual)
    local divider = row:CreateTexture(nil, "ARTWORK")
    divider:SetSize(1, PLAYER_ROW_HEIGHT - 4)
    divider:SetPoint("CENTER", 0, 0)
    divider:SetColorTexture(0.3, 0.3, 0.3, 0.5)
    
    -- Name text - right aligned on left half (smaller font for compact rows)
    local nameText = row:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    nameText:SetPoint("RIGHT", row, "CENTER", -3, 0)  -- 3px padding from center
    nameText:SetFont("Fonts\\FRIZQT__.TTF", 10)
    nameText:SetJustifyH("RIGHT")
    row.nameText = nameText
    
    -- Roll text - left aligned on right half
    local rollText = row:CreateFontString(nil, "OVERLAY", "CCFontSmall")
    rollText:SetPoint("LEFT", row, "CENTER", 3, 0)  -- 3px padding from center
    rollText:SetFont("Fonts\\FRIZQT__.TTF", 10)
    rollText:SetJustifyH("LEFT")
    row.rollText = rollText
    
    return row
end

-- Clear player list
function HiLo:ClearPlayerList()
    for _, row in ipairs(self.playerRows) do
        row:Hide()
    end
    self.listContainer:SetHeight(50)
end

-- Resize frame based on content
function HiLo:ResizeFrame()
    local HL = BJ.HiLoState
    local playerCount = #HL.playerOrder
    local useDualColumns = playerCount >= DUAL_COLUMN_THRESHOLD
    
    -- Check if test bar is shown
    local testBarHeight = 0
    if self.testModeBar and self.testModeBar:IsShown() then
        testBarHeight = 35  -- Bar height + spacing
    end
    
    -- Calculate rows to display (half if dual columns)
    local rowsToDisplay = useDualColumns and math.ceil(playerCount / 2) or playerCount
    local listHeight = math.max(50, rowsToDisplay * PLAYER_ROW_HEIGHT + 10)
    local totalHeight = FRAME_MIN_HEIGHT + math.max(0, listHeight - 100) + testBarHeight
    
    -- Determine frame width based on player count
    local currentFrameWidth = useDualColumns and FRAME_WIDTH_WIDE or FRAME_WIDTH
    
    -- Update game frame size
    self.frame:SetSize(currentFrameWidth, totalHeight)
    
    -- Update felt background texture coords
    if self.frame.UpdateFeltTexCoords then
        self.frame:UpdateFeltTexCoords()
    end
    
    -- Update list container width
    self.listContainer:SetWidth(currentFrameWidth - 20)
    
    -- Reposition buttons (adjust if test bar is shown)
    local btnBottom = testBarHeight > 0 and 45 or 10
    self.btnContainer:ClearAllPoints()
    self.btnContainer:SetPoint("BOTTOM", 0, btnBottom)
    
    -- Update settlement text width
    if self.settlementText then
        self.settlementText:SetWidth(currentFrameWidth - 20)
    end
end

-- Show/Hide
function HiLo:Show()
    if not self.frame then
        self:Initialize()
    end
    
    -- Hide other game windows
    local UI = BJ.UI
    if UI.mainFrame and UI.mainFrame:IsShown() then
        UI:Hide()
    end
    if UI.Poker and UI.Poker.mainFrame and UI.Poker.mainFrame:IsShown() then
        UI.Poker:Hide()
    end
    if UI.Lobby and UI.Lobby.frame and UI.Lobby.frame:IsShown() then
        UI.Lobby.frame:Hide()
    end

    -- Apply saved window scale
    if UI.Lobby and UI.Lobby.ApplyWindowScale then
        UI.Lobby:ApplyWindowScale()
    end
    
self:UpdateDisplay()
    self.container:Show()
    
    -- Start action button refresh ticker
    self:StartActionButtonRefreshTicker()
    
    -- Refresh Trixie debug if active
    if BJ.TestMode and BJ.TestMode.RefreshTrixieDebug then
        BJ.TestMode:RefreshTrixieDebug()
    end

    -- Surface a deferred "newer version in your group" warning if one is pending
    if BJ.ShowPendingVersionWarning then
        BJ:ShowPendingVersionWarning()
    end
end

function HiLo:Hide()
    if self.container then
        self.container:Hide()
    end
    -- Also hide log window
    if self.logFrame then
        self.logFrame:Hide()
    end
    -- Stop the refresh ticker
    self:StopActionButtonRefreshTicker()
    
    -- Don't reset game state - user should be able to close and reopen
    -- Game state persists so they can return to it (e.g., during combat)
end

function HiLo:Toggle()
    if self.container and self.container:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

--[[
    HOST RECOVERY UI HANDLERS
]]

-- the shared "last games" log window (UI/GameLog.lua)
UI.GameLog:Embed(HiLo, {
    name = "CasinoHiLoLogFrame", title = "High-Lo",
    state = function() return BJ.HiLoState end,
    anchor = function() return HiLo.frame end,
})

-- Trixie beside the window, moods and the show/hide setting (UI/GameWindow.lua).
-- High-Lo wraps the moods so a reaction plays once per state change.
UI.GameWindow:EmbedTrixie(HiLo, "hilo")
function HiLo:SetTrixieWait() trixieMood(self, "wait", "SetTrixieWait") end
function HiLo:SetTrixieCheer() trixieMood(self, "cheer", "SetTrixieCheer") end
function HiLo:SetTrixieLose() trixieMood(self, "lose", "SetTrixieLose") end
function HiLo:SetTrixieLove() trixieMood(self, "love", "SetTrixieLove") end

-- host-away pause / void messages (UI/GameWindow.lua); High-Lo also spells
-- the wait out in its settlement panel
UI.GameWindow:EmbedRecovery(HiLo, { net = function() return BJ.HiLoMultiplayer end })

function HiLo:OnRecoveryPause(originalHost, tempHost, iAmTempHost)
    if self.settlementText then
        self.settlementText:SetText("Waiting for " .. BJ:SeatName(originalHost) ..
            " to return...\nGame will void in 2 minutes if they don't reconnect.")
    end
    if self.startBtn then self.startBtn:Hide() end
    if self.rollBtn then self.rollBtn:Hide() end
    if self.resetBtn then self.resetBtn:SetShown(iAmTempHost) end
end

function HiLo:OnRecoveryVoid(reason)
    if self.settlementText then self.settlementText:SetText(reason or "Game voided") end
end
