local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()
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
    Main = Window:AddTab({ Title = "Main", Icon = "Main" }),
    Players = Window:AddTab({ Title = "Players", Icon = "Players" }),
    Teleport = Window:AddTab({ Title = "Teleport", Icon = "Teleport" }),
    ESP = Window:AddTab({ Title = "ESP", Icon = "ESP"}),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

local Options = Fluent.Options

do
    Fluent:Notify({
        Title = "Notification",
        Content = "This is a notification",
        SubContent = "SubContent", -- Optional
        Duration = 5 -- Set to nil to make the notification not disappear
    })



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

-- Auto Warp to player's Animals.Models (integrated with Fluent UI)
-- ใส่ส่วนนี้ต่อท้ายนายไว้หลังที่สร้าง Window, Tabs ตามที่ส่งมาแล้ว

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local plotsFolder = workspace:WaitForChild("Map"):WaitForChild("Plots")

-- ตั้งเป็นตัวแปรในโค้ดตามที่ขอ (ค่าเริ่มต้น)
local PerWarpDelay = 0.5   -- เวลาเว้นระหว่างการวาปแต่ละตัว (วินาที)
local CycleDelay = 3       -- เวลาเว้นหลังจบรอบทั้งหมด (วินาที)

-- UI Controls (สร้างในหน้า Main ของ Fluent) — เก็บ Toggle ไว้ตามเดิม
local AutoWarpToggle = Tabs.Main:AddToggle("AutoWarpAnimals", { Title = "Auto Wheat", Default = false })

-- internal control
local warpLoopRunning = false

-- Helper: find a usable BasePart within a model (PrimaryPart, HumanoidRootPart, Head, or first BasePart)
local function findModelPart(model)
    if not model or not model:IsA("Model") then return nil end
    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then return hrp end
    local head = model:FindFirstChild("Head")
    if head and head:IsA("BasePart") then return head end
    for _, v in ipairs(model:GetDescendants()) do
        if v:IsA("BasePart") then return v end
    end
    return nil
end

-- Helper: collect all target parts (CFrames) for the player's owned plots -> Animals -> each Model
local function collectAnimalTargets()
    local targets = {}
    if not plotsFolder then return targets end

    for _, plotModel in ipairs(plotsFolder:GetChildren()) do
        if plotModel:IsA("Model") and plotModel:FindFirstChild("Info") then
            local info = plotModel.Info
            local owner = info:FindFirstChild("Owner")
            if owner and owner:IsA("StringValue") and owner.Value == player.Name then
                local animalsFolder = plotModel:FindFirstChild("Animals")
                if animalsFolder then
                    for _, animalModel in ipairs(animalsFolder:GetChildren()) do
                        if animalModel:IsA("Model") then
                            local part = findModelPart(animalModel)
                            if part then
                                table.insert(targets, { part = part, name = animalModel.Name, plot = plotModel.Name })
                            end
                        end
                    end
                end
            end
        end
    end

    return targets
end

-- Helper: teleport local player to target part safely
local function teleportPlayerToPart(part)
    if not part or not part:IsA("BasePart") then return false, "invalid part" end
    local character = player.Character or player.CharacterAdded:Wait()
    if not character then return false, "no character" end

    local hrp = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChildWhichIsA("BasePart")
    if not hrp then return false, "no hrp" end

    local ok, err = pcall(function()
        hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0)
    end)
    return ok, err
end

-- Main loop runner (non-blocking)
local function startWarpLoop()
    if warpLoopRunning then return end
    warpLoopRunning = true

    task.spawn(function()
        while warpLoopRunning and not Fluent.Unloaded do
            local targets = collectAnimalTargets()

            if #targets == 0 then
                -- no targets found, just wait a cycle
            else
                for idx, t in ipairs(targets) do
                    if not warpLoopRunning or Fluent.Unloaded then break end

                    local ok, err = teleportPlayerToPart(t.part)
                    if not ok then
                        -- optional: warn(("Warp failed to %s in %s : %s"):format(t.name, t.plot, tostring(err)))
                    end

                    -- delay between individual warps (ใช้ตัวแปร PerWarpDelay)
                    local perDelay = PerWarpDelay or 0.5
                    if perDelay > 0 then
                        local waited = 0
                        while waited < perDelay do
                            if not warpLoopRunning or Fluent.Unloaded then break end
                            local step = 0.1
                            task.wait(step)
                            waited = waited + step
                        end
                    end
                end
            end

            -- after finishing all targets, wait cycle delay (ใช้ตัวแปร CycleDelay)
            local cycle = CycleDelay or 3
            local waited = 0
            while waited < cycle do
                if not warpLoopRunning or Fluent.Unloaded then break end
                local step = 0.5
                task.wait(step)
                waited = waited + step
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
    if Options.AutoWarpAnimals.Value then
        startWarpLoop()
        Fluent:Notify({ Title = "Auto Warp", Content = "เริ่มวาปไปที่ Animals ของคุณ", Duration = 4 })
    else
        stopWarpLoop()
        Fluent:Notify({ Title = "Auto Warp", Content = "หยุดการวาปแล้ว", Duration = 4 })
    end
end)

