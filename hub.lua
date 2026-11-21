--[[
    TUPACHUP  |  single-file Roblox script hub
    No external UI library, no dependencies.
    Entry point: loadstring(game:HttpGet("<your-host>/Exec"))()
    Unload: getgenv().Tupachup.Unload()
]]

local VERSION = "2.1.0"
local BRAND = "Tupachup"

if getgenv().Tupachup and getgenv().Tupachup.Unload then
    pcall(getgenv().Tupachup.Unload)
end

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UIS              = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local HttpService      = game:GetService("HttpService")
local Lighting         = game:GetService("Lighting")
local TeleportService  = game:GetService("TeleportService")
local VirtualUser      = game:GetService("VirtualUser")

local LP  = Players.LocalPlayer
local PG  = LP:WaitForChild("PlayerGui")
local CAM = workspace.CurrentCamera

local MarketplaceService = game:GetService("MarketplaceService")

-- ============================================================
-- CAPABILITIES  (level 3-8 executors: degrade, never error)
-- ============================================================
local CAP = {
    writefile = type(writefile) == "function",
    readfile  = type(readfile) == "function",
    clipboard = type(setclipboard) == "function" or type(toclipboard) == "function",
    touch     = type(firetouchinterest) == "function",
    clickDet  = type(fireclickdetector) == "function",
    prompt    = type(fireproximityprompt) == "function",
    keypress  = type(keypress) == "function",
    http      = type(game.HttpGet) == "function" or type(game.HttpGetAsync) == "function",
    request   = type(request) == "function"
        or type(http_request) == "function"
        or (type(syn) == "table" and type(syn.request) == "function"),
    fpsCap    = type(setfpscap) == "function",
    firesignal = type(firesignal) == "function",
    mouse     = type(mouse1click) == "function",
}

-- ============================================================
-- GAME DETECTION
-- ============================================================
local GAME_WORDS = {
    PS99 = { "pet simulator 99", "pet sim 99", "ps99" },
    PGO  = { "pets go", "pets go!" },
    GAG  = { "grow a garden" },
    ETFB = { "escape tsunami", "tsunami for brainrots", "brainrots" },
}

local GAME_LABEL = {
    PS99 = "Pet Simulator 99",
    PGO  = "Pets GO!",
    GAG  = "Grow a Garden",
    ETFB = "Escape Tsunami for Brainrots",
    UNIVERSAL = "Universal",
}

local function detectGame()
    local names = { tostring(game.Name) }
    pcall(function()
        local info = MarketplaceService:GetProductInfo(game.PlaceId)
        if info and info.Name then table.insert(names, tostring(info.Name)) end
    end)
    for key, words in pairs(GAME_WORDS) do
        for _, raw in ipairs(names) do
            local low = raw:lower()
            for _, w in ipairs(words) do
                if low:find(w, 1, true) then return key, raw end
            end
        end
    end
    return "UNIVERSAL", tostring(game.Name)
end

local DETECTED_KEY, DETECTED_NAME = detectGame()
local activeGame = DETECTED_KEY

-- ============================================================
-- THEME
-- ============================================================
local THEME = {
    Accent = Color3.fromRGB(245, 165, 36),
    Bg     = Color3.fromRGB(17, 17, 20),
    Panel  = Color3.fromRGB(25, 25, 29),
    Row    = Color3.fromRGB(34, 34, 40),
    Text   = Color3.fromRGB(238, 238, 244),
    Sub    = Color3.fromRGB(139, 139, 150),
    Stroke = Color3.fromRGB(45, 45, 53),
    Red    = Color3.fromRGB(255, 92, 92),
    Green  = Color3.fromRGB(86, 226, 140),
}

local WIN_W, WIN_H = 620, 442
local TOP_H, RAIL_W, PAD = 42, 152, 12
local ROW_W = WIN_W - RAIL_W - PAD * 2

-- the show/hide chip sits at the top centre; phones need room for the Roblox
-- topbar, and the window keeps clear of the chip instead of hiding behind it
local IS_MOBILE = UIS.TouchEnabled and not UIS.KeyboardEnabled
local CHIP_TOP = IS_MOBILE and 44 or 10
local TOP_RESERVE = IS_MOBILE and (CHIP_TOP + 40) or 0

-- ============================================================
-- STATE
-- ============================================================
local Flags   = {}
local Setters = {}
local Conns   = {}
local Stops   = {}
local menuKey = Enum.KeyCode.RightShift

local function track(c)
    table.insert(Conns, c)
    return c
end

local function bind(flag, fn)
    Setters[flag] = fn
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function round(v, step)
    return math.floor(v / step + 0.5) * step
end

local function new(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do
        inst[k] = v
    end
    if parent then inst.Parent = parent end
    return inst
end

-- A freshly joined client has no Character for a second or two, and a respawn
-- swaps it mid-click. Reading LP.Character alone made every toggle a no-op in
-- that window, which reads as "the hub does nothing". The workspace fallback
-- covers executors that report Character late.
local function char()
    local c = LP.Character
    if not c then
        local found = workspace:FindFirstChild(LP.Name)
        if found then c = found end
    end
    if not c then return nil end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if not hum then
        local alt = c:FindFirstChildWhichIsA("Humanoid", true)
        if alt then hum = alt end
    end
    if not hum then return nil end
    return c, hum
end

local function root()
    local c = LP.Character
    if not c then c = workspace:FindFirstChild(LP.Name) end
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function copy(text)
    if setclipboard then
        pcall(setclipboard, text)
        return true
    elseif toclipboard then
        pcall(toclipboard, text)
        return true
    end
    return false
end

-- ============================================================
-- NOTIFICATIONS
-- ============================================================
-- Toast cards: drawn icon, title, body, accent rail and a draining timer bar.
-- notify(text, kind, title) keeps every two-argument call site working.
local notifyOn = true
local notifHolder
local notifCards = {}

local NOTIF_W, NOTIF_H, NOTIF_STEP = 300, 58, 64
local NOTIF_LIFE = 3.6

local NOTIF_STYLE = {
    success = { color = THEME.Green, title = "Success", mark = "check" },
    error   = { color = THEME.Red, title = "Error", mark = "bang" },
    warn    = { color = Color3.fromRGB(255, 176, 66), title = "Warning", mark = "bang" },
    info    = { color = THEME.Accent, title = BRAND, mark = "brand" },
}

-- Gotham has no check mark glyph, so the icon is drawn out of two bars
local function drawMark(kind, parent, color)
    local box = new("Frame", {
        Size = UDim2.fromOffset(22, 22),
        Position = UDim2.fromOffset(10, 8),
        BackgroundColor3 = color,
        BackgroundTransparency = 0.85,
        BorderSizePixel = 0,
    }, parent)
    new("UICorner", { CornerRadius = UDim.new(0, 6) }, box)

    if kind == "check" then
        local a = new("Frame", {
            Size = UDim2.fromOffset(2, 6),
            Position = UDim2.fromOffset(7, 11),
            Rotation = -45,
            BackgroundColor3 = color,
            BorderSizePixel = 0,
        }, box)
        new("UICorner", { CornerRadius = UDim.new(1, 0) }, a)
        local b = new("Frame", {
            Size = UDim2.fromOffset(2, 10),
            Position = UDim2.fromOffset(12, 8),
            Rotation = 45,
            BackgroundColor3 = color,
            BorderSizePixel = 0,
        }, box)
        new("UICorner", { CornerRadius = UDim.new(1, 0) }, b)
    elseif kind == "bang" then
        new("Frame", {
            Size = UDim2.fromOffset(2, 9),
            Position = UDim2.fromOffset(10, 5),
            BackgroundColor3 = color,
            BorderSizePixel = 0,
        }, box)
        local dot = new("Frame", {
            Size = UDim2.fromOffset(2, 2),
            Position = UDim2.fromOffset(10, 16),
            BackgroundColor3 = color,
            BorderSizePixel = 0,
        }, box)
        new("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
    else
        new("TextLabel", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "T",
            Font = Enum.Font.GothamBlack,
            TextSize = 12,
            TextColor3 = color,
        }, box)
    end
end

local function reflowNotifs()
    for i, card in ipairs(notifCards) do
        if card.Parent then
            TweenService:Create(card, TweenInfo.new(0.18, Enum.EasingStyle.Quint), {
                Position = UDim2.new(1, -(NOTIF_W + 16), 0, 12 + (i - 1) * NOTIF_STEP),
            }):Play()
        end
    end
end

local function dropNotif(card)
    for i, c in ipairs(notifCards) do
        if c == card then
            table.remove(notifCards, i)
            break
        end
    end
    if card.Parent then card:Destroy() end
    reflowNotifs()
end

local function notify(text, kind, title)
    if not notifyOn then return end
    if not notifHolder or not notifHolder.Parent then
        notifHolder = new("ScreenGui", {
            Name = "TupachupNotify",
            ResetOnSpawn = false,
            IgnoreGuiInset = true,
            DisplayOrder = 999,
        }, PG)
        notifCards = {}
    end

    local style = NOTIF_STYLE[kind] or NOTIF_STYLE.info
    if #notifCards >= 5 then dropNotif(notifCards[1]) end

    local slot = #notifCards
    local card = new("Frame", {
        Size = UDim2.fromOffset(NOTIF_W, NOTIF_H),
        Position = UDim2.new(1, NOTIF_W + 24, 0, 12 + slot * NOTIF_STEP),
        BackgroundColor3 = THEME.Panel,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, notifHolder)
    table.insert(notifCards, card)
    new("UICorner", { CornerRadius = UDim.new(0, 8) }, card)
    new("UIStroke", { Color = style.color, Thickness = 1, Transparency = 0.55 }, card)

    new("Frame", {
        Size = UDim2.new(0, 3, 1, 0),
        BackgroundColor3 = style.color,
        BorderSizePixel = 0,
    }, card)

    drawMark(style.mark, card, style.color)

    new("TextLabel", {
        Size = UDim2.new(1, -52, 0, 16),
        Position = UDim2.fromOffset(40, 9),
        BackgroundTransparency = 1,
        Text = title or style.title,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = THEME.Text,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, card)

    new("TextLabel", {
        Size = UDim2.new(1, -52, 0, 24),
        Position = UDim2.fromOffset(40, 25),
        BackgroundTransparency = 1,
        Text = tostring(text),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        Font = Enum.Font.GothamMedium,
        TextSize = 11,
        TextColor3 = THEME.Sub,
    }, card)

    -- timer bar: the tween is the clock, so it always matches the dismiss
    local timer = new("Frame", {
        Size = UDim2.new(1, 0, 0, 2),
        Position = UDim2.new(0, 0, 1, -2),
        BackgroundColor3 = style.color,
        BackgroundTransparency = 0.25,
        BorderSizePixel = 0,
    }, card)
    TweenService:Create(timer, TweenInfo.new(NOTIF_LIFE, Enum.EasingStyle.Linear), {
        Size = UDim2.new(0, 0, 0, 2),
    }):Play()

    TweenService:Create(card, TweenInfo.new(0.26, Enum.EasingStyle.Quint), {
        Position = UDim2.new(1, -(NOTIF_W + 16), 0, 12 + slot * NOTIF_STEP),
    }):Play()

    card.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dropNotif(card)
        end
    end)

    task.delay(NOTIF_LIFE, function()
        if not card.Parent then return end
        TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Quint), {
            Position = UDim2.new(1, NOTIF_W + 24, 0, 12),
        }):Play()
        task.wait(0.22)
        dropNotif(card)
    end)
end

-- ============================================================
-- GAME LOCK  (PS99 only)
-- ============================================================
-- The hub is built and tuned for one game. Running it anywhere else used to
-- half-work and read as broken, so outside PS99 it now builds nothing and says
-- why. Detection reads game.Name and the marketplace product name; a place id
-- in `placeIds` overrides both, and `getgenv().TupachupForce = true` skips the
-- lock while you are testing.
local GAME_LOCK = {
    allow    = { PS99 = true },
    label    = "Pet Simulator 99",
    placeIds = {},
}

do
    local forced = rawget(getgenv(), "TupachupForce") and true or false
    local allowed = forced
        or GAME_LOCK.allow[DETECTED_KEY] == true
        or GAME_LOCK.placeIds[game.PlaceId] == true

    if not allowed then
        local card = new("ScreenGui", {
            Name = "TupachupLock",
            ResetOnSpawn = false,
            IgnoreGuiInset = true,
            DisplayOrder = 900,
        }, PG)

        local box = new("Frame", {
            Name = "Lock",
            Size = UDim2.fromOffset(300, 108),
            Position = UDim2.new(0.5, -150, 0.2, 0),
            BackgroundColor3 = THEME.Bg,
            BorderSizePixel = 0,
        }, card)
        new("UICorner", { CornerRadius = UDim.new(0, 10) }, box)
        new("UIStroke", { Color = THEME.Accent, Thickness = 1, Transparency = 0.4 }, box)

        new("Frame", {
            Size = UDim2.new(0, 3, 1, 0),
            BackgroundColor3 = THEME.Accent,
            BorderSizePixel = 0,
        }, box)

        local title = new("TextLabel", {
            Size = UDim2.new(1, -24, 0, 22),
            Position = UDim2.fromOffset(16, 12),
            BackgroundTransparency = 1,
            Text = BRAND,
            TextXAlignment = Enum.TextXAlignment.Left,
            Font = Enum.Font.GothamBold,
            TextSize = 16,
            TextColor3 = THEME.Accent,
        }, box)

        new("TextLabel", {
            Size = UDim2.new(1, -32, 0, 16),
            Position = UDim2.fromOffset(16, 38),
            BackgroundTransparency = 1,
            Text = "Runs on " .. GAME_LOCK.label .. " only",
            TextXAlignment = Enum.TextXAlignment.Left,
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            TextColor3 = THEME.Text,
        }, box)

        new("TextLabel", {
            Size = UDim2.new(1, -32, 0, 30),
            Position = UDim2.fromOffset(16, 58),
            BackgroundTransparency = 1,
            Text = "this game: " .. tostring(DETECTED_NAME) ..
                "  (" .. tostring(game.PlaceId) .. ")",
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            Font = Enum.Font.GothamMedium,
            TextSize = 10,
            TextColor3 = THEME.Sub,
        }, box)

        title.Text = BRAND .. "  -  " .. GAME_LOCK.label .. " only"
        print("[" .. BRAND:upper() .. "] locked: " .. tostring(DETECTED_NAME)
            .. " (" .. tostring(game.PlaceId) .. ") is not " .. GAME_LOCK.label)
        warn("[" .. BRAND:upper() .. "] this build runs on " .. GAME_LOCK.label .. " only")

        task.delay(9, function()
            if card and card.Parent then card:Destroy() end
        end)
        return
    end
end

-- ============================================================
-- ============================================================
-- PREMIUM  (key gate, Luarmor-shaped but yours)
-- ============================================================
-- A key is TPC-<TIER>-<EXPIRY>-<ID>-<SIG>. The hub only ever stores the
-- SHA-256 of an issued key, so reading this file back does not hand anyone a
-- working key. tools/keygen.mjs writes the list between the markers below.
local Premium
do
local function sha256(msg)
    local function band(a, b, c)
        local r = a & b
        if c then r = r & c end
        return r
    end
    local function bxor(a, b, c)
        local r = a ~ b
        if c then r = r ~ c end
        return r
    end
    local function rrot(x, n) return ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF end
    local function rsh(x, n) return (x & 0xFFFFFFFF) >> n end

    local K = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    }

    local bits = #msg * 8
    msg = msg .. "\128"
    while (#msg % 64) ~= 56 do msg = msg .. "\0" end
    local hi = math.floor(bits / 4294967296)
    msg = msg
        .. string.char((hi >> 24) & 0xFF, (hi >> 16) & 0xFF, (hi >> 8) & 0xFF, hi & 0xFF)
        .. string.char((bits >> 24) & 0xFF, (bits >> 16) & 0xFF, (bits >> 8) & 0xFF, bits & 0xFF)

    local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
    local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    local w = {}

    for chunk = 1, #msg, 64 do
        for i = 1, 16 do
            local o = chunk + (i - 1) * 4
            local b1, b2, b3, b4 = msg:byte(o, o + 3)
            w[i] = ((b1 << 24) | (b2 << 16) | (b3 << 8) | b4) & 0xFFFFFFFF
        end
        for i = 17, 64 do
            local s0 = bxor(rrot(w[i - 15], 7), rrot(w[i - 15], 18), rsh(w[i - 15], 3))
            local s1 = bxor(rrot(w[i - 2], 17), rrot(w[i - 2], 19), rsh(w[i - 2], 10))
            w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF
        end

        local a, b, c, d, e, f, g, hh = h0, h1, h2, h3, h4, h5, h6, h7
        for i = 1, 64 do
            local S1 = bxor(rrot(e, 6), rrot(e, 11), rrot(e, 25))
            local ch = bxor(band(e, f), band(~e, g))
            local t1 = (hh + S1 + ch + K[i] + w[i]) & 0xFFFFFFFF
            local S0 = bxor(rrot(a, 2), rrot(a, 13), rrot(a, 22))
            local maj = bxor(band(a, b), band(a, c), band(b, c))
            local t2 = (S0 + maj) & 0xFFFFFFFF
            hh, g, f, e = g, f, e, (d + t1) & 0xFFFFFFFF
            d, c, b, a = c, b, a, (t1 + t2) & 0xFFFFFFFF
        end

        h0 = (h0 + a) & 0xFFFFFFFF
        h1 = (h1 + b) & 0xFFFFFFFF
        h2 = (h2 + c) & 0xFFFFFFFF
        h3 = (h3 + d) & 0xFFFFFFFF
        h4 = (h4 + e) & 0xFFFFFFFF
        h5 = (h5 + f) & 0xFFFFFFFF
        h6 = (h6 + g) & 0xFFFFFFFF
        h7 = (h7 + hh) & 0xFFFFFFFF
    end

    return string.format("%08x%08x%08x%08x%08x%08x%08x%08x", h0, h1, h2, h3, h4, h5, h6, h7)
end

Premium = {
    file = "Tupachup/premium.json",
    -- BEGIN PREMIUM KEYS  (generated by tools/keygen.mjs)
    keys = {
    { "e7969014daaf8b34d1d8d60371fe856198f0ecdad5514dbacea1c5f3c69f27c1", "PRO", 1797897599 },
    { "577a44aa4a70ae36901f64ed29053972ea4cdae31f9de10abc4b1abf3a4671e7", "LIF", 0 },
    },
    -- END PREMIUM KEYS
    -- a set, so the lock pass can test a page name in one lookup
    tabs = { ["Pumpkin Tycoon"] = true, ["Webhook"] = true },
    status = { valid = false, tier = "free", reason = "no key" },
}

Premium.hash = sha256

function Premium.lookup(key)
    if type(key) ~= "string" then return nil end
    key = key:gsub("%s", ""):upper()
    if #key < 12 then return nil end
    local digest = sha256(key)
    for _, row in ipairs(Premium.keys) do
        if row[1] == digest then
            return { tier = row[2] or "PRO", expires = row[3] or 0, key = key }
        end
    end
    return nil
end

function Premium.check(key)
    local hit = Premium.lookup(key)
    if not hit then return { valid = false, tier = "free", reason = "unknown key" } end
    if hit.expires > 0 and os.time() > hit.expires then
        return { valid = false, tier = "free", reason = "key expired" }
    end
    return { valid = true, tier = hit.tier, expires = hit.expires, key = hit.key }
end

function Premium.save(key, status)
    if not (writefile and isfile) then return end
    pcall(function() if type(makefolder) == "function" then makefolder("Tupachup") end end)
    pcall(writefile, Premium.file, HttpService:JSONEncode({ key = key, saved = os.time() }))
end

function Premium.restore()
    if not (readfile and isfile) then return nil end
    local ok, raw = pcall(readfile, Premium.file)
    if not ok or type(raw) ~= "string" then return nil end
    local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok2 or type(data) ~= "table" then return nil end
    return data.key
end

function Premium.activate(key, quiet)    local status = Premium.check(key)
    Premium.status = status
    if status.valid then
        Premium.save(key, status)
        getgenv().TupachupKey = key
        if Premium.unlockAll then Premium.unlockAll() end
        if not quiet then
            notify("Key accepted - " .. status.tier .. " unlocked", "success", "Premium")
        end
        return status
    end
    if not quiet then
        notify(status.reason, "error", "Premium")
    end
    return status
end

-- script_key is the global ZapHub used, so the same one-liner shape works here
do
    local supplied = rawget(getgenv(), "TupachupKey")
    if type(supplied) ~= "string" or supplied == "" then
        local ok, global = pcall(function() return script_key end)
        if ok and type(global) == "string" and global ~= "" then supplied = global end
    end
    if type(supplied) ~= "string" or supplied == "" then
        supplied = Premium.restore()
    end
    if type(supplied) == "string" and supplied ~= "" then
        Premium.activate(supplied, true)
    end
end
end


-- GUI ROOT
-- ============================================================
local gui = new("ScreenGui", {
    Name = "Tupachup",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 500,
}, PG)

local window = new("Frame", {
    Name = "Window",
    Size = UDim2.fromOffset(WIN_W, WIN_H),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, TOP_RESERVE / 2),
    BackgroundColor3 = THEME.Bg,
    BorderSizePixel = 0,
    ClipsDescendants = false,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 12) }, window)
local winStroke = new("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, window)

-- phones: shrink the whole window, never overflow the viewport
local uiScale = new("UIScale", { Scale = 1 }, window)
local function fitScreen()
    local vp = (CAM and CAM.ViewportSize) or Vector2.new(1280, 720)
    local s = math.min(1, (vp.X - 24) / WIN_W, (vp.Y - 24 - TOP_RESERVE) / WIN_H)
    uiScale.Scale = clamp(s, 0.5, 1)
end
fitScreen()
if CAM then
    track(CAM:GetPropertyChangedSignal("ViewportSize"):Connect(fitScreen))
end
new("Frame", {
    Size = UDim2.new(1, 0, 0, 1),
    Position = UDim2.fromOffset(0, TOP_H),
    BackgroundColor3 = THEME.Stroke,
    BorderSizePixel = 0,
}, window)

-- topbar
local topbar = new("Frame", {
    Name = "Topbar",
    Size = UDim2.new(1, 0, 0, TOP_H),
    BackgroundTransparency = 1,
}, window)

local logo = new("Frame", {
    Size = UDim2.fromOffset(20, 20),
    Position = UDim2.fromOffset(14, 11),
    BackgroundColor3 = THEME.Accent,
    BorderSizePixel = 0,
}, topbar)
new("UICorner", { CornerRadius = UDim.new(0, 5) }, logo)
new("TextLabel", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Text = "T",
    Font = Enum.Font.GothamBlack,
    TextSize = 13,
    TextColor3 = Color3.fromRGB(22, 16, 10),
}, logo)

new("TextLabel", {
    Size = UDim2.new(1, -220, 1, 0),
    Position = UDim2.fromOffset(42, 0),
    BackgroundTransparency = 1,
    Text = "<b>" .. BRAND .. " Premium</b>  <font color=\"#8b8b96\">|  "
        .. (GAME_LABEL[activeGame] or "Universal") .. "</font>",
    RichText = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextColor3 = THEME.Text,
    TextTruncate = Enum.TextTruncate.AtEnd,
}, topbar)

local function topButton(text, x, color, cb)
    local b = new("TextButton", {
        Size = UDim2.fromOffset(26, 22),
        Position = UDim2.new(1, x, 0, 8),
        BackgroundColor3 = THEME.Row,
        BorderSizePixel = 0,
        Text = text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = color,
        AutoButtonColor = false,
    }, topbar)
    new("UICorner", { CornerRadius = UDim.new(0, 5) }, b)
    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = THEME.Stroke }):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = THEME.Row }):Play()
    end)
    b.MouseButton1Click:Connect(cb)
    return b
end

-- sidebar
local rail = new("Frame", {
    Name = "Rail",
    Size = UDim2.new(0, RAIL_W, 1, -TOP_H),
    Position = UDim2.fromOffset(0, TOP_H),
    BackgroundColor3 = THEME.Panel,
    BorderSizePixel = 0,
}, window)
new("Frame", {
    Size = UDim2.new(0, 1, 1, 0),
    Position = UDim2.new(1, -1, 0, 0),
    BackgroundColor3 = THEME.Stroke,
    BorderSizePixel = 0,
}, rail)

