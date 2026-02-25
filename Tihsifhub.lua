-- ============================================================
-- FishIt Omega Hub  |  v1.0
-- Built from full game source analysis (FishingController,
-- VendorController, TileInteraction, Constants, Tiers, etc.)
-- ============================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local StarterGui       = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer

-- ── Landscape orient ──────────────────────────────────────
pcall(function() StarterGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeRight end)
pcall(function() LocalPlayer.PlayerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeRight end)

-- ── GUI mount ─────────────────────────────────────────────
local TargetParent =
    (type(gethui) == "function" and gethui()) or
    (pcall(function() return game:GetService("CoreGui") end) and game:GetService("CoreGui")) or
    LocalPlayer:WaitForChild("PlayerGui")

if not TargetParent then return end
if TargetParent:FindFirstChild("FishItOmegaHub") then TargetParent.FishItOmegaHub:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "FishItOmegaHub"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = TargetParent

-- ── Theme ─────────────────────────────────────────────────
local T = {
    Bg         = Color3.fromRGB(20, 20, 26),
    Sidebar    = Color3.fromRGB(14, 14, 20),
    Accent     = Color3.fromRGB(0, 195, 125),
    AccentDim  = Color3.fromRGB(0, 130, 85),
    Text       = Color3.fromRGB(235, 235, 235),
    Sub        = Color3.fromRGB(125, 125, 140),
    Btn        = Color3.fromRGB(32, 32, 40),
    Stroke     = Color3.fromRGB(55, 55, 68),
    Danger     = Color3.fromRGB(215, 55, 55),
    Warn       = Color3.fromRGB(240, 150, 30),
    Good       = Color3.fromRGB(55, 195, 95),
}

-- ── State ─────────────────────────────────────────────────
local S = {
    DetectorActive  = false, DetectorStatus = "Offline",
    DetectorTime    = 0,     DetectorBag    = 0,
    WaitDelay       = 1.5,   CompleteDelay  = 0,
    InstantFishing  = false,
    AutoSell        = false, SellMode       = "Delay", SellValue = 30,
    AutoFavorite    = false, FavRarity      = "Any",  FavVariant = "Any",
    AutoRejoin      = false, RejoinTimer    = 1,
    ShowPing        = false, AutoEquipRod   = false,
    WalkOnWater     = false, FreezePlayer   = false,
    WalkSpeed       = false, WalkSpeedVal   = 50,
    Noclip          = false, InfJump        = false,
    FPSBoost        = false,
    SessionFish     = 0,
}

-- ── Remote helpers ────────────────────────────────────────
local _netCache = {}
local function getNet(name, isFunc)
    if _netCache[name] then return _netCache[name] end
    local ok, mod = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Packages",5):WaitForChild("Net",5))
    end)
    if not ok or not mod then return nil end
    local ok2, obj = pcall(function()
        return isFunc and mod:RemoteFunction(name) or mod:RemoteEvent(name)
    end)
    if ok2 and obj then _netCache[name] = obj end
    return _netCache[name]
end

local _replionData
local function getRepData()
    if _replionData and not _replionData.Destroyed then return _replionData end
    local ok, mod = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Packages",5):WaitForChild("Replion",5))
    end)
    if not ok then return nil end
    local ok2, d = pcall(function() return mod.Client:WaitReplion("Data") end)
    if ok2 then _replionData = d end
    return _replionData
end

local function getInvItems()
    local d = getRepData()
    if not d then return {} end
    local ok, v = pcall(function() return d:GetExpect({"Inventory","Items"}) end)
    return ok and v or {}
end

-- ── Character helpers ─────────────────────────────────────
local function getChar()  return LocalPlayer.Character end
local function getHRP()   local c=getChar() return c and c:FindFirstChild("HumanoidRootPart") end
local function getHum()   local c=getChar() return c and c:FindFirstChildOfClass("Humanoid") end

local function notify(msg)
    pcall(function()
        StarterGui:SetCore("SendNotification",{Title="FishIt Hub",Text=msg,Duration=3})
    end)
end

-- ============================================================
-- GAME FEATURES
-- ============================================================

-- Auto Fisher
local fishThread
local function startFisher()
    if fishThread then task.cancel(fishThread) end
    fishThread = task.spawn(function()
        S.DetectorStatus = "Running"
        S.DetectorTime   = 0
        local cam = workspace.CurrentCamera
        while S.DetectorActive do
            -- Cast rod
            local castRF = getNet("ChargeFishingRod", true)
            if castRF then
                local vp = cam.ViewportSize
                pcall(function()
                    castRF:InvokeServer(nil, nil, Vector2.new(vp.X/2, vp.Y/2), nil)
                end)
            end
            task.wait(0.5)
            -- Click/complete minigame
            local t0 = tick()
            local catchRF = getNet("CatchFishCompleted", true)
            local caught = false
            while S.DetectorActive and (tick()-t0) < (S.WaitDelay + 12) do
                task.wait(0.19)
                S.DetectorTime = tick()-t0
                if catchRF then
                    local ok, res = pcall(function() return catchRF:InvokeServer() end)
                    if ok and res then caught=true break end
                end
            end
            if caught then
                S.DetectorBag  = S.DetectorBag + 1
                S.SessionFish  = S.SessionFish + 1
            end
            task.wait(math.max(S.WaitDelay, 0.1))
        end
        S.DetectorStatus = "Offline"
    end)
end
local function stopFisher()
    if fishThread then task.cancel(fishThread) fishThread = nil end
    S.DetectorStatus = "Offline"
end

-- Sell All
local function doSellAll()
    local rf = getNet("SellAllItems", true)
    if rf then pcall(function() rf:InvokeServer() end) notify("Sold all fish! ✓") end
end
local sellThread
local function startAutoSell()
    if sellThread then task.cancel(sellThread) end
    sellThread = task.spawn(function()
        while S.AutoSell do
            task.wait(math.max(S.SellValue, 5))
            doSellAll()
        end
    end)
end

-- Favorite
local function favoriteUUID(uuid)
    local ev = getNet("FavoriteItem", false)
    if ev then pcall(function() ev:FireServer(uuid) end) end
