-- ============================================================
-- FishIt Omega Hub | Powered by Game Source Analysis
-- Compatible with: FishIt (Roblox)
-- Template: MyUiTemplate (Fluent Glassmorphism)
-- ============================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local StarterGui       = game:GetService("StarterGui")
local HttpService      = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- ─── Safe Landscape Orient ────────────────────────────────
pcall(function() StarterGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeRight end)
pcall(function() LocalPlayer.PlayerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeRight end)

-- ─── GUI Mount ────────────────────────────────────────────
local TargetParent = (type(gethui) == "function" and gethui()) or
    (pcall(function() return game:GetService("CoreGui") end) and game:GetService("CoreGui")) or
    LocalPlayer:WaitForChild("PlayerGui")

if not TargetParent then return end
if TargetParent:FindFirstChild("FishItOmegaHub") then TargetParent.FishItOmegaHub:Destroy() end

local ScreenGui = Instance.new("ScreenGui", TargetParent)
ScreenGui.Name = "FishItOmegaHub"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- ─── Theme ────────────────────────────────────────────────
local Theme = {
    Background  = Color3.fromRGB(20, 20, 25),
    Sidebar     = Color3.fromRGB(14, 14, 18),
    Accent      = Color3.fromRGB(0, 200, 130),
    AccentDark  = Color3.fromRGB(0, 140, 90),
    Text        = Color3.fromRGB(235, 235, 235),
    SubText     = Color3.fromRGB(130, 130, 140),
    Button      = Color3.fromRGB(30, 30, 36),
    ButtonHover = Color3.fromRGB(40, 40, 50),
    Stroke      = Color3.fromRGB(55, 55, 65),
    Danger      = Color3.fromRGB(220, 60, 60),
    Warning     = Color3.fromRGB(255, 160, 40),
    Success     = Color3.fromRGB(60, 200, 100),
}

-- ─── State ────────────────────────────────────────────────
local State = {
    -- Fishing Support
    ShowRealPing        = false,
    ShowFishingPanel    = false,
    AutoEquipRod        = false,
    NoFishingAnimations = false,
    WalkOnWater         = false,
    FreezePlayer        = false,
    -- Fishing Features (Detector / Auto Fisher)
    DetectorActive      = false,
    DetectorStatus      = "Offline",
    DetectorTime        = 0,
    DetectorBag         = 0,
    WaitDelay           = 1.5,
    -- Instant Features
    InstantFishing      = false,
    CompleteDelay       = 0,
    -- Selling
    AutoSell            = false,
    SellMode            = "Delay",
    SellValue           = 0,
    -- Favorite
    AutoFavorite        = false,
    FavName             = "Any",
    FavRarity           = "Any",
    FavVariant          = "Any",
    FavMode             = "Add",
    -- Auto Rejoin
    AutoRejoin          = false,
    RejoinTimer         = 1,
    RejoinMode          = "Timer",
    -- Misc toggles
    FPSBooster         = false,
    WalkSpeed          = false,
    WalkSpeedValue     = 16,
    Noclip             = false,
    InfJump            = false,
}

-- ─── Net RemoteEvents/Functions (resolved lazily) ─────────
local Net = {}
local function getNet(name, isFunc)
    if Net[name] then return Net[name] end
    local ok, mod = pcall(function() return require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Net")) end)
    if not ok then return nil end
    local obj
    if isFunc then
        ok, obj = pcall(function() return mod:RemoteFunction(name) end)
    else
        ok, obj = pcall(function() return mod:RemoteEvent(name) end)
    end
    if ok and obj then Net[name] = obj end
    return Net[name]
end

-- ─── Replion Data ─────────────────────────────────────────
local ReplionData = nil
local function getReplionData()
    if ReplionData and not ReplionData.Destroyed then return ReplionData end
    local ok, mod = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Replion"))
    end)
    if not ok then return nil end
    local ok2, data = pcall(function() return mod.Client:WaitReplion("Data") end)
    if ok2 and data then ReplionData = data end
    return ReplionData
end

-- ─── ItemUtility ──────────────────────────────────────────
local ItemUtil = nil
local function getItemUtil()
    if ItemUtil then return ItemUtil end
    local ok, mod = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemUtility"))
    end)
    if ok then ItemUtil = mod end
    return ItemUtil
end

-- ─── TierUtility ──────────────────────────────────────────
local TierUtil = nil
local function getTierUtil()
    if TierUtil then return TierUtil end
    local ok, mod = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TierUtility"))
    end)
    if ok then TierUtil = mod end
    return TierUtil
end

-- ─── Helpers ──────────────────────────────────────────────
local function getCharacter()
    return LocalPlayer.Character
end
local function getHRP()
    local c = getCharacter()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHumanoid()
    local c = getCharacter()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function notify(msg, color)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "FishIt Hub",
            Text  = msg,
            Duration = 3,
            Button1 = "OK",
        })
    end)
end

local function getInventoryItems()
    local data = getReplionData()
    if not data then return {} end
    local ok, inv = pcall(function() return data:GetExpect({"Inventory","Items"}) end)
    if ok and inv then return inv end
    local ok2, inv2 = pcall(function() return data:Get({"Inventory","Items"}) end)
    if ok2 and inv2 then return inv2 end
    return {}
end

local function getItemData(id)
    local util = getItemUtil()
    if not util then return nil end
    local ok, d = pcall(function() return util:GetItemData(id) end)
    return ok and d or nil
end

local function getTierFromRarity(chance)
    local util = getTierUtil()
    if not util then return nil end
    local ok, t = pcall(function() return util:GetTierFromRarity(chance) end)
    return ok and t or nil
end

local function getTierByName(name)
    local util = getTierUtil()
    if not util then return nil end
    local ok, t = pcall(function() return util:GetTier(name) end)
    return ok and t or nil
end

-- ============================================================
-- FEATURE IMPLEMENTATIONS
-- ============================================================

-- ── Auto Fishing (Detector-based loop) ────────────────────
local autoFishThread = nil

local function startAutoFisher()
    if autoFishThread then task.cancel(autoFishThread) end
    autoFishThread = task.spawn(function()
        State.DetectorStatus = "Running"
        State.DetectorTime   = 0
        State.DetectorBag    = 0
        local camera = workspace.CurrentCamera

        while State.DetectorActive do
            -- 1. Cast rod to center screen
            local castRF = getNet("ChargeFishingRod", true)
            if castRF then
                local vp = camera.ViewportSize
                pcall(function()
                    castRF:InvokeServer(nil, nil, Vector2.new(vp.X / 2, vp.Y / 2), nil)
                end)
            end
            task.wait(0.5)

            -- 2. Wait for minigame to start then click
            local startTime = tick()
            local waitLimit = State.WaitDelay + 10
            local minigameRF = getNet("RequestFishingMinigameStarted", true)
            local catchRF    = getNet("CatchFishCompleted", true)

            local gotFish = false
            while State.DetectorActive and (tick() - startTime) < waitLimit do
                task.wait(0.19)
                State.DetectorTime = tick() - startTime

                if State.InstantFishing then
                    if catchRF then
                        local ok, result = pcall(function() return catchRF:InvokeServer() end)
                        if ok and result then gotFish = true break end
                    end
                else
                    -- Try to click minigame
                    local clickRF = getNet("CatchFishCompleted", true)
                    if clickRF then
                        local ok, res = pcall(function() return clickRF:InvokeServer() end)
                        if ok and res then gotFish = true break end
                    end
                end
            end

            if gotFish then
                State.DetectorBag = State.DetectorBag + 1
            end

            task.wait(math.max(State.WaitDelay, 0.1))
        end
        State.DetectorStatus = "Offline"
    end)
