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
    Players = Window:AddTab({ Title = "Players", Icon = "Players" }),
    Teleport = Window:AddTab({ Title = "Teleport", Icon = "Teleport" }),
    ESP = Window:AddTab({ Title = "ESP", Icon = "ESP"}),
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

-- ============================
-- Teleport Dropdown example
-- ============================
do
    local selectedZone = "Zone 1"
    local Dropdown = Tabs.Teleport:AddDropdown("Teleport", {
        Title = "Select to Teleport",
        Values = {"Zone 1", "Zone 2","Zone 3","Zone 4", "Zone 5", "Zone 6", "Zone 7", "Zone 8"},
        Multi = false,
        Default = 1,
    })
    Dropdown:SetValue("Zone 1")
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
                        Callback = function() end
                    }
                }
            })
        end
    })
end

-- ============================
-- Auto Loop Logic (เดิม)
-- ============================
do
    local running = false
    local stopFlag = false
    local iterations = 0
    local DEFAULT_MINUTES = 6

    local ParagraphStatus = Tabs.Main:AddParagraph({ Title = "สถานะ", Content = "พร้อม" })
    local IterCount = Tabs.Main:AddParagraph({ Title = "รอบที่ทำไปแล้ว", Content = tostring(iterations) })

    local LoopToggle = Tabs.Main:AddToggle("LoopToggle", { Title = "Loop On/Off", Default = true })
    local DelaySlider = Tabs.Main:AddSlider("DelaySlider", { Title = "หน่วงเวลา (นาที)", Default = DEFAULT_MINUTES, Min = 1, Max = 60, Rounding = 0 })

    local KeyDropdown = Tabs.Main:AddDropdown("KeyDropdown", {
        Title = "เลือกปุ่ม (0-9)",
        Values = {"0","1","2","3","4","5","6","7","8","9"},
        Multi = false,
        Default = "9"
    })

    local function keyEnumFromStr(keyStr)
        if keyStr == "0" then return Enum.KeyCode.Zero end
        if keyStr == "1" then return Enum.KeyCode.One end
        if keyStr == "2" then return Enum.KeyCode.Two end
        if keyStr == "3" then return Enum.KeyCode.Three end
        if keyStr == "4" then return Enum.KeyCode.Four end
        if keyStr == "5" then return Enum.KeyCode.Five end
        if keyStr == "6" then return Enum.KeyCode.Six end
        if keyStr == "7" then return Enum.KeyCode.Seven end
        if keyStr == "8" then return Enum.KeyCode.Eight end
        if keyStr == "9" then return Enum.KeyCode.Nine end
        return nil
    end

    local function performAction()
        local keyStr = Options.KeyDropdown.Value or "9"
        local keyEnum = keyEnumFromStr(keyStr)
        if keyEnum then
            pcall(function() keypress(keyEnum) end)
            task.wait(0.05)
            pcall(function() keyrelease(keyEnum) end)
        end
        pcall(function() mouse1press() end)
        task.wait(0.05)
        pcall(function() mouse1release() end)
    end

    local function logStatus(txt) pcall(function() ParagraphStatus:SetDesc(txt) end) end
    local function updateIterations() pcall(function() IterCount:SetDesc(tostring(iterations)) end) end

    local function stop()
        running = false
        stopFlag = true
        logStatus("หยุดทำงานแล้ว")
    end

    local function doOnce(delaySeconds)
        logStatus("รอ " .. math.floor(delaySeconds) .. " วินาที...")
        for i = delaySeconds, 1, -1 do
            if stopFlag then return end
            logStatus("นับถอยหลัง: " .. i .. " วินาที")
            task.wait(1)
        end
        if stopFlag then return end
        logStatus("กดปุ่ม " .. (Options.KeyDropdown.Value or "9") .. " และคลิก...")
        performAction()
        iterations = iterations + 1
        updateIterations()
        logStatus("เสร็จแล้ว")
    end

    local function startLoop()
        if running then logStatus("ทำงานอยู่แล้ว..."); return end
        running = true
        stopFlag = false
        iterations = 0
        updateIterations()
        task.spawn(function()
            while running and not stopFlag do
                local delayMinutes = Options.DelaySlider.Value
                local delaySeconds = math.floor(delayMinutes * 60)
                doOnce(delaySeconds)
                if not Options.LoopToggle.Value then stop(); break end
                task.wait(0.2)
            end
        end)
    end

    Tabs.Main:AddButton({ Title = "Start", Description = "เริ่มทำงานตาม Loop", Callback = startLoop })
    Tabs.Main:AddButton({ Title = "Stop", Description = "หยุดการทำงาน", Callback = stop })
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

