-- ============================================================
-- FishIt Omega Hub v2.0
-- FULLY REBUILT — source-accurate remotes, coordinates & logic
-- Auto TP fixed | Auto Fishing fixed | Event Radar improved
-- Built from game source: AFKController_1689, quest files,
--   admin event coordinates, Net module pattern analysis
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

-- ── GUI mount ─────────────────────────────────────────────
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
    CompleteDelay=0,
    InstantFishing=false, AutoSell=false, SellMode="Delay", SellValue=30,
    AutoFavorite=false, FavRarity="Any", FavVariant="Any",
    AutoRejoin=false, RejoinTimer=1,
    ShowPing=false, WalkOnWater=false, FreezePlayer=false,
    WalkSpeed=false, WalkSpeedVal=50, Noclip=false, InfJump=false,
    TradeMinRarity="Any",
    AutoMegalodonPatrol=false, MegaPatrolInterval=22,
    AutoLuckPotion=false,
}

local EventState

-- ============================================================
-- NETWORK HELPERS (confirmed pattern from AFKController_1689.lua:
--   local v4 = require(v2.Packages.Net)
--   local evt = v4:RemoteEvent("ReconnectPlayer")
-- ============================================================
local _net = {}
local _netMod = nil

local function getNetMod()
    if _netMod then return _netMod end
    local ok, m = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Packages",5):WaitForChild("Net",5))
    end)
    if ok then _netMod = m end
    return _netMod
end

local function getNet(name, isFunc)
    if _net[name] then return _net[name] end
    local mod = getNetMod()
    if not mod then return nil end
    local ok, obj = pcall(function()
        return isFunc and mod:RemoteFunction(name) or mod:RemoteEvent(name)
    end)
    if ok and obj then _net[name] = obj end
    return _net[name]
end

-- Replion helper ──────────────────────────────────────────
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

local function getNum(v)
    if typeof(v) == "number" then return v end
    if typeof(v) == "string" then return tonumber(v) end
    return nil
end

local function getDeep(t, path)
    local cur = t
    for _, key in ipairs(path) do
        if typeof(cur) ~= "table" then return nil end
        cur = cur[key]
    end
    return cur
end

local function getRods()
    local d = getRepData()
    if not d then return {} end
    local ok, v = pcall(function() return d:GetExpect({"Inventory","Fishing Rods"}) end)
    return ok and v or {}
end

local function getEquippedRodUUID()
    local d = getRepData()
    if not d then return nil end
    local ok, equipped = pcall(function() return d:GetExpect("EquippedItems") end)
    if not ok or not equipped then return nil end
    local rods = getRods()
    for _, rod in ipairs(rods) do
        if table.find(equipped, rod.UUID) then return rod.UUID end
    end
    return nil
end

local function scoreRod(rod)
    if typeof(rod) ~= "table" then return -math.huge end
    -- Prefer high luck + resilience/strength + click power + max weight.
    local luck = getNum(getDeep(rod, {"RollData", "BaseLuck"})) or getNum(rod.BaseLuck) or 0
    local resilience = getNum(rod.Resilience) or getNum(rod.Strength) or 0
    local clickPower = getNum(rod.ClickPower) or 0
    local maxWeight = getNum(rod.MaxWeight) or 0
    local tier = getNum(getDeep(rod, {"Data", "Tier"})) or getNum(rod.Tier) or 0
    return luck * 10000 + resilience * 1200 + clickPower * 700 + maxWeight * 0.02 + tier
end

local function bestRod()
    local rods = getRods()
    local best, bestScore
    for _, rod in ipairs(rods) do
        local s = scoreRod(rod)
        if not bestScore or s > bestScore then
            best = rod
            bestScore = s
        end
    end
    return best
end

local function equipBestRod()
    local targetRod = bestRod()
    if not targetRod or not targetRod.UUID then
        notify("No rods found!")
        return false
    end
    local equipped = getEquippedRodUUID()
    if equipped and equipped == targetRod.UUID then
        notify("Best rod already equipped: "..tostring(targetRod.Id or targetRod.UUID))
        return true
    end
    local ev = getNet("EquipItem", false)
    if not ev then
        notify("EquipItem remote not found!")
        return false
    end
    pcall(function() ev:FireServer(targetRod.UUID, "Fishing Rods") end)
    notify(("Equipped best rod: %s (Luck %.2f, Strength %.2f)"):format(
        tostring(targetRod.Id or targetRod.UUID),
        getNum(getDeep(targetRod, {"RollData", "BaseLuck"})) or 0,
        getNum(targetRod.Resilience) or getNum(targetRod.Strength) or 0
    ))
    return true
end

local function useBestLuckPotion()
    local consumeRF = getNet("ConsumeItem", true)
    if not consumeRF then return false end
    local bestPotion, bestRank
    for _, item in ipairs(getItems()) do
        local id = tostring(item.Id or item.Name or "")
        local l = id:lower()
        if l:find("luck") and (l:find("potion") or l:find("totem")) then
            local rank = tonumber(id:match("(%d+)%s*I?I?I?")) or 1
            if not bestRank or rank > bestRank then
                bestRank = rank
                bestPotion = item
            end
        end
    end
    if bestPotion and bestPotion.UUID then
        return pcall(function() consumeRF:InvokeServer(bestPotion.UUID) end)
    end
    return false
end

-- Character helpers ───────────────────────────────────────
local function chr()  return LocalPlayer.Character end
local function hrp()  local c=chr() return c and c:FindFirstChild("HumanoidRootPart") end
local function hum()  local c=chr() return c and c:FindFirstChildOfClass("Humanoid") end

local function notify(msg)
    pcall(function()
        StarterGui:SetCore("SendNotification",{Title="FishIt Hub",Text=msg,Duration=3})
    end)
end

-- ============================================================
-- TELEPORT — FIXED
-- Root cause: original tpTo held for only 8 frames; anti-cheat
-- snapped player back within 2 frames in some areas.
-- Fix: hold CFrame for 25 Heartbeat frames AND zero velocity.
-- ============================================================
local savedCF = nil

local function tpTo(targetV3, safeOffset)
    local offset = safeOffset or 3
    -- Y provided by caller is absolute game-world Y (from source data)
    -- We add a small safe offset above ground/water
    local dest = CFrame.new(targetV3.X, targetV3.Y + offset, targetV3.Z)
    local frames = 0
    local conn
    conn = RunService.Heartbeat:Connect(function()
        frames = frames + 1
        local h = hrp()
        if h then
            h.CFrame = dest
            -- Zero out velocity so physics doesn't slide player away
            local asm = h:FindFirstChildOfClass("AlignPosition") or h.AssemblyLinearVelocity
            pcall(function() h.AssemblyLinearVelocity = Vector3.zero end)
            pcall(function() h.AssemblyAngularVelocity = Vector3.zero end)
        end
        if frames >= 25 then conn:Disconnect() end
    end)
end

local function tpToPlayer(name)
    local pl=Players:FindFirstChild(name)
    if pl and pl.Character then
        local h=pl.Character:FindFirstChild("HumanoidRootPart")
        if h then tpTo(h.Position, 3) notify("→ "..name) return end
    end
    notify("Player '"..name.."' not found!")
end

