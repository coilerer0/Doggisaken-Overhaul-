--[[
    DoggiSaken — Overhauled & Polished
    Roblox exploit script using Rayfield UI
    Refactored for clarity, safety, and performance
--]]

-- ============================================================
--  SERVICES
-- ============================================================
local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace       = game:GetService("Workspace")

local LocalPlayer     = Players.LocalPlayer

-- ============================================================
--  RAYFIELD UI
-- ============================================================
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Window = Rayfield:CreateWindow({
    Name             = "DoggiSaken",
    LoadingTitle     = "DoggiSaken",
    LoadingSubtitle  = "Loading features...",
    ToggleUIKeybind  = "K",
    KeySystem        = false,
    ConfigurationSaving = {
        Enabled  = true,
        FileName = "DoggiSaken",
    },
})

local Tab = {
    Main    = Window:CreateTab("Main"),
    ESP     = Window:CreateTab("ESP"),
    Combat  = Window:CreateTab("Combat"),
    Support = Window:CreateTab("Support"),
}

-- ============================================================
--  SHARED UTILITIES
-- ============================================================
local Util = {}

--- Safely get the local character's Humanoid.
function Util.GetHumanoid()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildWhichIsA("Humanoid")
end

--- Safely get the local character's HumanoidRootPart.
function Util.GetRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

--- Fire a network remote in ReplicatedStorage.Modules.Network.RemoteEvent.
local _remote
local function getRemote()
    if not _remote or not _remote.Parent then
        _remote = ReplicatedStorage
            :WaitForChild("Modules")
            :WaitForChild("Network")
            :WaitForChild("RemoteEvent")
    end
    return _remote
end

function Util.FireRemote(...)
    pcall(function() getRemote():FireServer(...) end)
end

function Util.FireAbility(buf)
    Util.FireRemote("UseActorAbility", { buf })
end

--- Check whether a character belongs to the Survivors folder.
local _survivorsFolder
local function getSurvivorsFolder()
    if not _survivorsFolder or not _survivorsFolder.Parent then
        local playersFolder = Workspace:FindFirstChild("Players")
        _survivorsFolder = playersFolder and playersFolder:FindFirstChild("Survivors")
    end
    return _survivorsFolder
end

--- Dot-product facing check (returns true if localRoot faces targetRoot within ~107°).
function Util.IsFacing(localRoot, targetRoot, threshold)
    if not localRoot or not targetRoot then return false end
    threshold = threshold or 0.0
    local toTarget = (targetRoot.Position - localRoot.Position).Unit
    return toTarget:Dot(localRoot.CFrame.LookVector) > threshold
end