if Options.AutoWarpAnimals.Value then
    startWarpLoop()
end

-- Remote
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remoteFolder = ReplicatedStorage:WaitForChild("Remote_Events")
local buyTreatRemote = remoteFolder:WaitForChild("Buy_Treat")

-- Settings
local FIRE_DELAY = 0.5 -- ดีเลย์เป็น 0.5 วิ ตามที่ขอ (เปลี่ยนถ้าต้องการ)

-- Multi dropdown (identifier "Treats")
local MultiDropdown = Tabs.Main:AddDropdown("Treats", {
    Title = "Select Treat",
    Description = "เลือกได้หลายค่า (Multi)",
    Values = {"Apple", "Banana", "Carrot", "Corn", "Pepper","Cherries"}, -- ใส่รายการตามเกมจริงได้เลย
    Multi = true,
    Default = {"Apple"}
})

-- Toggle (identifier "AutoFireToggle")
local AutoToggle = Tabs.Main:AddToggle("AutoFireToggle", { Title = " Auto Buy Treat", Default = false })

-- Ensure default
Options.AutoFireToggle:SetValue(false)

-- Optional: แสดงการเปลี่ยนค่าเมื่อ user เลือก/ยกเลิก
MultiDropdown:OnChanged(function(Value)
    local sel = {}
    for k,v in pairs(Value) do
        if v then table.insert(sel, k) end
    end
    if #sel == 0 then
        print("No treats selected")
    else
        print("Selected treats:", table.concat(sel, ", "))
    end
end)

-- Auto-loop control
local autoFireRunning = false