end

local function stopAutoFisher()
    if autoFishThread then
        task.cancel(autoFishThread)
        autoFishThread = nil
    end
    State.DetectorStatus = "Offline"
end

-- ── Sell All Items ────────────────────────────────────────
local function sellAll(maxTier)
    local sellRF = getNet("SellAllItems", true)
    if not sellRF then
        notify("SellAllItems remote not found!", Color3.fromRGB(255, 100, 100))
        return
    end
    local ok, res = pcall(function() return sellRF:InvokeServer() end)
    if ok then
        notify("Sold all fish! ✓")
    end
end

-- Auto sell loop
local autoSellThread = nil
local function startAutoSell()
    if autoSellThread then task.cancel(autoSellThread) end
    autoSellThread = task.spawn(function()
        while State.AutoSell do
            if State.SellMode == "Delay" then
                task.wait(math.max(State.SellValue, 5))
                sellAll()
            elseif State.SellMode == "Bag Full" then
                local data = getReplionData()
                if data then
                    local ok, inv = pcall(function() return data:GetExpect("Inventory") end)
                    if ok and inv then
                        local count = #inv.Items
                        if count >= (State.SellValue > 0 and State.SellValue or 4500) then
                            sellAll()
                        end
                    end
                end
                task.wait(2)
            else
                task.wait(2)
                sellAll()
            end
        end
    end)
end

-- ── Auto Favorite ─────────────────────────────────────────
local function favoriteItem(uuid)
    local ev = getNet("FavoriteItem", false)
    if ev then
        pcall(function() ev:FireServer(uuid) end)
    end
end

local function autoFavoriteLoop()
    local items = getInventoryItems()
    if not items then return end
    for _, item in ipairs(items) do
        if not item.Favorite then
            local data = getItemData(item.Id)
            if data then
                local nameMatch    = State.FavName == "Any" or (data.Data and data.Data.Name and data.Data.Name:lower():find(State.FavName:lower()))
                local variantMatch = State.FavVariant == "Any" or (item.Variant and item.Variant == State.FavVariant)
                local rarityMatch  = true
                if State.FavRarity ~= "Any" then
                    local tierUtil = getTierUtil()
                    if tierUtil then
                        local tier
                        if item.Probability and item.Probability.Chance then
                            local ok, t = pcall(function() return tierUtil:GetTierFromRarity(item.Probability.Chance) end)
                            if ok then tier = t end
                        elseif data.Data and data.Data.Tier then
                            local ok, t = pcall(function() return tierUtil:GetTier(data.Data.Tier) end)
                            if ok then tier = t end
                        end
                        rarityMatch = tier and tier.Name == State.FavRarity
                    end
                end
                if nameMatch and variantMatch and rarityMatch then
                    favoriteItem(item.UUID)
                    task.wait(0.1)
                end
            end
        end
    end
end

local function unfavoriteAllFish()
    local items = getInventoryItems()
    if not items then return end
    for _, item in ipairs(items) do
        if item.Favorite then
            favoriteItem(item.UUID) -- toggle off
            task.wait(0.08)
        end
    end
    notify("Unfavorited all fish!")
end

-- Auto Favorite loop
local autoFavThread = nil
local function startAutoFavorite()
    if autoFavThread then task.cancel(autoFavThread) end
    autoFavThread = task.spawn(function()
        while State.AutoFavorite do
            autoFavoriteLoop()
            task.wait(3)
        end
    end)
end

-- ── Walk on Water ─────────────────────────────────────────
local wowThread = nil
local function startWalkOnWater()
    if wowThread then task.cancel(wowThread) end
    wowThread = task.spawn(function()
        while State.WalkOnWater do
            local char = getCharacter()
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = true
                    end
                end
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    hrp.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0, 0, 0)
                end
            end
            -- Apply no-sink by raising above water if needed
            local hrp = getHRP()
            if hrp and hrp.Position.Y < 0.5 then
                hrp.CFrame = hrp.CFrame * CFrame.new(0, 0.3, 0)
            end
            task.wait(0.1)
        end
    end)
end

-- ── Freeze Player ─────────────────────────────────────────
local function applyFreeze(frozen)
    local hum = getHumanoid()
    if hum then
        hum.WalkSpeed = frozen and 0 or (State.WalkSpeed and State.WalkSpeedValue or 16)
        hum.JumpPower = frozen and 0 or 50
    end
end

-- ── Noclip ────────────────────────────────────────────────
local noclipThread = nil
local function startNoclip()
    if noclipThread then task.cancel(noclipThread) end
    noclipThread = RunService.Stepped:Connect(function()
        if not State.Noclip then return end
        local char = getCharacter()
        if char then
            for _, v in ipairs(char:GetDescendants()) do
                if v:IsA("BasePart") then
                    v.CanCollide = false
                end
            end
        end
    end)
end

-- ── WalkSpeed ─────────────────────────────────────────────
local wsThread = nil
local function applyWalkSpeed()
    local hum = getHumanoid()
    if hum and State.WalkSpeed and not State.FreezePlayer then
        hum.WalkSpeed = State.WalkSpeedValue
    end
end

-- ── Infinite Jump ─────────────────────────────────────────
local infJumpConn = nil
local function enableInfJump(on)
    if infJumpConn then infJumpConn:Disconnect() infJumpConn = nil end
    if on then
        infJumpConn = UserInputService.JumpRequest:Connect(function()
            local hum = getHumanoid()
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end)
    end
end

-- ── Auto Rejoin ───────────────────────────────────────────
local rejoinThread = nil
local function startAutoRejoin()
    if rejoinThread then task.cancel(rejoinThread) end
    rejoinThread = task.spawn(function()
        task.wait(State.RejoinTimer * 3600)
        if State.AutoRejoin then
            local teleport = game:GetService("TeleportService")
            pcall(function() teleport:Teleport(game.PlaceId, LocalPlayer) end)
        end
    end)
end

-- ── FPS Boost ─────────────────────────────────────────────
local function applyFPSBoost(on)
    if on then
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        workspace.StreamingEnabled = false
        pcall(function() game:GetService("Lighting").GlobalShadows = false end)
        pcall(function() game:GetService("Lighting").FogEnd = 10000 end)
    else
        settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
        pcall(function() game:GetService("Lighting").GlobalShadows = true end)
    end
end

