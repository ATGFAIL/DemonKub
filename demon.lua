-- -----------------------
-- Allowed PlaceIds
-- -----------------------
local allowedPlaces = {
    [8069117419] = true -- ตัวอย่างแมพ 1
}

-- ตรวจสอบแมพ
if not allowedPlaces[game.PlaceId] then
    warn("❌ Script ไม่ทำงานในแมพนี้:", game.PlaceId)
    return
end

print("✅ Script Loaded in allowed map:", game.PlaceId)


local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
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
    Main = Window:AddTab({ Title = "Main", Icon = "" }),
    Players = Window:AddTab({ Title = "Players", Icon = "" }),
    Teleport = Window:AddTab({ Title = "Teleport", Icon = "" }),
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


local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- ตั้งค่าระยะห่างเหนือ Part
local hoverHeight = 10

-- ความเร็ว/ความลื่นของ align (ปรับได้)
local alignResponsiveness = 40    -- ยิ่งสูง ยิ่งตามเป้าไว
local targetLerp = 0.20           -- อัตรา lerp ในการย้าย targetPart (0-1)

-- ควบคุมสถานะ AutoFarm
local autoFarmEnabled = false
local farmWorkerRunning = false

-- เก็บสถานะ CanCollide เดิมเพื่อคืนค่า
local savedCanCollide = {}

-- Align objects / target part
local targetPart = nil
local hrpAttachment = nil
local targetAttachment = nil
local alignPos = nil
local alignOri = nil

-- ฟังก์ชันหา Part ทั้งหมดใน Model ที่สนใจ (คัดลอกจากของคุณ)
local function getAllParts(models)
    local parts = {}

    local function scanFolder(folder)
        for _, obj in ipairs(folder:GetChildren()) do
            if obj:IsA("BasePart") then
                table.insert(parts, obj)
            elseif obj:IsA("Folder") or obj:IsA("Model") then
                scanFolder(obj)
            end
        end
    end

    for _, model in ipairs(models) do
        if model and model.Parent then
            scanFolder(model)
        end
    end

    return parts
end

local function getNearestPart()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local models = {
        workspace:FindFirstChild("NewBieGhostPos"),
        workspace:FindFirstChild("GhostPos"),
    }

    local parts = getAllParts(models)
    local nearestPart = nil
    local shortestDist = math.huge

    for _, part in ipairs(parts) do
        if part and part:IsA("BasePart") then
            local dist = (part.Position - hrp.Position).Magnitude
            if dist < shortestDist then
                shortestDist = dist
                nearestPart = part
            end
        end
    end

    return nearestPart
end

-- เก็บ/คืนค่า CanCollide ของตัวละคร
local function setCharacterCollisions(enable)
    local char = LocalPlayer.Character
    if not char then return end

    if enable then
        for part, val in pairs(savedCanCollide) do
            if part and part.Parent then
                pcall(function() part.CanCollide = val end)
            end
        end
        savedCanCollide = {}
    else
        savedCanCollide = {}
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                savedCanCollide[part] = part.CanCollide
                pcall(function() part.CanCollide = false end)
            end
        end
    end
end