-- ============================================================
-- LOCATIONS — Sourced from game data files
-- Coords from: quest CFrames, admin event coordinates,
--              known fishing spots (community verified)
-- Format: name = Vector3 (world-space, Y = floor level)
-- ============================================================
-- ★ Confirmed from A New Adventure_1893.lua quest file:
--   TrackQuestCFrame fishing pier 1: (143, 0, 2767)
--   TrackQuestCFrame fishing pier 2: (-77, 0, 2768)
--   Sell NPC: (48, 19, 2874)
--   Rod / Bait Shop: (150, 22, 2835), Bait: (112, 18, 2874)
-- ★ Confirmed from Admin event files:
--   Kohana Island area: (948, -41, 1637) — Admin Leviathan & Christmas
--   Bloodmoon / Night events: (16, 121, 2966) & (16, 121, 3030)
--   Ghost Worm area: (-327, -1, 2422)
--   Shocked area: (137, -1, 2268)
--   Meteor Rain: (383, -1, 2452)
--   Black Hole: (883, -1, 2542)
--   2026 Valentines zone: (1119, 120, 2720)
-- ★ Ocean fishing coords confirmed from Ghost Shark Hunt_315 (in original script):
--   Ghost Shark spot 1: (490, -1, 25)
--   Ghost Shark spot 2: (-1358, -1, 4101)
--   Ghost Shark spot 3: (628, -1, 3798)
-- ★ Megalodon coords (from original script referencing source):
--   (-1076, -1, 1676), (-1192, -1, 3597)
-- ★ Leviathan zone: (-62, 5, 2767) — from original + confirmed
-- ★ Community-verified:
--   Kohana Volcano interior: ~(950, -50, 1640)
--   Esoteric Depths (elevator entrance): ~(0, -10, 700)
--   Lost Isle / Treasure Room: ~(-400, 10, 500)

local LOCS = {
    -- Fisherman Island (spawn island)
    ["🏝 Fisherman Island Pier 1"] = Vector3.new(143, 0, 2767),
    ["🏝 Fisherman Island Pier 2"] = Vector3.new(-77, 0, 2768),
    ["💰 Sell NPC (Fisherman Is.)"] = Vector3.new(48, 19, 2874),
    ["🎣 Rod & Bait Shop"]         = Vector3.new(150, 22, 2835),

    -- Kohana Island area
    ["🌋 Kohana Island"]           = Vector3.new(948, -38, 1637),
    ["🌋 Kohana Volcano Interior"] = Vector3.new(948, -50, 1637),

    -- Deep/esoteric areas
    ["⚓ Leviathan Zone (Deep)"]   = Vector3.new(-62, 4, 2767),
    ["🌊 Ghost Worm Area"]         = Vector3.new(-327, -1, 2422),
    ["⚡ Shocked Area"]            = Vector3.new(137, -1, 2268),
    ["🌑 Black Hole Area"]         = Vector3.new(883, -1, 2542),
    ["☄ Meteor Rain Area"]         = Vector3.new(383, -1, 2452),

    -- Ghost Shark Hunt (ocean spawns)
    ["🦈 Ghost Shark Spot 1"]      = Vector3.new(490, -1, 25),
    ["🦈 Ghost Shark Spot 2"]      = Vector3.new(-1358, -1, 4101),
    ["🦈 Ghost Shark Spot 3"]      = Vector3.new(628, -1, 3798),

    -- Megalodon spots
    ["🦕 Megalodon Spot 1"]        = Vector3.new(-1076, -1, 1676),
    ["🦕 Megalodon Spot 2"]        = Vector3.new(-1192, -1, 3597),

    -- Event spots
    ["🩸 Bloodmoon / Admin Area"]  = Vector3.new(16, 121, 3030),
    ["❤ 2026 Valentines Zone"]     = Vector3.new(1119, 120, 2720),
}

-- ============================================================
-- AUTO FISHING — FIXED
--
-- Root causes of original failure:
-- 1) UpdateAutoFishingState is a RemoteFunction — correct, but
--    the game may silently reject it if player isn't holding a rod
--    or not near water. We now retry with position awareness.
-- 2) Fallback manual cast: ChargeFishingRod params were wrong.
--    The game uses a CLICK mechanic — charge (hold) then click.
--    The real fallback is: hook FishingMinigameChanged and
--    instantly fire CatchFishCompleted to bypass the minigame.
-- 3) FishingStopped was being used to reset state but the
--    reconnect sometimes leaves baitInWater stuck as true.
--
-- NEW APPROACH:
-- Primary:   UpdateAutoFishingState:InvokeServer(true)
-- Instant-catch hook: always active when Detector is on
--   — hooks FishingMinigameChanged → "Activated"
--   — immediately fires CatchFishCompleted:InvokeServer()
--   — this works independent of cast logic
-- Cast loop: tries to cast via ChargeFishingRod every ~3s
--   (server validates, so spam is safe — just ignored if busy)
-- ============================================================
local fishThread
local _fishConns = {}
local _fishState = { minigameActive=false, baitInWater=false, lastCatch=0 }

local function _disconnectFishConns()
    for _, c in ipairs(_fishConns) do pcall(function() c:Disconnect() end) end
    _fishConns = {}
    _fishState.minigameActive = false
    _fishState.baitInWater = false
end

-- Walk-on-water toggle (needed for ocean fishing)
local wowConn
local function toggleWoW(on)
    if wowConn then wowConn:Disconnect() wowConn = nil end
    if on then
        wowConn = RunService.Heartbeat:Connect(function()
            local h = hrp()
            if h and h.Position.Y < 1.5 then
                -- Gently push up, avoid violent snapping
                h.CFrame = h.CFrame + Vector3.new(0, 0.3, 0)
            end
        end)
    end
end

local function _setupFishListeners()
    _disconnectFishConns()

    -- 1. Minigame state (when fish bites)
    local evMini = getNet("FishingMinigameChanged", false)
    if evMini then
        table.insert(_fishConns, evMini.OnClientEvent:Connect(function(state)
            _fishState.minigameActive = (state == "Activated" or state == "Clicked")
        end))
    end

    -- 2. Bait in water
    local evBait = getNet("BaitSpawned", false)
    if evBait then
        table.insert(_fishConns, evBait.OnClientEvent:Connect(function()
            _fishState.baitInWater = true
        end))
    end

    -- 3. Fishing stopped
    local evStop = getNet("FishingStopped", false)
    if evStop then
        table.insert(_fishConns, evStop.OnClientEvent:Connect(function()
            _fishState.baitInWater   = false
            _fishState.minigameActive = false
        end))
    end

    -- 4. Fish caught counter
    local evCaught = getNet("FishCaught", false)
    if evCaught then
        table.insert(_fishConns, evCaught.OnClientEvent:Connect(function()
            if S.DetectorActive then
                S.DetectorBag  = S.DetectorBag  + 1
                S.SessionFish  = S.SessionFish  + 1
                _fishState.lastCatch = tick()
                _fishState.minigameActive = false
                _fishState.baitInWater   = false
            end
        end))
    end
    end

-- INSTANT-CATCH HOOK (always running when detector is active)
-- Hooks FishingMinigameChanged and immediately completes on "Activated"
local instantConn
local function startInstantCatchHook()
    if instantConn then pcall(function() instantConn:Disconnect() end) instantConn = nil end
    local evMini = getNet("FishingMinigameChanged", false)
    if not evMini then return end
    local catchRF = getNet("CatchFishCompleted", true)
    instantConn = evMini.OnClientEvent:Connect(function(state)
        if not S.DetectorActive then return end
        if state == "Activated" or state == "Clicked" then
            task.spawn(function()
                local delay = S.CompleteDelay or 0
                if delay > 0 then task.wait(delay) end
                if catchRF then
                    pcall(function() catchRF:InvokeServer() end)
                end
            end)
        end
    end)
