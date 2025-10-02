-- Libraries
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- Services (cache)
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

-- Window
local Window = Fluent:CreateWindow({
    Title = "ATG Hub Beta",
    SubTitle = "by ATGFAIL",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Main", Icon = "repeat" }),
    Auto = Window:AddTab({ Title = "Auto", Icon = ""}),
    Players = Window:AddTab({ Title = "Players", Icon = "" }),
    Teleport = Window:AddTab({ Title = "Teleport", Icon = "" }),
    ESP = Window:AddTab({ Title = "ESP", Icon = ""}),
    FPS = Window:AddTab({ Title = "FPS", Icon = ""}),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

local Options = Fluent.Options

-- small helper notify
local function notify(title, content, duration)
    Fluent:Notify({ Title = title, Content = content, Duration = duration or 3 })
end

-- ============================
-- Player Info (status panel)
-- ============================
do
    local startTime = tick()
    local infoParagraph = Tabs.Main:AddParagraph({ Title = "Player Info", Content = "Loading player info..." })

    local function pad2(n) return string.format("%02d", tonumber(n) or 0) end

    local function updateInfo()
        local playedSeconds = math.floor(tick() - startTime)
        local hours = math.floor(playedSeconds / 3600)
        local minutes = math.floor((playedSeconds % 3600) / 60)
        local seconds = playedSeconds % 60
        local dateStr = os.date("%d/%m/%Y")
        local content = string.format([[
Name: %s (@%s)
Date : %s

Played Time : %s : %s : %s
]],
            LocalPlayer.DisplayName or LocalPlayer.Name,
            LocalPlayer.Name or "Unknown",
            dateStr,
            pad2(hours), pad2(minutes), pad2(seconds)
        )
        pcall(function() infoParagraph:SetDesc(content) end)
    end

    task.spawn(function()
        while true do
            if Fluent.Unloaded then break end
            pcall(updateInfo)
            task.wait(1)
        end
    end)
end

-- Toggle Auto Buy
local AutoBuyToggle = Tabs.Auto:AddToggle("AutoBuy", {Title = "Auto Buy Seed", Default = false})

-- Multi Dropdown เลือกได้หลายอัน
local BuyMultiDropdown = Tabs.Auto:AddDropdown("BuyMultiDropdown", {
    Title = "Select Seed",
    Description = "Select Seed To Auto Buy",
    Values = {"Dragon Fruit Seed", "Sunflower Seed", "Pumpkin Seed", "Strawberry Seed","Cactus Seed","Grape Seed","Eggplant Seed","Watermelon Seed","Cocotank Seed","Carnivorous Plant Seed","Mr Carrot Seed","Tomatrio Seed","Shroombino Seed"},
    Multi = true,
    Default = {"Dragon Fruit Seed"},
})

-- ตัวแปรควบคุม loop
local AutoBuyRunning = false

-- ฟังก์ชัน Loop ซื้อของ
local function BuyLoop()
    AutoBuyRunning = true
    while AutoBuyRunning and Options.AutoBuy.Value do
        -- เก็บของที่เลือกทั้งหมด
        local selected = {}
        for item, state in pairs(BuyMultiDropdown.Value) do
            if state then
                table.insert(selected, item)
            end
        end

        -- ถ้ามีเลือกของไว้
        if #selected > 0 then
            for _, item in ipairs(selected) do
                -- ยิง Remote 20 ครั้งต่อไอเท็ม
                for i = 1, 20 do
                    if not AutoBuyRunning then break end
                    local args = {[1] = item}
                    game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("BuyItem"):FireServer(unpack(args))
                    print("Bought:", item, "Round:", i)
                    task.wait(0.2)
                end
            end
        end

        -- รอ 4 นาทีค่อยยิงรอบใหม่
        task.wait(60)
    end
end

-- เวลา Toggle เปลี่ยน
AutoBuyToggle:OnChanged(function()
    if Options.AutoBuy.Value then
        if not AutoBuyRunning then
            task.spawn(BuyLoop)
        end
    else
        AutoBuyRunning = false
    end
end)

-- เวลาเลือก MultiDropdown เปลี่ยนค่า (Debug print)
BuyMultiDropdown:OnChanged(function(Value)
    local Values = {}
    for v, state in next, Value do
        if state then table.insert(Values, v) end
    end
    print("Items selected:", table.concat(Values, ", "))
end)

-- Toggle Auto Equip Brainrots
local AutoEquipToggle = Tabs.Auto:AddToggle("AutoEquip", {Title = "Auto Equip Best Brainrots", Default = false})

-- ตัวแปรควบคุม loop
local AutoEquipRunning = false

-- ฟังก์ชัน Loop ยิง Remote
local function EquipLoop()
    AutoEquipRunning = true
    while AutoEquipRunning and Options.AutoEquip.Value do
        -- ยิง Remote รอบละ 1 ครั้ง
        game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("EquipBestBrainrots"):FireServer()
        print("Fired EquipBestBrainrots")
        
        -- รอ 30 วินาที
        task.wait(15)
    end
end

-- เวลา Toggle เปลี่ยนค่า
AutoEquipToggle:OnChanged(function()
    if Options.AutoEquip.Value then
        if not AutoEquipRunning then
            task.spawn(EquipLoop)
        end
    else
        AutoEquipRunning = false
    end
end)

-- Toggle Auto Sell Item
local AutoSellToggle = Tabs.Auto:AddToggle("AutoSell", {Title = "Auto Sell Brainrots", Default = false})

-- ตัวแปรควบคุม loop
local AutoSellRunning = false

-- ฟังก์ชัน Loop ยิง Remote
local function SellLoop()
    AutoSellRunning = true
    while AutoSellRunning and Options.AutoSell.Value do
        -- ยิง Remote รอบละ 1 ครั้ง
        game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("ItemSell"):FireServer()
        print("Fired ItemSell")
        
        -- รอ 32 วินาที
        task.wait(32)
    end
end

-- เวลา Toggle เปลี่ยนค่า
AutoSellToggle:OnChanged(function()
    if Options.AutoSell.Value then
        if not AutoSellRunning then
            task.spawn(SellLoop)
        end
    else
        AutoSellRunning = false
    end
end)

-- MultiDropdown Auto Buy
local AutoBuyDropdown = Tabs.Auto:AddDropdown("AutoBuyGear", {
    Title = "Auto Buy Gear",
    Description = "Select multiple items to auto-buy every 4 minutes",
    Values = {"Water Bucket", "Frost Grenade", "Banana Gun", "Frost Blower","Carrot Launcher"}, -- เพิ่มค่าได้ง่ายๆ
    Multi = true,
    Default = {}
})

local AutoBuyToggle = Tabs.Auto:AddToggle("AutoBuyToggle", {Title = "Auto Buy Gear", Default = false})
local AutoBuyRunning = false

-- ฟังก์ชันยิง Remote
local function FireBuyGear(item)
    local args = {[1] = item}
    game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("BuyGear"):FireServer(unpack(args))
end

-- ฟังก์ชัน Loop Auto Buy
local function AutoBuyLoop()
    AutoBuyRunning = true
    while AutoBuyRunning and Options.AutoBuyToggle.Value do
        -- ดึงไอเทมที่เลือกใน Dropdown
        local selectedItems = {}
        for item, state in pairs(Options.AutoBuyGear.Value) do
            if state then table.insert(selectedItems, item) end
        end

        if #selectedItems > 0 then
            -- ยิงไอเทมแต่ละตัว 20 ครั้ง
            for _, item in ipairs(selectedItems) do
                for i = 1, 20 do
                    FireBuyGear(item)
                    task.wait(0.05) -- หน่วงเล็กน้อยเพื่อไม่ให้เกมค้าง
                end
            end
        end

        -- รอรอบถัดไป 4 นาที
        local waitTime = 1 * 60
        for i = 1, waitTime do
            if not Options.AutoBuyToggle.Value then break end
            task.wait(1)
        end
    end
end

-- เมื่อ Toggle เปลี่ยนค่า
AutoBuyToggle:OnChanged(function()
    if Options.AutoBuyToggle.Value then
        if not AutoBuyRunning then
            task.spawn(AutoBuyLoop)
        end
    else
        AutoBuyRunning = false
    end
end)

-- Toggle Auto Buy Platforms (แก้แล้ว: ไม่มี goto/label)
local PlatformToggle = Tabs.Auto:AddToggle("AutoBuyPlatformToggle", {Title = "Auto Buy Platform", Default = false})
local PlatformRunning = false
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ฟังก์ชันยิง Remote (รับค่าเป็น string/number)
local function FirePlatform(number)
    local ok, err = pcall(function()
        local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
        local buyRemote = remotes:WaitForChild("BuyPlatform")
        buyRemote:FireServer(tostring(number))
    end)
    if not ok then
        warn("[AutoBuyPlatform] FirePlatform error:", err)
    end
end

-- หาโฟลเดอร์ที่ผู้เล่นเป็น Owner (ไม่มี goto)
local function getOwnedPlotFolder()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end

    for _, folder in ipairs(plots:GetChildren()) do
        if not folder then
            -- skip nil
        else
            -- 1) child ชื่อ Owner / owner
            local ownerChild = folder:FindFirstChild("Owner") or folder:FindFirstChild("owner")
            if ownerChild then
                local ok, val = pcall(function() return ownerChild.Value end)
                if ok and val ~= nil then
                    if typeof(val) == "Instance" and val:IsA("Player") then
                        if val.Name == LocalPlayer.Name then
                            return folder
                        end
                    else
                        if tostring(val) == LocalPlayer.Name or tostring(val) == tostring(LocalPlayer.UserId) then
                            return folder
                        end
                    end
                end
            end

            -- 2) attribute Owner / owner
            if folder.GetAttribute then
                local attr = folder:GetAttribute("Owner") or folder:GetAttribute("owner")
                if attr ~= nil then
                    if tostring(attr) == LocalPlayer.Name or tostring(attr) == tostring(LocalPlayer.UserId) then
                        return folder
                    end
                end
            end

            -- 3) child OwnerUserId / OwnerId
            local ownerIdChild = folder:FindFirstChild("OwnerUserId") or folder:FindFirstChild("OwnerId")
            if ownerIdChild then
                local ok2, val2 = pcall(function() return ownerIdChild.Value end)
                if ok2 and tonumber(val2) and tonumber(val2) == LocalPlayer.UserId then
                    return folder
                end
            end

            -- 4) fallback: folder name matches player name
            if folder.Name == LocalPlayer.Name then
                return folder
            end
        end
    end

    return nil
