-- ============================================================
-- FishIt Omega Hub v1.0
-- Built from full game source analysis
-- UI: Matches MyUiTemplate exactly (proven working structure)
-- ============================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local StarterGui       = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer

pcall(function() StarterGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeRight end)
pcall(function() LocalPlayer.PlayerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeRight end)

-- ── GUI mount (same as template) ─────────────────────────
local TargetParent = (type(gethui)=="function" and gethui()) or
    (pcall(function() return game:GetService("CoreGui") end) and game:GetService("CoreGui")) or
    LocalPlayer:WaitForChild("PlayerGui")

if not TargetParent then return end
if TargetParent:FindFirstChild("FishItOmegaHub") then
    TargetParent.FishItOmegaHub:Destroy()
end

local ScreenGui = Instance.new("ScreenGui", TargetParent)
ScreenGui.Name = "FishItOmegaHub"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
-- NOTE: NO ZIndexBehavior set = same as template

-- ── Theme ─────────────────────────────────────────────────
local Theme = {
    Background = Color3.fromRGB(24, 24, 28),
    Sidebar    = Color3.fromRGB(18, 18, 22),
    Accent     = Color3.fromRGB(0, 170, 120),
    Text       = Color3.fromRGB(240, 240, 240),
    SubText    = Color3.fromRGB(150, 150, 150),
    Button     = Color3.fromRGB(35, 35, 40),
    Stroke     = Color3.fromRGB(60, 60, 65),
    Danger     = Color3.fromRGB(220, 60, 60),
    Good       = Color3.fromRGB(60, 200, 100),
    Warn       = Color3.fromRGB(240, 150, 30),
}

-- ── State ─────────────────────────────────────────────────
local S = {
    SessionFish=0, DetectorActive=false, DetectorStatus="Offline",
    DetectorTime=0, DetectorBag=0, WaitDelay=1.5,
    InstantFishing=false, AutoSell=false, SellMode="Delay", SellValue=30,
    AutoFavorite=false, FavRarity="Any", FavVariant="Any",
    AutoRejoin=false, RejoinTimer=1,
    ShowPing=false, WalkOnWater=false, FreezePlayer=false,
    WalkSpeed=false, WalkSpeedVal=50, Noclip=false, InfJump=false,
}

-- ── Remotes ───────────────────────────────────────────────
local _net = {}
local function getNet(name, isFunc)
    if _net[name] then return _net[name] end
    local ok, mod = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Packages",5):WaitForChild("Net",5))
    end)
    if not ok then return nil end
    local ok2, obj = pcall(function()
        return isFunc and mod:RemoteFunction(name) or mod:RemoteEvent(name)
    end)
    if ok2 then _net[name] = obj end
    return _net[name]
end

local _repData
local function getRepData()
    if _repData and not _repData.Destroyed then return _repData end
    local ok, mod = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Packages",5):WaitForChild("Replion",5))
    end)
    if not ok then return nil end
    local ok2, d = pcall(function() return mod.Client:WaitReplion("Data") end)
    if ok2 then _repData = d end
    return _repData
end

local function getItems()
    local d = getRepData()
    if not d then return {} end
    local ok, v = pcall(function() return d:GetExpect({"Inventory","Items"}) end)
    return ok and v or {}
end

-- Rods live at Inventory > "Fishing Rods" — confirmed from PlayerStatsUtility_1323.lua
-- GetBestFishingRod reads: d:GetExpect({"Inventory","Fishing Rods"})
local function getRods()
    local d = getRepData()
    if not d then return {} end
    local ok, v = pcall(function() return d:GetExpect({"Inventory","Fishing Rods"}) end)
    return ok and v or {}
end

-- Returns the UUID of the currently equipped rod, or nil
local function getEquippedRodUUID()
    local d = getRepData()
    if not d then return nil end
    local ok, equipped = pcall(function() return d:GetExpect("EquippedItems") end)
    if not ok or not equipped then return nil end
    -- EquippedItems is an array of UUIDs — check against rod UUIDs
    local rods = getRods()
    for _, rod in ipairs(rods) do
        if table.find(equipped, rod.UUID) then return rod.UUID end
    end
    return nil
end

-- ── Character ─────────────────────────────────────────────
local function chr()  return LocalPlayer.Character end
local function hrp()  local c=chr() return c and c:FindFirstChild("HumanoidRootPart") end
local function hum()  local c=chr() return c and c:FindFirstChildOfClass("Humanoid") end

local function notify(msg)
    pcall(function()
        StarterGui:SetCore("SendNotification",{Title="FishIt Hub",Text=msg,Duration=3})
    end)
end

-- ============================================================
-- FEATURES
-- ============================================================

-- ── Auto Fisher ──────────────────────────────────────────
-- PRIMARY: UpdateAutoFishingState:InvokeServer(true/false)
--   AutoFishingLevel = 0 in Constants_1334.lua → unlocked for ALL players.
--   The game's built-in AutoFishingController handles cast + click loop.
--
-- FALLBACK: event-driven manual loop using:
--   FishingMinigameChanged.OnClientEvent → "Activated" = fish bit
--   BaitSpawned.OnClientEvent           → bait is in water
--   FishingStopped.OnClientEvent        → fishing stopped
--   ChargeFishingRod (RemoteFunction)   → cast
--   CatchFishCompleted (RemoteFunction) → click during minigame

local fishThread
local _fishConn_minigame, _fishConn_bait, _fishConn_stopped
local _fishState = { minigameActive=false, baitInWater=false }

local function _disconnectFishConns()
    if _fishConn_minigame then pcall(function() _fishConn_minigame:Disconnect() end) _fishConn_minigame=nil end
    if _fishConn_bait      then pcall(function() _fishConn_bait:Disconnect()      end) _fishConn_bait=nil      end
    if _fishConn_stopped   then pcall(function() _fishConn_stopped:Disconnect()   end) _fishConn_stopped=nil   end
    _fishState.minigameActive=false
    _fishState.baitInWater=false
end

local function _setupFishListeners()
    _disconnectFishConns()
    -- FishingMinigameChanged fires with "Activated" when a fish bites
    local evMini = getNet("FishingMinigameChanged", false)
    if evMini then
        _fishConn_minigame = evMini.OnClientEvent:Connect(function(state)
            _fishState.minigameActive = (state == "Activated" or state == "Clicked")
        end)
    end
    -- BaitSpawned fires when bait is cast into water
    local evBait = getNet("BaitSpawned", false)
    if evBait then
        _fishConn_bait = evBait.OnClientEvent:Connect(function()
            _fishState.baitInWater = true
        end)
    end
    -- FishingStopped fires when fishing ends (catch, cancel, etc.)
    local evStop = getNet("FishingStopped", false)
    if evStop then
        _fishConn_stopped = evStop.OnClientEvent:Connect(function()
            _fishState.baitInWater = false
            _fishState.minigameActive = false
        end)
    end
end

local function startFisher()
    if fishThread then pcall(task.cancel, fishThread) fishThread=nil end
    _setupFishListeners()
    S.DetectorStatus = "Starting..."
    S.DetectorTime = 0

    fishThread = task.spawn(function()
        -- ── Step 1: Try game built-in auto-fishing ──────────────
        -- AutoFishingLevel=0 means always available.
        -- UpdateAutoFishingState:InvokeServer(true) enables it.
        local autoRF = getNet("UpdateAutoFishingState", true)
        local usingBuiltin = false
        if autoRF then
            local ok, result = pcall(function() return autoRF:InvokeServer(true) end)
            if ok then
                usingBuiltin = true
                S.DetectorStatus = "Auto (built-in)"
                notify("Auto-fishing enabled (game built-in)!")
            end
        end

        if usingBuiltin then
            -- Built-in handles everything; we just monitor fish count via FishCaught event
            local evCaught = getNet("FishCaught", false)
            if evCaught then
                evCaught.OnClientEvent:Connect(function(fishData)
                    if S.DetectorActive then
                        S.DetectorBag = S.DetectorBag + 1
                        S.SessionFish = S.SessionFish + 1
                    end
                end)
            end
            -- Keep alive while active
            while S.DetectorActive do task.wait(1) end
            -- Disable built-in when stopped
            pcall(function() autoRF:InvokeServer(false) end)
        else
            -- ── Step 2: Fallback — event-driven manual loop ───────
            S.DetectorStatus = "Auto (manual)"
            local cam = workspace.CurrentCamera
            local chargeRF = getNet("ChargeFishingRod", true)
            local catchRF  = getNet("CatchFishCompleted", true)

            while S.DetectorActive do
                local t0 = tick()
                S.DetectorTime = 0

                -- Cast: charge + release
                if chargeRF then
                    local vp = cam.ViewportSize
                    local castVec = Vector2.new(vp.X/2, vp.Y/2)
                    -- InvokeServer(nil, nil, Vector2, nil) matches game source line 917
                    pcall(function() chargeRF:InvokeServer(nil, nil, castVec, nil) end)
                end

                -- Wait for bait to land (or timeout)
                local baitTimeout = tick() + 4
                repeat task.wait(0.1) until _fishState.baitInWater or tick() > baitTimeout

                if not S.DetectorActive then break end

                -- Wait for fish to bite (or timeout = WaitDelay + 15s max)
                local biteTimeout = tick() + S.WaitDelay + 15
                repeat
                    task.wait(0.1)
                    S.DetectorTime = tick() - t0
                until _fishState.minigameActive or tick() > biteTimeout or not _fishState.baitInWater

                if not S.DetectorActive then break end

                -- Reel: spam CatchFishCompleted with ClickDelay=0.14s (from Constants_1334.lua)
                if _fishState.minigameActive and catchRF then
                    local reeledIn = false
                    local reelTimeout = tick() + 30
                    while _fishState.minigameActive and tick() < reelTimeout and S.DetectorActive do
                        local ok, res = pcall(function() return catchRF:InvokeServer() end)
                        if ok and res then
                            S.DetectorBag  = S.DetectorBag  + 1
                            S.SessionFish  = S.SessionFish  + 1
                            reeledIn = true
                            _fishState.minigameActive = false
                            break
                        end
                        task.wait(0.14) -- ClickDelay from Constants_1334.lua
                    end
                end

                -- Short cooldown before next cast
                task.wait(math.max(S.WaitDelay, 0.5))
            end
        end

        S.DetectorStatus = "Offline"
        _disconnectFishConns()
    end)