-- สร้างระบบ Align (targetPart + Attachments + AlignPosition/Orientation)
local function createAlignSystem()
    -- ถ้ามีอยู่แล้ว ให้เคลียร์ก่อน
    if targetPart and targetPart.Parent then
        pcall(function() targetPart:Destroy() end)
    end

    -- target part (anchored, invisible)
    targetPart = Instance.new("Part")
    targetPart.Name = "ATG_AutoFarmTarget"
    targetPart.Size = Vector3.new(0.2,0.2,0.2)
    targetPart.Transparency = 1
    targetPart.CanCollide = false
    targetPart.Anchored = true
    targetPart.Parent = workspace

    -- หาก character มี HRP ให้สร้าง Attachment บน HRP
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    -- hrp attachment (ถ้ายังไม่มี)
    hrpAttachment = hrp:FindFirstChild("ATG_HRP_Attachment")
    if not hrpAttachment then
        hrpAttachment = Instance.new("Attachment")
        hrpAttachment.Name = "ATG_HRP_Attachment"
        hrpAttachment.Parent = hrp
        hrpAttachment.Position = Vector3.new(0,0,0)
    end

    -- target attachment
    targetAttachment = targetPart:FindFirstChild("ATG_Target_Attachment")
    if not targetAttachment then
        targetAttachment = Instance.new("Attachment")
        targetAttachment.Name = "ATG_Target_Attachment"
        targetAttachment.Parent = targetPart
    end

    -- AlignPosition
    alignPos = hrp:FindFirstChild("ATG_AlignPosition")
    if not alignPos then
        alignPos = Instance.new("AlignPosition")
        alignPos.Name = "ATG_AlignPosition"
        alignPos.Attachment0 = hrpAttachment
        alignPos.Attachment1 = targetAttachment
        alignPos.RigidityEnabled = false
        alignPos.ReactionForceEnabled = false
        alignPos.MaxForce = 1e6
        alignPos.MaxVelocity = math.huge
        alignPos.Responsiveness = alignResponsiveness
        alignPos.Parent = hrp
    end

    -- AlignOrientation
    alignOri = hrp:FindFirstChild("ATG_AlignOrientation")
    if not alignOri then
        alignOri = Instance.new("AlignOrientation")
        alignOri.Name = "ATG_AlignOrientation"
        alignOri.Attachment0 = hrpAttachment
        alignOri.Attachment1 = targetAttachment
        alignOri.MaxTorque = 1e6
        alignOri.Responsiveness = alignResponsiveness
        alignOri.Parent = hrp
    end

    return true
end

local function destroyAlignSystem()
    if alignPos then
        pcall(function() alignPos:Destroy() end)
        alignPos = nil
    end
    if alignOri then
        pcall(function() alignOri:Destroy() end)
        alignOri = nil
    end
    if hrpAttachment then
        pcall(function() hrpAttachment:Destroy() end)
        hrpAttachment = nil
    end
    if targetAttachment then
        pcall(function() targetAttachment:Destroy() end)
        targetAttachment = nil
    end
    if targetPart then
        pcall(function() targetPart:Destroy() end)
        targetPart = nil
    end
end

-- ฟังก์ชันหลัก เปิด/ปิด AutoFarm (ใช้ Align)
local function enableAutoFarmAura(enable)
    autoFarmEnabled = enable

    if autoFarmEnabled and not farmWorkerRunning then
        farmWorkerRunning = true

        -- ตรวจสอบ character พร้อม แล้วสร้าง align system
        if not LocalPlayer.Character then
            LocalPlayer.CharacterAdded:Wait()
        end
        -- รอ HRP
        local hrp = LocalPlayer.Character and LocalPlayer.Character:WaitForChild("HumanoidRootPart", 5)
        if not hrp then
            warn("AutoFarm: HRP not found")
            farmWorkerRunning = false
            return
        end

        -- ปิดการชนของตัวละครเพื่อให้ทะลุ (เก็บค่าเดิม)
        setCharacterCollisions(false)

        -- สร้างระบบ Align
        local ok = createAlignSystem()
        if not ok then
            warn("AutoFarm: failed to create align system")
            setCharacterCollisions(true)
            farmWorkerRunning = false
            return
        end

        -- loop อัพเดต targetPart ไปยัง nearestPart (ใช้ lerp เพื่อความลื่น)
        task.spawn(function()
            while autoFarmEnabled do
                -- หาก character respawn ให้รีเซ็ตระบบ
                if not LocalPlayer.Character or not LocalPlayer.Character.Parent then
                    -- รอ character ใหม่ แล้ว recreate align
                    LocalPlayer.CharacterAdded:Wait()
                    task.wait(0.2)
                    destroyAlignSystem()
                    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                        createAlignSystem()
                    end
                    setCharacterCollisions(false)
                end

                local nearest = getNearestPart()
                if nearest and targetPart then
                    local desired = nearest.Position + Vector3.new(0, hoverHeight, 0)
                    -- lerp target position เล็กน้อยเพื่อลดกระโดด
                    local currentCFrame = targetPart.CFrame
                    local goalCFrame = CFrame.new(desired)
                    targetPart.CFrame = currentCFrame:Lerp(goalCFrame, targetLerp)
                end

                -- สั้น ๆ เพื่อไม่ให้หน่วงมาก
                task.wait(0.06)
            end

            -- ปิด/คืนค่าเมื่อหยุด
            destroyAlignSystem()
            setCharacterCollisions(true)
            farmWorkerRunning = false
        end)

    elseif not autoFarmEnabled then
        -- ปิดทันที: เคลียร์ทุกอย่าง
        autoFarmEnabled = false
        destroyAlignSystem()
        setCharacterCollisions(true)
        farmWorkerRunning = false
    end