end

-- เก็บชื่อ Model ที่มี BillboardGui "PlatformPrice" ภายใน Brainrots ของโฟลเดอร์ที่เราเป็นเจ้าของ
local function collectPlatformIDsFromOwnedPlot()
    local ids = {}
    local owned = getOwnedPlotFolder()
    if not owned then return ids end

    local brainrots = owned:FindFirstChild("Brainrots") or owned:FindFirstChild("brainrots")
    if not brainrots then return ids end

    for _, m in ipairs(brainrots:GetChildren()) do
        if m and m:IsA("Model") then
            local hasPrice = false
            for _, desc in ipairs(m:GetDescendants()) do
                if desc and desc:IsA("BillboardGui") and desc.Name == "PlatformPrice" then
                    hasPrice = true
                    break
                end
            end
            if hasPrice then
                table.insert(ids, tostring(m.Name))
            end
        end
    end

    return ids
end

-- Loop หลัก: ขณะที่ Toggle เปิด ให้ค้นหา IDs แล้วยิงทีละตัว แล้วรอ 5 นาทีต่อรอบ
local function AutoBuyPlatformLoop()
    PlatformRunning = true
    while PlatformRunning and Options.AutoBuyPlatformToggle.Value do
        local platformIDs = collectPlatformIDsFromOwnedPlot()

        if #platformIDs == 0 then
            warn("[AutoBuyPlatform] ไม่พบ PlatformPrice ในโฟลเดอร์ของคุณ หรือหาโฟลเดอร์ไม่เจอ. จะรอ 5 นาทีแล้วลองใหม่.")
        else
            for _, id in ipairs(platformIDs) do
                if not Options.AutoBuyPlatformToggle.Value then break end
                FirePlatform(id)
                task.wait(0.15) -- หน่วงเล็กน้อยระหว่างการยิงแต่ละอัน
            end
        end

        -- รอรอบถัดไป 5 นาที (ตรวจสอบ toggle ทุกวินาทีเพื่อหยุดทันทีเมื่อปิด)
        local waitTime = 5 * 60
        for i = 1, waitTime do
            if not Options.AutoBuyPlatformToggle.Value then break end
            task.wait(1)
        end
    end

    PlatformRunning = false
end

-- เมื่อ Toggle เปลี่ยนค่า
PlatformToggle:OnChanged(function()
    if Options.AutoBuyPlatformToggle.Value then
        if not PlatformRunning then
            task.spawn(AutoBuyPlatformLoop)
        end
    else
        PlatformRunning = false
    end
end)

-- Toggle UI to send ChangeSetting remote (Graphics on/off)
local ChangeSettingToggle = Tabs.FPS:AddToggle("ChangeSettingToggle", {Title = "Remove Effect", Default = false})

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local changeRemote = remotes:WaitForChild("ChangeSetting")

ChangeSettingToggle:OnChanged(function(state)
    local payload = {
        [1] = {
            ["Value"] = state,
            ["Setting"] = "Graphics"
        }
    }
    local ok, err = pcall(function()
        changeRemote:FireServer(unpack(payload))
    end)
    if not ok then
        warn("[ChangeSetting] FireServer error:", err)
    else
        print("[ChangeSetting] Sent:", state and "Enable Graphics" or "Disable Graphics")
    end
end)

-- Toggle: Teleport -> Follow single Brainrot, smooth follow with Align (NO GATHER)
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Toggle UI (ถ้าตั้งไว้แล้วก็ไม่ต้องเพิ่มซ้ำ)
local BrainrotLockToggle = Tabs.Main:AddToggle("BrainrotLockToggle", { Title = "Lock & Follow Brainrots ( Beta )", Default = false })

-- state
local Running = false
local followConn = nil
local cleanupAligns = {} -- เก็บ Align/Attachments/TargetPart เพื่อ cleanup