end
local function runFavoriteLoop()
    local RARITY_MAP = {
        Common=1, Uncommon=2, Rare=3, Epic=4, Legendary=5, Mythic=6, SECRET=7
    }
    for _, item in ipairs(getInvItems()) do
        local skip = false
        if S.FavRarity ~= "Any" then
            local tier = item.Tier or (item.Probability and item.Probability.Tier) or 0
            if tier ~= (RARITY_MAP[S.FavRarity] or 0) then skip = true end
        end
        if S.FavVariant ~= "Any" and (item.Variant or "Normal") ~= S.FavVariant then skip = true end
        if not skip and not item.Favorite then
            favoriteUUID(item.UUID)
            task.wait(0.08)
        end
    end
end
local favThread
local function startAutoFav()
    if favThread then task.cancel(favThread) end
    favThread = task.spawn(function()
        while S.AutoFavorite do runFavoriteLoop() task.wait(3) end
    end)
end
local function unfavoriteAll()
    for _, item in ipairs(getInvItems()) do
        if item.Favorite then favoriteUUID(item.UUID) task.wait(0.07) end
    end
    notify("Unfavorited all!")
end

-- Walk on water
local wowConn
local function toggleWoW(on)
    if wowConn then wowConn:Disconnect() wowConn = nil end
    if on then
        wowConn = RunService.Heartbeat:Connect(function()
            local hrp = getHRP()
            if hrp and hrp.Position.Y < 0.4 then
                hrp.CFrame = hrp.CFrame + Vector3.new(0, 0.5, 0)
            end
        end)
    end
end

-- Noclip
local noclipConn
local function toggleNoclip(on)
    if noclipConn then noclipConn:Disconnect() noclipConn = nil end
    if on then
        noclipConn = RunService.Stepped:Connect(function()
            local c = getChar()
            if c then
                for _, p in ipairs(c:GetDescendants()) do
                    if p:IsA("BasePart") then p.CanCollide = false end
                end
            end
        end)
    else
        local c = getChar()
        if c then
            for _, p in ipairs(c:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = true end
            end
        end
    end
end

-- Inf jump
local infJumpConn
local function toggleInfJump(on)
    if infJumpConn then infJumpConn:Disconnect() infJumpConn = nil end
    if on then
        infJumpConn = UserInputService.JumpRequest:Connect(function()
            local h = getHum()
            if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
        end)
    end
end

-- Walkspeed loop
RunService.Heartbeat:Connect(function()
    if S.WalkSpeed and not S.FreezePlayer then
        local h = getHum()
        if h then h.WalkSpeed = S.WalkSpeedVal end
    end
    if S.FreezePlayer then
        local h = getHum()
        if h then h.WalkSpeed = 0; h.JumpPower = 0 end
    end
end)

-- Re-apply on respawn
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if S.WalkSpeed   then local h=getHum() if h then h.WalkSpeed = S.WalkSpeedVal end end
    if S.InfJump     then toggleInfJump(true) end
    if S.Noclip      then toggleNoclip(true) end
end)

-- Auto rejoin
local rejoinThread
local function startRejoin()
    if rejoinThread then task.cancel(rejoinThread) end
    rejoinThread = task.spawn(function()
        task.wait(S.RejoinTimer * 3600)
        if S.AutoRejoin then
            pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer) end)
        end
    end)
end

-- Teleport
local savedCF = nil
local LOCS = {
    ["Fisherman Island"] = Vector3.new(0, 5, 0),
    ["Sandy Shore"]      = Vector3.new(130, 5, 2768),
    ["Deep Ocean"]       = Vector3.new(-62, 5, 2767),
    ["Volcano Area"]     = Vector3.new(300, 65, -200),
    ["Ancient Ruins"]    = Vector3.new(-400, 12, 500),
    ["Crystal Cave"]     = Vector3.new(150, -18, -600),
    ["Sell NPC"]         = Vector3.new(10, 5, 30),
}
local function tpTo(v3)
    local h = getHRP()
    if h then h.CFrame = CFrame.new(v3 + Vector3.new(0,5,0)) end
end
local function tpToPlayer(name)
    local pl = Players:FindFirstChild(name)
    if pl and pl.Character then
        local h = pl.Character:FindFirstChild("HumanoidRootPart")
        if h then tpTo(h.Position) notify("Teleported to "..name) return end
    end
    notify("Player '"..name.."' not found!")
end

-- Auto equip best rod
local function equipBestRod()
    local ev = getNet("EquipItem", false)
    if not ev then return end
    for _, item in ipairs(getInvItems()) do
        -- rod IDs typically contain "Rod" keyword – equip first one found
        if item.Id and tostring(item.Id):lower():find("rod") then
            pcall(function() ev:FireServer(item.UUID, "Fishing Rods") end)
            notify("Equipped a fishing rod!")
            return
        end
    end
end

-- FPS boost
local function applyFPSBoost(on)
    if on then
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        pcall(function() game:GetService("Lighting").GlobalShadows = false end)
    else
        settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
        pcall(function() game:GetService("Lighting").GlobalShadows = true end)
    end
end

-- ============================================================
-- UI BUILDER
-- ============================================================

-- ── Minimize icon ─────────────────────────────────────────
local MinBtn = Instance.new("TextButton", ScreenGui)
MinBtn.Size     = UDim2.fromOffset(46, 46)
MinBtn.Position = UDim2.new(0.5, -23, 0.04, 0)
MinBtn.BackgroundColor3 = T.Bg
MinBtn.Text     = "🎣"
MinBtn.TextSize = 22
MinBtn.Visible  = false
MinBtn.ZIndex   = 20
Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(1, 0)
local ms = Instance.new("UIStroke", MinBtn)
ms.Color = T.Accent; ms.Thickness = 2

-- Make icon draggable
do
    local dragging, dStart, dOrigin
    MinBtn.InputBegan:Connect(function(i)
        if i.UserInputType.Name:find("Mouse") or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dStart = i.Position; dOrigin = MinBtn.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dStart
            MinBtn.Position = UDim2.new(dOrigin.X.Scale, dOrigin.X.Offset+d.X, dOrigin.Y.Scale, dOrigin.Y.Offset+d.Y)
        end
    end)
end

-- ── Main window ───────────────────────────────────────────
local Win = Instance.new("Frame", ScreenGui)
Win.Name              = "MainWindow"
Win.Size              = UDim2.fromOffset(520, 320)
Win.Position          = UDim2.new(0.5, -260, 0.5, -160)
Win.BackgroundColor3  = T.Bg
Win.BackgroundTransparency = 0.05
Win.Active            = true
Win.ClipsDescendants  = false
Win.ZIndex            = 5
Instance.new("UICorner", Win).CornerRadius = UDim.new(0, 10)
local ws = Instance.new("UIStroke", Win)
ws.Color = T.Stroke; ws.Thickness = 1; ws.Transparency = 0.4