local tabHolder = new("ScrollingFrame", {
    Name = "Tabs",
    Size = UDim2.new(1, 0, 1, -58),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    CanvasSize = UDim2.fromOffset(0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = THEME.Stroke,
    ScrollingDirection = Enum.ScrollingDirection.Y,
}, rail)

-- player card: avatar in a ring, "Welcome," and the display name
local welcome = new("Frame", {
    Name = "Welcome",
    Size = UDim2.new(1, 0, 0, 58),
    Position = UDim2.new(0, 0, 1, -58),
    BackgroundColor3 = THEME.Row,
    BackgroundTransparency = 0.55,
    BorderSizePixel = 0,
}, rail)
new("Frame", {
    Size = UDim2.new(1, -20, 0, 1),
    Position = UDim2.fromOffset(10, 0),
    BackgroundColor3 = THEME.Stroke,
    BorderSizePixel = 0,
}, welcome)

local displayName = tostring(LP.DisplayName or LP.Name or "player")
local shownName = #displayName > 15 and (string.sub(displayName, 1, 14) .. "...") or displayName

local avatarHolder = new("Frame", {
    Name = "Avatar",
    Size = UDim2.fromOffset(34, 34),
    Position = UDim2.fromOffset(10, 12),
    BackgroundColor3 = THEME.Panel,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, welcome)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, avatarHolder)
new("UIStroke", { Color = THEME.Accent, Thickness = 1.5, Transparency = 0.25 }, avatarHolder)

-- the letter shows through when the thumbnail has not loaded yet
new("TextLabel", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Text = string.sub(displayName, 1, 1):upper(),
    Font = Enum.Font.GothamBlack,
    TextSize = 14,
    TextColor3 = THEME.Accent,
}, avatarHolder)
local avatarImage = new("ImageLabel", {
    Name = "Thumb",
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LP.UserId) .. "&w=150&h=150",
    ScaleType = Enum.ScaleType.Crop,
}, avatarHolder)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, avatarImage)

new("TextLabel", {
    Size = UDim2.new(1, -56, 0, 13),
    Position = UDim2.fromOffset(52, 13),
    BackgroundTransparency = 1,
    Text = "Welcome,",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Enum.Font.GothamMedium,
    TextSize = 10,
    TextColor3 = THEME.Sub,
}, welcome)
new("TextLabel", {
    Size = UDim2.new(1, -56, 0, 16),
    Position = UDim2.fromOffset(52, 27),
    BackgroundTransparency = 1,
    Text = shownName,
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextColor3 = THEME.Text,
    TextTruncate = Enum.TextTruncate.AtEnd,
}, welcome)

local pageHolder = new("Frame", {
    Name = "Pages",
    Size = UDim2.new(1, -RAIL_W, 1, -TOP_H),
    Position = UDim2.fromOffset(RAIL_W, TOP_H),
    BackgroundTransparency = 1,
}, window)

-- ============================================================
-- WIDGETS
-- ============================================================
local function makePage()
    local f = new("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = THEME.Stroke,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Visible = false,
    }, pageHolder)
    return { frame = f, x = PAD, y = 12, w = ROW_W }
end

local function flush(page)
    page.frame.CanvasSize = UDim2.fromOffset(0, page.y + 16)
end

local function addSection(page, label)
    local holder = new("Frame", {
        Size = UDim2.new(0, page.w, 0, 26),
        Position = UDim2.fromOffset(page.x, page.y + 4),
        BackgroundTransparency = 1,
    }, page.frame)
    new("Frame", {
        Size = UDim2.fromOffset(3, 12),
        Position = UDim2.fromOffset(0, 7),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
    }, holder)
    new("TextLabel", {
        Size = UDim2.new(1, -10, 1, 0),
        Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1,
        Text = string.upper(label),
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = THEME.Sub,
    }, holder)
    page.y = page.y + 30
end

local function rowBase(page, h)
    local row = new("Frame", {
        Size = UDim2.new(0, page.w, 0, h),
        Position = UDim2.fromOffset(page.x, page.y),
        BackgroundColor3 = THEME.Row,
        BorderSizePixel = 0,
    }, page.frame)
    new("UICorner", { CornerRadius = UDim.new(0, 6) }, row)
    page.y = page.y + h + 6
    return row
end

-- A callback that throws used to die inside a spawned thread: the switch moved,
-- the feature did nothing, and the hub took the blame in silence. Every widget
-- callback runs through here now, and a failure prints itself on screen.
local function runCb(label, cb, ...)
    if not cb then return end
    local ok, err = pcall(cb, ...)
    if not ok then
        local msg = tostring(err)
        warn("[Tupachup] " .. label .. ": " .. msg)
        pcall(notify, label .. ": " .. msg, "error", "Feature error")
    end
    return ok, err
end

local function addToggle(page, label, default, flag, cb)
    local row = rowBase(page, 32)
    new("TextLabel", {
        Size = UDim2.new(1, -60, 1, 0),
        Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1,
        Text = label,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = THEME.Text,
    }, row)

    local sw = new("Frame", {
        Size = UDim2.fromOffset(34, 18),
        Position = UDim2.new(1, -46, 0.5, -9),
        BackgroundColor3 = THEME.Stroke,
        BorderSizePixel = 0,
    }, row)
    new("UICorner", { CornerRadius = UDim.new(0, 9) }, sw)
    local knob = new("Frame", {
        Size = UDim2.fromOffset(14, 14),
        Position = UDim2.fromOffset(2, 2),
        BackgroundColor3 = THEME.Sub,
        BorderSizePixel = 0,
    }, sw)
    new("UICorner", { CornerRadius = UDim.new(0, 7) }, knob)

    local state = false

    local function render(v)
        TweenService:Create(knob, TweenInfo.new(0.14), {
            Position = UDim2.fromOffset(v and 18 or 2, 2),
            BackgroundColor3 = v and Color3.new(1, 1, 1) or THEME.Sub,
        }):Play()
        TweenService:Create(sw, TweenInfo.new(0.14), {
            BackgroundColor3 = v and THEME.Accent or THEME.Stroke,
        }):Play()
    end

    local function set(v, silent)
        state = v and true or false
        Flags[flag] = state
        render(state)
        if not silent and cb then task.spawn(runCb, label, cb, state) end
    end

    local hit = new("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
    }, row)
    hit.MouseButton1Click:Connect(function()
        set(not state, false)
    end)

    bind(flag, set)
    set(default, true)
    return set
end

