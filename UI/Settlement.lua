--[[
    Chairface's Casino - UI/Settlement.lua
    Detailed settlement display and "who owes who" ledger
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

-- Enhanced settlement summary with colors and formatting
function UI:GetFormattedSettlement()
    local GS = BJ.GameState
    if not GS.ledger then
        return "No settlement data"
    end
    
    local lines = {}
    
    -- Header
    table.insert(lines, "|cffffd700=== SETTLEMENT ===|r")
    table.insert(lines, "")
    
    -- Dealer result
    local dealerScore = GS:ScoreHand(GS.dealerHand)
    local dealerStr = GS:FormatHand(GS.dealerHand)
    if dealerScore.isBust then
        table.insert(lines, "|cffffffffDealer:|r " .. dealerStr .. " |cffff4444(BUST)|r")
    elseif dealerScore.isBlackjack then
        table.insert(lines, "|cffffffffDealer:|r " .. dealerStr .. " |cffffd700(BLACKJACK)|r")
    else
        table.insert(lines, "|cffffffffDealer:|r " .. dealerStr .. " (" .. dealerScore.total .. ")")
    end
    table.insert(lines, "")
    
    -- Player results
    for _, entry in ipairs(GS.ledger.entries) do
        -- Player header with net result
        local netColor = "|cffffff00"  -- Yellow for push
        local netText = "PUSH"
        if entry.net > 0 then
            netColor = "|cff00ff00"  -- Green for win
            netText = "+" .. entry.net .. "g"
        elseif entry.net < 0 then
            netColor = "|cffff4444"  -- Red for loss
            netText = entry.net .. "g"
        end
        
        table.insert(lines, "|cffffffff" .. entry.player .. ":|r " .. netColor .. netText .. "|r")
        
        -- Detail each hand
        for _, detail in ipairs(entry.details) do
            if detail.type == "hand" then
                local resultColor = "|cffffff00"
                local resultText = detail.result
                
                if detail.result == "win" or detail.result == "blackjack" then
                    resultColor = "|cff00ff00"
                elseif detail.result == "lose" or detail.result == "bust" then
                    resultColor = "|cffff4444"
                end
                
                local handStr = string.format("  Hand %d: %s (%d) - %s%s|r",
                    detail.handIndex,
                    detail.hand,
                    detail.score,
                    resultColor,
                    string.upper(resultText)
                )
                table.insert(lines, handStr)
                
                -- Show payout
                if detail.amount ~= 0 then
                    local payoutColor = detail.amount > 0 and "|cff00ff00" or "|cffff4444"
                    local payoutSign = detail.amount > 0 and "+" or ""
                    table.insert(lines, "    Bet: " .. detail.bet .. "g → " .. 
                        payoutColor .. payoutSign .. detail.amount .. "g|r")
                end
                
            elseif detail.type == "insurance" then
                local insColor = detail.result == "win" and "|cff00ff00" or "|cffff4444"
                table.insert(lines, "  Insurance: " .. insColor .. string.upper(detail.result) .. 
                    " (" .. detail.amount .. "g)|r")
            end
        end
        table.insert(lines, "")
    end
    
    -- Who owes who section
    table.insert(lines, "|cffffd700--- WHO OWES WHO ---|r")
    
    local anyOwed = false
    for _, entry in ipairs(GS.ledger.entries) do
        if entry.net > 0 then
            table.insert(lines, "|cff00ff00" .. GS.hostName .. "|r owes |cff00ff00" .. 
                entry.player .. "|r |cffffffff" .. entry.net .. "g|r")
            anyOwed = true
        elseif entry.net < 0 then
            table.insert(lines, "|cffff4444" .. entry.player .. "|r owes |cffff4444" .. 
                GS.hostName .. "|r |cffffffff" .. math.abs(entry.net) .. "g|r")
            anyOwed = true
        end
    end
    
    if not anyOwed then
        table.insert(lines, "|cffffff00No debts - all pushes!|r")
    end
    
    table.insert(lines, "")
    
    -- House summary
    if GS.ledger.hostProfit > 0 then
        table.insert(lines, "|cffffd700House Profit: |cff00ff00+" .. GS.ledger.hostProfit .. "g|r")
    elseif GS.ledger.hostProfit < 0 then
        table.insert(lines, "|cffffd700House Loss: |cffff4444" .. GS.ledger.hostProfit .. "g|r")
    else
        table.insert(lines, "|cffffd700House: Break even|r")
    end
    
    return table.concat(lines, "\n")
end

-- Override the show settlement to use formatted version
function UI:ShowSettlement()
    local summary = self:GetFormattedSettlement()
    self.settlementPanel.text:SetText(summary)
    self.settlementPanel:Show()
end

-- Post settlement to party/raid chat
function UI:PostSettlementToChat()
    local GS = BJ.GameState
    if not GS.ledger then return end
    
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or "SAY")
    
    SendChatMessage("=== Blackjack Settlement ===", channel)
    
    local dealerScore = GS:ScoreHand(GS.dealerHand)
    SendChatMessage("Dealer: " .. GS:FormatHand(GS.dealerHand) .. " (" .. dealerScore.total .. ")", channel)
    
    for _, entry in ipairs(GS.ledger.entries) do
        local netText
        if entry.net > 0 then
            netText = "WON " .. entry.net .. "g"
        elseif entry.net < 0 then
            netText = "LOST " .. math.abs(entry.net) .. "g"
        else
            netText = "PUSH"
        end
        SendChatMessage(entry.player .. ": " .. netText, channel)
    end
    
    SendChatMessage("--- Debts ---", channel)
    for _, entry in ipairs(GS.ledger.entries) do
        if entry.net > 0 then
            SendChatMessage(GS.hostName .. " owes " .. entry.player .. " " .. entry.net .. "g", channel)
        elseif entry.net < 0 then
            SendChatMessage(entry.player .. " owes " .. GS.hostName .. " " .. math.abs(entry.net) .. "g", channel)
        end
    end
end