-- helper: find a part to use as anchor / primary
local function getAnchorPart(model)
    if not model then return nil end
    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
    for _, v in ipairs(model:GetDescendants()) do
        if v:IsA("BasePart") then return v end
    end
    return nil
end

-- cleanup Aligns / Attachments
local function cleanupAllAligns()
    for _, obj in ipairs(cleanupAligns) do
        pcall(function()
            if obj.AlignPosition then obj.AlignPosition:Destroy() end
            if obj.AlignOrientation then obj.AlignOrientation:Destroy() end
            if obj.AttachmentHRP then obj.AttachmentHRP:Destroy() end
            if obj.AttachmentTarget then obj.AttachmentTarget:Destroy() end
            if obj.TargetPart and obj.TargetPart.Parent then obj.TargetPart:Destroy() end
        end)
    end
    cleanupAligns = {}
end

-- stop everything now
local function stopAll()
    Running = false
    if followConn then
        pcall(function() followConn:Disconnect() end)
        followConn = nil
    end
    cleanupAllAligns()
end

-- create Align setup to smoothly follow a moving target part (uses a hidden anchored target Part)
local function createFollowAligns(hrp)
    if not hrp or not hrp.Parent then return nil end

    local targetPart = Instance.new("Part")
    targetPart.Name = "BR_FollowTarget"
    targetPart.Size = Vector3.new(0.2,0.2,0.2)
    targetPart.Transparency = 1
    targetPart.CanCollide = false
    targetPart.Anchored = true
    targetPart.Parent = workspace

    local attTarget = Instance.new("Attachment"); attTarget.Parent = targetPart
    local attHRP = Instance.new("Attachment"); attHRP.Parent = hrp

    local alignPos = Instance.new("AlignPosition")
    alignPos.Attachment0 = attHRP
    alignPos.Attachment1 = attTarget
    alignPos.RigidityEnabled = false
    alignPos.MaxForce = 1e7
    alignPos.Responsiveness = 20 -- สูงขึ้นเพื่อความนิ่ง
    alignPos.Parent = hrp

    local alignOri = Instance.new("AlignOrientation")
    alignOri.Attachment0 = attHRP
    alignOri.Attachment1 = attTarget
    alignOri.MaxTorque = 1e7
    alignOri.Responsiveness = 40
    alignOri.Parent = hrp

    table.insert(cleanupAligns, {
        AlignPosition = alignPos,
        AlignOrientation = alignOri,
        AttachmentHRP = attHRP,
        AttachmentTarget = attTarget,
        TargetPart = targetPart
    })

    return targetPart
end

-- main per-target: teleport HRP above and follow; NO GATHER
local function teleportFollowAndLock(targetModel, hrp, followTarget)
    if not targetModel or not hrp or not followTarget then return end
    local anchor = getAnchorPart(targetModel)
    if not anchor then return end

    -- immediate teleport ให้เริ่มนิ่ง ๆ
    pcall(function()
        hrp.CFrame = anchor.CFrame * CFrame.new(0, 6, 0)
    end)

    -- follow loop: update followTarget position to be above anchor; Align will pull HRP smoothly
    while Running and Options.BrainrotLockToggle.Value and targetModel.Parent do
        local updatedAnchor = getAnchorPart(targetModel)
        if not updatedAnchor then break end
        local goalCFrame = updatedAnchor.CFrame * CFrame.new(0, 6, 0)
        -- direct set of anchored followTarget (no physics)
        pcall(function() followTarget.CFrame = goalCFrame end)
        -- small wait to avoid hammering; keep update freq moderate so Align can smooth without jitter
        task.wait(0.08) -- ~12.5 updates/sec
    end
end

-- runner: iterate snapshot of models, one-by-one, follow until model disappears; on toggle off restore everything
local function runner()
    Running = true
    -- get HRP
    local hrp = nil
    hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        hrp = LocalPlayer.Character and LocalPlayer.Character:WaitForChild("HumanoidRootPart", 5)
    end
    if not hrp then
        warn("BrainrotLock: HRP not found")
        Running = false
        return
    end

    -- create follow Aligns/target once
    local followTarget = createFollowAligns(hrp)
    if not followTarget then
        warn("BrainrotLock: cannot create follow target")
        Running = false
        return
    end

    -- main loop
    while Running and Options.BrainrotLockToggle.Value do
        local container = workspace:FindFirstChild("ScriptedMap") and workspace.ScriptedMap:FindFirstChild("Brainrots")
        if not container then
            task.wait(1)
            if not Options.BrainrotLockToggle.Value then break end
            continue
        end

        -- snapshot targets to avoid dynamic changing while iterating
        local targets = {}
        for _, m in ipairs(container:GetChildren()) do
            if m:IsA("Model") then table.insert(targets, m) end
        end

        for _, target in ipairs(targets) do
            if not Running or not Options.BrainrotLockToggle.Value then break end
            if target and target.Parent then
                teleportFollowAndLock(target, hrp, followTarget)
                -- after target gone or toggle off, small pause then continue
                if not Running or not Options.BrainrotLockToggle.Value then break end
                task.wait(0.12)
            end
        end

        task.wait(0.5)
    end

    -- finished -> restore
    stopAll()
end

-- hook toggle
BrainrotLockToggle:OnChanged(function(enabled)
    if enabled then
        if not Running then
            task.spawn(function()
                runner()
            end)
        end
    else
        stopAll()
    end
end)

-- Toggle UI Auto ItemSell
local SellToggle = Tabs.Auto:AddToggle("AutoItemSellToggle", {Title = "Auto Sell Plants", Default = false})
local SellRunning = false

-- ฟังก์ชันยิง Remote
local function FireItemSell()
    game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("ItemSell"):FireServer()
end

-- Loop ทำงาน
local function AutoSellLoop()
    SellRunning = true
    while SellRunning and Options.AutoItemSellToggle.Value do
        FireItemSell()
        print("[AutoSell] Fired ItemSell remote")
        -- รอรอบถัดไป 32 วิ
        for i = 1, 100 do
            if not Options.AutoItemSellToggle.Value then break end
            task.wait(1)
        end
    end
end

-- เมื่อ Toggle ถูกเปลี่ยนค่า
SellToggle:OnChanged(function()
    if Options.AutoItemSellToggle.Value then
        if not SellRunning then
            task.spawn(AutoSellLoop)
        end
    else
        SellRunning = false
    end
end)

-- ============================
-- Teleport Dropdown example
-- ============================
do
    local selectedZone = "Plots 1"
    local Dropdown = Tabs.Teleport:AddDropdown("Teleport", {
        Title = "Select to Teleport",
        Values = {"Plots 1", "Plots 2","Plots 3","Plots 4", "Plots 5", "Plots 6"},
        Multi = false,
        Default = 1,
    })
    Dropdown:SetValue("Plots 1")
    Dropdown:OnChanged(function(Value) selectedZone = Value end)

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
                            local player = LocalPlayer
                            local char = player.Character or player.CharacterAdded:Wait()
                            local hrp = char:WaitForChild("HumanoidRootPart")
                            if selectedZone == "Plots 1" then
                                hrp.CFrame = CFrame.new(73.81974029541016, 10, 641.0382080078125)
                            elseif selectedZone == "Plots 2" then
                                hrp.CFrame = CFrame.new(-27.180259704589844, 10, 635.0382080078125)
                            elseif selectedZone == "Plots 3" then
                                hrp.CFrame = CFrame.new(-128.38168334960938, 10, 641.0382080078125)
                            elseif selectedZone == "Plots 4" then
                                hrp.CFrame = CFrame.new(-229.6109161376953, 10, 641.0382080078125)
                            elseif selectedZone == "Plots 5" then
                                hrp.CFrame = CFrame.new(-330.8679504394531, 10, 641.0382080078125)
                            elseif selectedZone == "Plots 6" then
                                hrp.CFrame = CFrame.new(-432.0971984863281, 10, 641.0382080078125)
                            end
                            print("Teleported to " .. selectedZone)
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
end