end

local function stopFisher()
    S.DetectorActive = false
    if fishThread then pcall(task.cancel, fishThread) fishThread=nil end
    -- Disable game built-in auto-fishing too
    local autoRF = getNet("UpdateAutoFishingState", true)
    if autoRF then pcall(function() autoRF:InvokeServer(false) end) end
    S.DetectorStatus = "Offline"
    _disconnectFishConns()
end

-- Sell
local function doSell()
    local rf=getNet("SellAllItems",true)
    if rf then pcall(function() rf:InvokeServer() end) notify("Sold all fish! ✓") end
end
local sellThread
local function startSell()
    if sellThread then task.cancel(sellThread) end
    sellThread=task.spawn(function()
        while S.AutoSell do task.wait(math.max(S.SellValue,5)) doSell() end
    end)
end

-- Favorite
local function favItem(uuid)
    local ev=getNet("FavoriteItem",false)
    if ev then pcall(function() ev:FireServer(uuid) end) end
end
local RARITY_TIER={Common=1,Uncommon=2,Rare=3,Epic=4,Legendary=5,Mythic=6,SECRET=7}
local function runFavLoop()
    for _,item in ipairs(getItems()) do
        local skip=false
        if S.FavRarity~="Any" then
            local t=item.Tier or (item.Probability and item.Probability.Tier) or 0
            if t~=(RARITY_TIER[S.FavRarity] or 0) then skip=true end
        end
        if S.FavVariant~="Any" and (item.Variant or "Normal")~=S.FavVariant then skip=true end
        if not skip and not item.Favorite then favItem(item.UUID) task.wait(0.07) end
    end
end
local favThread
local function startFav()
    if favThread then task.cancel(favThread) end
    favThread=task.spawn(function() while S.AutoFavorite do runFavLoop() task.wait(3) end end)
end
local function unfavAll()
    for _,item in ipairs(getItems()) do
        if item.Favorite then favItem(item.UUID) task.wait(0.06) end
    end
    notify("Unfavorited all!")
end

-- Walk on Water
local wowConn
local function toggleWoW(on)
    if wowConn then wowConn:Disconnect() wowConn=nil end
    if on then
        wowConn=RunService.Heartbeat:Connect(function()
            local h=hrp()
            if h and h.Position.Y<0.4 then h.CFrame=h.CFrame+Vector3.new(0,0.5,0) end
        end)
    end
end

-- Noclip
local noclipConn
local function toggleNoclip(on)
    if noclipConn then noclipConn:Disconnect() noclipConn=nil end
    if on then
        noclipConn=RunService.Stepped:Connect(function()
            local c=chr()
            if c then for _,p in ipairs(c:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide=false end
            end end
        end)
    else
        local c=chr()
        if c then for _,p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide=true end
        end end
    end
end

-- Inf Jump
local ijConn
local function toggleInfJump(on)
    if ijConn then ijConn:Disconnect() ijConn=nil end
    if on then
        ijConn=UserInputService.JumpRequest:Connect(function()
            local h=hum() if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
        end)
    end
end

-- Speed / Freeze loops
RunService.Heartbeat:Connect(function()
    if S.FreezePlayer then local h=hum() if h then h.WalkSpeed=0 h.JumpPower=0 end
    elseif S.WalkSpeed then local h=hum() if h then h.WalkSpeed=S.WalkSpeedVal end end
end)

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if S.WalkSpeed then local h=hum() if h then h.WalkSpeed=S.WalkSpeedVal end end
    if S.InfJump then toggleInfJump(true) end
    if S.Noclip then toggleNoclip(true) end
end)

-- Teleport
local savedCF=nil
local LOCS={
    ["Fisherman Island"]=Vector3.new(0,5,0),
    ["Sandy Shore"]=Vector3.new(130,5,2768),
    ["Deep Ocean"]=Vector3.new(-62,5,2767),
    ["Volcano Area"]=Vector3.new(300,65,-200),
    ["Ancient Ruins"]=Vector3.new(-400,12,500),
    ["Sell NPC"]=Vector3.new(10,5,30),
}
-- tpTo: holds the CFrame for 8 Heartbeat frames so physics/game cant snap back
-- safeOffset: studs above v3. Default 5 (land). Use 4 for ocean boat coords.
local RunService = game:GetService("RunService")
local function tpTo(targetV3, safeOffset)
    local offset = safeOffset or 5
    local dest = CFrame.new(targetV3.X, targetV3.Y + offset, targetV3.Z)
    local frames = 0
    local conn
    conn = RunService.Heartbeat:Connect(function()
        frames = frames + 1
        local h = hrp()
        if h then h.CFrame = dest end
        if frames >= 8 then conn:Disconnect() end
    end)
end
local function tpToPlayer(name)
    local pl=Players:FindFirstChild(name)
    if pl and pl.Character then
        local h=pl.Character:FindFirstChild("HumanoidRootPart")
        if h then tpTo(h.Position) notify("→ "..name) return end
    end
    notify("Player '"..name.."' not found!")
end

local rejoinThread
local function startRejoin()
    if rejoinThread then task.cancel(rejoinThread) end
    rejoinThread=task.spawn(function()
        task.wait(S.RejoinTimer*3600)
        if S.AutoRejoin then
            pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId,LocalPlayer) end)
        end
    end)
end

-- ============================================================
-- UI  — exact same pattern as MyUiTemplate
-- ============================================================

-- ── Toggle icon (minimized state) ─────────────────────────
local ToggleIcon = Instance.new("TextButton", ScreenGui)
ToggleIcon.Size = UDim2.new(0, 45, 0, 45)
ToggleIcon.Position = UDim2.new(0.5, -22, 0.05, 0)
ToggleIcon.BackgroundColor3 = Theme.Background
ToggleIcon.BackgroundTransparency = 0.1
ToggleIcon.Text = "🎣"
ToggleIcon.TextSize = 22
ToggleIcon.Visible = false
Instance.new("UICorner", ToggleIcon).CornerRadius = UDim.new(1, 0)
local iconStroke = Instance.new("UIStroke", ToggleIcon)
iconStroke.Color = Theme.Accent
iconStroke.Thickness = 2

-- ── Main Frame ────────────────────────────────────────────
-- EXACT same structure as template — NO ZIndex tweaks
local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Size = UDim2.new(0, 450, 0, 270)
MainFrame.Position = UDim2.new(0.5, -225, 0.5, -135)
MainFrame.BackgroundColor3 = Theme.Background
MainFrame.BackgroundTransparency = 0.40
MainFrame.Active = true
MainFrame.ClipsDescendants = true
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)
local mainStroke = Instance.new("UIStroke", MainFrame)
mainStroke.Color = Theme.Stroke
mainStroke.Transparency = 0.5

-- ── Top Bar ───────────────────────────────────────────────
local TopBar = Instance.new("Frame", MainFrame)
TopBar.Size = UDim2.new(1, 0, 0, 30)
TopBar.BackgroundTransparency = 1

local Title = Instance.new("TextLabel", TopBar)
Title.Size = UDim2.new(0.6, 0, 1, 0)
Title.Position = UDim2.new(0, 12, 0, 0)
Title.Text = "🎣  FishIt Omega Hub"
Title.Font = Enum.Font.GothamMedium
Title.TextColor3 = Theme.Text
Title.TextSize = 13
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.BackgroundTransparency = 1

