--[[
    Chairface's Casino - CardLib.lua
    Shared card constants and deck utilities used by all card games.

    The seeded PRNG and shuffle order must stay byte-identical across
    versions: hosts and clients rebuild the same deck from the same seed.
]]

local BJ = ChairfacesCasino
BJ.CardLib = {}
local CL = BJ.CardLib

CL.SUITS = { "hearts", "diamonds", "clubs", "spades" }

-- Blackjack ordering/values (Ace first; A = 11, reduced to 1 on bust)
CL.BLACKJACK_RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
CL.BLACKJACK_RANK_VALUES = {
    ["A"] = 11,
    ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6,
    ["7"] = 7, ["8"] = 8, ["9"] = 9, ["10"] = 10,
    ["J"] = 10, ["Q"] = 10, ["K"] = 10
}

-- Poker ordering/values (Ace high)
CL.POKER_RANKS = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A" }
CL.POKER_RANK_VALUES = {
    ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6,
    ["7"] = 7, ["8"] = 8, ["9"] = 9, ["10"] = 10,
    ["J"] = 11, ["Q"] = 12, ["K"] = 13, ["A"] = 14
}

-- Simple seeded PRNG (Linear Congruential Generator)
function CL.SeededRandom(seed)
    local state = seed
    return function()
        state = (state * 1103515245 + 12345) % 2147483648
        return state / 2147483648
    end
end

-- Build numDecks worth of cards from ranks/suits and Fisher-Yates
-- shuffle them with the seeded PRNG. Returns the deck array.
function CL:CreateShuffledDeck(seed, numDecks, ranks, suits)
    ranks = ranks or self.POKER_RANKS
    suits = suits or self.SUITS
    local deck = {}

    for _ = 1, (numDecks or 1) do
        for _, suit in ipairs(suits) do
            for _, rank in ipairs(ranks) do
                deck[#deck + 1] = {
                    rank = rank,
                    suit = suit,
                    id = #deck + 1
                }
            end
        end
    end

    local rng = self.SeededRandom(seed)
    for i = #deck, 2, -1 do
        local j = math.floor(rng() * i) + 1
        deck[i], deck[j] = deck[j], deck[i]
    end

    return deck
end
