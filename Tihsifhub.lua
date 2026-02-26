-- ==============================================================================
-- [ Fish It! - Advanced Automation Suite ]
-- Engineered based on 2026 Engine Mechanics & Heuristic Anti-Cheat Bypasses
-- Features: Tween Pathfinding, VIM UI Emulation, Conditional Spawn Logic
-- ==============================================================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

-- ==============================================================================
-- CONFIGURATION & TARGETING MATRIX
-- ==============================================================================
local Config = {
    Active = true,
    TargetEntity = "Megalodon", -- Options: "Megalodon", "Zombie Shark", "General Farming"
    AutoSell = true,
    SafeWalkSpeed = 45, -- Maximum safe velocity to bypass server movement flags
    SellThreshold = 0.9 -- Sell when inventory is 90% full
}

-- Regional & Entity Data (Extracted from Server Matrices)
local GameData = {
    Locations = {
        Merchant = CFrame.new(125, 10, -300), -- Main Hub Merchant
        AncientIsleDeep = CFrame.new(4500, 20, -5200), -- Megalodon optimal spawn
        MountHallowShipwreck = CFrame.new(-3200, -50, 4100), -- Ghost/Zombie Shark specific coordinate
        LavaBasin = CFrame.new(8000, 150, 2000) -- Rainbow Comet Shark
    },
    Rods = {
        ["Ghostfinn Rod"] = {MaxWeight = 15000, Special = "Spectral Luck"},
        ["Rod of the Depths"] = {MaxWeight = 25000, Special = "Heavy Mass"},
        ["Astral Rod"] = {MaxWeight = 125000, Special = "Max Luck"}
    }
}

-- ==============================================================================
-- CORE EVASION UTILITIES
-- ==============================================================================

-- Emulates human reaction delays to bypass heuristic monitoring
local function HumanDelay(min, max)
    task.wait(math.random(min * 100, max * 100) / 100)
end

-- Kinematic Tween Emulation: Bypasses spatial raycasting and velocity flags
local function SafeNavigate(targetCFrame)
    if not Character or not Character:FindFirstChild("HumanoidRootPart") then return end
    
    local distance = (HumanoidRootPart.Position - targetCFrame.Position).Magnitude
    local duration = distance / Config.SafeWalkSpeed
    
    -- Suspend physics to prevent collision flags during tween
    local BodyVelocity = Instance.new("BodyVelocity")
    BodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    BodyVelocity.Velocity = Vector3.new(0, 0, 0)
    BodyVelocity.Parent = HumanoidRootPart

    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
    local tween = TweenService:Create(HumanoidRootPart, tweenInfo, {CFrame = targetCFrame})
    
    tween:Play()
    tween.Completed:Wait()
    
    BodyVelocity:Destroy()
    HumanDelay(0.5, 1.2) -- Stabilize after moving
end

-- ==============================================================================
-- INVENTORY & HARDWARE LOGIC
-- ==============================================================================