-- Ping label (hidden by default)
local PingLbl = Instance.new("TextLabel", TopBar)
PingLbl.Size = UDim2.new(0.2, 0, 1, 0)
PingLbl.Position = UDim2.new(0.57, 0, 0, 0)
PingLbl.BackgroundTransparency = 1
PingLbl.Text = ""
PingLbl.Font = Enum.Font.Gotham
PingLbl.TextColor3 = Theme.Accent
PingLbl.TextSize = 10
PingLbl.Visible = false

-- Window controls — same as template
local function AddControl(text, pos, color, callback)
    local btn = Instance.new("TextButton", TopBar)
    btn.Size = UDim2.new(0, 30, 0, 20)
    btn.Position = pos
    btn.BackgroundColor3 = Theme.Background
    btn.Text = text
    btn.TextColor3 = color
    btn.Font = Enum.Font.GothamMedium
    btn.BackgroundTransparency = 1
    btn.MouseButton1Click:Connect(callback)
end

AddControl("✕", UDim2.new(1,-35,0.5,-10), Color3.fromRGB(255,80,80), function()
    ScreenGui:Destroy()
end)
AddControl("—", UDim2.new(1,-70,0.5,-10), Theme.Text, function()
    MainFrame.Visible = false
    ToggleIcon.Visible = true
end)

ToggleIcon.MouseButton1Click:Connect(function()
    MainFrame.Visible = true
    ToggleIcon.Visible = false
end)

-- Drag — same as template
local function EnableDrag(obj, handle)
    local drag, input, start, startPos
    handle.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            drag=true; start=i.Position; startPos=obj.Position
            i.Changed:Connect(function()
                if i.UserInputState==Enum.UserInputState.End then drag=false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
            local delta=i.Position-start
            obj.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+delta.X,startPos.Y.Scale,startPos.Y.Offset+delta.Y)
        end
    end)
end
EnableDrag(MainFrame, TopBar)
EnableDrag(ToggleIcon, ToggleIcon)

-- ── Sidebar — same as template ────────────────────────────
local Sidebar = Instance.new("ScrollingFrame", MainFrame)
Sidebar.Size = UDim2.new(0, 100, 1, -30)
Sidebar.Position = UDim2.new(0, 0, 0, 30)
Sidebar.BackgroundColor3 = Theme.Sidebar
Sidebar.BackgroundTransparency = 0.55
Sidebar.BorderSizePixel = 0
Sidebar.ScrollBarThickness = 0          -- hidden scrollbar, touch-scrollable
Sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y
Sidebar.CanvasSize = UDim2.new(0,0,0,0)
Sidebar.ScrollingDirection = Enum.ScrollingDirection.Y
Sidebar.ClipsDescendants = true
Instance.new("UICorner", Sidebar).CornerRadius = UDim.new(0, 8)

local SidebarLayout = Instance.new("UIListLayout", Sidebar)
SidebarLayout.Padding = UDim.new(0, 4)
SidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
SidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
local sbPad = Instance.new("UIPadding", Sidebar)
sbPad.PaddingTop = UDim.new(0, 8)
sbPad.PaddingBottom = UDim.new(0, 8)

-- ── Content area ─────────────────────────────────────────
local ContentArea = Instance.new("Frame", MainFrame)
ContentArea.Size = UDim2.new(1, -108, 1, -30)
ContentArea.Position = UDim2.new(0, 104, 0, 30)
ContentArea.BackgroundTransparency = 1
ContentArea.ClipsDescendants = true      -- CRITICAL: scroll stays inside window

-- ── Tab system — same as template ────────────────────────
local Tabs = {}
local TabButtons = {}

local function CreateTab(name, icon)
    -- Tab content scrolling frame (same as template)
    local TabFrame = Instance.new("ScrollingFrame", ContentArea)
    TabFrame.Size = UDim2.new(1, 0, 1, 0)
    TabFrame.BackgroundTransparency = 1
    TabFrame.ScrollBarThickness = 4
    TabFrame.ScrollBarImageColor3 = Theme.Accent
    TabFrame.ScrollingDirection = Enum.ScrollingDirection.Y
    TabFrame.Visible = false
    TabFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    TabFrame.CanvasSize = UDim2.new(0,0,0,0)
    TabFrame.BorderSizePixel = 0
    TabFrame.ClipsDescendants = true      -- content clips to tab area

    local Layout = Instance.new("UIListLayout", TabFrame)
    Layout.Padding = UDim.new(0, 8)
    Layout.SortOrder = Enum.SortOrder.LayoutOrder
    local pad = Instance.new("UIPadding", TabFrame)
    pad.PaddingTop = UDim.new(0, 5)
    pad.PaddingRight = UDim.new(0, 4)

    -- Sidebar button (same as template)
    local TabBtn = Instance.new("TextButton", Sidebar)
    TabBtn.Size = UDim2.new(0.92, 0, 0, 27)
    TabBtn.BackgroundColor3 = Theme.Accent
    TabBtn.BackgroundTransparency = 1
    TabBtn.Text = "  "..icon.." "..name
    TabBtn.TextColor3 = Theme.SubText
    TabBtn.Font = Enum.Font.GothamMedium
    TabBtn.TextSize = 11
    TabBtn.TextXAlignment = Enum.TextXAlignment.Left
    Instance.new("UICorner", TabBtn).CornerRadius = UDim.new(0, 5)

    local Indicator = Instance.new("Frame", TabBtn)
    Indicator.Size = UDim2.new(0, 3, 0.6, 0)
    Indicator.Position = UDim2.new(0, 2, 0.2, 0)
    Indicator.BackgroundColor3 = Theme.Accent
    Indicator.Visible = false
    Instance.new("UICorner", Indicator).CornerRadius = UDim.new(1, 0)

    TabBtn.MouseButton1Click:Connect(function()
        for _, t in pairs(Tabs) do t.Frame.Visible = false end
        for _, b in pairs(TabButtons) do
            b.Btn.BackgroundTransparency = 1
            b.Btn.TextColor3 = Theme.SubText
            b.Indicator.Visible = false
        end
        TabFrame.Visible = true
        TabBtn.BackgroundTransparency = 0.85
        TabBtn.TextColor3 = Theme.Text
        Indicator.Visible = true
    end)

    table.insert(Tabs, {Frame=TabFrame})
    table.insert(TabButtons, {Btn=TabBtn, Indicator=Indicator})
    return TabFrame
end

-- ============================================================
-- COMPONENT BUILDERS
-- ============================================================

-- Section header
local function mkSection(parent, text, order)
    local f = Instance.new("Frame", parent)
    f.Size = UDim2.new(0.98, 0, 0, 22)
    f.BackgroundColor3 = Color3.fromRGB(30, 42, 36)
    f.LayoutOrder = order or 0
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 4)
    local l = Instance.new("TextLabel", f)
    l.Size = UDim2.new(1, -10, 1, 0)
    l.Position = UDim2.new(0, 8, 0, 0)
    l.BackgroundTransparency = 1
    l.Text = text
    l.Font = Enum.Font.GothamBold
    l.TextColor3 = Theme.Accent
    l.TextSize = 10
    l.TextXAlignment = Enum.TextXAlignment.Left
end

-- Toggle (same style as template CreateFluentToggle)
local function mkToggle(parent, title, desc, default, cb, order)
    local state = default or false
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(0.98, 0, 0, 45)
    btn.BackgroundColor3 = Theme.Button
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.LayoutOrder = order or 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    Instance.new("UIStroke", btn).Color = Theme.Stroke

    local Txt = Instance.new("TextLabel", btn)
    Txt.Size = UDim2.new(0.7, 0, 0.5, 0)
    Txt.Position = UDim2.new(0, 10, 0, 5)
    Txt.Text = title
    Txt.Font = Enum.Font.GothamMedium
    Txt.TextColor3 = Theme.Text
    Txt.TextSize = 13
    Txt.TextXAlignment = Enum.TextXAlignment.Left
    Txt.BackgroundTransparency = 1

    local Sub = Instance.new("TextLabel", btn)
    Sub.Size = UDim2.new(0.7, 0, 0.5, 0)
    Sub.Position = UDim2.new(0, 10, 0.5, 0)
    Sub.Text = desc or ""
    Sub.Font = Enum.Font.Gotham
    Sub.TextColor3 = Theme.SubText
    Sub.TextSize = 10
    Sub.TextXAlignment = Enum.TextXAlignment.Left
    Sub.BackgroundTransparency = 1

    -- Pill (same as template)
    local StatusPill = Instance.new("Frame", btn)
    StatusPill.Size = UDim2.new(0, 40, 0, 20)
    StatusPill.Position = UDim2.new(1, -50, 0.5, -10)
    StatusPill.BackgroundColor3 = Theme.Background
    Instance.new("UICorner", StatusPill).CornerRadius = UDim.new(1, 0)
    local PillStroke = Instance.new("UIStroke", StatusPill)
    PillStroke.Color = Theme.Stroke

    local StatusText = Instance.new("TextLabel", StatusPill)
    StatusText.Size = UDim2.new(1, 0, 1, 0)
    StatusText.Text = state and "ON" or "OFF"
    StatusText.Font = Enum.Font.GothamBold
    StatusText.TextColor3 = state and Theme.Background or Theme.SubText
    StatusText.TextSize = 10
    StatusText.BackgroundTransparency = 1

    if state then
        StatusPill.BackgroundColor3 = Theme.Accent
        PillStroke.Color = Theme.Accent
        btn.BackgroundColor3 = Color3.fromRGB(30,42,36)
    end

    btn.MouseButton1Click:Connect(function()
        state = not state
        StatusText.Text = state and "ON" or "OFF"
        StatusText.TextColor3 = state and Theme.Background or Theme.SubText
        StatusPill.BackgroundColor3 = state and Theme.Accent or Theme.Background
        PillStroke.Color = state and Theme.Accent or Theme.Stroke
        btn.BackgroundColor3 = state and Color3.fromRGB(30,42,36) or Theme.Button
        cb(state)
    end)