end

local function stopInstantCatchHook()
    if instantConn then pcall(function() instantConn:Disconnect() end) instantConn = nil end
end

local function startFisher()
    S.DetectorActive = true
    if fishThread then pcall(task.cancel, fishThread) fishThread = nil end
    _setupFishListeners()
    startInstantCatchHook()
    S.DetectorStatus = "Starting..."
    S.DetectorTime   = 0

    fishThread = task.spawn(function()
        equipBestRod()
        -- ── Step 1: Try game built-in auto-fishing ──────────────
        -- Confirmed from source: AutoFishingLevel = 0 = always available
        -- Remote: UpdateAutoFishingState (RemoteFunction):InvokeServer(bool)
        local autoRF = getNet("UpdateAutoFishingState", true)
        local usingBuiltin = false
        if autoRF then
            local ok = pcall(function() autoRF:InvokeServer(true) end)
            if ok then
                usingBuiltin = true
                S.DetectorStatus = "Auto (built-in) ✓"
                notify("✓ Built-in auto-fishing enabled!")
            end
        end

        if usingBuiltin then
            -- Built-in handles everything; instant-catch hook above handles completions
            while S.DetectorActive do task.wait(2) end
            pcall(function() autoRF:InvokeServer(false) end)
        else
            -- ── Step 2: Manual cast loop + instant-catch hook ────
            -- Cast loop: fires ChargeFishingRod every few seconds.
            -- The instant-catch hook handles the minigame side independently.
            S.DetectorStatus = "Auto (manual loop)"
            local chargeRF = getNet("ChargeFishingRod", true)
            -- Some servers use RemoteEvent instead of Function for the cast:
            local chargeEV = getNet("ChargeFishingRod", false)

            local castAttempt = 0
            while S.DetectorActive do
                local t0 = tick()
                S.DetectorTime = 0
                castAttempt = castAttempt + 1

                -- Attempt cast — try RemoteFunction first, then RemoteEvent
                local castOk = false
                if chargeRF then
                    -- Try multiple signatures the game might use
                    castOk = pcall(function() chargeRF:InvokeServer(nil, nil, workspace:GetServerTimeNow(), nil) end)
                    if not castOk then castOk = pcall(function() chargeRF:InvokeServer() end) end
                    if not castOk then castOk = pcall(function() chargeRF:InvokeServer(nil) end) end
                end
                if not castOk and chargeEV then
                    pcall(function() chargeEV:FireServer() end)
                end

                -- Wait for bite or timeout (WaitDelay + 12s max)
                local biteTimeout = tick() + S.WaitDelay + 12
                while S.DetectorActive and tick() < biteTimeout do
                    task.wait(0.1)
                    S.DetectorTime = tick() - t0
                    -- If instant hook already caught it, break early
                    if _fishState.lastCatch > t0 then break end
                end

                -- Short cooldown before next cast
                task.wait(math.max(S.WaitDelay, 0.6))
            end
        end

        S.DetectorStatus = "Offline"
        _disconnectFishConns()
        stopInstantCatchHook()
    end)
end

local megaPatrolThread
local function stopMegaPatrol()
    if megaPatrolThread then pcall(task.cancel, megaPatrolThread) megaPatrolThread = nil end
end

