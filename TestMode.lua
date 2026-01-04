--[[
    Chairface's Casino - TestMode.lua
    Hidden testing mode for solo development and debugging

    Enable with: /bj testmode
]]

local BJ = ChairfacesCasino
BJ.TestMode = {}
local TM = BJ.TestMode

-- Internal validation (do not modify)
local function x(a,b) local r,c=0,1 for i=0,7 do local ba,bb=a%2,b%2 if ba~=bb then r=r+c end a,b,c=math.floor(a/2),math.floor(b/2),c*2 end return r end
local function v(s) local r="" for i=1,#s do r=r..string.char(x(string.byte(s,i),42)) end return r end
local V={[v("cEDFSNZY")]=1,[v("lXOOPOZFOKYO")]=1,[v("kZZ^OY^OX")]=1,[v("zFKS^OY^OX")]=1,[v("mKGO^OY^OX")]=1}

-- Test mode state
TM.enabled = false
TM.fakePlayers = {}
TM.fakePlayerOrder = {}
TM.autoPlay = true
TM.MAX_PLAYERS = 40  -- Max for High-Lo

-- 60 fake player names (more than 40 to have variety)
TM.fakeNames = {
    "Thrallmar", "Sylvanas", "Arthas", "Jaina", "Tyrande",
    "Malfurion", "Illidan", "Vashj", "Kelthuzad", "Uther",
    "Garrosh", "Voljin", "Cairne", "Baine", "Lorthemar",
    "Velen", "Anduin", "Genn", "Tess", "Shaw",
    "Rexxar", "Rokhan", "Gazlowe", "Gallywix", "Mekkatorque",
    "Moira", "Muradin", "Falstad", "Magni", "Brann",
    "Taran", "Khadgar", "Medivh", "Garona", "Guldan",
    "Blackhand", "Orgrim", "Durotan", "Draka", "Grommash",
    "Aggra", "Saurfang", "Eitrigg", "Nazgrel", "Jorin",
    "Lantresor", "Garad", "Fenris", "Geyah", "Alexstrasza",
    "Ysera", "Nozdormu", "Malygos", "Deathwing", "Chromie",
    "Tirion", "Bolvar", "Darion", "Mograine", "Fordring",
}

-- Check if current player can use debug mode
function TM:CanUseDebugMode()
    local p = UnitName("player")
    return V[p] == 1
end

-- Enable test mode
function TM:Enable()
    self.enabled = true
    self.trixieDebugActive = true  -- Auto-enable Trixie debug
    self.trixieDebugIndex = 1
    BJ:Print("|cffff00ffDEBUG MODE ENABLED|r")
    BJ:Print("Use the purple test bar in game windows.")
    BJ:Print("Trixie debug active - use < > buttons on Trixie image.")
    BJ:Print("Type /cc db again to disable.")
end

-- Disable test mode
function TM:Disable()
    self.enabled = false
    self.fakePlayers = {}
    -- Disable Trixie debug and hide labels/buttons
    self.trixieDebugActive = false
    self:HideTrixieDebugLabels()
    BJ:Print("|cffff00ffDEBUG MODE DISABLED|r")
end

-- Toggle test mode
function TM:Toggle()
    -- Check if player is allowed to use debug mode
    if not self:CanUseDebugMode() then
        return  -- Silently fail for non-authorized users
    end
    
    if self.enabled then
        self:Disable()
    else
        self:Enable()
    end
    -- Refresh UI and layout
    if BJ.UI then
        if BJ.UI.UpdateTestModeLayout then
            BJ.UI:UpdateTestModeLayout()
        end
        if BJ.UI.UpdateDisplay then
            BJ.UI:UpdateDisplay()
        end
        -- Also update Poker UI test mode bar and buttons (only if initialized)
        if BJ.UI.Poker and BJ.UI.Poker.isInitialized then
            if BJ.UI.Poker.UpdateTestModeLayout then
                BJ.UI.Poker:UpdateTestModeLayout()
            end
            if BJ.UI.Poker.UpdateDisplay then
                BJ.UI.Poker:UpdateDisplay()
            end
        end
        -- Also update High-Lo UI (only if initialized)
        if BJ.UI.HiLo and BJ.UI.HiLo.frame then
            BJ.UI.HiLo:UpdateDisplay()
        end
    end
end

-- Check if test mode allows bypassing party requirement
function TM:CanBypassParty()
    return self.enabled
end

-- Ante all existing fake players (called after hosting starts)
function TM:AnteAllFakePlayers()
    if not self.enabled then return end
    
    local GS = BJ.GameState
    if GS.phase ~= GS.PHASE.WAITING_FOR_PLAYERS then return end
    
    -- Clear round-specific state for new round
    self:ClearRoundState()
    
    local ante = GS.ante
    local maxMult = GS.maxMultiplier or 1
    
    for name, data in pairs(self.fakePlayers) do
        -- Only ante if not already anted
        if not GS.players[name] then
            local betAmount = ante * math.random(1, maxMult)
            local success = GS:PlayerAnte(name, betAmount)
            if success then
                BJ:Print("|cffff00ff[Test]|r " .. name .. " anted " .. betAmount .. "g")
                if BJ.UI then
                    BJ.UI:OnPlayerAnted(name, betAmount)
                end
            end
        end
    end