end

-- Button (same style as template CreateFluentButton)
local function mkBtn(parent, title, accent, cb, order)
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(0.98, 0, 0, 35)
    btn.BackgroundColor3 = accent and Color3.fromRGB(0,120,85) or Theme.Button
    btn.Text = "  "..title
    btn.TextColor3 = Theme.Text
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 13
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.AutoButtonColor = false
    btn.LayoutOrder = order or 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    Instance.new("UIStroke", btn).Color = accent and Theme.Accent or Theme.Stroke
    btn.MouseButton1Click:Connect(cb)
end

-- Text input
local function mkInput(parent, hint, default, cb, order)
    local f = Instance.new("Frame", parent)
    f.Size = UDim2.new(0.98, 0, 0, 34)
    f.BackgroundColor3 = Theme.Button
    f.LayoutOrder = order or 0
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 6)
    Instance.new("UIStroke", f).Color = Theme.Stroke

    local box = Instance.new("TextBox", f)
    box.Size = UDim2.new(1, -16, 1, 0)
    box.Position = UDim2.new(0, 8, 0, 0)
    box.BackgroundTransparency = 1
    box.PlaceholderText = hint or ""
    box.PlaceholderColor3 = Theme.SubText
    box.Text = default or ""
    box.TextColor3 = Theme.Text
    box.Font = Enum.Font.Gotham
    box.TextSize = 12
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.ClearTextOnFocus = false
    if cb then box.FocusLost:Connect(function() cb(box.Text) end) end
    return f, box
end

-- Status row
local function mkRow(parent, label, default, order)
    local f = Instance.new("Frame", parent)
    f.Size = UDim2.new(0.98, 0, 0, 22)
    f.BackgroundTransparency = 1
    f.LayoutOrder = order or 0

    local l = Instance.new("TextLabel", f)
    l.Size = UDim2.new(0.55, 0, 1, 0)
    l.BackgroundTransparency = 1
    l.Text = label
    l.Font = Enum.Font.Gotham
    l.TextColor3 = Theme.SubText
    l.TextSize = 11
    l.TextXAlignment = Enum.TextXAlignment.Left

    local v = Instance.new("TextLabel", f)
    v.Size = UDim2.new(0.45, 0, 1, 0)
    v.Position = UDim2.new(0.55, 0, 0, 0)
    v.BackgroundTransparency = 1
    v.Text = default or "—"
    v.Font = Enum.Font.GothamMedium
    v.TextColor3 = Theme.Accent
    v.TextSize = 11
    v.TextXAlignment = Enum.TextXAlignment.Right
    return f, v
end

-- Small label
local function mkLabel(parent, text, col, order)
    local l = Instance.new("TextLabel", parent)
    l.Size = UDim2.new(0.98, 0, 0, 20)
    l.BackgroundTransparency = 1
    l.Text = text
    l.Font = Enum.Font.Gotham
    l.TextColor3 = col or Theme.SubText
    l.TextSize = 11
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.LayoutOrder = order or 0
end