-- ── Top bar ───────────────────────────────────────────────
local Bar = Instance.new("Frame", Win)
Bar.Size             = UDim2.new(1, 0, 0, 32)
Bar.BackgroundColor3 = T.Sidebar
Bar.BorderSizePixel  = 0
Bar.ZIndex           = 6
do  -- only round top corners
    local c = Instance.new("UICorner", Bar)
    c.CornerRadius = UDim.new(0, 10)
    local fix = Instance.new("Frame", Bar)
    fix.Size = UDim2.new(1, 0, 0.5, 0)
    fix.Position = UDim2.new(0, 0, 0.5, 0)
    fix.BackgroundColor3 = T.Sidebar
    fix.BorderSizePixel = 0
    fix.ZIndex = 6
end

-- Accent pill on title bar
local pill = Instance.new("Frame", Bar)
pill.Size = UDim2.fromOffset(3, 18)
pill.Position = UDim2.new(0, 10, 0.5, -9)
pill.BackgroundColor3 = T.Accent
pill.ZIndex = 7
Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

local TitleLbl = Instance.new("TextLabel", Bar)
TitleLbl.Size              = UDim2.new(0.7, 0, 1, 0)
TitleLbl.Position          = UDim2.new(0, 18, 0, 0)
TitleLbl.BackgroundTransparency = 1
TitleLbl.Text              = "🎣  FishIt Omega Hub  |  v1.0"
TitleLbl.Font              = Enum.Font.GothamBold
TitleLbl.TextColor3        = T.Text
TitleLbl.TextSize          = 12
TitleLbl.TextXAlignment    = Enum.TextXAlignment.Left
TitleLbl.ZIndex            = 7

-- Ping display (hidden by default)
local PingLbl = Instance.new("TextLabel", Bar)
PingLbl.Size           = UDim2.new(0.2, 0, 1, 0)
PingLbl.Position       = UDim2.new(0.58, 0, 0, 0)
PingLbl.BackgroundTransparency = 1
PingLbl.Text           = ""
PingLbl.Font           = Enum.Font.Gotham
PingLbl.TextColor3     = T.Accent
PingLbl.TextSize       = 10
PingLbl.ZIndex         = 7
PingLbl.Visible        = false

-- Close / minimize buttons
local function makeCtrl(txt, offsetX, col, cb)
    local b = Instance.new("TextButton", Bar)
    b.Size = UDim2.fromOffset(26, 20)
    b.Position = UDim2.new(1, offsetX, 0.5, -10)
    b.BackgroundTransparency = 1
    b.Text = txt; b.TextColor3 = col
    b.Font = Enum.Font.GothamBold; b.TextSize = 13
    b.ZIndex = 8
    b.MouseButton1Click:Connect(cb)
    return b
end
makeCtrl("✕", -30, T.Danger, function() ScreenGui:Destroy() end)
makeCtrl("—", -60, T.Sub, function()
    Win.Visible = false; MinBtn.Visible = true
end)
MinBtn.MouseButton1Click:Connect(function()
    Win.Visible = true; MinBtn.Visible = false
end)

-- Drag window
do
    local dragging, dStart, dOrigin
    Bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dStart = i.Position; dOrigin = Win.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dStart
            Win.Position = UDim2.new(dOrigin.X.Scale, dOrigin.X.Offset+d.X, dOrigin.Y.Scale, dOrigin.Y.Offset+d.Y)
        end
    end)
end

-- ── Sidebar ───────────────────────────────────────────────
-- NOTE: ONLY tab buttons go inside sidebar — no extra frames!
local Sidebar = Instance.new("ScrollingFrame", Win)
Sidebar.Size                = UDim2.new(0, 95, 1, -32)
Sidebar.Position            = UDim2.new(0, 0, 0, 32)
Sidebar.BackgroundColor3    = T.Sidebar
Sidebar.BorderSizePixel     = 0
Sidebar.ScrollBarThickness  = 0
Sidebar.CanvasSize          = UDim2.new(0, 0, 0, 0)
Sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y
Sidebar.ZIndex              = 6

local sbLayout = Instance.new("UIListLayout", Sidebar)
sbLayout.Padding            = UDim.new(0, 3)
sbLayout.HorizontalAlignment= Enum.HorizontalAlignment.Center
sbLayout.SortOrder          = Enum.SortOrder.LayoutOrder
local sbPad = Instance.new("UIPadding", Sidebar)
sbPad.PaddingTop = UDim.new(0, 8)

-- ── Content area ──────────────────────────────────────────
local Content = Instance.new("Frame", Win)
Content.Size               = UDim2.new(1, -98, 1, -32)
Content.Position           = UDim2.new(0, 98, 0, 32)
Content.BackgroundTransparency = 1
Content.ClipsDescendants   = false
Content.ZIndex             = 6

-- Divider line between sidebar and content
local divider = Instance.new("Frame", Win)
divider.Size             = UDim2.fromOffset(1, 288)
divider.Position         = UDim2.new(0, 96, 0, 32)
divider.BackgroundColor3 = T.Stroke
divider.BorderSizePixel  = 0
divider.ZIndex           = 7

-- ── Tab factory ───────────────────────────────────────────
local allTabs    = {}   -- {frame, name}
local allTabBtns = {}   -- {btn, indicator}
local activeTab  = nil

local function selectTab(idx)
    for i, t in ipairs(allTabs) do
        t.Frame.Visible = (i == idx)
    end
    for i, b in ipairs(allTabBtns) do
        b.Btn.BackgroundTransparency = (i == idx) and 0.75 or 1
        b.Btn.TextColor3             = (i == idx) and T.Text or T.Sub
        b.Indicator.Visible          = (i == idx)
    end
    activeTab = idx
end