AutoToggle:OnChanged(function()
    local enabled = Options.AutoFireToggle.Value
    if enabled and not autoFireRunning then
        autoFireRunning = true
        task.spawn(function()
            -- Loop จะหยุดเมื่อ Toggle ถูกปิด (Options.AutoFireToggle.Value == false)
            while Options.AutoFireToggle.Value do
                -- อ่านค่าจาก MultiDropdown คาดว่าเป็น table { ["Apple"]=true, ... }
                local selMap = Options.Treats and Options.Treats.Value or {}
                local selList = {}
                for name, state in pairs(selMap) do
                    if state then table.insert(selList, name) end
                end

                if #selList == 0 then
                    -- ถ้าไม่มีการเลือกไอเท็ม ให้รอแล้ววนใหม่
                    task.wait(FIRE_DELAY)
                else
                    -- วนยิงทีละไอเท็ม (สลับตามลิสต์)
                    for _, itemName in ipairs(selList) do
                        if not Options.AutoFireToggle.Value then break end -- ตรวจสอบ Toggle ระหว่างการทำงาน
                        -- ป้องกัน error โดยใช้ pcall
                        pcall(function()
                            -- ส่งอาร์กิวเมนต์แบบเดิมที่ server น่าจะคาดหวัง เช่น remote:FireServer("Apple")
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

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local plotsFolder = workspace:WaitForChild("Map"):WaitForChild("Plots")

for i, model in ipairs(plotsFolder:GetChildren()) do
	if model:IsA("Model") and model:FindFirstChild("Info") then
		local info = model.Info
		local owner = info:FindFirstChild("Owner")

		if owner and owner:IsA("StringValue") then
			if owner.Value == player.Name then
			end
		end
	end
end


    -- สร้างตัวแปรเก็บค่า Dropdown ปัจจุบัน
local selectedZone = "Zone 1"

-- สร้าง Dropdown
local Dropdown = Tabs.Teleport:AddDropdown("Teleport", {
    Title = "Select to Teleport",
    Values = {"Zone 1", "Zone 2","Zone 3","Zone 4", "Zone 5", "Zone 6", "Zone 7", "Zone 8"},
    Multi = false,
    Default = 1,
})

-- ตั้งค่าเริ่มต้น
Dropdown:SetValue("Zone 1")

-- เมื่อ Dropdown เปลี่ยนค่า
Dropdown:OnChanged(function(Value)
    selectedZone = Value
    print("Dropdown changed:", Value)
end)

-- สร้างปุ่ม Teleport
Tabs.Teleport:AddButton({
    Title = "Teleport",
    Description = "Click To Teleport",
    Callback = function()
        Window:Dialog({
            Title = "Teleport to ...",
            Content = "Are you sure you want to teleport to " .. selectedZone .. "?",
            Buttons = {
                {
                    Title = "Confirm",
                    Callback = function()
                        -- วาปตามค่า Dropdown
                        local player = game.Players.LocalPlayer
                        local char = player.Character or player.CharacterAdded:Wait()
                        local hrp = char:WaitForChild("HumanoidRootPart")
                        
                        if selectedZone == "Zone 1" then
                            hrp.CFrame = CFrame.new(17240, 40, 850)
                        elseif selectedZone == "Zone 2" then
                            hrp.CFrame = CFrame.new(17300, 50, -15)
                        elseif selectedZone == "Zone 3" then
                            hrp.CFrame = CFrame.new(-1, 50, -501)
                        elseif selectedZone == "Zone 4" then
                            hrp.CFrame = CFrame.new(200, 30, -300)
                        elseif selectedZone == "Zone 5" then
                            hrp.CFrame = CFrame.new(45, 30, 70)
                        elseif selectedZone == "Zone 6" then
                            hrp.CFrame = CFrame.new(430, 50, 450)
                        elseif selectedZone == "Zone 7" then
                            hrp.CFrame = CFrame.new(430, 50, 707)
                        elseif selectedZone == "Zone 8" then
                            hrp.CFrame = CFrame.new(480, 50, 960)
                        end

                        print("Teleported to " .. selectedZone)
                    end
                },
                {
                    Title = "Cancel",
                    Callback = function()
                        print("Cancelled the dialog.")
                    end
                }
            }
        })
    end
})

-- -----------------------
-- Speed & Jump sliders
-- -----------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Humanoid

-- ค่าเริ่มต้น
local CurrentWalkSpeed = 16
local CurrentJumpPower = 50

-- ฟังก์ชันหา Humanoid
local function getHumanoid()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return char:FindFirstChildWhichIsA("Humanoid")
end

-- ฟังก์ชันเซ็ต WalkSpeed
local function setWalkSpeed(v)
    CurrentWalkSpeed = v
    Humanoid = getHumanoid()
    if Humanoid then
        Humanoid.WalkSpeed = v
    end
end

-- ฟังก์ชันเซ็ต JumpPower
local function setJumpPower(v)
    CurrentJumpPower = v
    Humanoid = getHumanoid()
    if Humanoid then
        Humanoid.JumpPower = v
    end
end

-- อัปเดต Humanoid ทุกครั้งที่ตัวละครตาย/รีสปอน
LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(1) -- รอโหลด Humanoid ให้เสร็จ
    Humanoid = getHumanoid()
    if Humanoid then
        Humanoid.WalkSpeed = CurrentWalkSpeed
        Humanoid.JumpPower = CurrentJumpPower
    end
end)

-- Loop ย้ำค่าตลอด (กันเกมรีเซ็ต)
RunService.Stepped:Connect(function()
    Humanoid = getHumanoid()
    if Humanoid then
        if Humanoid.WalkSpeed ~= CurrentWalkSpeed then
            Humanoid.WalkSpeed = CurrentWalkSpeed
        end
        if Humanoid.JumpPower ~= CurrentJumpPower then
            Humanoid.JumpPower = CurrentJumpPower
        end
    end
end)

-- === UI Slider ===
local speedSlider = Tabs.Players:AddSlider("WalkSpeedSlider", {
    Title = "WalkSpeed",
    Default = 16,
    Min = 8,
    Max = 200,
    Rounding = 0,
    Callback = function(Value)
        setWalkSpeed(Value)
    end
})
speedSlider:OnChanged(setWalkSpeed)

local jumpSlider = Tabs.Players:AddSlider("JumpPowerSlider", {
    Title = "JumpPower",
    Default = 50,
    Min = 10,
    Max = 300,
    Rounding = 0,
    Callback = function(Value)
        setJumpPower(Value)
    end
})
jumpSlider:OnChanged(setJumpPower)
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

    -- Noclip: save original collisions when enabling, restore when disabling
    local function setNoclip(enable)
        state.noclipEnabled = enable and true or false
        if enable then
            -- save and disable
            local char = LocalPlayer.Character
            if not char then
                notify("Noclip", "Character not ready", 2)
                return
            end
            savedCanCollide = {}
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    savedCanCollide[part] = part.CanCollide
                    pcall(function() part.CanCollide = false end)
                end
            end
            notify("Noclip", "Noclip enabled", 3)
        else
            -- restore
            for part, val in pairs(savedCanCollide) do
                if part and part.Parent then
                    pcall(function() part.CanCollide = val end)
                end
            end
            savedCanCollide = {}
            notify("Noclip", "Noclip disabled", 2)
        end
    end

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
        Max = 350,
        Rounding = 0,
        Callback = function(v) fly.speed = v end
    })
    flySpeedSlider:SetValue(fly.speed)

    local noclipToggle = Tabs.Players:AddToggle("NoclipToggle", { Title = "Noclip", Default = false })
    noclipToggle:OnChanged(function(v) setNoclip(v) end)

    Tabs.Players:AddKeybind("FlyKey", {
        Title = "Fly Key (Toggle)",
        Mode = "Toggle",
        Default = "F",
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



-- -----------------------
-- Teleport to Player (Dropdown + Button)
-- -----------------------
local playerListDropdown = Tabs.Teleport:AddDropdown("TeleportToPlayerDropdown", {
    Title = "Select Player to Teleport",
    Values = {},
    Multi = false,
    Default = 1
})

local function refreshPlayerDropdown()
    local vals = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            table.insert(vals, p.Name)
        end
    end
    if #vals == 0 then
        vals = {"No other players"}
        playerListDropdown:SetValues(vals)
        playerListDropdown:SetValue(vals[1])
        return
    end
    playerListDropdown:SetValues(vals)
    playerListDropdown:SetValue(vals[1])
end

-- init and update on join/leave
refreshPlayerDropdown()
Players.PlayerAdded:Connect(function(p)
    task.delay(0.5, refreshPlayerDropdown)
end)
Players.PlayerRemoving:Connect(function(p)
    task.delay(0.5, refreshPlayerDropdown)
end)

Tabs.Teleport:AddButton({
    Title = "Teleport to Selected Player",
    Description = "Teleport to the player selected in the dropdown",
    Callback = function()
        local sel = playerListDropdown.Value
        if not sel or sel == "No other players" then notify("Teleport", "No player selected", 3); return end
        local target = Players:FindFirstChild(sel)
        if not target then notify("Teleport", "Player not found", 3); return end
        if target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.CFrame = target.Character.HumanoidRootPart.CFrame + Vector3.new(0,3,0)
                notify("Teleport", "Teleported to "..target.Name, 3)
            end
        else
            notify("Teleport", "Target character not available", 3)
        end
    end
})

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

-- -----------------------
-- Server Hop
-- -----------------------
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ฟังก์ชันหาเซิร์ฟเวอร์ใหม่
local function findServer()
    local servers = {}
    local cursor = ""
    local found = false
    local placeId = game.PlaceId

    repeat
        local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100" .. (cursor ~= "" and "&cursor=" .. cursor or "")
        local success, response = pcall(function()
            return HttpService:JSONDecode(game:HttpGet(url))
        end)

        if success and response and response.data then
            for _, server in ipairs(response.data) do
                if server.playing < server.maxPlayers and server.id ~= game.JobId then
                    table.insert(servers, server.id)
                    found = true
                end
            end
            cursor = response.nextPageCursor or ""
        else
            break
        end
    until cursor == "" or found

    if #servers > 0 then
        return servers[math.random(1, #servers)]
    else
        return nil
    end
end

-- ปุ่มใน UI
Tabs.Settings:AddButton({
    Title = "Server Hop",
    Description = "Join a different random server instance.",
    Callback = function()
        local serverId = findServer()
        if serverId then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, serverId, LocalPlayer)
        else
            warn("No available servers found!")
        end
    end
})

local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

Tabs.Settings:AddButton({
    Title = "Rejoin",
    Description = "Rejoin This Server",
    Callback = function()
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end)
        if not ok then 
            notify("Rejoin Error", tostring(err), 5) 
        end
    end
})


local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ฟังก์ชันหาเซิร์ฟเวอร์ที่คนน้อยที่สุด
local function findLowestServer()
    local lowestServer = nil
    local lowestPlayers = math.huge
    local cursor = ""
    local placeId = game.PlaceId

    repeat
        local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100" .. (cursor ~= "" and "&cursor=" .. cursor or "")
        local success, response = pcall(function()
            return HttpService:JSONDecode(game:HttpGet(url))
        end)

        if success and response and response.data then
            for _, server in ipairs(response.data) do
                if server.playing < server.maxPlayers and server.id ~= game.JobId then
                    if server.playing < lowestPlayers then
                        lowestPlayers = server.playing
                        lowestServer = server.id
                    end
                end
            end
            cursor = response.nextPageCursor or ""
        else
            break
        end
    until cursor == ""

    return lowestServer
end

-- ปุ่มใน UI
Tabs.Settings:AddButton({
    Title = "Lower Server",
    Description = "Join the server with the least number of players.",
    Callback = function()
        local serverId = findLowestServer()
        if serverId then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, serverId, LocalPlayer)
        else
            warn("No available servers found!")
        end
    end
})

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
