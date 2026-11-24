--[[
    Chairface's Casino - UI/PokerFrame.lua
    5 Card Stud: the shared poker table (UI/PokerTable.lua) with no rule
    overrides - its defaults ARE stud (ante, no board, no blinds).
]]

local BJ = ChairfacesCasino
local UI = BJ.UI

UI.Poker = UI.PokerTable:Embed({}, {
    key = "poker",
    name = "5 Card Stud",
    state = "PokerState",
    net = "PokerMultiplayer",
    prefix = "Poker",
    frameName = "ChairfacesCasinoPoker",
    logFrameName = "CasinoPokerLogFrame",
    resetPopup = "CASINO_POKER_RESET",
})