-- ============================
-- Speed & Jump sliders (ปรับให้เช็คความถี่ต่ำลง)
-- ============================
do
    local Humanoid = nil
    local CurrentWalkSpeed = 16
    local CurrentJumpPower = 50

    local function getHumanoidNow()
        local char = LocalPlayer.Character
        if not char then return nil end
        return char:FindFirstChildWhichIsA("Humanoid")
    end

    local function setWalkSpeed(v)
        CurrentWalkSpeed = v
        Humanoid = getHumanoidNow()
        if Humanoid then
            pcall(function() Humanoid.WalkSpeed = v end)
        end
    end

    local function setJumpPower(v)
        CurrentJumpPower = v
        Humanoid = getHumanoidNow()
        if Humanoid then
            pcall(function() Humanoid.JumpPower = v end)
        end
    end

    LocalPlayer.CharacterAdded:Connect(function(char)
        task.wait(1)
        local h = getHumanoidNow()
        if h then
            pcall(function()
                h.WalkSpeed = CurrentWalkSpeed
                h.JumpPower = CurrentJumpPower
            end)
        end
    end)

    -- Throttled enforcement (every 0.25s) แทนการเชื่อมต่อ Stepped ต่อเฟรม
    task.spawn(function()
        while true do
            if Fluent.Unloaded then break end
            Humanoid = getHumanoidNow()
            if Humanoid then
                if Humanoid.WalkSpeed ~= CurrentWalkSpeed then
                    pcall(function() Humanoid.WalkSpeed = CurrentWalkSpeed end)
                end
                if Humanoid.JumpPower ~= CurrentJumpPower then
                    pcall(function() Humanoid.JumpPower = CurrentJumpPower end)
                end
            end
            task.wait(0.25) -- ลดความถี่จากทุกเฟรม -> 4 ครั้ง/วินาที
        end
    end)

    local speedSlider = Tabs.Players:AddSlider("WalkSpeedSlider", {
        Title = "WalkSpeed",
        Default = 16, Min = 8, Max = 200, Rounding = 0,
        Callback = function(Value) setWalkSpeed(Value) end
    })
    speedSlider:OnChanged(setWalkSpeed)

    local jumpSlider = Tabs.Players:AddSlider("JumpPowerSlider", {
        Title = "JumpPower",
        Default = 50, Min = 10, Max = 300, Rounding = 0,
        Callback = function(Value) setJumpPower(Value) end
    })
    jumpSlider:OnChanged(setJumpPower)
end

-- ============================
-- Fly & Noclip (เก็บให้เบาและเสถียร)
-- ============================
do
    local state = { flyEnabled = false, noclipEnabled = false }
    local bindName = "ATG_FlyStep"
    local fly = { bv = nil, bg = nil, speed = 60, smoothing = 0.35, bound = false }
    local savedCanCollide = {}

    local function getHRP()
        local char = LocalPlayer.Character
        if not char then char = LocalPlayer.CharacterAdded:Wait() end
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function createForces(hrp)
        if not hrp then return end
        if not fly.bv then
            fly.bv = Instance.new("BodyVelocity")
            fly.bv.Name = "ATG_Fly_BV"
            fly.bv.MaxForce = Vector3.new(9e9,9e9,9e9)
            fly.bv.P = 1250
        end
        if not fly.bg then
            fly.bg = Instance.new("BodyGyro")
            fly.bg.Name = "ATG_Fly_BG"
            fly.bg.MaxTorque = Vector3.new(9e9,9e9,9e9)
        end
        fly.bv.Parent = hrp
        fly.bg.Parent = hrp
    end

    local function destroyForces()
        if fly.bv then pcall(function() fly.bv:Destroy() end) fly.bv = nil end
        if fly.bg then pcall(function() fly.bg:Destroy() end) fly.bg = nil end
    end

    local function bindFlyStep()
        if fly.bound then return end
        fly.bound = true
        RunService:BindToRenderStep(bindName, Enum.RenderPriority.Character.Value + 1, function()
            if Fluent and Fluent.Unloaded then
                destroyForces()
                if fly.bound then pcall(function() RunService:UnbindFromRenderStep(bindName) end) fly.bound = false end
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
            local moveDir = Vector3.new()
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir += camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir -= camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir -= camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir += camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir += Vector3.new(0,1,0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir -= Vector3.new(0,1,0) end
            local targetVel = Vector3.new()
            if moveDir.Magnitude > 0 then targetVel = moveDir.Unit * fly.speed end
            fly.bv.Velocity = fly.bv.Velocity:Lerp(targetVel, fly.smoothing)
            fly.bg.CFrame = camCF
        end)
    end

    local function unbindFlyStep()
        if fly.bound then pcall(function() RunService:UnbindFromRenderStep(bindName) end) fly.bound = false end
    end

    local function enableFly(enable)
        state.flyEnabled = enable and true or false
        if enable then
            local hrp = getHRP()
            if not hrp then notify("Fly", "ไม่พบ HumanoidRootPart", 3); state.flyEnabled = false; return end
            createForces(hrp); bindFlyStep(); notify("Fly", "Fly enabled", 3)
        else
            destroyForces(); unbindFlyStep(); notify("Fly", "Fly disabled", 2)
        end
    end

    local function setNoclip(enable)
        state.noclipEnabled = enable and true or false
        if enable then
            local char = LocalPlayer.Character
            if not char then notify("Noclip", "Character not ready", 2); return end
            savedCanCollide = {}
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    savedCanCollide[part] = part.CanCollide
                    pcall(function() part.CanCollide = false end)
                end
            end
            notify("Noclip", "Noclip enabled", 3)
        else
            for part, val in pairs(savedCanCollide) do
                if part and part.Parent then pcall(function() part.CanCollide = val end) end
            end
            savedCanCollide = {}
            notify("Noclip", "Noclip disabled", 2)
        end
    end

    LocalPlayer.CharacterAdded:Connect(function(char)
        task.wait(0.15)
        if state.noclipEnabled then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then pcall(function() part.CanCollide = false end) end
            end
        end
        if state.flyEnabled then
            local hrp = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5)
            if hrp then createForces(hrp) end
            bindFlyStep()
        end
    end)

    local flyToggle = Tabs.Players:AddToggle("FlyToggle", { Title = "Fly", Default = false })
    flyToggle:OnChanged(function(v) enableFly(v) end)

    local flySpeedSlider = Tabs.Players:AddSlider("FlySpeedSlider", {
        Title = "Fly Speed", Description = "ปรับความเร็วการบิน", Default = fly.speed, Min = 10, Max = 350, Rounding = 0,
        Callback = function(v) fly.speed = v end
    })
    flySpeedSlider:SetValue(fly.speed)

    local noclipToggle = Tabs.Players:AddToggle("NoclipToggle", { Title = "Noclip", Default = false })
    noclipToggle:OnChanged(function(v) setNoclip(v) end)

    Tabs.Players:AddKeybind("FlyKey", {
        Title = "Fly Key (Toggle)", Mode = "Toggle", Default = "None",
        Callback = function(val) enableFly(val); pcall(function() flyToggle:SetValue(val) end) end
    })

    task.spawn(function()
        while true do
            if Fluent and Fluent.Unloaded then enableFly(false); setNoclip(false); break end
            task.wait(0.5)
        end
    end)