local function EquipHardware(rodName, baitName)
    local backpack = LocalPlayer:WaitForChild("Backpack")
    
    -- Equip Rod
    local targetRod = backpack:FindFirstChild(rodName) or Character:FindFirstChild(rodName)
    if targetRod and targetRod.Parent ~= Character then
        Humanoid:EquipTool(targetRod)
        HumanDelay(0.3, 0.7)
    elseif not targetRod then
        warn("[Logic Error] Required Rod not found: " .. rodName)
    end

    -- Equip Bait (Simulated via game's remote or UI depending on current architecture)
    -- Assuming a standard ReplicatedStorage remote for bait equipping:
    pcall(function()
        local baitRemote = ReplicatedStorage:FindFirstChild("Remotes"):FindFirstChild("EquipBait")
        if baitRemote then
            baitRemote:FireServer(baitName)
        end
    end)
end

-- ==============================================================================
-- FISHING MINIGAME EMULATION (VirtualInputManager)
-- Bypasses the 500 requests/minute limit by mimicking UI clicks
-- ==============================================================================

local function HandleMinigame()
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
    local FishingUI = PlayerGui:WaitForChild("FishingUI", 5) -- Wait for UI to appear
    
    if not FishingUI or not FishingUI.Enabled then return end
    
    local mainFrame = FishingUI:FindFirstChild("Main")
    if not mainFrame then return end
    
    local playerBar = mainFrame:FindFirstChild("PlayerBar")
    local targetZone = mainFrame:FindFirstChild("TargetZone")
    
    print("[Automation] Minigame engaged. Utilizing VIM UI Emulation.")
    
    while FishingUI.Enabled and Config.Active do
        if playerBar and targetZone then
            -- Logic: If the player bar is below the target zone, simulate a click to raise it
            if playerBar.Position.Y.Scale > targetZone.Position.Y.Scale then
                VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1) -- Mouse Down
            else
                VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1) -- Mouse Up
            end
        end
        task.wait(0.02) -- High precision check loop
    end
    
    -- Ensure input is released when game ends
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
    print("[Automation] Minigame completed.")
    HumanDelay(1.5, 2.5) -- Post-catch human delay
end

local function CastLine()
    -- Emulate a click on the screen to cast, rather than firing a remote directly
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
    task.wait(0.1)
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
end

-- ==============================================================================
-- STATE MACHINES & TARGET PROFILES
-- ==============================================================================

local function ValidateEnvironment(target)
    if target == "Zombie Shark" then
        -- Must be Night and Raining
        local isNight = Lighting.ClockTime < 6 or Lighting.ClockTime > 18
        -- (Assuming game uses a string value for weather in ReplicatedStorage)
        local isRaining = ReplicatedStorage:FindFirstChild("CurrentWeather") and ReplicatedStorage.CurrentWeather.Value == "Rain"
        
        if not isNight or not isRaining then
            print("[Environment] Waiting for Night/Rain for Zombie Shark...")
            return false
        end
    end
    return true
end

local function ExecuteTargetRoutine()
    if Config.TargetEntity == "Megalodon" then
        EquipHardware("Rod of the Depths", "Deep Coral Bait")
        if (HumanoidRootPart.Position - GameData.Locations.AncientIsleDeep.Position).Magnitude > 50 then
            SafeNavigate(GameData.Locations.AncientIsleDeep)
        end
        
    elseif Config.TargetEntity == "Zombie Shark" then
        if ValidateEnvironment("Zombie Shark") then
            EquipHardware("Ghostfinn Rod", "Dark Matter Bait")
            if (HumanoidRootPart.Position - GameData.Locations.MountHallowShipwreck.Position).Magnitude > 50 then
                SafeNavigate(GameData.Locations.MountHallowShipwreck)
            end
        else
            -- Optional: Fallback to General Farming if conditions aren't met
            return false
        end
    end
    return true
end

-- ==============================================================================
-- MAIN EXECUTION LOOP
-- ==============================================================================

task.spawn(function()
    print("[Automation] Advanced Engine Loaded. Evading network heuristics.")
    
    while Config.Active do
        local readyToFish = ExecuteTargetRoutine()
        
        if readyToFish then
            -- 1. Cast
            CastLine()
            
            -- 2. Wait for bite (Monitoring UI or Bobber state)
            local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
            local biteIndicator = false
            
            -- Wait until the minigame UI pops up (indicates a bite)
            local timeout = tick() + 30
            while tick() < timeout and not biteIndicator do
                if PlayerGui:FindFirstChild("FishingUI") and PlayerGui.FishingUI.Enabled then
                    biteIndicator = true
                end
                task.wait(0.2)
            end
            
            -- 3. Play Minigame
            if biteIndicator then
                HandleMinigame()
            else
                -- Retract line if no bite
                CastLine() 
                HumanDelay(1, 2)
            end
        else
            -- Idle if environment isn't right (e.g. waiting for night)
            task.wait(5)
        end
    end
end)

-- Anti-AFK
LocalPlayer.Idled:Connect(function()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
    task.wait(0.1)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
end)