local function addSlider(page, label, lo, hi, default, step, flag, cb, suffix)
    local row = rowBase(page, 46)
    local name = new("TextLabel", {
        Size = UDim2.new(1, -140, 0, 16),
        Position = UDim2.fromOffset(10, 7),
        BackgroundTransparency = 1,
        Text = label,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = THEME.Text,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, row)
    local valueLbl = new("TextLabel", {
        Size = UDim2.fromOffset(124, 16),
        Position = UDim2.new(1, -134, 0, 7),
        BackgroundTransparency = 1,
        Text = tostring(default) .. (suffix or ""),
        TextXAlignment = Enum.TextXAlignment.Right,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = THEME.Accent,
    }, row)

    local bar = new("Frame", {
        Size = UDim2.new(1, -20, 0, 5),
        Position = UDim2.fromOffset(10, 30),
        BackgroundColor3 = THEME.Stroke,
        BorderSizePixel = 0,
    }, row)
    new("UICorner", { CornerRadius = UDim.new(1, 0) }, bar)
    local fill = new("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
    }, bar)
    new("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
    local knob = new("Frame", {
        Size = UDim2.fromOffset(12, 12),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, bar)
    new("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

    -- a 5px frame is a hard target, and on a phone it is a miss. The whole bar
    -- band is a button now; the track and knob stay underneath it.
    local grab = new("TextButton", {
        Size = UDim2.new(1, -20, 0, 18),
        Position = UDim2.fromOffset(10, 22),
        BackgroundTransparency = 1,
        Text = "",
        ZIndex = 3,
    }, row)

    local value = default
    local dragging = false

    local function apply(v, silent)
        value = clamp(round(v, step), lo, hi)
        local alpha = (value - lo) / (hi - lo)
        fill.Size = UDim2.fromScale(alpha, 1)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        valueLbl.Text = tostring(value) .. (suffix or "")
        Flags[flag] = value
        if not silent and cb then task.spawn(runCb, label, cb, value) end
    end

    local function fromX(x)
        local alpha = (x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1)
        apply(lo + (hi - lo) * clamp(alpha, 0, 1), false)
    end

    track(grab.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            fromX(input.Position.X)
        end
    end))
    track(grab.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    track(UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            fromX(input.Position.X)
        end
    end))
    track(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))

    bind(flag, function(v) apply(v, false) end)
    apply(default, true)
    return apply
end

local function addButton(page, label, color, cb)
    local b = new("TextButton", {
        Size = UDim2.new(0, page.w, 0, 32),
        Position = UDim2.fromOffset(page.x, page.y),
        BackgroundColor3 = THEME.Row,
        BorderSizePixel = 0,
        Text = label,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = color or THEME.Text,
        AutoButtonColor = false,
    }, page.frame)
    new("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = THEME.Stroke }):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = THEME.Row }):Play()
    end)
    b.MouseButton1Click:Connect(function() runCb(label, cb) end)
    page.y = page.y + 38
    return b
end

-- ZapHub-style copy row: label left, copy glyph right, whole row clickable
local function addCopyRow(page, label, value, note)
    local row = rowBase(page, 32)
    local lbl = new("TextLabel", {
        Size = UDim2.new(1, -40, 1, 0),
        Position = UDim2.fromOffset(12, 0),
        BackgroundTransparency = 1,
        Text = label,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = THEME.Text,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, row)
    -- drawn icon, not a glyph: Gotham renders ⧉ as a tofu box
    local glyph = new("Frame", {
        Size = UDim2.fromOffset(9, 9),
        Position = UDim2.new(1, -22, 0.5, -4),
        BackgroundColor3 = THEME.Sub,
        BorderSizePixel = 0,
    }, row)
    new("UICorner", { CornerRadius = UDim.new(0, 2) }, glyph)
    local glyphCut = new("Frame", {
        Size = UDim2.fromOffset(9, 9),
        Position = UDim2.fromOffset(3, 3),
        BackgroundColor3 = THEME.Row,
        BorderSizePixel = 0,
    }, glyph)
    new("UICorner", { CornerRadius = UDim.new(0, 2) }, glyphCut)
    local hit = new("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
    }, row)
    hit.MouseEnter:Connect(function()
        TweenService:Create(row, TweenInfo.new(0.12), { BackgroundColor3 = THEME.Stroke }):Play()
        glyph.BackgroundColor3 = THEME.Accent
    end)
    hit.MouseLeave:Connect(function()
        TweenService:Create(row, TweenInfo.new(0.12), { BackgroundColor3 = THEME.Row }):Play()
        glyph.BackgroundColor3 = THEME.Sub
    end)
    hit.MouseButton1Click:Connect(function()
        copy(value)
        lbl.Text = (note or label) .. "  -  copied"
        task.delay(1.2, function()
            if lbl.Parent then lbl.Text = label end
        end)
    end)
    return row
end

local function addTextbox(page, label, placeholder, flag, cb)
    local row = rowBase(page, 34)
    new("TextLabel", {
        Size = UDim2.new(1, -180, 1, 0),
        Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1,
        Text = label,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = THEME.Text,
    }, row)
    local box = new("TextBox", {
        Size = UDim2.fromOffset(158, 24),
        Position = UDim2.new(1, -168, 0.5, -12),
        BackgroundColor3 = THEME.Panel,
        BorderSizePixel = 0,
        Text = "",
        PlaceholderText = placeholder or "",
        PlaceholderColor3 = THEME.Sub,
        ClearTextOnFocus = false,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = THEME.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    new("UICorner", { CornerRadius = UDim.new(0, 5) }, box)
    new("UIPadding", { PaddingLeft = UDim.new(0, 8) }, box)
    box.FocusLost:Connect(function()
        Flags[flag] = box.Text
        if cb then task.spawn(runCb, label, cb, box.Text) end
    end)
    bind(flag, function(v)
        -- programmatic sets (config load, quest arming) have to move the flag
        -- and the behaviour, not just the text in the box
        v = (v == nil) and "" or tostring(v)
        box.Text = v
        Flags[flag] = v
        if cb then task.spawn(runCb, label, cb, v) end
    end)
    return box
end

local function addKeybind(page, label, default, flag, cb)
    local row = rowBase(page, 32)
    new("TextLabel", {
        Size = UDim2.new(1, -120, 1, 0),
        Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1,
        Text = label,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = THEME.Text,
    }, row)
    local btn = new("TextButton", {
        Size = UDim2.fromOffset(96, 22),
        Position = UDim2.new(1, -106, 0.5, -11),
        BackgroundColor3 = THEME.Panel,
        BorderSizePixel = 0,
        Text = default.Name,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = THEME.Accent,
        AutoButtonColor = false,
    }, row)
    new("UICorner", { CornerRadius = UDim.new(0, 5) }, btn)

    local capturing = false
    btn.MouseButton1Click:Connect(function()
        capturing = true
        btn.Text = "press a key"
    end)
    track(UIS.InputBegan:Connect(function(input)
        if not capturing then return end
        if input.UserInputType == Enum.UserInputType.Keyboard then
            capturing = false
            btn.Text = input.KeyCode.Name
            Flags[flag] = input.KeyCode.Name
            if cb then task.spawn(runCb, label, cb, input.KeyCode) end
        end
    end))

    bind(flag, function(v)
        btn.Text = tostring(v)
        Flags[flag] = v
        local key = Enum.KeyCode[v]
        if key and cb then task.spawn(runCb, label, cb, key) end
    end)

    return btn
end

local function addDropdown(page, label, optionsFn, default, flag, cb)
    local row = rowBase(page, 32)
    new("TextLabel", {
        Size = UDim2.new(1, -150, 1, 0),
        Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1,
        Text = label,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = THEME.Text,
    }, row)
    local value = default
    local valueLbl = new("TextLabel", {
        Size = UDim2.fromOffset(120, 20),
        Position = UDim2.new(1, -132, 0.5, -10),
        BackgroundTransparency = 1,
        Text = tostring(value) .. "  v",
        TextXAlignment = Enum.TextXAlignment.Right,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = THEME.Accent,
    }, row)

    local hit = new("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
    }, row)

    hit.MouseButton1Click:Connect(function()
        local opts = optionsFn and optionsFn() or {}
        if #opts == 0 then
            notify("No options available", "error")
            return
        end

        local blocker = new("TextButton", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            ZIndex = 40,
        }, window)

        local visible = math.min(#opts, 6)
        local pop = new("Frame", {
            Size = UDim2.fromOffset(180, visible * 26 + 8),
            Position = UDim2.fromOffset(
                row.AbsolutePosition.X - window.AbsolutePosition.X + row.AbsoluteSize.X - 180,
                row.AbsolutePosition.Y - window.AbsolutePosition.Y + row.AbsoluteSize.Y + 4
            ),
            BackgroundColor3 = THEME.Panel,
            BorderSizePixel = 0,
            ZIndex = 41,
            ClipsDescendants = true,
        }, window)
        new("UICorner", { CornerRadius = UDim.new(0, 7) }, pop)
        new("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, pop)

        local list = new("ScrollingFrame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            CanvasSize = UDim2.fromOffset(0, #opts * 26),
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = THEME.Stroke,
            ZIndex = 41,
        }, pop)

        local function close()
            blocker:Destroy()
            pop:Destroy()
        end
        blocker.MouseButton1Click:Connect(close)

        for i, opt in ipairs(opts) do
            local o = new("TextButton", {
                Size = UDim2.new(1, 0, 0, 26),
                Position = UDim2.fromOffset(0, (i - 1) * 26),
                BackgroundTransparency = 1,
                Text = "  " .. tostring(opt),
                TextXAlignment = Enum.TextXAlignment.Left,
                Font = Enum.Font.GothamMedium,
                TextSize = 12,
                TextColor3 = THEME.Text,
                ZIndex = 42,
                AutoButtonColor = false,
            }, list)
            o.MouseEnter:Connect(function()
                o.BackgroundTransparency = 0.85
                o.BackgroundColor3 = THEME.Accent
            end)
            o.MouseLeave:Connect(function()
                o.BackgroundTransparency = 1
            end)
            o.MouseButton1Click:Connect(function()
                value = opt
                valueLbl.Text = tostring(opt) .. "  v"
                Flags[flag] = opt
                close()
                if cb then task.spawn(runCb, label, cb, opt) end
            end)
        end
    end)

    bind(flag, function(v)
        value = v
        valueLbl.Text = tostring(v) .. "  v"
        Flags[flag] = v
        if cb then task.spawn(runCb, label, cb, v) end
    end)
    Flags[flag] = value
    return valueLbl
end

-- multi-select list: summary on the right, checkbox popup on tap
local function addMultiSelect(page, label, options, default, flag, cb)
    local row = rowBase(page, 32)
    new("TextLabel", {
        Size = UDim2.new(1, -150, 1, 0),
        Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1,
        Text = label,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = THEME.Text,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, row)

    local picked = {}
    for _, v in ipairs(default or {}) do picked[v] = true end

    local valueLbl = new("TextLabel", {
        Size = UDim2.fromOffset(120, 20),
        Position = UDim2.new(1, -132, 0.5, -10),
        BackgroundTransparency = 1,
        Text = "Select options  v",
        TextXAlignment = Enum.TextXAlignment.Right,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = THEME.Sub,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, row)

    local function summary()
        local count, first = 0, nil
        for _, opt in ipairs(options) do
            if picked[opt] then
                count = count + 1
                first = first or opt
            end
        end
        if count == 0 then
            valueLbl.Text = "Select options  v"
            valueLbl.TextColor3 = THEME.Sub
        elseif count == 1 then
            valueLbl.Text = first .. "  v"
            valueLbl.TextColor3 = THEME.Accent
        else
            valueLbl.Text = count .. " selected  v"
            valueLbl.TextColor3 = THEME.Accent
        end
    end

    local function commit()
        local out = {}
        for _, opt in ipairs(options) do
            if picked[opt] then out[#out + 1] = opt end
        end
        Flags[flag] = out
        summary()
        if cb then task.spawn(runCb, label, cb, out) end
    end

    summary()

    local hit = new("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
    }, row)

    hit.MouseButton1Click:Connect(function()
        local blocker = new("TextButton", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            ZIndex = 40,
        }, window)

        local visible = math.min(#options, 6)
        local pop = new("Frame", {
            Size = UDim2.fromOffset(200, visible * 26 + 8),
            Position = UDim2.fromOffset(
                row.AbsolutePosition.X - window.AbsolutePosition.X + row.AbsoluteSize.X - 200,
                row.AbsolutePosition.Y - window.AbsolutePosition.Y + row.AbsoluteSize.Y + 4
            ),
            BackgroundColor3 = THEME.Panel,
            BorderSizePixel = 0,
            ZIndex = 41,
            ClipsDescendants = true,
        }, window)
        new("UICorner", { CornerRadius = UDim.new(0, 7) }, pop)
        new("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, pop)

        local list = new("ScrollingFrame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            CanvasSize = UDim2.fromOffset(0, #options * 26),
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = THEME.Stroke,
            ZIndex = 41,
        }, pop)

        local function close()
            blocker:Destroy()
            pop:Destroy()
        end
        blocker.MouseButton1Click:Connect(close)

        for i, opt in ipairs(options) do
            local o = new("TextButton", {
                Size = UDim2.new(1, 0, 0, 26),
                Position = UDim2.fromOffset(0, (i - 1) * 26),
                BackgroundTransparency = 1,
                Text = (picked[opt] and "  [x] " or "  [ ] ") .. tostring(opt),
                TextXAlignment = Enum.TextXAlignment.Left,
                Font = Enum.Font.GothamMedium,
                TextSize = 12,
                TextColor3 = picked[opt] and THEME.Text or THEME.Sub,
                ZIndex = 42,
                AutoButtonColor = false,
            }, list)
            o.MouseEnter:Connect(function()
                o.BackgroundTransparency = 0.85
                o.BackgroundColor3 = THEME.Accent
            end)
            o.MouseLeave:Connect(function()
                o.BackgroundTransparency = 1
            end)
            o.MouseButton1Click:Connect(function()
                picked[opt] = not picked[opt] or nil
                o.Text = (picked[opt] and "  [x] " or "  [ ] ") .. tostring(opt)
                o.TextColor3 = picked[opt] and THEME.Text or THEME.Sub
                commit()
            end)
        end
    end)

    bind(flag, function(v)
        if type(v) ~= "table" then return end
        picked = {}
        for _, item in ipairs(v) do picked[item] = true end
        commit()
    end)

    commit()
    return valueLbl
end

local function addNote(page, text, color)
    local l = new("TextLabel", {
        Size = UDim2.new(0, page.w, 0, 30),
        Position = UDim2.fromOffset(page.x, page.y),
        BackgroundTransparency = 1,
        Text = text,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium,
        TextSize = 11,
        TextColor3 = color or THEME.Sub,
    }, page.frame)
    page.y = page.y + 34
    return l
end

local function addPanel(page, height)    local p = new("ScrollingFrame", {
        Size = UDim2.new(0, page.w, 0, height),
        Position = UDim2.fromOffset(page.x, page.y),
        BackgroundColor3 = THEME.Panel,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = THEME.Stroke,
    }, page.frame)
    new("UICorner", { CornerRadius = UDim.new(0, 6) }, p)
    page.y = page.y + height + 8
    return p
end

-- ============================================================
-- FEATURES
-- ============================================================
local Features = {}

-- walk speed / jump power
local baseWalk, baseJump = 16, 50
local baseFov = CAM and CAM.FieldOfView or 70
do
    local c, hum = char()
    if hum then
        baseWalk = hum.WalkSpeed
        baseJump = hum.JumpPower
    end
end

Features.setWalk = function(v)
    local _, hum = char()
    if hum then hum.WalkSpeed = v end
end

Features.setJump = function(v)
    local _, hum = char()
    if hum then
        hum.UseJumpPower = true
        hum.JumpPower = v
    end
end

Features.reset = function()
    local _, hum = char()
    if hum then hum.Health = 0 end
end

-- infinite jump
local infJumpOn = false
track(UIS.JumpRequest:Connect(function()
    if not infJumpOn then return end
    local _, hum = char()
    if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end))

Features.infJump = function(on)
    infJumpOn = on
end

-- noclip
local noclipOn = false
local noclipConn
Stops.Noclip = function()
    noclipOn = false
    if noclipConn then noclipConn:Disconnect() noclipConn = nil end
end
Features.noclip = function(on)
    noclipOn = on
    if on and not noclipConn then
        noclipConn = RunService.Stepped:Connect(function()
            if not noclipOn then return end
            local c = LP.Character
            if not c then return end
            for _, part in ipairs(c:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end)
    elseif not on then
        Stops.Noclip()
    end
end

-- anti-afk
local antiAfkConn
Features.antiAfk = function(on)
    if antiAfkConn then antiAfkConn:Disconnect() antiAfkConn = nil end
    if not on then return end
    antiAfkConn = LP.Idled:Connect(function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)
    notify("Anti-AFK armed", "success")
end

-- fly
local fly = { active = false, bv = nil, bg = nil, conn = nil, speed = 50 }

local function flyStop()
    fly.active = false
    if fly.conn then fly.conn:Disconnect() fly.conn = nil end
    if fly.bv then fly.bv:Destroy() fly.bv = nil end
    if fly.bg then fly.bg:Destroy() fly.bg = nil end
    local _, hum = char()
    if hum then hum.PlatformStand = false end
end
Stops.Fly = flyStop

local function flyStart()
    local c, hum = char()
    local hrp = c and c:FindFirstChild("HumanoidRootPart")
    if not (hrp and hum) then
        notify("No character to fly", "error")
        return
    end
    flyStop()
    fly.active = true
    hum.PlatformStand = true

    local bv = new("BodyVelocity", { MaxForce = Vector3.new(1e5, 1e5, 1e5), Velocity = Vector3.zero }, hrp)
    local bg = new("BodyGyro", { MaxTorque = Vector3.new(1e5, 1e5, 1e5), P = 2500, D = 120, CFrame = hrp.CFrame }, hrp)
    fly.bv, fly.bg = bv, bg

    fly.conn = RunService.RenderStepped:Connect(function()
        if not hrp.Parent or not hum.Parent then
            flyStop()
            return
        end
        local cam = workspace.CurrentCamera
        local dir = Vector3.zero
        if UIS:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.CFrame.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.CFrame.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
        if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3.new(0, 1, 0) end

        if dir.Magnitude > 0 then
            bv.Velocity = dir.Unit * fly.speed
        else
            bv.Velocity = Vector3.zero
        end
        bg.CFrame = CFrame.new(hrp.Position) * (cam.CFrame - cam.CFrame.Position)
    end)
end

Features.fly = function(on)
    if on then flyStart() else flyStop() end
end
Features.flySpeed = function(v)
    fly.speed = v
end

-- anti void
local voidOn = false
local voidConn
local safePos = nil
Features.antiVoid = function(on)
    voidOn = on
    if voidConn then voidConn:Disconnect() voidConn = nil end
    if not on then return end
    voidConn = RunService.Heartbeat:Connect(function()
        if not voidOn then return end
        local c, hum = char()
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        if hum and hum.FloorMaterial ~= Enum.Material.Air then
            safePos = hrp.Position
        end
        if hrp.Position.Y < -60 and safePos then
            hrp.CFrame = CFrame.new(safePos + Vector3.new(0, 6, 0))
        end
    end)
end

-- esp
local esp = { on = false, names = false, hi = {}, bb = {}, conn = nil }

local function espClear()
    for plr, inst in pairs(esp.hi) do
        if inst then inst:Destroy() end
        esp.hi[plr] = nil
    end
    for plr, inst in pairs(esp.bb) do
        if inst then inst:Destroy() end
        esp.bb[plr] = nil
    end
end

local function espTick()
    if not esp.on then
        if next(esp.hi) or next(esp.bb) then espClear() end
        return
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            local c = plr.Character
            local hrp = c and c:FindFirstChild("HumanoidRootPart")
            local head = c and c:FindFirstChild("Head")
            local hum = c and c:FindFirstChildOfClass("Humanoid")

            if hrp and not esp.hi[plr] then
                esp.hi[plr] = new("Highlight", {
                    FillColor = THEME.Accent,
                    FillTransparency = 0.78,
                    OutlineColor = THEME.Accent,
                    OutlineTransparency = 0.25,
                    DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                    Adornee = c,
                }, c)
            elseif not hrp and esp.hi[plr] then
                esp.hi[plr]:Destroy()
                esp.hi[plr] = nil
            end

            if esp.names and head and not esp.bb[plr] then
                local bb = new("BillboardGui", {
                    Size = UDim2.fromOffset(130, 40),
                    StudsOffset = Vector3.new(0, 2.4, 0),
                    AlwaysOnTop = true,
                    Adornee = head,
                }, head)
                new("TextLabel", {
                    Size = UDim2.new(1, 0, 0, 16),
                    BackgroundTransparency = 1,
                    Text = plr.Name,
                    Font = Enum.Font.GothamBold,
                    TextSize = 12,
                    TextColor3 = THEME.Text,
                    TextStrokeTransparency = 0.4,
                }, bb)
                local barBg = new("Frame", {
                    Size = UDim2.new(1, -20, 0, 5),
                    Position = UDim2.fromOffset(10, 18),
                    BackgroundColor3 = THEME.Bg,
                    BorderSizePixel = 0,
                }, bb)
                new("UICorner", { CornerRadius = UDim.new(1, 0) }, barBg)
                local bar = new("Frame", {
                    Size = UDim2.fromScale(1, 1),
                    BackgroundColor3 = THEME.Green,
                    BorderSizePixel = 0,
                }, barBg)
                new("UICorner", { CornerRadius = UDim.new(1, 0) }, bar)
                bb:SetAttribute("Bar", true)
                esp.bb[plr] = bb
            elseif (not esp.names) and esp.bb[plr] then
                esp.bb[plr]:Destroy()
                esp.bb[plr] = nil
            end

            if esp.bb[plr] and hum then
                local barBg = nil
                for _, child in ipairs(esp.bb[plr]:GetChildren()) do
                    if child:IsA("Frame") then barBg = child break end
                end
                if barBg then
                    local fill = barBg:FindFirstChildOfClass("Frame")
                    if fill then
                        local ratio = clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                        fill.Size = UDim2.fromScale(ratio, 1)
                        fill.BackgroundColor3 = THEME.Green:Lerp(THEME.Red, 1 - ratio)
                    end
                end
            end
        end
    end
    for plr, inst in pairs(esp.hi) do
        if not plr.Parent or not plr.Character then
            inst:Destroy()
            esp.hi[plr] = nil
        end
    end
    for plr, inst in pairs(esp.bb) do
        if not plr.Parent or not plr.Character then
            inst:Destroy()
            esp.bb[plr] = nil
        end
    end
end

Features.esp = function(on)
    esp.on = on
    if not on then espClear() end
end
Features.espNames = function(on)
    esp.names = on
    if not on then
        for plr, inst in pairs(esp.bb) do
            inst:Destroy()
            esp.bb[plr] = nil
        end
    end
end
Stops.Esp = function() esp.on = false espClear() end

local espAccum = 0
track(RunService.Heartbeat:Connect(function(dt)
    espAccum = espAccum + (dt or 0)
    if espAccum < 0.4 then return end
    espAccum = 0
    if esp.on then pcall(espTick) end
end))

-- lighting
local lightingBackup = nil
Features.fullbright = function(on)
    if on then
        if not lightingBackup then
            lightingBackup = {
                Ambient = Lighting.Ambient,
                OutdoorAmbient = Lighting.OutdoorAmbient,
                Brightness = Lighting.Brightness,
                ClockTime = Lighting.ClockTime,
                FogEnd = Lighting.FogEnd,
            }
        end
        Lighting.Ambient = Color3.fromRGB(190, 190, 190)
        Lighting.OutdoorAmbient = Color3.fromRGB(190, 190, 190)
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.FogEnd = 1e5
    elseif lightingBackup then
        Lighting.Ambient = lightingBackup.Ambient
        Lighting.OutdoorAmbient = lightingBackup.OutdoorAmbient
        Lighting.Brightness = lightingBackup.Brightness
        Lighting.ClockTime = lightingBackup.ClockTime
        Lighting.FogEnd = lightingBackup.FogEnd
        lightingBackup = nil
    end
end
Stops.Lighting = function() Features.fullbright(false) end

Features.fov = function(v)
    local cam = workspace.CurrentCamera
    if cam then cam.FieldOfView = v end
end

-- performance
local gfxBackup = nil
Features.lowGraphics = function(on)
    if on then
        if not gfxBackup then
            local effects = {}
            for _, inst in ipairs(Lighting:GetDescendants()) do
                if inst:IsA("PostEffect") then
                    effects[#effects + 1] = { inst = inst, enabled = inst.Enabled }
                end
            end
            local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
            gfxBackup = {
                effects = effects,
                shadows = Lighting.GlobalShadows,
                atmo    = atmo,
                density = atmo and atmo.Density or nil,
                water   = workspace.Terrain and workspace.Terrain.WaterWaveSize or nil,
            }
        end
        for _, e in ipairs(gfxBackup.effects) do
            if e.inst.Parent then e.inst.Enabled = false end
        end
        Lighting.GlobalShadows = false
        if gfxBackup.atmo and gfxBackup.atmo.Parent then gfxBackup.atmo.Density = 0 end
        if workspace.Terrain then
            workspace.Terrain.WaterWaveSize = 0
            workspace.Terrain.WaterWaveSpeed = 0
        end
    elseif gfxBackup then
        for _, e in ipairs(gfxBackup.effects) do
            if e.inst.Parent then e.inst.Enabled = e.enabled end
        end
        Lighting.GlobalShadows = gfxBackup.shadows
        if gfxBackup.atmo and gfxBackup.atmo.Parent and gfxBackup.density then
            gfxBackup.atmo.Density = gfxBackup.density
        end
        if workspace.Terrain and gfxBackup.water then
            workspace.Terrain.WaterWaveSize = gfxBackup.water
        end
        gfxBackup = nil
    end
end
Stops.Graphics = function() Features.lowGraphics(false) end

Features.fpsCap = function(v)
    if not CAP.fpsCap then
        notify("setfpscap is not on this executor", "error")
        return
    end
    pcall(setfpscap, v)
end

-- webhook
local function postJson(url, body)
    local opts = {
        Url = url,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = body,
    }
    local ok, res
    if type(request) == "function" then
        ok, res = pcall(request, opts)
    elseif type(http_request) == "function" then
        ok, res = pcall(http_request, opts)
    elseif type(syn) == "table" and type(syn.request) == "function" then
        ok, res = pcall(syn.request, opts)
    else
        return false, "no http request function"
    end
    if not ok then return false, tostring(res) end
    return true, res
end

Features.webhookTest = function(url)
    if type(url) ~= "string" or url == "" then
        notify("Paste a webhook URL first", "error")
        return
    end
    if not CAP.request then
        notify("request() missing on this executor", "error")
        return
    end
    local payload = HttpService:JSONEncode({
        content = BRAND .. " v" .. VERSION .. " | test message",
        username = BRAND,
    })
    local ok, res = postJson(url, payload)
    if ok then
        notify("Webhook delivered", "success")
    else
        notify("Webhook failed: " .. tostring(res):sub(1, 60), "error")
    end
end

-- ============================================================
-- RENDER FILTERS  (client-side hide, fully restorable)
-- ============================================================
local Render = {
    hidden = {},
    rules = {
        { flag = "noBreakables", words = { "breakable" } },
        { flag = "noPets",       words = { "pet" } },
        { flag = "noConfetti",   words = { "confetti" } },
        { flag = "noLootbox",    words = { "lootbox", "loot box" } },
        { flag = "noEggFx",      words = { "exclusive egg", "egg animation" } },
    },
}

-- one scan pass is capped: a corrupt or gigantic workspace is skipped, never hung
local SCAN_CAP = 12000

local function hideNode(inst, depth)
    if depth > 4 or Render.hidden[inst] ~= nil then return end
    if inst:IsA("Model") or inst:IsA("Folder") then
        if inst:FindFirstChildOfClass("Humanoid") then return end
        Render.hidden[inst] = false
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("BasePart") then
                Render.hidden[d] = d.LocalTransparencyModifier or 0
                d.LocalTransparencyModifier = 1
            elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail")
                or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then
                Render.hidden[d] = d.Enabled
                d.Enabled = false
            end
        end
    elseif inst:IsA("BasePart") then
        Render.hidden[inst] = inst.LocalTransparencyModifier or 0
        inst.LocalTransparencyModifier = 1
    elseif inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail")
        or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles") then
        Render.hidden[inst] = inst.Enabled
        inst.Enabled = false
    end
end

local function restoreRender()
    for inst, prev in pairs(Render.hidden) do
        if inst.Parent then
            if inst:IsA("BasePart") then
                inst.LocalTransparencyModifier = prev or 0
            elseif prev ~= false then
                pcall(function() inst.Enabled = prev end)
            end
        end
    end
    Render.hidden = {}
end

local function activeRules()
    local out = {}
    for _, r in ipairs(Render.rules) do
        if Flags[r.flag] then out[#out + 1] = r end
    end
    return out
end

function Render.scan()
    local active = activeRules()
    if #active == 0 then return end

    local myChar = LP.Character
    local stack = { workspace }
    local seen = 0

    while #stack > 0 and seen < SCAN_CAP do
        local node = table.remove(stack)
        for _, child in ipairs(node:GetChildren()) do
            seen = seen + 1
            if seen > SCAN_CAP then break end
            if child ~= myChar and child ~= workspace.CurrentCamera
                and not child:IsA("Terrain") and not child:IsA("Camera") then
                local lower = string.lower(child.Name)
                local hit = false
                for _, r in ipairs(active) do
                    for _, w in ipairs(r.words) do
                        if string.find(lower, w, 1, true) then hit = true break end
                    end
                    if hit then break end
                end
                if hit then
                    hideNode(child, 0)
                elseif child:IsA("Folder") or child:IsA("Model") then
                    stack[#stack + 1] = child
                end
            end
        end
    end
end

Features.renderFilter = function(on)
    if not on then restoreRender() end
    pcall(Render.scan)
end

Stops.Render = restoreRender

-- pets, confetti and egg effects respawn: rescan on a slow tick while any rule is on
do
    local acc = 0
    track(RunService.Heartbeat:Connect(function(dt)
        if #activeRules() == 0 then return end
        acc = acc + dt
        if acc < 1.5 then return end
        acc = 0
        pcall(Render.scan)
    end))
end

-- ============================================================
-- PSX CLASSIC
-- ============================================================
-- Pet Simulator X Classic is reached through the game's own UI. Nothing here
-- guesses a remote: it finds the on-screen button by label and fires its click.
local PSX = {
    goals = {},
    -- FILL: drop the PSX Classic PlaceId here if you want a hard teleport
    -- fallback. 0 = only the in-game button is used.
    placeId = 0,
    goalWords = {
        Rewards = { "classic reward", "rewards" },
        Index   = { "classic index", "index" },
        Daily   = { "daily reward", "daily" },
        Quests  = { "quest", "goal" },
        Eggs    = { "egg" },
        Bank    = { "bank" },
    },
}

local GUI_SCAN_CAP = 4000

-- Games rarely put the words on the button itself. A shop row is an ImageButton
-- with a TextLabel child, a pad is a Part with a SurfaceGui. Reading only
-- `inst.Text` is why the engine used to match nothing at all: the switch lit up
-- and no click ever fired. labelOf() walks the button's own children (bounded)
-- so the words on the sticker are part of the haystack.
local LABEL_DEPTH_CAP = 8

local function labelOf(inst)
    local parts = { string.lower(inst.Name) }
    local ownText = inst:IsA("GuiObject") and inst.Text or nil
    if ownText and ownText ~= "" then parts[#parts + 1] = string.lower(ownText) end

    local walked = 0
    for _, child in ipairs(inst:GetDescendants()) do
        walked = walked + 1
        if walked > LABEL_DEPTH_CAP then break end
        if child:IsA("GuiObject") then
            local okT, t = pcall(function() return child.Text end)
            if okT and type(t) == "string" and t ~= "" then
                parts[#parts + 1] = string.lower(t)
            end
            if child.Name and child.Name ~= "" then
                parts[#parts + 1] = string.lower(child.Name)
            end
        end
    end
    return table.concat(parts, " ")
end

-- The hub's own window sits in PlayerGui as well. Walking it burns the scan
-- budget and can push the game's real buttons past the cap, so every scan
-- starts from PlayerGui children and skips our ScreenGui.
local function eachGameGui(fn)
    local seen = 0
    for _, root in ipairs(PG:GetChildren()) do
        if root ~= gui then
            seen = seen + 1
            if seen > GUI_SCAN_CAP then return end
            if fn(root) == false then return end
            for _, inst in ipairs(root:GetDescendants()) do
                seen = seen + 1
                if seen > GUI_SCAN_CAP then return end
                if fn(inst) == false then return end
            end
        end
    end
end

local function isShown(inst)
    local node = inst
    while node and node ~= PG do
        if node == gui then return false end
        if node:IsA("GuiObject") and node.Visible == false then return false end
        -- a disabled ScreenGui still reports Visible = true on its children
        if node:IsA("LayerCollector") and node.Enabled == false then return false end
        node = node.Parent
    end
    return true
end

-- ============================================================
-- SELF TEST  (the report killywilly sends back when a switch does nothing)
-- ============================================================
-- Everything here is read-only: no remote is fired, no part is moved. It
-- answers the four questions that decide whether the hub can work at all -
-- does the executor expose a click API, is the character loaded, can we see
-- the game's GUI, and does a word match actually land on a button.
local function selfTestReport()
    local L = {}
    local function add(s) L[#L + 1] = s end

    add("Tupachup " .. VERSION)
    add("game: " .. tostring(game.Name) .. "  (" .. tostring(game.PlaceId) .. ")")
    add("detected: " .. tostring(DETECTED_NAME))

    local exec = "unknown"
    if type(identifyexecutor) == "function" then
        local ok, a, b = pcall(identifyexecutor)
        if ok then exec = tostring(b or a) end
    elseif type(getexecutorname) == "function" then
        local ok, a = pcall(getexecutorname)
        if ok then exec = tostring(a) end
    end
    add("executor: " .. exec)

    local keys = {}
    for name, present in pairs(CAP) do
        if present then keys[#keys + 1] = name end
    end
    table.sort(keys)
    add("apis: " .. (#keys > 0 and table.concat(keys, ",") or "none"))

    local c, hum = char()
    local hrp = root()
    add("character: " .. (c and tostring(c.Name) or "nil")
        .. "  humanoid: " .. (hum and "yes" or "no")
        .. "  root: " .. (hrp and "yes" or "no"))
    if hum then
        add("walkspeed: " .. tostring(hum.WalkSpeed) .. "  health: " .. tostring(hum.Health))
    end

    add("ui parent: " .. (gui.Parent and gui.Parent:GetFullName() or "nil")
        .. "  visible: " .. tostring(gui.Enabled))
    add("playerGui children: " .. tostring(#PG:GetChildren()))

    -- what the engine can actually see in the game
    local buttons, labels = 0, {}
    eachGameGui(function(inst)
        if inst:IsA("GuiButton") and isShown(inst) then
            buttons = buttons + 1
            if #labels < 10 then
                local hay = labelOf(inst)
                if #hay > 0 then labels[#labels + 1] = hay:sub(1, 24) end
            end
        end
    end)
    add("game buttons visible: " .. tostring(buttons))
    if #labels > 0 then add("sample: " .. table.concat(labels, " | ")) end

    -- does a word match actually land on a button right now (same haystack the
    -- auto engine uses, inlined so this file's locals stay in declaration order)
    local PROBE_WORDS = { "claim", "collect", "gift", "reward", "tap", "egg" }
    local probe
    eachGameGui(function(inst)
        if inst:IsA("GuiButton") and isShown(inst) then
            local hay = labelOf(inst)
            for _, w in ipairs(PROBE_WORDS) do
                if string.find(hay, w, 1, true) then
                    probe = inst
                    return false
                end
            end
        end
        return nil
    end)
    add("claim probe: " .. (probe and ("HIT " .. tostring(probe.Name)) or "no match"))

    local ws = 0
    local okW, parts = pcall(function() return #workspace:GetDescendants() end)
    if okW then ws = parts or 0 end
    add("workspace instances: " .. tostring(ws))

    return table.concat(L, "\n")
end

function PSX.findButton(words)
    local hit
    eachGameGui(function(inst)
        if inst:IsA("GuiButton") and isShown(inst) then
            local hay = labelOf(inst)
            for _, w in ipairs(words) do
                if string.find(hay, w, 1, true) then
                    hit = inst
                    return false
                end
            end
        end
        return nil
    end)
    return hit
end

-- Three roads to a click, cheapest first. Some executors ship firesignal,
-- some only ship fireclickdetector, some ship neither — the virtual-mouse
-- fallback is the one that works on a barebones level-3 executor.
function PSX.click(btn)
    if not btn then return false end
    -- a TextLabel has no MouseButton1Click; indexing one throws before pcall
    -- even runs, which is how a label used to kill the whole quest cycle
    if not btn:IsA("GuiButton") then return false end

    if CAP.firesignal then
        local ok = pcall(function() firesignal(btn.MouseButton1Click) end)
        if not ok then pcall(function() firesignal(btn.Activated) end) end
        return true
    end

    if CAP.clickDet then
        local cd = btn:FindFirstChildWhichIsA("ClickDetector", true)
        if cd then
            local ok = pcall(fireclickdetector, cd)
            if ok then return true end
        end
    end

    if CAP.mouse then
        local ap, as = btn.AbsolutePosition, btn.AbsoluteSize
        local cx = ap.X + as.X * 0.5
        local cy = ap.Y + as.Y * 0.5
        local ok = pcall(function()
            VirtualUser:Button1Down(Vector2.new(cx, cy))
            task.wait(0.03)
            VirtualUser:Button1Up(Vector2.new(cx, cy))
        end)
        if ok then return true end
    end

    notify("No click API on this executor (firesignal / fireclickdetector / mouse1click)", "error")
    return false
end

function PSX.join()
    local btn = PSX.findButton({ "psx classic", "psx", "classic" })
    if btn and PSX.click(btn) then
        notify("PSX Classic: fired " .. btn.Name, "success")
        return true
    end
    if PSX.placeId and PSX.placeId > 0 then
        local ok = pcall(function()
            TeleportService:Teleport(PSX.placeId, LP)
        end)
        if ok then
            notify("PSX Classic: teleporting", "success")
            return true
        end
    end
    notify("PSX Classic button not on screen - open the PSX menu first", "error")
    return false
end

function PSX.openGoal(name)
    local words = PSX.goalWords[name] or { string.lower(name) }
    local btn = PSX.findButton(words)
    if btn then
        PSX.click(btn)
        return true
    end
    notify("No button matched: " .. tostring(name), "error")
    return false
end

Features.psxJoin = function() return PSX.join() end
Features.psxGoal = function(name) return PSX.openGoal(name) end

-- auto join runs once per execution, three seconds after load
Features.psxAutoJoin = function(on)
    if not on then return end
    task.delay(3, function()
        if Flags.psxAutoJoin then pcall(PSX.join) end
    end)
end

-- auto complete: fire each selected goal button on a slow tick
local psxAcc = 0
track(RunService.Heartbeat:Connect(function(dt)
    if not Flags.psxAutoGoals then return end
    local goals = Flags.psxGoals
    if type(goals) ~= "table" or #goals == 0 then return end
    psxAcc = psxAcc + dt
    if psxAcc < 3 then return end
    psxAcc = 0
    for _, goal in ipairs(goals) do
        pcall(PSX.openGoal, goal)
    end
end))

Stops.Psx = function() Flags.psxAutoGoals = false end

-- waypoints
local CFG_DIR = "Tupachup"
local WP_FILE = CFG_DIR .. "/waypoints.json"
local waypoints = {}
local waypointPanel
local renderWaypoints

local function ensureDir()
    if isfolder and makefolder then
        if not isfolder(CFG_DIR) then
            pcall(makefolder, CFG_DIR)
        end
    end
end

local function saveWaypoints()
    ensureDir()
    if not writefile then return end
    pcall(writefile, WP_FILE, HttpService:JSONEncode(waypoints))
end

local function loadWaypoints()
    if not (readfile and isfile) then return end
    if not isfile(WP_FILE) then return end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(WP_FILE))
    end)
    if ok and type(data) == "table" then
        waypoints = data
    end
end

renderWaypoints = function()
    if not waypointPanel then return end
    for _, child in ipairs(waypointPanel:GetChildren()) do
        if child:IsA("TextButton") or child:IsA("TextLabel") then
            child:Destroy()
        end
    end
    if #waypoints == 0 then
        waypointPanel.CanvasSize = UDim2.fromOffset(0, 26)
        new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 26),
            BackgroundTransparency = 1,
            Text = "   no waypoints saved",
            TextXAlignment = Enum.TextXAlignment.Left,
            Font = Enum.Font.GothamMedium,
            TextSize = 11,
            TextColor3 = THEME.Sub,
        }, waypointPanel)
        return
    end
    for i, wp in ipairs(waypoints) do
        local b = new("TextButton", {
            Size = UDim2.new(1, -8, 0, 26),
            Position = UDim2.fromOffset(4, (i - 1) * 27),
            BackgroundTransparency = 1,
            Text = "  " .. tostring(wp.name),
            TextXAlignment = Enum.TextXAlignment.Left,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            TextColor3 = THEME.Text,
            AutoButtonColor = false,
        }, waypointPanel)
        b.MouseEnter:Connect(function() b.BackgroundTransparency = 0.9 b.BackgroundColor3 = THEME.Accent end)
        b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end)
        b.MouseButton1Click:Connect(function()
            local hrp = root()
            if hrp then
                hrp.CFrame = CFrame.new(Vector3.new(wp.x, wp.y, wp.z) + Vector3.new(0, 3, 0))
                notify("Teleported: " .. tostring(wp.name), "success")
            end
        end)
        local del = new("TextButton", {
            Size = UDim2.fromOffset(22, 22),
            Position = UDim2.new(1, -26, 0.5, -11),
            BackgroundTransparency = 1,
            Text = "x",
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            TextColor3 = THEME.Red,
            AutoButtonColor = false,
        }, b)
        del.MouseButton1Click:Connect(function()
            table.remove(waypoints, i)
            saveWaypoints()
            renderWaypoints()
        end)
    end
    waypointPanel.CanvasSize = UDim2.fromOffset(0, #waypoints * 27 + 6)
end

local function addWaypoint(name)
    local hrp = root()
    if not hrp then
        notify("No character", "error")
        return
    end
    if name == "" then
        notify("Give the waypoint a name", "error")
        return
    end
    table.insert(waypoints, { name = name, x = hrp.Position.X, y = hrp.Position.Y, z = hrp.Position.Z })
    saveWaypoints()
    renderWaypoints()
    notify("Saved: " .. name, "success")
end

-- teleport
Features.tpMouse = function()
    local hrp = root()
    local mouse = LP:GetMouse()
    if hrp and mouse.Hit then
        hrp.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0, 3, 0))
        notify("Teleported to cursor", "success")
    end
end

Features.tpPlayer = function(name)
    local target = Players:FindFirstChild(name)
    if not target then
        notify("Player not found", "error")
        return
    end
    local theirHrp = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    local myHrp = root()
    if theirHrp and myHrp then
        myHrp.CFrame = theirHrp.CFrame + Vector3.new(0, 0, 3)
        notify("Teleported to " .. name, "success")
    else
        notify("Target has no character", "error")
    end
end

local function playerNames()
    local out = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then table.insert(out, plr.Name) end
    end
    return out
end

-- server
Features.rejoin = function()
    notify("Rejoining...", "info")
    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
end

Features.hop = function()
    local url = string.format(
        "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100",
        game.PlaceId
    )
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(url))
    end)
    if not ok or type(decoded) ~= "table" or not decoded.data then
        notify("Server list failed", "error")
        return
    end
    local pick = nil
    for _, srv in ipairs(decoded.data) do
        if srv.id ~= game.JobId and srv.playing < srv.maxPlayers then
            pick = srv
            break
        end
    end
    if not pick then
        notify("No open server found", "error")
        return
    end
    notify("Hopping to " .. tostring(pick.playing) .. "/" .. tostring(pick.maxPlayers), "info")
    TeleportService:TeleportToPlaceInstance(game.PlaceId, pick.id, LP)
end

Features.joinJob = function(jobId)
    if not jobId or jobId == "" then
        notify("Paste a JobId first", "error")
        return
    end
    notify("Joining instance...", "info")
    TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, LP)
end

Features.copyJob = function()
    if copy(game.JobId) then
        notify("JobId copied", "success")
    else
        notify("Clipboard unavailable", "error")
    end
end

Features.copyPlace = function()
    if copy(tostring(game.PlaceId)) then
        notify("PlaceId copied", "success")
    else
        notify("Clipboard unavailable", "error")
    end
end

-- ============================================================
-- TOOLKIT  (the machinery that works in all supported games)
-- ============================================================
local T = {
    promptOn = false, promptRadius = 45, promptFilter = "",
    touchOn = false, touchFilter = "coin,gem,cash,diamond,money",
    clickOn = false, clickCps = 8,
    keyOn = false, keyCode = Enum.KeyCode.E,
}

local promptCache, touchCache = {}, {}
local scanAcc, promptAcc, touchAcc, clickAcc, keyAcc = 0, 0, 0, 0, 0

local COLLECT_WORDS = {
    "coin", "gem", "cash", "money", "diamond", "brainrot", "crop", "fruit",
    "seed", "egg", "collect", "orb", "chest", "star", "token", "ticket", "loot",
}

local function pathOf(obj)
    local ok, full = pcall(function() return obj:GetFullName() end)
    return ok and full or tostring(obj.Name)
end

local function matchFilter(text, filter)
    if not filter or filter == "" then return true end
    local low = tostring(text):lower()
    for token in string.gmatch(filter, "[^,%s]+") do
        if low:find(token:lower(), 1, true) then return true end
    end
    return false
end

local function refreshCache()
    local prompts, parts = {}, {}
    local budget = 0
    for _, obj in ipairs(workspace:GetDescendants()) do
        budget = budget + 1
        if budget > 8000 then break end
        if obj:IsA("ProximityPrompt") then
            if #prompts < 300 then table.insert(prompts, obj) end
        elseif obj:IsA("BasePart") then
            if #parts < 400 then
                local low = obj.Name:lower()
                for _, word in ipairs(COLLECT_WORDS) do
                    if low:find(word, 1, true) then
                        table.insert(parts, obj)
                        break
                    end
                end
            end
        end
    end
    promptCache, touchCache = prompts, parts
end

local function firePrompt(prompt)
    if CAP.prompt then
        pcall(fireproximityprompt, prompt)
        return
    end
    pcall(function()
        prompt:InputHoldBegin()
        task.wait(0.05)
        prompt:InputHoldEnd()
    end)
end

local function clickAt(pos)
    if CAP.mouse then
        pcall(mouse1click, pos)
        return
    end
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton1(pos)
    end)
end

local function tapKey(code)
    if not CAP.keypress then return end
    pcall(keypress, code)
    task.delay(0.04, function()
        pcall(keyrelease, code)
    end)
end

-- forward declarations: the heartbeat below calls into both, and both modules
-- are defined further down the file
local Auto, Quest
local autoAcc = 0

track(RunService.Heartbeat:Connect(function(dt)
    dt = dt or 0

    scanAcc = scanAcc + dt
    if scanAcc >= 2 then
        scanAcc = 0
        pcall(refreshCache)
    end

    local hrp = root()

    promptAcc = promptAcc + dt
    if T.promptOn and promptAcc >= 0.35 and hrp then
        promptAcc = 0
        for _, prompt in ipairs(promptCache) do
            if prompt.Parent and prompt.Enabled then
                local part = prompt.Parent
                if part:IsA("BasePart") then
                    local text = (prompt.ActionText or "") .. " " .. (prompt.ObjectText or "") .. " " .. part.Name
                    if matchFilter(text, T.promptFilter)
                        and (part.Position - hrp.Position).Magnitude <= T.promptRadius then
                        firePrompt(prompt)
                    end
                end
            end
        end
    end

    touchAcc = touchAcc + dt
    if T.touchOn and touchAcc >= 0.25 and hrp then
        touchAcc = 0
        if CAP.touch then
            for _, part in ipairs(touchCache) do
                if part.Parent and matchFilter(part.Name, T.touchFilter) then
                    if (part.Position - hrp.Position).Magnitude <= T.promptRadius then
                        pcall(firetouchinterest, hrp, part, 0)
                        pcall(firetouchinterest, hrp, part, 1)
                    end
                end
            end
        end
    end

    clickAcc = clickAcc + dt
    if T.clickOn and clickAcc >= (1 / math.max(T.clickCps, 1)) then
        clickAcc = 0
        local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
        local pos = (Auto and Auto.tapPoint) and Auto.tapPoint(vp) or Vector2.new(vp.X / 2, vp.Y / 2)
        clickAt(pos)
    end

    keyAcc = keyAcc + dt
    if T.keyOn and keyAcc >= 0.12 then
        keyAcc = 0
        tapKey(T.keyCode)
    end

    -- the Auto Farm tab: one pass every half second, each feature throttled
    -- inside Auto.use by its own cooldown
    autoAcc = autoAcc + dt
    if autoAcc >= 0.5 then
        autoAcc = 0
        if Auto and Auto.tick then pcall(Auto.tick) end
    end
end))

-- ---------- scanner window ----------
local scanGui

local function openList(title, rows)
    if scanGui then scanGui:Destroy() end
    scanGui = new("ScreenGui", {
        Name = "TupachupScan",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 620,
    }, PG)

    local frame = new("Frame", {
        Size = UDim2.fromOffset(420, 360),
        Position = UDim2.new(0.5, -210, 0.5, -180),
        BackgroundColor3 = THEME.Bg,
        BorderSizePixel = 0,
    }, scanGui)
    new("UICorner", { CornerRadius = UDim.new(0, 9) }, frame)
    new("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, frame)

    new("TextLabel", {
        Size = UDim2.new(1, -70, 0, 34),
        Position = UDim2.fromOffset(14, 4),
        BackgroundTransparency = 1,
        Text = title,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = THEME.Text,
    }, frame)

    local close = new("TextButton", {
        Size = UDim2.fromOffset(26, 22),
        Position = UDim2.new(1, -36, 0, 6),
        BackgroundColor3 = THEME.Row,
        BorderSizePixel = 0,
        Text = "x",
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = THEME.Red,
        AutoButtonColor = false,
    }, frame)
    new("UICorner", { CornerRadius = UDim.new(0, 5) }, close)
    close.MouseButton1Click:Connect(function()
        scanGui:Destroy()
    end)

    local list = new("ScrollingFrame", {
        Size = UDim2.new(1, -16, 1, -48),
        Position = UDim2.fromOffset(8, 38),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, #rows * 30 + 8),
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = THEME.Stroke,
    }, frame)

    for i, row in ipairs(rows) do
        local b = new("TextButton", {
            Size = UDim2.new(1, -8, 0, 28),
            Position = UDim2.fromOffset(2, (i - 1) * 30),
            BackgroundColor3 = THEME.Row,
            BorderSizePixel = 0,
            Text = "  " .. tostring(row.text),
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Font = Enum.Font.GothamMedium,
            TextSize = 11,
            TextColor3 = THEME.Text,
            AutoButtonColor = false,
        }, list)
        new("UICorner", { CornerRadius = UDim.new(0, 5) }, b)
        b.MouseEnter:Connect(function() b.BackgroundColor3 = THEME.Stroke end)
        b.MouseLeave:Connect(function() b.BackgroundColor3 = THEME.Row end)
        b.MouseButton1Click:Connect(row.action)
    end

    local dragging, dragStart, startPos = false, nil, nil
    local bar = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundTransparency = 1,
        Text = "",
    }, frame)
    bar.MouseButton1Down:Connect(function()
        dragging = true
        dragStart = UIS:GetMouseLocation()
        startPos = frame.Position
    end)
    track(UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        local now = UIS:GetMouseLocation()
        local delta = now - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end))
    track(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

local Toolkit = {}

function Toolkit.scanPrompts()
    refreshCache()
    local rows = {}
    for i, prompt in ipairs(promptCache) do
        if i > 150 then break end
        local label = (prompt.ActionText ~= "" and prompt.ActionText) or prompt.Parent.Name
        rows[#rows + 1] = {
            text = label .. "  |  " .. pathOf(prompt.Parent),
            action = function()
                firePrompt(prompt)
                notify("Fired: " .. tostring(prompt.Parent.Name), "success")
            end,
        }
    end
    if #rows == 0 then
        notify("No ProximityPrompts found", "error")
        return
    end
    openList("Prompts (" .. #rows .. ")", rows)
end

function Toolkit.scanRemotes()
    local rows = {}
    local container = game:GetService("ReplicatedStorage")
    for _, obj in ipairs(container:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            local path = pathOf(obj)
            rows[#rows + 1] = {
                text = path,
                action = function()
                    if copy(path) then
                        notify("Copied path", "success")
                    else
                        notify(path, "info")
                    end
                end,
            }
            if #rows >= 200 then break end
        end
    end
    if #rows == 0 then
        notify("No remotes under ReplicatedStorage", "error")
        return
    end
    openList("Remotes (" .. #rows .. ")", rows)
end

function Toolkit.scanParts()
    refreshCache()
    local rows = {}
    for i, part in ipairs(touchCache) do
        if i > 150 then break end
        rows[#rows + 1] = {
            text = part.Name .. "  |  " .. pathOf(part),
            action = function()
                local hrp = root()
                if hrp and CAP.touch then
                    pcall(firetouchinterest, hrp, part, 0)
                    pcall(firetouchinterest, hrp, part, 1)
                    notify("Touched: " .. part.Name, "success")
                else
                    notify("No firetouchinterest", "error")
                end
            end,
        }
    end
    if #rows == 0 then
        notify("No collectible parts found", "error")
        return
    end
    openList("Parts (" .. #rows .. ")", rows)
end

-- ---------- remote firer ----------
local function remotePaths()
    local out = {}
    for _, obj in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
        if obj:IsA("RemoteEvent") then
            table.insert(out, pathOf(obj))
            if #out >= 150 then break end
        end
    end
    return out
end

local function resolvePath(path)
    local node = game
    for seg in string.gmatch(tostring(path), "[^%.]+") do
        local child = node:FindFirstChild(seg)
        if not child then return nil end
        node = child
    end
    return node
end

local function parseArgs(text)
    local out = {}
    if not text or text == "" then return out end
    for token in string.gmatch(text, "[^,]+") do
        local t = token:gsub("^%s+", ""):gsub("%s+$", "")
        local num = tonumber(t)
        if num then
            table.insert(out, num)
        elseif t == "true" then
            table.insert(out, true)
        elseif t == "false" then
            table.insert(out, false)
        else
            table.insert(out, t:gsub('^"', ""):gsub('"$', ""))
        end
    end
    return out
end

function Toolkit.fireRemote(path, argsText)    local remote = resolvePath(path)
    if not remote then
        notify("Remote not found", "error")
        return
    end
    local args = parseArgs(argsText)
    local ok = pcall(function()
        remote:FireServer(table.unpack(args))
    end)
    notify(ok and ("Fired " .. tostring(remote.Name)) or "Fire failed", ok and "success" or "error")
end

Toolkit.State = T

-- ============================================================
-- PROTECTION
-- ============================================================
-- Client-side only, and honest about it: a server kick cannot be cancelled
-- from the client, so Anti-Kick stops the local Kick() calls game scripts
-- make, and says so instead of pretending it is a shield.
local Protect = { kickOn = false, hidden = false, locked = false, restoreKick = nil }

function Protect.apiScore()
    local have, total = 0, 0
    for _, present in pairs(CAP) do
        total = total + 1
        if present then have = have + 1 end
    end
    return have, total
end

function Protect.hideGui(on, quiet)
    if on then
        local holder
        if type(gethui) == "function" then
            local ok, res = pcall(gethui)
            if ok then holder = res end
        end
        if not holder and type(get_hidden_gui) == "function" then
            local ok, res = pcall(get_hidden_gui)
            if ok then holder = res end
        end
        if not holder then
            if not quiet then
                notify("gethui is missing - the hub stays in PlayerGui", "warn", "Protection")
            end
            return false
        end
        gui.Parent = holder
        Protect.hidden = true
        return true
    end
    gui.Parent = PG
    Protect.hidden = false
    return true
end

function Protect.lockGui(on, quiet)
    if not on then
        Protect.locked = false
        return true
    end
    if type(protectgui) ~= "function" then
        if not quiet then
            notify("protectgui is missing - the GUI stays unlocked", "warn", "Protection")
        end
        return false
    end
    local ok = pcall(protectgui, gui, true)
    Protect.locked = ok
    return ok
end

function Protect.antiKick(on, quiet)
    if Protect.restoreKick then
        pcall(Protect.restoreKick)
        Protect.restoreKick = nil
    end
    Protect.kickOn = on and true or false
    if not on then return true end

    if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
        Protect.kickOn = false
        if not quiet then
            notify("hookmetamethod is missing - Anti-Kick is off here", "warn", "Protection")
        end
        return false
    end

    local original
    original = hookmetamethod(game, "__namecall", function(self, ...)
        if Protect.kickOn and getnamecallmethod() == "Kick" and self == LP then
            notify("Kick blocked. A server kick still removes you.", "warn", "Protection")
            return
        end
        return original(self, ...)
    end)
    Protect.restoreKick = function()
        pcall(function() hookmetamethod(game, "__namecall", original) end)
    end
    return true
end

Features.antiKick = function(on, quiet)
    local ok = Protect.antiKick(on, quiet)
    if on and ok and not quiet then
        notify("Anti-Kick armed", "success", "Protection")
    end
    return ok
end

Features.hideGui = function(on, quiet)
    local ok = Protect.hideGui(on, quiet)
    if on and ok and not quiet then
        notify("Hub moved out of PlayerGui", "success", "Protection")
    end
    return ok
end

Features.lockGui = function(on, quiet)
    local ok = Protect.lockGui(on, quiet)
    if on and ok and not quiet then
        notify("GUI locked against Destroy", "success", "Protection")
    end
    return ok
end

Stops.Protect = function()
    pcall(Protect.antiKick, false, true)
end

-- ============================================================
-- AUTO FARM ENGINE
-- ============================================================
-- Every feature here is a labelled button in the game's own UI. Nothing fires
-- a guessed remote: the engine finds the button by text, then clicks it.
Auto = {
    last = {},          -- feature key -> os.clock of the last click
    tapMode = "Random",
    miscItem = "Basic Coin Jar",
    flagItem = "Strength Flag",
    breakables = {},
    breakablesAt = 0,
}

local AUTO_BREAK_WORDS = {
    "breakable", "chest", "coin", "jar", "crate", "rock", "ore", "tree",
    "crystal", "gem", "box", "barrel", "vault",
}

local function autoThrottle(key, seconds)
    local now = os.clock()
    local last = Auto.last[key]
    -- a nil last means never fired. Comparing against 0 would block the first
    -- click for `seconds` on a freshly started client, where os.clock is small.
    if last and (now - last) < seconds then return false end
    Auto.last[key] = now
    return true
end

-- words: at least one must appear. avoid: none may appear. context: if given,
-- at least one of these must also appear.
-- The longest matching word wins: "free gift" beats a generic "claim" that a
-- different panel happens to be showing. A plain claim is still the fallback
-- when nothing more specific is on screen.
local function autoFind(words, avoid, context)
    local best, bestScore, longest = nil, 0, 0
    for _, w in ipairs(words) do
        if #w > longest then longest = #w end
    end

    local function scoreOf(hay)
        local score = 0
        for _, w in ipairs(words) do
            if #w > score and string.find(hay, w, 1, true) then score = #w end
        end
        return score
    end

    local function blockedBy(hay)
        for _, w in ipairs(avoid or {}) do
            if string.find(hay, w, 1, true) then return true end
        end
        if context and #context > 0 then
            for _, w in ipairs(context) do
                if string.find(hay, w, 1, true) then return false end
            end
            return true
        end
        return false
    end

    eachGameGui(function(inst)
        if inst:IsA("GuiButton") and isShown(inst) then
            -- cheap pass first: name and own text. Only a miss pays for the
            -- descendant walk, which is what most real game buttons need.
            local hay = string.lower(inst.Name) .. " " .. string.lower(inst.Text or "")
            local score = scoreOf(hay)
            if score == 0 then
                hay = labelOf(inst)
                score = scoreOf(hay)
            end
            if score > 0 and not blockedBy(hay) then
                if score > bestScore then
                    best, bestScore = inst, score
                end
                if bestScore >= longest then return false end
            end
        end
        return nil
    end)
    return best
end

-- A switch that lights up and finds nothing is indistinguishable from a broken
-- hub. After three empty sweeps the engine says so once per key: the words are
-- printed, so it is obvious which panel has to be open first.
Auto.missWarned = Auto.missWarned or {}
Auto.missCount = Auto.missCount or {}

function Auto.use(words, key, seconds, avoid, context)
    if not autoThrottle(key, seconds) then return false end
    local btn = autoFind(words, avoid, context)
    if not btn then
        local n = (Auto.missCount[key] or 0) + 1
        Auto.missCount[key] = n
        if n == 3 and not Auto.missWarned[key] then
            Auto.missWarned[key] = true
            notify("No button for \"" .. tostring(words[1]) .. "\" on screen - open that panel in game", "warn", "Auto " .. tostring(key))
        end
        return false
    end
    Auto.missCount[key] = 0
    return PSX.click(btn)
end

-- dropdown food: the names the game is actually showing
function Auto.options(words, fallback, cap)
    local out, seen = {}, {}
    eachGameGui(function(inst)
        if inst:IsA("GuiButton") and isShown(inst) then
            local text = cleanText(inst.Text or "")
            if text == "" then
                -- the label usually lives one level down on an ImageButton
                local lbl = inst:FindFirstChildWhichIsA("TextLabel", true)
                if lbl then text = cleanText(lbl.Text or "") end
            end
            local low = string.lower(text)
            if #text >= 3 and #text <= 28 and not seen[low] then
                for _, w in ipairs(words) do
                    if string.find(low, w, 1, true) then
                        seen[low] = true
                        out[#out + 1] = text
                        break
                    end
                end
            end
            if #out >= cap then return false end
        end
        return nil
    end)
    if #out == 0 then return fallback end
    table.sort(out)
    return out
end

-- flies the character to the nearest part whose name matches, then fires its
-- prompt if it has one. Used by the "find" switches: relics, admin characters,
-- secret key merchants. Never invents a remote.
function Auto.flyToWords(words, key, seconds)
    if not autoThrottle(key, seconds) then return false end
    local hrp = root()
    if not hrp then return false end

    local target, bestDist, scanned = nil, nil, 0
    for _, obj in ipairs(workspace:GetDescendants()) do
        scanned = scanned + 1
        if scanned > 12000 then break end
        if obj:IsA("BasePart") then
            local low = string.lower(obj.Name)
            for _, w in ipairs(words) do
                if string.find(low, w, 1, true) then
                    local d = (obj.Position - hrp.Position).Magnitude
                    if d < 900 and (not bestDist or d < bestDist) then
                        bestDist, target = d, obj
                    end
                    break
                end
            end
        end
    end
    if not target then return false end

    for _, d in ipairs(target:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Enabled then
            pcall(firePrompt, d)
            break
        end
    end

    if bestDist and bestDist < 12 then return true end

    local bv = new("BodyVelocity", {
        Name = "TupachupFind",
        MaxForce = Vector3.new(1e5, 1e5, 1e5),
        Velocity = Vector3.zero,
    }, hrp)
    local started = os.clock()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if not hrp.Parent or not target.Parent or os.clock() - started > 20 then
            conn:Disconnect()
            if bv.Parent then bv:Destroy() end
            return
        end
        local delta = target.Position - hrp.Position
        if delta.Magnitude < 6 then
            conn:Disconnect()
            if bv.Parent then bv:Destroy() end
            return
        end
        bv.Velocity = delta.Unit * math.min(160, delta.Magnitude * 2.5)
    end)
    track(conn)
    return true
end

function Auto.refreshBreakables()
    local now = os.clock()
    if now - Auto.breakablesAt < 1 then return end
    Auto.breakablesAt = now
    local out, scanned = {}, 0
    for _, obj in ipairs(workspace:GetDescendants()) do
        scanned = scanned + 1
        if scanned > 9000 then break end
        if obj:IsA("BasePart") then
            local low = string.lower(obj.Name)
            for _, w in ipairs(AUTO_BREAK_WORDS) do
                if string.find(low, w, 1, true) then
                    out[#out + 1] = obj
                    break
                end
            end
            if #out >= 250 then break end
        end
    end
    Auto.breakables = out
end

function Auto.nearestBreakable()
    local hrp = root()
    local cam = workspace.CurrentCamera
    if not hrp or not cam then return nil end
    Auto.refreshBreakables()
    local best, bestDist
    for _, part in ipairs(Auto.breakables) do
        if part.Parent then
            local d = (part.Position - hrp.Position).Magnitude
            if d < 300 and (not bestDist or d < bestDist) then
                bestDist, best = d, part
            end
        end
    end
    if not best then return nil end
    local screen, onScreen = cam:WorldToViewportPoint(best.Position)
    if not onScreen then return nil end
    return Vector2.new(screen.X, screen.Y)
end

function Auto.tapPoint(vp)
    if Auto.tapMode == "Center" then
        return Vector2.new(vp.X / 2, vp.Y / 2)
    elseif Auto.tapMode == "Nearest Breakable" then
        local p = Auto.nearestBreakable()
        if p then return p end
    elseif Auto.tapMode == "Screen Edges" then
        local edge = math.random(1, 4)
        local x = (edge == 1) and 60 or (edge == 2) and (vp.X - 60) or math.random(80, math.max(81, math.floor(vp.X - 80)))
        local y = (edge == 3) and 80 or (edge == 4) and (vp.Y - 80) or math.random(80, math.max(81, math.floor(vp.Y - 80)))
        return Vector2.new(x, y)
    end
    return Vector2.new(
        math.random(70, math.max(71, math.floor(vp.X - 70))),
        math.random(70, math.max(71, math.floor(vp.Y - 70)))
    )
end

-- switches from the extra tabs. Each row is one toggle: the flag that turns it
-- on, the button words to look for, its own cooldown key and default delay.
local AUTO_RULES = {
    -- Main: Auto Claim
    { flag = "autoFreeGifts", key = "freegift", seconds = 3,
      words = { "free gift", "gift", "claim" } },
    { flag = "autoRankRewards", key = "rankreward", seconds = 5,
      words = { "rank reward", "rank", "reward", "claim" } },
    { flag = "autoForeverPack", key = "foreverpack", seconds = 4,
      words = { "forever pack", "forever", "gift", "claim" } },
    -- Main: Others
    { flag = "autoBalloons", key = "balloon", seconds = 2,
      words = { "balloon", "pop" } },
    { flag = "autoStairwayExit", key = "stairway", seconds = 4,
      words = { "stairway", "leave", "exit", "heaven" } },
    -- Mailbox
    { flag = "autoMail", key = "mail", seconds = 3,
      words = { "claim all", "collect all", "claim", "collect", "mail", "gift" } },
    -- Current Event
    { flag = "autoEventReward", key = "eventreward", seconds = 4,
      words = { "claim", "collect", "reward", "event" } },
    { flag = "autoEventUse", key = "eventuse", seconds = 3,
      words = { "use", "open", "event item", "event" } },
    -- Fishing World
    { flag = "autoCast", key = "cast", seconds = 2,
      words = { "cast", "fish" } },
    { flag = "autoReel", key = "reel", seconds = 1.5,
      words = { "reel", "hook", "catch" } },
    { flag = "autoSellFish", key = "sellfish", seconds = 6,
      words = { "sell" }, context = { "fish" } },
    -- Farming World
    { flag = "autoPlant", key = "plant", seconds = 2,
      words = { "plant", "seed" } },
    { flag = "autoHarvest", key = "harvest", seconds = 2,
      words = { "harvest", "collect", "pick" } },
    { flag = "autoWater", key = "water", seconds = 8,
      words = { "water" } },
    { flag = "autoSellCrop", key = "sellcrop", seconds = 6,
      words = { "sell" }, context = { "crop", "farm", "garden", "fruit" } },
    -- Egg
    { flag = "autoHatch", key = "hatch", seconds = 1, delayFlag = "hatchDelay",
      words = { "hatch", "egg", "open" } },
    { flag = "autoEquipBest", key = "equipbest", seconds = 6,
      words = { "equip best", "best pet", "equip" } },
    -- Daycare
    { flag = "autoDaycare", key = "daycare", seconds = 5,
      words = { "daycare", "claim", "collect" }, context = { "daycare", "pet" } },
    -- Minigames
    { flag = "autoMinigame", key = "minigame", seconds = 5,
      words = { "play", "join", "start" }, context = { "minigame", "game", "arena" } },
    { flag = "autoMinigameReward", key = "minigamereward", seconds = 6,
      words = { "claim", "reward" }, context = { "minigame", "game", "arena" } },
    -- Automatic
    { flag = "autoClaimAll", key = "claimall", seconds = 4,
      words = { "claim all", "collect all", "claim", "collect", "reward" } },
    { flag = "autoSellAll", key = "sellall", seconds = 8,
      words = { "sell all", "sell" } },
}

function Auto.tick()
    -- keeps re-applying so the game cannot drop the speed back down
    if Flags.infinitePetSpeed then
        local _, hum = char()
        if hum and hum.WalkSpeed ~= 200 then hum.WalkSpeed = 200 end
    end

    if Flags.autoUltimate then Auto.use({ "ultimate" }, "ultimate", 1) end
    if Flags.autoBestArea then Quest.travel(false, Quest.areaWords, "area") end
    if Flags.autoBestWorld then Quest.travel(false, Quest.worldWords, "world") end
    if Flags.autoBuyArea then
        Auto.use({ "buy", "unlock", "purchase" }, "buyArea", 3, nil, Quest.areaWords)
    end
    if Flags.autoRebirth then Auto.use({ "rebirth" }, "rebirth", 5) end

    if Flags.autoMisc and Auto.miscItem and Auto.miscItem ~= "" then
        Auto.use({ string.lower(Auto.miscItem) }, "misc", 2)
    end
    if Flags.autoFlag and Auto.flagItem and Auto.flagItem ~= "" then
        Auto.use({ string.lower(Auto.flagItem) }, "flag", 2)
    end
    if Flags.autoSprinkler then Auto.use({ "sprinkler" }, "sprinkler", 5) end

    if Flags.autoTNT then
        Auto.use({ "tnt" }, "tnt", Flags.tntDelay or 7.5, { "crate" })
    end
    if Flags.autoTNTCrate then
        Auto.use({ "tnt crate", "crate" }, "tntcrate", Flags.tntCrateDelay or 15)
    end

    -- everything the extra tabs switch on: one row per switch, same engine
    for _, rule in ipairs(AUTO_RULES) do
        if Flags[rule.flag] then
            Auto.use(rule.words, rule.key, Flags[rule.delayFlag] or rule.seconds, rule.avoid, rule.context)
        end
    end

    -- Main: find switches. Both walk the map for a named part, then fire its
    -- prompt or fly the character to it.
    if Flags.autoShinyRelics then
        Auto.flyToWords({ "shiny", "relic" }, "shiny", 8)
    end
    if Flags.autoAdminAbuse then
        Auto.flyToWords({ "admin", "abuse" }, "admin", 10)
    end

    -- Main: secret keys sit behind an area gate, so the area button comes first
    if Flags.autoTreehouse then
        if Quest.gotoArea(15, Quest.areaWords) then
            Auto.use({ "treehouse", "merchant" }, "treehouse", 6)
        end
    end
    if Flags.autoCrystalKey then
        if Quest.gotoArea(58, Quest.areaWords) then
            Auto.use({ "crystal", "castle" }, "crystal", 6)
        end
    end
end

Auto.rules = AUTO_RULES

-- the quest runner arms the same engine through these flags
bind("autoPrompt", function(v)
    Flags.autoPrompt = v and true or false
    T.promptOn = Flags.autoPrompt
end)
bind("autoTouch", function(v)
    Flags.autoTouch = v and true or false
    T.touchOn = Flags.autoTouch
end)
bind("autoClick", function(v)
    Flags.autoClick = v and true or false
    T.clickOn = Flags.autoClick
end)
bind("promptFilter", function(v)
    Flags.promptFilter = (v == nil) and "" or tostring(v)
    T.promptFilter = Flags.promptFilter
end)
bind("touchFilter", function(v)
    Flags.touchFilter = (v == nil) and "" or tostring(v)
    T.touchFilter = Flags.touchFilter
end)
bind("promptRadius", function(v)
    Flags.promptRadius = tonumber(v) or 45
    T.promptRadius = Flags.promptRadius
end)
bind("clickCps", function(v)
    Flags.clickCps = tonumber(v) or 8
    T.clickCps = Flags.clickCps
end)

-- ============================================================
-- PAGES
-- ============================================================
local pages = {}
local tabButtons = {}
local selectedTab

-- Roblox's Gotham font has no coverage for the symbol glyphs a web mock uses,
-- so the sidebar draws a shape instead of a character. Tofu boxes are worse
-- than no icon: the dot always renders.
local tabIndex = 0

-- Tab row: emoji icon, label, and an explicit slot so the sidebar order is the
-- spec's order, not the order the sections happen to be written in.
local TAB_SLOT = 0
local function addTab(name, icon, order)
    local page = makePage()
    pages[name] = page

    tabIndex = tabIndex + 1
    TAB_SLOT = TAB_SLOT + 1
    local idx = order or TAB_SLOT
    local btn = new("TextButton", {
        Name = "Tab_" .. name,
        Size = UDim2.new(1, -14, 0, 28),
        Position = UDim2.fromOffset(7, 6 + (idx - 1) * 30),
        BackgroundColor3 = THEME.Row,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
    }, tabHolder)
    new("UICorner", { CornerRadius = UDim.new(0, 7) }, btn)

    local marker = new("Frame", {
        Size = UDim2.fromOffset(2, 13),
        Position = UDim2.fromOffset(0, 7),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        Visible = false,
    }, btn)
    new("UICorner", { CornerRadius = UDim.new(1, 0) }, marker)

    local glyph = new("TextLabel", {
        Name = "Icon",
        Size = UDim2.fromOffset(18, 28),
        Position = UDim2.fromOffset(9, 0),
        BackgroundTransparency = 1,
        Text = icon or "",
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextTransparency = 0.15,
    }, btn)

    local label = new("TextLabel", {
        Size = UDim2.new(1, -42, 1, 0),
        Position = UDim2.fromOffset(32, 0),
        BackgroundTransparency = 1,
        Text = name,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = THEME.Sub,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, btn)

    btn.MouseEnter:Connect(function()
        if selectedTab ~= name then
            TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundTransparency = 0.85 }):Play()
        end
    end)
    btn.MouseLeave:Connect(function()
        if selectedTab ~= name then
            TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundTransparency = 1 }):Play()
        end
    end)

    local function select()
        for tabName, p in pairs(pages) do
            p.frame.Visible = (tabName == name)
        end
        for tabName, b in pairs(tabButtons) do
            local isSel = (tabName == name)
            b.btn.BackgroundTransparency = isSel and 0 or 1
            b.label.TextColor3 = isSel and THEME.Text or THEME.Sub
            b.icon.TextTransparency = isSel and 0 or 0.25
            b.marker.Visible = isSel
        end
        selectedTab = name
    end

    btn.MouseButton1Click:Connect(select)

    tabButtons[name] = {
        btn = btn,
        marker = marker,
        icon = glyph,
        label = label,
    }

    if not selectedTab then
        select()
    end

    return page
end

-- ---------- HOME ----------
local main = addTab("Home", "🏠", 1)

addSection(main, "Credits")
addNote(main, BRAND .. " v" .. VERSION .. " - built and maintained by the " .. BRAND .. " team.", THEME.Sub)
addCopyRow(main, "Copy Discord Server Invite", "https://discord.gg/ojailbreaks")
addCopyRow(main, "Copy Hub Site", "https://vkorona26-oss.github.io/Tupachub/")

addSection(main, "Character")
addSlider(main, "Walk Speed", 16, 200, 16, 1, "walkSpeed", function(v) Features.setWalk(v) end)
addSlider(main, "Jump Power", 50, 300, 50, 1, "jumpPower", function(v) Features.setJump(v) end)
addToggle(main, "Infinite Jump", false, "infJump", function(v) Features.infJump(v) end)
addToggle(main, "Noclip", false, "noclip", function(v) Features.noclip(v) end)
addToggle(main, "Anti-AFK", false, "antiAfk", function(v) Features.antiAfk(v) end)
addToggle(main, "Anti-Void", false, "antiVoid", function(v) Features.antiVoid(v) end)
addButton(main, "Reset Character", THEME.Red, function() Features.reset() end)

addSection(main, "Flight")
addToggle(main, "Fly", false, "fly", function(v) Features.fly(v) end)
addSlider(main, "Fly Speed", 10, 300, 50, 1, "flySpeed", function(v) Features.flySpeed(v) end)

-- ---------- GAMES + AUTO FARM ----------
local gamePage = addTab("Main", "🏡", 13)
-- the whole farm page lives in its own block: the compiler frees its locals at
-- the end, and the main chunk is already near the 200-local ceiling.
-- callSetter stays outside because the quest runner drives the same flags.
local callSetter
do
local farmPage = addTab("Farm", "🖱️", 10)

function callSetter(flag, v)
    if Setters[flag] then pcall(Setters[flag], v) end
end

addSection(farmPage, "Auto Farm")
addToggle(farmPage, "Infinite Pet Speed", false, "infinitePetSpeed", function(on)
    local _, hum = char()
    if not hum then return end
    hum.WalkSpeed = on and 200 or baseWalk
end)

local TAP_MODES = { "Random", "Center", "Nearest Breakable", "Screen Edges" }
addDropdown(farmPage, "Auto Tap Mode", function() return TAP_MODES end, "Random", "tapMode",
    function(v) Auto.tapMode = v end)

addToggle(farmPage, "Auto Tap", false, "autoTap", function(on)
    callSetter("autoClick", on)
end)

addToggle(farmPage, "Auto Efficient Farm (Fast Farm)", false, "fastFarm", function(on)
    if on then
        callSetter("autoPrompt", true)
        callSetter("promptFilter", "")
        callSetter("touchFilter", "")
        if CAP.touch then callSetter("autoTouch", true) end
        callSetter("autoClick", true)
        Quest.travel(false, Quest.areaWords, "area")
        notify("Fast farm: prompts, orbs and tap are on", "success", "Auto Farm")
    else
        callSetter("autoPrompt", false)
        callSetter("autoTouch", false)
        callSetter("autoClick", false)
    end
end)

addToggle(farmPage, "Auto Collect Orbs", false, "autoOrbs", function(on)
    callSetter("autoTouch", on)
end)

addToggle(farmPage, "Auto Use Ultimate", false, "autoUltimate")
addToggle(farmPage, "Auto Teleport To Best Area", false, "autoBestArea")
addToggle(farmPage, "Auto Buy Next Area", false, "autoBuyArea")
addToggle(farmPage, "Auto Rebirth", false, "autoRebirth")
addToggle(farmPage, "Auto Teleport To Best World", false, "autoBestWorld")

addSection(farmPage, "Auto Use Items")
local MISC_FALLBACK = { "Basic Coin Jar", "Coin Jar", "Potion", "Booster", "Chest" }
addDropdown(farmPage, "Select a Misc Item",
    function() return Auto.options({ "jar", "potion", "booster", "item", "orb", "chest" }, MISC_FALLBACK, 24) end,
    "Basic Coin Jar", "miscItem", function(v) Auto.miscItem = v end)

addToggle(farmPage, "Auto Use Misc Item", false, "autoMisc")

local FLAG_FALLBACK = { "Strength Flag", "Speed Flag", "Coin Flag", "Luck Flag" }
addDropdown(farmPage, "Select a Flag",
    function() return Auto.options({ "flag" }, FLAG_FALLBACK, 24) end,
    "Strength Flag", "flagItem", function(v) Auto.flagItem = v end)

addToggle(farmPage, "Auto Use Flag", false, "autoFlag")
addToggle(farmPage, "Auto Use Breakable Sprinkler", false, "autoSprinkler")

addSection(farmPage, "TNT")
addSlider(farmPage, "TNT Delay", 1, 30, 7.5, 0.5, "tntDelay", nil, " Seconds")
addToggle(farmPage, "Auto Use TNT", false, "autoTNT")
addSlider(farmPage, "TNT Crate Delay", 1, 60, 15, 0.5, "tntCrateDelay", nil, " Seconds")
addToggle(farmPage, "Auto Use TNT Crate", false, "autoTNTCrate")

addNote(farmPage, "Every switch finds the game's own button by label and clicks it. Cooldowns are the sliders above; nothing is fired blind.", THEME.Sub)
end

-- ---------- MAIN ----------
-- The Main tab is a fixed layout: Auto Claim, Others, Secret Key. The game
-- preset plumbing that used to live here moved into the Farm tab's own
-- switches, so this page no longer rebuilds itself on a dropdown.
do
addSection(gamePage, "Auto Claim")
addToggle(gamePage, "Auto Claim Free Gifts", false, "autoFreeGifts")
addToggle(gamePage, "Auto Claim Rank Rewards", false, "autoRankRewards")
addToggle(gamePage, "Auto Claim Forever Pack Free Gifts", false, "autoForeverPack")
addToggle(gamePage, "Auto Find Shiny Relics", false, "autoShinyRelics")

addSection(gamePage, "Others")
addToggle(gamePage, "Auto Pop Balloons", false, "autoBalloons")
addToggle(gamePage, "Auto Leave Stairway To Heaven", false, "autoStairwayExit")
addToggle(gamePage, "Auto Find Admin Abuse Character ⭐", false, "autoAdminAbuse")

addSection(gamePage, "Secret Key")
addToggle(gamePage, "Auto Treehouse Merchant (Secret Key, Area 15)", false, "autoTreehouse")
addToggle(gamePage, "Auto Crystal Key Castle (Secret Key, Area 58)", false, "autoCrystalKey")

addNote(gamePage, "Detected: " .. DETECTED_NAME .. ". Every claim switch clicks a labelled button in the game's own UI. The find switches walk the map for the named object, then fire its prompt.", THEME.Sub)
end

-- ---------- PLAYER (visuals + teleport) ----------
local vis = addTab("Player", "👤", 17)
addSection(vis, "Players")
addToggle(vis, "Player ESP", false, "esp", function(v) Features.esp(v) end)
addToggle(vis, "ESP Names + Health", false, "espNames", function(v) Features.espNames(v) end)
addSection(vis, "Environment")
addToggle(vis, "Fullbright", false, "fullbright", function(v) Features.fullbright(v) end)
addSlider(vis, "Camera FOV", 70, 120, 70, 1, "fov", function(v) Features.fov(v) end)

addSection(vis, "Teleport Waypoints")
local wpName = addTextbox(vis, "Name", "spawn", "wpName")
addButton(vis, "Save Current Position", THEME.Text, function()
    addWaypoint(wpName.Text)
end)
waypointPanel = addPanel(vis, 150)
addSection(vis, "Teleport Targets")
addDropdown(vis, "Player", playerNames, "-", "tpTarget", function(v) Features.tpPlayer(v) end)
addButton(vis, "Teleport To Player", THEME.Text, function()
    if Flags.tpTarget and Flags.tpTarget ~= "-" then
        Features.tpPlayer(Flags.tpTarget)
    else
        notify("Pick a player first", "error")
    end
end)
addButton(vis, "Teleport To Cursor", THEME.Text, function() Features.tpMouse() end)

-- ---------- WEBHOOK ----------
local hook = addTab("Webhook", "🪝", 2)
addSection(hook, "Discord Webhook")
local hookBox = addTextbox(hook, "URL", "https://discord.com/api/webhooks/...", "webhookUrl")
addButton(hook, "Send Test Message", THEME.Text, function()
    Features.webhookTest(hookBox.Text)
end)
if CAP.request then
    addNote(hook, "Paste a Discord webhook URL, then send a test. The URL stays in memory and in your saved config only.", THEME.Sub)
else
    addNote(hook, "request() is missing on this executor - webhook sending is off.", THEME.Red)
end

-- ---------- OPTIMIZATION ----------
local opt = addTab("Optimization", "🪄", 4)

addSection(opt, "Game Objects")
addToggle(opt, "Disable Breakables Models", false, "noBreakables", function(v) Features.renderFilter(v) end)
addToggle(opt, "Disable Pets Rendering", false, "noPets", function(v) Features.renderFilter(v) end)
addToggle(opt, "Disable Confetti Rendering", false, "noConfetti", function(v) Features.renderFilter(v) end)
addToggle(opt, "Disable Lootbox Animation", false, "noLootbox", function(v) Features.renderFilter(v) end)
addToggle(opt, "Disable Exclusive Egg Animation", false, "noEggFx", function(v) Features.renderFilter(v) end)
addNote(opt, "Hides the object on your client only - the server still counts it. Rescans every 1.5s, restored on toggle off and on unload.", THEME.Sub)

addSection(opt, "Graphics")
addToggle(opt, "Low Graphics Mode", false, "lowGfx", function(v) Features.lowGraphics(v) end)
addNote(opt, "Turns off post effects, atmosphere density and water waves. Restored on toggle off and on unload.", THEME.Sub)

addSection(opt, "Frame Rate")
if CAP.fpsCap then
    addSlider(opt, "FPS Cap", 30, 240, 60, 10, "fpsCap", function(v) Features.fpsCap(v) end)
else
    addNote(opt, "setfpscap is missing on this executor - frame cap is off.", THEME.Red)
end

-- ---------- PSX ----------
do
local psx = addTab("PSX Classic", "🕹️", 5)

addSection(psx, "PSX Classic")
addMultiSelect(psx, "Select Goals to Complete in PSX...",
    { "Rewards", "Index", "Daily", "Quests", "Eggs", "Bank" },
    {}, "psxGoals")

addToggle(psx, "Auto Join PSX Classic", false, "psxAutoJoin", function(v) Features.psxAutoJoin(v) end)
addToggle(psx, "Auto Complete Selected Goals", false, "psxAutoGoals")

addButton(psx, "Join PSX Classic", THEME.Accent, function() Features.psxJoin() end)
addButton(psx, "Open Classic Rewards", THEME.Text, function() Features.psxGoal("Rewards") end)
addButton(psx, "Open Classic Index", THEME.Text, function() Features.psxGoal("Index") end)

if CAP.firesignal then
    addNote(psx, "Finds the on-screen PSX button by label and fires its click. Open the PSX menu first if a button is not found.", THEME.Sub)
else
    addNote(psx, "firesignal is missing on this executor - PSX buttons are off. Join still works if a PlaceId is set.", THEME.Red)
end

-- ============================================================
-- QUEST RUNNER
-- ============================================================
-- The quest panel is the game printing its own requirements: "Break 50
-- Breakables", "Hatch 20 Eggs", "Collect 5,000 Coins". Nothing here guesses a
-- remote. The requirement line decides which farm tool gets armed, and claim
-- buttons are fired through their own MouseButton1Click.
Quest = {
    claimWords = { "claim", "collect", "complete", "redeem", "turn in" },
    questWords = {
        Daily = "daily", Rank = "rank", Clan = "clan",
        Season = "season", Event = "event", Index = "index",
    },
    -- the game's own quest button, so the runner never needs the panel opened
    -- by hand
    panelWords = { "quest", "mission", "task", "objective", "rank quest" },
    -- area / world map labels: highest unlocked number wins
    areaWords = {
        "area", "zone", "world", "biome", "island", "map",
        "stage", "realm", "land", "dimension", "location",
    },
    lockedWords = { "lock", "require", "need", "buy", "unlock", "not enough", "too weak" },
    worldWords = { "world", "dimension", "realm", "universe", "galaxy", "planet" },
    -- requirement keyword -> what the farm toolkit has to do about it
    plan = {
        breakable = {
            words = { "breakable", "break", "destroy", "smash", "chest", "dig", "mine" },
            set = {
                autoPrompt = true,
                promptFilter = "breakable, break, chest, destroy, dig, mine",
                promptRadius = 120,
            },
        },
        egg = {
            words = { "hatch", "egg" },
            set = {
                autoPrompt = true,
                promptFilter = "egg, hatch",
                promptRadius = 120,
            },
        },
        coin = {
            words = { "coin", "gem", "cash", "money", "diamond", "collect", "pick" },
            set = {
                autoTouch = true,
                touchFilter = "coin, gem, cash, money, diamond, collect",
                promptRadius = 120,
            },
        },
        plant = {
            words = { "plant", "harvest", "water", "grow", "seed" },
            set = {
                autoPrompt = true,
                promptFilter = "plant, harvest, water, collect",
                promptRadius = 120,
                autoTouch = true,
                touchFilter = "crop, fruit, seed, plant",
            },
        },
        sell = {
            words = { "sell", "trade", "buy", "purchase" },
            set = {
                autoPrompt = true,
                promptFilter = "sell, trade, buy, purchase",
                promptRadius = 120,
            },
        },
        click = {
            words = { "click", "tap", "spin", "wheel", "press" },
            set = { autoClick = true, clickCps = 15 },
        },
        boss = {
            words = { "defeat", "kill", "damage", "boss", "attack" },
            set = { autoClick = true, clickCps = 20 },
        },
        escape = {
            words = { "escape", "survive", "reach", "door", "exit" },
            set = {
                autoPrompt = true,
                promptFilter = "escape, door, exit, enter, reach",
                promptRadius = 120,
            },
        },
    },
    -- order decides priority when one line matches two rules
    order = { "breakable", "egg", "coin", "plant", "sell", "click", "boss", "escape" },
    armed = {},  -- flag -> { prev = value } recorded before we touched it
    reqs = {},   -- requirement list from the last read
    cycles = 0,
}

local questStatusLabel

local function uiButtons(words, limit)
    local out, seen = {}, 0
    for _, inst in ipairs(PG:GetDescendants()) do
        seen = seen + 1
        if seen > GUI_SCAN_CAP then break end
        if inst:IsA("GuiButton") and isShown(inst) then
            local hay = string.lower(inst.Name) .. " " .. string.lower(inst.Text or "")
            for _, w in ipairs(words) do
                if string.find(hay, w, 1, true) then
                    out[#out + 1] = inst
                    break
                end
            end
            if #out >= limit then break end
        end
    end
    return out
end

local function matchesAny(btn, words)
    if #words == 0 then return true end
    local hay = string.lower(btn.Name) .. " " .. string.lower(btn.Text or "")
    for _, w in ipairs(words) do
        if string.find(hay, w, 1, true) then return true end
    end
    return false
end

function Quest.classify(low)
    for _, key in ipairs(Quest.order) do
        for _, w in ipairs(Quest.plan[key].words) do
            if string.find(low, w, 1, true) then return key end
        end
    end
    return nil
end

-- the panel is not named the same in every game, so the ancestor name is a
-- hint, not a requirement: a progress line ("0/50") is enough on its own
local QUEST_NODE_WORDS = { "quest", "goal", "mission", "task", "objective", "challenge" }

local function underQuestNode(inst)
    local node, depth = inst.Parent, 0
    while node and node ~= PG and depth < 9 do
        local low = string.lower(node.Name)
        for _, w in ipairs(QUEST_NODE_WORDS) do
            if string.find(low, w, 1, true) then return true end
        end
        node = node.Parent
        depth = depth + 1
    end
    return false
end

local function cleanText(text)
    local t = string.gsub(text, "%s+", " ")
    t = string.gsub(t, "^%s+", "")
    t = string.gsub(t, "%s+$", "")
    return t
end

function Quest.read()
    local primary, fallback, seen = {}, {}, {}
    local scanned = 0
    for _, inst in ipairs(PG:GetDescendants()) do
        scanned = scanned + 1
        if scanned > GUI_SCAN_CAP then break end
        if inst:IsA("TextLabel") and type(inst.Text) == "string"
            and inst.Text ~= "" and isShown(inst) then
            local text = cleanText(inst.Text)
            local low = string.lower(text)
            if #text >= 4 and #text <= 90 and not seen[low] then
                local key = Quest.classify(low)
                local isQuestNode = key and underQuestNode(inst)
                -- a quest-named panel is trusted on its own; anywhere else the
                -- line needs a number before it counts as a requirement
                if key and (isQuestNode or string.find(low, "%d")) then
                    seen[low] = true
                    local entry = { text = text, key = key }
                    if isQuestNode then
                        primary[#primary + 1] = entry
                    else
                        fallback[#fallback + 1] = entry
                    end
                end
            end
            if #primary >= 40 then break end
        end
    end
    Quest.reqs = (#primary > 0) and primary or fallback
    return Quest.reqs
end

-- the requirement names the thing to hit: "Break 3 coin jars" has to put "jar"
-- in the prompt filter, or the tool runs with a filter that matches nothing
local QUEST_STOP = {
    the = true, ["and"] = true, ["for"] = true, with = true, from = true,
    ["break"] = true, hatch = true, collect = true, plant = true, sell = true,
    open = true, complete = true, your = true, quest = true, rank = true,
    times = true, total = true, reach = true, earn = true, defeat = true,
}

function Quest.keywords(reqs, key)
    local out, seen = {}, {}
    for _, r in ipairs(reqs or {}) do
        if r.key == key then
            for word in string.gmatch(string.lower(r.text), "%a+") do
                if #word > 4 and string.sub(word, -1) == "s" then
                    word = string.sub(word, 1, -2)
                end
                if #word >= 3 and not QUEST_STOP[word] and not seen[word] then
                    seen[word] = true
                    out[#out + 1] = word
                end
            end
        end
    end
    return out
end

function Quest.arm(keys, reqs)
    local applied = {}
    for _, key in ipairs(Quest.order) do
        if keys[key] then
            local extra = Quest.keywords(reqs, key)
            for flag, base in pairs(Quest.plan[key].set) do
                local value = base
                if flag == "promptFilter" or flag == "touchFilter" then
                    local added = 0
                    for _, w in ipairs(extra) do
                        if not string.find(base, w, 1, true) then
                            value = value .. ", " .. w
                            added = added + 1
                            if added >= 4 then break end
                        end
                    end
                end
                if Quest.armed[flag] == nil then
                    Quest.armed[flag] = { prev = Flags[flag] }
                end
                if Flags[flag] ~= value then
                    callSetter(flag, value)
                    applied[#applied + 1] = flag
                end
            end
        end
    end
    table.sort(applied)
    return applied
end

function Quest.disarm()
    local restored = 0
    for flag, rec in pairs(Quest.armed) do
        if Flags[flag] ~= rec.prev then
            callSetter(flag, rec.prev)
            restored = restored + 1
        end
    end
    Quest.armed = {}
    return restored
end

function Quest.claim()
    local maxRank = Flags.questMaxRank or 40
    local questFilter = {}
    local selected = Flags.questQuests
    if type(selected) == "table" then
        for _, name in ipairs(selected) do
            local w = Quest.questWords[name]
            if w then questFilter[#questFilter + 1] = w end
        end
    end

    local matched, rest = {}, {}
    for _, btn in ipairs(uiButtons(Quest.claimWords, 60)) do
        if matchesAny(btn, questFilter) then
            matched[#matched + 1] = btn
        else
            rest[#rest + 1] = btn
        end
    end

    -- selected ranks go first, the rest still get claimed: a filter that
    -- silently does nothing is a dead widget
    local fired = 0
    for _, list in ipairs({ matched, rest }) do
        for _, btn in ipairs(list) do
            if fired >= maxRank then break end
            if PSX.click(btn) then fired = fired + 1 end
        end
    end

    local gifts = 0
    local giftSel = Flags.questGifts
    if type(giftSel) == "table" and #giftSel > 0 then
        local giftWords = {}
        for _, name in ipairs(giftSel) do
            giftWords[#giftWords + 1] = string.lower(name)
        end
        for _, btn in ipairs(uiButtons({ "gift" }, 12)) do
            if gifts >= 3 then break end
            if matchesAny(btn, giftWords) and PSX.click(btn) then
                gifts = gifts + 1
            end
        end
    end

    return fired, gifts
end

local function listKeys(reqs)
    local seen, out = {}, {}
    for _, r in ipairs(reqs) do
        if not seen[r.key] then
            seen[r.key] = true
            out[#out + 1] = r.key
        end
    end
    return table.concat(out, ", ")
end

function Quest.setStatus(text, color)
    Quest.status = text
    if questStatusLabel and questStatusLabel.Parent then
        questStatusLabel.Text = text
        if color then questStatusLabel.TextColor3 = color end
    end
end

-- the game's own quest button. Clicking it is how the panel opens, so the
-- player never has to press Read first.
function Quest.openPanel()
    local btn = PSX.findButton(Quest.panelWords)
    if not btn then return false end
    if not PSX.click(btn) then return false end
    Quest.openedAt = os.clock()
    return true
end

-- the match may be a TextLabel inside the area row; the clickable is the
-- GuiButton above it
local function clickable(inst)
    local node = inst
    while node and node ~= PG do
        if node:IsA("GuiButton") then return node end
        node = node.Parent
    end
    return nil
end

-- highest unlocked area the world map is offering
function Quest.bestArea(words)
    words = words or Quest.areaWords
    local best, bestNum = nil, -1
    eachGameGui(function(inst)
        if (inst:IsA("GuiButton") or inst:IsA("TextLabel")) and isShown(inst) then
            local text = cleanText(inst.Text or inst.Name or "")
            local low = string.lower(text)
            if #text >= 3 and #text <= 60 then
                local isArea = false
                for _, w in ipairs(words) do
                    if string.find(low, w, 1, true) then isArea = true break end
                end
                if isArea then
                    local locked = false
                    for _, w in ipairs(Quest.lockedWords) do
                        if string.find(low, w, 1, true) then locked = true break end
                    end
                    local num = tonumber(string.match(low, "(%d+)"))
                    if not locked and num and num > bestNum then
                        local target = clickable(inst)
                        if target then
                            bestNum, best = num, target
                        end
                    end
                end
            end
        end
        return nil
    end)
    return best, bestNum
end

-- when the map button does not teleport, fly the character to the part the
-- game names after that area
function Quest.flyTo(num)
    local hrp = root()
    if not hrp then return false end
    local c = LP.Character
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    if not hum then return false end

    local target, bestDist, seen = nil, nil, 0
    for _, obj in ipairs(workspace:GetDescendants()) do
        seen = seen + 1
        if seen > 12000 then break end
        if obj:IsA("BasePart") then
            local low = string.lower(obj.Name)
            local hasWord = false
            for _, w in ipairs(Quest.areaWords) do
                if string.find(low, w, 1, true) then hasWord = true break end
            end
            if hasWord and tonumber(string.match(low, "(%d+)")) == num then
                local d = (obj.Position - hrp.Position).Magnitude
                if not bestDist or d < bestDist then
                    bestDist, target = d, obj
                end
            end
        end
    end
    if not target then return false end

    local bv = new("BodyVelocity", {
        Name = "TupachupTravel",
        MaxForce = Vector3.new(1e5, 1e5, 1e5),
        Velocity = Vector3.zero,
    }, hrp)
    local started = os.clock()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if not hrp.Parent or os.clock() - started > 15 then
            conn:Disconnect()
            if bv.Parent then bv:Destroy() end
            return
        end
        local delta = target.Position - hrp.Position
        if delta.Magnitude < 7 then
            conn:Disconnect()
            if bv.Parent then bv:Destroy() end
            return
        end
        bv.Velocity = delta.Unit * math.min(140, delta.Magnitude * 2)
    end)
    track(conn)
    Quest.travelPart = target
    return true
end

-- travels to a named area number: the secret-key merchants sit behind a gate
-- at a fixed area, and the highest-unlocked rule would walk past them
function Quest.gotoArea(num, words)
    words = words or Quest.areaWords
    local key = "area" .. tostring(num)
    Quest.at = Quest.at or {}
    if Quest.at[key] and (os.clock() - Quest.at[key]) < 20 then return false end
    local found
    eachGameGui(function(inst)
        if (inst:IsA("GuiButton") or inst:IsA("TextLabel")) and isShown(inst) then
            local text = cleanText(inst.Text or inst.Name or "")
            local low = string.lower(text)
            if #text >= 3 and #text <= 60 then
                local hasWord = false
                for _, w in ipairs(words) do
                    if string.find(low, w, 1, true) then hasWord = true break end
                end
                local n = tonumber(string.match(low, "(%d+)"))
                if hasWord and n == num then
                    local target = clickable(inst)
                    if target then
                        found = target
                        return false
                    end
                end
            end
        end
        return nil
    end)
    if not found then return false end
    if not PSX.click(found) then return false end
    Quest.at[key] = os.clock()
    return true
end

-- moves the character with the game's own area button, never a guessed remote
function Quest.travel(force, words, key)
    key = key or "area"
    local btn, num = Quest.bestArea(words)
    if not btn then return false, 0 end
    Quest.travelState = Quest.travelState or {}
    local state = Quest.travelState[key] or {}
    Quest.travelState[key] = state
    local now = os.clock()
    if not force and state.num == num and (now - (state.at or 0)) < 45 then
        return false, num
    end
    if not PSX.click(btn) then return false, num end
    state.num, state.at = num, now

    -- the button may only open a preview; if the character has not moved in a
    -- second and a half, fly to the area part instead
    if Flags.questFly then
        local hrp = root()
        local startPos = hrp and hrp.Position
        task.delay(1.5, function()
            local hrpNow = root()
            if not hrpNow or not startPos then return end
            if (hrpNow.Position - startPos).Magnitude < 6 then
                pcall(Quest.flyTo, num)
            end
        end)
    end
    return true, num
end

function Quest.step()
    local reqs = Quest.read()

    -- nothing readable: click the game's quest button, then look again
    if #reqs == 0 then
        local now = os.clock()
        if Quest.panelAt and (now - Quest.panelAt) > 30 then
            Quest.panelTries = 0
        end
        if (Quest.panelTries or 0) < 3 and Quest.openPanel() then
            Quest.panelAt = now
            Quest.panelTries = (Quest.panelTries or 0) + 1
            Quest.setStatus("Opening the quest panel...", THEME.Accent)
            task.delay(0.7, function()
                if Flags.questAuto or Quest.manual then pcall(Quest.cycle) end
            end)
            return 0, 0, 0, {}
        end
        Quest.setStatus("No quest panel found. Open it once in game - the runner reads it from then on.", THEME.Red)
        return 0, 0, 0, {}
    end

    Quest.panelTries = 0

    local keys = {}
    for _, r in ipairs(reqs) do keys[r.key] = true end

    local applied = Quest.arm(keys, reqs)
    local travelled, area = false, 0
    if Flags.questTravel then
        travelled, area = Quest.travel()
    end
    local fired, gifts = Quest.claim()
    Quest.cycles = Quest.cycles + 1

    local tools = (#applied > 0) and table.concat(applied, ", ") or "already armed"
    Quest.setStatus(
        ("%d quests - %s - %s%s - claimed %d")
            :format(#reqs, reqs[1] and reqs[1].text or "?", tools,
                travelled and (" - area " .. area) or "", fired),
        THEME.Sub
    )

    return fired, gifts, #reqs, applied
end

-- a thrown step used to vanish inside the heartbeat pcall and leave the tab
-- looking dead; now the reason lands in the status line
function Quest.cycle()
    local ok, fired, gifts, count, applied = pcall(Quest.step)
    if not ok then
        Quest.setStatus("Runner error: " .. tostring(fired), THEME.Red)
        return 0, 0, 0, {}
    end
    return fired, gifts, count, applied
end

Features.questPass = function()
    Quest.manual = true
    task.delay(2, function() Quest.manual = false end)
    local fired, gifts, count = Quest.cycle()
    if count == 0 then
        notify("No quests read yet - opening the panel and retrying", "info", "Quest")
    else
        notify(("Quests: %d read, %d claimed, %d gifts - %s")
            :format(count, fired, gifts, listKeys(Quest.reqs)), "success", "Quest")
    end
    return fired
end

Features.questRead = function()
    local reqs = Quest.read()
    if #reqs == 0 then
        notify("No quest text found - open the Rank Quest panel first", "error")
        return 0
    end
    notify(("%d quest lines: %s"):format(#reqs, listKeys(reqs)), "success")
    Quest.setStatus(("%d quests (%s) - %s")
        :format(#reqs, listKeys(reqs), reqs[1] and reqs[1].text or ""), THEME.Accent)
    return #reqs
end

Features.questAuto = function(on)
    if not on then
        local restored = Quest.disarm()
        Quest.setStatus(("Idle. %d tool flag(s) restored."):format(restored), THEME.Sub)
        return
    end
    -- first cycle runs straight away so the toggle does something visible
    task.spawn(function()
        task.wait(0.4)
        if Flags.questAuto then pcall(Quest.cycle) end
    end)
end

local questAcc = 0
track(RunService.Heartbeat:Connect(function(dt)
    if not Flags.questAuto then return end
    questAcc = questAcc + (dt or 0)
    if questAcc < (Flags.questWait or 5) then return end
    questAcc = 0
    pcall(Quest.cycle)
end))

Stops.Quest = function()
    Flags.questAuto = false
    pcall(Quest.disarm)
end

end
-- ---------- QUEST ----------
do
local quest = addTab("Quest", "🏆", 12)

addSection(quest, "Rank Quest")
addSlider(quest, "Select Max Rank", 1, 40, 40, 1, "questMaxRank", nil, " Ranks")
addMultiSelect(quest, "Select Rank Quests",
    { "Daily", "Rank", "Clan", "Season", "Event", "Index" },
    { "Daily", "Rank", "Clan", "Season", "Event", "Index" }, "questQuests")
addSlider(quest, "Select Priority Quests Wait Time", 1, 30, 5, 1, "questWait", nil, " Seconds")
addMultiSelect(quest, "Select Gifts To Open If Necessary",
    { "Small Gift", "Medium Gift", "Large Gift", "Huge Gift", "Titanic Gift" },
    { "Small Gift", "Medium Gift", "Large Gift", "Huge Gift", "Titanic Gift" }, "questGifts")
addToggle(quest, "Auto Complete Selected Rank Quests", false, "questAuto", function(on)
    Features.questAuto(on)
end)
addToggle(quest, "Travel To Best Unlocked Area", true, "questTravel")
addToggle(quest, "Fly If The Area Button Does Not Move You", true, "questFly")

addButton(quest, "Read Rank Quests", THEME.Text, function() Features.questRead() end)
addButton(quest, "Complete Rank Quests Now", THEME.Accent, function() Features.questPass() end)

questStatusLabel = addNote(quest, "Idle. Switch Auto Complete on - the runner opens the panel itself.", THEME.Sub)
addNote(quest, "Reads the requirement lines, moves to the highest unlocked area, arms the matching farm tool, then claims. Tools restore when switched off.", THEME.Sub)

-- ---------- MAILBOX ----------
-- every extra tab lives in its own block so its locals are freed; the main
-- chunk is close to Lua's 200-local ceiling
do
local mail = addTab("Mailbox", "📬", 3)

addSection(mail, "Mailbox")
addButton(mail, "Open Mailbox", THEME.Text, function()
    if Auto.use({ "mailbox", "mail", "inbox" }, "openmail", 0) then
        notify("Mailbox opened", "info", "Mailbox")
    else
        notify("No mailbox button on screen - open it once in game", "error", "Mailbox")
    end
end)
addToggle(mail, "Auto Claim Mail", false, "autoMail")
addButton(mail, "Claim All Now", THEME.Accent, function()
    local hit = Auto.use({ "claim all", "collect all", "claim", "collect", "gift" }, "mailnow", 0)
    notify(hit and "Claim fired" or "No claim button found", hit and "success" or "error", "Mailbox")
end)
addNote(mail, "Looks for the game's own Claim / Collect buttons inside the mailbox window. Keeps a 3 second gap so a double click cannot skip a reward.", THEME.Sub)

-- ---------- CURRENT EVENT ----------
local ev = addTab("Current Event", "📅", 6)

addSection(ev, "Event")
addButton(ev, "Travel To Event Area", THEME.Accent, function()
    local moved, num = Quest.travel(true, { "event", "limited", "season", "current", "festival" }, "event")
    notify(moved and ("Moving to the event area" .. (num > 0 and (" " .. num) or "")) or "No event area button found",
        moved and "success" or "error", "Event")
end)
addToggle(ev, "Auto Claim Event Rewards", false, "autoEventReward")
addToggle(ev, "Auto Use Event Items", false, "autoEventUse")
addNote(ev, "The event area is found the same way the quest runner finds an area: the game's own labelled button, highest unlocked number first.", THEME.Sub)

-- ---------- FISHING WORLD ----------
local fish = addTab("Fishing World", "🎣", 8)

addSection(fish, "Travel")
addButton(fish, "Travel To Fishing World", THEME.Accent, function()
    local moved = Quest.travel(true, { "fishing", "fish", "ocean", "sea", "aqua" }, "fishing")
    notify(moved and "Moving to the fishing world" or "No fishing world button found",
        moved and "success" or "error", "Fishing")
end)

addSection(fish, "Automation")
addToggle(fish, "Auto Cast", false, "autoCast")
addToggle(fish, "Auto Reel", false, "autoReel")
addToggle(fish, "Auto Sell Fish", false, "autoSellFish")
addNote(fish, "Cast and reel are separate switches: some games want the cast button only, some fire the reel automatically. Sell only clicks a button that also mentions fish.", THEME.Sub)

-- ---------- FARMING WORLD ----------
local farmw = addTab("Farming World", "🚜", 9)

addSection(farmw, "Travel")
addButton(farmw, "Travel To Farming World", THEME.Accent, function()
    local moved = Quest.travel(true, { "farming", "farm", "garden", "plot", "ranch" }, "farming")
    notify(moved and "Moving to the farming world" or "No farming world button found",
        moved and "success" or "error", "Farming")
end)

addSection(farmw, "Automation")
addToggle(farmw, "Auto Plant", false, "autoPlant")
addToggle(farmw, "Auto Harvest", false, "autoHarvest")
addToggle(farmw, "Auto Water", false, "autoWater")
addToggle(farmw, "Auto Sell Crops", false, "autoSellCrop")
addNote(farmw, "Plant, harvest and water run on their own timers, so a slow plot animation cannot block the next action. Sell only fires a button that names crops, farm or garden.", THEME.Sub)

-- ---------- EGG ----------
local egg = addTab("Egg", "🥚", 11)

addSection(egg, "Hatching")
addToggle(egg, "Auto Hatch Egg", false, "autoHatch")
addSlider(egg, "Hatch Delay", 0.3, 10, 1, 0.1, "hatchDelay", nil, " Seconds")
addButton(egg, "Open All Eggs Now", THEME.Accent, function()
    local hit = Auto.use({ "open all", "hatch all", "open", "hatch" }, "openall", 0)
    notify(hit and "Egg button fired" or "No egg button found", hit and "success" or "error", "Egg")
end)

addSection(egg, "Pets")
addToggle(egg, "Auto Equip Best Pet", false, "autoEquipBest")
addNote(egg, "The hatch switch clicks whatever the game labels Hatch / Open / Egg. Lower the delay only if your executor keeps up - 1 second is safe on mobile.", THEME.Sub)

-- ---------- DAYCARE ----------
local day = addTab("Daycare", "🏫", 14)

addSection(day, "Daycare")
addButton(day, "Travel To Daycare", THEME.Text, function()
    local moved = Quest.travel(true, { "daycare", "day care", "nursery" }, "daycare")
    notify(moved and "Moving to the daycare" or "No daycare button found",
        moved and "success" or "error", "Daycare")
end)
addToggle(day, "Auto Collect Daycare", false, "autoDaycare")
addNote(day, "Collect only fires a button that also mentions daycare or pet, so a generic Claim elsewhere on screen cannot take the click.", THEME.Sub)

-- ---------- AUTOMATIC ----------
local autoTab = addTab("Automatic", "🤖", 15)

addSection(autoTab, "One Switch")
addToggle(autoTab, "Full Auto (Farm + Quest + Claims)", false, "autoFull", function(on)
    callSetter("fastFarm", on)
    callSetter("questAuto", on)
    callSetter("autoClaimAll", on)
    notify(on and "Full auto on: farm, quests and claims" or "Full auto off, tools restored",
        on and "success" or "info", "Automatic")
end)
addToggle(autoTab, "Auto Claim Everything", false, "autoClaimAll")
addToggle(autoTab, "Auto Sell Everything", false, "autoSellAll")
addNote(autoTab, "Full Auto is the three switches above it, wired together. Turning it off puts every tool back the way it was.", THEME.Sub)

-- ---------- MINIGAMES ----------
local mini = addTab("Minigames", "🎮", 16)

addSection(mini, "Minigames")
addButton(mini, "Travel To Minigames", THEME.Accent, function()
    local moved = Quest.travel(true, { "minigame", "minigames", "arena", "arcade", "game" }, "minigames")
    notify(moved and "Moving to the minigames" or "No minigame button found",
        moved and "success" or "error", "Minigames")
end)
addToggle(mini, "Auto Play Minigames", false, "autoMinigame")
addToggle(mini, "Auto Claim Minigame Rewards", false, "autoMinigameReward")
addNote(mini, "Play and claim only accept buttons whose label also mentions minigame, arena or arcade, so a lobby Claim cannot be mistaken for a reward.", THEME.Sub)
end

end
-- ---------- MISC ----------
-- ============================================================
-- PUMPKIN TYCOON  (ZapHub-shaped settings, one schema for UI and engine)
-- ============================================================
-- Settings is the source of truth. Every widget writes into it, the engine
-- reads it once per tick, and _G.TupachupSettings always mirrors what is on
-- screen. A ZapHub config pasted from another script is accepted verbatim:
-- the keys and the value shapes are the same.
local PT
do
PT = {
    last = {},
    seen = {},
    thrown = {},
    boostNote = nil,
    statGui = nil,
    white = nil,
}

local DEFAULTS = {
    NewPetsTracker = { Enable = true, WebhookURL = "", PetTypes = { "Gargantuan", "Titanic", "Huge", "Exclusive" } },
    NewPetsMailer = { Enable = true, Username = "", PetTypes = { "Gargantuan", "Titanic", "Huge", "Exclusive" } },
    ClaimMailbox = { Enable = true },
    Optimization = { Enable = true },
    PumpkinTycoonMovement = { Mode = "Legit Walk" },
    OptimizePumpkinTycoon = { Enable = true, Optimizations = { "Destroy Island Decoration", "Destroy Pumpkin Effects" } },
    TeleportToBestPumpkinEggArea = { Enable = true },
    BuyPumpkinTycoonButtons = { Enable = true },
    BuyNearestPumpkinEgg = { Enable = true, MaximumPetsPerArea = 100, KeepLastEggLimit = true },
    KeepPumpkins = { Enable = true, Rarity = "Mythical+" },
    BreakPumpkins = { Enable = true },
    BuyMerchantPumpkins = { Enable = true, Bands = { "Rare+ Pumpkin", "Epic+ Pumpkin", "Legendary+ Pumpkin", "Mythical+ Pumpkin", "Exotic+ Pumpkin" } },
    PlantMerchantPumpkins = { Enable = true, MaximumSeconds = 5 },
    BuyPumpkinUpgrades = { Enable = true, Upgrades = { "Spawn Luck", "Patch Coin Payout", "Pumpkin Damage", "Faster Spawns", "Merchant Stock", "Pumpkin Chase Odds", "Island Luck", "Merchant Luck" } },
    BuyHotCocoaBoosts = { Enable = true, Boosts = { "Patch Coin Boost", "Pumpkin Damage Boost", "Island Luck Boost" }, MinimumMinutes = 15, OnlyWhenButtonsDone = true },
    UsePumpkinBoosts = { Enable = true, Boosts = { "Patch Coin Boost", "Pumpkin Damage Boost", "Island Luck Boost" } },
    OpenFlannelGifts = { Enable = true },
    InfinitePetSpeed = { Enable = true },
    Tap = { Enable = true, Mode = "Random" },
    EfficientFarm = { Enable = true },
    CollectOrbs = { Enable = true },
    DisableEggAnimation = { Enable = true },
    MakePetsGold = { Enable = false },
    MakePetsRainbow = { Enable = false },
    ClaimFreeGifts = { Enable = true },
    ClaimDefaultForeverPackFreeGift = { Enable = true },
    UseFruits = { Enable = true, Fruits = { "Apple", "Orange", "Banana", "Pineapple", "Watermelon", "Candycane", "Rainbow" }, Amount = 3, Type = "Normal" },
    UseBuffs = { Enable = true, Buffs = { "Diamond Pencil", "Ultra Pet Token Boost", "Christmas Cookie", "Super Rng Chest Luck", "Squeaky Toy", "Ultra Adoption Token Boost", "Ultra Grinch-B-Gone", "Ultra Rng Chest V2 Luck", "Lucky Tile", "Ultra Lucky Tile", "Rng Chest V2 Luck", "Ultra Rng Chest Luck", "Mega Chest Empowered", "Grinch-B-Gone", "Super Rng Chest V2 Luck", "Adoption Token Boost", "Golden Pencil", "Nightmare Fuel", "Mega Rng Chest Luck", "Hot Cocoa", "Rng Chest Luck", "Glitched Drive", "Toy Ball", "Rainbow Pencil", "Pet Token Boost", "Toy Bone" } },
    UsePotions = { Enable = true, Potions = { "Coins", "Lucky", "The Cocktail", "Huge", "Treasure Hunter", "Walkspeed", "Diamonds", "Damage" } },
    EquipEnchants = { Enable = true, Enchants = { "Coins", "Criticals", "Strong Pets", "Tap Power", "Lucky Eggs" } },
    Rejoin = { Enable = false, Time = 5 },
    WhiteScreen = { Enable = false },
    StatGUI = { Enable = true, Items = {
        { Class = "Currency", Item = "Diamonds" },
        { Class = "Currency", Item = "PumpkinTycoonCoins" },
        { Class = "Currency", Item = "PumpkinTokens" },
        { Class = "Lootbox", Item = "Flannel Gift" },
    } },
}

local function copyTable(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, sub in pairs(v) do out[k] = copyTable(sub) end
    return out
end

-- fills only what the incoming table is missing: a config that leaves a key
-- out keeps the default instead of crashing the engine on a nil index
local function mergeInto(dst, src)
    for k, v in pairs(src or {}) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            mergeInto(dst[k], v)
        else
            dst[k] = v
        end
    end
    return dst
end

local Settings = copyTable(DEFAULTS)
if type(_G.TupachupSettings) == "table" then mergeInto(Settings, _G.TupachupSettings) end
if type(_G.ZapHubSettings) == "table" then mergeInto(Settings, _G.ZapHubSettings) end
_G.TupachupSettings = Settings
PT.settings = Settings

-- dot path write, so a widget can say "BuyNearestPumpkinEgg.Enable" and stay
-- one line without a table of closures per key
local function setPath(path, value)
    local node, parts = Settings, {}
    for seg in tostring(path):gmatch("[^%.]+") do parts[#parts + 1] = seg end
    if #parts == 0 then return end
    for i = 1, #parts - 1 do
        local seg = parts[i]
        if type(node[seg]) ~= "table" then node[seg] = {} end
        node = node[seg]
    end
    node[parts[#parts]] = value
    _G.TupachupSettings = Settings
    return value
end
PT.setPath = setPath
PT.cfg = function(key) return Settings[key] or {} end

-- throttle shared by every PT feature: key -> minimum seconds between runs
local function gate(key, seconds)
    local now = os.clock()
    local last = PT.last[key]
    if last and (now - last) < seconds then return false end
    PT.last[key] = now
    return true
end
PT.gate = gate



-- ============================================================
-- MOVEMENT  ("Teleport" or "Legit Walk", used by every event feature)
-- ============================================================
local function travelTo(target, done)
    if not target then return false end
    local _, hum = char()
    local hrp = root()
    if not (hrp and hum) then return false end
    local dest = target.Position or target
    local mode = (PT.cfg("PumpkinTycoonMovement").Mode or "Legit Walk")

    if mode == "Teleport" then
        hrp.CFrame = CFrame.new(dest + Vector3.new(0, 4, 0))
        if done then task.spawn(done) end
        return true
    end

    task.spawn(function()
        local tries = 0
        while tries < 120 do
            tries = tries + 1
            local _, h = char()
            local r = root()
            if not (h and r) or not r.Parent then break end
            local flat = Vector3.new(dest.X, r.Position.Y, dest.Z)
            if (r.Position - flat).Magnitude < 6 then break end
            h:MoveTo(flat)
            task.wait(0.1)
        end
        if done then pcall(done) end
    end)
    return true
end
PT.travelTo = travelTo

-- ============================================================
-- FINDERS  (labels and parts, never a guessed remote)
-- ============================================================
local function clickWords(words, key, seconds, avoid, context)
    return Auto.use(words, "pt" .. key, seconds, avoid, context)
end
PT.clickWords = clickWords

local function findPart(words, avoid)
    local best, bestDist = nil, nil
    local hrp = root()
    local origin = hrp and hrp.Position or Vector3.zero
    local scanned = 0
    for _, obj in ipairs(workspace:GetDescendants()) do
        scanned = scanned + 1
        if scanned > 14000 then break end
        if obj:IsA("BasePart") then
            local low = string.lower(obj.Name)
            local hit = false
            for _, w in ipairs(words) do
                if string.find(low, w, 1, true) then hit = true break end
            end
            if hit then
                local bad = false
                for _, w in ipairs(avoid or {}) do
                    if string.find(low, w, 1, true) then bad = true break end
                end
                if not bad then
                    local d = (obj.Position - origin).Magnitude
                    if not bestDist or d < bestDist then best, bestDist = obj, d end
                end
            end
        end
    end
    return best
end
PT.findPart = findPart

-- a proximity prompt is the only click a lot of event objects accept
local function promptPart(part)
    if not part then return false end
    local prompt = part:FindFirstChildWhichIsA("ProximityPrompt", true)
    if not prompt then
        local model = part.Parent
        if model then prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true) end
    end
    if not prompt then return false end
    if type(fireproximityprompt) == "function" then
        local ok = pcall(fireproximityprompt, prompt)
        if ok then return true end
    end
    pcall(function() prompt:InputHoldBegin() end)
    return true
end
PT.promptPart = promptPart

-- ============================================================
-- NEW PETS  (tracker + mailer share one scan)
-- ============================================================
local PET_TAG = { "pet", "huge", "titanic", "gargantuan", "exclusive" }

local function petTypeOf(name)
    local low = string.lower(name)
    local tagged = false
    for _, tag in ipairs(PET_TAG) do
        if string.find(low, tag, 1, true) then tagged = true break end
    end
    if not tagged then return nil end
    local types = PT.cfg("NewPetsTracker").PetTypes or {}
    for _, t in ipairs(types) do
        if string.find(low, string.lower(t), 1, true) then return t end
    end
    return nil
end

local function post(url, body)
    if url == nil or url == "" then return false end
    local payload = HttpService:JSONEncode(body)
    if type(request) == "function" then
        local ok = pcall(request, { Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = payload })
        return ok
    end
    if type(syn) == "table" and type(syn.request) == "function" then
        local ok = pcall(syn.request, { Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = payload })
        return ok
    end
    return false
end

local function scanPets()
    local found = {}
    local scanned = 0
    for _, obj in ipairs(workspace:GetDescendants()) do
        scanned = scanned + 1
        if scanned > 16000 then break end
        if obj:IsA("Model") or obj:IsA("Tool") then
            local kind = petTypeOf(obj.Name)
            if kind then
                -- GetDebugId separates two pets with the same name
                local ident
                if type(obj.GetDebugId) == "function" then
                    local okId, id = pcall(obj.GetDebugId, obj)
                    if okId and id then ident = tostring(id) end
                end
                local key = obj.Name .. "#" .. (ident or obj.Name)
                if not PT.seen[key] then
                    PT.seen[key] = os.clock()
                    found[#found + 1] = { name = obj.Name, kind = kind, inst = obj }
                end
            end
        end
    end
    -- forget pets that vanished, so a re-summon counts again
    for key, at in pairs(PT.seen) do
        if os.clock() - at > 180 then PT.seen[key] = nil end
    end
    return found
end

local function reportPets(hits)
    if #hits == 0 then return end
    local tracker, mailer = PT.cfg("NewPetsTracker"), PT.cfg("NewPetsMailer")

    if tracker.Enable then
        for _, hit in ipairs(hits) do
            notify(hit.kind .. ": " .. hit.name, "success", "New pet")
            post(tracker.WebhookURL, {
                username = "Tupachup",
                content = "**New " .. hit.kind .. "** `" .. hit.name .. "` in " .. tostring(game.Name),
            })
        end
    end

    if mailer.Enable then
        local who = mailer.Username ~= "" and ("@" .. mailer.Username .. " ") or ""
        for _, hit in ipairs(hits) do
            notify(who .. hit.kind .. ": " .. hit.name, "info", "Mailer")
        end
    end
end

-- ============================================================
-- STAT GUI  (reads the numbers the game already draws)
-- ============================================================
local function readStat(item)
    local want = string.lower(item)
    local value
    eachGameGui(function(inst)
        if inst:IsA("TextLabel") and isShown(inst) then
            local text = string.lower(inst.Text or "")
            if string.find(text, want, 1, true) then
                local num = string.match(inst.Text, "[%d,]+")
                if num then value = num return false end
            end
            local parent = inst.Parent
            if parent and string.find(string.lower(parent.Name), want, 1, true) then
                local num = string.match(inst.Text or "", "[%d,]+")
                if num and #num > 0 then value = num return false end
            end
        end
        return nil
    end)
    return value
end
PT.readStat = readStat

local function buildStatGui()
    if PT.statGui then return end
    local holder = new("ScreenGui", {
        Name = "TupachupStats",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 480,
    }, PG)
    PT.statGui = holder

    local box = new("Frame", {
        Size = UDim2.fromOffset(186, 26),
        Position = UDim2.new(0, 12, 0, 12),
        BackgroundColor3 = THEME.Panel,
        BorderSizePixel = 0,
    }, holder)
    new("UICorner", { CornerRadius = UDim.new(0, 8) }, box)
    new("UIStroke", { Color = THEME.Accent, Thickness = 1, Transparency = 0.6 }, box)

    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundTransparency = 1,
    }, box)
    local rows = {}
    PT.statRows = rows
    for i, entry in ipairs((PT.cfg("StatGUI").Items) or {}) do
        local cell
        if i == 1 then
            cell = new("Frame", { Size = UDim2.new(1, -8, 0, 26), Position = UDim2.fromOffset(4, 0), BackgroundTransparency = 1 }, row)
        else
            cell = new("Frame", {
                Size = UDim2.new(1, -8, 0, 22),
                Position = UDim2.fromOffset(4, 26 + (i - 2) * 22),
                BackgroundTransparency = 1,
            }, box)
        end
        rows[i] = new("TextLabel", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = entry.Item .. ": ...",
            TextXAlignment = Enum.TextXAlignment.Left,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextColor3 = i == 1 and THEME.Accent or THEME.Text,
        }, cell)
    end

    box.Size = UDim2.fromOffset(186, 26 + math.max(0, #rows - 1) * 22)
end

local function updateStatGui()
    if not PT.statGui then return end
    local items = (PT.cfg("StatGUI").Items) or {}
    for i, entry in ipairs(items) do
        local label = PT.statRows and PT.statRows[i]
        if label then
            label.Text = entry.Item .. ": " .. (readStat(entry.Item) or "-")
        end
    end
end

-- ============================================================
-- TICK  (one pass, reads Settings, calls each feature)
-- ============================================================
local RARITY = { ["Off"] = 0, ["Rare+"] = 1, ["Epic+"] = 2, ["Legendary+"] = 3, ["Mythical+"] = 4, ["Exotic+"] = 5, ["Divine+"] = 6, ["Secret+"] = 7 }

local function rarityAtLeast(name, want)
    local floor = RARITY[want] or 0
    if floor == 0 then return false end
    local order = { "rare", "epic", "legendary", "mythical", "exotic", "divine", "secret" }
    local low = string.lower(name or "")
    for i, word in ipairs(order) do
        if string.find(low, word, 1, true) then return i >= floor end
    end
    return false
end
PT.rarityAtLeast = rarityAtLeast

function PT.tick(dt)
    local s = Settings

    -- pets: tracker and mailer share one scan
    if (s.NewPetsTracker.Enable or s.NewPetsMailer.Enable) and gate("pets", 2) then
        pcall(function() reportPets(scanPets()) end)
    end

    if s.ClaimMailbox.Enable and gate("mail", 4) then
        clickWords({ "claim all", "collect all", "claim", "collect" }, "mail", 4)
    end

    if s.Optimization.Enable and gate("optim", 20) then
        pcall(function() Features.lowGraphics(true) end)
    end

    if s.TeleportToBestPumpkinEggArea.Enable and gate("bestarea", 6) then
        local ok = pcall(Quest.travel, false, Quest.areaWords, "area")
        if not ok then clickWords({ "area" }, "bestarea", 6) end
    end

    if s.BuyPumpkinTycoonButtons.Enable and gate("buybuttons", 3) then
        local clicked = clickWords({ "buy", "unlock", "purchase" }, "buybuttons", 3)
        -- nothing left to buy for a full minute means the buttons are done,
        -- which is the gate BuyHotCocoaBoosts waits on
        if clicked then
            PT.buttonsDone, PT.buttonsIdle = true, 0
        else
            PT.buttonsIdle = (PT.buttonsIdle or 0) + 1
            if PT.buttonsIdle > 20 then PT.buttonsDone = true end
        end
    end

    if s.BuyNearestPumpkinEgg.Enable and gate("egg", 2) then
        clickWords({ "egg", "hatch", "open" }, "egg", 2)
    end

    -- the kept pumpkin is whichever one clears the rarity bar. BreakPumpkins
    -- reads the same test and skips it, so a rare pumpkin is never touched.

    if s.BreakPumpkins.Enable and gate("break", 1.2) then
        local part = findPart({ "pumpkin" }, { "seed", "shop", "icon" })
        if part then
            local keep = s.KeepPumpkins.Enable and rarityAtLeast(part.Name, s.KeepPumpkins.Rarity)
            if not keep then pcall(promptPart, part) end
        end
    end

    if s.BuyMerchantPumpkins.Enable and gate("merchant", 4) then
        local bands = s.BuyMerchantPumpkins.Bands or {}
        for _, band in ipairs(bands) do
            local words = {}
            for w in string.gmatch(string.lower(band), "%a+") do words[#words + 1] = w end
            if #words > 0 then
                if clickWords(words, "merchant_" .. band, 4, nil, { "merchant" }) then break end
            end
        end
    end

    if s.PlantMerchantPumpkins.Enable and gate("plant", 3) then
        clickWords({ "plant" }, "plant", 3, nil, { "pedestal", "stand", "merchant" })
    end

    if s.BuyPumpkinUpgrades.Enable and gate("upgrade", 5) then
        for _, name in ipairs(s.BuyPumpkinUpgrades.Upgrades or {}) do
            local words = {}
            for w in string.gmatch(string.lower(name), "%a+") do words[#words + 1] = w end
            if #words > 1 then
                if clickWords(words, "upgrade_" .. name, 5) then break end
            end
        end
    end

    if s.BuyHotCocoaBoosts.Enable and gate("cocoa", 6) then
        local cfg = s.BuyHotCocoaBoosts
        local okToGo = true
        if cfg.OnlyWhenButtonsDone then
            okToGo = PT.buttonsDone == true
        end
        if okToGo then
            for _, name in ipairs(cfg.Boosts or {}) do
                local words = {}
                for w in string.gmatch(string.lower(name), "%a+") do words[#words + 1] = w end
                if #words > 1 and clickWords(words, "cocoa_" .. name, 6) then break end
            end
        end
    end

    if s.UsePumpkinBoosts.Enable and gate("useboost", 8) then
        for _, name in ipairs(s.UsePumpkinBoosts.Boosts or {}) do
            local words = {}
            for w in string.gmatch(string.lower(name), "%a+") do words[#words + 1] = w end
            if #words > 1 then clickWords(words, "useboost_" .. name, 8, { "buy" }) end
        end
    end

    if s.OpenFlannelGifts.Enable and gate("flannel", 5) then
        clickWords({ "flannel", "gift" }, "flannel", 5, { "send" })
    end

    if s.ClaimFreeGifts.Enable and gate("freegift", 6) then
        clickWords({ "free gift", "freebie", "claim" }, "freegift", 6, { "rank" })
    end

    if s.ClaimDefaultForeverPackFreeGift.Enable and gate("forever", 8) then
        clickWords({ "forever", "free gift" }, "forever", 8)
    end

    if s.DisableEggAnimation.Enable and gate("eggskip", 2) then
        clickWords({ "skip", "fast hatch", "disable animation" }, "eggskip", 2)
    end

    if s.MakePetsGold.Enable and gate("gold", 5) then
        clickWords({ "gold" }, "gold", 5)
    end
    if s.MakePetsRainbow.Enable and gate("rainbow", 5) then
        clickWords({ "rainbow" }, "rainbow", 5)
    end

    -- consumables: open the bag once, then click the named items
    local bags = {
        { "UseFruits", "Fruits", "fruit" },
        { "UseBuffs", "Buffs", "buff" },
        { "UsePotions", "Potions", "potion" },
        { "EquipEnchants", "Enchants", "enchant" },
    }
    for _, bag in ipairs(bags) do
        local cfg = s[bag[1]]
        if cfg and cfg.Enable and #(cfg[bag[2]] or {}) > 0 and gate("bag_" .. bag[3], 6) then
            local opened = clickWords({ bag[3], "inventory", "bag" }, "open_" .. bag[3], 6)
            if opened then
                local items = cfg[bag[2]]
                for _, name in ipairs(items) do
                    clickWords({ string.lower(name) }, "use_" .. bag[3] .. "_" .. name, 6)
                end
            end
        end
    end

    -- interface
    if s.StatGUI.Enable then
        if not PT.statGui then buildStatGui() end
        if gate("stats", 1) then updateStatGui() end
    elseif PT.statGui then
        PT.statGui:Destroy()
        PT.statGui, PT.statRows = nil, nil
    end

    if s.WhiteScreen.Enable then
        if not PT.white then
            PT.white = new("ScreenGui", { Name = "TupachupWhite", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 470 }, PG)
            new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, PT.white)
        end
    elseif PT.white then
        PT.white:Destroy()
        PT.white = nil
    end

    if s.Rejoin.Enable and gate("rejoin", 1) then
        PT.rejoinAt = PT.rejoinAt or (os.clock() + (s.Rejoin.Time or 5) * 60)
        if os.clock() >= PT.rejoinAt then
            PT.rejoinAt = nil
            pcall(Features.rejoin)
        end
    else
        PT.rejoinAt = nil
    end
end

-- OptimizePumpkinTycoon is a one-shot sweep, not a tick job: decorations and
-- effects go away and stay away.
function PT.optimizePumpkinTycoon()
    local cfg = PT.cfg("OptimizePumpkinTycoon")
    if not cfg.Enable then return 0 end
    local removed, scanned = 0, 0
    local words = { "decoration", "islanddeco", "pumpkineffect", "particle", "smoke", "sparkle" }
    for _, obj in ipairs(workspace:GetDescendants()) do
        scanned = scanned + 1
        if scanned > 14000 then break end
        local low = string.lower(obj.Name)
        for _, w in ipairs(words) do
            if string.find(low, w, 1, true) then
                if obj:IsA("ParticleEmitter") or obj:IsA("Beam") or obj:IsA("Trail") or obj:IsA("Fire") or obj:IsA("Smoke") then
                    obj.Enabled = false
                    removed = removed + 1
                elseif obj:IsA("BasePart") and string.find(low, "deco", 1, true) then
                    obj.Transparency = 1
                    removed = removed + 1
                end
                break
            end
        end
    end
    return removed
end

-- ============================================================
-- UI  (one control per settings key)
-- ============================================================
local pt = addTab("Pumpkin Tycoon", "🎃", 7)

local function bindToggle(key, label, flag, default)
    local cfg = Settings[key]
    addToggle(pt, label, cfg.Enable == true, flag, function(v)
        setPath(key .. ".Enable", v)
    end)
end

addSection(pt, "Auto Farm")
bindToggle("InfinitePetSpeed", "Infinite Pet Speed", "ptInfinitePetSpeed")
addDropdown(pt, "Auto Tap Mode", function() return { "Random", "Center", "Edges" } end, Settings.Tap.Mode or "Random", "ptTapMode", function(v)
    setPath("Tap.Mode", v)
end)
bindToggle("Tap", "Auto Tap", "ptTap")
bindToggle("EfficientFarm", "Efficient Farm", "ptEfficient")
bindToggle("CollectOrbs", "Collect Orbs", "ptOrbs")

addSection(pt, "Eggs")
bindToggle("DisableEggAnimation", "Disable Egg Animation", "ptEggAnim")
bindToggle("BuyNearestPumpkinEgg", "Buy Nearest Egg", "ptBuyEgg")
addSlider(pt, "Max Pets Per Area", 1, 100, Settings.BuyNearestPumpkinEgg.MaximumPetsPerArea or 100, 1, "ptMaxPets", function(v)
    setPath("BuyNearestPumpkinEgg.MaximumPetsPerArea", v)
end)
addToggle(pt, "Keep Last Egg Limit", Settings.BuyNearestPumpkinEgg.KeepLastEggLimit == true, "ptKeepLimit", function(v)
    setPath("BuyNearestPumpkinEgg.KeepLastEggLimit", v)
end)
bindToggle("BuyPumpkinTycoonButtons", "Buy Area Buttons", "ptBuyButtons")
bindToggle("TeleportToBestPumpkinEggArea", "Teleport To Best Area", "ptBestArea")
addDropdown(pt, "Movement Mode", function() return { "Legit Walk", "Teleport" } end, Settings.PumpkinTycoonMovement.Mode or "Legit Walk", "ptMoveMode", function(v)
    setPath("PumpkinTycoonMovement.Mode", v)
end)

addSection(pt, "Pumpkins")
bindToggle("KeepPumpkins", "Keep Pumpkins", "ptKeep")
addDropdown(pt, "Keep Rarity", function()
    return { "Off", "Rare+", "Epic+", "Legendary+", "Mythical+", "Exotic+", "Divine+", "Secret+" }
end, Settings.KeepPumpkins.Rarity or "Mythical+", "ptKeepRarity", function(v)
    setPath("KeepPumpkins.Rarity", v)
end)
bindToggle("BreakPumpkins", "Break Pumpkins", "ptBreak")

addSection(pt, "Merchant")
bindToggle("BuyMerchantPumpkins", "Buy Merchant Pumpkins", "ptMerchant")
addMultiSelect(pt, "Merchant Bands", {
    "Rare+ Pumpkin", "Epic+ Pumpkin", "Legendary+ Pumpkin", "Mythical+ Pumpkin", "Exotic+ Pumpkin",
}, Settings.BuyMerchantPumpkins.Bands, "ptMerchantBands", function(list)
    setPath("BuyMerchantPumpkins.Bands", list)
end)
bindToggle("PlantMerchantPumpkins", "Plant On Pedestal", "ptPlant")
addSlider(pt, "Pedestal Freshness", 1, 60, Settings.PlantMerchantPumpkins.MaximumSeconds or 5, 1, "ptPlantSecs", function(v)
    setPath("PlantMerchantPumpkins.MaximumSeconds", v)
end, " s")

addSection(pt, "Upgrades")
bindToggle("BuyPumpkinUpgrades", "Buy Upgrades", "ptUpgrades")
addMultiSelect(pt, "Upgrade List", {
    "Spawn Luck", "Patch Coin Payout", "Pumpkin Damage", "Faster Spawns",
    "Merchant Stock", "Pumpkin Chase Odds", "Island Luck", "Merchant Luck",
}, Settings.BuyPumpkinUpgrades.Upgrades, "ptUpgradeList", function(list)
    setPath("BuyPumpkinUpgrades.Upgrades", list)
end)

addSection(pt, "Boosts")
bindToggle("BuyHotCocoaBoosts", "Buy Hot Cocoa Boosts", "ptCocoa")
addMultiSelect(pt, "Cocoa Boosts", {
    "Patch Coin Boost", "Pumpkin Damage Boost", "Island Luck Boost",
}, Settings.BuyHotCocoaBoosts.Boosts, "ptCocoaList", function(list)
    setPath("BuyHotCocoaBoosts.Boosts", list)
end)
addSlider(pt, "Minimum Minutes", 1, 720, Settings.BuyHotCocoaBoosts.MinimumMinutes or 15, 1, "ptCocoaMins", function(v)
    setPath("BuyHotCocoaBoosts.MinimumMinutes", v)
end, " min")
addToggle(pt, "Only When Buttons Done", Settings.BuyHotCocoaBoosts.OnlyWhenButtonsDone == true, "ptCocoaGate", function(v)
    setPath("BuyHotCocoaBoosts.OnlyWhenButtonsDone", v)
end)
bindToggle("UsePumpkinBoosts", "Use Boosts", "ptUseBoost")

addSection(pt, "Gifts")
bindToggle("OpenFlannelGifts", "Open Flannel Gifts", "ptFlannel")

addSection(pt, "Pets")
addToggle(pt, "Make Pets Gold", Settings.MakePetsGold.Enable == true, "ptGold", function(v) setPath("MakePetsGold.Enable", v) end)
addToggle(pt, "Make Pets Rainbow", Settings.MakePetsRainbow.Enable == true, "ptRainbow", function(v) setPath("MakePetsRainbow.Enable", v) end)

addSection(pt, "Consumables")
bindToggle("UseFruits", "Use Fruits", "ptFruits")
addMultiSelect(pt, "Fruit List", {
    "Apple", "Orange", "Banana", "Pineapple", "Watermelon", "Candycane", "Rainbow",
}, Settings.UseFruits.Fruits, "ptFruitList", function(list) setPath("UseFruits.Fruits", list) end)
addDropdown(pt, "Fruit Type", function() return { "Normal", "Golden", "Rainbow" } end, Settings.UseFruits.Type or "Normal", "ptFruitType", function(v)
    setPath("UseFruits.Type", v)
end)
bindToggle("UseBuffs", "Use Buffs", "ptBuffs")
addMultiSelect(pt, "Buff List", Settings.UseBuffs.Buffs, Settings.UseBuffs.Buffs, "ptBuffList", function(list) setPath("UseBuffs.Buffs", list) end)
bindToggle("UsePotions", "Use Potions", "ptPotions")
addMultiSelect(pt, "Potion List", Settings.UsePotions.Potions, Settings.UsePotions.Potions, "ptPotionList", function(list) setPath("UsePotions.Potions", list) end)
bindToggle("EquipEnchants", "Equip Enchants", "ptEnchants")
addMultiSelect(pt, "Enchant List", Settings.EquipEnchants.Enchants, Settings.EquipEnchants.Enchants, "ptEnchantList", function(list) setPath("EquipEnchants.Enchants", list) end)

addSection(pt, "Webhook")
addTextbox(pt, "Tracker Webhook", "https://discord.com/api/webhooks/...", "ptWebhook", function(text)
    setPath("NewPetsTracker.WebhookURL", text)
end)
addTextbox(pt, "Mailer Username", "your discord name", "ptMailerName", function(text)
    setPath("NewPetsMailer.Username", text)
end)
addToggle(pt, "New Pets Tracker", Settings.NewPetsTracker.Enable == true, "ptTracker", function(v) setPath("NewPetsTracker.Enable", v) end)
addToggle(pt, "New Pets Mailer", Settings.NewPetsMailer.Enable == true, "ptMailer", function(v) setPath("NewPetsMailer.Enable", v) end)

addSection(pt, "Interface")
bindToggle("Optimization", "Optimization", "ptOptim")
addToggle(pt, "Optimize Pumpkin Tycoon", Settings.OptimizePumpkinTycoon.Enable == true, "ptPT", function(v)
    setPath("OptimizePumpkinTycoon.Enable", v)
    if v then
        local n = PT.optimizePumpkinTycoon()
        notify(n .. " decorations and effects cleared", "success", "Pumpkin Tycoon")
    end
end)
addToggle(pt, "Stat GUI", Settings.StatGUI.Enable == true, "ptStats", function(v) setPath("StatGUI.Enable", v) end)
addToggle(pt, "White Screen", Settings.WhiteScreen.Enable == true, "ptWhite", function(v) setPath("WhiteScreen.Enable", v) end)
addToggle(pt, "Auto Rejoin", Settings.Rejoin.Enable == true, "ptRejoin", function(v) setPath("Rejoin.Enable", v) end)
addSlider(pt, "Rejoin Minutes", 1, 720, Settings.Rejoin.Time or 5, 1, "ptRejoinMin", function(v)
    setPath("Rejoin.Time", v)
end, " min")

addSection(pt, "Settings")
addButton(pt, "Export Settings", THEME.Accent, function()
    local body = HttpService:JSONEncode(Settings)
    if copy(body) then
        notify("Settings copied as JSON", "success", "Pumpkin Tycoon")
    else
        notify("No clipboard on this executor", "error")
    end
end)
addButton(pt, "Print Settings", THEME.Text, function()
    print("[TUPACHUP SETTINGS] " .. HttpService:JSONEncode(Settings))
    notify("Settings printed to console", "info")
end)

-- paste a ZapHub config straight in: the shapes are the same, so a merge is
-- enough and anything missing keeps its default
local pasteBox = addTextbox(pt, "Paste ZapHub Config", "_G.ZapHubSettings = {...}", "ptPaste")
addButton(pt, "Import Config", THEME.Green, function()
    local raw = pasteBox.Text or ""
    local body = raw:match("ZapHubSettings%s*=%s*(%b{})") or raw:match("TupachupSettings%s*=%s*(%b{})") or raw
    if type(loadstring) ~= "function" then
        notify("This executor has no loadstring", "error")
        return
    end
    local chunk = loadstring("return " .. body)
    if not chunk then notify("Could not parse that table", "error") return end
    local ok, parsed = pcall(chunk)
    if not ok or type(parsed) ~= "table" then
        notify("That is not a settings table", "error")
        return
    end
    mergeInto(Settings, parsed)
    _G.TupachupSettings = Settings
    for flag, setter in pairs(Setters) do
        if Flags[flag] ~= nil then pcall(setter, Flags[flag]) end
    end
    notify("Config imported and applied", "success", "Pumpkin Tycoon")
end)

flush(pt)

-- the tick: one heartbeat, every feature reads Settings. The accumulator lives
-- on PT so the chunk stays under Lua's 200-local ceiling.
track(RunService.Heartbeat:Connect(function(dt)
    PT.acc = (PT.acc or 0) + (dt or 0)
    if PT.acc < 0.2 then return end
    PT.acc = 0
    pcall(PT.tick, dt)
end))
end

local misc = addTab("Misc", "🎛️", 18)

addSection(misc, "Protection")
addToggle(misc, "Anti-Kick", false, "antiKick", function(v) Features.antiKick(v) end)
addToggle(misc, "Hide Hub From Game", true, "hideGui", function(v) Features.hideGui(v) end)
addToggle(misc, "Lock GUI", true, "lockGui", function(v) Features.lockGui(v) end)
addNote(misc, "Anti-Kick blocks local Kick() calls only. Hide Hub moves the UI out of PlayerGui.", THEME.Sub)

addSection(misc, "Server")
addButton(misc, "Rejoin", THEME.Text, function() Features.rejoin() end)
addButton(misc, "Server Hop", THEME.Text, function() Features.hop() end)
local jobBox = addTextbox(misc, "JobId", "paste job id", "jobId")
addButton(misc, "Join Instance", THEME.Text, function() Features.joinJob(jobBox.Text) end)
addButton(misc, "Copy JobId", THEME.Text, function() Features.copyJob() end)
addButton(misc, "Copy PlaceId", THEME.Text, function() Features.copyPlace() end)

-- ---------- MISC + SETTINGS ----------
local set = misc
addSection(set, "Interface")
addSlider(set, "UI Transparency", 0, 60, 0, 5, "uiAlpha", function(v)
    gui.Enabled = true
    for _, inst in ipairs(window:GetDescendants()) do
        if inst:IsA("Frame") or inst:IsA("TextButton") or inst:IsA("ScrollingFrame") then
            if inst.BackgroundTransparency < 0.99 and inst.Name ~= "Knob" then
                inst:SetAttribute("BaseTransparency", inst:GetAttribute("BaseTransparency") or inst.BackgroundTransparency)
                inst.BackgroundTransparency = clamp(inst:GetAttribute("BaseTransparency") + v / 100, 0, 0.95)
            end
        end
    end
end)
addToggle(set, "Notifications", true, "notifications", function(v) notifyOn = v end)
addKeybind(set, "Menu Key", Enum.KeyCode.RightShift, "menuKey", function(key) menuKey = key end)

addSection(set, "Premium")
addNote(set, "Key: " .. (Premium.status.valid and (Premium.status.tier .. " active") or ("locked (" .. Premium.status.reason .. ")")), Premium.status.valid and THEME.Green or THEME.Red)
local keyBox = addTextbox(set, "Premium Key", "TPC-...", "premiumKey")
addButton(set, "Activate Key", THEME.Accent, function()
    local result = Premium.activate(keyBox.Text, true)
    if result.valid then
        Premium.unlockAll()
        notify("Premium unlocked - " .. result.tier, "success", "Premium")
    else
        notify(result.reason, "error", "Premium")
    end
end)

addSection(set, "Executor")
do
    local missing = {}
    for name, present in pairs(CAP) do
        if not present then table.insert(missing, name) end
    end
    table.sort(missing)
    if #missing == 0 then
        addNote(set, "All optional APIs present. Every module is live.", THEME.Green)
    else
        addNote(set, "Missing: " .. table.concat(missing, ", ") .. ". Those widgets are switched off, everything else runs.", THEME.Sub)
    end
end

-- One button that answers "nothing happens". It writes the report into a
-- scrolling box on the page and into the clipboard, so the text can be pasted
-- straight back. The box reserves its height at build time, so the Config
-- section below still lands where it should.
local selfBox = new("ScrollingFrame", {
    Size = UDim2.new(0, set.w, 0, 168),
    Position = UDim2.fromOffset(set.x, set.y),
    BackgroundColor3 = THEME.Panel,
    BorderSizePixel = 0,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = THEME.Stroke,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, set.frame)
new("UICorner", { CornerRadius = UDim.new(0, 6) }, selfBox)
set.y = set.y + 174

local selfNote = new("TextLabel", {
    Size = UDim2.new(1, -12, 0, 24),
    Position = UDim2.fromOffset(8, 6),
    BackgroundTransparency = 1,
    Text = "Run Self Test, then paste the report here.",
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    Font = Enum.Font.Code,
    TextSize = 10,
    TextColor3 = THEME.Sub,
}, selfBox)

addButton(set, "Run Self Test", THEME.Accent, function()
    local ok, report = pcall(selfTestReport)
    if not ok then
        selfNote.Text = "Self test failed: " .. tostring(report)
        selfNote.TextColor3 = THEME.Red
        notify(tostring(report), "error", "Self test")
        return
    end
    selfNote.Text = report
    selfNote.TextColor3 = THEME.Text
    selfNote.Size = UDim2.new(1, -12, 0, 0)
    selfNote.AutomaticSize = Enum.AutomaticSize.Y
    if copy(report) then
        notify("Self test copied - paste it in the chat", "success")
    else
        notify("Self test written above", "info")
    end
    warn("[Tupachup self test]\n" .. report)
end)

addSection(set, "Config")
local cfgName = addTextbox(set, "Config Name", "default", "configName")
addButton(set, "Save Config", THEME.Text, function() Features.saveConfig(cfgName.Text) end)
addButton(set, "Load Config", THEME.Text, function() Features.loadConfig(cfgName.Text) end)
addButton(set, "Delete Config", THEME.Red, function() Features.deleteConfig(cfgName.Text) end)
addButton(set, "Unload Hub", THEME.Red, function() Features.unload() end)

for _, page in pairs(pages) do
    flush(page)
end

-- ============================================================
-- PREMIUM GATE  (locks the premium tabs until a key is accepted)
-- ============================================================
do
    local locks = {}

    local function buildLock(page, name)
        local cover = new("Frame", {
            Name = "PremiumLock",
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = THEME.Bg,
            BackgroundTransparency = 0.08,
            BorderSizePixel = 0,
            ZIndex = 60,
        }, page.frame)

        new("TextLabel", {
            Size = UDim2.new(1, -40, 0, 26),
            Position = UDim2.new(0, 20, 0, 24),
            BackgroundTransparency = 1,
            Text = "🔒  Premium",
            TextXAlignment = Enum.TextXAlignment.Left,
            Font = Enum.Font.GothamBold,
            TextSize = 16,
            TextColor3 = THEME.Accent,
            ZIndex = 61,
        }, cover)

        new("TextLabel", {
            Size = UDim2.new(1, -40, 0, 34),
            Position = UDim2.new(0, 20, 0, 54),
            BackgroundTransparency = 1,
            Text = name .. " is a premium tab. Paste your key below to unlock it. The key saves, so you only do this once.",
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            Font = Enum.Font.GothamMedium,
            TextSize = 11,
            TextColor3 = THEME.Sub,
            ZIndex = 61,
        }, cover)

        local box = new("TextBox", {
            Size = UDim2.new(1, -40, 0, 32),
            Position = UDim2.new(0, 20, 0, 96),
            BackgroundColor3 = THEME.Row,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = "TPC-PRO-...",
            PlaceholderColor3 = THEME.Sub,
            TextXAlignment = Enum.TextXAlignment.Left,
            Font = Enum.Font.Code,
            TextSize = 11,
            TextColor3 = THEME.Text,
            ClearTextOnFocus = false,
            ZIndex = 61,
        }, cover)
        new("UICorner", { CornerRadius = UDim.new(0, 6) }, box)
        new("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, box)
        box:GetPropertyChangedSignal("Text"):Connect(function()
            box.Text = box.Text:upper():gsub("[^%w%-]", "")
        end)

        local go = new("TextButton", {
            Size = UDim2.new(0, 120, 0, 32),
            Position = UDim2.new(0, 20, 0, 136),
            BackgroundColor3 = THEME.Accent,
            BorderSizePixel = 0,
            Text = "Activate",
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            TextColor3 = Color3.new(0.06, 0.06, 0.07),
            AutoButtonColor = false,
            ZIndex = 61,
        }, cover)
        new("UICorner", { CornerRadius = UDim.new(0, 6) }, go)

        local status = new("TextLabel", {
            Size = UDim2.new(1, -160, 0, 32),
            Position = UDim2.new(0, 152, 0, 136),
            BackgroundTransparency = 1,
            Text = "",
            TextXAlignment = Enum.TextXAlignment.Left,
            Font = Enum.Font.GothamMedium,
            TextSize = 10,
            TextColor3 = THEME.Sub,
            ZIndex = 61,
        }, cover)

        go.MouseButton1Click:Connect(function()
            local result = Premium.activate(box.Text, true)
            if result.valid then
                status.Text = "Unlocked - " .. result.tier
                status.TextColor3 = THEME.Green
                Premium.unlockAll()
                notify("Premium unlocked - " .. result.tier, "success", "Premium")
            else
                status.Text = result.reason
                status.TextColor3 = THEME.Red
            end
        end)

        return cover
    end

    function Premium.applyLocks()
        for name, page in pairs(pages) do
            if Premium.tabs[name] and not Premium.status.valid and not locks[name] then
                locks[name] = buildLock(page, name)
            end
        end
    end

    function Premium.unlockAll()
        for name, cover in pairs(locks) do
            if cover and cover.Parent then cover:Destroy() end
            locks[name] = nil
        end
        for name, page in pairs(pages) do
            for _, child in ipairs(page.frame:GetChildren()) do
                if child.Name == "PremiumLock" then child:Destroy() end
            end
        end
    end

    Premium.applyLocks()
end


-- ============================================================
-- CONFIG IO
-- ============================================================
local function cfgPath(name)
    name = (name and name ~= "") and name or "default"
    name = name:gsub("[^%w_%-]", "")
    if name == "" then name = "default" end
    return CFG_DIR .. "/" .. name .. ".json"
end

Features.saveConfig = function(name)
    if not writefile then
        notify("Executor has no writefile", "error")
        return
    end
    ensureDir()
    local ok = pcall(writefile, cfgPath(name), HttpService:JSONEncode(Flags))
    notify(ok and ("Saved " .. cfgPath(name)) or "Save failed", ok and "success" or "error")
end

Features.loadConfig = function(name)
    if not (readfile and isfile) then
        notify("Executor has no readfile", "error")
        return
    end
    local path = cfgPath(name)
    if not isfile(path) then
        notify("No config: " .. path, "error")
        return
    end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(path))
    end)
    if not ok or type(data) ~= "table" then
        notify("Config is corrupt", "error")
        return
    end
    for key, value in pairs(data) do
        if Setters[key] then
            pcall(Setters[key], value)
        end
    end
    notify("Loaded " .. path, "success")
end

Features.deleteConfig = function(name)
    if not delfile then
        notify("Executor has no delfile", "error")
        return
    end
    local path = cfgPath(name)
    local ok = pcall(delfile, path)
    notify(ok and ("Deleted " .. path) or "Delete failed", ok and "success" or "error")
end

-- ============================================================
-- UNLOAD
-- ============================================================
Features.unload = function()
    notifyOn = false
    for _, stop in pairs(Stops) do
        pcall(stop)
    end
    for _, c in ipairs(Conns) do
        pcall(function() c:Disconnect() end)
    end
    Conns = {}

    local _, hum = char()
    if hum then
        hum.WalkSpeed = baseWalk
        hum.JumpPower = baseJump
        hum.UseJumpPower = true
    end
    local cam = workspace.CurrentCamera
    if cam then cam.FieldOfView = baseFov end

    if notifHolder then notifHolder:Destroy() end
    if gui then gui:Destroy() end
    getgenv().Tupachup = nil
end

-- ============================================================
-- DRAG + MENU KEY
-- ============================================================
do
    local dragging = false
    local dragStart, startPos

    topbar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = window.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    track(UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            window.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end))
end

local minimized = false
local minBtn, closeBtn
local setWindowVisible

minBtn = topButton("–", -66, THEME.Sub, function()
    minimized = not minimized
    if minimized then
        rail.Visible = false
        pageHolder.Visible = false
        TweenService:Create(window, TweenInfo.new(0.18), { Size = UDim2.fromOffset(WIN_W, TOP_H) }):Play()
        minBtn.Text = "+"
    else
        rail.Visible = true
        pageHolder.Visible = true
        TweenService:Create(window, TweenInfo.new(0.18), { Size = UDim2.fromOffset(WIN_W, WIN_H) }):Play()
        minBtn.Text = "–"
    end
end)

closeBtn = topButton("×", -32, THEME.Red, function()
    setWindowVisible(false)
    notify("Hidden. Tap the Tupachup chip or press " .. tostring(menuKey.Name) .. " to reopen.", "info", "Hidden")
end)

-- top-centre chip: always on screen, tap it to show or hide the window
local pill = new("TextButton", {
    Name = "TupachupPill",
    Size = UDim2.fromOffset(140, 30),
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, CHIP_TOP),
    BackgroundColor3 = Color3.fromRGB(14, 14, 17),
    BackgroundTransparency = 0.06,
    BorderSizePixel = 0,
    Text = "",
    AutoButtonColor = false,
    ZIndex = 60,
}, gui)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, pill)
local pillStroke = new("UIStroke", { Color = THEME.Stroke, Thickness = 1 }, pill)

local pillMark = new("Frame", {
    Size = UDim2.fromOffset(18, 18),
    Position = UDim2.fromOffset(7, 6),
    BackgroundColor3 = THEME.Accent,
    BorderSizePixel = 0,
    ZIndex = 61,
}, pill)
new("UICorner", { CornerRadius = UDim.new(0, 5) }, pillMark)
new("TextLabel", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Text = "T",
    Font = Enum.Font.GothamBlack,
    TextSize = 12,
    TextColor3 = Color3.fromRGB(22, 16, 10),
    ZIndex = 62,
}, pillMark)

new("TextLabel", {
    Size = UDim2.fromOffset(84, 30),
    Position = UDim2.fromOffset(30, 0),
    BackgroundTransparency = 1,
    Text = BRAND,
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextColor3 = THEME.Text,
    ZIndex = 61,
}, pill)

-- status led: green while the window is open, grey while it is hidden
local pillDot = new("Frame", {
    Size = UDim2.fromOffset(6, 6),
    Position = UDim2.new(1, -16, 0.5, -3),
    BackgroundColor3 = THEME.Green,
    BorderSizePixel = 0,
    ZIndex = 61,
}, pill)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, pillDot)

pill.MouseEnter:Connect(function()
    TweenService:Create(pillStroke, TweenInfo.new(0.12), {
        Color = THEME.Accent, Transparency = 0.15,
    }):Play()
end)
pill.MouseLeave:Connect(function()
    TweenService:Create(pillStroke, TweenInfo.new(0.12), {
        Color = THEME.Stroke, Transparency = 0,
    }):Play()
end)

setWindowVisible = function(on)
    window.Visible = on
    pillDot.BackgroundColor3 = on and THEME.Green or THEME.Sub
    if on and minimized then
        minimized = false
        rail.Visible = true
        pageHolder.Visible = true
        window.Size = UDim2.fromOffset(WIN_W, WIN_H)
        minBtn.Text = "–"
    end
end

pill.MouseButton1Click:Connect(function()
    setWindowVisible(not window.Visible)
end)

track(UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == menuKey then
        setWindowVisible(not window.Visible)
    end
end))

-- ============================================================
-- BOOT
-- ============================================================
loadWaypoints()
renderWaypoints()

-- protection defaults land before the welcome, so the first thing on screen is
-- already the protected build
pcall(Features.hideGui, true, true)
pcall(Features.lockGui, true, true)

getgenv().Tupachup = {
    Version = VERSION,
    Unload = Features.unload,
    Flags = Flags,
    Features = Features,
    Toolkit = Toolkit,
    Quest = Quest,
    Auto = Auto,
    SelfTest = selfTestReport,
    PSX = PSX,
    PT = PT,
    Premium = Premium,
    CallSetter = callSetter,
    Pages = pages,
    Setters = Setters,
    Protect = Protect,
    Game = activeGame,
    GameLock = GAME_LOCK,
    Detected = DETECTED_NAME,
    Capabilities = CAP,
}

local apiHave, apiTotal = Protect.apiScore()
notify((LP.DisplayName or LP.Name) .. "  -  " .. (GAME_LABEL[activeGame] or "Universal"),
    "success", "Welcome back")
notify(("%d tabs  -  %d/%d APIs  -  v%s"):format(tabIndex, apiHave, apiTotal, VERSION),
    "info", BRAND .. " loaded")

print("[" .. BRAND:upper() .. "] v" .. VERSION .. " ready | " .. tostring(game.PlaceId))