end

-- ส่วนฟังก์ชัน Toggle UI: Boost FPS / Fast Mode / Ultra Boost FPS
-- ใส่บล็อกนี้ตรงที่มีตัวแปร Fluent, Tabs (เช่น Tabs.Main) อยู่แล้ว
-- โค้ดนี้เป็น LocalScript (รันฝั่ง client) — ออกแบบให้ไม่ทำลายของเดิมถ้าปิดกลับคืนได้

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- เก็บสถานะเดิมเพื่อ restore เวลาปิด
local _saved = {
    lighting = {},
    particles = {},      -- [instance] = originalEnabled
    effects = {},        -- smoke/fire etc
    decals = {},         -- [instance] = originalTransparency / TextureId
    meshparts = {},      -- [instance] = originalTextureId
    parts = {},          -- [instance] = {Material = ..., Color = ..., LocalTransparencyModifier = ...}
}

-- เก็บ connections ที่ต้องปิดเวลายกเลิก
local _connections = {
    descendantAdded = nil,
    heartbeat = nil
}

-- ช่วยตรวจว่าจะข้ามส่วนของตัวละคร localplayer ไหม (เพื่อไม่ให้มองไม่เห็นตัวเอง)
local function isInLocalCharacter(inst)
    local char = LocalPlayer and LocalPlayer.Character
    return char and inst:IsDescendantOf(char)
end

-- ฟังก์ชันช่วย set/restore โปรพอร์ตี้ ปลอดภัยด้วย pcall
local function safeSet(obj, prop, value)
    pcall(function() obj[prop] = value end)
end

local function safeGet(obj, prop)
    local ok, v = pcall(function() return obj[prop] end)
    if ok then return v end
    return nil
end

-- =========================
-- 1) BOOST FPS (เบสิค) : ลดโหลด effect ที่กิน fps เล็กน้อย แต่ไม่ทำให้เกมมืด/แปลกมาก
-- ทำอะไร: ปิด particle, fire, smoke, trail, beam, global shadows
-- =========================
local function applyBoostFPS(enable)
    if enable then
        -- save lighting
        _saved.lighting.GlobalShadows = safeGet(Lighting, "GlobalShadows")
        _saved.lighting.Brightness = safeGet(Lighting, "Brightness")
        _saved.lighting.Ambient = safeGet(Lighting, "Ambient")
        _saved.lighting.OutdoorAmbient = safeGet(Lighting, "OutdoorAmbient")

        -- set lighter settings
        safeSet(Lighting, "GlobalShadows", false)
        -- don't set brightness to 0 to avoid blindness; just keep safe default
        safeSet(Lighting, "Brightness", (_saved.lighting.Brightness or 2) * 0.8)

        -- iterate ปิด emitter/effect ที่กิน fps
        for _, v in pairs(Workspace:GetDescendants()) do
            if isInLocalCharacter(v) then continue end

            -- ParticleEmitter / Trail / Beam
            if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") then
                if _saved.particles[v] == nil then
                    _saved.particles[v] = v.Enabled
                end
                safeSet(v, "Enabled", false)
            end

            -- Fire, Smoke, Sparkles
            if v:IsA("Fire") or v:IsA("Smoke") or v:IsA("Sparkles") then
                if _saved.effects[v] == nil then
                    _saved.effects[v] = v.Enabled
                end
                safeSet(v, "Enabled", false)
            end

            -- Decals / Texture: เพิ่มกรณีแค่ทำให้โปร่ง (แต่ไม่ลบ) — ลด draw calls
            if v:IsA("Decal") or v:IsA("Texture") then
                if _saved.decals[v] == nil then
                    _saved.decals[v] = {Transparency = safeGet(v, "Transparency"), Texture = safeGet(v, "Texture") or safeGet(v, "TextureId")}
                end
                -- ทำให้โปร่งขึ้น แต่ไม่เอาออกทั้งหมด
                safeSet(v, "Transparency", math.clamp((v.Transparency or 0) + 0.5, 0, 1))
            end
        end

        -- connection: ถ้ามี object ใหม่ที่ spawn เข้ามา ให้ปิด emitter ทันที
        _connections.descendantAdded = Workspace.DescendantAdded:Connect(function(desc)
            if isInLocalCharacter(desc) then return end
            if desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
                if _saved.particles[desc] == nil then _saved.particles[desc] = desc.Enabled end
                safeSet(desc, "Enabled", false)
            end
            if desc:IsA("Fire") or desc:IsA("Smoke") or desc:IsA("Sparkles") then
                if _saved.effects[desc] == nil then _saved.effects[desc] = desc.Enabled end
                safeSet(desc, "Enabled", false)
            end
        end)
    else
        -- restore lighting
        safeSet(Lighting, "GlobalShadows", _saved.lighting.GlobalShadows)
        safeSet(Lighting, "Brightness", _saved.lighting.Brightness)
        safeSet(Lighting, "Ambient", _saved.lighting.Ambient)
        safeSet(Lighting, "OutdoorAmbient", _saved.lighting.OutdoorAmbient)
        _saved.lighting = {}

        -- restore particles/effects/decals
        for inst, orig in pairs(_saved.particles) do
            if inst and inst.Parent then safeSet(inst, "Enabled", orig) end
        end
        _saved.particles = {}

        for inst, orig in pairs(_saved.effects) do
            if inst and inst.Parent then safeSet(inst, "Enabled", orig) end
        end
        _saved.effects = {}

        for inst, orig in pairs(_saved.decals) do
            if inst and inst.Parent then
                pcall(function()
                    inst.Transparency = orig.Transparency or 0
                    if orig.Texture then
                        -- some have Texture or TextureId
                        if inst:IsA("Decal") then inst.Texture = orig.Texture end
                        if inst:IsA("Texture") then inst.Texture = orig.Texture end
                    end
                end)
            end
        end
        _saved.decals = {}

        -- disconnect
        if _connections.descendantAdded then
            _connections.descendantAdded:Disconnect()
            _connections.descendantAdded = nil
        end
    end
end

-- =========================
-- 2) FAST MODE : ลบ/ปิดเท็กเจอร์ทั้งหมด (ทำแมพเป็นพื้นแบบเรียบ ดิน/น้ำมัน) เพื่อให้ fps ดีขึ้น
-- ทำอะไร: เซ็ต MeshPart.TextureId = "" / Decal.Texture = "" / SurfaceAppearance maps = nil
-- เปลี่ยน Material เป็น SmoothPlastic และเปลี่ยนสีเป็นโทนดิน (configurable)
-- =========================
local FAST_COLOR = Color3.fromRGB(117, 85, 61) -- สีพื้นดินแบบคร่าว ๆ (เปลี่ยนได้)