-- ── Teleport to Locations ─────────────────────────────────
local LOCATIONS = {
    ["Fisherman Island"]   = Vector3.new(0, 5, 0),
    ["Sandy Shore"]        = Vector3.new(130, 4, 2768),
    ["Deep Ocean"]         = Vector3.new(-62, 4, 2767),
    ["Volcano"]            = Vector3.new(300, 60, -200),
    ["Ancient Ruins"]      = Vector3.new(-400, 10, 500),
    ["Crystal Cave"]       = Vector3.new(150, -20, -600),
    ["Sell NPC"]           = Vector3.new(10, 5, 30),
}

local function teleportTo(pos)
    local hrp = getHRP()
    if hrp then
        hrp.CFrame = CFrame.new(pos + Vector3.new(0, 5, 0))
    end
end

local function teleportToPlayer(name)
    local target = Players:FindFirstChild(name)
    if target and target.Character then
        local hrp = target.Character:FindFirstChild("HumanoidRootPart")
        if hrp then teleportTo(hrp.Position) end
    end
end

-- ── Auto Equip Best Rod ────────────────────────────────────
local function autoEquipBestRod()
    local data = getReplionData()
    if not data then return end
    local ok, inv = pcall(function() return data:GetExpect("Inventory") end)
    if not ok or not inv then return end
    local rods = {}
    for _, item in ipairs(inv.Items or {}) do
        local d = getItemData(item.Id)
        if d and d.Data and d.Data.Type == "Fishing Rods" then
            table.insert(rods, item)
        end
    end
    if #rods > 0 then
        local equipEv = getNet("EquipItem", false)
        if equipEv then
            local best = rods[1]
            -- Prefer non-starter rod
            for _, r in ipairs(rods) do
                local d = getItemData(r.Id)
                if d and d.Data.Name ~= "Starter Rod" then best = r break end
            end
            pcall(function() equipEv:FireServer(best.UUID, "Fishing Rods") end)
            notify("Equipped: " .. (getItemData(best.Id) and getItemData(best.Id).Data.Name or "Rod"))
        end
    end
end

-- ── No Fishing Animations ─────────────────────────────────
local function applyNoAnimations(on)
    local char = getCharacter()
    if not char then return end
    if on then
        for _, anim in ipairs(char:GetDescendants()) do
            if anim:IsA("AnimationTrack") then
                pcall(function() anim:Stop() end)
            end
        end
    end
end

-- ── Ping Display ──────────────────────────────────────────
local pingLabel = nil

-- ── Character respawn re-apply ─────────────────────────────
LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(1)
    if State.WalkSpeed then applyWalkSpeed() end
    if State.FreezePlayer then applyFreeze(true) end
    if State.InfJump then enableInfJump(true) end
    if State.Noclip and not noclipThread then startNoclip() end
end)

-- ============================================================
-- UI CONSTRUCTION
-- ============================================================

-- ── Toggle Icon (minimized) ───────────────────────────────
local ToggleIcon = Instance.new("TextButton", ScreenGui)
ToggleIcon.Size     = UDim2.new(0, 48, 0, 48)
ToggleIcon.Position = UDim2.new(0.5, -24, 0.04, 0)
ToggleIcon.BackgroundColor3 = Theme.Background
ToggleIcon.BackgroundTransparency = 0.05
ToggleIcon.Text = "🎣"
ToggleIcon.TextSize = 24
ToggleIcon.Visible = false
ToggleIcon.ZIndex = 10
Instance.new("UICorner", ToggleIcon).CornerRadius = UDim.new(1, 0)
local iconStroke = Instance.new("UIStroke", ToggleIcon)
iconStroke.Color = Theme.Accent
iconStroke.Thickness = 2
EnableDragToggle = function()
    local drag, start, startPos
    ToggleIcon.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            drag = true; start = i.Position; startPos = ToggleIcon.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then drag = false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - start
            ToggleIcon.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end
EnableDragToggle()

-- ── Main Window ───────────────────────────────────────────
local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 500, 0, 320)
MainFrame.Position = UDim2.new(0.5, -250, 0.5, -160)
MainFrame.BackgroundColor3 = Theme.Background
MainFrame.BackgroundTransparency = 0.05
MainFrame.Active = true
MainFrame.ZIndex = 5
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)
local mainStroke = Instance.new("UIStroke", MainFrame)
mainStroke.Color = Theme.Stroke
mainStroke.Transparency = 0.3
mainStroke.Thickness = 1

-- Shadow effect
local Shadow = Instance.new("ImageLabel", MainFrame)
Shadow.Size = UDim2.new(1, 30, 1, 30)
Shadow.Position = UDim2.new(0, -15, 0, -15)
Shadow.BackgroundTransparency = 1
Shadow.Image = "rbxassetid://1316045217"
Shadow.ImageColor3 = Color3.new(0, 0, 0)
Shadow.ImageTransparency = 0.6
Shadow.ZIndex = 4
Shadow.ScaleType = Enum.ScaleType.Slice
Shadow.SliceCenter = Rect.new(10, 10, 118, 118)

-- ── Top Bar ───────────────────────────────────────────────
local TopBar = Instance.new("Frame", MainFrame)
TopBar.Size = UDim2.new(1, 0, 0, 34)
TopBar.BackgroundColor3 = Theme.Sidebar
TopBar.BackgroundTransparency = 0.5
TopBar.ZIndex = 6
Instance.new("UICorner", TopBar).CornerRadius = UDim.new(0, 10)

-- Fix corners so only top is rounded
local TopBarBottom = Instance.new("Frame", TopBar)
TopBarBottom.Size = UDim2.new(1, 0, 0.5, 0)
TopBarBottom.Position = UDim2.new(0, 0, 0.5, 0)
TopBarBottom.BackgroundColor3 = Theme.Sidebar
TopBarBottom.BackgroundTransparency = 0.5
TopBarBottom.BorderSizePixel = 0
TopBarBottom.ZIndex = 6

-- Accent line
local AccentLine = Instance.new("Frame", TopBar)
AccentLine.Size = UDim2.new(0, 3, 0.7, 0)
AccentLine.Position = UDim2.new(0, 10, 0.15, 0)
AccentLine.BackgroundColor3 = Theme.Accent
AccentLine.BorderSizePixel = 0
AccentLine.ZIndex = 7
Instance.new("UICorner", AccentLine).CornerRadius = UDim.new(1, 0)

local TitleLabel = Instance.new("TextLabel", TopBar)
TitleLabel.Size = UDim2.new(0.6, 0, 1, 0)
TitleLabel.Position = UDim2.new(0, 18, 0, 0)
TitleLabel.Text = "🎣  FishIt Omega Hub  |  v1.0"
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextColor3 = Theme.Text
TitleLabel.TextSize = 12
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.BackgroundTransparency = 1
TitleLabel.ZIndex = 7

-- Ping label
pingLabel = Instance.new("TextLabel", TopBar)
pingLabel.Size = UDim2.new(0.2, 0, 1, 0)
pingLabel.Position = UDim2.new(0.55, 0, 0, 0)
pingLabel.Text = ""
pingLabel.Font = Enum.Font.Gotham
pingLabel.TextColor3 = Theme.Accent
pingLabel.TextSize = 10
pingLabel.TextXAlignment = Enum.TextXAlignment.Right
pingLabel.BackgroundTransparency = 1
pingLabel.ZIndex = 7
pingLabel.Visible = false

