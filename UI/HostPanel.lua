--[[
    Chairface's Casino - UI/HostPanel.lua
    Host configuration panel for game settings
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.hostPanel = nil

-- Blackjack's host settings, on the shared host popup (UI/HostForm.lua)
function UI:CreateHostPanel()
    if self.hostForm then return end
    local form = UI.HostForm:Create({
        name = "BlackjackHostPanel",
        title = "Blackjack - Host",
        onStart = function(f)
            f:Hide()
            BJ.Multiplayer:HostTable()
        end,
    })
    form:Number("ante", "Ante Amount (1-1000g):", { default = 10, min = 1, max = 1000, unit = "g" })
    form:Choice("maxMultiplier", "Max Bet Multiple:", { 1, 2, 5, 10 }, {
        default = 1, buttonWidth = 56,
        text = function(v) return v == 1 and "None" or (v .. "x") end,
        status = function(v) return v == 1 and "(Ante only)" or ("(Up to " .. v .. "x)") end,
    })
    form:Choice("maxPlayers", "Max Players:", { 2, 4, 6, 10, 15, 20 }, {
        default = 20, buttonWidth = 38, status = function(v) return "(" .. v .. " max)" end,
    })
    form:Countdown("countdownEnabled", "countdownSeconds", "Time to Join / Deal:", { offText = "(Manual)" })
    form:Choice("dealerHitsSoft17", "Dealer Soft 17:", { true, false }, {
        default = true, buttonWidth = 100,
        text = function(v) return v and "H17 (Hit)" or "S17 (Stand)" end,
        tooltip = { "Dealer Soft 17", "H17: the dealer HITS soft 17 - the more common rule, slightly favours the house.",
            "S17: the dealer STANDS on soft 17 - better for players." },
    })
    form:Finish()
    self.hostForm = form
    self.hostPanel = form.frame
end

-- Reload every field from the saved host settings
function UI:UpdateHostPanel()
    if self.hostForm then self.hostForm:Refresh() end
end

-- Show host panel
function UI:ShowHostPanel()
    if not self.hostPanel then
        self:CreateHostPanel()
    end
    
    -- Check if can host - but allow during settlement phase
    local GS = BJ.GameState
    if GS.phase ~= GS.PHASE.SETTLEMENT and GS.phase ~= GS.PHASE.IDLE then
        local canStart, reason = BJ.SessionManager:CanStartSession()
        if not canStart then
            BJ:Print("Cannot host: " .. reason)
            return
        end
    end
    
    -- Check if in group (bypass in test mode)
    local inTestMode = BJ.TestMode and BJ.TestMode.enabled
    if not IsInGroup() and not inTestMode then
        BJ:Print("You must be in a party or raid to host.")
        return
    end
    
    self.hostForm:Show()
end