end

-- UI Toggle (ใช้ของคุณ)
local autoFarmToggle = Tabs.Main:AddToggle("AutoFarmAuraToggle", {
    Title = "Auto Farm Aura",
    Default = false,
})
autoFarmToggle:OnChanged(function(v)
    enableAutoFarmAura(v)
end)



local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("GeneralAttack")

-- กำหนดชุด args ที่จะยิงทีละอัน (ตามที่ผู้ใช้ให้มา)
local argsList = {
    { [1] = 4 },
    { [1] = 1 },
    { [1] = 2 },
    { [1] = 3 },
}

-- ตั้งค่าเริ่มต้นของ delay (วินาที ระหว่างการยิงแต่ละอัน)
local delayBetweenShots = 0.01

-- สถานะควบคุมการทำงานของ loop และตัวแปรกันซ้ำ
local fastAttackEnabled = false
local workerRunning = false

-- ฟังก์ชันเปิด/ปิด Fast Attack
local function enableFastAttack(enable)
    fastAttackEnabled = enable

    -- ถ้าเปิดแล้ว worker ยังไม่รัน ให้ spawn มัน
    if fastAttackEnabled and not workerRunning then
        workerRunning = true
        task.spawn(function()
            while fastAttackEnabled do
                -- วนยิงทีละอัน ตามลำดับ และเว้นระยะ 0.01 วิ ระหว่างแต่ละการยิง
                for idx, args in ipairs(argsList) do
                    -- ถ้าระหว่างการยิงมีการปิด ให้ break ออกทั้ง loop ทันที
                    if not fastAttackEnabled then break end

                    local ok, err = pcall(function()
                        remote:FireServer(unpack(args))
                    end)
                    if not ok then
                        warn(string.format("FastAttack - shot %d failed: %s", idx, tostring(err)))
                    end

                    -- รอระยะสั้นก่อนยิงตัวถัดไป
                    task.wait(delayBetweenShots)
                end

                -- ถ้ายังเปิดอยู่ จะวนทำรอบถัดไปโดยอัตโนมัติ (ไม่มีการจำกัดจำนวนรอบ)
            end

            -- worker จะมาถึงตรงนี้เมื่อ fastAttackEnabled == false
            workerRunning = false
        end)
    end
    -- ถ้าปิด จะให้ loop หยุดเองเพราะ fastAttackEnabled = false
end

-- สร้าง Toggle ใน UI แทน AntiAFK (ตามตัวอย่างของคุณ)
local fastAttackToggle = Tabs.Main:AddToggle("FastAttackToggle", {
    Title = "Fast Attack",
    Default = false, -- กำหนดค่า default ตามต้องการ
})

fastAttackToggle:OnChanged(function(v)
    enableFastAttack(v)
end)