local function applyFastMode(enable)
    if enable then
        -- เดินดูทุก instance เก็บสถานะเดิมแล้วเปลี่ยน
        for _, v in pairs(Workspace:GetDescendants()) do
            if isInLocalCharacter(v) then continue end

            -- BasePart: เก็บ Material/Color/LocalTransparencyModifier แล้วเปลี่ยนเป็น SmoothPlastic + สีดิน
            if v:IsA("BasePart") then
                if _saved.parts[v] == nil then
                    _saved.parts[v] = {
                        Material = safeGet(v, "Material"),
                        Color = safeGet(v, "Color"),
                        LocalTransparencyModifier = safeGet(v, "LocalTransparencyModifier")
                    }
                end
                pcall(function()
                    v.Material = Enum.Material.SmoothPlastic
                    v.Color = FAST_COLOR
                    v.LocalTransparencyModifier = 0 -- ให้มองเห็น แต่เป็นสีเรียบ
                end)
            end

            -- MeshPart: เคลียร์ texture
            if v:IsA("MeshPart") then
                if _saved.meshparts[v] == nil then
                    _saved.meshparts[v] = {TextureId = safeGet(v, "TextureID")}
                end
                pcall(function() v.TextureID = "" end)
            end

            -- Decal/Texture: เคลียร์
            if v:IsA("Decal") or v:IsA("Texture") then
                if _saved.decals[v] == nil then
                    _saved.decals[v] = {Transparency = safeGet(v, "Transparency"), Texture = safeGet(v, "Texture") or safeGet(v, "TextureId")}
                end
                pcall(function()
                    if v:IsA("Decal") then v.Texture = "" end
                    if v:IsA("Texture") then v.Texture = "" end
                    v.Transparency = 0
                end)
            end

            -- SurfaceAppearance: ไม่สามารถลบ map ได้ง่าย ๆ แต่เราสามารถซ่อนโดยเพิ่ม LocalTransparencyModifier ในพาร์ทที่มีมัน
            if v:IsA("SurfaceAppearance") and v.Parent and v.Parent:IsA("BasePart") then
                local part = v.Parent
                if _saved.parts[part] == nil then
                    _saved.parts[part] = {
                        Material = safeGet(part, "Material"),
                        Color = safeGet(part, "Color"),
                        LocalTransparencyModifier = safeGet(part, "LocalTransparencyModifier")
                    }
                end
                pcall(function()
                    part.Material = Enum.Material.SmoothPlastic
                    part.Color = FAST_COLOR
                end)
            end
        end

        -- connection: new objects ที่เพิ่มเข้ามา ให้ apply แบบเดียวกัน
        _connections.descendantAdded = Workspace.DescendantAdded:Connect(function(desc)
            if isInLocalCharacter(desc) then return end
            -- ทำเหมือนข้างบน (เร็วๆ)
            if desc:IsA("BasePart") then
                if _saved.parts[desc] == nil then
                    _saved.parts[desc] = {Material = safeGet(desc, "Material"), Color = safeGet(desc, "Color"), LocalTransparencyModifier = safeGet(desc, "LocalTransparencyModifier")}
                end
                pcall(function() desc.Material = Enum.Material.SmoothPlastic; desc.Color = FAST_COLOR end)
            end
            if desc:IsA("MeshPart") then
                if _saved.meshparts[desc] == nil then _saved.meshparts[desc] = {TextureId = safeGet(desc, "TextureID")} end
                pcall(function() desc.TextureID = "" end)
            end
            if desc:IsA("Decal") or desc:IsA("Texture") then
                if _saved.decals[desc] == nil then _saved.decals[desc] = {Transparency = safeGet(desc, "Transparency"), Texture = safeGet(desc, "Texture") or safeGet(desc, "TextureId")} end
                pcall(function() if desc:IsA("Decal") then desc.Texture = "" end; if desc:IsA("Texture") then desc.Texture = "" end; desc.Transparency = 0 end)
            end
        end)
    else
        -- restore parts
        for inst, orig in pairs(_saved.parts) do
            if inst and inst.Parent then
                pcall(function()
                    if orig.Material then inst.Material = orig.Material end
                    if orig.Color then inst.Color = orig.Color end
                    if orig.LocalTransparencyModifier then inst.LocalTransparencyModifier = orig.LocalTransparencyModifier end
                end)
            end
        end
        _saved.parts = {}

        for inst, orig in pairs(_saved.meshparts) do
            if inst and inst.Parent then
                pcall(function() inst.TextureID = orig.TextureId end)
            end
        end
        _saved.meshparts = {}

        for inst, orig in pairs(_saved.decals) do
            if inst and inst.Parent then
                pcall(function()
                    if inst:IsA("Decal") and orig.Texture then inst.Texture = orig.Texture end
                    if inst:IsA("Texture") and orig.Texture then inst.Texture = orig.Texture end
                    if orig.Transparency then inst.Transparency = orig.Transparency end
                end)
            end
        end
        _saved.decals = {}

        if _connections.descendantAdded then
            _connections.descendantAdded:Disconnect()
            _connections.descendantAdded = nil
        end
    end
end

-- =========================
-- 3) ULTRA BOOST FPS : ปิด 3D ทุกอย่าง (local) และแสดงหน้าจอสีดำ
-- ทำอะไร: ซ่อนทุก BasePart (LocalTransparencyModifier = 1) ยกเว้นตัวละครของผู้เล่นท้องถิ่น (optionally)
-- สร้าง ScreenGui สีดำทับหน้าจอ และปิด particle/effect/sky/shadows
-- =========================
local _ultraGui = nil
local _ultraHiddenParts = {} -- เก็บ LocalTransparencyModifier ก่อนหน้า