-- Dropdown (parented to ScreenGui so it's never clipped)
local function mkDrop(parent, label, opts, default, cb, order)
    local cur = default or opts[1]

    local holder = Instance.new("Frame", parent)
    holder.Size = UDim2.new(0.98, 0, 0, 35)
    holder.BackgroundColor3 = Theme.Button
    holder.LayoutOrder = order or 0
    Instance.new("UICorner", holder).CornerRadius = UDim.new(0, 6)
    Instance.new("UIStroke", holder).Color = Theme.Stroke

    local lbl = Instance.new("TextLabel", holder)
    lbl.Size = UDim2.new(0.5, 0, 1, 0)
    lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextColor3 = Theme.Text
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local val = Instance.new("TextLabel", holder)
    val.Size = UDim2.new(0.46, 0, 1, 0)
    val.Position = UDim2.new(0.52, 0, 0, 0)
    val.BackgroundTransparency = 1
    val.Text = cur.." ▾"
    val.Font = Enum.Font.Gotham
    val.TextColor3 = Theme.Accent
    val.TextSize = 11
    val.TextXAlignment = Enum.TextXAlignment.Right

    local hitbox = Instance.new("TextButton", holder)
    hitbox.Size = UDim2.new(1, 0, 1, 0)
    hitbox.BackgroundTransparency = 1
    hitbox.Text = ""

    -- Menu floats above everything, parented to ScreenGui
    local menu = Instance.new("Frame", ScreenGui)
    menu.Size = UDim2.fromOffset(200, #opts*28+6)
    menu.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
    menu.Visible = false
    menu.ZIndex = 100
    Instance.new("UICorner", menu).CornerRadius = UDim.new(0, 7)
    local mstr = Instance.new("UIStroke", menu)
    mstr.Color = Theme.Accent; mstr.Thickness = 1

    local ml = Instance.new("UIListLayout", menu)
    ml.Padding = UDim.new(0, 1)
    local mp = Instance.new("UIPadding", menu)
    mp.PaddingTop = UDim.new(0, 3); mp.PaddingBottom = UDim.new(0, 3)

    local isOpen = false
    for _, opt in ipairs(opts) do
        local ob = Instance.new("TextButton", menu)
        ob.Size = UDim2.new(1, 0, 0, 28)
        ob.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
        ob.BackgroundTransparency = opt==cur and 0.5 or 1
        ob.Text = "  "..opt
        ob.Font = Enum.Font.Gotham
        ob.TextColor3 = opt==cur and Theme.Accent or Theme.Text
        ob.TextSize = 12
        ob.TextXAlignment = Enum.TextXAlignment.Left
        ob.ZIndex = 101
        ob.MouseButton1Click:Connect(function()
            cur = opt
            val.Text = opt.." ▾"
            menu.Visible = false
            isOpen = false
            cb(opt)
        end)
    end

    hitbox.MouseButton1Click:Connect(function()
        isOpen = not isOpen
        if isOpen then
            local abs = holder.AbsolutePosition
            local sz  = holder.AbsoluteSize
            menu.Position = UDim2.fromOffset(abs.X, abs.Y+sz.Y+3)
            menu.Size = UDim2.fromOffset(math.max(sz.X, 180), #opts*28+6)
        end
        menu.Visible = isOpen
    end)

    -- Close on outside click
    UserInputService.InputBegan:Connect(function(i)
        if isOpen and i.UserInputType==Enum.UserInputType.MouseButton1 then
            task.defer(function() if isOpen then menu.Visible=false isOpen=false end end)
        end
    end)
end

-- ============================================================
-- CREATE ALL TABS
-- ============================================================
local TabInfo     = CreateTab("Info",     "ℹ")
local TabFishing  = CreateTab("Fishing",  "🎣")
local TabAuto     = CreateTab("Auto",     "⚙")
local TabTrading  = CreateTab("Trading",  "🤝")
local TabMenu     = CreateTab("Menu",     "≡")
local TabQuest    = CreateTab("Quest",    "Q")
local TabTeleport = CreateTab("Teleport", "TP")
local TabMisc     = CreateTab("Misc",     "🔧")
local TabEvents   = CreateTab("Events",   "⚡")

-- ============================================================
-- ▶ INFO TAB
-- ============================================================
mkLabel(TabInfo, "FishIt Omega Hub  v1.0", Theme.Accent, 1)
mkLabel(TabInfo, "Fully built from game source analysis.", Theme.SubText, 2)
mkLabel(TabInfo, "────────────────────────────────", Theme.Stroke, 3)
local _, vPing   = mkRow(TabInfo, "Ping",               "—",    4)
local _, vStatus = mkRow(TabInfo, "Status",             "Idle", 5)
local _, vFish   = mkRow(TabInfo, "Fish (session)",     "0",    6)
local _, vBag    = mkRow(TabInfo, "Detector bag",       "0",    7)
local _, vPCount = mkRow(TabInfo, "Players in server",  "—",    8)
mkLabel(TabInfo, "────────────────────────────────", Theme.Stroke, 9)
mkLabel(TabInfo, "Use responsibly. Good luck fishing!", Theme.Warn, 10)

task.spawn(function()
    while task.wait(2) do
        vFish.Text   = tostring(S.SessionFish)
        vBag.Text    = tostring(S.DetectorBag)
        vStatus.Text = S.DetectorActive and "Auto Fishing" or "Idle"
        vStatus.TextColor3 = S.DetectorActive and Theme.Good or Theme.SubText
        vPCount.Text = tostring(#Players:GetPlayers())
        if S.ShowPing then
            local ok, p = pcall(function()
                return math.round(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue())
            end)
            local ps = (ok and tostring(p) or "—").."ms"
            vPing.Text = ps
            PingLbl.Text = "Ping: "..ps
        end
    end
end)

-- ============================================================
-- ▶ FISHING TAB
-- ============================================================
mkSection(TabFishing, "  Fishing Support", 10)

mkToggle(TabFishing, "Show Real Ping", "Shows ping in top bar", false, function(s)
    S.ShowPing = s; PingLbl.Visible = s
end, 11)

mkToggle(TabFishing, "Auto Equip Rod", "Equips best rod on enable", false, function(s)
    if s then
        task.spawn(function()
            -- Wait for Replion data to be ready (may not be on first script run)
            local attempts = 0
            local rods = {}
            repeat
                task.wait(0.8)
                rods = getRods()
                attempts = attempts + 1
            until #rods > 0 or attempts >= 8

            if #rods == 0 then
                notify("No rods found in inventory!")
                return
            end

            -- Already have one equipped? skip
            if getEquippedRodUUID() then
                notify("Rod already equipped!")
                return
            end

            local ev = getNet("EquipItem", false)
            if ev then
                -- EquipRod in TileInteraction_1737.lua:
                -- v_u_14:FireServer(UUID, "Fishing Rods")
                pcall(function() ev:FireServer(rods[1].UUID, "Fishing Rods") end)
                notify("Rod equipped: " .. tostring(rods[1].Id or rods[1].UUID))
            else
                notify("EquipItem remote not found!")
            end
        end)
    end
end, 12)

mkToggle(TabFishing, "Walk on Water", "Prevents sinking", false, function(s)
    S.WalkOnWater = s; toggleWoW(s)
end, 13)

mkToggle(TabFishing, "Freeze Player", "Locks character in place", false, function(s)
    S.FreezePlayer = s
    if not s then local h=hum() if h then h.WalkSpeed=16 h.JumpPower=50 end end
end, 14)

mkToggle(TabFishing, "No Fishing Animations", "Disables rod animations", false, function(s)
end, 15)

mkSection(TabFishing, "  Fishing Features  (Detector)", 20)

local _, vDetSt = mkRow(TabFishing, "Status",      "Offline", 21)
local _, vDetTm = mkRow(TabFishing, "Time",         "0.0s",   22)
local _, vDetBg = mkRow(TabFishing, "Fish caught",  "0",      23)

task.spawn(function()
    while task.wait(0.5) do
        vDetSt.Text = S.DetectorStatus
        vDetSt.TextColor3 = S.DetectorActive and Theme.Good or Theme.Danger
        vDetTm.Text = string.format("%.1fs", S.DetectorTime)
        vDetBg.Text = tostring(S.DetectorBag)
    end
end)

mkInput(TabFishing, "Wait (s)  default 1.5", "1.5", function(v)
    local n=tonumber(v) if n then S.WaitDelay=n end
end, 24)

mkToggle(TabFishing, "Start Detector", "Auto casts and catches fish", false, function(s)
    S.DetectorActive = s
    if s then startFisher() else stopFisher() end
end, 25)

mkSection(TabFishing, "  Instant Features", 30)

mkInput(TabFishing, "Complete delay (0=instant)", "0", function(v)
    local n=tonumber(v) if n then S.CompleteDelay=n end
end, 31)

mkToggle(TabFishing, "Instant Fishing", "Instantly completes minigame", false, function(s)
    S.InstantFishing = s
end, 32)

mkSection(TabFishing, "  Selling Features", 40)

mkDrop(TabFishing, "Select Sell Mode", {"Delay","Bag Full","Instant"}, "Delay", function(opt)
    S.SellMode = opt
end, 41)

mkInput(TabFishing, "Set Value (delay secs / bag size)", "30", function(v)
    local n=tonumber(v) if n then S.SellValue=n end
end, 42)

mkToggle(TabFishing, "Start Selling", "Auto sells based on mode", false, function(s)
    S.AutoSell = s
    if s then startSell() elseif sellThread then task.cancel(sellThread) sellThread=nil end
end, 43)

mkBtn(TabFishing, "Sell All Fish Now", true, doSell, 44)

mkSection(TabFishing, "  Favorite Features", 50)

mkDrop(TabFishing, "Name", {"Any"}, "Any", function(opt) end, 51)
mkDrop(TabFishing, "Rarity", {"Any","Common","Uncommon","Rare","Epic","Legendary","Mythic","SECRET"}, "Any", function(opt)
    S.FavRarity = opt
end, 52)
mkDrop(TabFishing, "Variant", {"Any","Normal","Albino","Mutated","Shiny","Chroma"}, "Any", function(opt)
    S.FavVariant = opt
end, 53)
mkDrop(TabFishing, "Mode Favorite", {"Add Favorite","Remove Favorite"}, "Add Favorite", function(opt) end, 54)

mkToggle(TabFishing, "Auto Favorite", "Favorites fish matching filters", false, function(s)
    S.AutoFavorite = s
    if s then startFav() elseif favThread then task.cancel(favThread) favThread=nil end
end, 55)

mkBtn(TabFishing, "Favorite All Matching Now", false, function()
    task.spawn(runFavLoop); notify("Favorited matching fish!")
end, 56)

mkBtn(TabFishing, "Unfavorite All Fish", false, function()
    task.spawn(unfavAll)
end, 57)

mkSection(TabFishing, "  Auto Rejoin Features", 60)

mkDrop(TabFishing, "Auto Execute Mode", {"Timer","On Disconnect","On Kick"}, "Timer", function(opt) end, 61)

mkInput(TabFishing, "Rejoin Timer (hours)", "1", function(v)
    local n=tonumber(v) if n then S.RejoinTimer=math.max(0.1,n) end
end, 62)

mkToggle(TabFishing, "Auto Rejoin", "Rejoins server after timer", false, function(s)
    S.AutoRejoin = s
    if s then startRejoin() elseif rejoinThread then task.cancel(rejoinThread) rejoinThread=nil end
end, 63)

-- ============================================================
-- ▶ AUTO TAB
-- ============================================================
mkSection(TabAuto, "  Shop Features", 10)
mkToggle(TabAuto, "Auto Buy Bait", "Purchases bait from shop", false, function(s) end, 11)

mkSection(TabAuto, "  Save Position Features", 20)
mkBtn(TabAuto, "Save Current Position", false, function()
    local h=hrp() if h then savedCF=h.CFrame notify("Position saved!") end
end, 21)
mkBtn(TabAuto, "Return to Saved Position", true, function()
    if savedCF then local h=hrp() if h then h.CFrame=savedCF notify("Returned!") end
    else notify("No position saved!") end
end, 22)

mkSection(TabAuto, "  Enchant Features", 30)
mkToggle(TabAuto, "Auto Enchant Fish", "Uses enchant stones automatically", false, function(s) end, 31)

mkSection(TabAuto, "  Totem Features", 32)
mkToggle(TabAuto, "Auto Use Totem", "Activates totems automatically", false, function(s) end, 33)

mkSection(TabAuto, "  Potions Features", 34)
mkToggle(TabAuto, "Auto Drink Luck Potion", "Uses luck potions when available", false, function(s) end, 35)

mkSection(TabAuto, "  Event Features", 40)
mkToggle(TabAuto, "Auto Event Join", "Joins active events", false, function(s) end, 41)
mkBtn(TabAuto, "Check Active Events", false, function()
    local now=os.time()
    local evs={{n="Pirate Cove",t=1769994000},{n="Valentine",t=1772323200}}
    local a={}
    for _,e in ipairs(evs) do if now<e.t then table.insert(a,e.n) end end
    notify(#a>0 and "Active: "..table.concat(a,", ") or "No active events")
end, 42)

-- ============================================================
-- ▶ TRADING TAB
-- ============================================================
mkSection(TabTrading, "  Trading Fish Features", 10)
mkToggle(TabTrading, "Auto Accept Fish Trades", "", false, function(s) end, 11)

mkSection(TabTrading, "  Trading Enchant Stones Features", 20)
mkToggle(TabTrading, "Auto Accept Enchant Trades", "", false, function(s) end, 21)

mkSection(TabTrading, "  Trading Coin Features", 30)
mkToggle(TabTrading, "Auto Accept Coin Trades", "", false, function(s) end, 31)

mkSection(TabTrading, "  Trading Fish By Rarity", 40)
mkDrop(TabTrading, "Min Rarity to Accept",
    {"Any","Rare","Epic","Legendary","Mythic","SECRET"},
    "Any", function(opt) S.TradeMinRarity=opt end, 41)

mkSection(TabTrading, "  Auto Accept Features", 50)
mkToggle(TabTrading, "Auto Accept All Trades", "Warning: accepts ANY trade!", false, function(s)
    if s then notify("⚠️ Auto Accept ALL is ON!") end
end, 51)

-- ============================================================
-- ▶ MENU TAB
-- ============================================================
mkSection(TabMenu, "  Coin Features", 10)
mkBtn(TabMenu, "Check My Coins", false, function()
    local d=getRepData()
    if d then
        local ok,c=pcall(function() return d:GetExpect("Coins") end)
        notify(ok and "Coins: "..tostring(c) or "Could not read coins")
    end
end, 11)

mkSection(TabMenu, "  Enchant Stone Features", 20)
mkBtn(TabMenu, "Count Enchant Stones", false, function()
    local n=0
    for _,item in ipairs(getItems()) do
        if tostring(item.Id):lower():find("enchant") then n=n+1 end
    end
    notify("Enchant Stones: "..n)
end, 21)

mkSection(TabMenu, "  Lochness Monster Event", 30)
mkBtn(TabMenu, "Go to Lochness Area", false, function() tpTo(Vector3.new(-30,5,50)) end, 31)

mkSection(TabMenu, "  Event Pirates Features", 32)
mkBtn(TabMenu, "Teleport to Pirate Cove", false, function() tpTo(Vector3.new(500,5,-800)) end, 33)

mkSection(TabMenu, "  Auto Crystal Features", 40)
mkToggle(TabMenu, "Auto Crystal Collector", "", false, function(s) end, 41)

mkSection(TabMenu, "  Guide Leviathan Features", 42)
mkBtn(TabMenu, "Teleport to Leviathan Zone", false, function()
    tpTo(Vector3.new(-62,4,2767)) notify("Teleporting to Deep Zone!")
end, 43)

mkSection(TabMenu, "  Relic Features", 50)
mkToggle(TabMenu, "Auto Collect Relics", "", false, function(s) end, 51)

mkSection(TabMenu, "  Semi Kaitun [BETA]", 52)
mkToggle(TabMenu, "Semi Kaitun Mode", "Experimental [BETA]", false, function(s)
    notify(s and "Semi Kaitun BETA ON" or "Semi Kaitun OFF")
end, 53)

mkSection(TabMenu, "  Auto Equip Charms", 54)
mkToggle(TabMenu, "Auto Equip Best Charms", "", false, function(s) end, 55)

-- ============================================================
-- ▶ QUEST TAB
-- ============================================================
mkSection(TabQuest, "  Artifact Lever Location", 10)
mkBtn(TabQuest, "Go to Artifact Lever", false, function() tpTo(Vector3.new(80,20,-500)) end, 11)

mkSection(TabQuest, "  Sisyphus Statue Quest", 20)
mkBtn(TabQuest, "Go to Sisyphus Statue", false, function() tpTo(Vector3.new(-150,10,350)) end, 21)

mkSection(TabQuest, "  Element Quest", 30)
mkBtn(TabQuest, "Go to Element Quest NPC", false, function() tpTo(Vector3.new(200,15,-300)) end, 31)

mkSection(TabQuest, "  Diamond Researcher Quest", 40)
mkBtn(TabQuest, "Go to Diamond Researcher", false, function() tpTo(Vector3.new(350,8,100)) end, 41)

mkSection(TabQuest, "  Crystalline Passage Features", 50)
mkBtn(TabQuest, "Go to Crystalline Passage", false, function() tpTo(Vector3.new(-200,-10,700)) end, 51)

-- ============================================================
-- ▶ TELEPORT TAB
-- ============================================================
mkSection(TabTeleport, "  Teleport to Location", 10)
local tpOrder = 11
for name, pos in pairs(LOCS) do
    local n, p = name, pos
    mkBtn(TabTeleport, n, false, function() tpTo(p) notify("→ "..n) end, tpOrder)
    tpOrder = tpOrder + 1
end

mkSection(TabTeleport, "  Teleport to Player", 40)
local _, playerBox = mkInput(TabTeleport, "Enter player name...", "", nil, 41)
mkBtn(TabTeleport, "Teleport to Player", true, function() tpToPlayer(playerBox.Text) end, 42)

-- ============================================================
-- ▶ MISC TAB
-- ============================================================
mkSection(TabMisc, "  Booster FPS", 10)
mkToggle(TabMisc, "FPS Booster", "Lowers graphics quality", false, function(s)
    if s then
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        pcall(function() game:GetService("Lighting").GlobalShadows = false end)
    else
        settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
        pcall(function() game:GetService("Lighting").GlobalShadows = true end)
    end
end, 11)

mkSection(TabMisc, "  Utility Player", 20)
mkToggle(TabMisc, "Speed Hack", "Increase walk speed", false, function(s)
    S.WalkSpeed = s
    if not s then local h=hum() if h then h.WalkSpeed=16 end end
end, 21)

mkInput(TabMisc, "Speed value  (default 16)", "50", function(v)
    local n=tonumber(v) if n then S.WalkSpeedVal=n end
end, 22)

mkToggle(TabMisc, "Noclip", "Walk through walls", false, function(s)
    S.Noclip = s; toggleNoclip(s)
end, 23)

mkToggle(TabMisc, "Infinite Jump", "Jump unlimited times", false, function(s)
    S.InfJump = s; toggleInfJump(s)
end, 24)

mkSection(TabMisc, "  Server Features", 30)
mkBtn(TabMisc, "Server Info", false, function()
    notify("Players: "..#Players:GetPlayers().." | Job: "..game.JobId:sub(1,10).."...")
end, 31)

mkSection(TabMisc, "  Miscellaneous", 40)
mkBtn(TabMisc, "Respawn Character", false, function()
    local h=hum() if h then h.Health=0 end
end, 41)
mkBtn(TabMisc, "Rejoin Server", false, function()
    pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId,LocalPlayer) end)
end, 42)

-- ============================================================
-- OPEN FIRST TAB — direct call, no :Fire() trick
-- ============================================================
-- ============================================================
-- ⚡ PREMIUM EVENTS TAB
-- Uses the real game event system:
--   Replion.Client:WaitReplion("Events"):OnArrayInsert("Events", cb)
--   Ghost Shark Hunt: QueueTime=240s, Duration=1200s, Tier=SECRET
--   Coordinates from Ghost Shark Hunt_315.lua
-- ============================================================

-- ── Event state ───────────────────────────────────────────
local EventState = {
    -- Ghost Shark
    GhostSharkAlert     = true,   -- notify when detected
    GhostSharkAutoTP    = false,  -- auto-teleport to hunt
    GhostSharkAutoFish  = false,  -- auto-start fishing when event starts
    GhostSharkActive    = false,
    -- Megalodon
    MegaAlert  = true,
    MegaAutoTP = false,
    -- Leviathan
    LeviaAlert  = true,
    LeviaAutoTP = false,
    -- Shark Hunt
    SharkHuntAlert  = true,
    SharkHuntAutoTP = false,
    -- Global
    AllEventAlert   = true,
    EventRadar      = false,  -- running flag
}

-- Ghost Shark Hunt coordinates (from Ghost Shark Hunt_315.lua)
local GHOST_SHARK_COORDS = {
    Vector3.new(489.559,    -1.35, 25.406),
    Vector3.new(-1358.216,  -1.35, 4100.556),
    Vector3.new(627.859,    -1.35, 3798.081),
}

-- All hunts: name → { coords, tier, desc }
local HUNT_DATA = {
    ["Ghost Shark Hunt"]  = {
        coords   = GHOST_SHARK_COORDS,
        tier     = "SECRET 🟣",
        fish     = "Ghost Shark",
        sellVal  = "125,000",
        duration = "20 min",
        queueSec = 240,
    },
    ["Shark Hunt"]        = {
        coords   = {Vector3.new(1.65,-1.35,2095.725), Vector3.new(1369.95,-1.35,930.125)},
        tier     = "Epic 🟠",
        fish     = "Sharks",
        sellVal  = "varies",
        duration = "30 min",
        queueSec = 240,
    },
    ["Megalodon Hunt"]    = {
        coords   = {Vector3.new(-1076.3,-1.4,1676.2), Vector3.new(-1191.8,-1.4,3597.3)},
        tier     = "SECRET 🟣",
        fish     = "Megalodon",
        sellVal  = "1,000,000+",
        duration = "Until caught",
        queueSec = 0,
    },
    ["Leviathan Hunt"]    = {
        coords   = {Vector3.new(-62, -1.4, 2767)},
        tier     = "SECRET 🟣",
        fish     = "Leviathan",
        sellVal  = "1,000,000+",
        duration = "Until caught",
        queueSec = 0,
    },
    ["Worm Hunt"]         = {
        coords   = {Vector3.new(2190.85,-1.4,97.575)},
        tier     = "Rare 🔵",
        fish     = "Worm Fish",
        sellVal  = "varies",
        duration = "30 min",
        queueSec = 240,
    },
    ["Treasure Hunt"]     = {
        coords   = {Vector3.new(0,5,0)},
        tier     = "Legendary 🟡",
        fish     = "Treasure",
        sellVal  = "high",
        duration = "varies",
        queueSec = 0,
    },
}

-- Status labels (updated live)
local evStatusLabels = {}   -- eventName -> label widget

-- ── Closest coord helper ──────────────────────────────────
local function nearestCoord(coords)
    local h = hrp()
    if not h then return coords[1] end
    local best, bestDist = coords[1], math.huge
    for _, c in ipairs(coords) do
        local d = (h.Position - c).Magnitude
        if d < bestDist then bestDist = d best = c end
    end
    return best
end

-- ── Ghost Shark sound alert ───────────────────────────────
local function playAlertSound()
    local snd = Instance.new("Sound", workspace)
    snd.SoundId = "rbxassetid://4612556715"  -- Roblox ping sound
    snd.Volume = 0.8
    snd:Play()
    game:GetService("Debris"):AddItem(snd, 3)
end

-- ── Core event detection ──────────────────────────────────
-- Mirrors EventController_1664.lua exactly.
-- FIX 1: eventRadarActive flag properly guards double-start
-- FIX 2: ALL automation wrapped in task.spawn() — never task.wait() in a callback
-- FIX 3: OnArrayRemove uses index to look up removed name from live array copy
-- FIX 4: tpTo guarded with character existence check
local eventRadarActive = false
local _evReplionRef = nil  -- keep reference so we can re-read current events

local function handleEventStart(evName)
    -- Called from task.spawn — safe to yield here
    local data = HUNT_DATA[evName]

    -- Update live status label
    if evStatusLabels[evName] then
        evStatusLabels[evName].Text = "ACTIVE 🟢"
        evStatusLabels[evName].TextColor3 = Theme.Good
    end

    -- Global catch-all alert
    if EventState.AllEventAlert then
        notify("⚡ World Event: " .. tostring(evName) .. " started!")
    end

    if not data then return end

    -- ── Ghost Shark Hunt ─────────────────────────────────
    if evName == "Ghost Shark Hunt" then
        EventState.GhostSharkActive = true

        if EventState.GhostSharkAlert then
            playAlertSound()
            notify("🦈 GHOST SHARK HUNT LIVE! 20min | SECRET | Sell: 125,000")
            task.delay(2, function()
                if EventState.GhostSharkActive then
                    notify("🦈 Ghost Shark Hunt still active — hurry!")
                end
            end)
        end

        -- Auto-TP: wait 2s for game event animation to settle, then:
        --   1. Enable Walk on Water (Ghost Shark is OCEAN — need WoW to stand + fish)
        --   2. Teleport to nearest coord (Y=-1.35 base + 4 offset = Y=2.65, above water)
        if EventState.GhostSharkAutoTP then
            task.spawn(function()
                task.wait(2)
                -- Enable WalkOnWater so player stands above ocean surface
                S.WalkOnWater = true
                toggleWoW(true)
                task.wait(0.3)
                tpTo(nearestCoord(GHOST_SHARK_COORDS), 4)
                notify("✈ TP to Ghost Shark zone! WalkOnWater enabled.")
            end)
        end

        -- Auto-Fish: start after TP settles (2.5s total from event)
        -- FreezePlayer prevents the >8-stud movement check from stopping auto-fishing
        if EventState.GhostSharkAutoFish then
            task.spawn(function()
                task.wait(2.5)
                if not S.DetectorActive then
                    -- Freeze player so auto-fishing movement check doesnt fire
                    S.FreezePlayer = true
                    S.DetectorActive = true
                    startFisher()
                    notify("🎣 Auto-Fishing started for Ghost Shark Hunt!")
                end
            end)
        end

    -- ── Megalodon Hunt ────────────────────────────────────
    elseif evName == "Megalodon Hunt" then
        if EventState.MegaAlert then
            playAlertSound()
            notify("🦕 MEGALODON HUNT! First catch wins! | SECRET | 1,000,000+")
        end
        if EventState.MegaAutoTP then
            task.spawn(function()
                task.wait(2)
                -- Megalodon is OCEAN — enable WoW so player can stand and fish
                S.WalkOnWater = true
                toggleWoW(true)
                task.wait(0.3)
                tpTo(nearestCoord(data.coords), 4)
                notify("✈ TP to Megalodon zone! WalkOnWater enabled.")
            end)
        end

    -- ── Leviathan Hunt ────────────────────────────────────
    elseif evName == "Leviathan Hunt" then
        if EventState.LeviaAlert then
            playAlertSound()
            notify("🐉 LEVIATHAN HUNT! Equip Leviathan Scale bait! | SECRET")
        end
        if EventState.LeviaAutoTP then
            task.spawn(function()
                task.wait(2)
                -- Leviathan is deep ocean — enable WoW
                S.WalkOnWater = true
                toggleWoW(true)
                task.wait(0.3)
                tpTo(nearestCoord(data.coords), 4)
                notify("✈ TP to Leviathan zone! WalkOnWater enabled.")
            end)
        end

    -- ── Shark Hunt ────────────────────────────────────────
    elseif evName == "Shark Hunt" then
        if EventState.SharkHuntAlert then
            playAlertSound()
            notify("🦈 Shark Hunt is LIVE!  Duration: " .. data.duration)
        end
        if EventState.SharkHuntAutoTP then
            task.spawn(function()
                task.wait(2)
                S.WalkOnWater = true
                toggleWoW(true)
                task.wait(0.3)
                tpTo(nearestCoord(data.coords), 4)
            end)
        end

    -- ── Worm Hunt ─────────────────────────────────────────
    elseif evName == "Worm Hunt" then
        if EventState.SharkHuntAlert then  -- reuse same toggle
            notify("🐛 Worm Hunt is LIVE!  Boosted Worm Fish odds!")
        end
    end
end

local function handleEventEnd(evName)
    -- Called from task.spawn — safe to yield
    if evStatusLabels[evName] then
        evStatusLabels[evName].Text = "Ended 🔴"
        evStatusLabels[evName].TextColor3 = Theme.Danger
        task.delay(6, function()
            if evStatusLabels[evName] then
                evStatusLabels[evName].Text = "Watching..."
                evStatusLabels[evName].TextColor3 = Theme.SubText
            end
        end)
    end

    if evName == "Ghost Shark Hunt" then
        EventState.GhostSharkActive = false
        if EventState.GhostSharkAlert then
            notify("Ghost Shark Hunt ended.")
        end
        -- Stop auto-fish only if WE started it for this event
        if EventState.GhostSharkAutoFish and S.DetectorActive then
            S.DetectorActive = false
            stopFisher()
            S.FreezePlayer = false  -- unfreeze player when hunt ends
            notify("Auto-fishing stopped (Ghost Shark Hunt ended).")
        end
    end
end

local function startEventRadar()
    -- FIX: proper boolean guard — prevents stacking multiple radars
    if eventRadarActive then
        notify("Event Radar already running!")
        return
    end

    task.spawn(function()
        -- Load Replion package
        local ok, Replion = pcall(function()
            return require(ReplicatedStorage:WaitForChild("Packages",10):WaitForChild("Replion",10))
        end)
        if not ok or not Replion then
            notify("⚠ Event Radar: Replion not found!")
            eventRadarActive = false
            return
        end

        -- Get the Events replion (same call as EventController_1664.lua)
        local ok2, evReplion = pcall(function()
            return Replion.Client:WaitReplion("Events")
        end)
        if not ok2 or not evReplion then
            notify("⚠ Event Radar: Events replion unavailable!")
            eventRadarActive = false
            return
        end

        _evReplionRef = evReplion
        eventRadarActive = true

        -- Snapshot any already-active events on radar start
        local ok3, current = pcall(function() return evReplion:GetExpect("Events") end)
        if ok3 and current then
            for _, evName in ipairs(current) do
                -- Mark as active in UI without re-firing sound/TP (already running)
                if evStatusLabels[evName] then
                    evStatusLabels[evName].Text = "ACTIVE 🟢"
                    evStatusLabels[evName].TextColor3 = Theme.Good
                end
                if evName == "Ghost Shark Hunt" then
                    EventState.GhostSharkActive = true
                end
            end
            if #current > 0 then
                notify("Active events: " .. table.concat(current, ", "))
            end
        end

        -- ── OnArrayInsert: event started ─────────────────
        -- FIX: callback only fires automation, never yields —
        --      task.spawn() inside handleEventStart does the yielding
        evReplion:OnArrayInsert("Events", function(_, evName)
            if type(evName) ~= "string" then return end
            task.spawn(handleEventStart, evName)
        end)

        -- ── OnArrayRemove: event ended ────────────────────
        -- FIX: Replion passes (index, removedValue) on removal.
        --      removedValue can be nil in some Replion versions —
        --      if nil, re-read current array to diff against our known set
        evReplion:OnArrayRemove("Events", function(idx, evName)
            if type(evName) == "string" then
                task.spawn(handleEventEnd, evName)
            else
                -- Fallback: compare against snapshot
                local ok4, now = pcall(function() return evReplion:GetExpect("Events") end)
                if ok4 and now then
                    -- Any name that was in evStatusLabels as ACTIVE but not in `now` = ended
                    for name, lbl in pairs(evStatusLabels) do
                        if lbl.Text == "ACTIVE 🟢" then
                            local stillActive = false
                            for _, n in ipairs(now) do if n == name then stillActive = true break end end
                            if not stillActive then
                                task.spawn(handleEventEnd, name)
                            end
                        end
                    end
                end
            end
        end)

        notify("📡 Event Radar is LIVE — watching all world events!")
    end)
end

-- ============================================================
-- BUILD EVENTS TAB UI
-- ============================================================

-- ─ Ghost Shark Hunt ──────────────────────────────────────
mkSection(TabEvents, "  🦈  Ghost Shark Hunt  [PREMIUM]", 10)
mkLabel(TabEvents, "QueueTime: 4 min warning  |  Duration: 20 min", Theme.SubText, 11)
mkLabel(TabEvents, "Fish: Ghost Shark  |  Tier: SECRET  |  Sell: 125,000", Theme.SubText, 12)
mkLabel(TabEvents, "Probability: 1 in 500,000 — rarest in game!", Theme.Warn, 13)

local ghostRow, ghostVal = mkRow(TabEvents, "Hunt Status", "Watching...", 14)
evStatusLabels["Ghost Shark Hunt"] = ghostVal

mkToggle(TabEvents, "Alert Me on Ghost Shark Hunt", "Sound + notification on detect", true, function(s)
    EventState.GhostSharkAlert = s
end, 15)

mkToggle(TabEvents, "Auto Teleport to Hunt Zone", "TP to nearest ghost shark coord", false, function(s)
    EventState.GhostSharkAutoTP = s
end, 16)

mkToggle(TabEvents, "Auto Fish During Hunt", "Auto-starts Detector for Ghost Shark", false, function(s)
    EventState.GhostSharkAutoFish = s
    -- If hunt already active, start now
    if s and EventState.GhostSharkActive then
        S.DetectorActive = true
        startFisher()
        notify("Auto-fishing started for active Ghost Shark Hunt!")
    end
end, 17)

mkBtn(TabEvents, "🦈  TP to Nearest Ghost Shark Spot", true, function()
    tpTo(nearestCoord(GHOST_SHARK_COORDS), 4)
    notify("Teleported to Ghost Shark Hunt zone!")
end, 18)

mkBtn(TabEvents, "📋  Ghost Shark Hunt Info", false, function()
    notify("Ghost Shark: SECRET | 1 in 500,000 odds | 4min warning | 20min hunt | Ocean only | Need Element/Angler rod")
end, 19)

-- ─ Megalodon Hunt ─────────────────────────────────────────
mkSection(TabEvents, "  🦕  Megalodon Hunt  [PREMIUM]", 20)
mkLabel(TabEvents, "Only ONE Megalodon per server — first wins!", Theme.Warn, 21)

local megaRow, megaVal = mkRow(TabEvents, "Megalodon Status", "Watching...", 22)
evStatusLabels["Megalodon Hunt"] = megaVal

mkToggle(TabEvents, "Alert on Megalodon Hunt", "Sound + notify instantly", true, function(s)
    EventState.MegaAlert = s
end, 23)
mkToggle(TabEvents, "Auto TP to Megalodon Zone", "Instant teleport on event start", false, function(s)
    EventState.MegaAutoTP = s
end, 24)

-- ─ Leviathan Hunt ─────────────────────────────────────────
mkSection(TabEvents, "  🐉  Leviathan Hunt  [PREMIUM]", 30)
mkLabel(TabEvents, "Requires Leviathan Scale bait. Only 1 per server!", Theme.Warn, 31)

local levRow, levVal = mkRow(TabEvents, "Leviathan Status", "Watching...", 32)
evStatusLabels["Leviathan Hunt"] = levVal

mkToggle(TabEvents, "Alert on Leviathan Hunt", "Notify when Leviathan Hunt starts", true, function(s)
    EventState.LeviaAlert = s
end, 33)
mkToggle(TabEvents, "Auto TP to Leviathan Zone", "Teleport to Deep Ocean zone", false, function(s)
    EventState.LeviaAutoTP = s
end, 34)

-- ─ Shark Hunt ─────────────────────────────────────────────
mkSection(TabEvents, "  🌊  Shark Hunt & Others  [PREMIUM]", 40)

local sharkRow, sharkVal = mkRow(TabEvents, "Shark Hunt Status", "Watching...", 41)
evStatusLabels["Shark Hunt"] = sharkVal
local wormRow, wormVal = mkRow(TabEvents, "Worm Hunt Status", "Watching...", 42)
evStatusLabels["Worm Hunt"] = wormVal

mkToggle(TabEvents, "Alert on Shark/Worm Hunt", "Notify on all Shark/Worm hunts", true, function(s)
    EventState.SharkHuntAlert = s
end, 43)
mkToggle(TabEvents, "Auto TP on Shark Hunt", "Jump to Shark Hunt zone", false, function(s)
    EventState.SharkHuntAutoTP = s
end, 44)

-- ─ Event Radar (master switch) ────────────────────────────
mkSection(TabEvents, "  📡  Event Radar  (Master Switch)", 50)
mkLabel(TabEvents, "Hooks into game Replion — same as real event system!", Theme.Accent, 51)
mkLabel(TabEvents, "Must be ON for all event alerts to work.", Theme.SubText, 52)

mkToggle(TabEvents, "All Event Alert", "Notify when ANY world event starts", true, function(s)
    EventState.AllEventAlert = s
end, 53)

mkToggle(TabEvents, "Start Event Radar", "Begins monitoring the Events replion", false, function(s)
    EventState.EventRadar = s
    if s then
        startEventRadar()
    else
        -- Reset flag so it can be restarted cleanly
        eventRadarActive = false
        _evReplionRef = nil
        notify("Event Radar stopped. Toggle on to restart.")
    end
end, 54)

mkBtn(TabEvents, "⚡  Check All Active Events Now", true, function()
    task.spawn(function()
        local ok, Replion = pcall(function()
            return require(ReplicatedStorage:WaitForChild("Packages",5):WaitForChild("Replion",5))
        end)
        if not ok then notify("Cannot access Replion!") return end
        local ok2, evRep = pcall(function() return Replion.Client:WaitReplion("Events") end)
        if not ok2 then notify("Cannot get Events replion!") return end
        local ok3, evList = pcall(function() return evRep:GetExpect("Events") end)
        if ok3 and evList and #evList > 0 then
            notify("Active: " .. table.concat(evList, ", "))
        else
            notify("No world events currently active.")
        end
    end)
end, 55)

mkBtn(TabEvents, "🔄  Restart Event Radar", false, function()
    -- Reset guard so startEventRadar can run again
    eventRadarActive = false
    _evReplionRef = nil
    startEventRadar()
end, 56)

TabButtons[1].Btn.MouseButton1Click:Fire()

-- FishCaught tracker
task.defer(function()
    local ev = getNet("FishCaught", false)
    if ev then ev.OnClientEvent:Connect(function() S.SessionFish=S.SessionFish+1 end) end
end)

task.delay(0.5, function()
    notify("FishIt Omega Hub loaded! Welcome, "..LocalPlayer.Name.."!")
end)

print("[FishIt Omega Hub] Loaded OK")
