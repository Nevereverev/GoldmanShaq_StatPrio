local ADDON, ns = ...

local DEFAULT_PROFILE = "Default"
local EXPORT_PREFIX = "GSP1:"
local MAX_IMPORT_LEN = 60000

------------------------------------------------------------------------
-- Profile data helpers
------------------------------------------------------------------------
local function NewData()
    return { prios = {}, ties = {}, extra = {}, specColors = {}, colors = {} }
end

local function IsColor(c)
    return type(c) == "table"
        and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number"
end

-- Make sure every table exists and every rank color is set
local function Ensure(p)
    p.prios = p.prios or {}
    p.ties = p.ties or {}
    p.extra = p.extra or {}
    p.specColors = p.specColors or {}
    p.colors = p.colors or {}
    for i, def in ipairs(ns.DEFAULT_COLORS) do
        if not IsColor(p.colors[i]) then
            p.colors[i] = { def[1], def[2], def[3] }
        end
    end
end

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = DeepCopy(x) end
    return c
end

local function CleanName(name)
    name = tostring(name or "")
    name = name:gsub("[%c|]", "")
    name = name:gsub("^%s+", "")
    name = name:gsub("%s+$", "")
    return name:sub(1, 32)
end

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

------------------------------------------------------------------------
-- Init / migration / switching
------------------------------------------------------------------------
function ns.ActivateProfile(name)
    local db = ns.db
    if not name or not db.profiles[name] then name = DEFAULT_PROFILE end
    if not db.profiles[name] then db.profiles[name] = NewData() end
    Ensure(db.profiles[name])
    db.charProfile[CharKey()] = name
    ns.profile = db.profiles[name]
    ns.profileName = name
end

function ns.InitProfiles()
    local db = ns.db
    db.profiles = db.profiles or {}
    db.charProfile = db.charProfile or {}

    -- Migrate the pre-profile layout (data used to sit at the top level)
    if db.prios or db.ties or db.extra or db.specColors or db.colors then
        if not db.profiles[DEFAULT_PROFILE] then
            db.profiles[DEFAULT_PROFILE] = {
                prios = db.prios or {},
                ties = db.ties or {},
                extra = db.extra or {},
                specColors = db.specColors or {},
                colors = (db.colorsVersion == 2 and db.colors) or {},
            }
        end
        db.prios, db.ties, db.extra, db.specColors, db.colors, db.colorsVersion =
            nil, nil, nil, nil, nil, nil
    end

    ns.ActivateProfile(db.charProfile[CharKey()] or DEFAULT_PROFILE)
end