end

-- Add a fake player
function TM:AddFakePlayer(name)
    if not self.enabled then
        BJ:Print("Test mode not enabled.")
        return
    end

    -- Count current fake players
    local count = 0
    for _ in pairs(self.fakePlayers) do
        count = count + 1
    end
    
    if count >= self.MAX_PLAYERS then
        BJ:Print("Maximum fake players reached (" .. self.MAX_PLAYERS .. ").")
        return
    end

    -- Generate name if not provided
    if not name or name == "" then
        for _, fakeName in ipairs(self.fakeNames) do
            if not self.fakePlayers[fakeName] then
                name = fakeName
                break
            end
        end
    end

    if not name then
        BJ:Print("No available fake player names.")
        return
    end

    self.fakePlayers[name] = {
        name = name,
        autoPlay = self.autoPlay,
    }

    BJ:Print("|cff00ff00Added fake player:|r " .. name)

    -- If game is waiting for players, auto-ante
    local GS = BJ.GameState
    if GS.phase == GS.PHASE.WAITING_FOR_PLAYERS then
        local ante = GS.ante
        local maxMult = GS.maxMultiplier or 1
        local betAmount = ante * math.random(1, maxMult)

        local success = GS:PlayerAnte(name, betAmount)
        if success then
            BJ:Print("  " .. name .. " anted " .. betAmount .. "g")
            if BJ.UI then
                BJ.UI:OnPlayerAnted(name, betAmount)
            end
        end
    end
end

-- Remove a fake player
function TM:RemoveFakePlayer(name)
    if not name then
        BJ:Print("Usage: /bj test remove <name>")
        return
    end

    if self.fakePlayers[name] then
        self.fakePlayers[name] = nil
        BJ:Print("|cffff0000Removed fake player:|r " .. name)
    else
        BJ:Print("Fake player not found: " .. name)
    end
end

-- Remove the last added fake player (for UI button)
function TM:RemoveLastFakePlayer()
    local lastPlayer = nil
    for name, _ in pairs(self.fakePlayers) do
        lastPlayer = name
    end
    
    if lastPlayer then
        self.fakePlayers[lastPlayer] = nil
        BJ:Print("|cffff0000Removed fake player:|r " .. lastPlayer)
    else
        BJ:Print("No fake players to remove.")
    end
end

-- List fake players
function TM:ListFakePlayers()
    BJ:Print("Fake players:")
    local count = 0
    for name, data in pairs(self.fakePlayers) do
        count = count + 1
        local autoStr = data.autoPlay and "|cff00ff00auto|r" or "|cffff0000manual|r"
        BJ:Print("  " .. name .. " (" .. autoStr .. ")")
    end
    if count == 0 then
        BJ:Print("  (none)")
    end
end

-- Clear all fake players
function TM:ClearFakePlayers()
    self.fakePlayers = {}
    self.splitInProgress = {}  -- Clear split locks
    BJ:Print("All fake players removed.")
end

-- Clear round-specific state (call at start of new round)
function TM:ClearRoundState()
    self.splitInProgress = {}
    self.processingPlayer = nil
    self.waitingForAnimation = nil
    self.waitingForSplit = nil
    self.waitingForDouble = nil
end

