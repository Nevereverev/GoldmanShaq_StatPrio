local ADDON, ns = ...

local O = {}
ns.Options = O

local WHITE = "Interface\\Buttons\\WHITE8X8"
local BG     = { 0.06, 0.06, 0.08, 0.97 }
local PANEL  = { 0.10, 0.10, 0.13, 1 }
local BORDER = { 0.22, 0.22, 0.28, 1 }

local frame
local state = { class = nil, spec = nil }
local classButtons, specButtons, rows, swatches = {}, {}, {}, {}

------------------------------------------------------------------------
-- Small skinning helpers
------------------------------------------------------------------------
local function Skin(f, bg, border)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function MakeButton(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, h)
    Skin(b, PANEL, BORDER)

    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    b.text:SetTextColor(0.9, 0.9, 0.9)

    b:SetScript("OnEnter", function(self)
        if not self:IsEnabled() then return end
        local r, g, bl = ns.GetAccent()
        self:SetBackdropBorderColor(r, g, bl, 1)
    end)
    b:SetScript("OnLeave", function(self)
        if self.selected then
            local r, g, bl = ns.GetAccent()
            self:SetBackdropBorderColor(r, g, bl, 1)
        else
            self:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 1)
        end
    end)

    function b:SetSelected(v)
        self.selected = v
        if v then
            local r, g, bl = ns.GetAccent()
            self:SetBackdropColor(r * 0.25, g * 0.25, bl * 0.25, 1)
            self:SetBackdropBorderColor(r, g, bl, 1)
        else
            self:SetBackdropColor(PANEL[1], PANEL[2], PANEL[3], 1)
            self:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 1)
        end
    end

    function b:SetActive(v)
        self:SetEnabled(v)
        self:SetAlpha(v and 1 or 0.35)
    end

    return b
end

local function MakeSwatch(parent, size)
    local sw = CreateFrame("Button", nil, parent, "BackdropTemplate")
    sw:SetSize(size, size)
    Skin(sw, PANEL, BORDER)
    sw.tex = sw:CreateTexture(nil, "ARTWORK")
    sw.tex:SetPoint("TOPLEFT", 2, -2)
    sw.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    return sw
end

local function AddTooltip(widget, text)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local function ClassEntry(classID)
    for _, cls in ipairs(ns.CLASSES) do
        if cls.id == classID then return cls end
    end
end