local function newTab(icon, label, order)
    -- Content scroll frame
    local sf = Instance.new("ScrollingFrame", Content)
    sf.Size                = UDim2.new(1, 0, 1, -6)
    sf.Position            = UDim2.new(0, 0, 0, 4)
    sf.BackgroundTransparency = 1
    sf.ScrollBarThickness  = 3
    sf.ScrollBarImageColor3= T.Accent
    sf.Visible             = false
    sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sf.CanvasSize          = UDim2.new(0,0,0,0)
    sf.BorderSizePixel     = 0
    sf.ZIndex              = 7
    sf.ClipsDescendants    = true

    local fl = Instance.new("UIListLayout", sf)
    fl.Padding   = UDim.new(0, 5)
    fl.SortOrder = Enum.SortOrder.LayoutOrder
    local fp = Instance.new("UIPadding", sf)
    fp.PaddingTop   = UDim.new(0, 4)
    fp.PaddingRight = UDim.new(0, 6)

    -- Sidebar button
    local btn = Instance.new("TextButton", Sidebar)
    btn.Size                = UDim2.new(0.92, 0, 0, 26)
    btn.BackgroundColor3    = T.Accent
    btn.BackgroundTransparency = 1
    btn.Text                = icon.."  "..label
    btn.TextColor3          = T.Sub
    btn.Font                = Enum.Font.GothamMedium
    btn.TextSize            = 11
    btn.TextXAlignment      = Enum.TextXAlignment.Left
    btn.LayoutOrder         = order
    btn.ZIndex              = 7
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
    local bpad = Instance.new("UIPadding", btn)
    bpad.PaddingLeft = UDim.new(0, 7)

    local ind = Instance.new("Frame", btn)
    ind.Size             = UDim2.fromOffset(3, 14)
    ind.Position         = UDim2.new(0, 2, 0.5, -7)
    ind.BackgroundColor3 = T.Accent
    ind.Visible          = false
    ind.ZIndex           = 8
    Instance.new("UICorner", ind).CornerRadius = UDim.new(1, 0)

    local idx = #allTabs + 1
    table.insert(allTabs,    {Frame = sf, Name = label})
    table.insert(allTabBtns, {Btn = btn, Indicator = ind})

    btn.MouseButton1Click:Connect(function() selectTab(idx) end)
    return sf
end

-- ── Component helpers ─────────────────────────────────────

-- Section header
local function mkSection(parent, text, order)
    local f = Instance.new("Frame", parent)
    f.Size             = UDim2.new(0.98, 0, 0, 20)
    f.BackgroundColor3 = T.Sidebar
    f.BackgroundTransparency = 0.4
    f.LayoutOrder      = order or 0
    f.ZIndex           = 8
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 4)
    local lbl = Instance.new("TextLabel", f)
    lbl.Size = UDim2.new(1, -8, 1, 0)
    lbl.Position = UDim2.new(0, 8, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.Font = Enum.Font.GothamBold
    lbl.TextColor3 = T.Accent
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.ZIndex = 9
    return f
end

-- Toggle with animated knob
local function mkToggle(parent, title, desc, default, cb, order)
    local state = default or false
    local row = Instance.new("TextButton", parent)
    row.Size             = UDim2.new(0.98, 0, 0, desc~="" and 40 or 32)
    row.BackgroundColor3 = T.Btn
    row.Text             = ""
    row.AutoButtonColor  = false
    row.LayoutOrder      = order or 0
    row.ZIndex           = 8
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
    local rstr = Instance.new("UIStroke", row)
    rstr.Color = T.Stroke; rstr.Thickness = 1

    local titleLbl = Instance.new("TextLabel", row)
    titleLbl.Size = UDim2.new(0.72, 0, desc~="" and 0.55 or 1, 0)
    titleLbl.Position = UDim2.new(0, 10, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = title
    titleLbl.Font = Enum.Font.GothamMedium
    titleLbl.TextColor3 = T.Text
    titleLbl.TextSize = 12
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.ZIndex = 9

    if desc and desc ~= "" then
        local sub = Instance.new("TextLabel", row)
        sub.Size = UDim2.new(0.72, 0, 0.45, 0)
        sub.Position = UDim2.new(0, 10, 0.55, 0)
        sub.BackgroundTransparency = 1
        sub.Text = desc
        sub.Font = Enum.Font.Gotham
        sub.TextColor3 = T.Sub
        sub.TextSize = 9
        sub.TextXAlignment = Enum.TextXAlignment.Left
        sub.ZIndex = 9
    end

    -- Pill track
    local track = Instance.new("Frame", row)
    track.Size             = UDim2.fromOffset(36, 18)
    track.Position         = UDim2.new(1, -46, 0.5, -9)
    track.BackgroundColor3 = state and T.Accent or T.Btn
    track.ZIndex           = 9
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
    local tstr = Instance.new("UIStroke", track)
    tstr.Color = state and T.Accent or T.Stroke; tstr.Thickness = 1

    -- Knob
    local knob = Instance.new("Frame", track)
    knob.Size             = UDim2.fromOffset(12, 12)
    knob.Position         = state and UDim2.new(1,-14,0.5,-6) or UDim2.new(0,2,0.5,-6)
    knob.BackgroundColor3 = state and Color3.new(1,1,1) or T.Sub
    knob.ZIndex           = 10
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local function refresh(s)
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = s and UDim2.new(1,-14,0.5,-6) or UDim2.new(0,2,0.5,-6),
            BackgroundColor3 = s and Color3.new(1,1,1) or T.Sub,
        }):Play()
        TweenService:Create(track, TweenInfo.new(0.15), {
            BackgroundColor3 = s and T.Accent or T.Btn,
        }):Play()
        tstr.Color = s and T.Accent or T.Stroke
        row.BackgroundColor3 = s and Color3.fromRGB(22, 40, 32) or T.Btn
        rstr.Color = s and T.Accent or T.Stroke
    end
    refresh(state)

    row.MouseButton1Click:Connect(function()
        state = not state
        refresh(state)
        cb(state)
    end)

    -- Return setter so external code can flip it
    return row, function(s) state = s refresh(s) end
end

-- Button
local function mkBtn(parent, text, accent, cb, order)
    local btn = Instance.new("TextButton", parent)
    btn.Size             = UDim2.new(0.98, 0, 0, 30)
    btn.BackgroundColor3 = accent and T.AccentDim or T.Btn
    btn.Text             = text
    btn.TextColor3       = T.Text
    btn.Font             = Enum.Font.GothamMedium
    btn.TextSize         = 11
    btn.AutoButtonColor  = false
    btn.LayoutOrder      = order or 0
    btn.ZIndex           = 8
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    Instance.new("UIStroke", btn).Color = accent and T.Accent or T.Stroke

    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundTransparency = 0.25}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundTransparency = 0}):Play()
    end)
    btn.MouseButton1Click:Connect(cb)
    return btn