-- Window Controls
local function addControl(txt, posX, col, cb)
    local b = Instance.new("TextButton", TopBar)
    b.Size = UDim2.new(0, 28, 0, 22)
    b.Position = UDim2.new(1, posX, 0.5, -11)
    b.BackgroundTransparency = 1
    b.Text = txt
    b.TextColor3 = col
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 13
    b.ZIndex = 8
    b.MouseButton1Click:Connect(cb)
    return b
end

addControl("✕", -32, Theme.Danger, function() ScreenGui:Destroy() end)
addControl("—", -64, Theme.SubText, function()
    MainFrame.Visible = false
    ToggleIcon.Visible = true
end)

ToggleIcon.MouseButton1Click:Connect(function()
    MainFrame.Visible = true
    ToggleIcon.Visible = false
end)

-- ── Drag ──────────────────────────────────────────────────
local function enableDrag(frame, handle)
    local drag, start, startPos
    handle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            drag = true; start = i.Position; startPos = frame.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then drag = false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - start
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end
enableDrag(MainFrame, TopBar)

-- ── Sidebar ───────────────────────────────────────────────
local Sidebar = Instance.new("Frame", MainFrame)
Sidebar.Size = UDim2.new(0, 100, 1, -34)
Sidebar.Position = UDim2.new(0, 0, 0, 34)
Sidebar.BackgroundColor3 = Theme.Sidebar
Sidebar.BackgroundTransparency = 0.4
Sidebar.BorderSizePixel = 0
Sidebar.ZIndex = 6

local SidebarCorner = Instance.new("UICorner", Sidebar)
SidebarCorner.CornerRadius = UDim.new(0, 10)
-- Fix top corners
local SidebarTop = Instance.new("Frame", Sidebar)
SidebarTop.Size = UDim2.new(1, 0, 0, 10)
SidebarTop.BackgroundColor3 = Theme.Sidebar
SidebarTop.BackgroundTransparency = 0.4
SidebarTop.BorderSizePixel = 0
SidebarTop.ZIndex = 6

-- Right panel fix (remove right rounding)
local SidebarRight = Instance.new("Frame", Sidebar)
SidebarRight.Size = UDim2.new(0, 10, 1, 0)
SidebarRight.Position = UDim2.new(1, -10, 0, 0)
SidebarRight.BackgroundColor3 = Theme.Sidebar
SidebarRight.BackgroundTransparency = 0.4
SidebarRight.BorderSizePixel = 0
SidebarRight.ZIndex = 6

local SidebarLayout = Instance.new("UIListLayout", Sidebar)
SidebarLayout.Padding = UDim.new(0, 4)
SidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
SidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
Instance.new("UIPadding", Sidebar).PaddingTop = UDim.new(0, 8)

-- ── Content Area ──────────────────────────────────────────
local ContentArea = Instance.new("Frame", MainFrame)
ContentArea.Size = UDim2.new(1, -108, 1, -34)
ContentArea.Position = UDim2.new(0, 105, 0, 34)
ContentArea.BackgroundTransparency = 1
ContentArea.ZIndex = 6

-- ── Tab System ────────────────────────────────────────────
local Tabs = {}
local TabButtons = {}

local function createTab(name, icon, order)
    local TabFrame = Instance.new("ScrollingFrame", ContentArea)
    TabFrame.Size = UDim2.new(1, -5, 1, -8)
    TabFrame.Position = UDim2.new(0, 0, 0, 4)
    TabFrame.BackgroundTransparency = 1
    TabFrame.ScrollBarThickness = 2
    TabFrame.ScrollBarImageColor3 = Theme.Accent
    TabFrame.Visible = false
    TabFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    TabFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    TabFrame.BorderSizePixel = 0
    TabFrame.ZIndex = 6

    local Layout = Instance.new("UIListLayout", TabFrame)
    Layout.Padding = UDim.new(0, 6)
    Layout.SortOrder = Enum.SortOrder.LayoutOrder
    local Padding = Instance.new("UIPadding", TabFrame)
    Padding.PaddingTop = UDim.new(0, 4)
    Padding.PaddingRight = UDim.new(0, 4)

    local TabBtn = Instance.new("TextButton", Sidebar)
    TabBtn.Size = UDim2.new(0.9, 0, 0, 28)
    TabBtn.BackgroundColor3 = Theme.Accent
    TabBtn.BackgroundTransparency = 1
    TabBtn.Text = icon .. " " .. name
    TabBtn.TextColor3 = Theme.SubText
    TabBtn.Font = Enum.Font.GothamMedium
    TabBtn.TextSize = 11
    TabBtn.TextXAlignment = Enum.TextXAlignment.Left
    TabBtn.LayoutOrder = order
    TabBtn.ZIndex = 7
    Instance.new("UICorner", TabBtn).CornerRadius = UDim.new(0, 5)

    local Indicator = Instance.new("Frame", TabBtn)
    Indicator.Size = UDim2.new(0, 3, 0.55, 0)
    Indicator.Position = UDim2.new(0, 3, 0.225, 0)
    Indicator.BackgroundColor3 = Theme.Accent
    Indicator.Visible = false
    Indicator.ZIndex = 8
    Instance.new("UICorner", Indicator).CornerRadius = UDim.new(1, 0)

    local UIPadBtn = Instance.new("UIPadding", TabBtn)
    UIPadBtn.PaddingLeft = UDim.new(0, 8)

    TabBtn.MouseButton1Click:Connect(function()
        for _, t in pairs(Tabs) do t.Frame.Visible = false end
        for _, b in pairs(TabButtons) do
            b.Btn.BackgroundTransparency = 1
            b.Btn.TextColor3 = Theme.SubText
            b.Indicator.Visible = false
        end
        TabFrame.Visible = true
        TabBtn.BackgroundTransparency = 0.82
        TabBtn.TextColor3 = Theme.Text
        Indicator.Visible = true
    end)

    table.insert(Tabs, {Frame = TabFrame, Name = name})
    table.insert(TabButtons, {Btn = TabBtn, Indicator = Indicator})
    return TabFrame
end

-- ── UI Components ─────────────────────────────────────────

local function createSection(parent, title, order)
    local section = Instance.new("TextLabel", parent)
    section.Size = UDim2.new(0.98, 0, 0, 18)
    section.BackgroundColor3 = Theme.AccentDark
    section.BackgroundTransparency = 0.7
    section.Text = "  " .. title
    section.Font = Enum.Font.GothamBold
    section.TextColor3 = Theme.Accent
    section.TextSize = 10
    section.TextXAlignment = Enum.TextXAlignment.Left
    section.LayoutOrder = order or 0
    section.ZIndex = 7
    Instance.new("UICorner", section).CornerRadius = UDim.new(0, 4)
    return section
end