local function SelectClass(classID)
    local cls = ClassEntry(classID)
    if not cls then return end
    state.class = classID
    -- Prefer the player's own spec if it belongs to this class
    local mine = ns.GetPlayerSpecID()
    state.spec = cls.specs[1]
    for _, id in ipairs(cls.specs) do
        if id == mine then state.spec = id end
    end
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
function O.Refresh()
    if not frame then return end
    local ar, ag, ab = ns.GetAccent()
    local mine = ns.GetPlayerSpecID()

    frame.title:SetTextColor(ar, ag, ab)

    -- classes
    for i, cls in ipairs(ns.CLASSES) do
        classButtons[i]:SetSelected(cls.id == state.class)
    end

    -- specs
    local cls = ClassEntry(state.class)
    for i = 1, #specButtons do
        local id = cls and cls.specs[i]
        local b = specButtons[i]
        if id then
            b.specID = id
            b.text:SetText(ns.GetSpecName(id))
            b:SetSelected(id == state.spec)
            b:Show()
        else
            b:Hide()
        end
    end

    -- single "also show this spec" control for the selected spec tab
    -- (shown on every tab; ticks are universal, so they work whichever spec you play)
    if state.spec then
        local sc = ns.GetSpecColor(state.spec)
        frame.extraCheck:SetChecked(ns.IsExtra(state.spec))
        frame.extraText:SetText("Show " .. ns.GetSpecName(state.spec) .. " on tooltips")
        frame.extraSwatch.tex:SetColorTexture(sc[1], sc[2], sc[3], 1)
        frame.extraSwatch:ClearAllPoints()
        frame.extraSwatch:SetPoint("LEFT", frame.extraText, "RIGHT", 8, 0)
        frame.extraCheck:Show()
        frame.extraText:Show()
        frame.extraSwatch:Show()
    else
        frame.extraCheck:Hide()
        frame.extraText:Hide()
        frame.extraSwatch:Hide()
    end

    -- priority rows
    local list, ranks = ns.GetRanks(state.spec)
    local ties = ns.GetTies(state.spec)
    for i, row in ipairs(rows) do
        local key = list[i]
        local rank = ranks[i]
        local c = ns.GetRankColor(rank)
        row.rank:SetText("#" .. rank)
        row.rank:SetTextColor(c[1], c[2], c[3])
        row.name:SetText(ns.STAT_NAME[key] or key or "")
        row.up:SetActive(i > 1)
        row.down:SetActive(i < #rows)
        swatches[i].rank = rank
        swatches[i].tex:SetColorTexture(c[1], c[2], c[3], 1)
        if i > 1 then
            row.tie:Show()
            row.tie:SetSelected(ties[i])
        else
            row.tie:Hide()
        end
    end

    frame.enable:SetChecked(ns.db.enabled)
end

------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------
local function Move(i, delta)
    local list = ns.GetPrio(state.spec)
    local j = i + delta
    if j < 1 or j > #list then return end
    list[i], list[j] = list[j], list[i]
    ns.SetPrio(state.spec, list)
    O.Refresh()
end

local function ShowPicker(c, onChange)
    local info = {
        r = c[1], g = c[2], b = c[3],
        hasOpacity = false,
        swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            onChange(r, g, b)
            O.Refresh()
        end,
        cancelFunc = function(prev)
            if prev then onChange(prev.r, prev.g, prev.b) end
            O.Refresh()
        end,
    }
    ColorPickerFrame:SetupColorPickerAndShow(info)
end

local function PickColor(rank)
    ShowPicker(ns.GetRankColor(rank), function(r, g, b)
        ns.SetRankColor(rank, r, g, b)
    end)
end

local function PickSpecColor(specID)
    ShowPicker(ns.GetSpecColor(specID), function(r, g, b)
        ns.SetSpecColor(specID, r, g, b)
    end)
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
local function Build()
    frame = CreateFrame("Frame", "GoldmanShaq_StatPrioFrame", UIParent, "BackdropTemplate")
    frame:SetSize(630, 380)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    Skin(frame, BG, BORDER)
    tinsert(UISpecialFrames, "GoldmanShaq_StatPrioFrame") -- close with ESC

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 14, -12)
    frame.title:SetText("GoldmanShaq StatPrio")

    local close = MakeButton(frame, "X", 24, 24)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Left: class list
    local left = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    left:SetPoint("TOPLEFT", 10, -42)
    left:SetSize(140, 328)
    Skin(left, PANEL, BORDER)

    for i, cls in ipairs(ns.CLASSES) do
        local className, classFile = GetClassInfo(cls.id)
        local b = MakeButton(left, className or ("Class " .. cls.id), 128, 22)
        b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 24)
        local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if cc then b.text:SetTextColor(cc.r, cc.g, cc.b) end
        b:SetScript("OnClick", function()
            SelectClass(cls.id)
            O.Refresh()
        end)
        classButtons[i] = b
    end

    -- Right: spec tabs (each with a "show on tooltip" tick and a label color)
    local rx = 162
    for i = 1, 4 do
        local x = rx + (i - 1) * 104
        local b = MakeButton(frame, "", 100, 26)
        b:SetPoint("TOPLEFT", x, -42)
        b:SetScript("OnClick", function(self)
            state.spec = self.specID
            O.Refresh()
        end)

        specButtons[i] = b
    end

    -- One checkbox for whichever spec tab is selected
    local extraCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    extraCheck:SetSize(22, 22)
    extraCheck:SetPoint("TOPLEFT", rx - 2, -72)
    extraCheck:SetScript("OnClick", function(self)
        ns.SetExtra(state.spec, self:GetChecked())
    end)
    frame.extraCheck = extraCheck

    frame.extraText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.extraText:SetPoint("LEFT", extraCheck, "RIGHT", 2, 0)
    frame.extraText:SetTextColor(0.9, 0.9, 0.9)

    local extraSwatch = MakeSwatch(frame, 18)
    extraSwatch:SetPoint("LEFT", frame.extraText, "RIGHT", 8, 0)
    extraSwatch:SetScript("OnClick", function() PickSpecColor(state.spec) end)
    AddTooltip(extraSwatch, "Color of this spec's name on tooltips")
    frame.extraSwatch = extraSwatch

    local hdr = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", rx, -102)
    hdr:SetText("Priority  (top = highest)")
    hdr:SetTextColor(0.7, 0.7, 0.7)

    -- Priority rows
    for i = 1, #ns.STAT_ORDER do
        local row = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        row:SetSize(458, 40)
        row:SetPoint("TOPLEFT", rx, -122 - (i - 1) * 46)
        Skin(row, PANEL, BORDER)

        row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        row.rank:SetPoint("LEFT", 12, 0)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        row.name:SetPoint("LEFT", 64, 0)

        local sw = MakeSwatch(row, 22)
        sw:SetPoint("RIGHT", -184, 0)
        sw:SetScript("OnClick", function(self) PickColor(self.rank or i) end)
        sw:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Color for rank #" .. (self.rank or i))
            GameTooltip:Show()
        end)
        sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
        swatches[i] = sw

        -- Tie with the stat above (same rank, same color)
        row.tie = MakeButton(row, "Tie", 44, 24)
        row.tie:SetPoint("RIGHT", -136, 0)
        row.tie:SetScript("OnClick", function()
            ns.ToggleTie(state.spec, i)
            O.Refresh()
        end)
        AddTooltip(row.tie, "Same rank as the stat above")

        row.up = MakeButton(row, "Up", 60, 24)
        row.up:SetPoint("RIGHT", -70, 0)
        row.up:SetScript("OnClick", function() Move(i, -1) end)

        row.down = MakeButton(row, "Down", 60, 24)
        row.down:SetPoint("RIGHT", -6, 0)
        row.down:SetScript("OnClick", function() Move(i, 1) end)

        rows[i] = row
    end

    -- Bottom controls
    local enable = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    enable:SetPoint("BOTTOMLEFT", rx - 4, 12)
    enable:SetSize(24, 24)
    enable.text = enable:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    enable.text:SetPoint("LEFT", enable, "RIGHT", 4, 0)
    enable.text:SetText("Enable StatPrio (master switch)")
    enable:SetScript("OnClick", function(self)
        ns.db.enabled = self:GetChecked() and true or false
    end)
    frame.enable = enable

    local reset = MakeButton(frame, "Reset this spec", 120, 26)
    reset:SetPoint("BOTTOMRIGHT", -10, 10)
    reset:SetScript("OnClick", function()
        ns.ResetPrio(state.spec)
        O.Refresh()
    end)

    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", rx, 42)
    note:SetWidth(458)
    note:SetJustifyH("LEFT")
    note:SetText("Tooltips use your current spec. Ticked specs of your class show beside it.")

    frame:SetScript("OnShow", O.Refresh)

    -- Start on the player's own class/spec
    local classID = select(3, UnitClass("player"))
    local mine = ns.GetPlayerSpecID()
    SelectClass((mine and ns.ClassOfSpec(mine)) or classID or 1)

    -- Frames start shown; hide it so the first Toggle() opens it (and runs OnShow/Refresh)
    frame:Hide()
end

function O.Toggle()
    if not ns.db then return end
    if not frame then Build() end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end
