--[[
    TUPACHUP  |  single-file Roblox script hub
    No external UI library, no dependencies.
    Entry point: loadstring(game:HttpGet("<your-host>/Exec"))()
    Unload: getgenv().Tupachup.Unload()
]]

local VERSION = "1.6.0"
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

local function char()
    local c = LP.Character
    if not c then return nil end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    return c, hum
end

local function root()
    local c = LP.Character
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
        if not silent and cb then task.spawn(cb, state) end
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

    local value = default
    local dragging = false

    local function apply(v, silent)
        value = clamp(round(v, step), lo, hi)
        local alpha = (value - lo) / (hi - lo)
        fill.Size = UDim2.fromScale(alpha, 1)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        valueLbl.Text = tostring(value) .. (suffix or "")
        Flags[flag] = value
        if not silent and cb then task.spawn(cb, value) end
    end

    local function fromX(x)
        local alpha = (x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1)
        apply(lo + (hi - lo) * clamp(alpha, 0, 1), false)
    end

    track(bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            fromX(input.Position.X)
        end
    end))
    track(bar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end))
    track(UIS.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            fromX(input.Position.X)
        end
    end))
    track(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
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
    b.MouseButton1Click:Connect(cb)
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
        if cb then task.spawn(cb, box.Text) end
    end)
    bind(flag, function(v)
        -- programmatic sets (config load, quest arming) have to move the flag
        -- and the behaviour, not just the text in the box
        v = (v == nil) and "" or tostring(v)
        box.Text = v
        Flags[flag] = v
        if cb then task.spawn(cb, v) end
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
            if cb then task.spawn(cb, input.KeyCode) end
        end
    end))

    bind(flag, function(v)
        btn.Text = tostring(v)
        Flags[flag] = v
        local key = Enum.KeyCode[v]
        if key and cb then task.spawn(cb, key) end
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
                if cb then task.spawn(cb, opt) end
            end)
        end
    end)

    bind(flag, function(v)
        value = v
        valueLbl.Text = tostring(v) .. "  v"
        Flags[flag] = v
        if cb then task.spawn(cb, v) end
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
        if cb then task.spawn(cb, out) end
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

local function isShown(inst)
    local node = inst
    while node and node ~= PG do
        if node == gui then return false end
        if node:IsA("GuiObject") and node.Visible == false then return false end
        node = node.Parent
    end
    return true
end

function PSX.findButton(words)
    local seen = 0
    for _, inst in ipairs(PG:GetDescendants()) do
        seen = seen + 1
        if seen > GUI_SCAN_CAP then break end
        if inst:IsA("GuiButton") and isShown(inst) then
            local hay = string.lower(inst.Name) .. " " .. string.lower(inst.Text or "")
            for _, w in ipairs(words) do
                if string.find(hay, w, 1, true) then return inst end
            end
        end
    end
    return nil
end

function PSX.click(btn)
    if not btn then return false end
    -- a TextLabel has no MouseButton1Click; indexing one throws before pcall
    -- even runs, which is how a label used to kill the whole quest cycle
    if not btn:IsA("GuiButton") then return false end
    if not CAP.firesignal then
        notify("firesignal is missing on this executor - cannot click UI", "error")
        return false
    end
    local ok = pcall(function() firesignal(btn.MouseButton1Click) end)
    if not ok then pcall(function() firesignal(btn.Activated) end) end
    return true
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
    if now - (Auto.last[key] or 0) < seconds then return false end
    Auto.last[key] = now
    return true
end

-- words: at least one must appear. avoid: none may appear. context: if given,
-- at least one of these must also appear.
local function autoFind(words, avoid, context)
    local seen = 0
    for _, inst in ipairs(PG:GetDescendants()) do
        seen = seen + 1
        if seen > GUI_SCAN_CAP then break end
        if inst:IsA("GuiButton") and isShown(inst) then
            local hay = string.lower(inst.Name) .. " " .. string.lower(inst.Text or "")
            local hit = false
            for _, w in ipairs(words) do
                if string.find(hay, w, 1, true) then hit = true break end
            end
            if hit then
                local blocked = false
                for _, w in ipairs(avoid or {}) do
                    if string.find(hay, w, 1, true) then blocked = true break end
                end
                if not blocked and context and #context > 0 then
                    blocked = true
                    for _, w in ipairs(context) do
                        if string.find(hay, w, 1, true) then blocked = false break end
                    end
                end
                if not blocked then return inst end
            end
        end
    end
    return nil
end

function Auto.use(words, key, seconds, avoid, context)
    if not autoThrottle(key, seconds) then return false end
    local btn = autoFind(words, avoid, context)
    if not btn then return false end
    return PSX.click(btn)
end

-- dropdown food: the names the game is actually showing
function Auto.options(words, fallback, cap)
    local out, seen = {}, {}
    local scanned = 0
    for _, inst in ipairs(PG:GetDescendants()) do
        scanned = scanned + 1
        if scanned > GUI_SCAN_CAP then break end
        if inst:IsA("GuiButton") and isShown(inst) then
            local text = cleanText(inst.Text or "")
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
            if #out >= cap then break end
        end
    end
    if #out == 0 then return fallback end
    table.sort(out)
    return out
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
end

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

local function addTab(name)
    local page = makePage()
    pages[name] = page

    tabIndex = tabIndex + 1
    local idx = tabIndex
    local btn = new("TextButton", {
        Size = UDim2.new(1, -14, 0, 28),
        Position = UDim2.fromOffset(7, 6 + (idx - 1) * 29),
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

    local dot = new("Frame", {
        Size = UDim2.fromOffset(5, 5),
        Position = UDim2.fromOffset(12, 11),
        BackgroundColor3 = THEME.Sub,
        BorderSizePixel = 0,
    }, btn)
    new("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)

    local label = new("TextLabel", {
        Size = UDim2.new(1, -34, 1, 0),
        Position = UDim2.fromOffset(24, 0),
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
            b.dot.BackgroundColor3 = isSel and THEME.Accent or THEME.Sub
            b.marker.Visible = isSel
        end
        selectedTab = name
    end

    btn.MouseButton1Click:Connect(select)

    tabButtons[name] = {
        btn = btn,
        marker = marker,
        dot = dot,
        label = label,
    }

    if not selectedTab then
        select()
    end

    return page
end

-- ---------- HOME ----------
local main = addTab("Home")

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
local gamePage = addTab("Games")
-- the whole farm page lives in its own block: the compiler frees its locals at
-- the end, and the main chunk is already near the 200-local ceiling.
-- callSetter stays outside because the quest runner drives the same flags.
local callSetter
do
local farmPage = addTab("Auto Farm")

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

-- ---------- GAME ----------
local GAME_PRESETS = {
    PS99 = {
        prompts = "hatch, egg, open, rebirth, rank, upgrade",
        touch = "coin, gem, diamond, cash, money",
        note = "Auto-hatch fires the egg ProximityPrompts in range. Auto-collect touches coin and gem parts. Turn the radius up to 90 for a full area sweep.",
    },
    PGO = {
        prompts = "egg, hatch, open, rebirth, upgrade",
        touch = "coin, gold, gem, cash, money",
        note = "Same layout as PS99: egg prompts hatch, coin parts collect. Radius 60-90 covers most spawn areas.",
    },
    GAG = {
        prompts = "plant, harvest, collect, sell, water, buy",
        touch = "crop, fruit, seed, plant, harvest",
        note = "Plant and harvest are prompts on the plots. Auto-collect touches crop and fruit parts. Keep the radius at 40 or you will fire neighbouring plots.",
    },
    ETFB = {
        prompts = "escape, collect, open, rescue, brainrot",
        touch = "brainrot, coin, cash, money",
        note = "Collect touches brainrot parts. Escape prompts fire the exit interactions. Speed and fly live in Main if the round is going badly.",
    },
    UNIVERSAL = {
        prompts = "",
        touch = "coin, gem, cash, money",
        note = "Game not recognised. Scan the prompts and parts first, then type the names you see into the filters on the Farm tab.",
    },
}

local GAME_ORDER = { "PS99", "PGO", "GAG", "ETFB", "UNIVERSAL" }

local function labelToKey(label)
    for _, key in ipairs(GAME_ORDER) do
        if GAME_LABEL[key] == label then return key end
    end
    return "UNIVERSAL"
end

local function gameLabels()
    local out = {}
    for _, key in ipairs(GAME_ORDER) do table.insert(out, GAME_LABEL[key]) end
    return out
end

local function buildGamePage(key)
    local page = gamePage
    for _, child in ipairs(page.frame:GetChildren()) do
        child:Destroy()
    end
    page.y = 12

    local preset = GAME_PRESETS[key] or GAME_PRESETS.UNIVERSAL

    addSection(page, GAME_LABEL[key] or "Universal")
    addNote(page, "Detected: " .. DETECTED_NAME, THEME.Accent)
    addDropdown(page, "Game", gameLabels, GAME_LABEL[key] or "Universal", "gamePick", function(label)
        activeGame = labelToKey(label)
        buildGamePage(activeGame)
    end)

    addSection(page, "One Tap")
    addButton(page, "Apply Farm Preset", THEME.Accent, function()
        T.promptFilter = preset.prompts
        T.touchFilter = preset.touch
        callSetter("promptFilter", preset.prompts)
        callSetter("touchFilter", preset.touch)
        callSetter("autoPrompt", true)
        if CAP.touch then callSetter("autoTouch", true) end
        notify(GAME_LABEL[key] .. " preset armed", "success")
    end)
    addButton(page, "Auto Hatch / Interact", THEME.Text, function()
        T.promptFilter = preset.prompts
        callSetter("promptFilter", preset.prompts)
        callSetter("autoPrompt", true)
        notify("Prompts on", "success")
    end)
    if CAP.touch then
        addButton(page, "Auto Collect", THEME.Text, function()
            T.touchFilter = preset.touch
            callSetter("touchFilter", preset.touch)
            callSetter("autoTouch", true)
            notify("Collect on", "success")
        end)
    end
    addButton(page, "Auto Click", THEME.Text, function()
        callSetter("autoClick", true)
        notify("Click on", "success")
    end)
    addButton(page, "Stop Everything", THEME.Red, function()
        callSetter("autoPrompt", false)
        callSetter("autoTouch", false)
        callSetter("autoClick", false)
        callSetter("autoKey", false)
        notify("All automation off", "info")
    end)

    addSection(page, "Scan")
    addButton(page, "Scan Prompts", THEME.Text, function() Toolkit.scanPrompts() end)
    addButton(page, "Scan Collectibles", THEME.Text, function() Toolkit.scanParts() end)

    addSection(page, "How This Works")
    addNote(page, preset.note)
    addNote(page, "Filters live on the Farm tab. Presets only fill them in and switch the toggles.", THEME.Sub)
end

buildGamePage(activeGame)

-- ---------- VISUALS ----------
local vis = addTab("Visuals")
addSection(vis, "Players")
addToggle(vis, "Player ESP", false, "esp", function(v) Features.esp(v) end)
addToggle(vis, "ESP Names + Health", false, "espNames", function(v) Features.espNames(v) end)
addSection(vis, "Environment")
addToggle(vis, "Fullbright", false, "fullbright", function(v) Features.fullbright(v) end)
addSlider(vis, "Camera FOV", 70, 120, 70, 1, "fov", function(v) Features.fov(v) end)

-- ---------- TELEPORT ----------
local tp = addTab("Teleport")
addSection(tp, "Waypoints")
local wpName = addTextbox(tp, "Name", "spawn", "wpName")
addButton(tp, "Save Current Position", THEME.Text, function()
    addWaypoint(wpName.Text)
end)
waypointPanel = addPanel(tp, 150)
addSection(tp, "Targets")
addDropdown(tp, "Player", playerNames, "-", "tpTarget", function(v) Features.tpPlayer(v) end)
addButton(tp, "Teleport To Player", THEME.Text, function()
    if Flags.tpTarget and Flags.tpTarget ~= "-" then
        Features.tpPlayer(Flags.tpTarget)
    else
        notify("Pick a player first", "error")
    end
end)
addButton(tp, "Teleport To Cursor", THEME.Text, function() Features.tpMouse() end)

-- ---------- WEBHOOK ----------
local hook = addTab("Webhook")
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
local opt = addTab("Optimization")

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
local psx = addTab("PSX")

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
    local best, bestNum, seen = nil, -1, 0
    for _, inst in ipairs(PG:GetDescendants()) do
        seen = seen + 1
        if seen > GUI_SCAN_CAP then break end
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
    end
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

-- ---------- QUEST ----------
local quest = addTab("Quest")

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

-- ---------- MISC ----------
local misc = addTab("Misc")

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

-- ---------- SETTINGS ----------
local set = addTab("Settings")
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
    CallSetter = callSetter,
    Protect = Protect,
    Game = activeGame,
    Detected = DETECTED_NAME,
    Capabilities = CAP,
}

local apiHave, apiTotal = Protect.apiScore()
notify((LP.DisplayName or LP.Name) .. "  -  " .. (GAME_LABEL[activeGame] or "Universal"),
    "success", "Welcome back")
notify(("%d tabs  -  %d/%d APIs  -  v%s"):format(tabIndex, apiHave, apiTotal, VERSION),
    "info", BRAND .. " loaded")

print("[" .. BRAND:upper() .. "] v" .. VERSION .. " ready | " .. tostring(game.PlaceId))
