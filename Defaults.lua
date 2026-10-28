local ADDON, ns = ...

-- Secondary stats handled by the addon (keys used in saved priority lists)
ns.STAT_ORDER = { "CRIT", "HASTE", "MASTERY", "VERS" }

-- Localized names, taken from Blizzard global strings so it works in any client language
ns.STAT_NAME = {
    CRIT    = ITEM_MOD_CRIT_RATING_SHORT    or "Critical Strike",
    HASTE   = ITEM_MOD_HASTE_RATING_SHORT   or "Haste",
    MASTERY = ITEM_MOD_MASTERY_RATING_SHORT or "Mastery",
    VERS    = ITEM_MOD_VERSATILITY          or "Versatility",
}

-- Default colors for rank #1..#5 (r, g, b)
ns.DEFAULT_COLORS = {
    { 0.70, 0.30, 1.00 }, -- #1 purple
    { 0.25, 0.60, 1.00 }, -- #2 blue
    { 0.12, 1.00, 0.00 }, -- #3 green
    { 1.00, 1.00, 1.00 }, -- #4 white
    { 0.60, 0.60, 0.60 }, -- #5 gray
}

-- classID -> spec IDs (names are looked up from the game at runtime)
ns.CLASSES = {
    { id = 1,  specs = { 71, 72, 73 } },          -- Warrior
    { id = 2,  specs = { 65, 66, 70 } },          -- Paladin
    { id = 3,  specs = { 253, 254, 255 } },       -- Hunter
    { id = 4,  specs = { 259, 260, 261 } },       -- Rogue
    { id = 5,  specs = { 256, 257, 258 } },       -- Priest
    { id = 6,  specs = { 250, 251, 252 } },       -- Death Knight
    { id = 7,  specs = { 262, 263, 264 } },       -- Shaman
    { id = 8,  specs = { 62, 63, 64 } },          -- Mage
    { id = 9,  specs = { 265, 266, 267 } },       -- Warlock
    { id = 10, specs = { 268, 269, 270 } },       -- Monk
    { id = 11, specs = { 102, 103, 104, 105 } },  -- Druid
    { id = 12, specs = { 577, 581, 1480 } },      -- Demon Hunter (incl. Devourer)
    { id = 13, specs = { 1467, 1468, 1473 } },    -- Evoker
}

-- PLACEHOLDER defaults. Stat priorities change with patches and sims, so
-- these are only a starting point: edit them in game (/statprio).
-- Add per-spec entries here if you want your own starting values, e.g.
-- ns.SPEC_DEFAULTS[72] = { "HASTE", "MASTERY", "CRIT", "VERS" }
ns.SPEC_DEFAULTS = {}
ns.GENERIC_DEFAULT = { "CRIT", "HASTE", "MASTERY", "VERS" }