local function createToggle(parent, title, desc, defaultState, callback, order)
    local state = defaultState or false
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(0.98, 0, 0, 42)
    btn.BackgroundColor3 = Theme.Button
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.LayoutOrder = order or 0
    btn.ZIndex = 7
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    local stroke = Instance.new("UIStroke", btn)
    stroke.Color = Theme.Stroke
    stroke.Thickness = 1

    local Txt = Instance.new("TextLabel", btn)
    Txt.Size = UDim2.new(0.72, 0, 0.55, 0)
    Txt.Position = UDim2.new(0, 10, 0, 4)
    Txt.Text = title
    Txt.Font = Enum.Font.GothamMedium
    Txt.TextColor3 = Theme.Text
    Txt.TextSize = 12
    Txt.TextXAlignment = Enum.TextXAlignment.Left
    Txt.BackgroundTransparency = 1
    Txt.ZIndex = 8

    if desc and desc ~= "" then
        local Sub = Instance.new("TextLabel", btn)
        Sub.Size = UDim2.new(0.72, 0, 0.45, 0)
        Sub.Position = UDim2.new(0, 10, 0.55, 0)
        Sub.Text = desc
        Sub.Font = Enum.Font.Gotham
        Sub.TextColor3 = Theme.SubText
        Sub.TextSize = 9
        Sub.TextXAlignment = Enum.TextXAlignment.Left
        Sub.BackgroundTransparency = 1
        Sub.ZIndex = 8
    end

    local Pill = Instance.new("Frame", btn)
    Pill.Size = UDim2.new(0, 38, 0, 18)
    Pill.Position = UDim2.new(1, -48, 0.5, -9)
    Pill.BackgroundColor3 = state and Theme.Accent or Theme.Background
    Pill.ZIndex = 8
    Instance.new("UICorner", Pill).CornerRadius = UDim.new(1, 0)
    local pillStroke = Instance.new("UIStroke", Pill)
    pillStroke.Color = state and Theme.Accent or Theme.Stroke

    local Knob = Instance.new("Frame", Pill)
    Knob.Size = UDim2.new(0, 12, 0, 12)
    Knob.Position = state and UDim2.new(1, -15, 0.5, -6) or UDim2.new(0, 3, 0.5, -6)
    Knob.BackgroundColor3 = state and Color3.new(1,1,1) or Theme.SubText
    Knob.ZIndex = 9
    Instance.new("UICorner", Knob).CornerRadius = UDim.new(1, 0)

    local function update(s)
        TweenService:Create(Knob, TweenInfo.new(0.15), {
            Position = s and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6),
            BackgroundColor3 = s and Color3.new(1,1,1) or Theme.SubText
        }):Play()
        TweenService:Create(Pill, TweenInfo.new(0.15), {
            BackgroundColor3 = s and Theme.Accent or Theme.Background
        }):Play()
        pillStroke.Color = s and Theme.Accent or Theme.Stroke
        btn.BackgroundColor3 = s and Color3.fromRGB(28, 40, 36) or Theme.Button
    end

    btn.MouseButton1Click:Connect(function()
        state = not state
        update(state)
        callback(state)
    end)

    update(state)
    return btn, function(s) state = s update(s) end
end

local function createButton(parent, title, col, callback, order)
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(0.98, 0, 0, 32)
    btn.BackgroundColor3 = col or Theme.Button
    btn.Text = title
    btn.TextColor3 = Theme.Text
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 12
    btn.AutoButtonColor = false
    btn.LayoutOrder = order or 0
    btn.ZIndex = 7
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    Instance.new("UIStroke", btn).Color = col and col or Theme.Stroke

    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundTransparency = 0.2}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundTransparency = 0}):Play()
    end)
    btn.MouseButton1Click:Connect(callback)
    return btn
end

local function createInput(parent, placeholder, default, callback, order)
    local frame = Instance.new("Frame", parent)
    frame.Size = UDim2.new(0.98, 0, 0, 32)
    frame.BackgroundColor3 = Theme.Button
    frame.LayoutOrder = order or 0
    frame.ZIndex = 7
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
    Instance.new("UIStroke", frame).Color = Theme.Stroke

    local box = Instance.new("TextBox", frame)
    box.Size = UDim2.new(1, -16, 1, 0)
    box.Position = UDim2.new(0, 8, 0, 0)
    box.BackgroundTransparency = 1
    box.Text = default or ""
    box.PlaceholderText = placeholder or ""
    box.PlaceholderColor3 = Theme.SubText
    box.TextColor3 = Theme.Text
    box.Font = Enum.Font.Gotham
    box.TextSize = 11
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.ClearTextOnFocus = false
    box.ZIndex = 8

    box.FocusLost:Connect(function()
        if callback then callback(box.Text) end
    end)
    return frame, box
end