-- (ถ้าต้องการให้เปิดโดย default ให้ใช้บรรทัดด้านล่าง)
-- fastAttackToggle:SetValue(true)
-- enableFastAttack(true)

-- ตัวเลือกเพิ่มเติม (ถ้าต้องการให้ผู้ใช้ปรับ delay ผ่าน UI)
-- local delaySlider = Tabs.Settings:AddSlider("FastAttackDelay", { Title = "Delay (s)", Min = 0.001, Max = 0.1, Default = 0.01, Precision = 0.001 })
-- delaySlider:OnChanged(function(val) delayBetweenShots = val end)

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
local LocalPlayer = Players.LocalPlayer

local function setWalkSpeed(v)
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hum = char:FindFirstChildWhichIsA("Humanoid")
    if hum then 
        hum.WalkSpeed = v 
    end
end

local function setJumpPower(v)
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hum = char:FindFirstChildWhichIsA("Humanoid")
    if hum then 
        hum.JumpPower = v 
    end
end

-- WalkSpeed Slider
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

-- JumpPower Slider
local jumpSlider = Tabs.Players:AddSlider("JumpSlider", {
    Title = "JumpPower",
    Default = 50,
    Min = 0,
    Max = 300,
    Rounding = 0,
    Callback = function(Value)
        setJumpPower(Value)
    end
})
jumpSlider:OnChanged(setJumpPower)

-- ensure defaults applied on spawn/character added
LocalPlayer.CharacterAdded:Connect(function(char)
    task.delay(0.5, function()
        setWalkSpeed(speedSlider.Value or 16)
        setJumpPower(jumpSlider.Value or 50)
    end)
end)

-- apply immediately if character already loaded
if LocalPlayer.Character then
    task.delay(0.5, function()
        setWalkSpeed(speedSlider.Value or 16)
        setJumpPower(jumpSlider.Value or 50)
    end)
end

    -- Auto Skill System
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local skillRemote = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("SkillAttack")

-- mapping ของสกิลกับ args
local skillMap = {
    Q = { [1] = 1 },
    E = { [1] = 2 },
    R = { [1] = 3 },
}

-- ตัวเลือก skill ที่ผู้ใช้เลือกจาก MultiDropdown
local selectedSkills = { "Q", "E", "R" }

-- ตัวแปรควบคุม loop
local autoSkillEnabled = false
local skillWorkerRunning = false

-- MultiDropdown UI
local MultiDropdown = Tabs.Main:AddDropdown("MultiDropdown", {
    Title = "Auto Skill",
    Description = "Select Skills",
    Values = {"Q", "E", "R"},
    Multi = true,
    Default = {"Q", "E", "R"},
})

MultiDropdown:OnChanged(function(values)
    selectedSkills = {}
    for value, state in next, values do
        if state then
            table.insert(selectedSkills, value)
        end
    end
    print("Selected Skills:", table.concat(selectedSkills, ", "))
end)

-- ฟังก์ชันเปิดปิด Auto Skill
local function enableAutoSkill(enable)
    autoSkillEnabled = enable
    if autoSkillEnabled and not skillWorkerRunning then
        skillWorkerRunning = true
        task.spawn(function()
            while autoSkillEnabled do
                for _, skill in ipairs(selectedSkills) do
                    if not autoSkillEnabled then break end
                    local args = skillMap[skill]
                    if args then
                        local ok, err = pcall(function()
                            skillRemote:FireServer(unpack(args))
                        end)
                        if not ok then
                            warn("AutoSkill failed for:", skill, err)
                        end
                    end
                    task.wait(0.5) -- ดีเลย์ระหว่างสกิลแต่ละอัน (ปรับได้)
                end
                task.wait(0.1) -- ดีเลย์ระหว่างรอบ
            end
            skillWorkerRunning = false
        end)
    end
end

-- Toggle UI สำหรับเปิด/ปิด Auto Skill
local autoSkillToggle = Tabs.Main:AddToggle("AutoSkillToggle", {
    Title = "Enable Auto Skill",
    Default = false,
})