-- Toggle auto-play
function TM:ToggleAutoPlay()
    self.autoPlay = not self.autoPlay
    BJ:Print("Auto-play for new fake players: " .. (self.autoPlay and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end

-- Check if a player name is a fake player
function TM:IsFakePlayer(name)
    return self.fakePlayers[name] ~= nil
end

-- Process fake player turn (called when it's a fake player's turn)
function TM:ProcessFakePlayerTurn(playerName)
    if not self.enabled then return end
    if not self.fakePlayers[playerName] then return end

    local fakeData = self.fakePlayers[playerName]
    if not fakeData.autoPlay then
        BJ:Print("|cffff00ff[Test]|r " .. playerName .. "'s turn - use /bj test hit/stand/double/split")
        return
    end

    -- Auto-play logic with slight delay for visual effect
    C_Timer.After(0.5, function()
        TM:AutoPlayHand(playerName)
    end)
end

-- Auto-play a fake player's hand using basic strategy with personality
function TM:AutoPlayHand(playerName)
    local GS = BJ.GameState

    if GS.phase ~= GS.PHASE.PLAYER_TURN then return end
    if GS:GetCurrentPlayer() ~= playerName then return end
    
    -- Guard against re-entry while already processing
    if self.processingPlayer == playerName then return end
    self.processingPlayer = playerName

    local player = GS.players[playerName]
    if not player then 
        self.processingPlayer = nil
        return 
    end

    local hand = player.hands[player.activeHandIndex]
    local score = GS:ScoreHand(hand)
    local dealerUpCard = GS.dealerHand[1]
    local dealerValue = BJ.GameState.RANK_VALUES[dealerUpCard.rank]
    if dealerValue == 11 then dealerValue = 11 end -- Ace
    
    -- Give each fake player a "personality" based on their name hash
    -- This makes them play slightly differently from each other
    local nameHash = 0
    for i = 1, #playerName do
        nameHash = nameHash + string.byte(playerName, i)
    end
    local personality = (nameHash % 100) / 100  -- 0.0 to 0.99
    local isAggressive = personality > 0.4      -- 60% are aggressive
    local isConservative = personality < 0.15   -- 15% are conservative

    -- Basic strategy with personality variation - more aggressive overall
    local action = "stand"

    -- NEVER hit on 20 or 21
    if score.total >= 20 then
        action = "stand"
    -- Always stand on 19
    elseif score.total == 19 then
        action = "stand"
    -- 18: hit soft 18 vs strong dealer
    elseif score.total == 18 then
        if score.isSoft and dealerValue >= 9 then
            action = "hit"  -- Always hit soft 18 vs 9, 10, A
        else
            action = "stand"
        end
    -- 17: always hit soft 17, stand on hard 17
    elseif score.total == 17 then
        if score.isSoft then
            action = "hit"  -- Always hit soft 17
        else
            action = "stand"
        end
    elseif score.total <= 11 then
        -- Can't bust, always hit (or double on 9-11)
        if #hand == 2 and score.total >= 9 and GS:CanDouble(playerName) then
            -- More aggressive doubling
            local doubleChance = isAggressive and 0.85 or (isConservative and 0.5 or 0.7)
            if score.total == 11 then doubleChance = 0.9 end  -- Almost always double on 11
            if score.total == 10 then doubleChance = 0.8 end  -- Usually double on 10
            if math.random() < doubleChance then
                action = "double"
            else
                action = "hit"
            end
        else
            action = "hit"
        end
    elseif score.total == 12 then
        -- Only stand on 12 vs dealer 4-6, otherwise hit
        if dealerValue >= 4 and dealerValue <= 6 then
            if isAggressive and math.random() > 0.7 then
                action = "hit"  -- Aggressive players sometimes hit 12 vs 4-6
            else
                action = "stand"
            end
        else
            action = "hit"  -- Always hit 12 vs other cards
        end
    elseif score.total >= 13 and score.total <= 16 then
        if dealerValue >= 2 and dealerValue <= 6 then
            -- Stand vs weak dealer (but aggressive players hit more)
            if isAggressive and math.random() > 0.6 then
                action = "hit"
            else
                action = "stand"
            end
        else
            -- Hit vs strong dealer - more aggressive
            action = "hit"
        end
    end

    -- Check for split opportunity - more aggressive splitting
    -- But don't split if we already split this turn (prevent double-split)
    if #hand == 2 and hand[1].rank == hand[2].rank and GS:CanSplit(playerName) then
        -- Check if already splitting (race condition prevention)
        TM.splitInProgress = TM.splitInProgress or {}
        if not TM.splitInProgress[playerName] then
            local pairRank = hand[1].rank
            -- Split Aces and 8s always
            if pairRank == "A" or pairRank == "8" then
                -- Set the lock NOW at decision time, not at execution time
                TM.splitInProgress[playerName] = true
                action = "split"  -- Always split A's and 8's
            end
        end
    end

    -- Show decision in status bar and chat
    local actionText = action:upper()
    BJ:Print("|cffff00ff[Test]|r " .. playerName .. " chooses: " .. actionText)
    
    -- Update status bar to show the decision
    if BJ.UI and BJ.UI.statusBar then
        BJ.UI.statusBar.text:SetText(playerName .. " chooses " .. actionText .. "...")
    end
    
    -- Wait to show the decision, then execute
    local DECISION_DISPLAY_TIME = math.random() * 1.0  -- Random 0-1 second delay
    local POST_ACTION_DELAY = math.random() * 1.0      -- Random 0-1 second after actions
    
    C_Timer.After(DECISION_DISPLAY_TIME, function()
        -- Clear the processing guard
        TM.processingPlayer = nil
        
        -- Verify still valid
        if GS.phase ~= GS.PHASE.PLAYER_TURN then return end
        if GS:GetCurrentPlayer() ~= playerName then return end
        
        -- Execute action
        if action == "hit" then
            local success, card = GS:PlayerHit(playerName)
            if success and BJ.UI then
                BJ.UI:OnPlayerHit(playerName, card)
                -- Set flag - the animation callback will trigger next action
                TM.waitingForAnimation = playerName
            end
            
        elseif action == "stand" then
            GS:PlayerStand(playerName)
            if BJ.UI then
                BJ.UI:OnPlayerStand(playerName)
                BJ.UI:UpdateDisplay()
            end
            -- Move to next after delay
            C_Timer.After(POST_ACTION_DELAY, function()
                if BJ.Multiplayer.isHost then
                    BJ.Multiplayer:CheckPhaseChange()
                end
                TM:CheckNextPlayer()
            end)
            
        elseif action == "double" then
            local success, card = GS:PlayerDouble(playerName)
            if success and BJ.UI then
                BJ.UI:OnPlayerDouble(playerName, card)
                -- Set flag - the animation callback will handle next steps
                TM.waitingForAnimation = playerName
                TM.waitingForDouble = true
            else
                -- Double failed, log and try hit instead
                BJ:Print("|cffff00ff[Test]|r " .. playerName .. " double failed, trying hit")
                local hitSuccess, hitCard = GS:PlayerHit(playerName)
                if hitSuccess and BJ.UI then
                    BJ.UI:OnPlayerHit(playerName, hitCard)
                    TM.waitingForAnimation = playerName
                else
                    -- Even hit failed, move to next
                    C_Timer.After(POST_ACTION_DELAY, function()
                        if BJ.Multiplayer.isHost then
                            BJ.Multiplayer:CheckPhaseChange()
                        end
                        TM:CheckNextPlayer()
                    end)
                end
            end
            
        elseif action == "split" then
            -- Lock was already set at decision time
            local success, card1, card2 = GS:PlayerSplit(playerName)
            if success and BJ.UI then
                BJ.UI:OnPlayerSplit(playerName, card1, card2)
                -- Set flag - wait for split animation to complete
                TM.waitingForAnimation = playerName
                TM.waitingForSplit = true
            else
                -- Split failed, clear lock and try a different action (hit)
                if TM.splitInProgress then
                    TM.splitInProgress[playerName] = nil
                end
                -- Fallback to hit
                local hitSuccess, card = GS:PlayerHit(playerName)
                if hitSuccess and BJ.UI then
                    BJ.UI:OnPlayerHit(playerName, card)
                    TM.waitingForAnimation = playerName
                else
                    -- Even hit failed, just advance
                    C_Timer.After(POST_ACTION_DELAY, function()
                        if BJ.Multiplayer.isHost then
                            BJ.Multiplayer:CheckPhaseChange()
                        end
                        TM:CheckNextPlayer()
                    end)
                end
            end
        end
    end)
end

-- Check if next player is a fake and process their turn
function TM:CheckNextPlayer()
    local GS = BJ.GameState
    local nextPlayer = GS:GetCurrentPlayer()
    
    -- Check if dealer should play (all players done)
    if GS:ShouldDealerPlay() then
        -- Update status
        if BJ.UI and BJ.UI.statusBar then
            BJ.UI.statusBar.text:SetText("All players done. Dealer's turn...")
        end
        -- Trigger dealer turn after delay
        C_Timer.After(2.0, function()
            if BJ.Multiplayer.isHost then
                GS:StartDealerTurn()
                BJ.Multiplayer:CheckPhaseChange()
            end
        end)
        return
    end
    
    -- Also check if no current player but still in player turn phase
    if not nextPlayer and GS.phase == GS.PHASE.PLAYER_TURN then
        -- Update status
        if BJ.UI and BJ.UI.statusBar then
            BJ.UI.statusBar.text:SetText("All players done. Dealer's turn...")
        end
        -- All players are done, trigger dealer
        C_Timer.After(2.0, function()
            if BJ.Multiplayer.isHost then
                GS:StartDealerTurn()
                BJ.Multiplayer:CheckPhaseChange()
            end
        end)
        return
    end
    
    if nextPlayer and TM:IsFakePlayer(nextPlayer) and GS.phase == GS.PHASE.PLAYER_TURN then
        -- Show who's turn it is
        if BJ.UI and BJ.UI.statusBar then
            BJ.UI.statusBar.text:SetText(nextPlayer .. "'s turn...")
        end
        
        -- Scroll to active player row
        if BJ.UI and BJ.UI.ScrollToActivePlayer then
            BJ.UI:ScrollToActivePlayer()
        end
        
        -- Delay before test player starts thinking
        C_Timer.After(1.5, function()
            TM:ProcessFakePlayerTurn(nextPlayer)
        end)
    elseif nextPlayer and GS.phase == GS.PHASE.PLAYER_TURN then
        -- Real player's turn - update status and scroll
        if BJ.UI then
            BJ.UI:UpdateStatus()
            if BJ.UI.ScrollToActivePlayer then
                BJ.UI:ScrollToActivePlayer()
            end
        end
    end
end

-- Manual control of any player (fake or real)
function TM:ManualAction(action, targetPlayer)
    local GS = BJ.GameState
    local currentPlayer = GS:GetCurrentPlayer()
    
    -- If target specified, use that; otherwise use current player
    local playerName = targetPlayer
    if not playerName or playerName == "" then
        playerName = currentPlayer
    end

    if not playerName then
        BJ:Print("No active player turn and no player specified.")
        return
    end
    
    -- Check if target player exists in game
    if not GS.players[playerName] then
        BJ:Print("Player '" .. playerName .. "' not found in game.")
        return
    end
    
    -- Check if it's actually this player's turn (if not forcing)
    if playerName ~= currentPlayer then
        BJ:Print("|cffff00ff[Test]|r Warning: Acting for " .. playerName .. " but it's " .. (currentPlayer or "no one") .. "'s turn")
    end

    BJ:Print("|cffff00ff[Test]|r Manual " .. action .. " for " .. playerName)

    if action == "hit" then
        local success, card = GS:PlayerHit(playerName)
        if success and BJ.UI then BJ.UI:OnPlayerHit(playerName, card) end
    elseif action == "stand" then
        GS:PlayerStand(playerName)
        if BJ.UI then BJ.UI:OnPlayerStand(playerName) end
    elseif action == "double" then
        local success, card = GS:PlayerDouble(playerName)
        if success and BJ.UI then BJ.UI:OnPlayerDouble(playerName, card) end
    elseif action == "split" then
        local success, c1, c2 = GS:PlayerSplit(playerName)
        if success and BJ.UI then BJ.UI:OnPlayerSplit(playerName, c1, c2) end
    end

    if BJ.UI then
        BJ.UI:UpdateDisplay()
    end

    -- Use CheckNextPlayer for proper timing (it handles CheckPhaseChange too)
    C_Timer.After(1.5, function()
        if BJ.Multiplayer.isHost then
            BJ.Multiplayer:CheckPhaseChange()
        end
        TM:CheckNextPlayer()
    end)
end

-- Force dealer to play their turn
function TM:DealerAction()
    local GS = BJ.GameState
    
    if GS.phase ~= GS.PHASE.PLAYER_TURN and GS.phase ~= GS.PHASE.DEALER_TURN then
        BJ:Print("Cannot trigger dealer action in current phase.")
        return
    end
    
    BJ:Print("|cffff00ff[Test]|r Forcing dealer turn...")
    
    -- Start dealer turn if not already in it
    if GS.phase == GS.PHASE.PLAYER_TURN then
        GS:StartDealerTurn()
    end
    
    -- Play out dealer hand
    GS:PlayDealerHand()
    
    if BJ.UI then
        BJ.UI:UpdateDisplay()
    end
    
    BJ.Multiplayer:CheckPhaseChange()
end

-- Force deal (for testing)
function TM:ForceDeal()
    if not self.enabled then return end

    local GS = BJ.GameState
    if GS.phase ~= GS.PHASE.WAITING_FOR_PLAYERS then
        BJ:Print("Can only force deal during waiting phase.")
        return
    end

    if #GS.playerOrder == 0 then
        BJ:Print("No players to deal to. Add fake players first.")
        return
    end

    BJ.Multiplayer:Deal()
    
    -- The animation callback in OnCardsDealt will handle triggering the first player
    -- No need to manually trigger here
end

-- Hook into game state to trigger fake player actions
local originalAdvanceToNextHand = BJ.GameState.AdvanceToNextHand
BJ.GameState.AdvanceToNextHand = function(self, playerName)
    originalAdvanceToNextHand(self, playerName)

    -- Don't auto-trigger during initial deal or if animations are running
    -- The animation callback in OnCardsDealt handles the first player turn
    if BJ.UI and (BJ.UI.isDealingAnimation or (BJ.UI.Animation and BJ.UI.Animation:IsAnimating())) then
        return
    end
    
    -- Also don't trigger if we're still in waiting phase (deal hasn't completed)
    if self.phase ~= self.PHASE.PLAYER_TURN then
        return
    end

    -- Check if next player is a fake player
    if TM.enabled and TM.autoPlay then
        local nextPlayer = self:GetCurrentPlayer()
        if nextPlayer and TM:IsFakePlayer(nextPlayer) then
            -- Use CheckNextPlayer for proper timing
            C_Timer.After(1.5, function()
                -- Double-check we're still in player turn phase
                if self.phase == self.PHASE.PLAYER_TURN then
                    TM:CheckNextPlayer()
                end
            end)
        end
    end
end

-- Hook into SkipToNextNonBlackjackPlayer to handle fake player after blackjack skips
local originalSkipFunc = BJ.GameState.SkipToNextNonBlackjackPlayer
if originalSkipFunc then
    BJ.GameState.SkipToNextNonBlackjackPlayer = function(self)
        originalSkipFunc(self)
        
        -- Don't auto-trigger during initial deal - the animation callback handles first turn
        -- This hook is called during CheckAndAutoStandBlackjacks BEFORE animations start
        if BJ.UI and (BJ.UI.isDealingAnimation or (BJ.UI.Animation and BJ.UI.Animation:IsAnimating())) then
            return
        end
        
        -- Also don't trigger if we're still setting up (not yet in player turn from user perspective)
        -- The OnCardsDealt callback will call CheckNextPlayer after animations complete
        if self.phase ~= self.PHASE.PLAYER_TURN then
            return
        end
        
        -- Check if current player after skip is a fake player
        if TM.enabled and TM.autoPlay then
            local currentPlayer = self:GetCurrentPlayer()
            if currentPlayer and TM:IsFakePlayer(currentPlayer) then
                -- Use CheckNextPlayer for proper timing
                C_Timer.After(1.5, function()
                    -- Double-check we're still in player turn phase
                    if self.phase == self.PHASE.PLAYER_TURN then
                        TM:CheckNextPlayer()
                    end
                end)
            end
        end
    end
end

--[[
    HIGH-LO TEST MODE FUNCTIONS
]]

-- Add fake player to High-Lo game
function TM:AddHiLoFakePlayer(name)
    if not self.enabled then
        BJ:Print("Test mode not enabled.")
        return
    end
    
    local HL = BJ.HiLoState
    if not HL then return end
    
    -- Count current players
    local count = #HL.playerOrder
    
    if count >= self.MAX_PLAYERS then
        BJ:Print("Maximum players reached (" .. self.MAX_PLAYERS .. ").")
        return
    end
    
    -- Generate name if not provided
    if not name or name == "" then
        for _, fakeName in ipairs(self.fakeNames) do
            if not HL.players[fakeName] and not self.fakePlayers[fakeName] then
                name = fakeName
                break
            end
        end
    end
    
    if not name then
        BJ:Print("No available fake player names.")
        return
    end
    
    -- Add to fake players tracking
    self.fakePlayers[name] = {
        name = name,
        autoPlay = self.autoPlay,
        isHiLo = true,
    }
    
    -- Add to High-Lo game
    local success = HL:AddPlayer(name)
    if success then
        BJ:Print("|cff00ff00Added High-Lo fake player:|r " .. name .. " (" .. (#HL.playerOrder) .. "/" .. self.MAX_PLAYERS .. ")")
        if BJ.UI and BJ.UI.HiLo then
            BJ.UI.HiLo:UpdatePlayerList()
            BJ.UI.HiLo:UpdateDisplay()
        end
    end
end

-- Remove last High-Lo fake player
function TM:RemoveHiLoFakePlayer()
    local HL = BJ.HiLoState
    if not HL then return end
    
    -- Find last fake player
    local lastFake = nil
    for i = #HL.playerOrder, 1, -1 do
        local name = HL.playerOrder[i]
        if self.fakePlayers[name] and self.fakePlayers[name].isHiLo then
            lastFake = name
            break
        end
    end
    
    if lastFake then
        -- Remove from game
        HL:RemovePlayer(lastFake)
        self.fakePlayers[lastFake] = nil
        BJ:Print("|cffff0000Removed High-Lo fake player:|r " .. lastFake)
        if BJ.UI and BJ.UI.HiLo then
            BJ.UI.HiLo:UpdatePlayerList()
            BJ.UI.HiLo:UpdateDisplay()
        end
    else
        BJ:Print("No High-Lo fake players to remove.")
    end
end

-- Simulate fake player rolls for High-Lo
function TM:SimulateHiLoRolls()
    if not self.enabled then return end
    
    local HL = BJ.HiLoState
    if not HL or HL.phase ~= HL.PHASE.ROLLING then return end
    
    local maxRoll = HL.maxRoll or 100
    
    -- Roll for all fake players who haven't rolled
    for _, name in ipairs(HL.playerOrder) do
        local player = HL.players[name]
        if player and not player.rolled and self.fakePlayers[name] then
            -- Generate random roll
            local roll = math.random(1, maxRoll)
            
            -- Record the roll
            local success = HL:RecordRoll(name, roll)
            if success then
                BJ:Print("|cffff00ff[Test]|r " .. name .. " rolls " .. roll .. " (1-" .. maxRoll .. ")")
                
                -- Play sound
                if BJ.UI and BJ.UI.Animation then
                    BJ.UI.Animation:PlayAnteSound()
                end
            end
            
            -- Small delay between rolls for visual effect
            C_Timer.After(0.3, function()
                if BJ.UI and BJ.UI.HiLo then
                    BJ.UI.HiLo:UpdatePlayerList()
                    BJ.UI.HiLo:UpdateDisplay()
                end
            end)
        end
    end
end

-- Simulate tiebreaker rolls for High-Lo
function TM:SimulateHiLoTiebreakerRolls()
    if not self.enabled then return end
    
    local HL = BJ.HiLoState
    if not HL or HL.phase ~= HL.PHASE.TIEBREAKER then return end
    
    -- Roll for all fake players in tiebreaker who haven't rolled
    for _, name in ipairs(HL.tiebreakerPlayers or {}) do
        if self.fakePlayers[name] and not HL.tiebreakerRolls[name] then
            local roll = math.random(1, 100)
            
            local success = HL:RecordTiebreakerRoll(name, roll)
            if success then
                BJ:Print("|cffff00ff[Test]|r " .. name .. " tiebreaker rolls " .. roll .. " (1-100)")
                
                if BJ.UI and BJ.UI.Animation then
                    BJ.UI.Animation:PlayAnteSound()
                end
            end
        end
    end
    
    -- Update display
    C_Timer.After(0.3, function()
        if BJ.UI and BJ.UI.HiLo then
            BJ.UI.HiLo:UpdatePlayerList()
            BJ.UI.HiLo:UpdateDisplay()
        end
    end)
end

-- Clear all High-Lo fake players
function TM:ClearHiLoFakePlayers()
    local HL = BJ.HiLoState
    if not HL then return end
    
    local removed = 0
    for name, data in pairs(self.fakePlayers) do
        if data.isHiLo then
            HL:RemovePlayer(name)
            self.fakePlayers[name] = nil
            removed = removed + 1
        end
    end
    
    BJ:Print("Removed " .. removed .. " High-Lo fake players.")
    if BJ.UI and BJ.UI.HiLo then
        BJ.UI.HiLo:UpdatePlayerList()
        BJ.UI.HiLo:UpdateDisplay()
    end
end

--[[
    TRIXIE DEBUG MODE
    Cycle through all Trixie animations with filename labels
]]

-- All Trixie image files in order
TM.trixieImages = {
    -- Wait images (31)
    "trix_wait1", "trix_wait2", "trix_wait3", "trix_wait4", "trix_wait5",
    "trix_wait6", "trix_wait7", "trix_wait8", "trix_wait9", "trix_wait10",
    "trix_wait11", "trix_wait12", "trix_wait13", "trix_wait14", "trix_wait15",
    "trix_wait16", "trix_wait17", "trix_wait18", "trix_wait19", "trix_wait20",
    "trix_wait21", "trix_wait22", "trix_wait23", "trix_wait24", "trix_wait25",
    "trix_wait26", "trix_wait27", "trix_wait28", "trix_wait29", "trix_wait30",
    "trix_wait31",
    -- Deal images (8)
    "trix_deal1", "trix_deal2", "trix_deal3", "trix_deal4",
    "trix_deal5", "trix_deal6", "trix_deal7", "trix_deal8",
    -- Shuffle images (12)
    "trix_shuf1", "trix_shuf2", "trix_shuf3", "trix_shuf4",
    "trix_shuf5", "trix_shuf6", "trix_shuf7", "trix_shuf8",
    "trix_shuf9", "trix_shuf10", "trix_shuf11", "trix_shuf12",
    -- Lose images (12)
    "trix_lose1", "trix_lose2", "trix_lose3", "trix_lose4",
    "trix_lose5", "trix_lose6", "trix_lose7", "trix_lose8",
    "trix_lose9", "trix_lose10", "trix_lose11", "trix_lose12",
    -- Win images (9)
    "trix_win1", "trix_win2", "trix_win3", "trix_win4", "trix_win5",
    "trix_win6", "trix_win7", "trix_win8", "trix_win9",
    -- Love images (10)
    "trix_love1", "trix_love2", "trix_love3", "trix_love4", "trix_love5",
    "trix_love6", "trix_love7", "trix_love8", "trix_love9", "trix_love10",
}

TM.trixieDebugIndex = 1
TM.trixieDebugActive = false

-- Turn off debug mode (called from OFF button on Trixie)
function TM:ToggleTrixieDebug()
    -- Just toggle the main debug mode off
    if self.enabled then
        self:Toggle()  -- This will disable everything
    end
end

-- Refresh Trixie debug display (call when windows show)
function TM:RefreshTrixieDebug()
    if self.enabled and self.trixieDebugActive then
        self:UpdateTrixieDebugDisplay()
    end
end

-- Show next Trixie image
function TM:NextTrixieImage()
    if not self.trixieDebugActive then return end
    
    self.trixieDebugIndex = self.trixieDebugIndex + 1
    if self.trixieDebugIndex > #self.trixieImages then
        self.trixieDebugIndex = 1
    end
    self:UpdateTrixieDebugDisplay()
end

-- Show previous Trixie image
function TM:PrevTrixieImage()
    if not self.trixieDebugActive then return end
    
    self.trixieDebugIndex = self.trixieDebugIndex - 1
    if self.trixieDebugIndex < 1 then
        self.trixieDebugIndex = #self.trixieImages
    end
    self:UpdateTrixieDebugDisplay()
end

-- Jump to specific index
function TM:SetTrixieImage(index)
    if not self.trixieDebugActive then return end
    
    index = tonumber(index) or 1
    if index < 1 then index = 1 end
    if index > #self.trixieImages then index = #self.trixieImages end
    
    self.trixieDebugIndex = index
    self:UpdateTrixieDebugDisplay()
end

-- Update all visible Trixie frames with current debug image
function TM:UpdateTrixieDebugDisplay()
    if not self.trixieDebugActive then return end
    
    local imageName = self.trixieImages[self.trixieDebugIndex]
    local texturePath = "Interface\\AddOns\\Chairfaces Casino\\Textures\\dealer\\" .. imageName
    
    BJ:Print("|cffff00ff[Trixie " .. self.trixieDebugIndex .. "/" .. #self.trixieImages .. "]|r " .. imageName)
    
    -- Update Blackjack Trixie
    if BJ.UI and BJ.UI.trixieFrame and BJ.UI.trixieFrame:IsVisible() then
        BJ.UI.trixieFrame.texture:SetTexture(texturePath)
        self:ShowTrixieDebugLabel(BJ.UI.trixieFrame, imageName)
    end
    
    -- Update Poker Trixie
    if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.trixieFrame and BJ.UI.Poker.trixieFrame:IsVisible() then
        BJ.UI.Poker.trixieFrame.texture:SetTexture(texturePath)
        self:ShowTrixieDebugLabel(BJ.UI.Poker.trixieFrame, imageName)
    end
    
    -- Update HiLo Trixie
    if BJ.UI and BJ.UI.HiLo and BJ.UI.HiLo.trixieFrame and BJ.UI.HiLo.trixieFrame:IsVisible() then
        BJ.UI.HiLo.trixieTexture:SetTexture(texturePath)
        self:ShowTrixieDebugLabel(BJ.UI.HiLo.trixieFrame, imageName)
    end
    
    -- Update Lobby Trixie
    if BJ.UI and BJ.UI.Lobby and BJ.UI.Lobby.lobbyFrame and BJ.UI.Lobby.lobbyFrame.trixieTexture then
        local lobbyFrame = BJ.UI.Lobby.lobbyFrame
        if lobbyFrame:IsVisible() and lobbyFrame.trixieFrame then
            lobbyFrame.trixieTexture:SetTexture(texturePath)
            self:ShowTrixieDebugLabel(lobbyFrame.trixieFrame, imageName)
        end
    end
    
    -- Update Help window Trixie
    if BJ.UI and BJ.UI.Lobby and BJ.UI.Lobby.helpFrame then
        local helpFrame = BJ.UI.Lobby.helpFrame
        if helpFrame:IsVisible() and helpFrame.trixieTexture then
            helpFrame.trixieTexture:SetTexture(texturePath)
            if helpFrame.trixieFrame then
                self:ShowTrixieDebugLabel(helpFrame.trixieFrame, imageName)
            end
        end
    end
end

-- Show debug label on a Trixie frame (just label, buttons are on test bar)
function TM:ShowTrixieDebugLabel(frame, imageName)
    if not frame then return end
    
    -- Create label if it doesn't exist
    if not frame.debugLabel then
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        label:SetPoint("CENTER", frame, "CENTER", 0, 0)
        label:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
        label:SetTextColor(0, 0, 0, 1)  -- Black text
        label:SetShadowOffset(1, -1)
        label:SetShadowColor(1, 1, 1, 0.8)  -- White shadow for readability
        frame.debugLabel = label
    end
    
    frame.debugLabel:SetText(imageName)
    frame.debugLabel:Show()
end

-- Hide all debug labels
function TM:HideTrixieDebugLabels()
    local function hideDebugLabel(frame)
        if frame and frame.debugLabel then 
            frame.debugLabel:Hide() 
        end
    end
    
    -- Blackjack
    if BJ.UI and BJ.UI.trixieFrame then
        hideDebugLabel(BJ.UI.trixieFrame)
    end
    
    -- Poker
    if BJ.UI and BJ.UI.Poker and BJ.UI.Poker.trixieFrame then
        hideDebugLabel(BJ.UI.Poker.trixieFrame)
    end
    
    -- HiLo
    if BJ.UI and BJ.UI.HiLo and BJ.UI.HiLo.trixieFrame then
        hideDebugLabel(BJ.UI.HiLo.trixieFrame)
    end
    
    -- Lobby
    if BJ.UI and BJ.UI.Lobby and BJ.UI.Lobby.lobbyFrame and BJ.UI.Lobby.lobbyFrame.trixieFrame then
        hideDebugLabel(BJ.UI.Lobby.lobbyFrame.trixieFrame)
    end
    
    -- Help
    if BJ.UI and BJ.UI.Lobby and BJ.UI.Lobby.helpFrame and BJ.UI.Lobby.helpFrame.trixieFrame then
        hideDebugLabel(BJ.UI.Lobby.helpFrame.trixieFrame)
    end
end