function ns.GetProfileNames()
    local names = {}
    for name in pairs(ns.db.profiles) do names[#names + 1] = name end
    table.sort(names, function(a, b)
        if a == DEFAULT_PROFILE then return b ~= DEFAULT_PROFILE end
        if b == DEFAULT_PROFILE then return false end
        return a:lower() < b:lower()
    end)
    return names
end

function ns.SwitchProfile(name)
    if ns.db.profiles[name] then
        ns.ActivateProfile(name)
        return true
    end
    return false
end

-- Case-insensitive lookup, used by the slash command
function ns.SwitchProfileByName(name)
    name = CleanName(name):lower()
    for existing in pairs(ns.db.profiles) do
        if existing:lower() == name then
            return ns.SwitchProfile(existing)
        end
    end
    return false
end

-- Returns the new name, or nil + error message
function ns.CreateProfile(name, copyCurrent)
    local n = CleanName(name)
    if n == "" then return nil, "Please enter a name." end
    if ns.db.profiles[n] then return nil, "A profile with that name already exists." end
    ns.db.profiles[n] = copyCurrent and DeepCopy(ns.profile) or NewData()
    ns.ActivateProfile(n)
    return n
end

function ns.RenameProfile(old, new)
    local n = CleanName(new)
    if old == DEFAULT_PROFILE then return nil, "The Default profile cannot be renamed." end
    if n == "" then return nil, "Please enter a name." end
    if n == old then return old end
    if ns.db.profiles[n] then return nil, "A profile with that name already exists." end
    ns.db.profiles[n] = ns.db.profiles[old]
    ns.db.profiles[old] = nil
    for key, value in pairs(ns.db.charProfile) do
        if value == old then ns.db.charProfile[key] = n end
    end
    if ns.profileName == old then
        ns.profileName = n
    end
    return n
end

function ns.DeleteProfile(name)
    if name == DEFAULT_PROFILE then return nil, "The Default profile cannot be deleted." end
    if name == ns.profileName then return nil, "Switch to another profile first." end
    if not ns.db.profiles[name] then return nil, "That profile does not exist." end
    ns.db.profiles[name] = nil
    return true
end

function ns.ResetProfile()
    ns.db.profiles[ns.profileName] = NewData()
    ns.ActivateProfile(ns.profileName)
end

------------------------------------------------------------------------
-- Serializer (own tiny format, parsed without loadstring, so it is safe)
------------------------------------------------------------------------
local function SerKey(k)
    return type(k) == "number" and k or tostring(k)
end

local function Ser(v, out)
    local t = type(v)
    if t == "number" then
        out[#out + 1] = string.format("%.6g", v)
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "string" then
        local escaped = v:gsub('[\\"]', "\\%0")
        out[#out + 1] = '"' .. escaped .. '"'
    elseif t == "table" then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) == "number"
        end)
        out[#out + 1] = "{"
        for i, k in ipairs(keys) do
            if i > 1 then out[#out + 1] = "," end
            Ser(SerKey(k), out)
            out[#out + 1] = ":"
            Ser(v[k], out)
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "F"
    end
end

local function Parse(str)
    local pos = 1

    local function value(depth)
        if depth > 8 then error("nested too deep") end
        local c = str:sub(pos, pos)

        if c == "{" then
            pos = pos + 1
            local t = {}
            if str:sub(pos, pos) == "}" then
                pos = pos + 1
                return t
            end
            while true do
                local k = value(depth + 1)
                if type(k) ~= "number" and type(k) ~= "string" then error("bad key") end
                if str:sub(pos, pos) ~= ":" then error("expected ':'") end
                pos = pos + 1
                t[k] = value(depth + 1)
                local d = str:sub(pos, pos)
                pos = pos + 1
                if d == "}" then return t end
                if d ~= "," then error("expected ',' or '}'") end
            end

        elseif c == '"' then
            pos = pos + 1
            local buf = {}
            while true do
                local ch = str:sub(pos, pos)
                if ch == "" then error("unterminated string") end
                if ch == "\\" then
                    buf[#buf + 1] = str:sub(pos + 1, pos + 1)
                    pos = pos + 2
                elseif ch == '"' then
                    pos = pos + 1
                    break
                else
                    buf[#buf + 1] = ch
                    pos = pos + 1
                end
            end
            return table.concat(buf)

        elseif c == "T" then
            pos = pos + 1
            return true
        elseif c == "F" then
            pos = pos + 1
            return false
        else
            local num = str:match("^-?[%d%.]+[eE]?[%+%-]?%d*", pos)
            local n = num and tonumber(num)
            if not n then error("bad value") end
            pos = pos + #num
            return n
        end
    end

    local result = value(0)
    if pos ~= #str + 1 then error("trailing data") end
    return result
end

------------------------------------------------------------------------
-- Base64
------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_REV = {}
for i = 1, #B64 do B64_REV[B64:sub(i, i)] = i - 1 end

local function B64Encode(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local i1 = math.floor(n / 262144)
        local i2 = math.floor(n / 4096) % 64
        local i3 = math.floor(n / 64) % 64
        local i4 = n % 64
        out[#out + 1] = B64:sub(i1 + 1, i1 + 1)
        out[#out + 1] = B64:sub(i2 + 1, i2 + 1)
        out[#out + 1] = b and B64:sub(i3 + 1, i3 + 1) or "="
        out[#out + 1] = c and B64:sub(i4 + 1, i4 + 1) or "="
    end
    return table.concat(out)
end

local function B64Decode(s)
    s = s:gsub("[^%w%+/]", "")
    local out = {}
    for i = 1, #s, 4 do
        local chunk = s:sub(i, i + 3)
        local cnt = #chunk
        if cnt < 2 then return nil end
        local n = 0
        for j = 1, 4 do
            local v = 0
            if j <= cnt then
                v = B64_REV[chunk:sub(j, j)]
                if not v then return nil end
            end
            n = n * 64 + v
        end
        local b1 = math.floor(n / 65536)
        local b2 = math.floor(n / 256) % 256
        local b3 = n % 256
        if cnt == 4 then
            out[#out + 1] = string.char(b1, b2, b3)
        elseif cnt == 3 then
            out[#out + 1] = string.char(b1, b2)
        else
            out[#out + 1] = string.char(b1)
        end
    end
    return table.concat(out)
end

------------------------------------------------------------------------
-- Export / import
------------------------------------------------------------------------
function ns.ExportProfile()
    local out = {}
    Ser({ v = 1, n = ns.profileName, p = ns.profile }, out)
    local encoded = EXPORT_PREFIX .. B64Encode(table.concat(out))
    -- wrap lines so the text box stays readable
    local lines = {}
    for i = 1, #encoded, 60 do
        lines[#lines + 1] = encoded:sub(i, i + 59)
    end
    return table.concat(lines, "\n")
end

-- Rebuild a profile from untrusted data: only known keys and valid values survive
local function Sanitize(src)
    if type(src) ~= "table" then return nil end

    local validStat, validSpec = {}, {}
    for _, key in ipairs(ns.STAT_ORDER) do validStat[key] = true end
    for _, cls in ipairs(ns.CLASSES) do
        for _, id in ipairs(cls.specs) do validSpec[id] = true end
    end

    local function CleanColor(c)
        if type(c) ~= "table" then return nil end
        local out = {}
        for i = 1, 3 do
            local v = c[i]
            if type(v) ~= "number" or v ~= v or v < 0 or v > 1 then return nil end
            out[i] = v
        end
        return out
    end

    local p = NewData()

    if type(src.prios) == "table" then
        for specID, list in pairs(src.prios) do
            if validSpec[specID] and type(list) == "table" then
                local clean = {}
                for i = 1, #ns.STAT_ORDER do
                    if validStat[list[i]] then clean[#clean + 1] = list[i] end
                end
                p.prios[specID] = clean
            end
        end
    end

    if type(src.ties) == "table" then
        for specID, t in pairs(src.ties) do
            if validSpec[specID] and type(t) == "table" then
                local clean = {}
                for pos = 2, #ns.STAT_ORDER do
                    if t[pos] == true then clean[pos] = true end
                end
                p.ties[specID] = clean
            end
        end
    end

    if type(src.extra) == "table" then
        for specID, v in pairs(src.extra) do
            if validSpec[specID] and v == true then p.extra[specID] = true end
        end
    end

    if type(src.specColors) == "table" then
        for specID, c in pairs(src.specColors) do
            local clean = CleanColor(c)
            if validSpec[specID] and clean then p.specColors[specID] = clean end
        end
    end

    if type(src.colors) == "table" then
        for i = 1, #ns.DEFAULT_COLORS do
            local clean = CleanColor(src.colors[i])
            if clean then p.colors[i] = clean end
        end
    end

    return p
end

-- Returns the name of the new (now active) profile, or nil + error message
function ns.ImportProfile(text, name)
    local s = (text or ""):gsub("%s+", "")
    if s:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
        return nil, "That is not a StatPrio profile string."
    end
    if #s > MAX_IMPORT_LEN then
        return nil, "That string is too long to be a profile."
    end

    local raw = B64Decode(s:sub(#EXPORT_PREFIX + 1))
    if not raw then
        return nil, "The string is damaged or cut off."
    end

    local ok, data = pcall(Parse, raw)
    if not ok or type(data) ~= "table" then
        return nil, "The string is damaged or cut off."
    end

    local p = Sanitize(data.p)
    if not p then
        return nil, "The string does not contain a profile."
    end

    local n = CleanName(name)
    if n == "" then n = CleanName(type(data.n) == "string" and data.n or "") end
    if n == "" then n = "Imported" end

    local base, i = n, 2
    while ns.db.profiles[n] do
        n = base .. " (" .. i .. ")"
        i = i + 1
    end

    ns.db.profiles[n] = p
    ns.ActivateProfile(n)
    return n
end