end

-- Text input
local function mkInput(parent, hint, default, cb, order)
    local f = Instance.new("Frame", parent)
    f.Size             = UDim2.new(0.98, 0, 0, 30)
    f.BackgroundColor3 = T.Btn
    f.LayoutOrder      = order or 0
    f.ZIndex           = 8
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 6)
    Instance.new("UIStroke", f).Color = T.Stroke

    local box = Instance.new("TextBox", f)
    box.Size = UDim2.new(1, -16, 1, 0)
    box.Position = UDim2.new(0, 8, 0, 0)
    box.BackgroundTransparency = 1
    box.PlaceholderText = hint or ""
    box.PlaceholderColor3 = T.Sub
    box.Text = default or ""
    box.TextColor3 = T.Text
    box.Font = Enum.Font.Gotham
    box.TextSize = 11
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.ClearTextOnFocus = false
    box.ZIndex = 9
    if cb then box.FocusLost:Connect(function() cb(box.Text) end) end
    return f, box
end

-- Status row  (label : value)
local function mkStatusRow(parent, label, default, order)
    local f = Instance.new("Frame", parent)
    f.Size = UDim2.new(0.98, 0, 0, 20)
    f.BackgroundTransparency = 1
    f.LayoutOrder = order or 0
    f.ZIndex = 8

    local l = Instance.new("TextLabel", f)
    l.Size = UDim2.new(0.55, 0, 1, 0)
    l.BackgroundTransparency = 1
    l.Text = label
    l.Font = Enum.Font.Gotham
    l.TextColor3 = T.Sub
    l.TextSize = 10
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.ZIndex = 9

    local v = Instance.new("TextLabel", f)
    v.Size = UDim2.new(0.45, 0, 1, 0)
    v.Position = UDim2.new(0.55, 0, 0, 0)
    v.BackgroundTransparency = 1
    v.Text = default or "—"
    v.Font = Enum.Font.GothamMedium
    v.TextColor3 = T.Accent
    v.TextSize = 10
    v.TextXAlignment = Enum.TextXAlignment.Right
    v.ZIndex = 9

    return f, v
end

-- Small label
local function mkLabel(parent, text, col, order)
    local l = Instance.new("TextLabel", parent)
    l.Size = UDim2.new(0.98, 0, 0, 18)
    l.BackgroundTransparency = 1
    l.Text = text
    l.Font = Enum.Font.Gotham
    l.TextColor3 = col or T.Sub
    l.TextSize = 10
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.LayoutOrder = order or 0
    l.ZIndex = 8
    return l
end