autoSkillToggle:OnChanged(function(v)
    enableAutoSkill(v)
end)
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

-- -----------------------
-- Fly (simple) & Noclip
-- -----------------------
local flyForce = {bv = nil, bg = nil}
local function enableFly(enable)
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if enable then
        if hrp then
            flyForce.bv = Instance.new("BodyVelocity")
            flyForce.bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
            flyForce.bv.Velocity = Vector3.new(0,0,0)
            flyForce.bv.Parent = hrp

            flyForce.bg = Instance.new("BodyGyro")
            flyForce.bg.MaxTorque = Vector3.new(1e5,1e5,1e5)
            flyForce.bg.CFrame = hrp.CFrame
            flyForce.bg.Parent = hrp

            notify("Fly", "Fly enabled", 3)
        end
    else
        if flyForce.bv then flyForce.bv:Destroy() flyForce.bv = nil end
        if flyForce.bg then flyForce.bg:Destroy() flyForce.bg = nil end
        notify("Fly", "Fly disabled", 2)
    end
    state.flyEnabled = enable
end

local flyToggle = Tabs.Players:AddToggle("FlyToggle", {Title = "Fly", Default = false})
flyToggle:OnChanged(function(v) enableFly(v) end)

local function setNoclip(enable)
    state.noclipEnabled = enable
    if enable then
        notify("Noclip", "Noclip enabled", 3)
    else
        notify("Noclip", "Noclip disabled", 2)
        local char = LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then pcall(function() part.CanCollide = true end) end
            end
        end
    end
end

local noclipToggle = Tabs.Players:AddToggle("NoclipToggle", {Title = "Noclip", Default = false})
noclipToggle:OnChanged(function(v) setNoclip(v) end)

-- noclip loop
task.spawn(function()
    while true do
        if state.noclipEnabled then
            local char = LocalPlayer.Character
            if char then
                for _,part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                        pcall(function() part.CanCollide = false end)
                    end
                end
            end
        end
        task.wait(0.3)
        if Fluent.Unloaded then break end
    end
end)

-- -----------------------
-- Simple ESP
-- -----------------------
local function createESPForPlayer(p)
    if state.espTable[p] then return end
    local char = p.Character
    if not char then return end
    local head = char:FindFirstChild("Head")
    if not head then return end
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ATG_ESP"
    billboard.Size = UDim2.new(0,100,0,40)
    billboard.StudsOffset = Vector3.new(0,2.5,0)
    billboard.AlwaysOnTop = true
    billboard.Parent = head

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1,1)
    label.BackgroundTransparency = 1
    label.Text = p.Name
    label.TextScaled = true
    label.TextColor3 = Color3.fromRGB(255, 50, 50)
    label.Parent = billboard

    state.espTable[p] = billboard
end

local function removeESPForPlayer(p)
    if state.espTable[p] then
        pcall(function() state.espTable[p]:Destroy() end)
        state.espTable[p] = nil
    end
end

local espToggle = Tabs.Players:AddToggle("ESPToggle", {Title = "ESP", Default = false})
espToggle:OnChanged(function(v)
    state.espEnabled = v
    if not v then
        for pl,_ in pairs(state.espTable) do removeESPForPlayer(pl) end
    else
        for _,p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then createESPForPlayer(p) end
        end
    end
end)

Players.PlayerAdded:Connect(function(p)
    if state.espEnabled and p ~= LocalPlayer then
        p.CharacterAdded:Connect(function() createESPForPlayer(p) end)
        createESPForPlayer(p)
    end
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
    Title = "Fluent",
    Content = "The script has been loaded.",
    Duration = 8
})

-- You can use the SaveManager:LoadAutoloadConfig() to load a config
-- which has been marked to be one that auto loads!
SaveManager:LoadAutoloadConfig() 
