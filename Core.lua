local ADDON, ns = ...

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function CopyList(t)
    local c = {}
    for i, v in ipairs(t) do c[i] = v end
    return c
end

-- Make sure a priority list contains each stat exactly once
local function Normalize(list)
    local seen, out = {}, {}
    for _, key in ipairs(list or {}) do
        if ns.STAT_NAME[key] and not seen[key] then
            seen[key] = true
            out[#out + 1] = key
        end
    end
    for _, key in ipairs(ns.STAT_ORDER) do
        if not seen[key] then out[#out + 1] = key end
    end
    return out
end

local function ColorToHex(c)
    return string.format("%02x%02x%02x",
        math.floor(c[1] * 255 + 0.5),
        math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end

------------------------------------------------------------------------
-- Saved variables
------------------------------------------------------------------------
function ns.InitDB()
    GoldmanShaq_StatPrioDB = GoldmanShaq_StatPrioDB or {}
    local db = GoldmanShaq_StatPrioDB
    if db.enabled == nil then db.enabled = true end
    db.prios = db.prios or {}
    db.ties = db.ties or {}          -- [specID] = { [position] = true } (position ties with the one above)
    db.extra = db.extra or {}        -- [specID] = true -> also shown on tooltips
    db.specColors = db.specColors or {} -- [specID] = { r, g, b } for the "// Spec" label
    db.minimap = db.minimap or {}
    if db.minimap.angle == nil then db.minimap.angle = 215 end
    -- Colors changed in 0.2.0: reset old saved colors once so the new defaults apply
    if db.colorsVersion ~= 2 then
        db.colors = {}
        db.colorsVersion = 2
    end
    db.colors = db.colors or {}
    for i, def in ipairs(ns.DEFAULT_COLORS) do
        local c = db.colors[i]
        if type(c) ~= "table" or not c[1] or not c[2] or not c[3] then
            db.colors[i] = { def[1], def[2], def[3] }
        end
    end
    ns.db = db
end

function ns.GetPrio(specID)
    local saved = ns.db and ns.db.prios[specID]
    if saved then return Normalize(saved) end
    return Normalize(CopyList(ns.SPEC_DEFAULTS[specID] or ns.GENERIC_DEFAULT))
end

function ns.SetPrio(specID, list)
    ns.db.prios[specID] = Normalize(list)
end

function ns.ResetPrio(specID)
    ns.db.prios[specID] = nil
    ns.db.ties[specID] = nil
end

-- Ties: ties[i] == true means the stat at position i has the same rank as position i-1
function ns.GetTies(specID)
    local saved = ns.db and ns.db.ties[specID]
    local out = {}
    for i = 2, #ns.STAT_ORDER do
        out[i] = (saved and saved[i]) and true or false
    end
    return out
end

function ns.ToggleTie(specID, position)
    if position < 2 or position > #ns.STAT_ORDER then return end
    local t = ns.db.ties[specID]
    if not t then
        t = {}
        ns.db.ties[specID] = t
    end
    t[position] = (not t[position]) or nil
end

-- Returns: list (stat keys in order), ranks (rank per position), byKey (rank per stat key)
-- Dense ranking: Crit = Haste > Mastery > Vers  ->  1, 1, 2, 3
function ns.GetRanks(specID)
    local list = ns.GetPrio(specID)
    local ties = ns.GetTies(specID)
    local ranks, byKey = {}, {}
    local r = 0
    for i, key in ipairs(list) do
        if i == 1 or not ties[i] then r = r + 1 end
        ranks[i] = r
        byKey[key] = r
    end
    return list, ranks, byKey
end

function ns.GetRankColor(rank)
    return ns.db.colors[rank] or ns.DEFAULT_COLORS[rank] or { 1, 1, 1 }
end

function ns.SetRankColor(rank, r, g, b)
    ns.db.colors[rank] = { r, g, b }
end

-- Extra specs shown next to the current one on tooltips
function ns.IsExtra(specID)
    return ns.db.extra[specID] and true or false
end

function ns.SetExtra(specID, value)
    ns.db.extra[specID] = value and true or nil
end

local DEFAULT_SPEC_COLOR = { 1.00, 0.82, 0.00 }

function ns.GetSpecColor(specID)
    return ns.db.specColors[specID] or DEFAULT_SPEC_COLOR
end

function ns.SetSpecColor(specID, r, g, b)
    ns.db.specColors[specID] = { r, g, b }
end

function ns.ClassOfSpec(specID)
    for _, cls in ipairs(ns.CLASSES) do
        for _, id in ipairs(cls.specs) do
            if id == specID then return cls.id end
        end
    end
end

------------------------------------------------------------------------
-- Player info
------------------------------------------------------------------------
function ns.GetPlayerSpecID()
    local CSI = C_SpecializationInfo
    local getSpec = (CSI and CSI.GetSpecialization) or GetSpecialization
    local getInfo = (CSI and CSI.GetSpecializationInfo) or GetSpecializationInfo
    if not getSpec or not getInfo then return nil end
    local index = getSpec()
    if not index then return nil end
    local id = getInfo(index)
    return id
end

function ns.GetSpecName(specID)
    local CSI = C_SpecializationInfo
    local fn = GetSpecializationInfoByID or (CSI and CSI.GetSpecializationInfoByID)
    if fn then
        local ok, _, name = pcall(fn, specID)
        if ok and name then return name end
    end
    return "Spec " .. specID
end

-- Accent color. Uses EllesmereUI's accent if we can find it, else teal.
-- (Phase 2: replace this guess with the real EllesmereUI API.)
function ns.GetAccent()
    local E = _G.EllesmereUI
    if type(E) == "table" then
        local ok, r, g, b = pcall(function()
            if type(E.GetAccentColor) == "function" then
                local a, b2, c = E.GetAccentColor(E)
                if type(a) == "table" then return a.r or a[1], a.g or a[2], a.b or a[3] end
                return a, b2, c
            end
        end)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    return 0.05, 0.82, 0.62
end

------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------
-- Any line we already decorated contains a colored "#<rank>"
local MARKER = "|c%x%x%x%x%x%x%x%x#%d|r"

local function IsSecret(v)
    return issecretvalue and issecretvalue(v)
end

local function Strip(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return text
end

local function DecorateTooltip(tooltip)
    if not ns.db or not ns.db.enabled then return end
    if not tooltip or not tooltip.GetName or not tooltip.NumLines then return end
    local name = tooltip:GetName()
    if not name then return end

    local specID = ns.GetPlayerSpecID()
    if not specID then return end

    local _, _, mainRanks = ns.GetRanks(specID)

    -- Extra specs (same class as the player, other than the current spec)
    local extras = {}
    local myClass = ns.ClassOfSpec(specID)
    for id in pairs(ns.db.extra) do
        if id ~= specID and ns.ClassOfSpec(id) == myClass then
            local _, _, byKey = ns.GetRanks(id)
            extras[#extras + 1] = {
                id = id,
                byKey = byKey,
                name = ns.GetSpecName(id),
                hex = ColorToHex(ns.GetSpecColor(id)),
            }
        end
    end
    table.sort(extras, function(a, b) return a.id < b.id end)

    local changed = false
    for i = 2, tooltip:NumLines() do
        local fs = _G[name .. "TextLeft" .. i]
        if fs then
            local text = fs:GetText()
            if type(text) == "string" and not IsSecret(text) and not text:find(MARKER) then
                local plain = Strip(text)
                -- Only real stat lines ("+123 Haste"), not "Equip: ..." descriptions
                if plain:find("^%s*%+%d") then
                    for key, label in pairs(ns.STAT_NAME) do
                        if plain:find(label, 1, true) then
                            local out = text
                            local r = mainRanks[key]
                            if r then
                                out = string.format("%s |cff%s#%d|r", out, ColorToHex(ns.GetRankColor(r)), r)
                            end
                            for _, e in ipairs(extras) do
                                local er = e.byKey[key]
                                if er then
                                    out = string.format("%s |cff%s// %s|r |cff%s#%d|r",
                                        out, e.hex, e.name, ColorToHex(ns.GetRankColor(er)), er)
                                end
                            end
                            if out ~= text then
                                fs:SetText(out)
                                changed = true
                            end
                            break
                        end
                    end
                end
            end
        end
    end

    -- Let the tooltip grow to fit the longer lines
    if changed and tooltip.Show then tooltip:Show() end
end

local function SafeDecorate(tooltip)
    pcall(DecorateTooltip, tooltip)
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, addon)
    if addon ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    ns.InitDB()
    if ns.InitMinimap then ns.InitMinimap() end

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
            SafeDecorate(tooltip)
        end)
    end
end)

SLASH_STATPRIO1 = "/statprio"
SLASH_STATPRIO2 = "/sprio"
SlashCmdList["STATPRIO"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "minimap" then
        if ns.ToggleMinimapButton then ns.ToggleMinimapButton() end
    elseif ns.Options and ns.Options.Toggle then
        ns.Options.Toggle()
    end
end
