repeat task.wait() until game:IsLoaded()

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/ATGFAIL/ATGHub/Addons/autosave.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/ATGFAIL/ATGHub/Addons/config.lua"))()
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Window = Fluent:CreateWindow({
    Title = "ATG Hub Beta",
    SubTitle = "by ATGFAIL",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true, -- The blur may be detectable, setting this to false disables blur entirely
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl -- Used when theres no MinimizeKeybind
})

--Fluent provides Lucide Icons https://lucide.dev/icons/ for the tabs, icons are optional
local Tabs = {
    Main = Window:AddTab({ Title = "Main", Icon = "repeat" }),
    Players = Window:AddTab({ Title = "Humanoid", Icon = "users" }),
    Teleport = Window:AddTab({ Title = "Teleport", Icon = "plane" }),
    ESP = Window:AddTab({ Title = "ESP", Icon = "locate"}),
    Server = Window:AddTab({ Title = "Server", Icon = "server"}),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

local Options = Fluent.Options
-- -----------------------
-- Player Info Paragraph (Status Panel)
-- -----------------------

-- ประกาศตัวแปรที่ใช้
local startTime = tick() -- เวลาเริ่มสคริปต์
local infoParagraph = nil
local char = nil
local hum = nil
local content = ""

-- สร้าง Paragraph
infoParagraph = Tabs.Main:AddParagraph({
    Title = "Player Info",
    Content = "Loading player info..."
})

-- ฟังก์ชันช่วยเติมเลขให้เป็น 2 หลัก (เช่น 4 -> "04")
local function pad2(n)
    return string.format("%02d", tonumber(n) or 0)
end

-- ฟังก์ชันอัพเดทข้อมูล
local function updateInfo()
    -- รับตัวละคร / humanoid (ถ้ามี)
    char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    hum = char and char:FindFirstChildWhichIsA("Humanoid")

    -- เวลาที่เล่น (วินาที, ปัดลง)
    local playedSeconds = math.floor(tick() - startTime)

    -- แยกชั่วโมง นาที วินาที
    local hours = math.floor(playedSeconds / 3600)
    local minutes = math.floor((playedSeconds % 3600) / 60)
    local seconds = playedSeconds % 60

    -- วันที่ปัจจุบัน รูปแบบ DD/MM/YYYY
    local dateStr = os.date("%d/%m/%Y")

    -- สร้างข้อความที่จะโชว์ (เอา Health/WalkSpeed/JumpPower ออกแล้ว)
    content = string.format([[
Name: %s (@%s)
Date : %s

Played Time : %s : %s : %s
]],
        LocalPlayer.DisplayName or LocalPlayer.Name,
        LocalPlayer.Name or "Unknown",
        dateStr,
        pad2(hours),
        pad2(minutes),
        pad2(seconds)
    )

    -- อัปเดต Paragraph ใน UI
    pcall(function()
        infoParagraph:SetDesc(content)
    end)
end

-- loop update ทุกๆ 1 วิ
task.spawn(function()
    while true do
        if Fluent.Unloaded then break end
        pcall(updateInfo)
        task.wait(1)
    end
end)

-- Improved Auto Warp to player's Animals (integrated with Fluent UI)
-- Usage: วางส่วนนี้ต่อท้ายที่สร้าง Window, Tabs ตามที่มีอยู่แล้ว
-- วางทับโค้ดเดิมทั้งหมดที่เกี่ยวกับ AutoWarp/AutoFire

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local plotsFolder = workspace:WaitForChild("Map"):WaitForChild("Plots")

local FluentRef = Fluent -- cache external object
local OptionsRef = Options -- cache Options table (assumes existing in environment)

-- CONFIG (ปรับค่าได้)
local PerWarpDelay = 0.5   -- เวลาเว้นระหว่างการวาปแต่ละตัว (วินาที)
local CycleDelay = 3       -- เวลาเว้นหลังจบรอบทั้งหมด (วินาที)
local MaxWarpsPerCycle = 40 -- จำกัดจำนวนวาปต่อรอบ (เพื่อหลีกเลี่ยงการกระตุกถ้าสัตว์เยอะมาก)

-- UI (สมมติ Tabs.Main / Options มีอยู่แล้ว)
local AutoWarpToggle = Tabs.Main:AddToggle("AutoWarpAnimals", { Title = "Auto Wheat", Default = false })

-- Internal state
local warpLoopRunning = false
local cachedTargets = {}      -- { {part=BasePart, name=string, plot=string}, ... }
local lastTargetsUpdate = 0
local TARGETS_REFRESH_INTERVAL = 5 -- วินาที: update cache ทุก ๆ X วินาที (ลดการสแกนบ่อย)
local plotConnections = {}    -- เก็บ connections ถ้าจะใช้อีเวนต์ (optional)
local remoteFolder = ReplicatedStorage:WaitForChild("Remote_Events")
local buyTreatRemote = remoteFolder:WaitForChild("Buy_Treat")

-- Helper: find a usable BasePart (fast, non-recursive first, fallback to shallow search)
local function findModelPart(model)
    if not model or not model:IsA("Model") then return nil end

    -- common primaries
    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then return hrp end
    local head = model:FindFirstChild("Head")
    if head and head:IsA("BasePart") then return head end

    -- shallow search through direct children (faster than GetDescendants when models are large)
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") then return child end
    end

    -- final fallback: a single GetDescendants call (rare)
    for _, v in ipairs(model:GetDescendants()) do
        if v:IsA("BasePart") then return v end
    end

    return nil
end

-- Update cachedTargets (cheap, called periodically)
local function updateCachedTargets()
    local now = tick()
    if now - lastTargetsUpdate < TARGETS_REFRESH_INTERVAL then
        return -- ใช้ cache ถ้าเพิ่งอัพเดตไปไม่กี่วินาที
    end
    lastTargetsUpdate = now

    local newTargets = {}

    -- iterate plots (this is the main scan; made infrequent by TARGETS_REFRESH_INTERVAL)
    for _, plotModel in ipairs(plotsFolder:GetChildren()) do
        if plotModel:IsA("Model") and plotModel:FindFirstChild("Info") then
            local info = plotModel.Info
            local owner = info:FindFirstChild("Owner")
            if owner and owner:IsA("StringValue") and owner.Value == player.Name then
                local animalsFolder = plotModel:FindFirstChild("Animals")
                if animalsFolder then
                    -- iterate immediate children only (expect animals as models)
                    for _, animalModel in ipairs(animalsFolder:GetChildren()) do
                        if animalModel:IsA("Model") then
                            local part = findModelPart(animalModel)
                            if part then
                                table.insert(newTargets, { part = part, name = animalModel.Name, plot = plotModel.Name })
                            end
                        end
                    end
                end
            end
        end
    end

    cachedTargets = newTargets
end

-- Teleport function (safe, pcall)
local function teleportPlayerToPart(part)
    if not part or not part:IsA("BasePart") then return false, "invalid part" end
    local character = player.Character or player.CharacterAdded:Wait()
    if not character then return false, "no character" end

    local hrp = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChildWhichIsA("BasePart")
    if not hrp then return false, "no hrp" end

    local ok, err = pcall(function()
        -- using CFrame assignment once per teleport (cheap)
        hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0)
    end)
    return ok, err
end