local function applyUltraBoost(enable)
    if enable then
        -- สร้าง black overlay full-screen
        if not LocalPlayer or not LocalPlayer:FindFirstChild("PlayerGui") then
            -- ถ้าไม่มี PlayerGui ให้รอ 1s แล้วลองอีกที
            for i = 1, 5 do
                task.wait(0.2)
                if LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") then break end
            end
        end

        if LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") then
            _ultraGui = Instance.new("ScreenGui")
            _ultraGui.Name = "UltraBoostBlackout"
            _ultraGui.ResetOnSpawn = false
            _ultraGui.IgnoreGuiInset = true
            _ultraGui.Parent = LocalPlayer.PlayerGui

            local frame = Instance.new("Frame")
            frame.Size = UDim2.fromScale(1,1)
            frame.Position = UDim2.fromScale(0,0)
            frame.BackgroundColor3 = Color3.new(0,0,0)
            frame.BorderSizePixel = 0
            frame.ZIndex = 999999
            frame.Parent = _ultraGui
        end

        -- save and hide parts (ยกเว้นตัวละคร local player เพื่อไม่ให้หาย)
        for _, v in pairs(Workspace:GetDescendants()) do
            if v:IsA("BasePart") then
                if isInLocalCharacter(v) then continue end
                if _ultraHiddenParts[v] == nil then
                    _ultraHiddenParts[v] = safeGet(v, "LocalTransparencyModifier")
                end
                pcall(function() v.LocalTransparencyModifier = 1 end)
            end

            -- ปิด particle / effects
            if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") or v:IsA("Fire") or v:IsA("Smoke") or v:IsA("Sparkles") then
                if _saved.particles[v] == nil then _saved.particles[v] = safeGet(v, "Enabled") end
                pcall(function() v.Enabled = false end)
            end
        end

        -- ปรับ lighting ให้มืด
        _saved.lighting.Brightness = safeGet(Lighting, "Brightness")
        _saved.lighting.GlobalShadows = safeGet(Lighting, "GlobalShadows")
        safeSet(Lighting, "Brightness", 0)
        safeSet(Lighting, "GlobalShadows", false)
        safeSet(Lighting, "Ambient", Color3.new(0,0,0))
        safeSet(Lighting, "OutdoorAmbient", Color3.new(0,0,0))

        -- ถ้ามี object ใหม่ ให้ซ่อนทันที
        _connections.descendantAdded = Workspace.DescendantAdded:Connect(function(desc)
            if desc:IsA("BasePart") then
                if isInLocalCharacter(desc) then return end
                if _ultraHiddenParts[desc] == nil then _ultraHiddenParts[desc] = safeGet(desc, "LocalTransparencyModifier") end
                pcall(function() desc.LocalTransparencyModifier = 1 end)
            end
            if desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") or desc:IsA("Fire") or desc:IsA("Smoke") or desc:IsA("Sparkles") then
                if _saved.particles[desc] == nil then _saved.particles[desc] = safeGet(desc, "Enabled") end
                pcall(function() desc.Enabled = false end)
            end
        end)

        -- heartbeat: บางเกมรีเซ็ต LocalTransparencyModifier บ่อย ให้เราตรวจซ้ำ
        _connections.heartbeat = RunService.Heartbeat:Connect(function()
            for inst, prev in pairs(_ultraHiddenParts) do
                if inst and inst.Parent and not isInLocalCharacter(inst) then
                    pcall(function() inst.LocalTransparencyModifier = 1 end)
                end
            end
        end)
    else
        -- restore parts
        for inst, orig in pairs(_ultraHiddenParts) do
            if inst and inst.Parent then
                pcall(function() inst.LocalTransparencyModifier = orig or 0 end)
            end
        end
        _ultraHiddenParts = {}

        -- restore particles
        for inst, orig in pairs(_saved.particles) do
            if inst and inst.Parent then pcall(function() inst.Enabled = orig end) end
        end
        _saved.particles = {}

        -- restore lighting
        safeSet(Lighting, "Brightness", _saved.lighting.Brightness or 2)
        safeSet(Lighting, "GlobalShadows", _saved.lighting.GlobalShadows)
        safeSet(Lighting, "Ambient", _saved.lighting.Ambient or Color3.new(0.5,0.5,0.5))
        safeSet(Lighting, "OutdoorAmbient", _saved.lighting.OutdoorAmbient or Color3.new(0.5,0.5,0.5))
        _saved.lighting = {}

        -- remove overlay gui
        if _ultraGui and _ultraGui.Parent then
            pcall(function() _ultraGui:Destroy() end)
            _ultraGui = nil
        end

        -- disconnect connections
        if _connections.descendantAdded then
            _connections.descendantAdded:Disconnect()
            _connections.descendantAdded = nil
        end
        if _connections.heartbeat then
            _connections.heartbeat:Disconnect()
            _connections.heartbeat = nil
        end
    end
end

-- =========================
-- สร้าง Toggle UI (Fluent) — ใส่บรรทัดนี้ตรงที่สร้าง Tabs.Main
-- =========================
-- ตัวอย่างการเชื่อมต่อกับ Fluent UI (สมมติ Tabs.Main มีอยู่แล้ว)
local BoostToggle = Tabs.FPS:AddToggle("BoostFPS", { Title = "Boost FPS", Default = false, Description = "ปิด particle / effect เล็กน้อย + ปรับ lighting เล็กน้อย เพื่อเพิ่ม FPS" })
BoostToggle:OnChanged(function()
    applyBoostFPS(BoostToggle.Value)
end)

local FastToggle = Tabs.FPS:AddToggle("FastMode", { Title = "Fast Mode", Default = false, Description = "ลบเท็กซ์เจอร์และเปลี่ยนวัสดุเป็นเรียบๆ (แมพจะกลายเป็นพื้นเรียบดิน)" })
FastToggle:OnChanged(function()
    applyFastMode(FastToggle.Value)
end)

local UltraToggle = Tabs.FPS:AddToggle("UltraBoost", { Title = "Ultra Boost FPS", Default = false, Description = "ปิด 3D ทั้งหมดและแสดงหน้าจอดำ — สำหรับไล่ FPS สูงสุด (local only)" })
UltraToggle:OnChanged(function()
    applyUltraBoost(UltraToggle.Value)
end)

-- หมายเหตุสำคัญ:
-- 1) โค้ดนี้ทำงานฝั่ง client เท่านั้น — เปลี่ยนเฉพาะสิ่งที่ผู้เล่นคนนั้นมองเห็น ไม่ส่งผลกับผู้เล่นคนอื่น (ยกเว้น server script ถูกออกแบบให้แก้)
-- 2) ถ้าเกมมีระบบ anti-exploit หรือ server อิงสภาพแวดล้อม client บางฟังก์ชันอาจถูกรีเซ็ตโดย server หรือโดยเกมเอง
-- 3) ถ้าต้องการให้ไม่กระทบตัวละครของผู้เล่น ให้ปรับ isInLocalCharacter เพื่อรวม/ยกเว้นตามต้องการ
-- 4) ถ้าต้องการค่าโทนดิน/สีอื่น ปรับตัวแปร FAST_COLOR ด้านบน