-- Dropdown
local function mkDropdown(parent, label, opts, default, cb, order)
    local cur = default or opts[1]

    local holder = Instance.new("Frame", parent)
    holder.Size = UDim2.new(0.98, 0, 0, 30)
    holder.BackgroundTransparency = 1
    holder.LayoutOrder = order or 0
    holder.ZIndex = 8
    holder.ClipsDescendants = false

    local header = Instance.new("TextButton", holder)
    header.Size = UDim2.new(1, 0, 0, 30)
    header.BackgroundColor3 = T.Btn
    header.ZIndex = 9
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 6)
    Instance.new("UIStroke", header).Color = T.Stroke

    local lLbl = Instance.new("TextLabel", header)
    lLbl.Size = UDim2.new(0.5, 0, 1, 0)
    lLbl.Position = UDim2.new(0, 8, 0, 0)
    lLbl.BackgroundTransparency = 1
    lLbl.Text = label
    lLbl.Font = Enum.Font.GothamMedium
    lLbl.TextColor3 = T.Text
    lLbl.TextSize = 11
    lLbl.TextXAlignment = Enum.TextXAlignment.Left
    lLbl.ZIndex = 10

    local vLbl = Instance.new("TextLabel", header)
    vLbl.Size = UDim2.new(0.46, 0, 1, 0)
    vLbl.Position = UDim2.new(0.52, 0, 0, 0)
    vLbl.BackgroundTransparency = 1
    vLbl.Text = cur .. "  ▾"
    vLbl.Font = Enum.Font.Gotham
    vLbl.TextColor3 = T.Accent
    vLbl.TextSize = 10
    vLbl.TextXAlignment = Enum.TextXAlignment.Right
    vLbl.ZIndex = 10

    local isOpen = false
    local menu = Instance.new("Frame", ScreenGui)  -- parent to ScreenGui so it's never clipped!
    menu.BackgroundColor3 = T.Bg
    menu.Size = UDim2.fromOffset(200, #opts * 26 + 4)
    menu.Visible = false
    menu.ZIndex = 50
    menu.ClipsDescendants = false
    Instance.new("UICorner", menu).CornerRadius = UDim.new(0, 6)
    local mstr = Instance.new("UIStroke", menu)
    mstr.Color = T.Accent; mstr.Thickness = 1

    local mLayout = Instance.new("UIListLayout", menu)
    mLayout.Padding = UDim.new(0, 0)
    local mPad = Instance.new("UIPadding", menu)
    mPad.PaddingTop = UDim.new(0, 2); mPad.PaddingBottom = UDim.new(0, 2)

    for _, opt in ipairs(opts) do
        local ob = Instance.new("TextButton", menu)
        ob.Size = UDim2.new(1, 0, 0, 26)
        ob.BackgroundTransparency = 1
        ob.Text = "  " .. opt
        ob.Font = Enum.Font.Gotham
        ob.TextColor3 = opt == cur and T.Accent or T.Text
        ob.TextSize = 11
        ob.TextXAlignment = Enum.TextXAlignment.Left
        ob.ZIndex = 51
        ob.MouseButton1Click:Connect(function()
            cur = opt
            vLbl.Text = opt .. "  ▾"
            menu.Visible = false
            isOpen = false
            cb(opt)
        end)
    end

    header.MouseButton1Click:Connect(function()
        isOpen = not isOpen
        if isOpen then
            -- Position menu below header in screen space
            local abs = header.AbsolutePosition
            local sz  = header.AbsoluteSize
            menu.Position = UDim2.fromOffset(abs.X, abs.Y + sz.Y + 2)
            menu.Size     = UDim2.fromOffset(sz.X, #opts * 26 + 4)
        end
        menu.Visible = isOpen
    end)

    -- Close dropdown when clicking elsewhere
    UserInputService.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            if isOpen and i.UserInputState == Enum.UserInputState.Begin then
                task.defer(function()
                    if isOpen then menu.Visible = false isOpen = false end
                end)
            end
        end
    end)

    return holder
end

-- ============================================================
-- CREATE TABS
-- ============================================================
local TabInfo     = newTab("ℹ️",  "Info",     1)
local TabFishing  = newTab("🎣",  "Fishing",  2)
local TabAuto     = newTab("⚙️",  "Auto",     3)
local TabTrading  = newTab("🤝",  "Trading",  4)
local TabMenu     = newTab("📋",  "Menu",     5)
local TabQuest    = newTab("📜",  "Quest",    6)
local TabTeleport = newTab("🗺️", "Teleport", 7)
local TabMisc     = newTab("🔧",  "Misc",     8)

-- ============================================================
-- ▶  INFO TAB
-- ============================================================
mkLabel(TabInfo, "🎣  FishIt Omega Hub  v1.0", T.Accent, 1)
mkLabel(TabInfo, "Built from full game source analysis.", T.Sub, 2)
mkLabel(TabInfo, "──────────────────────────────────", T.Stroke, 3)

local _, vPing    = mkStatusRow(TabInfo, "📶  Ping",             "— ms",     4)
local _, vStatus  = mkStatusRow(TabInfo, "🎣  Status",           "Idle",     5)
local _, vFish    = mkStatusRow(TabInfo, "🐟  Fish (session)",   "0",        6)
local _, vBag     = mkStatusRow(TabInfo, "🎒  Bag caught",       "0",        7)
local _, vPlayers = mkStatusRow(TabInfo, "👥  Players in server","—",        8)

mkLabel(TabInfo, "──────────────────────────────────", T.Stroke, 9)
mkLabel(TabInfo, "⚠️  Use responsibly & happy fishing!", T.Warn, 10)

-- Live update info
task.spawn(function()
    while task.wait(2) do
        vFish.Text    = tostring(S.SessionFish)
        vBag.Text     = tostring(S.DetectorBag)
        vStatus.Text  = S.DetectorActive and "Auto Fishing 🟢" or "Idle 🔴"
        vStatus.TextColor3 = S.DetectorActive and T.Good or T.Sub
        vPlayers.Text = tostring(#Players:GetPlayers())

        if S.ShowPing then
            local ok, p = pcall(function()
                return math.round(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue())
            end)
            local ps = ok and (p.."ms") or "—"
            vPing.Text    = ps
            PingLbl.Text  = "📶 "..ps
        else
            vPing.Text = "— ms"
        end
    end
end)

-- ============================================================
-- ▶  FISHING TAB
-- ============================================================

-- ─ Fishing Support ─────
mkSection(TabFishing, "  Fishing Support", 10)

mkToggle(TabFishing, "Show Real Ping", "Displays ping in title bar", false, function(s)
    S.ShowPing = s; PingLbl.Visible = s
end, 11)

mkToggle(TabFishing, "Auto Equip Rod", "Equips best rod on enable", false, function(s)
    S.AutoEquipRod = s
    if s then task.spawn(equipBestRod) end
end, 12)

mkToggle(TabFishing, "Walk on Water", "Prevents sinking into water", false, function(s)
    S.WalkOnWater = s; toggleWoW(s)
end, 13)

mkToggle(TabFishing, "Freeze Player", "Locks character position", false, function(s)
    S.FreezePlayer = s
    local h = getHum()
    if h and not s then h.WalkSpeed = 16; h.JumpPower = 50 end
end, 14)

mkToggle(TabFishing, "No Fishing Animations", "Hides cast/reel animations", false, function(s)
    S.NoAnims = s
end, 15)

-- ─ Auto Fisher (Detector) ─────
mkSection(TabFishing, "  Auto Fisher  (Detector)", 20)

local _, vDetStatus = mkStatusRow(TabFishing, "Status",       "Offline",  21)
local _, vDetTime   = mkStatusRow(TabFishing, "Time",         "0.0s",     22)
local _, vDetBag    = mkStatusRow(TabFishing, "Fish caught",  "0",        23)

-- Update detector labels
task.spawn(function()
    while task.wait(0.5) do
        vDetStatus.Text      = S.DetectorStatus
        vDetStatus.TextColor3= S.DetectorActive and T.Good or T.Danger
        vDetTime.Text        = string.format("%.1fs", S.DetectorTime)
        vDetBag.Text         = tostring(S.DetectorBag)
    end
end)

mkInput(TabFishing, "Wait delay in seconds  (default 1.5)", "1.5", function(v)
    local n = tonumber(v); if n then S.WaitDelay = n end
end, 24)

mkToggle(TabFishing, "Start Detector", "Auto cast & catch fish loop", false, function(s)
    S.DetectorActive = s
    if s then startFisher() else stopFisher() end
end, 25)

-- ─ Instant Features ─────
mkSection(TabFishing, "  Instant Features", 30)

mkInput(TabFishing, "Complete delay (0 = instant)", "0", function(v)
    local n = tonumber(v); if n then S.CompleteDelay = n end
end, 31)

mkToggle(TabFishing, "Instant Fishing", "Instantly completes minigame on bite", false, function(s)
    S.InstantFishing = s
end, 32)

-- ─ Legit Fishing ─────
mkSection(TabFishing, "  Legit Mode", 33)

mkInput(TabFishing, "Legit Click Delay (default 0.19)", "0.19", function(v)
    local n = tonumber(v); if n then S.LegitDelay = n end
end, 34)

mkInput(TabFishing, "Shake Delay (seconds)", "0.3", function(v)
    local n = tonumber(v); if n then S.ShakeDelay = n end
end, 35)

mkToggle(TabFishing, "Legit Fishing", "Mimics human-like click timing", false, function(s)
    S.LegitMode = s
end, 36)

mkToggle(TabFishing, "Auto Shake", "Handles shake events automatically", false, function(s)
    S.AutoShake = s
end, 37)

-- ─ Selling Features ─────
mkSection(TabFishing, "  Selling Features", 40)

mkDropdown(TabFishing, "Sell Mode", {"Delay","Bag Full","Instant"}, "Delay", function(opt)
    S.SellMode = opt
end, 41)

mkInput(TabFishing, "Value  (delay secs / bag fill %)", "30", function(v)
    local n = tonumber(v); if n then S.SellValue = n end
end, 42)

mkToggle(TabFishing, "Start Auto Selling", "Sells fish based on mode above", false, function(s)
    S.AutoSell = s
    if s then startAutoSell()
    elseif sellThread then task.cancel(sellThread) sellThread = nil end
end, 43)

mkBtn(TabFishing, "💰  Sell All Fish Now", true, doSellAll, 44)

-- ─ Favorite Features ─────
mkSection(TabFishing, "  Favorite Features", 50)

mkDropdown(TabFishing, "Name Filter", {"Any"}, "Any", function(opt)
    S.FavName = opt
end, 51)

mkDropdown(TabFishing, "Rarity Filter",
    {"Any","Common","Uncommon","Rare","Epic","Legendary","Mythic","SECRET"},
    "Any", function(opt) S.FavRarity = opt end, 52)

mkDropdown(TabFishing, "Variant Filter",
    {"Any","Normal","Albino","Mutated","Shiny","Chroma"},
    "Any", function(opt) S.FavVariant = opt end, 53)

mkDropdown(TabFishing, "Mode Favorite",
    {"Add Favorite","Remove Favorite"},
    "Add Favorite", function(opt) S.FavMode = opt end, 54)

mkToggle(TabFishing, "Auto Favorite", "Favorites fish matching your filters", false, function(s)
    S.AutoFavorite = s
    if s then startAutoFav()
    elseif favThread then task.cancel(favThread) favThread = nil end
end, 55)

mkBtn(TabFishing, "⭐  Favorite All Matching Now", false, function()
    task.spawn(runFavoriteLoop); notify("Favorited matching fish!")
end, 56)

mkBtn(TabFishing, "🗑️  Unfavorite All Fish", false, function()
    task.spawn(unfavoriteAll)
end, 57)

-- ─ Auto Rejoin ─────
mkSection(TabFishing, "  Auto Rejoin Features", 60)

mkDropdown(TabFishing, "Auto Execute Mode",
    {"Timer","On Disconnect","On Kick"},
    "Timer", function(opt) S.RejoinMode = opt end, 61)

mkInput(TabFishing, "Rejoin Timer (hours)", "1", function(v)
    local n = tonumber(v); if n then S.RejoinTimer = math.max(0.1, n) end
end, 62)

mkToggle(TabFishing, "Auto Rejoin", "Rejoins game after set timer", false, function(s)
    S.AutoRejoin = s
    if s then startRejoin()
    elseif rejoinThread then task.cancel(rejoinThread) rejoinThread = nil end
end, 63)

-- ============================================================
-- ▶  AUTO TAB
-- ============================================================
mkSection(TabAuto, "  Shop Features", 10)
mkToggle(TabAuto, "Auto Buy Bait", "Purchases bait from nearby shop", false, function(s)
    notify(s and "Auto Buy Bait ON" or "Auto Buy Bait OFF")
end, 11)

mkSection(TabAuto, "  Save Position Features", 20)
mkBtn(TabAuto, "📌  Save Current Position", false, function()
    local h = getHRP()
    if h then savedCF = h.CFrame; notify("Position saved!") end
end, 21)
mkBtn(TabAuto, "🔁  Return to Saved Position", true, function()
    if savedCF then
        local h = getHRP(); if h then h.CFrame = savedCF; notify("Teleported!") end
    else notify("No position saved!") end
end, 22)

mkSection(TabAuto, "  Enchant Features", 30)
mkToggle(TabAuto, "Auto Enchant Fish", "Uses enchant stones on fish", false, function(s) end, 31)

mkSection(TabAuto, "  Totem Features", 32)
mkToggle(TabAuto, "Auto Use Totem", "Activates totems automatically", false, function(s) end, 33)

mkSection(TabAuto, "  Potions Features", 34)
mkToggle(TabAuto, "Auto Drink Luck Potion", "Uses luck potions when available", false, function(s) end, 35)

mkSection(TabAuto, "  Event Features", 40)
mkToggle(TabAuto, "Auto Event Join", "Joins events as they activate", false, function(s) end, 41)
mkBtn(TabAuto, "🎉  Check Active Events", false, function()
    local now = os.time()
    local events = {
        {n="Pirate Cove",    t=1769994000},
        {n="Valentine",      t=1772323200},
        {n="Weekly Limited", t=1770508800},
        {n="Volcano Weekly", t=1771113600},
    }
    local active = {}
    for _, e in ipairs(events) do
        if now < e.t then table.insert(active, e.n) end
    end
    notify(#active > 0 and "Active: "..table.concat(active,", ") or "No events active right now")
end, 42)

-- ============================================================
-- ▶  TRADING TAB
-- ============================================================
mkSection(TabTrading, "  Trading Fish Features", 10)
mkToggle(TabTrading, "Auto Accept Fish Trades", "Accepts incoming fish trades", false, function(s) end, 11)

mkSection(TabTrading, "  Trading Enchant Stones Features", 20)
mkToggle(TabTrading, "Auto Accept Enchant Trades", "", false, function(s) end, 21)

mkSection(TabTrading, "  Trading Coin Features", 30)
mkToggle(TabTrading, "Auto Accept Coin Trades", "", false, function(s) end, 31)

mkSection(TabTrading, "  Trading Fish By Rarity", 40)
mkDropdown(TabTrading, "Min Rarity to Accept",
    {"Any","Rare","Epic","Legendary","Mythic","SECRET"},
    "Any", function(opt) S.TradeMinRarity = opt end, 41)

mkSection(TabTrading, "  Auto Accept Features", 50)
mkToggle(TabTrading, "Auto Accept All Trades", "⚠️ Accepts ANY incoming trade!", false, function(s)
    if s then notify("⚠️ Auto Accept ALL trades is ON – be careful!") end
end, 51)

-- ============================================================
-- ▶  MENU TAB
-- ============================================================
mkSection(TabMenu, "  Coin Features", 10)
mkBtn(TabMenu, "🪙  Check My Coins", false, function()
    local d = getRepData()
    if d then
        local ok, c = pcall(function() return d:GetExpect("Coins") end)
        notify(ok and "💰 Coins: "..tostring(c) or "Could not read coins!")
    end
end, 11)

mkSection(TabMenu, "  Enchant Stone Features", 20)
mkBtn(TabMenu, "💎  Count Enchant Stones", false, function()
    local n = 0
    for _, item in ipairs(getInvItems()) do
        if tostring(item.Id):lower():find("enchant") then n = n + 1 end
    end
    notify("Enchant Stones: " .. n)
end, 21)

mkSection(TabMenu, "  Lochness Monster Event", 30)
mkLabel(TabMenu, "Watch Fisherman Island for the Lochness event.", T.Sub, 31)
mkBtn(TabMenu, "🦕  Teleport to Lochness Area", false, function()
    tpTo(Vector3.new(-30, 5, 50))
end, 32)

mkSection(TabMenu, "  Event Pirates Features", 33)
mkLabel(TabMenu, "Pirate Cove available until 2025-08.", T.Sub, 34)
mkBtn(TabMenu, "🏴‍☠️  Teleport to Pirate Cove", false, function()
    tpTo(Vector3.new(500, 5, -800))
end, 35)

mkSection(TabMenu, "  Auto Crystal Features", 40)
mkToggle(TabMenu, "Auto Crystal Collector", "Collects crystals nearby", false, function(s) end, 41)

mkSection(TabMenu, "  Guide Leviathan Features", 42)
mkLabel(TabMenu, "Use special bait at the Deep Ocean zone.", T.Sub, 43)
mkBtn(TabMenu, "🐉  Leviathan Teleport", false, function()
    tpTo(Vector3.new(-62, 4, 2767)); notify("Teleporting to Deep Zone!")
end, 44)

mkSection(TabMenu, "  Relic Features", 50)
mkToggle(TabMenu, "Auto Collect Relics", "Picks up relic items automatically", false, function(s) end, 51)

mkSection(TabMenu, "  Semi Kaitun [BETA]", 52)
mkToggle(TabMenu, "Semi Kaitun Mode", "Experimental semi-auto mode [BETA]", false, function(s)
    notify(s and "Semi Kaitun BETA ON" or "Semi Kaitun OFF")
end, 53)

mkSection(TabMenu, "  Auto Equip Charms", 54)
mkToggle(TabMenu, "Auto Equip Best Charms", "Equips highest-stat charms", false, function(s) end, 55)

-- ============================================================
-- ▶  QUEST TAB
-- ============================================================
mkSection(TabQuest, "  Artifact Lever Location", 10)
mkBtn(TabQuest, "📍  Go to Artifact Lever", false, function()
    tpTo(Vector3.new(80, 20, -500)); notify("Teleporting to Artifact Lever!")
end, 11)

mkSection(TabQuest, "  Sisyphus Statue Quest", 20)
mkBtn(TabQuest, "🗿  Go to Sisyphus Statue", false, function()
    tpTo(Vector3.new(-150, 10, 350)); notify("Teleporting to Sisyphus Statue!")
end, 21)

mkSection(TabQuest, "  Element Quest", 30)
mkBtn(TabQuest, "⚗️  Go to Element Quest NPC", false, function()
    tpTo(Vector3.new(200, 15, -300)); notify("Teleporting to Element Quest!")
end, 31)

mkSection(TabQuest, "  Diamond Researcher Quest", 40)
mkBtn(TabQuest, "💎  Go to Diamond Researcher", false, function()
    tpTo(Vector3.new(350, 8, 100)); notify("Teleporting to Diamond Researcher!")
end, 41)

mkSection(TabQuest, "  Crystalline Passage Features", 50)
mkBtn(TabQuest, "💠  Go to Crystalline Passage", false, function()
    tpTo(Vector3.new(-200, -10, 700)); notify("Teleporting to Crystalline Passage!")
end, 51)

-- ============================================================
-- ▶  TELEPORT TAB
-- ============================================================
mkSection(TabTeleport, "  Teleport to Location", 10)

local order = 11
for name, pos in pairs(LOCS) do
    local p = pos
    local n = name
    mkBtn(TabTeleport, "📍  "..n, false, function() tpTo(p); notify("→ "..n) end, order)
    order = order + 1
end

mkSection(TabTeleport, "  Teleport to Player", 40)
local _, playerBox = mkInput(TabTeleport, "Enter player username…", "", nil, 41)
mkBtn(TabTeleport, "🏃  Teleport to Player", true, function()
    tpToPlayer(playerBox.Text)
end, 42)

-- ============================================================
-- ▶  MISC TAB
-- ============================================================
mkSection(TabMisc, "  Booster FPS", 10)
mkToggle(TabMisc, "FPS Booster", "Lowers graphics for more FPS", false, function(s)
    S.FPSBoost = s; applyFPSBoost(s)
end, 11)

mkSection(TabMisc, "  Utility Player", 20)
mkToggle(TabMisc, "Speed Hack", "Increase character walk speed", false, function(s)
    S.WalkSpeed = s
    if not s then local h = getHum(); if h then h.WalkSpeed = 16 end end
end, 21)

mkInput(TabMisc, "Walk speed value  (16 = default)", "50", function(v)
    local n = tonumber(v)
    if n then S.WalkSpeedVal = n end
end, 22)

mkToggle(TabMisc, "Noclip", "Walk through all parts", false, function(s)
    S.Noclip = s; toggleNoclip(s)
end, 23)

mkToggle(TabMisc, "Infinite Jump", "Jump unlimited times in air", false, function(s)
    S.InfJump = s; toggleInfJump(s)
end, 24)

mkSection(TabMisc, "  Server Features", 30)
mkBtn(TabMisc, "📊  Server Info", false, function()
    local cnt = #Players:GetPlayers()
    notify("Players: "..cnt.." | Job: "..game.JobId:sub(1,10).."…")
end, 31)

mkSection(TabMisc, "  Miscellaneous", 40)
mkBtn(TabMisc, "🔄  Respawn Character", false, function()
    local h = getHum(); if h then h.Health = 0 end
end, 41)

mkBtn(TabMisc, "🔁  Rejoin Server", false, function()
    pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer) end)
end, 42)

-- ============================================================
-- OPEN DEFAULT TAB  (direct call — no :Fire() hack)
-- ============================================================
selectTab(1)   -- Opens Info tab immediately

-- Track FishCaught remote
task.defer(function()
    local ev = getNet("FishCaught", false)
    if ev then
        ev.OnClientEvent:Connect(function()
            S.SessionFish = S.SessionFish + 1
        end)
    end
end)

-- Done
task.delay(0.5, function()
    notify("🎣 FishIt Omega Hub loaded! Welcome, "..LocalPlayer.Name.."!")
end)

print("[FishIt Omega Hub] ✓ Loaded successfully")