-- Start warp loop (optimized)
local function startWarpLoop()
    if warpLoopRunning then return end
    warpLoopRunning = true

    task.spawn(function()
        while warpLoopRunning and not (FluentRef and FluentRef.Unloaded) do
            -- Ensure targets cache is fresh
            updateCachedTargets()

            local targets = cachedTargets
            if #targets == 0 then
                -- ถ้าไม่มีเป้าหมายเลย ให้รอเป็น cycle
                local totalWait = 0
                while warpLoopRunning and totalWait < CycleDelay do
                    task.wait(0.25)
                    totalWait = totalWait + 0.25
                end
            else
                -- limit per cycle เพื่อหลีกเลี่ยงการทำหนักถ้ามีเป้าจำนวนมาก
                local limit = math.min(#targets, MaxWarpsPerCycle)
                for i = 1, limit do
                    if not warpLoopRunning or (FluentRef and FluentRef.Unloaded) then break end

                    local t = targets[i]
                    if t and t.part then
                        local ok, err = teleportPlayerToPart(t.part)
                        -- optional: can log failed warps less frequently to avoid spam
                        if not ok then
                            --print(("Warp failed to %s in %s : %s"):format(t.name, t.plot, tostring(err)))
                        end
                    end

                    -- wait between warps (single call, lighter than many small waits)
                    if PerWarpDelay > 0 then
                        local waited = 0
                        -- wait in small slices to be responsive to stop commands, but keep slices coarse
                        while warpLoopRunning and waited < PerWarpDelay do
                            task.wait(0.1)
                            waited = waited + 0.1
                        end
                    end
                end

                -- after finishing one pass (or limited pass), recalc/update targets next iteration
                local waited = 0
                while warpLoopRunning and waited < CycleDelay do
                    task.wait(0.25)
                    waited = waited + 0.25
                end
            end
        end

        warpLoopRunning = false
    end)
end

local function stopWarpLoop()
    warpLoopRunning = false
end

-- Connect UI toggle
AutoWarpToggle:OnChanged(function()
    local enabled = OptionsRef and OptionsRef.AutoWarpAnimals and OptionsRef.AutoWarpAnimals.Value or false
    if enabled then
        startWarpLoop()
        if FluentRef then FluentRef:Notify({ Title = "Auto Warp", Content = "เริ่มวาปไปที่ Animals ของคุณ", Duration = 4 }) end
    else
        stopWarpLoop()
        if FluentRef then FluentRef:Notify({ Title = "Auto Warp", Content = "หยุดการวาปแล้ว", Duration = 4 }) end
    end
end)

-- start if option already true
if OptionsRef and OptionsRef.AutoWarpAnimals and OptionsRef.AutoWarpAnimals.Value then
    startWarpLoop()
end

-- ===== Auto Buy Treat (ปรับให้เบา) =====
local FIRE_DELAY = 0.5 -- ดีเลย์ระหว่างการยิง

local MultiDropdown = Tabs.Main:AddDropdown("Treats", {
    Title = "Select Treat",
    Description = "เลือกได้หลายค่า (Multi)",
    Values = {"Apple", "Banana", "Carrot", "Corn", "Pepper","Cherries"},
    Multi = true,
    Default = {"Apple"}
})

local AutoToggle = Tabs.Main:AddToggle("AutoFireToggle", { Title = "Auto Buy Treat", Default = false })
OptionsRef.AutoFireToggle = OptionsRef.AutoFireToggle or {} -- guard
if OptionsRef.AutoFireToggle.SetValue then
    OptionsRef.AutoFireToggle:SetValue(false)
end

local autoFireRunning = false

MultiDropdown:OnChanged(function(Value)
    -- print selected keys for debug (lightweight)
    local sel = {}
    for k, v in pairs(Value) do
        if v then table.insert(sel, k) end
    end
    -- ไม่พิมพ์ทุกครั้งเพื่อลด overhead; เอาไว้ debug เท่านั้น
    -- print("Selected treats:", table.concat(sel, ", "))
end)

AutoToggle:OnChanged(function()
    local enabled = OptionsRef and OptionsRef.AutoFireToggle and OptionsRef.AutoFireToggle.Value
    if enabled and not autoFireRunning then
        autoFireRunning = true
        task.spawn(function()
            while OptionsRef and OptionsRef.AutoFireToggle and OptionsRef.AutoFireToggle.Value do
                -- read selection map (expected as { ["Apple"]=true, ... })
                local selMap = OptionsRef.Treats and OptionsRef.Treats.Value or {}
                -- build list quickly
                local selList = {}
                for name, state in pairs(selMap) do
                    if state then table.insert(selList, name) end
                end

                if #selList == 0 then
                    task.wait(FIRE_DELAY)
                else
                    for _, itemName in ipairs(selList) do
                        if not (OptionsRef and OptionsRef.AutoFireToggle and OptionsRef.AutoFireToggle.Value) then break end
                        pcall(function()
                            buyTreatRemote:FireServer(itemName)
                        end)
                        task.wait(FIRE_DELAY)
                    end
                end
            end
            autoFireRunning = false
        end)
    end
end)

-- ============================
-- Speed & Jump (ปรับปรุง)
-- - ลดความถี่การเช็ค (throttled)
-- - เก็บค่า original ของ Humanoid เพื่อคืนค่าเมื่อปิด toggle
-- - เพิ่ม Toggle เพื่อเปิด/ปิด Walk และ Jump
-- ============================
local Section = Tabs.Players:AddSection("Speed & Jump")
-- wait for LocalPlayer if not ready (safe in LocalScript)
if not LocalPlayer or typeof(LocalPlayer) == "Instance" and LocalPlayer.ClassName == "" then
    LocalPlayer = Players.LocalPlayer
end

do
    -- config
    local enforcementRate = 0.1 -- วินาที (0.1 = 10 ครั้ง/วินาที) -> ตอบสนองดีขึ้น แต่ไม่เกินไป
    local WalkMin, WalkMax = 8, 200
    local JumpMin, JumpMax = 10, 300

    local DesiredWalkSpeed = 16
    local DesiredJumpPower = 50

    local WalkEnabled = false
    local JumpEnabled = false

    -- เก็บค่าเดิมของ humanoid (weak table ตาม instance)
    local originalValues = setmetatable({}, { __mode = "k" })

    local currentHumanoid = nil
    local heartbeatConn = nil
    local lastApplyTick = 0

    local function clamp(v, a, b)
        if v < a then return a end
        if v > b then return b end
        return v
    end

    local function findHumanoid()
        if not Players.LocalPlayer then return nil end
        local char = Players.LocalPlayer.Character
        if not char then return nil end
        return char:FindFirstChildWhichIsA("Humanoid")
    end

    local function saveOriginal(hum)
        if not hum then return end
        if not originalValues[hum] then
            local ok, ws, jp, usejp = pcall(function()
                return hum.WalkSpeed, hum.JumpPower, hum.UseJumpPower
            end)
            if ok then
                originalValues[hum] = { WalkSpeed = ws or 16, JumpPower = jp or 50, UseJumpPower = usejp }
            else
                originalValues[hum] = { WalkSpeed = 16, JumpPower = 50, UseJumpPower = true }
            end
        end
    end

    local function restoreOriginal(hum)
        if not hum then return end
        local orig = originalValues[hum]
        if orig then
            pcall(function()
                if orig.UseJumpPower ~= nil then
                    hum.UseJumpPower = orig.UseJumpPower
                end
                hum.WalkSpeed = orig.WalkSpeed or 16
                hum.JumpPower = orig.JumpPower or 50
            end)
            originalValues[hum] = nil
        end
    end

    local function applyToHumanoid(hum)
        if not hum then return end
        saveOriginal(hum)

        -- Walk
        if WalkEnabled then
            local desired = clamp(math.floor(DesiredWalkSpeed + 0.5), WalkMin, WalkMax)
            if hum.WalkSpeed ~= desired then
                pcall(function() hum.WalkSpeed = desired end)
            end
        end

        -- Jump: ensure UseJumpPower true, then set JumpPower
        if JumpEnabled then
            pcall(function()
                -- set UseJumpPower true to ensure JumpPower is respected
                if hum.UseJumpPower ~= true then
                    hum.UseJumpPower = true
                end
            end)

            local desiredJ = clamp(math.floor(DesiredJumpPower + 0.5), JumpMin, JumpMax)
            if hum.JumpPower ~= desiredJ then
                pcall(function() hum.JumpPower = desiredJ end)
            end
        end
    end

    local function startEnforcement()
        if heartbeatConn then return end
        local acc = 0
        heartbeatConn = RunService.Heartbeat:Connect(function(dt)
            acc = acc + dt
            if acc < enforcementRate then return end
            acc = 0

            local hum = findHumanoid()
            if hum then
                currentHumanoid = hum
                -- apply only when enabled; if both disabled, avoid applying
                if WalkEnabled or JumpEnabled then
                    applyToHumanoid(hum)
                end
            else
                -- no humanoid: clear currentHumanoid
                currentHumanoid = nil
            end
        end)
    end

    local function stopEnforcement()
        if heartbeatConn then
            heartbeatConn:Disconnect()
            heartbeatConn = nil
        end
    end

    -- Toggle handlers
    local function setWalkEnabled(v)
        WalkEnabled = not not v
        if WalkEnabled then
            -- immediately apply
            local hum = findHumanoid()
            if hum then
                applyToHumanoid(hum)
            end
            startEnforcement()
        else
            -- restore walk value on current humanoid if we recorded it
            if currentHumanoid then
                -- only restore WalkSpeed (not touching Jump here)
                local orig = originalValues[currentHumanoid]
                if orig and orig.WalkSpeed ~= nil then
                    pcall(function() currentHumanoid.WalkSpeed = orig.WalkSpeed end)
                end
            end

            -- if both disabled, we can stop enforcement and restore jump if needed
            if not JumpEnabled then
                if currentHumanoid then
                    restoreOriginal(currentHumanoid)
                end
                stopEnforcement()
            end
        end
    end

    local function setJumpEnabled(v)
        JumpEnabled = not not v
        if JumpEnabled then
            local hum = findHumanoid()
            if hum then
                applyToHumanoid(hum)
            end
            startEnforcement()
        else
            if currentHumanoid then
                -- restore JumpPower and UseJumpPower
                local orig = originalValues[currentHumanoid]
                if orig and (orig.JumpPower ~= nil or orig.UseJumpPower ~= nil) then
                    pcall(function()
                        if orig.UseJumpPower ~= nil then
                            currentHumanoid.UseJumpPower = orig.UseJumpPower
                        end
                        if orig.JumpPower ~= nil then
                            currentHumanoid.JumpPower = orig.JumpPower
                        end
                    end)
                end
            end

            if not WalkEnabled then
                if currentHumanoid then
                    restoreOriginal(currentHumanoid)
                end
                stopEnforcement()
            end
        end
    end

    -- sliders callbacks
    local function setWalkSpeed(v)
        DesiredWalkSpeed = clamp(v, WalkMin, WalkMax)
        if WalkEnabled then
            local hum = findHumanoid()
            if hum then applyToHumanoid(hum) end
            startEnforcement()
        end
    end

    local function setJumpPower(v)
        DesiredJumpPower = clamp(v, JumpMin, JumpMax)
        if JumpEnabled then
            local hum = findHumanoid()
            if hum then applyToHumanoid(hum) end
            startEnforcement()
        end
    end

    -- CharacterAdded handling to apply as soon as possible
    if Players.LocalPlayer then
        Players.LocalPlayer.CharacterAdded:Connect(function(char)
            -- small wait for humanoid to exist
            local hum = nil
            for i = 1, 20 do
                hum = char:FindFirstChildWhichIsA("Humanoid")
                if hum then break end
                task.wait(0.05)
            end
            if hum and (WalkEnabled or JumpEnabled) then
                applyToHumanoid(hum)
                startEnforcement()
            end
        end)
    end

    -- UI
    local speedSlider = Section:AddSlider("WalkSpeedSlider", {
        Title = "WalkSpeed",
        Default = DesiredWalkSpeed, Min = WalkMin, Max = WalkMax, Rounding = 0,
        Callback = function(Value) setWalkSpeed(Value) end
    })
    speedSlider:OnChanged(setWalkSpeed)

    local jumpSlider = Section:AddSlider("JumpPowerSlider", {
        Title = "JumpPower",
        Default = DesiredJumpPower, Min = JumpMin, Max = JumpMax, Rounding = 0,
        Callback = function(Value) setJumpPower(Value) end
    })
    jumpSlider:OnChanged(setJumpPower)

    local walkToggle = Section:AddToggle("EnableWalkToggle", {
        Title = "Enable Walk",
        Description = "เปิด/ปิดการบังคับ WalkSpeed",
        Default = WalkEnabled,
        Callback = function(value) setWalkEnabled(value) end
    })
    walkToggle:OnChanged(setWalkEnabled)

    local jumpToggle = Section:AddToggle("EnableJumpToggle", {
        Title = "Enable Jump",
        Description = "เปิด/ปิดการบังคับ JumpPower",
        Default = JumpEnabled,
        Callback = function(value) setJumpEnabled(value) end
    })
    jumpToggle:OnChanged(setJumpEnabled)

    Section:AddButton({
        Title = "Reset to defaults",
        Description = "คืนค่า Walk/Jump ไปค่าเริ่มต้น (16, 50)",
        Callback = function()
            DesiredWalkSpeed = 16
            DesiredJumpPower = 50
            speedSlider:SetValue(DesiredWalkSpeed)
            jumpSlider:SetValue(DesiredJumpPower)
            if WalkEnabled or JumpEnabled then
                local hum = findHumanoid()
                if hum then applyToHumanoid(hum) end
            end
        end
    })

    -- start enforcement if either is enabled initially
    if WalkEnabled or JumpEnabled then startEnforcement() end
end

-- -----------------------
-- Setup
-- -----------------------
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer

-- state table
local state = {
    flyEnabled = false,
    noclipEnabled = false,
    espEnabled = false,
    espTable = {}
}

-- ใช้ Fluent:Notify แทน
local function notify(title, content, duration)
    Fluent:Notify({
        Title = title,
        Content = content,
        Duration = duration or 3
    })
end

-- Fly & Noclip (improved, stable)
do
    state = state or {}
    state.flyEnabled = state.flyEnabled or false
    state.noclipEnabled = state.noclipEnabled or false

    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local bindName = "ATG_FlyStep"
    local fly = {
        bv = nil,
        bg = nil,
        speed = 60,           -- default speed (can be adjusted by slider)
        smoothing = 0.35,     -- lerp for velocity smoothing
        bound = false
    }
    local savedCanCollide = {} -- map part -> bool (to restore when disabling noclip)

    local function getHRP(timeout)
        local char = LocalPlayer.Character
        if not char then
            char = LocalPlayer.CharacterAdded:Wait()
        end
        timeout = timeout or 5
        local ok, hrp = pcall(function() return char:WaitForChild("HumanoidRootPart", timeout) end)
        if ok and hrp then return hrp end
        return nil
    end

    local function createForces(hrp)
        if not hrp or not hrp.Parent then return end
        if not fly.bv then
            fly.bv = Instance.new("BodyVelocity")
            fly.bv.Name = "ATG_Fly_BV"
            fly.bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            fly.bv.Velocity = Vector3.new(0,0,0)
            fly.bv.P = 1250
            fly.bv.Parent = hrp
        else
            fly.bv.Parent = hrp
        end

        if not fly.bg then
            fly.bg = Instance.new("BodyGyro")
            fly.bg.Name = "ATG_Fly_BG"
            fly.bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
            fly.bg.CFrame = hrp.CFrame
            fly.bg.Parent = hrp
        else
            fly.bg.Parent = hrp
        end
    end

    local function destroyForces()
        if fly.bv then
            pcall(function() fly.bv:Destroy() end)
            fly.bv = nil
        end
        if fly.bg then
            pcall(function() fly.bg:Destroy() end)
            fly.bg = nil
        end
    end

    local function bindFlyStep()
        if fly.bound then return end
        fly.bound = true
        RunService:BindToRenderStep(bindName, Enum.RenderPriority.Character.Value + 1, function()
            if Fluent and Fluent.Unloaded then
                -- cleanup if UI unloaded
                destroyForces()
                if fly.bound then
                    pcall(function() RunService:UnbindFromRenderStep(bindName) end)
                    fly.bound = false
                end
                return
            end

            if not state.flyEnabled then return end
            local char = LocalPlayer.Character
            if not char then return end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp or not fly.bv or not fly.bg then return end

            local cam = workspace.CurrentCamera
            if not cam then return end
            local camCF = cam.CFrame

            local moveDir = Vector3.new(0,0,0)
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir += camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir -= camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir -= camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir += camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir += Vector3.new(0,1,0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir -= Vector3.new(0,1,0) end

            local targetVel = Vector3.new(0,0,0)
            if moveDir.Magnitude > 0 then
                targetVel = moveDir.Unit * fly.speed
            end

            -- smooth the velocity so it's not jittery
            fly.bv.Velocity = fly.bv.Velocity:Lerp(targetVel, fly.smoothing)
            -- make gyro follow camera for natural facing
            fly.bg.CFrame = camCF
        end)
    end

    local function unbindFlyStep()
        if fly.bound then
            pcall(function() RunService:UnbindFromRenderStep(bindName) end)
            fly.bound = false
        end
    end

    -- enableFly: create forces + bind loop
    local function enableFly(enable)
        state.flyEnabled = enable and true or false

        if enable then
            local hrp = getHRP(5)
            if not hrp then
                notify("Fly", "ไม่พบ HumanoidRootPart", 3)
                state.flyEnabled = false
                return
            end
            createForces(hrp)
            bindFlyStep()
            notify("Fly", "Fly enabled", 3)
        else
            destroyForces()
            unbindFlyStep()
            notify("Fly", "Fly disabled", 2)
        end
    end

    -- ✅ Noclip เวอร์ชันอัปเกรด (Smooth + Safe)
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")

local state = state or { noclipEnabled = false }
local savedCanCollide = {}
local noclipConn = nil

local function setNoclip(enable)
    if enable == state.noclipEnabled then return end -- ไม่ต้องทำซ้ำ
    state.noclipEnabled = enable

    local char = LocalPlayer.Character
    if not char or not char:FindFirstChildOfClass("Humanoid") then
        warn("[Noclip] Character not ready")
        return
    end

    if enable then
        -- 🔥 เปิด Noclip
        savedCanCollide = {}

        -- ปิดการชนทุกส่วนของตัวละคร
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                savedCanCollide[part] = part.CanCollide
                part.CanCollide = false
            end
        end

        -- ทำให้ Noclip ต่อเนื่องทุกเฟรม (กันหลุด)
        noclipConn = RunService.Stepped:Connect(function()
            local c = LocalPlayer.Character
            if c then
                for _, part in ipairs(c:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end
        end)

        notify("Noclip", "✅ Enabled", 2.5)

    else
        -- 🧊 ปิด Noclip
        if noclipConn then
            noclipConn:Disconnect()
            noclipConn = nil
        end

        for part, val in pairs(savedCanCollide) do
            if part and part.Parent then
                part.CanCollide = val
            end
        end
        savedCanCollide = {}
        notify("Noclip", "❌ Disabled", 2)
    end
end

-- ♻️ Auto reapply on respawn
LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.2)
    if state.noclipEnabled then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
        notify("Noclip", "Re-enabled after respawn", 2)
    end
end)


    -- Re-apply noclip and fly on respawn if toggled
    LocalPlayer.CharacterAdded:Connect(function(char)
        task.wait(0.15) -- wait parts spawn
        if state.noclipEnabled then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    pcall(function() part.CanCollide = false end)
                end
            end
        end
        if state.flyEnabled then
            -- recreate forces on new HRP
            local hrp = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5)
            if hrp then
                createForces(hrp)
            end
            bindFlyStep()
        end
    end)

    -- UI: toggle, slider, keybind
    local flyToggle = Tabs.Players:AddToggle("FlyToggle", { Title = "Fly", Default = false })
    flyToggle:OnChanged(function(v) enableFly(v) end)

    local flySpeedSlider = Tabs.Players:AddSlider("FlySpeedSlider", {
        Title = "Fly Speed",
        Description = "ปรับความเร็วการบิน",
        Default = fly.speed,
        Min = 10,
        Max = 3500,
        Rounding = 0,
        Callback = function(v) fly.speed = v end
    })
    flySpeedSlider:SetValue(fly.speed)

    local noclipToggle = Tabs.Players:AddToggle("NoclipToggle", { Title = "Noclip", Default = false })
    noclipToggle:OnChanged(function(v) setNoclip(v) end)

    Tabs.Players:AddKeybind("FlyKey", {
        Title = "Fly Key (Toggle)",
        Mode = "Toggle",
        Default = "None",
        Callback = function(val)
            enableFly(val)
            -- sync UI toggle
            pcall(function() flyToggle:SetValue(val) end)
        end
    })

    -- cleanup if Fluent unloads (safety)
    task.spawn(function()
        while true do
            if Fluent and Fluent.Unloaded then
                -- force disable
                enableFly(false)
                setNoclip(false)
                break
            end
            task.wait(0.5)
        end
    end)