-- ============================
-- Improved ESP (centralized throttled updater)
-- ============================
do
    local espState = {
        enabled = false,
        color = Color3.fromRGB(255,50,50),
        showName = true,
        showHealth = true,
        showDistance = true,
        espTable = {}, -- player -> { billboard, label, charConn }
        updateInterval = 0.18, -- seconds (ปรับได้เพื่อ trade-off ระหว่างความสดใหม่และ FPS)
    }

    local function createBillboard(head)
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "ATG_ESP"
        billboard.Size = UDim2.new(0, 160, 0, 28)
        billboard.StudsOffset = Vector3.new(0, 2.4, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = head

        local label = Instance.new("TextLabel")
        label.Name = "ATG_ESP_Label"
        label.Size = UDim2.fromScale(1,1)
        label.BackgroundTransparency = 1
        label.BorderSizePixel = 0
        label.Text = ""
        label.TextScaled = false
        label.TextSize = 14
        label.Font = Enum.Font.GothamBold
        label.TextColor3 = espState.color
        label.TextStrokeTransparency = 0.4
        label.TextStrokeColor3 = Color3.new(0,0,0)
        label.TextWrapped = true
        label.Parent = billboard

        return billboard, label
    end

    local function attachToCharacter(p)
        if not espState.enabled then return end
        if not p.Character or not p.Character.Parent then return end
        local head = p.Character:FindFirstChild("Head")
        if not head then return end
        -- cleanup if exists
        if espState.espTable[p] and espState.espTable[p].billboard then
            pcall(function() espState.espTable[p].billboard:Destroy() end)
        end
        local billboard, label = createBillboard(head)
        espState.espTable[p] = espState.espTable[p] or {}
        espState.espTable[p].billboard = billboard
        espState.espTable[p].label = label
    end

    local function removeESPForPlayer(p)
        local info = espState.espTable[p]
        if not info then return end
        pcall(function()
            if info.billboard then info.billboard:Destroy() end
            if info.charConn then info.charConn:Disconnect() end
        end)
        espState.espTable[p] = nil
    end

    -- Central updater: one loop updates all labels at espState.updateInterval
    task.spawn(function()
        local acc = 0
        local last = tick()
        while true do
            if Fluent.Unloaded then break end
            local now = tick()
            local dt = now - last
            last = now
            acc = acc + dt
            if espState.enabled and acc >= espState.updateInterval then
                acc = 0
                -- prepare local refs
                local myHRP = nil
                local myChar = LocalPlayer.Character
                if myChar then myHRP = myChar:FindFirstChild("HumanoidRootPart") end
                for p, info in pairs(espState.espTable) do
                    if not p or not p.Character or not p.Character.Parent or not info or not info.label then
                        removeESPForPlayer(p)
                    else
                        local parts = {}
                        if espState.showName then table.insert(parts, p.DisplayName or p.Name) end
                        if espState.showHealth then
                            local hum = p.Character:FindFirstChildOfClass("Humanoid")
                            if hum then table.insert(parts, "HP:" .. math.floor(hum.Health)) end
                        end
                        if espState.showDistance and myHRP then
                            local theirHRP = p.Character:FindFirstChild("HumanoidRootPart")
                            if theirHRP then
                                local d = math.floor((myHRP.Position - theirHRP.Position).Magnitude)
                                table.insert(parts, "[" .. d .. "m]")
                            end
                        end
                        info.label.Text = table.concat(parts, " | ")
                        info.label.TextColor3 = espState.color
                    end
                end
            end
            task.wait(0.03) -- light sleep to avoid busy loop
        end
    end)

    -- Player join/leave handlers
    Players.PlayerAdded:Connect(function(p)
        task.delay(0.5, function()
            if espState.enabled and p ~= LocalPlayer then
                if p.Character and p.Character.Parent then
                    attachToCharacter(p)
                end
                -- connect to CharacterAdded to attach new billboards on spawn
                espState.espTable[p] = espState.espTable[p] or {}
                if espState.espTable[p].charConn then espState.espTable[p].charConn:Disconnect() end
                espState.espTable[p].charConn = p.CharacterAdded:Connect(function(c) task.wait(0.05); if espState.enabled then attachToCharacter(p) end end)
            end
        end)
    end)
    Players.PlayerRemoving:Connect(function(p) removeESPForPlayer(p) end)

    -- UI controls
    local espToggle = Tabs.ESP:AddToggle("ESPToggle", { Title = "ESP", Default = false })
    espToggle:OnChanged(function(v)
        espState.enabled = v
        if not v then
            for p,_ in pairs(espState.espTable) do removeESPForPlayer(p) end
        else
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then
                    if p.Character and p.Character.Parent then attachToCharacter(p) end
                    espState.espTable[p] = espState.espTable[p] or {}
                    if espState.espTable[p].charConn then espState.espTable[p].charConn:Disconnect() end
                    espState.espTable[p].charConn = p.CharacterAdded:Connect(function() task.wait(0.05); if espState.enabled then attachToCharacter(p) end end)
                end
            end
        end
    end)

    local espColorPicker = Tabs.ESP:AddColorpicker("ESPColor", { Title = "ESP Color", Default = espState.color })
    espColorPicker:OnChanged(function(c) espState.color = c end)

    Tabs.ESP:AddToggle("ESP_ShowName", { Title = "Show Name", Default = espState.showName }):OnChanged(function(v) espState.showName = v end)
    Tabs.ESP:AddToggle("ESP_ShowHealth", { Title = "Show Health", Default = espState.showHealth }):OnChanged(function(v) espState.showHealth = v end)
    Tabs.ESP:AddToggle("ESP_ShowDistance", { Title = "Show Distance", Default = espState.showDistance }):OnChanged(function(v) espState.showDistance = v end)
end

-- ============================
-- Teleport to Player (dropdown)
-- ============================
do
    local playerListDropdown = Tabs.Teleport:AddDropdown("TeleportToPlayerDropdown", { Title = "Select Player to Teleport", Values = {}, Multi = false, Default = 1 })

    local function refreshPlayerDropdown()
        local vals = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then table.insert(vals, p.Name) end
        end
        if #vals == 0 then vals = {"No other players"} end
        playerListDropdown:SetValues(vals)
        playerListDropdown:SetValue(vals[1])
    end

    refreshPlayerDropdown()
    Players.PlayerAdded:Connect(function() task.delay(0.5, refreshPlayerDropdown) end)
    Players.PlayerRemoving:Connect(function() task.delay(0.5, refreshPlayerDropdown) end)

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
end

-- ============================
-- Anti-AFK
-- ============================
do
    local vu = nil
    local function enableAntiAFK(enable)
        if enable then
            if not vu then pcall(function() vu = game:GetService("VirtualUser") end) end
            if vu then
                Players.LocalPlayer.Idled:Connect(function()
                    pcall(function() vu:Button2Down(Vector2.new(0,0)); task.wait(1); vu:Button2Up(Vector2.new(0,0)) end)
                end)
            end
            notify("Anti-AFK", "Anti-AFK enabled", 3)
        else
            notify("Anti-AFK", "Anti-AFK disabled (client may still have other handlers)", 3)
        end
    end

    local antiAFKToggle = Tabs.Settings:AddToggle("AntiAFKToggle", { Title = "Anti-AFK", Default = true })
    antiAFKToggle:OnChanged(function(v) enableAntiAFK(v) end)
    antiAFKToggle:SetValue(true)
    enableAntiAFK(true)
end

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

    Tabs.Settings:AddButton({
        Title = "Server Hop",
        Description = "Join a different random server instance.",
        Callback = function()
            local serverId = findServer()
            if serverId then TeleportService:TeleportToPlaceInstance(game.PlaceId, serverId, LocalPlayer) else warn("No available servers found!") end
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

    Tabs.Settings:AddButton({
        Title = "Lower Server",
        Description = "Join the server with the least number of players.",
        Callback = function()
            local serverId = findLowestServer()
            if serverId then TeleportService:TeleportToPlaceInstance(game.PlaceId, serverId, LocalPlayer) else warn("No available servers found!") end
        end
    })
end

-- ============================
-- SaveManager & InterfaceManager setup
-- ============================
InterfaceManager:SetLibrary(Fluent)
SaveManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("FluentScriptHub")
SaveManager:SetFolder("FluentScriptHub/specific-game")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)
SaveManager:LoadAutoloadConfig()

Window:SelectTab(1)

Fluent:Notify({ Title = "Fluent", Content = "The script has been loaded.", Duration = 8 })

-- Cleanup on unload
task.spawn(function()
    while true do
        if Fluent and Fluent.Unloaded then
            -- try to restore any forced states
            pcall(function() RunService:Set3dRenderingEnabled(true) end)
            break
        end
        task.wait(0.5)
    end
end)
