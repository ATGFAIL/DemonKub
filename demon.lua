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
local playedTime = 0
local minutes = 0
local hours = 0
local content = ""

-- สร้าง Paragraph
infoParagraph = Tabs.Main:AddParagraph({
    Title = "Player Info",
    Content = "Loading player info..."
})

-- ฟังก์ชันอัพเดทข้อมูล
local function updateInfo()
    char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    hum = char:FindFirstChildWhichIsA("Humanoid")
    playedTime = tick() - startTime

    minutes = math.floor(playedTime / 60)
    hours = math.floor(minutes / 60)
    minutes = minutes % 60

    content = string.format([[
Name: %s (@%s)
UserId: %d

Health: %d / %d
WalkSpeed: %d
JumpPower: %d

Played Time: %dh %dm
]], 
        LocalPlayer.DisplayName, 
        LocalPlayer.Name, 
        LocalPlayer.UserId,
        hum and hum.Health or 0, 
        hum and hum.MaxHealth or 0,
        hum and hum.WalkSpeed or 0,
        hum and hum.JumpPower or 0,
        hours, minutes
    )

    infoParagraph:SetDesc(content)
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
local LocalPlayer = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local killAuraEnabled = false
local attackRemote = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("GeneralAttack") -- ปรับให้ตรงเกม

-- ระยะตรวจจับ NPC รอบตัว
local radius = 2000
-- ระยะวาปไปข้างๆเป้าหมาย
local offset = Vector3.new(3,0,0)

-- ฟังก์ชัน Kill Aura
local function doKillAura()
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    for _, model in ipairs(workspace:GetChildren()) do
        if model:IsA("Model") and model ~= char then
            local hum = model:FindFirstChildWhichIsA("Humanoid")
            local hrp2 = model:FindFirstChild("HumanoidRootPart")
            if hum and hrp2 and hum.Health > 0 then
                -- เช็คว่าไม่ใช่ผู้เล่น
                local plr = Players:GetPlayerFromCharacter(model)
                if not plr then
                    local dist = (hrp.Position - hrp2.Position).Magnitude
                    if dist <= radius then
                        -- วาปไปข้างๆเป้าหมาย
                        hrp.CFrame = hrp2.CFrame * CFrame.new(offset)
                        -- โจมตี
                        pcall(function()
                            attackRemote:FireServer(model)
                        end)
                    end
                end
            end
        end
    end
end

-- Toggle Kill Aura
local killButton = Tabs.Main:AddToggle("KillAuraToggle", {Title = "Kill Aura", Default = false})
killButton:OnChanged(function(v)
    killAuraEnabled = v
end)

-- loop ทำงานออโต้
RunService.RenderStepped:Connect(function()
    if killAuraEnabled then
        pcall(doKillAura)
    end
end)



    Tabs.Main:AddButton({
        Title = "Button",
        Description = "Very important button",
        Callback = function()
            Window:Dialog({
                Title = "Title",
                Content = "This is a dialog",
                Buttons = {
                    {
                        Title = "Confirm",
                        Callback = function()
                            print("Confirmed the dialog.")
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

spawn(function()
    while true do
        if isAttacking then
            game:GetService("ReplicatedStorage").RemoteEvents.GeneralAttack:FireServer(1)
        end
        wait(0.01) -- ปรับความเร็วได้
    end
end)



    
    local Slider = Tabs.Main:AddSlider("Slider", {
        Title = "Slider",
        Description = "This is a slider",
        Default = 2,
        Min = 0,
        Max = 5,
        Rounding = 1,
        Callback = function(Value)
            print("Slider was changed:", Value)
        end
    })

    Slider:OnChanged(function(Value)
        print("Slider changed:", Value)
    end)

    Slider:SetValue(3)


    local Dropdown = Tabs.Main:AddDropdown("Dropdown", {
        Title = "Dropdown",
        Values = {"one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen"},
        Multi = false,
        Default = 1,
    })

    Dropdown:SetValue("four")

    Dropdown:OnChanged(function(Value)
        print("Dropdown changed:", Value)
    end)

    -- สร้างตัวแปรเก็บค่า Dropdown ปัจจุบัน
local selectedZone = "Zone 1"

-- สร้าง Dropdown
local Dropdown = Tabs.Teleport:AddDropdown("Teleport", {
    Title = "Select to Teleport",
    Values = {"Zone 1", "Zone 2"},
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
                            hrp.CFrame = CFrame.new(200, 30, -300)
                        elseif selectedZone == "Zone 2" then
                            hrp.CFrame = CFrame.new(45, 30, 70)
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



    
    local MultiDropdown = Tabs.Main:AddDropdown("MultiDropdown", {
        Title = "Dropdown",
        Description = "You can select multiple values.",
        Values = {"one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen"},
        Multi = true,
        Default = {"seven", "twelve"},
    })

    MultiDropdown:SetValue({
        three = true,
        five = true,
        seven = false
    })

    MultiDropdown:OnChanged(function(Value)
        local Values = {}
        for Value, State in next, Value do
            table.insert(Values, Value)
        end
        print("Mutlidropdown changed:", table.concat(Values, ", "))
    end)



    local Colorpicker = Tabs.Main:AddColorpicker("Colorpicker", {
        Title = "Colorpicker",
        Default = Color3.fromRGB(96, 205, 255)
    })

    Colorpicker:OnChanged(function()
        print("Colorpicker changed:", Colorpicker.Value)
    end)
    
    Colorpicker:SetValueRGB(Color3.fromRGB(0, 255, 140))



    local TColorpicker = Tabs.Main:AddColorpicker("TransparencyColorpicker", {
        Title = "Colorpicker",
        Description = "but you can change the transparency.",
        Transparency = 0,
        Default = Color3.fromRGB(96, 205, 255)
    })

    TColorpicker:OnChanged(function()
        print(
            "TColorpicker changed:", TColorpicker.Value,
            "Transparency:", TColorpicker.Transparency
        )
    end)

    local Input = Tabs.Main:AddInput("Input", {
        Title = "Input",
        Default = "Default",
        Placeholder = "Placeholder",
        Numeric = false, -- Only allows numbers
        Finished = false, -- Only calls callback when you press enter
        Callback = function(Value)
            print("Input changed:", Value)
        end
    })

    Input:OnChanged(function()
        print("Input updated:", Input.Value)
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