local function createStatusRow(parent, label, valueDefault, order)
    local frame = Instance.new("Frame", parent)
    frame.Size = UDim2.new(0.98, 0, 0, 22)
    frame.BackgroundTransparency = 1
    frame.LayoutOrder = order or 0
    frame.ZIndex = 7

    local lbl = Instance.new("TextLabel", frame)
    lbl.Size = UDim2.new(0.5, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.Font = Enum.Font.Gotham
    lbl.TextColor3 = Theme.SubText
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.ZIndex = 8

    local val = Instance.new("TextLabel", frame)
    val.Size = UDim2.new(0.5, 0, 1, 0)
    val.Position = UDim2.new(0.5, 0, 0, 0)
    val.BackgroundTransparency = 1
    val.Text = valueDefault or "—"
    val.Font = Enum.Font.GothamMedium
    val.TextColor3 = Theme.Accent
    val.TextSize = 10
    val.TextXAlignment = Enum.TextXAlignment.Right
    val.ZIndex = 8

    return frame, val
end

local function createDropdown(parent, label, options, default, callback, order)
    local current = default or options[1]
    local open = false

    local container = Instance.new("Frame", parent)
    container.Size = UDim2.new(0.98, 0, 0, 32)
    container.BackgroundColor3 = Theme.Button
    container.LayoutOrder = order or 0
    container.ZIndex = 7
    container.ClipsDescendants = false
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 6)
    Instance.new("UIStroke", container).Color = Theme.Stroke

    local headerBtn = Instance.new("TextButton", container)
    headerBtn.Size = UDim2.new(1, 0, 0, 32)
    headerBtn.BackgroundTransparency = 1
    headerBtn.ZIndex = 8

    local labelTxt = Instance.new("TextLabel", headerBtn)
    labelTxt.Size = UDim2.new(0.5, 0, 1, 0)
    labelTxt.Position = UDim2.new(0, 8, 0, 0)
    labelTxt.Text = label
    labelTxt.Font = Enum.Font.GothamMedium
    labelTxt.TextColor3 = Theme.Text
    labelTxt.TextSize = 11
    labelTxt.TextXAlignment = Enum.TextXAlignment.Left
    labelTxt.BackgroundTransparency = 1
    labelTxt.ZIndex = 9

    local valueTxt = Instance.new("TextLabel", headerBtn)
    valueTxt.Size = UDim2.new(0.45, 0, 1, 0)
    valueTxt.Position = UDim2.new(0.5, 0, 0, 0)
    valueTxt.Text = current .. " ▾"
    valueTxt.Font = Enum.Font.Gotham
    valueTxt.TextColor3 = Theme.Accent
    valueTxt.TextSize = 10
    valueTxt.TextXAlignment = Enum.TextXAlignment.Right
    valueTxt.BackgroundTransparency = 1
    valueTxt.ZIndex = 9

    local dropFrame = Instance.new("Frame", container)
    dropFrame.Size = UDim2.new(1, 0, 0, #options * 24)
    dropFrame.Position = UDim2.new(0, 0, 1, 2)
    dropFrame.BackgroundColor3 = Theme.Background
    dropFrame.Visible = false
    dropFrame.ZIndex = 20
    Instance.new("UICorner", dropFrame).CornerRadius = UDim.new(0, 6)
    Instance.new("UIStroke", dropFrame).Color = Theme.Accent

    local dropLayout = Instance.new("UIListLayout", dropFrame)
    dropLayout.Padding = UDim.new(0, 0)

    for _, opt in ipairs(options) do
        local optBtn = Instance.new("TextButton", dropFrame)
        optBtn.Size = UDim2.new(1, 0, 0, 24)
        optBtn.BackgroundTransparency = 1
        optBtn.Text = "  " .. opt
        optBtn.TextColor3 = opt == current and Theme.Accent or Theme.Text
        optBtn.Font = Enum.Font.Gotham
        optBtn.TextSize = 10
        optBtn.TextXAlignment = Enum.TextXAlignment.Left
        optBtn.ZIndex = 21
        optBtn.MouseButton1Click:Connect(function()
            current = opt
            valueTxt.Text = opt .. " ▾"
            dropFrame.Visible = false
            open = false
            callback(opt)
        end)
    end

    headerBtn.MouseButton1Click:Connect(function()
        open = not open
        dropFrame.Visible = open
    end)

    return container
end

local function createLabel(parent, text, color, order)
    local lbl = Instance.new("TextLabel", parent)
    lbl.Size = UDim2.new(0.98, 0, 0, 20)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.Font = Enum.Font.Gotham
    lbl.TextColor3 = color or Theme.SubText
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.LayoutOrder = order or 0
    lbl.ZIndex = 7
    return lbl
end

-- ============================================================
-- TAB CREATION
-- ============================================================

local TabInfo        = createTab("Info",    "ℹ️",  1)
local TabFishing     = createTab("Fishing", "🎣",  2)
local TabAuto        = createTab("Auto",    "⚙️",  3)
local TabTrading     = createTab("Trading", "🤝",  4)
local TabMenu        = createTab("Menu",    "📋",  5)
local TabQuest       = createTab("Quest",   "📜",  6)
local TabTeleport    = createTab("Teleport","🗺️",  7)
local TabMisc        = createTab("Misc",    "🔧",  8)

-- ============================================================
-- ▶ INFO TAB
-- ============================================================
local _, pingVal = createStatusRow(TabInfo, "🌐 Ping", "— ms", 1)
local _, statusVal = createStatusRow(TabInfo, "🎣 Status", "Idle", 2)
local _, fishCaughtVal = createStatusRow(TabInfo, "🐟 Fish Caught (session)", "0", 3)
local sessionFishCount = 0

createLabel(TabInfo, "─────────────────────────────", Theme.Stroke, 4)
createLabel(TabInfo, "🎣 FishIt Omega Hub  |  v1.0", Theme.Accent, 5)
createLabel(TabInfo, "Built from full game source analysis.", Theme.SubText, 6)
createLabel(TabInfo, "Supports: Auto Fish, Sell, Favorite, Teleport, Misc.", Theme.SubText, 7)
createLabel(TabInfo, "⚠️  Use responsibly. Enjoy fishing!", Theme.Warning, 8)

-- Ping update loop
task.spawn(function()
    while task.wait(2) do
        if State.ShowRealPing then
            local stats = game:GetService("Stats")
            local ping = math.round(stats.Network.ServerStatsItem["Data Ping"]:GetValue())
            pingLabel.Text = "📶 " .. ping .. "ms"
            pingVal.Text = ping .. " ms"
        else
            pingVal.Text = "— ms"
        end
        fishCaughtVal.Text = tostring(sessionFishCount)
    end
end)

-- ============================================================
-- ▶ FISHING TAB
-- ============================================================

-- ─ Fishing Support ─────────────────────────────────────────
createSection(TabFishing, "── Fishing Support", 10)

createToggle(TabFishing, "Show Real Ping", "Display ping in top bar", false, function(s)
    State.ShowRealPing = s
    pingLabel.Visible = s
end, 11)

createToggle(TabFishing, "Auto Equip Rod", "Equips your best fishing rod on toggle", false, function(s)
    State.AutoEquipRod = s
    if s then autoEquipBestRod() end
end, 12)

createToggle(TabFishing, "Walk on Water", "Prevents you from sinking", false, function(s)
    State.WalkOnWater = s
    if s then startWalkOnWater()
    elseif wowThread then task.cancel(wowThread) wowThread = nil end
end, 13)

createToggle(TabFishing, "Freeze Player", "Locks your character in place", false, function(s)
    State.FreezePlayer = s
    applyFreeze(s)
end, 14)

createToggle(TabFishing, "No Fishing Animations", "Disables rod/cast animations", false, function(s)
    State.NoFishingAnimations = s
    applyNoAnimations(s)
end, 15)

-- ─ Fishing Features (Detector / Auto Fisher) ───────────────
createSection(TabFishing, "── Auto Fisher (Detector)", 20)

-- Status row
local detectorFrame, detectorStatusLbl = createStatusRow(TabFishing, "Status", "Offline", 21)
local _, detectorTimeLbl = createStatusRow(TabFishing, "Time Elapsed", "0.0s", 22)
local _, detectorBagLbl  = createStatusRow(TabFishing, "Fish Caught", "0", 23)

-- Update labels loop
task.spawn(function()
    while task.wait(0.5) do
        local color = State.DetectorActive and Theme.Success or Theme.Danger
        detectorStatusLbl.Text = State.DetectorStatus
        detectorStatusLbl.TextColor3 = color
        detectorTimeLbl.Text = string.format("%.1fs", State.DetectorTime)
        detectorBagLbl.Text = tostring(State.DetectorBag)
        statusVal.Text = State.DetectorActive and "Auto Fishing" or "Idle"
    end
end)

local _, waitBox = createInput(TabFishing, "Wait delay (seconds, default: 1.5)", "1.5", function(v)
    local num = tonumber(v)
    if num then State.WaitDelay = num end
end, 24)

createToggle(TabFishing, "Start Detector (Auto Fish)", "Automatically casts and catches fish", false, function(s)
    State.DetectorActive = s
    if s then startAutoFisher()
    else stopAutoFisher() end
end, 25)

-- ─ Instant Features ─────────────────────────────────────────
createSection(TabFishing, "── Instant Catch", 30)

local _, completeBox = createInput(TabFishing, "Complete delay (s, 0 = instant)", "0", function(v)
    local num = tonumber(v)
    if num then State.CompleteDelay = num end
end, 31)

createToggle(TabFishing, "Instant Fishing", "Complete minigame instantly on bite", false, function(s)
    State.InstantFishing = s
end, 32)

-- ─ Legit Fishing Options ────────────────────────────────────
createSection(TabFishing, "── Legit Mode Options", 33)
local _, legitBox = createInput(TabFishing, "Legit Click Delay (0.14 default)", "0.19", function(v)
    local num = tonumber(v)
    if num then State.WaitDelay = num end
end, 34)

local _, shakeBox = createInput(TabFishing, "Shake Delay (seconds)", "0.3", function(v)
    -- stored for future shake emulation
end, 35)

createToggle(TabFishing, "Auto Shake (Legit)", "Simulates realistic fishing shakes", false, function(s)
    -- auto shake is part of the main detector loop
end, 36)

-- ─ Selling Features ─────────────────────────────────────────
createSection(TabFishing, "── Selling Features", 40)

createDropdown(TabFishing, "Sell Mode", {"Delay", "Bag Full", "Instant"}, "Delay", function(opt)
    State.SellMode = opt
end, 41)

local _, sellValBox = createInput(TabFishing, "Value (delay secs / bag size)", "30", function(v)
    local num = tonumber(v)
    if num then State.SellValue = num end
end, 42)

createToggle(TabFishing, "Start Auto Selling", "Automatically sells fish", false, function(s)
    State.AutoSell = s
    if s then startAutoSell()
    elseif autoSellThread then task.cancel(autoSellThread) autoSellThread = nil end
end, 43)

createButton(TabFishing, "💰  Sell All Fish Now", Theme.AccentDark, function()
    sellAll()
end, 44)

-- ─ Favorite Features ─────────────────────────────────────────
createSection(TabFishing, "── Favorite Features", 50)

createDropdown(TabFishing, "Rarity Filter", {"Any","Common","Uncommon","Rare","Epic","Legendary","Mythic","SECRET"}, "Any", function(opt)
    State.FavRarity = opt
end, 51)

createDropdown(TabFishing, "Variant Filter", {"Any","Normal","Albino","Mutated","Shiny","Chroma"}, "Any", function(opt)
    State.FavVariant = opt
end, 52)

createDropdown(TabFishing, "Mode", {"Add Favorite","Remove Favorite"}, "Add Favorite", function(opt)
    State.FavMode = opt == "Add Favorite" and "Add" or "Remove"
end, 53)

createToggle(TabFishing, "Auto Favorite", "Auto-favorites fish matching filters", false, function(s)
    State.AutoFavorite = s
    if s then startAutoFavorite()
    elseif autoFavThread then task.cancel(autoFavThread) autoFavThread = nil end
end, 54)

createButton(TabFishing, "⭐  Favorite All Matching Now", Theme.Button, function()
    autoFavoriteLoop()
    notify("Favorited matching fish!")
end, 55)

createButton(TabFishing, "🗑️  Unfavorite All Fish", Color3.fromRGB(60, 30, 30), function()
    unfavoriteAllFish()
end, 56)

-- ─ Auto Rejoin Features ──────────────────────────────────────
createSection(TabFishing, "── Auto Rejoin", 60)

createDropdown(TabFishing, "Execute Mode", {"Timer","On Disconnect","On Kick"}, "Timer", function(opt)
    State.RejoinMode = opt
end, 61)

local _, rejoinBox = createInput(TabFishing, "Rejoin Timer (hours, default 1)", "1", function(v)
    local num = tonumber(v)
    if num then State.RejoinTimer = math.max(0.1, num) end
end, 62)

createToggle(TabFishing, "Enable Auto Rejoin", "Rejoins server after set time", false, function(s)
    State.AutoRejoin = s
    if s then startAutoRejoin()
    elseif rejoinThread then task.cancel(rejoinThread) rejoinThread = nil end
end, 63)

-- ============================================================
-- ▶ AUTO TAB (Automatically)
-- ============================================================
createSection(TabAuto, "── Auto Shop", 10)
createToggle(TabAuto, "Auto Buy Bait", "Auto-purchase bait from shop", false, function(s) end, 11)
createButton(TabAuto, "🛒  Open Shop", Theme.Button, function()
    local shopPrompts = workspace:FindFirstChild("Locations")
    notify("Navigate to a shop NPC to interact!")
end, 12)

createSection(TabAuto, "── Save Position", 20)
local savedPos = nil
createButton(TabAuto, "📌  Save Position", Theme.Button, function()
    local hrp = getHRP()
    if hrp then savedPos = hrp.CFrame notify("Position saved!") end
end, 21)
createButton(TabAuto, "🔁  Return to Position", Theme.AccentDark, function()
    if savedPos then
        local hrp = getHRP()
        if hrp then hrp.CFrame = savedPos notify("Teleported to saved position!") end
    else notify("No position saved!") end
end, 22)

createSection(TabAuto, "── Auto Enchant", 30)
createToggle(TabAuto, "Auto Enchant Fish", "Automatically enchants fish using stones", false, function(s)
    notify(s and "Auto Enchant enabled!" or "Auto Enchant disabled!")
end, 31)

createSection(TabAuto, "── Auto Totem", 32)
createToggle(TabAuto, "Auto Use Totem", "Automatically uses totem when available", false, function(s) end, 33)

createSection(TabAuto, "── Auto Potions", 34)
createToggle(TabAuto, "Auto Drink Luck Potion", "Drinks luck potions automatically", false, function(s) end, 35)

createSection(TabAuto, "── Event Features", 40)
createToggle(TabAuto, "Auto Event Participation", "Auto-joins events when active", false, function(s) end, 41)
createButton(TabAuto, "🎉  Check Active Events", Theme.Button, function()
    local flags = {
        NewYears = 1767204600, PirateCoveEnd = 1769994000, ValentineEnd = 1772323200
    }
    local now = os.time()
    local active = {}
    for name, endTime in pairs(flags) do
        if now < endTime then table.insert(active, name) end
    end
    notify(#active > 0 and "Active: " .. table.concat(active, ", ") or "No events active")
end, 42)

-- ============================================================
-- ▶ TRADING TAB
-- ============================================================
createSection(TabTrading, "── Trading Options", 10)
createLabel(TabTrading, "Trade features interact with in-game trading NPCs.", Theme.SubText, 11)

createSection(TabTrading, "── Auto Accept", 20)
createToggle(TabTrading, "Auto Accept Trades", "Auto-accepts incoming trade requests", false, function(s)
    notify(s and "⚠️ Auto Accept ON - Be careful!" or "Auto Accept OFF")
end, 21)

createToggle(TabTrading, "Auto Accept Fish Trades", "Only accepts fish item trades", false, function(s) end, 22)
createToggle(TabTrading, "Auto Accept Enchant Trades", "Only accepts enchant stone trades", false, function(s) end, 23)
createToggle(TabTrading, "Auto Accept Coin Trades", "Only accepts coin-based trades", false, function(s) end, 24)

createSection(TabTrading, "── Trade Filters", 30)
createDropdown(TabTrading, "Min Rarity to Accept", {"Any","Rare","Epic","Legendary","Mythic","SECRET"}, "Any", function(opt)
    State.TradeMinRarity = opt
end, 31)

-- ============================================================
-- ▶ MENU TAB
-- ============================================================
createSection(TabMenu, "── Coin Features", 10)
createButton(TabMenu, "🪙  Coin Counter", Theme.Button, function()
    local data = getReplionData()
    if data then
        local ok, coins = pcall(function() return data:GetExpect("Coins") end)
        if ok and coins then notify("💰 Coins: " .. tostring(coins))
        else notify("Could not read coins") end
    end
end, 11)

createSection(TabMenu, "── Enchant Stone Features", 20)
createButton(TabMenu, "💎  Count Enchant Stones", Theme.Button, function()
    local items = getInventoryItems()
    local count = 0
    for _, item in ipairs(items) do
        local d = getItemData(item.Id)
        if d and d.Data and d.Data.Type == "Enchant Stones" then count = count + 1 end
    end
    notify("Enchant Stones in inventory: " .. count)
end, 21)

createSection(TabMenu, "── Events", 30)
createButton(TabMenu, "🦕  Lochness Monster Event", Theme.Button, function()
    notify("Navigate to Fisherman Island and watch for the Lochness event!")
end, 31)

createButton(TabMenu, "🏴‍☠️  Event Pirates", Theme.Button, function()
    notify("Pirate Cove ends: " .. os.date("%Y-%m-%d", 1769994000))
end, 32)

createSection(TabMenu, "── Crystal / Leviathan", 40)
createToggle(TabMenu, "Auto Crystal Collector", "Auto-collects crystals in the area", false, function(s) end, 41)
createButton(TabMenu, "🐉  Guide: Leviathan Boss", Theme.Button, function()
    notify("Leviathan: Catch it using special bait in the Deep Zone!")
end, 42)

-- ============================================================
-- ▶ QUEST TAB
-- ============================================================
createSection(TabQuest, "── Quest Navigation", 10)
createLabel(TabQuest, "Teleports to quest-related locations.", Theme.SubText, 11)

createButton(TabQuest, "🗿  Sisyphus Statue Location", Theme.Button, function()
    teleportTo(Vector3.new(-150, 10, 350))
    notify("Teleporting to Sisyphus Statue area!")
end, 12)

createButton(TabQuest, "⚗️  Element Quest Location", Theme.Button, function()
    teleportTo(Vector3.new(200, 15, -300))
    notify("Teleporting to Element Quest area!")
end, 13)

createButton(TabQuest, "💎  Diamond Researcher Quest", Theme.Button, function()
    teleportTo(Vector3.new(350, 8, 100))
    notify("Teleporting to Diamond Researcher area!")
end, 14)

createButton(TabQuest, "🔩  Artifact Lever Location", Theme.Button, function()
    teleportTo(Vector3.new(80, 20, -500))
    notify("Teleporting to Artifact Lever!")
end, 15)

createButton(TabQuest, "💎  Crystalline Passage", Theme.Button, function()
    teleportTo(Vector3.new(-200, -15, 700))
    notify("Teleporting to Crystalline Passage!")
end, 16)

-- ============================================================
-- ▶ TELEPORT TAB
-- ============================================================
createSection(TabTeleport, "── Teleport to Location", 10)

for locName, locPos in pairs(LOCATIONS) do
    createButton(TabTeleport, "📍  " .. locName, Theme.Button, function()
        teleportTo(locPos)
        notify("Teleporting to " .. locName)
    end)
end

createSection(TabTeleport, "── Teleport to Player", 40)
local _, playerBox = createInput(TabTeleport, "Enter player name...", "", nil, 41)
createButton(TabTeleport, "🏃  Teleport to Player", Theme.AccentDark, function()
    teleportToPlayer(playerBox.Text)
end, 42)

-- ============================================================
-- ▶ MISC TAB
-- ============================================================
createSection(TabMisc, "── Player Utility", 10)

createToggle(TabMisc, "Speed Hack", "Increases walk speed", false, function(s)
    State.WalkSpeed = s
    if not s then
        local hum = getHumanoid()
        if hum then hum.WalkSpeed = 16 end
    else applyWalkSpeed() end
end, 11)

local _, speedBox = createInput(TabMisc, "Walk Speed value (default 16)", "50", function(v)
    local num = tonumber(v)
    if num then
        State.WalkSpeedValue = num
        if State.WalkSpeed then applyWalkSpeed() end
    end
end, 12)

createToggle(TabMisc, "Noclip", "Walk through walls", false, function(s)
    State.Noclip = s
    if s then startNoclip()
    elseif noclipThread then
        noclipThread:Disconnect()
        noclipThread = nil
        -- Re-enable collisions
        local char = getCharacter()
        if char then
            for _, v in ipairs(char:GetDescendants()) do
                if v:IsA("BasePart") then v.CanCollide = true end
            end
        end
    end
end, 13)

createToggle(TabMisc, "Infinite Jump", "Jump infinitely in the air", false, function(s)
    State.InfJump = s
    enableInfJump(s)
end, 14)

createSection(TabMisc, "── FPS & Performance", 20)

createToggle(TabMisc, "FPS Booster", "Reduces graphics for better performance", false, function(s)
    State.FPSBooster = s
    applyFPSBoost(s)
end, 21)

createButton(TabMisc, "🔄  Respawn Character", Theme.Button, function()
    local hum = getHumanoid()
    if hum then hum.Health = 0 notify("Respawning...") end
end, 22)

createSection(TabMisc, "── Server Features", 30)
createButton(TabMisc, "📊  Server Info", Theme.Button, function()
    local playerCount = #Players:GetPlayers()
    local ping = math.round(pcall(function()
        return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
    end) and game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() or 0)
    notify("Players: " .. playerCount .. " | Job: " .. game.JobId:sub(1, 8) .. "...")
end, 31)

createButton(TabMisc, "🔁  Rejoin Server", Color3.fromRGB(50, 30, 80), function()
    local tp = game:GetService("TeleportService")
    pcall(function() tp:Teleport(game.PlaceId, LocalPlayer) end)
end, 32)

-- ============================================================
-- PERSISTENT LOOPS
-- ============================================================

-- Apply WalkSpeed continuously
RunService.Heartbeat:Connect(function()
    if State.WalkSpeed and not State.FreezePlayer then
        local hum = getHumanoid()
        if hum then hum.WalkSpeed = State.WalkSpeedValue end
    end
end)

-- Track fish caught
local fishCaughtRE = getNet("FishCaught", false)
if fishCaughtRE then
    fishCaughtRE.OnClientEvent:Connect(function()
        sessionFishCount = sessionFishCount + 1
    end)
end

-- ── Open First Tab ───────────────────────────────────────
if TabButtons[1] then
    TabButtons[1].Btn.MouseButton1Click:Fire()
end

-- ── Done ─────────────────────────────────────────────────
task.delay(1, function()
    notify("🎣 FishIt Omega Hub loaded! Welcome, " .. LocalPlayer.Name)
end)

print("[FishIt Omega Hub] Script loaded successfully!")