--- Enumerate all other players.
function Util.OtherPlayers()
    local out = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then out[#out+1] = p end
    end
    return out
end

--- Check if a character is the local killer (not inside Survivors).
function Util.IsKiller()
    local char = LocalPlayer.Character
    if not char or not char.Parent then return false end
    return char.Parent ~= getSurvivorsFolder()
end

--- Returns the map folder (Workspace.Map.Ingame.Map).
function Util.GetMapFolder()
    local map = Workspace:FindFirstChild("Map")
    if map and map:FindFirstChild("Ingame") then
        return map.Ingame:FindFirstChild("Map")
    end
end

--- Returns the Sprinting module from ReplicatedStorage.
function Util.GetSprintingModule()
    return require(
        ReplicatedStorage
            :WaitForChild("Systems")
            :WaitForChild("Character")
            :WaitForChild("Game")
            :WaitForChild("Sprinting")
    )
end

-- ============================================================
--  MAIN TAB  —  Generator
-- ============================================================
do
    Tab.Main:CreateSection("Generator")

    local autoGenEnabled = false
    local autoGenCooldown = 4

    Tab.Main:CreateToggle({
        Name         = "Auto Generator",
        CurrentValue = false,
        Flag         = "AutoGen",
        Callback     = function(v) autoGenEnabled = v end,
    })

    Tab.Main:CreateSlider({
        Name         = "Cooldown",
        Range        = { 1, 15 },
        Increment    = 0.5,
        Suffix       = "s",
        CurrentValue = autoGenCooldown,
        Flag         = "AutoGenCooldown",
        Callback     = function(v) autoGenCooldown = v end,
    })

    task.spawn(function()
        local lastFire = 0
        while task.wait(0.1) do
            if autoGenEnabled and (tick() - lastFire) >= autoGenCooldown then
                pcall(function()
                    local mapFolder = Util.GetMapFolder()
                    if not mapFolder then return end
                    for _, gen in ipairs(mapFolder:GetChildren()) do
                        if gen.Name == "Generator" then
                            local re = gen:FindFirstChild("Remotes")
                                and gen.Remotes:FindFirstChild("RE")
                            if re then re:FireServer() end
                        end
                    end
                end)
                lastFire = tick()
            end
        end
    end)
end

-- ============================================================
--  MAIN TAB  —  Player / Stamina
-- ============================================================
do
    Tab.Main:CreateSection("Player")

    -- Lazy-load the module to avoid blocking at script start
    local SprintingModule
    local defaultLoss, defaultGain

    local function getSprintMod()
        if not SprintingModule then
            SprintingModule = Util.GetSprintingModule()
            defaultLoss     = SprintingModule.StaminaLoss
            defaultGain     = SprintingModule.StaminaGain
        end
        return SprintingModule
    end

    local infStaminaEnabled   = false
    local visualStaminaEnabled = false
    local staminaConnection    -- RenderStepped handle

    -- Apply or revert infinite stamina values
    local function applyStamina()
        local mod = pcall(getSprintMod) and SprintingModule
        if not mod then return end
        if infStaminaEnabled then
            mod.StaminaLoss = 0
            mod.StaminaGain = 9999
        else
            mod.StaminaLoss = defaultLoss or mod.StaminaLoss
            mod.StaminaGain = defaultGain or mod.StaminaGain
        end
    end

    -- Build or rebuild the overhead stamina BillboardGui
    local function createStaminaDisplay()
        local char = LocalPlayer.Character
        if not char then return nil end
        local head = char:WaitForChild("Head")

        local existing = head:FindFirstChild("StaminaDisplay")
        if existing then existing:Destroy() end

        local bb = Instance.new("BillboardGui")
        bb.Name         = "StaminaDisplay"
        bb.Size         = UDim2.new(3, 0, 1, 0)
        bb.StudsOffset  = Vector3.new(0, 3.5, 0)
        bb.AlwaysOnTop  = true
        bb.LightInfluence = 0
        bb.Enabled      = visualStaminaEnabled
        bb.Parent       = head

        local lbl = Instance.new("TextLabel")
        lbl.Size                  = UDim2.fromScale(1, 1)
        lbl.BackgroundTransparency = 1
        lbl.Font                  = Enum.Font.GothamBold
        lbl.TextSize              = 12
        lbl.TextColor3            = Color3.fromRGB(0, 255, 0)
        lbl.TextStrokeTransparency = 0.4
        lbl.Text                  = "Stamina"
        lbl.Parent                = bb

        return lbl
    end

    local function setupStaminaDisplay()
        local lbl = createStaminaDisplay()
        if not lbl then return end

        if staminaConnection then staminaConnection:Disconnect() end
        staminaConnection = RunService.RenderStepped:Connect(function()
            if not visualStaminaEnabled then return end
            pcall(function()
                local mod = getSprintMod()
                local cur = math.floor(mod.Stamina or 0)
                local max = mod.MaxStamina or 100
                lbl.Text = string.format("Stamina  %d / %d", cur, max)
            end)
        end)
    end

    Tab.Main:CreateToggle({
        Name         = "Inf Stamina",
        CurrentValue = false,
        Flag         = "InfStamina",
        Callback     = function(v)
            infStaminaEnabled = v
            applyStamina()
        end,
    })

    Tab.Main:CreateToggle({
        Name         = "Visual Stamina",
        CurrentValue = false,
        Flag         = "VisualStamina",
        Callback     = function(v)
            visualStaminaEnabled = v
            local char = LocalPlayer.Character
            if char then
                local head = char:FindFirstChild("Head")
                local disp = head and head:FindFirstChild("StaminaDisplay")
                if disp then disp.Enabled = v end
            end
        end,
    })

    -- Initialise on existing character
    if LocalPlayer.Character then
        task.delay(1, setupStaminaDisplay)
        applyStamina()
    end

    LocalPlayer.CharacterAdded:Connect(function()
        task.wait(2)
        applyStamina()
        setupStaminaDisplay()
    end)
end

-- ============================================================
--  ESP TAB
-- ============================================================
do
    local ESPState = {
        Killers    = false,
        Survivors  = false,
        Generators = false,
        Items      = false,
    }

    Tab.ESP:CreateSection("Text ESP")

    Tab.ESP:CreateToggle({ Name = "Killers ESP",    Flag = "ESP_Killers",    CurrentValue = false, Callback = function(v) ESPState.Killers    = v end })
    Tab.ESP:CreateToggle({ Name = "Survivors ESP",  Flag = "ESP_Survivors",  CurrentValue = false, Callback = function(v) ESPState.Survivors  = v end })
    Tab.ESP:CreateToggle({ Name = "Generators ESP", Flag = "ESP_Generators", CurrentValue = false, Callback = function(v) ESPState.Generators = v end })
    Tab.ESP:CreateToggle({ Name = "Items ESP",      Flag = "ESP_Items",      CurrentValue = false, Callback = function(v) ESPState.Items      = v end })

    local function getKillersFolder()
        local p = Workspace:FindFirstChild("Players")
        return p and p:FindFirstChild("Killers")
    end
    local function getESPSurvivorsFolder()
        local p = Workspace:FindFirstChild("Players")
        return p and p:FindFirstChild("Survivors")
    end
    local function getItemsFolder()
        return Workspace:FindFirstChild("Items")
    end

    -- Create a BillboardGui tag on an object if not already present
    local function createESPTag(obj, color)
        if obj:FindFirstChild("ESP_Tag") then return end

        local adornee = obj:FindFirstChild("Head")
            or obj:FindFirstChild("HumanoidRootPart")
            or obj:FindFirstChildWhichIsA("BasePart")
        if not adornee then return end

        local bb = Instance.new("BillboardGui")
        bb.Name       = "ESP_Tag"
        bb.Adornee    = adornee
        bb.Size       = UDim2.new(0, 100, 0, 20)
        bb.StudsOffset = Vector3.new(0, 2.5, 0)
        bb.AlwaysOnTop = true
        bb.Enabled    = false
        bb.Parent     = obj

        local lbl = Instance.new("TextLabel")
        lbl.Size                   = UDim2.fromScale(1, 1)
        lbl.BackgroundTransparency = 1
        lbl.TextSize               = 10
        lbl.Font                   = Enum.Font.GothamBold
        lbl.TextStrokeTransparency = 0.4
        lbl.TextColor3             = color
        lbl.Text                   = obj.Name
        lbl.Parent                 = bb
    end

    -- Periodically ensure ESP tags exist on newly spawned entities
    task.spawn(function()
        while task.wait(1.5) do
            if ESPState.Killers then
                local kf = getKillersFolder()
                if kf then
                    for _, k in ipairs(kf:GetChildren()) do
                        if k:IsA("Model") then createESPTag(k, Color3.fromRGB(255, 60, 60)) end
                    end
                end
            end
            if ESPState.Survivors then
                local sf = getESPSurvivorsFolder()
                if sf then
                    for _, s in ipairs(sf:GetChildren()) do
                        if s:IsA("Model") then createESPTag(s, Color3.fromRGB(0, 180, 255)) end
                    end
                end
            end
            if ESPState.Generators then
                local mapFolder = Util.GetMapFolder()
                if mapFolder then
                    for _, gen in ipairs(mapFolder:GetChildren()) do
                        if gen.Name == "Generator" then createESPTag(gen, Color3.fromRGB(180, 0, 255)) end
                    end
                end
            end
            if ESPState.Items then
                local itf = getItemsFolder()
                if itf then
                    for _, item in ipairs(itf:GetChildren()) do
                        createESPTag(item, Color3.fromRGB(255, 200, 0))
                    end
                end
            end
        end
    end)

    -- Every frame, toggle tag visibility based on current ESP state
    RunService.RenderStepped:Connect(function()
        local kf = getKillersFolder()
        if kf then
            for _, obj in ipairs(kf:GetChildren()) do
                local bb = obj:FindFirstChild("ESP_Tag")
                if bb then bb.Enabled = ESPState.Killers end
            end
        end
        local sf = getESPSurvivorsFolder()
        if sf then
            for _, obj in ipairs(sf:GetChildren()) do
                local bb = obj:FindFirstChild("ESP_Tag")
                if bb then bb.Enabled = ESPState.Survivors end
            end
        end
        local mapFolder = Util.GetMapFolder()
        if mapFolder then
            for _, gen in ipairs(mapFolder:GetChildren()) do
                local bb = gen:FindFirstChild("ESP_Tag")
                if bb then bb.Enabled = ESPState.Generators end
            end
        end
        local itf = getItemsFolder()
        if itf then
            for _, item in ipairs(itf:GetChildren()) do
                local bb = item:FindFirstChild("ESP_Tag")
                if bb then bb.Enabled = ESPState.Items end
            end
        end
    end)
end

-- ============================================================
--  COMBAT TAB  —  Pizza Aimbot
-- ============================================================
do
    Tab.Combat:CreateSection("Pizza Aimbot")

    local pizzaEnabled    = false
    local pizzaDistance   = 100
    local targetModeOn    = false
    local selectedTarget  = nil

    local PIZZA_ANIMS = {
        ["114155003741146"] = true,
        ["12662553001"]     = true,
        ["104033348426533"] = true,
    }

    local currentTarget, wasPlaying, autoRotateOff = nil, false, false

    local function isPizzaAnimPlaying()
        local hum = Util.GetHumanoid()
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        if not animator then return false end
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            local id = track.Animation and track.Animation.AnimationId:match("%d+")
            if id and PIZZA_ANIMS[id] then return true end
        end
        return false
    end

    local function getWeakestSurvivorInRange()
        local root = Util.GetRoot()
        if not root then return nil end
        local weakest, lowestHP = nil, math.huge
        local sf = getSurvivorsFolder()
        if not sf then return nil end
        for _, m in ipairs(sf:GetChildren()) do
            if m:IsA("Model") and m ~= LocalPlayer.Character then
                local h = m:FindFirstChildWhichIsA("Humanoid")
                local r = m:FindFirstChild("HumanoidRootPart")
                if h and r and h.Health > 0 then
                    local dist = (r.Position - root.Position).Magnitude
                    if dist <= pizzaDistance and h.Health < lowestHP then
                        lowestHP = h.Health
                        weakest  = m
                    end
                end
            end
        end
        return weakest
    end

    local function getSelectedCharacter()
        local plr  = selectedTarget
        local char = plr and plr.Character
        local hum  = char and char:FindFirstChildWhichIsA("Humanoid")
        local r    = char and char:FindFirstChild("HumanoidRootPart")
        if char and hum and r and hum.Health > 0 then return char end
    end

    RunService.RenderStepped:Connect(function()
        if not pizzaEnabled then
            currentTarget, wasPlaying = nil, false
            if autoRotateOff then
                local h = Util.GetHumanoid()
                if h then h.AutoRotate = true end
                autoRotateOff = false
            end
            return
        end

        local hum  = Util.GetHumanoid()
        local root = Util.GetRoot()
        if not hum or not root then return end

        local playing = isPizzaAnimPlaying()

        if playing and not currentTarget then
            currentTarget = targetModeOn and getSelectedCharacter() or getWeakestSurvivorInRange()
        end

        if not playing and wasPlaying then
            currentTarget = nil
            hum.AutoRotate = true
            autoRotateOff  = false
        end
        wasPlaying = playing

        if playing and currentTarget then
            local hrp = currentTarget:FindFirstChild("HumanoidRootPart")
            if hrp then
                hum.AutoRotate = false
                autoRotateOff  = true
                local look = Vector3.new(hrp.Position.X, root.Position.Y, hrp.Position.Z)
                root.CFrame = root.CFrame:Lerp(CFrame.lookAt(root.Position, look), 0.95)
            end
        end
    end)

    LocalPlayer.CharacterAdded:Connect(function()
        task.wait(1)
        currentTarget, wasPlaying = nil, false
    end)

    -- UI
    Tab.Combat:CreateToggle({
        Name = "Pizza Aim",  Flag = "PizzaAim",  CurrentValue = false,
        Callback = function(v) pizzaEnabled = v end,
    })

    Tab.Combat:CreateInput({
        Name = "Aim Distance",  Flag = "PizzaDist",
        PlaceholderText = "100",  RemoveTextAfterFocusLost = false,
        Callback = function(t)
            local n = tonumber(t)
            if n then pizzaDistance = n end
        end,
    })

    Tab.Combat:CreateToggle({
        Name = "Target Mode",  Flag = "PizzaTargetMode",  CurrentValue = false,
        Callback = function(v)
            targetModeOn   = v
            selectedTarget = nil
        end,
    })

    local dropdown
    local function refreshPlayerList()
        local list = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then list[#list+1] = p.Name end
        end
        if dropdown then dropdown:Refresh(list, true) end
        return list
    end

    dropdown = Tab.Combat:CreateDropdown({
        Name = "Select Player",  Options = refreshPlayerList(),
        Callback = function(opt)
            local name = typeof(opt) == "table" and opt[1] or opt
            selectedTarget = Players:FindFirstChild(name)
        end,
    })

    Tab.Combat:CreateButton({
        Name = "Refresh Player List",
        Callback = refreshPlayerList,
    })

    Players.PlayerAdded:Connect(refreshPlayerList)
    Players.PlayerRemoving:Connect(refreshPlayerList)
    task.delay(1, refreshPlayerList)
end

-- ============================================================
--  COMBAT TAB  —  Auto Slash
-- ============================================================
do
    Tab.Combat:CreateSection("Auto Slash")

    local autoSlash   = false
    local autoAim     = false
    local slashRage   = 12
    local slashCooldown = 30
    local lastSlash   = 0

    local SLASH_TARGETS = {
        "Slasher", "c00lkidd", "JohnDoe", "1x1x1x1",
        "Noli", "Guest 666", "Sixer", "Nosferatu",
    }

    local humanoid, hrp

    local function setupChar(char)
        humanoid = char:WaitForChild("Humanoid")
        hrp      = char:WaitForChild("HumanoidRootPart")
    end
    if LocalPlayer.Character then setupChar(LocalPlayer.Character) end
    LocalPlayer.CharacterAdded:Connect(setupChar)

    local function getSlashTarget()
        if not hrp then return end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                local c = plr.Character
                local r = c:FindFirstChild("HumanoidRootPart")
                if r and (r.Position - hrp.Position).Magnitude <= slashRage then
                    for _, name in ipairs(SLASH_TARGETS) do
                        if c.Name:lower():find(name:lower()) then return r end
                    end
                end
            end
        end
    end

    RunService.RenderStepped:Connect(function()
        if not humanoid or not hrp then return end
        local target = getSlashTarget()
        if not target then return end

        local now  = tick()
        local ready = (now - lastSlash) >= slashCooldown

        if autoAim and ready then
            local dir = (target.Position - hrp.Position).Unit
            hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, math.atan2(-dir.X, -dir.Z), 0)
        end

        if autoSlash and ready then
            lastSlash = now
            Util.FireAbility(buffer.fromstring("\3\5\0\0\0Slash"))
        end
    end)

    Tab.Combat:CreateToggle({ Name = "Auto Slash", Flag = "AutoSlash", CurrentValue = false, Callback = function(v) autoSlash = v end })
    Tab.Combat:CreateToggle({ Name = "Auto Aim",   Flag = "SlashAim",  CurrentValue = false, Callback = function(v) autoAim  = v end })
    Tab.Combat:CreateInput({
        Name = "Rage",  Flag = "SlashRage",  PlaceholderText = "12",  RemoveTextAfterFocusLost = false,
        Callback = function(t)
            local n = tonumber(t)
            if n then slashRage = n end
        end,
    })
end

-- ============================================================
--  COMBAT TAB  —  Chance Aim (Flintlock)
-- ============================================================
do
    Tab.Combat:CreateSection("Chance Aim")

    local aimActive      = false
    local aimPrediction  = 2
    local aimDuration    = 1.6
    local aimThreshold   = 0.5

    local CHANCE_TARGETS = { "Slasher", "c00lkidd", "JohnDoe", "1x1x1x1", "Noli", "Guest 666", "Sixer", "Nosferatu" }

    local playerHum, playerHRP
    local aiming, triggerTime       = false, 0
    local origWS, origAutoRotate    = nil, nil
    local prevFlintVisible          = false

    local function configChar(char)
        playerHum = char:FindFirstChild("Humanoid")
        playerHRP = char:FindFirstChild("HumanoidRootPart")
    end
    if LocalPlayer.Character then configChar(LocalPlayer.Character) end
    LocalPlayer.CharacterAdded:Connect(configChar)

    local function findChanceTarget()
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                local r = plr.Character:FindFirstChild("HumanoidRootPart")
                if r then
                    for _, n in ipairs(CHANCE_TARGETS) do
                        if plr.Character.Name:lower():find(n:lower()) then return r end
                    end
                end
            end
        end
    end

    local function isFlintlockVisible()
        if not LocalPlayer.Character then return false end
        local flint = LocalPlayer.Character:FindFirstChild("Flintlock", true)
        if not flint then return false end
        if not (flint:IsA("BasePart") or flint:IsA("MeshPart") or flint:IsA("UnionOperation")) then
            flint = flint:FindFirstChildWhichIsA("BasePart", true)
            if not flint then return false end
        end
        return flint.Transparency < 1
    end

    local function stopAim()
        aiming = false
        if origWS ~= nil and playerHum then
            playerHum.WalkSpeed  = origWS
            playerHum.AutoRotate = origAutoRotate
        end
        origWS, origAutoRotate = nil, nil
    end

    RunService.RenderStepped:Connect(function()
        if not aimActive or not playerHum or not playerHRP then
            if aiming then stopAim() end
            return
        end

        local visible = isFlintlockVisible()
        if not aiming and visible and not prevFlintVisible then
            triggerTime   = tick()
            aiming        = true
            origWS        = playerHum.WalkSpeed
            origAutoRotate = playerHum.AutoRotate
        end
        prevFlintVisible = visible

        if aiming then
            local tHRP = findChanceTarget()
            if not tHRP
                or (tHRP.Position - playerHRP.Position).Magnitude < 6
                or (tick() - triggerTime) > aimDuration
                or not visible then
                stopAim()
                return
            end

            playerHum.AutoRotate = false
            playerHRP.AssemblyAngularVelocity = Vector3.zero

            local vel = tHRP.Velocity
            local predicted = (vel.Magnitude > aimThreshold)
                and (tHRP.Position + tHRP.CFrame.LookVector * aimPrediction)
                or   tHRP.Position

            local dir = (predicted - playerHRP.Position).Unit
            playerHRP.CFrame = CFrame.new(playerHRP.Position)
                * CFrame.Angles(0, math.atan2(-dir.X, -dir.Z), 0)
        end
    end)

    Tab.Combat:CreateToggle({ Name = "Auto Aim",     Flag = "ChanceAim", CurrentValue = false, Callback = function(v) aimActive = v end })
    Tab.Combat:CreateInput({
        Name = "Aim Prediction",  Flag = "ChancePred",  PlaceholderText = "2",  RemoveTextAfterFocusLost = false,
        Callback = function(t)
            local n = tonumber(t)
            if n then aimPrediction = n end
        end,
    })
end

-- ============================================================
--  COMBAT TAB  —  Dusekkar Aimbot
-- ============================================================
do
    Tab.Combat:CreateSection("Dusekkar Aimbot")

    local enabled      = false
    local aimMode      = "Survivor"
    local healthPenalty = 1000

    local DUSEK_ANIM_IDS = { "77894750279891", "118933622288262" }
    local KILLER_NAMES   = { "Slasher", "c00lkidd", "JohnDoe", "1x1x1x1", "Noli", "Sixer", "Nosferatu" }

    local aiming         = false
    local humanoid       = nil
    local animConnection = nil

    local Camera = Workspace.CurrentCamera

    local function getNearestTarget()
        local char = LocalPlayer.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local playersFolder = Workspace:FindFirstChild("Players")
        if not playersFolder then return end
        local survivors = playersFolder:FindFirstChild("Survivors")
        local killers   = playersFolder:FindFirstChild("Killers")

        local best, bestScore = nil, math.huge

        local function check(model, isKillerModel)
            if not model:IsA("Model") or model == char then return end
            local nameMatch = table.find(KILLER_NAMES, model.Name) ~= nil
            if isKillerModel  and not nameMatch then return end
            if not isKillerModel and nameMatch  then return end

            local tHRP = model:FindFirstChild("HumanoidRootPart")
            local hum  = model:FindFirstChildOfClass("Humanoid")
            if not tHRP or not hum or hum.Health <= 0 then return end

            local dist  = (tHRP.Position - hrp.Position).Magnitude ^ 2
            local score = dist + (healthPenalty * (hum.Health / math.max(hum.MaxHealth, 1)))
            if score < bestScore then bestScore = score; best = tHRP end
        end

        if aimMode == "Survivor" and survivors then
            for _, m in ipairs(survivors:GetChildren()) do check(m, false) end
        elseif aimMode == "Killer" and killers then
            for _, m in ipairs(killers:GetChildren()) do check(m, true) end
        elseif aimMode == "Random" then
            if survivors then for _, m in ipairs(survivors:GetChildren()) do check(m, false) end end
            if killers   then for _, m in ipairs(killers:GetChildren())   do check(m, true)  end end
        end

        return best
    end

    local function setupDusekCharacter(char)
        humanoid = char:WaitForChild("Humanoid", 5)
        if not humanoid then return end

        if animConnection then pcall(function() animConnection:Disconnect() end) end
        local animator = humanoid:FindFirstChildOfClass("Animator")
        if not animator then return end

        animConnection = animator.AnimationPlayed:Connect(function(track)
            local id = track.Animation.AnimationId:match("%d+")
            if table.find(DUSEK_ANIM_IDS, id) then
                task.delay(0.5, function()
                    if enabled then aiming = true end
                end)
                track.Stopped:Once(function() aiming = false end)
            end
        end)
    end

    if LocalPlayer.Character then setupDusekCharacter(LocalPlayer.Character) end
    LocalPlayer.CharacterAdded:Connect(function(c) task.delay(1, setupDusekCharacter, c) end)

    RunService.RenderStepped:Connect(function()
        if not enabled or not aiming or not humanoid then return end
        local target = getNearestTarget()
        if target then
            Camera.CFrame = CFrame.new(Camera.CFrame.Position, target.Position)
        end
    end)

    Tab.Combat:CreateToggle({
        Name = "Aim",  Flag = "DusekAim",  CurrentValue = false,
        Callback = function(v) enabled = v; aiming = false end,
    })
    Tab.Combat:CreateDropdown({
        Name = "Aim Mode",  Options = { "Survivor", "Killer", "Random" },
        CurrentOption = "Survivor",  Flag = "DusekMode",
        Callback = function(opt)
            aimMode = typeof(opt) == "table" and opt[1] or opt
        end,
    })
end

-- ============================================================
--  COMBAT TAB  —  Auto M1 (Killer)
-- ============================================================
do
    local autoM1         = false
    local aimEnabled     = true
    local aimDistance    = 15
    local facingCheck    = true

    local M1_BUFFERS = {
        ["c00lkidd"]  = buffer.fromstring("\3\5\0\0\0Punch"),
        ["Noli"]      = buffer.fromstring("\3\4\0\0\0Stab"),
        ["Sixer"]     = buffer.fromstring("\3\13\0\0\0Carving Slash"),
        ["Guest 666"] = buffer.fromstring("\3\13\0\0\0Carving Slash"),
        ["Slasher"]   = buffer.fromstring("\3\5\0\0\0Slash"),
        ["JohnDoe"]   = buffer.fromstring("\3\5\0\0\0Slash"),
        ["1x1x1x1"]   = buffer.fromstring("\3\5\0\0\0Slash"),
        ["Nosferatu"] = buffer.fromstring("\3\5\0\0\0Slash"),
    }
    local DEFAULT_BUFFER = buffer.fromstring("\3\5\0\0\0Slash")

    local ANTI_M1_ANIMS = {
        ["rbxassetid://100926346851492"] = true, ["rbxassetid://140671644163156"] = true,
        ["rbxassetid://72182155407310"]  = true, ["rbxassetid://72722244508749"]  = true,
        ["rbxassetid://95802026624883"]  = true, ["rbxassetid://88557287105521"]  = true,
        ["rbxassetid://82605295530067"]  = true, ["rbxassetid://96959123077498"]  = true,
        ["rbxassetid://120748030255574"] = true, ["rbxassetid://88287038085804"]  = true,
        ["rbxassetid://115706752305794"] = true, ["rbxassetid://82036084568393"]  = true,
    }
    local PROTECTED_SKILLS = {
        "VoidRush","Nova","CorruptEnergy","Behead","GashingWound","MassInfection",
        "CorruptNature","WalkspeedOverride","PizzaDelivery","UnstableEye",
        "Entanglement","DigitalFootprint","404Error","RagingPace",
        "DemonicPursuit","InfernalCry","BloodRush",
    }

    local currentBuffer   = DEFAULT_BUFFER
    local lastM1Fire      = 0
    local M1_COOLDOWN     = 0.1

    local function updateBuffer()
        local char = LocalPlayer.Character
        if char and Util.IsKiller() then
            currentBuffer = M1_BUFFERS[char.Name] or DEFAULT_BUFFER
        end
    end

    local function isUsingProtectedSkill(target)
        local hum = target and target:FindFirstChildWhichIsA("Humanoid")
        if hum then
            local anim = hum:FindFirstChildWhichIsA("Animator")
            if anim then
                for _, track in ipairs(anim:GetPlayingAnimationTracks()) do
                    if ANTI_M1_ANIMS[track.Animation.AnimationId] then return true end
                end
            end
        end
        for _, skill in ipairs(PROTECTED_SKILLS) do
            if target:FindFirstChild(skill) then return true end
        end
        return false
    end

    local function getNearestSurvivor()
        local root = Util.GetRoot()
        if not root then return end
        local sf = getSurvivorsFolder()
        if not sf then return end
        local best, bestDist = nil, math.huge
        for _, m in ipairs(sf:GetChildren()) do
            local r = m:FindFirstChild("HumanoidRootPart")
            local h = m:FindFirstChildWhichIsA("Humanoid")
            if r and h and h.Health > 0 then
                local d = (r.Position - root.Position).Magnitude
                if d < bestDist and d <= aimDistance then
                    bestDist = d
                    best     = m
                end
            end
        end
        return best
    end

    if LocalPlayer.Character then updateBuffer() end
    LocalPlayer.CharacterAdded:Connect(function() task.wait(0.5); updateBuffer() end)

    RunService.RenderStepped:Connect(function()
        if not autoM1 then
            local h = Util.GetHumanoid()
            if h then h.AutoRotate = true end
            return
        end

        if not Util.IsKiller() then
            local h = Util.GetHumanoid()
            if h then h.AutoRotate = true end
            return
        end

        local hum  = Util.GetHumanoid()
        local root = Util.GetRoot()
        if not hum or not root or hum.Health <= 0 then return end

        local target = getNearestSurvivor()
        if not target then
            hum.AutoRotate = true
            return
        end

        if isUsingProtectedSkill(target) then
            hum.AutoRotate = true
            return
        end

        local tr = target:FindFirstChild("HumanoidRootPart")
        if not tr then return end

        if facingCheck and not Util.IsFacing(root, tr, 0.0) then
            hum.AutoRotate = true
            return
        end

        if (tick() - lastM1Fire) >= M1_COOLDOWN then
            lastM1Fire = tick()
            Util.FireAbility(currentBuffer)
        end

        if aimEnabled then
            hum.AutoRotate = false
            local lookPos = Vector3.new(tr.Position.X, root.Position.Y, tr.Position.Z)
            root.CFrame = root.CFrame:Lerp(CFrame.lookAt(root.Position, lookPos), 0.9)
        else
            hum.AutoRotate = true
        end
    end)

    Tab.Combat:CreateSection("Auto M1 Killer")
    Tab.Combat:CreateToggle({ Name = "Auto M1",       Flag = "AutoM1",        CurrentValue = false, Callback = function(v) autoM1       = v end })
    Tab.Combat:CreateToggle({ Name = "Aim",           Flag = "M1Aim",         CurrentValue = true,  Callback = function(v) aimEnabled   = v end })
    Tab.Combat:CreateToggle({ Name = "Facing Check",  Flag = "M1FacingCheck", CurrentValue = true,  Callback = function(v) facingCheck  = v end })
    Tab.Combat:CreateInput({
        Name = "Rage",  Flag = "M1Rage",  PlaceholderText = "15",  RemoveTextAfterFocusLost = false,
        Callback = function(t)
            local n = tonumber(t)
            if n then aimDistance = math.clamp(n, 1, 50) end
        end,
    })
end

-- ============================================================
--  COMBAT TAB  —  1x1x1x1 Aim
-- ============================================================
do
    Tab.Combat:CreateSection("1x1x1x1 Aim")

    local aimEnabled       = false
    local aimMode          = "One Player"
    local predictMovement  = false
    local autoRotateOff    = false
    local currentTarget    = nil
    local wasPlaying       = false

    local KILLER_MODELS = { ["1x1x1x1"] = true }

    local DANGER_ANIMS = {
        ["119181003138006"] = true, ["99050723653468"]  = true,
        ["100592913030351"] = true, ["81935774508746"]  = true,
        ["116814116277716"] = true, ["86799093901669"]  = true,
        ["83685305553364"]  = true, ["99030950661794"]  = true,
        ["101101433684051"] = true, ["116787687605496"] = true,
        ["109777684604906"] = true, ["105026134432828"] = true,
        ["91237398850193"]  = true, ["104897856211468"] = true,
        ["112598064360414"] = true,
    }

    local function isLocalKiller()
        local char = LocalPlayer.Character
        return char and KILLER_MODELS[char.Name] or false
    end

    local function isDangerAnimPlaying()
        local hum = Util.GetHumanoid()
        if not hum then return false end
        local anim = hum:FindFirstChildOfClass("Animator")
        if not anim then return false end
        for _, track in ipairs(anim:GetPlayingAnimationTracks()) do
            local id = tostring(track.Animation.AnimationId):match("%d+")
            if id and DANGER_ANIMS[id] then return true end
        end
        return false
    end

    local function getClosestSurvivor()
        local root = Util.GetRoot()
        if not root then return end
        local closest, dist = nil, math.huge
        for _, model in ipairs(getSurvivorsFolder():GetChildren()) do
            if model:IsA("Model") then
                local hrp = model:FindFirstChild("HumanoidRootPart")
                local hum = model:FindFirstChildWhichIsA("Humanoid")
                if hrp and hum and hum.Health > 0 then
                    local d = (hrp.Position - root.Position).Magnitude
                    if d < dist then dist = d; closest = model end
                end
            end
        end
        return closest
    end

    RunService.RenderStepped:Connect(function()
        if not aimEnabled then
            local h = Util.GetHumanoid()
            if h and autoRotateOff then h.AutoRotate = true; autoRotateOff = false end
            currentTarget = nil; wasPlaying = false
            return
        end

        if not isLocalKiller() then return end

        local hum  = Util.GetHumanoid()
        local root = Util.GetRoot()
        if not hum or not root then return end

        local playing = isDangerAnimPlaying()

        if playing and not currentTarget then currentTarget = getClosestSurvivor() end

        if not playing and wasPlaying then
            currentTarget = nil
            if autoRotateOff then hum.AutoRotate = true; autoRotateOff = false end
        end
        wasPlaying = playing

        if currentTarget and playing then
            local hrp = currentTarget:FindFirstChild("HumanoidRootPart")
            local hum2 = currentTarget:FindFirstChildWhichIsA("Humanoid")
            if not hrp or not hum2 or hum2.Health <= 0 then currentTarget = nil; return end

            if not autoRotateOff then hum.AutoRotate = false; autoRotateOff = true end

            local targetPos = hrp.Position
            if predictMovement and hrp.Velocity.Magnitude > 2 then
                targetPos = targetPos + hrp.CFrame.LookVector * 3
            end

            if aimMode == "Multi Players" then currentTarget = getClosestSurvivor() end

            local look = Vector3.new(targetPos.X, root.Position.Y, targetPos.Z)
            root.CFrame = root.CFrame:Lerp(CFrame.lookAt(root.Position, look), 0.99)
        end
    end)

    Tab.Combat:CreateToggle({ Name = "Aim",              Flag = "XAim",     CurrentValue = false, Callback = function(v) aimEnabled      = v end })
    Tab.Combat:CreateDropdown({ Name = "Mode", Options = {"One Player","Multi Players"}, CurrentOption = "One Player", Flag = "XAimMode",
        Callback = function(v) aimMode = typeof(v)=="table" and v[1] or v end })
    Tab.Combat:CreateToggle({ Name = "Predict Movement", Flag = "XPredict", CurrentValue = false, Callback = function(v) predictMovement = v end })
end

-- ============================================================
--  COMBAT TAB  —  Auto Block / Punch
-- ============================================================
do
    Tab.Combat:CreateSection("Auto Block")

    local autoBlock      = false
    local blockMode      = "Block"
    local facingCheck    = true
    local autoPunch      = false
    local autoPunchAim   = false
    local blockRage      = 20

    local lastBlockTime  = 0
    local lastPunchTime  = 0
    local BLOCK_CD       = 0.7
    local PUNCH_CD       = 0.6
    local AIM_WINDOW     = 0.5
    local AIM_CD         = 0.6

    local blockPrev      = {}
    local lastAimTrigger = {}

    local KILLER_NAMES   = { "c00lkidd","Jason","JohnDoe","1x1x1x1","Noli","Slasher","Sixer","Nosferatu" }
    local KILLER_DELAYS  = {
        ["c00lkidd"]  = 0,    ["jason"]    = 0.005,
        ["slasher"]   = 0.005,["1x1x1x1"]  = 0.15,
        ["johndoe"]   = 0.33, ["noli"]     = 0.14,
        ["nosferatu"] = 0.7,
    }

    local BLOCK_TRIGGER_ANIMS = {
        "105458270463374","126830014841198","129260077168659","114375669802778",
        "80208162053146","135853087227453","88451353906104","116618003477002",
        "83829782357897","118298475669935","74707328554358","109667959938617",
        "120112897026015","125403313786645","94958041603347","130958529065375",
        "106860049270347","124705663396411","70948173568515","126355327951215",
        "82113744478546","133336594357903","126681776859538","81639435858902",
        "126727756047566","110702884830060","101736016625776","109845134167647",
        "121086746534252","113440898787986","118901677478609","86204001129974",
        "81255669374177","83446441317389","129976080405072","140125695162370",
        "77154853064447","93316899246221","137314737492715","138390711856189",
        "121043188582126","106847695270773","91758760621955","114356208094580",
        "126896426760253","135884061951801","139321362207112","137642639873297",
        "132221505301108","94634594529334","100358581940485","86185540502966",
        "106538427162796","77375846492436","93366464803829","91509234639766",
        "86510482379594","133990700986998","84895799077246","84413781229733",
        "128414736976503","133363345661032","139309647473555","122709416391891",
        "91628732643385","124269076578545","90620531468240","71834552297085",
        "110877859670130","12222208","10548112","127324570265084","105937652127383",
        "102923788301986","11998777","88970503168421","81299297965542",
        "93069721274110","97167027849946","118919403162061","131219306779772",
        "106776364623742","127846074966393","123345437821399","18885909645",
        "121080480916189","131543461321709","84069821282466","114126519127454",
        "70371667919898","137679730950847",
    }

    local PUNCH_ANIM_IDS = {
        "87259391926321","138040001965654","136007065400978","108911997126897",
        "129843313690921","81905101227053","113936304594883","140703210927645",
        "86709774283672","119850211147676","108807732150251","111270184603402",
        "86096387000557","99422325754526","82137285150006","78440860685556",
    }

    local function isFacingLocal(localRoot, targetRoot)
        if not facingCheck then return true end
        return Util.IsFacing(localRoot, targetRoot, -0.3)
    end

    local function getNearestKillerInRange()
        local root = Util.GetRoot()
        if not root then return end
        local nearest, minD = nil, math.huge
        for _, plr in ipairs(Util.OtherPlayers()) do
            local char = plr.Character
            if char then
                local isK = false
                for _, n in ipairs(KILLER_NAMES) do
                    if char.Name:lower():find(n:lower()) then isK = true; break end
                end
                if isK then
                    local r = char:FindFirstChild("HumanoidRootPart")
                    if r then
                        local d = (r.Position - root.Position).Magnitude
                        if d < minD and d <= blockRage then minD = d; nearest = r end
                    end
                end
            end
        end
        return nearest
    end

    local function getPunchCharges()
        local gui = LocalPlayer:FindFirstChild("PlayerGui")
        local charges = gui
            and gui:FindFirstChild("MainUI")
            and gui.MainUI:FindFirstChild("AbilityContainer")
            and gui.MainUI.AbilityContainer:FindFirstChild("Punch")
            and gui.MainUI.AbilityContainer.Punch:FindFirstChild("Charges")
        return (charges and tonumber(charges.Text)) or 0
    end

    RunService.RenderStepped:Connect(function()
        local root = Util.GetRoot()
        if not root then return end
        local now = tick()

        -- Auto Block
        if autoBlock then
            local current = {}
            for _, plr in ipairs(Util.OtherPlayers()) do
                local char = plr.Character
                if char then
                    local hum  = char:FindFirstChildOfClass("Humanoid")
                    local r    = char:FindFirstChild("HumanoidRootPart")
                    if hum and r and (r.Position - root.Position).Magnitude <= blockRage then
                        local anim = hum:FindFirstChildOfClass("Animator")
                        if anim then
                            for _, track in ipairs(anim:GetPlayingAnimationTracks()) do
                                local id = tostring(track.Animation and track.Animation.AnimationId or ""):match("%d+")
                                if id and table.find(BLOCK_TRIGGER_ANIMS, id) then
                                    current[id] = true
                                    if not blockPrev[id] and isFacingLocal(root, r) then
                                        local delay = KILLER_DELAYS[char.Name:lower()] or 0
                                        task.delay(delay, function()
                                            if autoBlock and (tick() - lastBlockTime) > BLOCK_CD then
                                                if blockMode == "Block" then
                                                    Util.FireAbility(buffer.fromstring("\3\5\0\0\0Block"))
                                                else
                                                    Util.FireAbility(buffer.fromstring("\3\5\0\0\0Clone"))
                                                end
                                                lastBlockTime = tick()
                                            end
                                        end)
                                    end
                                end
                            end
                        end
                    end
                end
            end
            blockPrev = current
        else
            blockPrev = {}
        end

        -- Auto Punch
        if autoPunch then
            local charges = getPunchCharges()
            if charges >= 1 then
                local kr = getNearestKillerInRange()
                if kr and (kr.Position - root.Position).Magnitude <= math.min(blockRage, 10) then
                    if (now - lastPunchTime) > PUNCH_CD then
                        Util.FireAbility(buffer.fromstring("\3\5\0\0\0Punch"))
                        lastPunchTime = now
                    end
                end
            end
        end

        -- Punch Aim
        if autoPunchAim then
            local hum = Util.GetHumanoid()
            local anim = hum and hum:FindFirstChildOfClass("Animator")
            if anim then
                for _, track in ipairs(anim:GetPlayingAnimationTracks()) do
                    local id = tostring(track.Animation and track.Animation.AnimationId or ""):match("%d+")
                    if id and table.find(PUNCH_ANIM_IDS, id) then
                        local last = lastAimTrigger[track]
                        if not last or (now - last) > AIM_CD then
                            local tp = 0
                            pcall(function() tp = track.TimePosition end)
                            if tp <= 0.1 then
                                lastAimTrigger[track] = now
                                local kr = getNearestKillerInRange()
                                if kr then
                                    local predicted = kr.Position + (kr.CFrame.LookVector * 4)
                                    task.spawn(function()
                                        local s = now
                                        while tick() - s < AIM_WINDOW do
                                            local myRoot = Util.GetRoot()
                                            if myRoot and myRoot.Parent and kr and kr.Parent then
                                                local lp = Vector3.new(predicted.X, myRoot.Position.Y, predicted.Z)
                                                myRoot.CFrame = myRoot.CFrame:Lerp(CFrame.lookAt(myRoot.Position, lp), 0.7)
                                            end
                                            task.wait()
                                        end
                                    end)
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    LocalPlayer.CharacterAdded:Connect(function()
        blockPrev     = {}
        lastAimTrigger = {}
        lastBlockTime = 0
        lastPunchTime = 0
    end)

    Tab.Combat:CreateToggle({ Name = "Auto Block",    Flag = "AutoBlock",   CurrentValue = false, Callback = function(v) autoBlock    = v end })
    Tab.Combat:CreateDropdown({ Name = "Mode", Options = {"Block","Clone"}, CurrentOption = "Block", Flag = "BlockMode",
        Callback = function(opt) blockMode = typeof(opt)=="table" and opt[1] or opt end })
    Tab.Combat:CreateInput({ Name = "Rage", Flag = "BlockRage", PlaceholderText = "20", RemoveTextAfterFocusLost = false,
        Callback = function(t) local n=tonumber(t); if n then blockRage=n end end })
    Tab.Combat:CreateToggle({ Name = "Facing Check",  Flag = "BlockFacing", CurrentValue = true,  Callback = function(v) facingCheck  = v end })
    Tab.Combat:CreateToggle({ Name = "Auto Punch",    Flag = "AutoPunch",   CurrentValue = false, Callback = function(v) autoPunch    = v end })
    Tab.Combat:CreateToggle({ Name = "Punch Aim",     Flag = "PunchAim",    CurrentValue = false, Callback = function(v) autoPunchAim = v end })
end

-- ============================================================
--  COMBAT TAB  —  Auto Parry
-- ============================================================
do
    Tab.Combat:CreateSection("Auto Parry")

    local autoParry    = false
    local parryRage    = 19
    local PARRY_CD     = 5
    local SPAM_TIME    = 3
    local cooldowns    = {}

    local BUF_RAGE   = buffer.fromstring("\3\10\0\0\0RagingPace")
    local BUF_404    = buffer.fromstring("\3\8\0\0\0" .. "404Error")

    local PARRY_ANIMS = {
        ["87259391926321"]=true, ["138040001965654"]=true, ["136007065400978"]=true,
        ["108911997126897"]=true,["129843313690921"]=true, ["81905101227053"]=true,
        ["113936304594883"]=true,["140703210927645"]=true, ["86709774283672"]=true,
        ["119850211147676"]=true,["108807732150251"]=true, ["111270184603402"]=true,
        ["86096387000557"]=true, ["99422325754526"]=true,  ["82137285150006"]=true,
        ["78440860685556"]=true, ["138008678294576"]=true, ["108137703081583"]=true,
        ["111351142668768"]=true,["97020933136241"]=true,  ["80109359274646"]=true,
        ["91876712939436"]=true, ["80872238342472"]=true,  ["129228295705213"]=true,
        ["118647044497447"]=true,["116618003477002"]=true, ["122503338277352"]=true,
        ["131696603025265"]=true,["119462383658044"]=true, ["77448521277146"]=true,
        ["108773914369470"]=true,["98031287364865"]=true,  ["121255898612475"]=true,
        ["110400453990786"]=true,["105614318732282"]=true,
    }

    local function isParryAnim(track)
        local id = tostring(track.Animation.AnimationId):match("%d+")
        return id and PARRY_ANIMS[id]
    end

    RunService.Heartbeat:Connect(function()
        if not autoParry then return end
        local myChar = LocalPlayer.Character
        local myHRP  = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myHRP then return end

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
                local hrp  = plr.Character.HumanoidRootPart
                local dist = (hrp.Position - myHRP.Position).Magnitude
                if dist <= parryRage and (not cooldowns[plr] or tick() - cooldowns[plr] >= PARRY_CD) then
                    local hum = plr.Character:FindFirstChildOfClass("Humanoid")
                    if hum then
                        for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
                            if isParryAnim(track) then
                                cooldowns[plr] = tick()
                                task.spawn(function()
                                    Util.FireAbility(BUF_RAGE)
                                    task.wait(0.15)
                                    local t = tick()
                                    while tick() - t < SPAM_TIME do
                                        Util.FireAbility(BUF_404)
                                        task.wait(0.05)
                                    end
                                end)
                                break
                            end
                        end
                    end
                end
            end
        end
    end)

    Tab.Combat:CreateToggle({ Name = "Auto Parry", Flag = "AutoParry", CurrentValue = false, Callback = function(v) autoParry = v end })
    Tab.Combat:CreateInput({ Name = "Rage", Flag = "ParryRage", PlaceholderText = "19", RemoveTextAfterFocusLost = false,
        Callback = function(t)
            local n = tonumber(t)
            if n then parryRage = math.clamp(n, 5, 50) end
        end,
    })
end

-- ============================================================
--  COMBAT TAB  —  QTE Nosferatu
-- ============================================================
do
    Tab.Combat:CreateSection("QTE Nosferatu")

    local autoQTE  = false
    local qteDelay = 0.05

    task.spawn(function()
        while task.wait(0.3) do
            if autoQTE then
                task.spawn(function()
                    while autoQTE do
                        pcall(function()
                            local tempUI = LocalPlayer.PlayerGui:FindFirstChild("TemporaryUI")
                            if not tempUI then return end
                            local qte = tempUI:FindFirstChild("QTE")
                            if not qte then return end
                            local btn = qte:FindFirstChild("ActiveButton")
                            if not btn then return end
                            for _, conn in ipairs(getconnections(btn.MouseButton1Down)) do
                                pcall(conn.Function)
                            end
                        end)
                        task.wait(qteDelay)
                    end
                end)
                repeat task.wait() until not autoQTE
            end
        end
    end)

    Tab.Combat:CreateToggle({ Name = "Auto QTE (Mobile)", Flag = "AutoQTE", CurrentValue = false, Callback = function(v) autoQTE = v end })
    Tab.Combat:CreateInput({ Name = "QTE Delay", Flag = "QTEDelay", PlaceholderText = "0.05", RemoveTextAfterFocusLost = false,
        Callback = function(t)
            local n = tonumber(t)
            if n and n >= 0 and n <= 10 then qteDelay = n end
        end,
    })
end

-- ============================================================
--  SUPPORT TAB
-- ============================================================
do
    Tab.Support:CreateSection("Links")

    Tab.Support:CreateParagraph({
        Title   = "Discord",
        Content = "Join the server to report bugs or get support.",
    })
    Tab.Support:CreateButton({
        Name = "Copy Discord Link",
        Callback = function()
            setclipboard("https://discord.gg/jtxyfUyJQY")
            Rayfield:Notify({ Title = "Copied!", Content = "Discord link copied to clipboard.", Duration = 3 })
        end,
    })

    Tab.Support:CreateParagraph({
        Title   = "YouTube",
        Content = "Subscribe for updates and tutorials.",
    })
    Tab.Support:CreateButton({
        Name = "Copy YouTube Link",
        Callback = function()
            setclipboard("https://www.youtube.com/@Wscript1955")
            Rayfield:Notify({ Title = "Copied!", Content = "YouTube link copied to clipboard.", Duration = 3 })
        end,
    })

    Tab.Support:CreateSection("Config")
    Tab.Support:CreateButton({
        Name = "Save Configuration",
        Callback = function()
            Rayfield:SaveConfiguration()
            Rayfield:Notify({ Title = "Saved", Content = "Configuration saved successfully.", Duration = 3 })
        end,
    })
end

-- ============================================================
--  LOAD SAVED CONFIGURATION
-- ============================================================
Rayfield:LoadConfiguration()