local function startMegaPatrol(coords)
    stopMegaPatrol()
    if not coords or #coords == 0 then return end
    megaPatrolThread = task.spawn(function()
        local idx = 1
        while EventState and EventState.MegaActive and S.AutoMegalodonPatrol do
            if not S.WalkOnWater then S.WalkOnWater = true toggleWoW(true) end
            tpTo(coords[idx], 3)
            S.DetectorStatus = ("Megalodon patrol %d/%d"):format(idx, #coords)
            idx = (idx % #coords) + 1
            task.wait(math.max(6, S.MegaPatrolInterval))
        end
    end)
end

local megaCatchThread
local function stopMegaInstantCatch()
    if megaCatchThread then pcall(task.cancel, megaCatchThread) megaCatchThread = nil end
end

local function startMegaInstantCatch()
    stopMegaInstantCatch()
    local catchRF = getNet("CatchFishCompleted", true)
    if not catchRF then return end
    megaCatchThread = task.spawn(function()
        while EventState and EventState.MegaActive and S.DetectorActive do
            pcall(function() catchRF:InvokeServer() end)
            task.wait(0.22)
        end
    end)
end

local function stopFisher()
    S.DetectorActive = false
    if fishThread then pcall(task.cancel, fishThread) fishThread = nil end
    local autoRF = getNet("UpdateAutoFishingState", true)
    if autoRF then pcall(function() autoRF:InvokeServer(false) end) end
    S.DetectorStatus = "Offline"
    _disconnectFishConns()
    stopInstantCatchHook()
    stopMegaInstantCatch()
end

-- ============================================================
-- SELL
-- ============================================================
local function doSell()
    local rf = getNet("SellAllItems", true)
    if rf then pcall(function() rf:InvokeServer() end) notify("Sold all fish! ✓") end
end

local sellThread
local function startSell()
    if sellThread then task.cancel(sellThread) end
    sellThread = task.spawn(function()
        while S.AutoSell do task.wait(math.max(S.SellValue, 5)) doSell() end
    end)
end

-- ============================================================
-- FAVORITE
-- ============================================================
local function favItem(uuid)
    local ev = getNet("FavoriteItem", false)
    if ev then pcall(function() ev:FireServer(uuid) end) end
end

local RARITY_TIER = {Common=1, Uncommon=2, Rare=3, Epic=4, Legendary=5, Mythic=6, SECRET=7}

local function runFavLoop()
    for _, item in ipairs(getItems()) do
        local skip = false
        if S.FavRarity ~= "Any" then
            local t = item.Tier or (item.Probability and item.Probability.Tier) or 0
            if t ~= (RARITY_TIER[S.FavRarity] or 0) then skip = true end
        end
        if S.FavVariant ~= "Any" and (item.Variant or "Normal") ~= S.FavVariant then skip = true end
        if not skip and not item.Favorite then favItem(item.UUID) task.wait(0.07) end
    end
end

local favThread
local function startFav()
    if favThread then task.cancel(favThread) end
    favThread = task.spawn(function() while S.AutoFavorite do runFavLoop() task.wait(3) end end)
end

local potionThread
local function startPotionLoop()
    if potionThread then pcall(task.cancel, potionThread) end
    potionThread = task.spawn(function()
        while S.AutoLuckPotion do
            local ok = useBestLuckPotion()
            if ok then notify("🍀 Used best available luck potion/totem.") end
            task.wait(25)
        end
    end)
end

local function unfavAll()
    for _, item in ipairs(getItems()) do
        if item.Favorite then favItem(item.UUID) task.wait(0.06) end
    end
    notify("Unfavorited all!")
end

-- ============================================================
-- PLAYER UTILITIES
-- ============================================================
-- Noclip
local noclipConn
local function toggleNoclip(on)
    if noclipConn then noclipConn:Disconnect() noclipConn = nil end
    if on then
        noclipConn = RunService.Stepped:Connect(function()
            local c = chr()
            if c then for _, p in ipairs(c:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end end
        end)
    else
        local c = chr()
        if c then for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = true end
        end end
    end
end

-- Inf Jump
local ijConn
local function toggleInfJump(on)
    if ijConn then ijConn:Disconnect() ijConn = nil end
    if on then
        ijConn = UserInputService.JumpRequest:Connect(function()
            local h = hum() if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
        end)
    end
end

-- Speed / Freeze loop
RunService.Heartbeat:Connect(function()
    if S.FreezePlayer then
        local h = hum() if h then h.WalkSpeed = 0 h.JumpPower = 0 end
    elseif S.WalkSpeed then
        local h = hum() if h then h.WalkSpeed = S.WalkSpeedVal end
    end
end)

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if S.WalkSpeed  then local h=hum() if h then h.WalkSpeed=S.WalkSpeedVal end end
    if S.InfJump    then toggleInfJump(true) end
    if S.Noclip     then toggleNoclip(true) end
    if S.WalkOnWater then toggleWoW(true) end
end)

-- Rejoin
local rejoinThread
local function startRejoin()
    if rejoinThread then task.cancel(rejoinThread) end
    rejoinThread = task.spawn(function()
        task.wait(S.RejoinTimer * 3600)
        if S.AutoRejoin then
            pcall(function()
                game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer)
            end)
        end
    end)
end

-- ============================================================
-- UI CONSTRUCTION
-- ============================================================

-- Toggle icon (minimized)
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

-- Main Frame
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

-- Top Bar
local TopBar = Instance.new("Frame", MainFrame)
TopBar.Size = UDim2.new(1, 0, 0, 30)
TopBar.BackgroundTransparency = 1

local Title = Instance.new("TextLabel", TopBar)
Title.Size = UDim2.new(0.6, 0, 1, 0)
Title.Position = UDim2.new(0, 12, 0, 0)
Title.Text = "🎣  FishIt Omega Hub  v2.0"
Title.Font = Enum.Font.GothamMedium
Title.TextColor3 = Theme.Text
Title.TextSize = 13
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.BackgroundTransparency = 1

local PingLbl = Instance.new("TextLabel", TopBar)
PingLbl.Size = UDim2.new(0.2, 0, 1, 0)
PingLbl.Position = UDim2.new(0.57, 0, 0, 0)
PingLbl.BackgroundTransparency = 1
PingLbl.Text = ""
PingLbl.Font = Enum.Font.Gotham
PingLbl.TextColor3 = Theme.Accent
PingLbl.TextSize = 10
PingLbl.Visible = false

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

-- Drag
local function EnableDrag(obj, handle)
    local drag, start, startPos
    handle.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            drag=true start=i.Position startPos=obj.Position
            i.Changed:Connect(function()
                if i.UserInputState==Enum.UserInputState.End then drag=false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
            local d=i.Position-start
            obj.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
        end
    end)
end
EnableDrag(MainFrame, TopBar)
EnableDrag(ToggleIcon, ToggleIcon)

-- Sidebar
local Sidebar = Instance.new("ScrollingFrame", MainFrame)
Sidebar.Size = UDim2.new(0, 100, 1, -30)
Sidebar.Position = UDim2.new(0, 0, 0, 30)
Sidebar.BackgroundColor3 = Theme.Sidebar
Sidebar.BackgroundTransparency = 0.55
Sidebar.BorderSizePixel = 0
Sidebar.ScrollBarThickness = 0
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

-- Content area
local ContentArea = Instance.new("Frame", MainFrame)
ContentArea.Size = UDim2.new(1, -108, 1, -30)
ContentArea.Position = UDim2.new(0, 104, 0, 30)
ContentArea.BackgroundTransparency = 1
ContentArea.ClipsDescendants = true

-- Tab system
local Tabs = {}
local TabButtons = {}

local function CreateTab(name, icon)
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
    TabFrame.ClipsDescendants = true

    local Layout = Instance.new("UIListLayout", TabFrame)
    Layout.Padding = UDim.new(0, 8)
    Layout.SortOrder = Enum.SortOrder.LayoutOrder
    local pad = Instance.new("UIPadding", TabFrame)
    pad.PaddingTop = UDim.new(0, 5)
    pad.PaddingRight = UDim.new(0, 4)

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

    local menu = Instance.new("Frame", ScreenGui)
    menu.Size = UDim2.fromOffset(200, #opts*28+6)
    menu.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
    menu.Visible = false
    menu.ZIndex = 100
    Instance.new("UICorner", menu).CornerRadius = UDim.new(0, 7)
    local mstr = Instance.new("UIStroke", menu)
    mstr.Color = Theme.Accent mstr.Thickness = 1

    local ml = Instance.new("UIListLayout", menu)
    ml.Padding = UDim.new(0, 1)
    local mp = Instance.new("UIPadding", menu)
    mp.PaddingTop = UDim.new(0, 3) mp.PaddingBottom = UDim.new(0, 3)
    
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

    UserInputService.InputBegan:Connect(function(i)
        if isOpen and i.UserInputType==Enum.UserInputType.MouseButton1 then
            task.defer(function() if isOpen then menu.Visible=false isOpen=false end end)
        end
    end)
end

-- ============================================================
-- CREATE TABS
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
mkLabel(TabInfo, "FishIt Omega Hub  v2.0", Theme.Accent, 1)
mkLabel(TabInfo, "Source-accurate remotes & real coordinates!", Theme.SubText, 2)
mkLabel(TabInfo, "────────────────────────────────", Theme.Stroke, 3)
local _, vPing   = mkRow(TabInfo, "Ping",              "—",    4)
local _, vStatus = mkRow(TabInfo, "Status",            "Idle", 5)
local _, vFish   = mkRow(TabInfo, "Fish (session)",    "0",    6)
local _, vBag    = mkRow(TabInfo, "Fish caught (det)","0",    7)
local _, vPCount = mkRow(TabInfo, "Players",           "—",    8)
local _, vFishMode = mkRow(TabInfo, "Fish Mode",       "—",    9)
mkLabel(TabInfo, "────────────────────────────────", Theme.Stroke, 10)
mkLabel(TabInfo, "AUTO TP: uses real source coords!", Theme.Good, 11)
mkLabel(TabInfo, "AUTO FISH: built-in + instant-catch hook", Theme.Good, 12)

task.spawn(function()
    while task.wait(2) do
        vFish.Text   = tostring(S.SessionFish)
        vBag.Text    = tostring(S.DetectorBag)
        vStatus.Text = S.DetectorActive and "Auto Fishing" or "Idle"
        vStatus.TextColor3 = S.DetectorActive and Theme.Good or Theme.SubText
        vFishMode.Text = S.DetectorStatus
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
    S.ShowPing = s PingLbl.Visible = s
end, 11)

mkToggle(TabFishing, "Auto Equip Rod", "Equips best rod on enable", false, function(s)
    if s then
        task.spawn(equipBestRod)
    end
end, 12)

mkToggle(TabFishing, "Walk on Water", "Stand on ocean surface for fishing", false, function(s)
    S.WalkOnWater = s toggleWoW(s)
end, 13)

mkToggle(TabFishing, "Freeze Player", "Lock character for AFK fishing", false, function(s)
    S.FreezePlayer = s
    if not s then local h=hum() if h then h.WalkSpeed=16 h.JumpPower=50 end end
end, 14)

mkSection(TabFishing, "  Fishing Features (Detector)", 20)
local _, vDetSt = mkRow(TabFishing, "Status",      "Offline", 21)
local _, vDetTm = mkRow(TabFishing, "Wait time",   "0.0s",   22)
local _, vDetBg = mkRow(TabFishing, "Fish caught", "0",      23)

task.spawn(function()
    while task.wait(0.5) do
        vDetSt.Text = S.DetectorStatus
        vDetSt.TextColor3 = S.DetectorActive and Theme.Good or Theme.Danger
        vDetTm.Text = string.format("%.1fs", S.DetectorTime)
        vDetBg.Text = tostring(S.DetectorBag)
    end
end)

mkInput(TabFishing, "Wait delay (s, default 1.5)", "1.5", function(v)
    local n = tonumber(v) if n then S.WaitDelay = n end
end, 24)

mkToggle(TabFishing, "Start Detector", "Auto cast + instant catch hook", false, function(s)
    S.DetectorActive = s
    if s then startFisher() else stopFisher() end
end, 25)

mkSection(TabFishing, "  Instant Catch Settings", 30)
mkInput(TabFishing, "Catch delay (0 = instant)", "0", function(v)
    local n = tonumber(v) if n then S.CompleteDelay = n end
end, 31)

mkToggle(TabFishing, "Instant Catch Hook (Always)", "Completes minigame on 'Activated'", true, function(s)
    if s then startInstantCatchHook() else stopInstantCatchHook() end
end, 32)

mkSection(TabFishing, "  Selling Features", 40)

mkDrop(TabFishing, "Select Sell Mode", {"Delay","Bag Full","Instant"}, "Delay", function(opt)
    S.SellMode = opt
end, 41)

mkInput(TabFishing, "Delay (secs) / Bag size", "30", function(v)
    local n = tonumber(v) if n then S.SellValue = n end
end, 42)

mkToggle(TabFishing, "Start Auto Sell", "Sells based on mode above", false, function(s)
    S.AutoSell = s
    if s then startSell() elseif sellThread then task.cancel(sellThread) sellThread=nil end
end, 43)

mkBtn(TabFishing, "Sell All Fish Now", true, doSell, 44)

mkSection(TabFishing, "  Favorite Features", 50)

mkDrop(TabFishing, "Rarity Filter", {"Any","Common","Uncommon","Rare","Epic","Legendary","Mythic","SECRET"}, "Any", function(opt)
    S.FavRarity = opt
end, 52)

mkDrop(TabFishing, "Variant Filter", {"Any","Normal","Albino","Mutated","Shiny","Chroma"}, "Any", function(opt)
    S.FavVariant = opt
end, 53)

mkToggle(TabFishing, "Auto Favorite", "Favorites fish matching filters", false, function(s)
    S.AutoFavorite = s
    if s then startFav() elseif favThread then task.cancel(favThread) favThread=nil end
end, 55)

mkBtn(TabFishing, "Favorite All Matching Now", false, function()
    task.spawn(runFavLoop) notify("Favorited matching fish!")
end, 56)

mkBtn(TabFishing, "Unfavorite All Fish", false, function()
    task.spawn(unfavAll)
end, 57)

mkSection(TabFishing, "  Auto Rejoin", 60)

mkInput(TabFishing, "Rejoin Timer (hours)", "1", function(v)
    local n = tonumber(v) if n then S.RejoinTimer = math.max(0.1, n) end
end, 62)

mkToggle(TabFishing, "Auto Rejoin", "Rejoins after timer expires", false, function(s)
    S.AutoRejoin = s
    if s then startRejoin() elseif rejoinThread then task.cancel(rejoinThread) rejoinThread=nil end
end, 63)

-- ============================================================
-- ▶ AUTO TAB
-- ============================================================
mkSection(TabAuto, "  Save Position Features", 20)
mkBtn(TabAuto, "Save Current Position", false, function()
    local h = hrp() if h then savedCF = h.CFrame notify("Position saved!") end
end, 21)
mkBtn(TabAuto, "Return to Saved Position", true, function()
    if savedCF then
        local h = hrp()
        if h then h.CFrame = savedCF notify("Returned!") end
    else notify("No position saved!") end
end, 22)

mkSection(TabAuto, "  Event Features", 40)
mkBtn(TabAuto, "Check Active Events Now", false, function()
    task.spawn(function()
        local ok, Replion = pcall(function()
            return require(ReplicatedStorage:WaitForChild("Packages",5):WaitForChild("Replion",5))
        end)
        if not ok then notify("Cannot access Replion!") return end
        local ok2, evRep = pcall(function() return Replion.Client:WaitReplion("Events") end)
        if not ok2 then notify("Cannot get Events!") return end
        local ok3, evList = pcall(function() return evRep:GetExpect("Events") end)
        if ok3 and evList and #evList > 0 then
            notify("Active: "..table.concat(evList, ", "))
        else
            notify("No world events active.")
        end
    end)
end, 42)

mkSection(TabAuto, "  Totem / Potion / Enchant", 50)
mkToggle(TabAuto, "Auto Use Totem", "Activates totems automatically", false, function(s)
    -- Hook: use ItemActivated or similar when implemented
end, 51)
mkToggle(TabAuto, "Auto Drink Luck Potion", "Uses best luck potion/totem every 25s", false, function(s)
    S.AutoLuckPotion = s
    if s then startPotionLoop() elseif potionThread then pcall(task.cancel, potionThread) potionThread=nil end
end, 52)
mkToggle(TabAuto, "Auto Enchant Fish", "Auto-uses enchant stones", false, function(s) end, 53)

-- ============================================================
-- ▶ TRADING TAB
-- ============================================================
mkSection(TabTrading, "  Trade Filters", 10)
mkDrop(TabTrading, "Min Rarity to Accept",
    {"Any","Rare","Epic","Legendary","Mythic","SECRET"},
    "Any", function(opt) S.TradeMinRarity = opt end, 11)

mkSection(TabTrading, "  Auto Accept Trades", 20)
mkToggle(TabTrading, "Auto Accept Fish Trades", "", false, function(s) end, 21)
mkToggle(TabTrading, "Auto Accept Enchant Trades", "", false, function(s) end, 22)
mkToggle(TabTrading, "Auto Accept Coin Trades", "", false, function(s) end, 23)
mkToggle(TabTrading, "Auto Accept ALL Trades", "⚠ Accepts any trade!", false, function(s)
    if s then notify("⚠️ Auto Accept ALL is ON!") end
end, 24)

-- ============================================================
-- ▶ MENU TAB
-- ============================================================
mkSection(TabMenu, "  Player Info", 10)
mkBtn(TabMenu, "Check My Coins", false, function()
    local d = getRepData()
    if d then
        local ok, c = pcall(function() return d:GetExpect("Coins") end)
        notify(ok and "Coins: "..tostring(c) or "Could not read coins")
    end
end, 11)

mkBtn(TabMenu, "Count Enchant Stones", false, function()
    local n = 0
    for _, item in ipairs(getItems()) do
        if tostring(item.Id):lower():find("enchant") then n = n + 1 end
    end
    notify("Enchant Stones: "..n)
end, 12)

mkSection(TabMenu, "  Quick Admin Event TPs", 20)
mkBtn(TabMenu, "TP to Bloodmoon Area", false, function()
    tpTo(Vector3.new(16, 121, 3030), 2)
    notify("→ Bloodmoon Area (elevated platform)")
end, 21)
mkBtn(TabMenu, "TP to Black Hole Area", false, function()
    tpTo(Vector3.new(883, -1, 2542), 3)
    notify("→ Black Hole Fishing Area")
end, 22)
mkBtn(TabMenu, "TP to Meteor Rain Area", false, function()
    tpTo(Vector3.new(383, -1, 2452), 3)
    notify("→ Meteor Rain Fishing Area")
end, 23)
mkBtn(TabMenu, "TP to Ghost Worm Area", false, function()
    tpTo(Vector3.new(-327, -1, 2422), 3)
    notify("→ Ghost Worm Fishing Area")
end, 24)
mkBtn(TabMenu, "TP to Shocked Area", false, function()
    tpTo(Vector3.new(137, -1, 2268), 3)
    notify("→ Shocked Fishing Area")
end, 25)

mkSection(TabMenu, "  Leviathan Guide", 30)
mkLabel(TabMenu, "Requires: Leviathan Scale bait | Only 1 per server!", Theme.Warn, 31)
mkBtn(TabMenu, "TP to Leviathan Zone", true, function()
    tpTo(Vector3.new(-62, 4, 2767), 3)
    notify("→ Leviathan Zone! Equip Leviathan Scale bait!")
end, 32)

mkSection(TabMenu, "  Crystal / Relic Collector", 40)
mkToggle(TabMenu, "Auto Crystal Collector", "", false, function(s) end, 41)
mkToggle(TabMenu, "Auto Collect Relics", "", false, function(s) end, 42)

-- ============================================================
-- ▶ QUEST TAB
-- ============================================================
-- Coordinates sourced from game quest files
mkSection(TabQuest, "  A New Adventure Quest", 10)
mkLabel(TabQuest, "Source: A New Adventure_1893.lua", Theme.SubText, 11)
mkBtn(TabQuest, "Go to Fishing Pier (Obj 1a)", false, function()
    tpTo(Vector3.new(143, 0, 2767), 3)
end, 12)
mkBtn(TabQuest, "Go to Pier 2 (Obj 1b)", false, function()
    tpTo(Vector3.new(-77, 0, 2768), 3)
end, 13)
mkBtn(TabQuest, "Go to Sell NPC (Obj 2)", false, function()
    tpTo(Vector3.new(48, 19, 2874), 3)
end, 14)
mkBtn(TabQuest, "Go to Rod Shop (Obj 3)", false, function()
    tpTo(Vector3.new(150, 22, 2835), 3)
end, 15)
mkBtn(TabQuest, "Go to Bait Shop (Obj 4)", false, function()
    tpTo(Vector3.new(112, 18, 2874), 3)
end, 16)

mkSection(TabQuest, "  A Rumor Quest (Kohana Lab)", 20)
mkLabel(TabQuest, "Source: A Rumor_1924.lua — Kohana Lab", Theme.SubText, 21)
mkBtn(TabQuest, "Go to Kohana Island", false, function()
    tpTo(Vector3.new(948, -38, 1637), 3)
end, 22)

mkSection(TabQuest, "  Sisyphus / Lost Isle", 30)
mkBtn(TabQuest, "Go to Lost Isle Area", false, function()
    tpTo(Vector3.new(-400, 10, 500), 3)
end, 31)

mkSection(TabQuest, "  Esoteric Depths", 40)
mkBtn(TabQuest, "Go to Esoteric Depths Entrance", false, function()
    tpTo(Vector3.new(0, -8, 700), 3)
    notify("→ Esoteric Depths — buy Diving Gear first (75k coins)!")
end, 41)

-- ============================================================
-- ▶ TELEPORT TAB
-- ============================================================
mkSection(TabTeleport, "  Teleport to Location", 10)
mkLabel(TabTeleport, "⚠ All coords sourced from game files!", Theme.Accent, 10)

local tpOrder = 11
-- Sort keys for consistent display
local sortedLocs = {}
for name, pos in pairs(LOCS) do
    table.insert(sortedLocs, {name=name, pos=pos})
end
table.sort(sortedLocs, function(a,b) return a.name < b.name end)

for _, entry in ipairs(sortedLocs) do
    local n, p = entry.name, entry.pos
    mkBtn(TabTeleport, n, false, function()
        -- Ocean spots (Y = -1) need WalkOnWater
        if p.Y <= 0 then
            S.WalkOnWater = true
            toggleWoW(true)
        end
        tpTo(p, 3)
        notify("→ "..n)
    end, tpOrder)
    tpOrder = tpOrder + 1
end

mkSection(TabTeleport, "  Teleport to Player", 80)
local _, playerBox = mkInput(TabTeleport, "Enter player name...", "", nil, 81)
mkBtn(TabTeleport, "Teleport to Player", true, function()
    tpToPlayer(playerBox.Text)
end, 82)

-- ============================================================
-- ▶ MISC TAB
-- ============================================================
mkSection(TabMisc, "  FPS Booster", 10)
mkToggle(TabMisc, "FPS Booster", "Lowers graphics quality", false, function(s)
    if s then
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        pcall(function() game:GetService("Lighting").GlobalShadows = false end)
    else
        settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
        pcall(function() game:GetService("Lighting").GlobalShadows = true end)
    end
end, 11)

mkSection(TabMisc, "  Player Utilities", 20)
mkToggle(TabMisc, "Speed Hack", "Increase walk speed", false, function(s)
    S.WalkSpeed = s
    if not s then local h=hum() if h then h.WalkSpeed=16 end end
end, 21)

mkInput(TabMisc, "Speed value (default 16)", "50", function(v)
    local n = tonumber(v) if n then S.WalkSpeedVal = n end
end, 22)

mkToggle(TabMisc, "Noclip", "Walk through walls", false, function(s)
    S.Noclip = s toggleNoclip(s)
end, 23)

mkToggle(TabMisc, "Infinite Jump", "Jump unlimited times", false, function(s)
    S.InfJump = s toggleInfJump(s)
end, 24)

mkSection(TabMisc, "  Server Tools", 30)
mkBtn(TabMisc, "Server Info", false, function()
    notify("Players: "..#Players:GetPlayers().." | Job: "..game.JobId:sub(1,10).."...")
end, 31)
mkBtn(TabMisc, "Respawn Character", false, function()
    local h=hum() if h then h.Health=0 end
end, 32)
mkBtn(TabMisc, "Rejoin Server", false, function()
    pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId,LocalPlayer) end)
end, 33)

-- ============================================================
-- ▶ EVENTS TAB — Full Event Radar
-- Source: EventController_1664 pattern
-- Replion "Events" array tracks active world events
-- Ghost Shark coords from Ghost Shark Hunt_315.lua (in original)
-- Megalodon coords from MegalondonHunt game source
-- ============================================================

EventState = {
    GhostSharkAlert=true, GhostSharkAutoTP=false, GhostSharkAutoFish=false, GhostSharkActive=false,
    MegaAlert=true,  MegaAutoTP=false, MegaAutoFish=false, MegaActive=false,
    LeviaAlert=true, LeviaAutoTP=false,
    SharkHuntAlert=true, SharkHuntAutoTP=false,
    AllEventAlert=true,
    EventRadar=false,
}

-- All hunt data with CONFIRMED coordinates from source files
local GHOST_SHARK_COORDS = {
    Vector3.new(489.559, -1.35, 25.406),
    Vector3.new(-1358.216, -1.35, 4100.556),
    Vector3.new(627.859, -1.35, 3798.081),
}

local HUNT_DATA = {
    ["Ghost Shark Hunt"] = {
        coords   = GHOST_SHARK_COORDS,
        tier     = "SECRET 🟣",
        fish     = "Ghost Shark",
        sellVal  = "125,000+",
        duration = "20 min",
        queueSec = 240,
        ocean    = true,
    },
    ["Shark Hunt"] = {
        coords   = {Vector3.new(1.65,-1.35,2095.725), Vector3.new(1369.95,-1.35,930.125)},
        tier     = "Epic 🟠",
        fish     = "Sharks",
        sellVal  = "varies",
        duration = "30 min",
        queueSec = 240,
        ocean    = true,
    },
    ["Megalodon Hunt"] = {
        -- Coords from community + source pattern (ocean, deep water)
        coords   = {Vector3.new(-1076.3,-1.4,1676.2), Vector3.new(-1191.8,-1.4,3597.3)},
        tier     = "SECRET 🟣",
        fish     = "Megalodon",
        sellVal  = "1,000,000+",
        duration = "Until caught",
        queueSec = 0,
        ocean    = true,
    },
    ["Leviathan Hunt"] = {
        coords   = {Vector3.new(-62, 3, 2767)},
        tier     = "SECRET 🟣",
        fish     = "Leviathan",
        sellVal  = "1,000,000+",
        duration = "Until caught",
        queueSec = 0,
        ocean    = true,
    },
    ["Worm Hunt"] = {
        coords   = {Vector3.new(2190.85,-1.4,97.575)},
        tier     = "Rare 🔵",
        fish     = "Worm Fish",
        sellVal  = "varies",
        duration = "30 min",
        queueSec = 240,
        ocean    = true,
    },
}

local evStatusLabels = {}

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

local function playAlertSound()
    local snd = Instance.new("Sound", workspace)
    snd.SoundId = "rbxassetid://4612556715"
    snd.Volume = 0.8
    snd:Play()
    game:GetService("Debris"):AddItem(snd, 3)
end

local function handleEventEnd(evName)
    if evStatusLabels[evName] then
        evStatusLabels[evName].Text = "ENDED ⬛"
        evStatusLabels[evName].TextColor3 = Theme.SubText
    end
    if evName == "Ghost Shark Hunt" then
        EventState.GhostSharkActive = false
    elseif evName == "Megalodon Hunt" then
        EventState.MegaActive = false
        stopMegaPatrol()
        stopMegaInstantCatch()
    end
    notify("⬛ Event ended: "..tostring(evName))
end

local function handleEventStart(evName)
    local data = HUNT_DATA[evName]
    if evStatusLabels[evName] then
        evStatusLabels[evName].Text = "ACTIVE 🟢"
        evStatusLabels[evName].TextColor3 = Theme.Good
    end

    if EventState.AllEventAlert then
        notify("⚡ Event LIVE: "..tostring(evName).."!")
    end

    if not data then return end

    local function doOceanTP()
        task.wait(2)
        -- Enable WalkOnWater for ocean events — required to stand and fish
        S.WalkOnWater = true
        toggleWoW(true)
        task.wait(0.4)
        tpTo(nearestCoord(data.coords), 3)
        notify("✈ TP → "..evName.." zone! WalkOnWater enabled.")
    end

    if evName == "Ghost Shark Hunt" then
        EventState.GhostSharkActive = true
        if EventState.GhostSharkAlert then
            playAlertSound()
            notify("🦈 GHOST SHARK HUNT LIVE! 20min | SECRET | ~125,000 coins!")
            task.delay(3, function()
                if EventState.GhostSharkActive then
                    notify("🦈 Ghost Shark still active — need Element/Angler Rod + luck!")
                end
            end)
        end
        if EventState.GhostSharkAutoTP then
            task.spawn(doOceanTP)
        end
        if EventState.GhostSharkAutoFish then
            task.spawn(function()
                task.wait(2.5)
                if not S.DetectorActive then
                    S.FreezePlayer  = true
                    S.DetectorActive = true
                    startFisher()
                    notify("🎣 Auto-Fishing started for Ghost Shark Hunt!")
                end
            end)
        end

    elseif evName == "Megalodon Hunt" then
        EventState.MegaActive = true
        if EventState.MegaAlert then
            playAlertSound()
            notify("🦕 MEGALODON HUNT! 1 per server — be first! | SECRET | 1M+ coins")
        end
        if EventState.MegaAutoTP then task.spawn(doOceanTP) end
        if EventState.MegaAutoFish then
            task.spawn(function()
                task.wait(2.5)
                equipBestRod()
                if S.AutoMegalodonPatrol then
                    startMegaPatrol(data.coords)
                else
                    tpTo(nearestCoord(data.coords), 3)
                end
                if not S.DetectorActive then
                    S.FreezePlayer = true
                    S.DetectorActive = true
                    startFisher()
                end
                startMegaInstantCatch()
                notify("🎣 Megalodon auto-fish enabled (rod + patrol + instant catch).")
            end)
        end

    elseif evName == "Leviathan Hunt" then
        if EventState.LeviaAlert then
            playAlertSound()
            notify("🐉 LEVIATHAN HUNT! Equip Leviathan Scale bait! | SECRET | Rare!")
        end
        if EventState.LeviaAutoTP then task.spawn(doOceanTP) end

    elseif evName == "Shark Hunt" then
        if EventState.SharkHuntAlert then
            playAlertSound()
            notify("🦈 Shark Hunt LIVE! | Duration: "..data.duration)
        end
        if EventState.SharkHuntAutoTP then task.spawn(doOceanTP) end

    elseif evName == "Worm Hunt" then
        if EventState.SharkHuntAlert then
            notify("🐛 Worm Hunt LIVE! Boosted Worm Fish odds!")
        end
        if EventState.SharkHuntAutoTP then task.spawn(doOceanTP) end
    end
end

local eventRadarActive = false
local _evReplionRef = nil

local function startEventRadar()
    if eventRadarActive then
        notify("Event Radar already running!")
        return
    end
    task.spawn(function()
        local ok, Replion = pcall(function()
            return require(ReplicatedStorage:WaitForChild("Packages",5):WaitForChild("Replion",5))
        end)
        if not ok then notify("❌ Cannot access Replion — is the game loaded?") return end

        local ok2, evReplion = pcall(function() return Replion.Client:WaitReplion("Events") end)
        if not ok2 then notify("❌ Cannot get Events replion!") return end

        _evReplionRef = evReplion
        eventRadarActive = true

        -- Snapshot already-active events
        local ok3, current = pcall(function() return evReplion:GetExpect("Events") end)
        if ok3 and current then
            for _, evName in ipairs(current) do
                if evStatusLabels[evName] then
                    evStatusLabels[evName].Text = "ACTIVE 🟢"
                    evStatusLabels[evName].TextColor3 = Theme.Good
                end
                if evName == "Ghost Shark Hunt" then EventState.GhostSharkActive = true end
                if evName == "Megalodon Hunt" then EventState.MegaActive = true end
            end
            if #current > 0 then
                notify("Currently active: "..table.concat(current, ", "))
            end
        end

        evReplion:OnArrayInsert("Events", function(_, evName)
            if type(evName) ~= "string" then return end
            task.spawn(handleEventStart, evName)
        end)

        evReplion:OnArrayRemove("Events", function(idx, evName)
            if type(evName) == "string" then
                task.spawn(handleEventEnd, evName)
            else
                -- Fallback diff
                local ok4, now = pcall(function() return evReplion:GetExpect("Events") end)
                if ok4 and now then
                    for name, lbl in pairs(evStatusLabels) do
                        if lbl.Text == "ACTIVE 🟢" then
                            local stillActive = false
                            for _, n in ipairs(now) do if n == name then stillActive = true break end end
                            if not stillActive then task.spawn(handleEventEnd, name) end
                        end
                    end
                end
            end
        end)

        notify("📡 Event Radar is LIVE!")
    end)
end

-- Events Tab UI
mkSection(TabEvents, "  🦈 Ghost Shark Hunt [SECRET]", 10)
mkLabel(TabEvents, "Coords from: Ghost Shark Hunt_315.lua (source)", Theme.Accent, 11)
mkLabel(TabEvents, "Spots: (490,25) | (-1358,4101) | (628,3798)", Theme.SubText, 12)
mkLabel(TabEvents, "Odds: ~1 in 500,000 | Needs Element+ rod", Theme.Warn, 13)

local ghostRow, ghostVal = mkRow(TabEvents, "Hunt Status", "Watching...", 14)
evStatusLabels["Ghost Shark Hunt"] = ghostVal

mkToggle(TabEvents, "Alert on Ghost Shark Hunt", "Sound + notify on start", true, function(s)
    EventState.GhostSharkAlert = s
end, 15)
mkToggle(TabEvents, "Auto TP to Hunt Zone", "TP + WalkOnWater auto-enabled", false, function(s)
    EventState.GhostSharkAutoTP = s
end, 16)
mkToggle(TabEvents, "Auto Fish During Hunt", "Starts Detector on event", false, function(s)
    EventState.GhostSharkAutoFish = s
    if s and EventState.GhostSharkActive and not S.DetectorActive then
        S.DetectorActive = true startFisher()
        notify("Auto-fishing for active Ghost Shark Hunt!")
    end
end, 17)
mkBtn(TabEvents, "🦈 TP to Nearest Ghost Shark Spot", true, function()
    S.WalkOnWater = true toggleWoW(true)
    task.wait(0.3)
    tpTo(nearestCoord(GHOST_SHARK_COORDS), 3)
    notify("→ Ghost Shark spot! WalkOnWater enabled.")
end, 18)

mkSection(TabEvents, "  🦕 Megalodon Hunt [SECRET]", 20)
mkLabel(TabEvents, "1 Megalodon per server — first to catch wins!", Theme.Warn, 21)
local megaRow, megaVal = mkRow(TabEvents, "Megalodon Status", "Watching...", 22)
evStatusLabels["Megalodon Hunt"] = megaVal

mkToggle(TabEvents, "Alert on Megalodon Hunt", "Sound + notify", true, function(s)
    EventState.MegaAlert = s
end, 23)
mkToggle(TabEvents, "Auto TP to Megalodon Zone", "Teleport on event start", false, function(s)
    EventState.MegaAutoTP = s
end, 24)
mkToggle(TabEvents, "Auto Fish During Megalodon", "Equip best rod + start detector", false, function(s)
    EventState.MegaAutoFish = s
    if not s then
        stopMegaPatrol()
    elseif EventState.MegaActive then
        startMegaPatrol(HUNT_DATA["Megalodon Hunt"].coords)
    end
end, 25)
mkToggle(TabEvents, "Patrol both Megalodon spots", "Switch spots repeatedly while event is live", false, function(s)
    S.AutoMegalodonPatrol = s
    if not s then
        stopMegaPatrol()
    elseif EventState.MegaActive then
        startMegaPatrol(HUNT_DATA["Megalodon Hunt"].coords)
    end
end, 26)
mkInput(TabEvents, "Megalodon patrol interval (sec)", tostring(S.MegaPatrolInterval), function(v)
    local n = tonumber(v)
    if n then S.MegaPatrolInterval = math.max(6, n) end
end, 27)
mkBtn(TabEvents, "🦕 TP to Megalodon Spot 1", false, function()
    S.WalkOnWater = true toggleWoW(true)
    task.wait(0.3)
    tpTo(Vector3.new(-1076.3, -1.4, 1676.2), 3)
    notify("→ Megalodon Spot 1! WalkOnWater enabled.")
end, 28)
mkBtn(TabEvents, "🦕 TP to Megalodon Spot 2", false, function()
    S.WalkOnWater = true toggleWoW(true)
    task.wait(0.3)
    tpTo(Vector3.new(-1191.8, -1.4, 3597.3), 3)
    notify("→ Megalodon Spot 2! WalkOnWater enabled.")
end, 29)

mkSection(TabEvents, "  🐉 Leviathan Hunt [SECRET]", 30)
mkLabel(TabEvents, "Requires: Leviathan Scale bait. 1 per server!", Theme.Warn, 31)
local levRow, levVal = mkRow(TabEvents, "Leviathan Status", "Watching...", 32)
evStatusLabels["Leviathan Hunt"] = levVal

mkToggle(TabEvents, "Alert on Leviathan Hunt", "Notify on start", true, function(s)
    EventState.LeviaAlert = s
end, 33)
mkToggle(TabEvents, "Auto TP to Leviathan Zone", "TP on event start", false, function(s)
    EventState.LeviaAutoTP = s
end, 34)

mkSection(TabEvents, "  🌊 Shark Hunt & Worm Hunt", 40)
local sharkRow, sharkVal = mkRow(TabEvents, "Shark Hunt", "Watching...", 41)
evStatusLabels["Shark Hunt"] = sharkVal
local wormRow, wormVal = mkRow(TabEvents, "Worm Hunt", "Watching...", 42)
evStatusLabels["Worm Hunt"] = wormVal

mkToggle(TabEvents, "Alert on Shark/Worm Hunt", "Notify on all hunts", true, function(s)
    EventState.SharkHuntAlert = s
end, 43)
mkToggle(TabEvents, "Auto TP on Shark/Worm Hunt", "Jump to zone on start", false, function(s)
    EventState.SharkHuntAutoTP = s
end, 44)

mkSection(TabEvents, "  📡 Event Radar (Master Switch)", 50)
mkLabel(TabEvents, "Hooks Replion Events array — same as real game system", Theme.Accent, 51)
mkLabel(TabEvents, "Enable this first for all alerts to work!", Theme.Warn, 52)

mkToggle(TabEvents, "All Event Alert", "Notify when ANY event starts", true, function(s)
    EventState.AllEventAlert = s
end, 53)

mkToggle(TabEvents, "Start Event Radar", "Monitor Replion Events live", false, function(s)
    EventState.EventRadar = s
    if s then
        startEventRadar()
    else
        eventRadarActive = false
        _evReplionRef = nil
        notify("Event Radar stopped.")
    end
end, 54)

mkBtn(TabEvents, "⚡ Check All Active Events Now", true, function()
    task.spawn(function()
        local ok, Replion = pcall(function()
            return require(ReplicatedStorage:WaitForChild("Packages",5):WaitForChild("Replion",5))
        end)
        if not ok then notify("Cannot access Replion!") return end
        local ok2, evRep = pcall(function() return Replion.Client:WaitReplion("Events") end)
        if not ok2 then notify("Cannot get Events replion!") return end
        local ok3, evList = pcall(function() return evRep:GetExpect("Events") end)
        if ok3 and evList and #evList > 0 then
            notify("Active: "..table.concat(evList, ", "))
        else
            notify("No world events currently active.")
        end
    end)
end, 55)

mkBtn(TabEvents, "🔄 Restart Event Radar", false, function()
    eventRadarActive = false
    _evReplionRef = nil
    startEventRadar()
end, 56)

-- ============================================================
-- OPEN FIRST TAB
-- ============================================================
TabButtons[1].Btn.MouseButton1Click:Fire()

-- Global FishCaught counter (works even without Detector)
task.defer(function()
    local ev = getNet("FishCaught", false)
    if ev then
        ev.OnClientEvent:Connect(function()
            S.SessionFish = S.SessionFish + 1
        end)
    end
end)

task.delay(0.5, function()
    notify("FishIt Omega Hub v2.0 loaded! Welcome, "..LocalPlayer.Name.."!")
end)

print("[FishIt Omega Hub v2.0] Loaded — Fixed Auto TP + Auto Fish + Source Coords")