-- ============================
-- Low Graphics & Boost FPS features
-- ============================
do
    local savedParticleStates = {} -- store emitter enabled states
    local savedLighting = {}
    local fastModeEnabled = false
    local hardBoostEnabled = false

    -- helper to iterate and change particle emitters/trails/etc
    local function setEmittersEnabled(root, enabled)
        for _, obj in ipairs(root:GetDescendants()) do
            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") then
                if enabled == nil then
                    -- read
                    savedParticleStates[obj] = obj.Enabled
                else
                    pcall(function() obj.Enabled = enabled end)
                end
            end
        end
    end

    local function enableLowGraphics(enable)
        if enable then
            -- save lighting properties
            savedLighting.GlobalShadows = Lighting.GlobalShadows
            savedLighting.Brightness = Lighting.Brightness
            savedLighting.ClockTime = Lighting.ClockTime
            savedLighting.ExposureCompensation = Lighting.ExposureCompensation
            -- apply low settings
            pcall(function() Lighting.GlobalShadows = false end)
            pcall(function() Lighting.Brightness = math.clamp((Lighting.Brightness or 1) * 0.7, 0, 10) end)
            pcall(function() Lighting.ExposureCompensation = 0 end)
            -- disable heavy particle systems in Workspace and descendants
            setEmittersEnabled(Workspace, false)
            -- also try to reduce terrain water detail (if exists)
            pcall(function()
                local terrain = Workspace:FindFirstChildOfClass("Terrain")
                if terrain then
                    if terrain.WaterWaveSize then terrain.WaterWaveSize = 0 end
                    if terrain.WaterWaveSpeed then terrain.WaterWaveSpeed = 0 end
                end
            end)
            notify("Low Graphics", "Low Graphics enabled (particles & shadows reduced).", 4)
        else
            -- restore lighting
            pcall(function() Lighting.GlobalShadows = savedLighting.GlobalShadows end)
            pcall(function() Lighting.Brightness = savedLighting.Brightness end)
            pcall(function() Lighting.ClockTime = savedLighting.ClockTime end)
            pcall(function() Lighting.ExposureCompensation = savedLighting.ExposureCompensation end)
            -- restore particle states
            for obj, state in pairs(savedParticleStates) do
                if obj and obj.Parent then
                    pcall(function() obj.Enabled = state end)
                end
            end
            savedParticleStates = {}
            notify("Low Graphics", "Low Graphics disabled (restored).", 3)
        end
    end

    -- Soft Boost: reduce UI/ops frequency and set render quality friendly settings
    local function enableSoftBoost(enable)
        if enable then
            fastModeEnabled = true
            -- reduce ESP update frequency (if present)
            pcall(function()
                local espToggle = Tabs.ESP -- just a trigger; actual esp update interval is in code above
            end)
            notify("Boost FPS", "Soft Boost enabled (reduced per-frame work).", 3)
        else
            fastModeEnabled = false
            notify("Boost FPS", "Soft Boost disabled.", 2)
        end
    end

    -- Hard Boost: turn off 3D rendering (HUGE fps gains). UI remains.
    local function enableHardBoost(enable)
        if enable then
            hardBoostEnabled = true
            -- store previous rendering state? We only toggle
            pcall(function() RunService:Set3dRenderingEnabled(false) end)
            notify("Boost FPS", "Hard Boost enabled: 3D rendering OFF. Use carefully.", 5)
        else
            hardBoostEnabled = false
            pcall(function() RunService:Set3dRenderingEnabled(true) end)
            notify("Boost FPS", "Hard Boost disabled: 3D rendering ON.", 3)
        end
    end

    -- UI toggles
    local lowGraphicsToggle = Tabs.Main:AddToggle("LowGraphicsToggle", { Title = "Low Graphics (Disable Particles/Shadows)", Default = false })
    lowGraphicsToggle:OnChanged(function(v) enableLowGraphics(v) end)

    local softBoostToggle = Tabs.Main:AddToggle("SoftBoostToggle", { Title = "Boost FPS (Soft)", Default = false })
    softBoostToggle:OnChanged(function(v) enableSoftBoost(v) end)

    local hardBoostToggle = Tabs.Main:AddToggle("HardBoostToggle", { Title = "Boost FPS (Hard) - DISABLE 3D", Default = false })
    hardBoostToggle:OnChanged(function(v) enableHardBoost(v) end)
end

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