end


-- Improved ESP (no size/distance sliders)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- state init (keep previous values if exist)
state = state or {}
state.espTable = state.espTable or {}
state.espEnabled = state.espEnabled or false
state.espColor = state.espColor or Color3.fromRGB(255, 50, 50)
state.showName = (state.showName == nil) and true or state.showName
state.showHealth = (state.showHealth == nil) and true or state.showHealth
state.showDistance = (state.showDistance == nil) and true or state.showDistance

local function getHRP(pl)
    if not pl or not pl.Character then return nil end
    return pl.Character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(char)
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

local function createESPForPlayer(p)
    if state.espTable[p] then return end
    local info = { billboard = nil, updateConn = nil, charConn = nil }
    state.espTable[p] = info

    local function attachToCharacter(char)
        if not state.espEnabled then return end
        if not char or not char.Parent then return end
        local head = char:FindFirstChild("Head")
        if not head then return end

        -- cleanup old if exists
        pcall(function()
            if info.updateConn then info.updateConn:Disconnect() info.updateConn = nil end
            if info.billboard then info.billboard:Destroy() info.billboard = nil end
        end)

        -- create billboard
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "ATG_ESP"
        billboard.Size = UDim2.new(0, 200, 0, 36)
        billboard.StudsOffset = Vector3.new(0, 2.6, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = head

        local label = Instance.new("TextLabel")
        label.Name = "ATG_ESP_Label"
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.BorderSizePixel = 0
        label.Text = ""
        label.TextScaled = true
        label.Font = Enum.Font.GothamBold
        label.TextColor3 = state.espColor
        label.TextStrokeTransparency = 0.4
        label.TextStrokeColor3 = Color3.new(0,0,0)
        label.TextWrapped = true
        label.Parent = billboard

        info.billboard = billboard

        -- live update (RenderStepped)
        info.updateConn = RunService.RenderStepped:Connect(function()
            if not state.espEnabled then return end
            if not p or not p.Character or not p.Character.Parent then
                label.Text = ""
                return
            end

            local parts = {}
            if state.showName then table.insert(parts, p.DisplayName or p.Name) end

            local hum = getHumanoid(p.Character)
            if state.showHealth and hum then
                table.insert(parts, "HP:" .. math.floor(hum.Health))
            end

            if state.showDistance then
                local myHRP = getHRP(LocalPlayer)
                local theirHRP = getHRP(p)
                if myHRP and theirHRP then
                    local d = math.floor((myHRP.Position - theirHRP.Position).Magnitude)
                    table.insert(parts, "[" .. d .. "m]")
                end
            end

            label.Text = table.concat(parts, " | ")
            label.TextColor3 = state.espColor
        end)
    end

    -- attach if character exists now
    if p.Character and p.Character.Parent then
        attachToCharacter(p.Character)
    end

    -- reconnect on respawn
    info.charConn = p.CharacterAdded:Connect(function(char)
        task.wait(0.05)
        if state.espEnabled then
            attachToCharacter(char)
        end
    end)
end

local function removeESPForPlayer(p)
    local info = state.espTable[p]
    if not info then return end
    pcall(function()
        if info.updateConn then info.updateConn:Disconnect() info.updateConn = nil end
        if info.charConn then info.charConn:Disconnect() info.charConn = nil end
        if info.billboard then info.billboard:Destroy() info.billboard = nil end
    end)
    state.espTable[p] = nil
end

-- UI: toggle/color and show options (no size/distance sliders)
local espToggle = Tabs.ESP:AddToggle("ESPToggle", { Title = "ESP", Default = state.espEnabled })
espToggle:OnChanged(function(v)
    state.espEnabled = v
    if not v then
        for pl,_ in pairs(state.espTable) do removeESPForPlayer(pl) end
    else
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then createESPForPlayer(p) end
        end
    end
end)

local espColorPicker = Tabs.ESP:AddColorpicker("ESPColor", { Title = "ESP Color", Default = state.espColor })
espColorPicker:OnChanged(function(c) state.espColor = c end)

Tabs.ESP:AddToggle("ESP_ShowName", { Title = "Show Name", Default = state.showName }):OnChanged(function(v) state.showName = v end)
Tabs.ESP:AddToggle("ESP_ShowHealth", { Title = "Show Health", Default = state.showHealth }):OnChanged(function(v) state.showHealth = v end)
Tabs.ESP:AddToggle("ESP_ShowDistance", { Title = "Show Distance", Default = state.showDistance }):OnChanged(function(v) state.showDistance = v end)

-- handle players joining/leaving
Players.PlayerAdded:Connect(function(p)
    if state.espEnabled and p ~= LocalPlayer then createESPForPlayer(p) end
end)
Players.PlayerRemoving:Connect(function(p) removeESPForPlayer(p) end)

Tabs.Server:AddButton({
    Title = "Find Private Server",
    Description = "หาเซิฟ VIP ฟรี",
    Callback = function()
        Window:Dialog({
            Title = "ยืนยันการทำงาน",
            Content = "แน่ใจนะว่าจะหาเซิฟวี?",
            Buttons = {
                {
                    Title = "Confirm",
                    Callback = function()   
                        loadstring(game:HttpGet("https://raw.githubusercontent.com/caomod2077/Script/refs/heads/main/Free%20Private%20Server.lua"))()
                    end
                },
                {
                    Title = "Cancel",
                    Callback = function()
                    end
                }
            }
        })
    end
})

-- ============================
-- Server Hop (unchanged logic, but minimal calls)
-- ============================
do
    local function findServer()
        local servers = {}
        local cursor = ""
        local placeId = game.PlaceId
        repeat
            local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100" .. (cursor ~= "" and "&cursor=" .. cursor or "")
            local success, response = pcall(function() return HttpService:JSONDecode(game:HttpGet(url)) end)
            if success and response and response.data then
                for _, server in ipairs(response.data) do
                    if server.playing < server.maxPlayers and server.id ~= game.JobId then
                        table.insert(servers, server.id)
                    end
                end
                cursor = response.nextPageCursor or ""
            else break end
        until cursor == ""
        if #servers > 0 then return servers[math.random(1,#servers)] end
        return nil
    end

    Tabs.Server:AddButton({
    Title = "Server Hop",
    Description = "Join a different random server instance.",
    Callback = function()
        Window:Dialog({
            Title = "Server Hop?",
            Content = "คุณต้องการเข้าร่วมเซิร์ฟเวอร์สุ่มใหม่หรือไม่?",
            Buttons = {
                {
                    Title = "Confirm",
                    Callback = function()
                        local ok, err = pcall(function()
                            local serverId = findServer()
                            if serverId then
                                TeleportService:TeleportToPlaceInstance(game.PlaceId, serverId, LocalPlayer)
                            else
                                warn("No available servers found!")
                                Window:Dialog({
                                    Title = "Server Hop Failed",
                                    Content = "ไม่พบเซิร์ฟเวอร์ว่างสำหรับ Hop!",
                                    Buttons = { { Title = "OK", Callback = function() end } }
                                })
                            end
                        end)

                        if not ok then
                            Window:Dialog({
                                Title = "Error!",
                                Content = "เกิดข้อผิดพลาด: " .. tostring(err),
                                Buttons = { { Title = "OK", Callback = function() end } }
                            })
                        end
                    end
                },
                {
                    Title = "Cancel",
                    Callback = function() end
                }
            }
        })
    end
})



    Tabs.Server:AddButton({
    Title = "Rejoin",
    Description = "Rejoin This Server",
    Callback = function()
        -- ถ้า LocalPlayer ยังไม่พร้อม ให้แจ้ง
        if not LocalPlayer then
            Window:Dialog({
                Title = "ไม่พร้อม",
                Content = "ไม่สามารถดึง LocalPlayer ได้ตอนนี้",
                Buttons = { { Title = "OK", Callback = function() end } }
            })
            return
        end

        -- ยืนยันก่อน
        Window:Dialog({
            Title = "Rejoin?",
            Content = "ต้องการกลับเข้าเซิร์ฟเวอร์นี้อีกครั้งหรือไม่? (จะโหลดใหม่)",
            Buttons = {
                {
                    Title = "Confirm",
                    Callback = function()
                        -- เรียก teleport ใน pcall เผื่อเกิด error
                        local ok, err = pcall(function()
                            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
                        end)

                        -- ปกติถ้า teleport สำเร็จ client จะโหลดออกไปและไม่มาถึงบรรทัดนี้
                        if not ok then
                            Window:Dialog({
                                Title = "Error!",
                                Content = "เกิดข้อผิดพลาดขณะพยายาม Rejoin:\n" .. tostring(err),
                                Buttons = { { Title = "OK", Callback = function() end } }
                            })
                        end
                    end
                },
                { Title = "Cancel", Callback = function() end }
            }
        })
    end
})


    local function findLowestServer()
        local lowestServer, lowestPlayers = nil, math.huge
        local cursor = ""
        local placeId = game.PlaceId
        repeat
            local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100" .. (cursor ~= "" and "&cursor=" .. cursor or "")
            local success, response = pcall(function() return HttpService:JSONDecode(game:HttpGet(url)) end)
            if success and response and response.data then
                for _, server in ipairs(response.data) do
                    if server.playing < server.maxPlayers and server.id ~= game.JobId then
                        if server.playing < lowestPlayers then lowestPlayers = server.playing; lowestServer = server.id end
                    end
                end
                cursor = response.nextPageCursor or ""
            else break end
        until cursor == ""
        return lowestServer
    end

    Tabs.Server:AddButton({
    Title = "Lower Server",
    Description = "Join the server with the least number of players.",
    Callback = function()
        Window:Dialog({
            Title = "Lower Server?",
            Content = "คุณต้องการเข้าร่วมเซิร์ฟเวอร์ที่มีผู้เล่นน้อยที่สุดหรือไม่?",
            Buttons = {
                {
                    Title = "Confirm",
                    Callback = function()
                        local ok, err = pcall(function()
                            local serverId = findLowestServer()
                            if serverId then
                                TeleportService:TeleportToPlaceInstance(game.PlaceId, serverId, LocalPlayer)
                            else
                                warn("No available servers found!")
                                Window:Dialog({
                                    Title = "Failed",
                                    Content = "ไม่พบเซิร์ฟเวอร์ว่าง!",
                                    Buttons = { { Title = "OK", Callback = function() end } }
                                })
                            end
                        end)

                        if not ok then
                            Window:Dialog({
                                Title = "Error!",
                                Content = "เกิดข้อผิดพลาด: " .. tostring(err),
                                Buttons = { { Title = "OK", Callback = function() end } }
                            })
                        end
                    end
                },
                { Title = "Cancel", Callback = function() end }
            }
        })
    end
})
end

local Section = Tabs.Server:AddSection("Job ID")

-- เก็บค่าจาก Input
local jobIdInputValue = ""

-- สร้าง Input (ใช้ของเดิมที่ให้มา ปรับ Default ให้ว่าง)
local Input = Tabs.Server:AddInput("Input", {
    Title = "Input Job ID",
    Default = "",
    Placeholder = "วาง Job ID ที่นี่",
    Numeric = false,
    Finished = false,
    Callback = function(Value)
        jobIdInputValue = tostring(Value or "")
    end
})

-- อัปเดตค่าแบบ realtime เวลาเปลี่ยน
Input:OnChanged(function(Value)
    jobIdInputValue = tostring(Value or "")
end)

-- ปุ่ม Teleport
Tabs.Server:AddButton({
    Title = "Teleport to Job",
    Description = "Teleport ไปยัง Job ID ที่ใส่ข้างบน",
    Callback = function()
        -- validation เบื้องต้น
        if jobIdInputValue == "" or jobIdInputValue == "Default" then
            Window:Dialog({
                Title = "กรอกก่อน!!",
                Content = "กรอก Job ID ก่อนนะ จิ้มปุ่มอีกทีจะ teleport ให้",
                Buttons = {
                    { Title = "OK", Callback = function() end }
                }
            })
            return
        end

        -- เช็คว่าเป็น Job เดียวกับที่เราอยู่หรือยัง
        if tostring(game.JobId) == jobIdInputValue then
            Window:Dialog({
                Title = "อยู่แล้วนะ",
                Content = "คุณอยู่ในเซิร์ฟเวอร์นี้อยู่แล้ว (same Job ID).",
                Buttons = { { Title = "OK", Callback = function() end } }
            })
            return
        end

        -- ยืนยันก่อน teleport
        Window:Dialog({
            Title = "ยืนยันการย้าย",
            Content = "จะย้ายไปเซิร์ฟเวอร์ Job ID:\n" .. jobIdInputValue .. "\nยืนยันไหม?",
            Buttons = {
                {
                    Title = "Confirm",
                    Callback = function()
                        -- เรียก Teleport ใน pcall กัน error
                        local ok, err = pcall(function()
                            TeleportService:TeleportToPlaceInstance(game.PlaceId, jobIdInputValue)
                        end)

                        if ok then
                            -- ปกติจะไม่มาถึงบรรทัดนี้เพราะ client จะโหลดหน้า teleport แต่เผื่อ error
                            print("Teleport เริ่มแล้ว — ถ้ามีปัญหาจะมี log ขึ้น")
                        else
                            Window:Dialog({
                                Title = "Teleport ล้มเหลว",
                                Content = "เกิดข้อผิดพลาด: " .. tostring(err),
                                Buttons = { { Title = "OK", Callback = function() end } }
                            })
                        end
                    end
                },
                { Title = "Cancel", Callback = function() end }
            }
        })
    end
})

-- ปุ่มคัดลอก Job ID ปัจจุบัน
Tabs.Server:AddButton({
    Title = "Copy Current Job ID",
    Description = "คัดลอก Job ID ที่คุณอยู่ตอนนี้",
    Callback = function()
        local currentJobId = tostring(game.JobId or "")
        if currentJobId == "" then
            Window:Dialog({
                Title = "ไม่พบ Job ID",
                Content = "ไม่สามารถดึง Job ID ปัจจุบันได้",
                Buttons = { { Title = "OK", Callback = function() end } }
            })
            return
        end

        -- คัดลอกเข้าคลิปบอร์ด
        pcall(function()
            setclipboard(currentJobId)
        end)

        Window:Dialog({
            Title = "สำเร็จ!",
            Content = "คัดลอก Job ID ปัจจุบันเรียบร้อย:\n" .. currentJobId,
            Buttons = { { Title = "OK", Callback = function() end } }
        })
    end
})

-- -----------------------
-- Teleport to Player (Dropdown + Button)
-- -----------------------
-- Teleport to Player (improved) - Camera rotation-friendly + reorganized UI
-- Assistant update: Camera now repositions near target but preserves player camera rotation (doesn't fully lock).
-- UI restructured into sections using AddSection. Added more camera config (offset X/Y/Z, smoothing, rotation lock toggle), and general improvements.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

if not Tabs.Teleport then
    Tabs.Teleport = Window:AddTab({ Title = "Teleport", Icon = "arrow-right" })
end

-- Sections: Player / Teleport / Camera / Advanced
local PlayerSection = Tabs.Teleport:AddSection("Player")
local TeleportSection = Tabs.Teleport:AddSection("Teleport")
local CameraSection = Tabs.Teleport:AddSection("Camera")
local AdvancedSection = Tabs.Teleport:AddSection("Advanced")

local function notify(title, content, duration)
    duration = duration or 4
    if typeof(Fluent) == "table" and Fluent.Notify then
        Fluent:Notify({ Title = title, Content = content, Duration = duration })
    else
        print(string.format("[%s] %s", title, content))
    end
end

-- Player dropdown + Reset button
local playerListDropdown = PlayerSection:AddDropdown("TeleportToPlayerDropdown", {
    Title = "Player",
    Values = {},
    Multi = false,
    Default = 1,
})

local function buildPlayerValues()
    local vals = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(vals, p.Name) end
    end
    if #vals == 0 then vals = {"No players"} end
    return vals
end

local function refreshPlayerDropdown()
    local current = playerListDropdown.Value
    local vals = buildPlayerValues()
    playerListDropdown:SetValues(vals)
    if current and table.find(vals, current) then
        playerListDropdown:SetValue(current)
    else
        playerListDropdown:SetValue(vals[1])
    end
end

PlayerSection:AddButton({
    Title = "Reset Players",
    Description = "Refresh player list",
    Callback = function()
        refreshPlayerDropdown()
        notify("Teleport", "Player list refreshed", 2)
    end,
})

refreshPlayerDropdown()

-- Teleport options (compact labels)
local TeleportMethodDropdown = TeleportSection:AddDropdown("TeleportMethod", {
    Title = "Method",
    Description = "Instant / Tween / MoveTo",
    Values = {"Instant","Tween","MoveTo"},
    Multi = false,
    Default = 1
})

local YOffsetSlider = TeleportSection:AddSlider("TeleportYOffset", { Title = "Y Off", Default = 3, Min = 0, Max = 10, Rounding = 1 })
local TweenTimeSlider = TeleportSection:AddSlider("TeleportTweenTime", { Title = "Tween (s)", Default = 0.25, Min = 0.05, Max = 2, Rounding = 2 })
local AutoFollowInterval = TeleportSection:AddSlider("AutoFollowInterval", { Title = "Auto-Follow Int (s)", Default = 0.35, Min = 0.05, Max = 2, Rounding = 2 })
local CooldownSlider = TeleportSection:AddSlider("TeleportCooldown", { Title = "Cooldown (s)", Default = 0.6, Min = 0, Max = 5, Rounding = 2 })
local RespectHumanoidRootPartToggle = TeleportSection:AddToggle("RespectHRPToggle", { Title = "Require HRP", Default = true })
local NotifyToggle = TeleportSection:AddToggle("TeleportNotifyToggle", { Title = "Notify", Default = true })
local TeleportKeybind = TeleportSection:AddKeybind("TeleportKeybind", { Title = "Keybind", Mode = "Always", Default = "T" })
local TeleportNowToggle = TeleportSection:AddToggle("TeleportNowToggle", { Title = "Teleport Now", Description = "Momentary", Default = false })
local AutoFollowToggle = TeleportSection:AddToggle("TeleportAutoFollowToggle", { Title = "Auto-Follow", Description = "Continuously move to selected", Default = false })
local TeleportToNearestToggle = TeleportSection:AddToggle("TeleportNearestToggle", { Title = "To Nearest", Description = "Momentary", Default = false })

-- Camera options (more granular)
local CameraEnableToggle = CameraSection:AddToggle("CameraEnableToggle", { Title = "Enable Camera Follow", Description = "Position camera near target (won't force rotation by default)", Default = false })
local CameraLockRotationToggle = CameraSection:AddToggle("CameraLockRotationToggle", { Title = "Lock Rotation", Description = "If ON: camera looks at target (locked). If OFF: camera position follows but rotation remains user-controlled", Default = false })
local CameraSmoothingSlider = CameraSection:AddSlider("CameraSmoothing", { Title = "Smoothing", Description = "How fast camera moves to position (0 = snap)", Default = 8, Min = 0, Max = 30, Rounding = 1 })

-- Offsets separated for finer control
local CameraOffsetX = CameraSection:AddSlider("CameraOffsetX", { Title = "Offset X", Default = 0, Min = -10, Max = 10, Rounding = 1 })
local CameraOffsetY = CameraSection:AddSlider("CameraOffsetY", { Title = "Offset Y", Default = 1, Min = -10, Max = 20, Rounding = 1 })
local CameraOffsetZ = CameraSection:AddSlider("CameraOffsetZ", { Title = "Offset Z", Default = -2, Min = -30, Max = 30, Rounding = 1 })

-- Advanced: expose API and debug
AdvancedSection:AddButton({ Title = "Print Camera Info", Description = "Debug", Callback = function()
    local cam = workspace.CurrentCamera
    if cam then
        print("Camera type:", cam.CameraType, "CFrame:", cam.CFrame)
        notify("Teleport", "Camera info printed to output", 2)
    end
end })

-- Internal state
local LastTeleportTime = 0
local AutoFollowConnection = nil
local CameraFollowConnection = nil
local SavedCamera = {Type = nil, Subject = nil}

local function getHRP(player)
    if not player then return nil end
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
end

local function getLocalHRP()
    if not LocalPlayer or not LocalPlayer.Character then return nil end
    return LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or LocalPlayer.Character.PrimaryPart
end

local function teleportToPlayer(player)
    if not player or not player.Parent then if NotifyToggle.Value then notify("Teleport","Target invalid",2) end return false end
    local now = tick()
    local cooldown = CooldownSlider.Value or 0
    if now - LastTeleportTime < cooldown then if NotifyToggle.Value then notify("Teleport", string.format("Cooldown (%.2f)", cooldown - (now - LastTeleportTime)), 2) end return false end

    local targetHRP = getHRP(player)
    if RespectHumanoidRootPartToggle.Value and (not targetHRP) then if NotifyToggle.Value then notify("Teleport","Target missing HRP",2) end return false end

    local localHRP = getLocalHRP()
    if not localHRP then if NotifyToggle.Value then notify("Teleport","Local character not ready",2) end return false end

    local yOffset = YOffsetSlider.Value or 3
    local method = TeleportMethodDropdown.Value or "Instant"

    local success, err = pcall(function()
        local targetCFrame = (targetHRP and targetHRP.CFrame) or (player.Character and player.Character:GetModelCFrame()) or nil
        if not targetCFrame then error("No target CFrame") end
        local destination = targetCFrame + Vector3.new(0, yOffset, 0)

        if method == "Instant" then
            localHRP.CFrame = destination

        elseif method == "Tween" then
            local tweenTime = TweenTimeSlider.Value or 0.25
            local info = TweenInfo.new(math.max(0.01, tweenTime), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            local tween = TweenService:Create(localHRP, info, {CFrame = destination})
            tween:Play()
            tween.Completed:Wait()

        elseif method == "MoveTo" then
            local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.MoveTo then
                humanoid:MoveTo(destination.Position)
                humanoid.MoveToFinished:Wait()
            else
                localHRP.CFrame = destination
            end
        else
            localHRP.CFrame = destination
        end
    end)

    if success then
        LastTeleportTime = tick()
        if NotifyToggle.Value then notify("Teleport","Teleported to "..player.Name,2) end
        return true
    else
        if NotifyToggle.Value then notify("Teleport","Teleport failed: "..tostring(err),3) end
        return false
    end
end

local function findNearestPlayer()
    local myHRP = getLocalHRP()
    if not myHRP then return nil end
    local nearest, bestDist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character and p.Character.PrimaryPart then
            local hrp = getHRP(p)
            if hrp then
                local d = (hrp.Position - myHRP.Position).Magnitude
                if d < bestDist then bestDist = d; nearest = p end
            end
        end
    end
    return nearest
end

-- Keybind action
TeleportKeybind:OnClick(function()
    local sel = playerListDropdown.Value
    if not sel or sel == "No players" then notify("Teleport","No player selected",2); return end
    local target = Players:FindFirstChild(sel)
    if not target then notify("Teleport","Not found",2); return end
    teleportToPlayer(target)
end)

TeleportNowToggle:OnChanged(function(val)
    if val then
        local sel = playerListDropdown.Value
        if not sel or sel == "No players" then notify("Teleport","No player selected",2); TeleportNowToggle:SetValue(false); return end
        local target = Players:FindFirstChild(sel)
        if not target then notify("Teleport","Not found",2); TeleportNowToggle:SetValue(false); return end
        teleportToPlayer(target)
        TeleportNowToggle:SetValue(false)
    end
end)

TeleportToNearestToggle:OnChanged(function(val)
    if val then
        local nearest = findNearestPlayer()
        if not nearest then notify("Teleport","No nearby player",2); TeleportToNearestToggle:SetValue(false); return end
        teleportToPlayer(nearest)
        TeleportToNearestToggle:SetValue(false)
    end
end)

-- Auto-follow uses Heartbeat timing but only while toggle is ON
AutoFollowToggle:OnChanged(function(val)
    if val then
        if AutoFollowConnection then AutoFollowConnection:Disconnect(); AutoFollowConnection = nil end
        AutoFollowConnection = RunService.Heartbeat:Connect(function(dt)
            AutoFollowToggle._acc = (AutoFollowToggle._acc or 0) + dt
            local interval = AutoFollowInterval.Value or 0.35
            if AutoFollowToggle._acc >= interval then
                AutoFollowToggle._acc = 0
                local sel = playerListDropdown.Value
                if sel and sel ~= "No players" then
                    local target = Players:FindFirstChild(sel)
                    if target then teleportToPlayer(target) end
                end
            end
        end)
        notify("Teleport","Auto-Follow ON",2)
    else
        if AutoFollowConnection then AutoFollowConnection:Disconnect(); AutoFollowConnection = nil end
        AutoFollowToggle._acc = nil
        notify("Teleport","Auto-Follow OFF",2)
    end
end)

-- Camera follow implementation: reposition camera near target while preserving user rotation when LockRotation is OFF.
local cam = workspace.CurrentCamera
CameraEnableToggle:OnChanged(function(val)
    if val then
        -- save camera settings
        SavedCamera.Type = cam.CameraType
        SavedCamera.Subject = cam.CameraSubject

        if CameraFollowConnection then CameraFollowConnection:Disconnect(); CameraFollowConnection = nil end
        CameraFollowConnection = RunService.RenderStepped:Connect(function(dt)
            local sel = playerListDropdown.Value
            if not sel or sel == "No players" then return end
            local target = Players:FindFirstChild(sel)
            if not target or not target.Character then return end
            local head = target.Character:FindFirstChild("Head")
            if not head then return end

            -- desired position relative to head
            local offset = Vector3.new(CameraOffsetX.Value or 0, CameraOffsetY.Value or 1, CameraOffsetZ.Value or -2)
            local desiredCF = head.CFrame * CFrame.new(offset)

            -- smoothing
            local smooth = CameraSmoothingSlider.Value or 8

            -- store current look vector before moving camera (preserve user's rotation)
            local currentLook = cam.CFrame.LookVector
            local currentPos = cam.CFrame.Position
            local lerpT = math.clamp(smooth * dt, 0, 1)
            local newPos = currentPos:Lerp(desiredCF.Position, lerpT)

            if CameraLockRotationToggle.Value then
                -- locked: look at head
                cam.CameraType = Enum.CameraType.Scriptable
                cam.CFrame = CFrame.new(newPos, head.Position)
            else
                -- free rotation: move camera position but preserve user's look direction (so user can rotate)
                -- keep CameraType Custom when possible to maintain normal controls
                cam.CameraType = Enum.CameraType.Custom
                -- set CFrame using preserved look vector so rotation follows user input (it's read from cam each frame)
                cam.CFrame = CFrame.new(newPos, newPos + currentLook)
            end
        end)
        notify("Teleport","Camera follow ON (preserves rotation unless locked)",2)
    else
        if CameraFollowConnection then CameraFollowConnection:Disconnect(); CameraFollowConnection = nil end
        -- restore camera
        if SavedCamera.Type then cam.CameraType = SavedCamera.Type else cam.CameraType = Enum.CameraType.Custom end
        if SavedCamera.Subject and LocalPlayer and LocalPlayer.Character then
            local localHum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if localHum then cam.CameraSubject = localHum end
        end
        notify("Teleport","Camera follow OFF",2)
    end
end)

-- safety cleanup when Fluent UI unloads
if Fluent and Fluent.Unloaded then
    Fluent.Unloaded:Connect(function()
        if AutoFollowConnection then AutoFollowConnection:Disconnect(); AutoFollowConnection = nil end
        if CameraFollowConnection then CameraFollowConnection:Disconnect(); CameraFollowConnection = nil end
    end)
end

-- expose API
local TeleportAPI = { TeleportTo = teleportToPlayer, FindNearest = findNearestPlayer, RefreshPlayers = refreshPlayerDropdown }
_G.TeleportToPlayerModule = TeleportAPI

notify("Teleport","Module updated: camera rotation-friendly + UI sections" ,3)


-- -----------------------
-- Anti-AFK
-- -----------------------
do
    local vu = nil
    -- VirtualUser trick: works in many environments (Roblox default)
    local function enableAntiAFK(enable)
        if enable then
            if not vu then
                -- VirtualUser exists only in Roblox client; we get via game:GetService("VirtualUser") (works in studio / client)
                pcall(function() vu = game:GetService("VirtualUser") end)
            end
            if vu then
                Players.LocalPlayer.Idled:Connect(function()
                    pcall(function()
                        vu:Button2Down(Vector2.new(0,0))
                        task.wait(1)
                        vu:Button2Up(Vector2.new(0,0))
                    end)
                end)
            end
            notify("Anti-AFK", "Anti-AFK enabled", 3)
        else
            -- Can't fully disconnect all Idled events if there are others, but setting to nil stops new ones
            notify("Anti-AFK", "Anti-AFK disabled (client may still have other handlers)", 3)
        end
    end

    local antiAFKToggle = Tabs.Settings:AddToggle("AntiAFKToggle", { Title = "Anti-AFK", Default = true })
    antiAFKToggle:OnChanged(function(v) enableAntiAFK(v) end)
    -- default on
    antiAFKToggle:SetValue(true)
    enableAntiAFK(true)
end


-- Addons:
-- SaveManager (Allows you to have a configuration system)
-- InterfaceManager (Allows you to have a interface managment system)

-- Hand the library over to our managers
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)

-- Ignore keys that are used by ThemeManager.
-- (we dont want configs to save themes, do we?)
SaveManager:IgnoreThemeSettings()

-- You can add indexes of elements the save manager should ignore
SaveManager:SetIgnoreIndexes({})

-- use case for doing it this way:
-- a script hub could have themes in a global folder
-- and game configs in a separate folder per game
InterfaceManager:SetFolder("FluentScriptHub")
SaveManager:SetFolder("FluentScriptHub/specific-game")

InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)


Window:SelectTab(1)

Fluent:Notify({
    Title = "ATG Hub",
    Content = "The script has been loaded.",
    Duration = 8
})

-- You can use the SaveManager:LoadAutoloadConfig() to load a config
-- which has been marked to be one that auto loads!
SaveManager:LoadAutoloadConfig() 
