-- WindUI Loader
local ok, WindUI = pcall(function()
    return loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
end)
if not ok or not WindUI then return warn("WindUI load failed") end

-- Window
local Window = WindUI:CreateWindow({
    Title = "ATG Hub",
    Author = "by ATGFAIL",
    Theme = "Dark",
    Size = UDim2.fromOffset(540, 390),
    Folder = "GUI",
    AutoScale = false
})

Window:EditOpenButton({
    Title = "Open Menu",
    Icon = "monitor",
    CornerRadius = UDim.new(0,16),
    StrokeThickness = 2,
    Color = ColorSequence.new(Color3.fromHex("FF0F7B"), Color3.fromHex("F89B29")),
    OnlyMobile = false,
    Enabled = true,
    Draggable = true,
})

-- Tabs
local ESP_Tab = Window:Tab({ Title = "ESP", Icon = "app-window" })
local TP_Tab  = Window:Tab({ Title = "TP", Icon = "zap" })
local Local_Tab = Window:Tab({ Title = "Local Player", Icon = "user" })

local HttpService = game:GetService("HttpService")

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- Globals
_G.ESPEnabled = false
_G.GunESPEnabled = false
_G.WalkSpeedValue = 16
_G.InfiniteJumpEnabled = false
_G.NoclipEnabled = false

-- Utility
local function safeNewDrawing(class, props)
    local ok, obj = pcall(function() return Drawing.new(class) end)
    if not ok or not obj then return nil end
    if props then
        for k,v in pairs(props) do
            pcall(function() obj[k] = v end)
        end
    end
    return obj
end

local function worldToScreen(pos)
    local ok, sp, onScreen = pcall(function() return Camera:WorldToViewportPoint(pos) end)
    if not ok then return Vector2.new(0,0), false end
    return Vector2.new(sp.X, sp.Y), onScreen
end

local ROLE_COLORS = { Murderer=Color3.fromRGB(255,0,0), Sheriff=Color3.fromRGB(0,0,255), Innocent=Color3.fromRGB(0,255,0) }

local function detectRole(player)
    local role = "Innocent"
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        if backpack:FindFirstChild("Knife") then role = "Murderer"
        elseif backpack:FindFirstChild("Gun") then role = "Sheriff" end
    end
    local char = player.Character
    if char then
        for _, tool in pairs(char:GetChildren()) do
            if tool:IsA("Tool") then
                if tool.Name=="Knife" then role="Murderer"
                elseif tool.Name=="Gun" then role="Sheriff" end
            end
        end
    end
    return role
end

-- ESP
local ESP = {}
local function createPlayerESP(player)
    if player == LocalPlayer or ESP[player] then return end
    local line = safeNewDrawing("Line",{Thickness=3,Visible=false})
    local box  = safeNewDrawing("Square",{Thickness=1,Filled=false,Visible=false})
    local nameTag = safeNewDrawing("Text",{Size=16,Center=true,Outline=true,Visible=false,Text=player.Name})
    local highlight = Instance.new("Highlight")
    highlight.Name = "ESP_Highlight"
    highlight.FillTransparency = 0
    highlight.OutlineTransparency = 0.5
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Enabled = false
    ESP[player] = {Line=line, Box=box, NameTag=nameTag, Highlight=highlight}
    player.CharacterAdded:Connect(function(char)
        highlight.Parent = char
        highlight.Adornee = char
    end)
    if player.Character then
        highlight.Parent = player.Character
        highlight.Adornee = player.Character
    end
end

local function destroyPlayerESP(player)
    local data = ESP[player]
    if not data then return end
    if data.Line then data.Line:Remove() end
    if data.Box then data.Box:Remove() end
    if data.NameTag then data.NameTag:Remove() end
    if data.Highlight then data.Highlight:Destroy() end
    ESP[player] = nil
end

Players.PlayerAdded:Connect(createPlayerESP)
Players.PlayerRemoving:Connect(destroyPlayerESP)
for _,p in pairs(Players:GetPlayers()) do createPlayerESP(p) end

-- Gun ESP
local gunLine = safeNewDrawing("Line",{Thickness=3,Visible=false})
local gunBox  = safeNewDrawing("Square",{Thickness=1,Filled=false,Visible=false})
local currentGun = nil

task.spawn(function()
    while true do
        currentGun = nil
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Name=="GunDrop" then currentGun=obj break end
        end
        task.wait(0.5)
    end
end)

-- Teleports
local function teleportToGun()
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if hrp and currentGun then hrp.CFrame = currentGun.CFrame + Vector3.new(0,3,0) end
end

local function teleportBehind(target)
    if not target or not target.Character then return end
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if hrp and myHRP then
        myHRP.CFrame = CFrame.new(hrp.Position - hrp.CFrame.LookVector*8, hrp.Position)
    end
end

local function getSheriff()
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            if (p.Backpack:FindFirstChild("Gun")) or (p.Character and p.Character:FindFirstChild("Gun")) then return p end
        end
    end
end

local function getMurderer()
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            if (p.Backpack:FindFirstChild("Knife")) or (p.Character and p.Character:FindFirstChild("Knife")) then return p end
        end
    end
end

-- WalkSpeed
local function setWalkSpeed()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.WalkSpeed ~= _G.WalkSpeedValue then hum.WalkSpeed=_G.WalkSpeedValue end
end
LocalPlayer.CharacterAdded:Connect(function() task.wait(0.5) setWalkSpeed() end)
if LocalPlayer.Character then setWalkSpeed() end

-- Infinite Jump
UserInputService.JumpRequest:Connect(function()
    if _G.InfiniteJumpEnabled then
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

-- Noclip
RunService.Stepped:Connect(function()
    if _G.NoclipEnabled then
        local char = LocalPlayer.Character
        if char then
            for _, part in pairs(char:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide=false end
            end
        end
    end
end)

-- TP Buttons
TP_Tab:Button({Title="Gun TP", Callback=teleportToGun})
TP_Tab:Button({Title="Teleport to Murderer", Callback=function()
    local m=getMurderer()
    if m then teleportBehind(m) else WindUI:Notify({Title="Error",Content="No murderer detected",Duration=3,Icon="x"}) end
end})
TP_Tab:Button({Title="Teleport to Sheriff", Callback=function()
    local s=getSheriff()
    if s then teleportBehind(s) else WindUI:Notify({Title="Error",Content="No sheriff detected",Duration=3,Icon="x"}) end
end})

-- ESP Toggles
ESP_Tab:Toggle({Title="Player ESP", Default=false, Callback=function(state) _G.ESPEnabled=state end})
ESP_Tab:Toggle({Title="Gun ESP", Default=false, Callback=function(state) _G.GunESPEnabled=state end})

-- Local Player
Local_Tab:Slider({Title="WalkSpeed", Step=1, Value={Min=16,Max=100,Default=16}, Callback=function(val) _G.WalkSpeedValue=val setWalkSpeed() end})
Local_Tab:Toggle({Title="Infinite Jump", Default=false, Callback=function(state) _G.InfiniteJumpEnabled=state end})
Local_Tab:Toggle({Title="Noclip", Default=false, Callback=function(state) _G.NoclipEnabled=state end})

-- ESP Render Loop
RunService.RenderStepped:Connect(function()
    for player,data in pairs(ESP) do
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local head = char and char:FindFirstChild("Head")
        if not _G.ESPEnabled or not (char and hrp and hum and hum.Health>0) then
            if data.Box then data.Box.Visible=false end
            if data.Line then data.Line.Visible=false end
            if data.NameTag then data.NameTag.Visible=false end
            if data.Highlight then data.Highlight.Enabled=false end
        else
            local role = detectRole(player)
            if data.Highlight then data.Highlight.FillColor=ROLE_COLORS[role]; data.Highlight.Enabled=true end
            if head and hrp then
                local top2D, onTop = worldToScreen(head.Position+Vector3.new(0,0.5,0))
                local bottom2D, onBottom = worldToScreen(hrp.Position-Vector3.new(0,2.5,0))
                if onTop and onBottom then
                    local height=math.abs(top2D.Y-bottom2D.Y)
                    local width=height/2
                    if data.Box then data.Box.Position=Vector2.new(top2D.X-width/2,top2D.Y); data.Box.Size=Vector2.new(width,height); data.Box.Color=ROLE_COLORS[role]; data.Box.Visible=true end
                    if data.NameTag then data.NameTag.Position=top2D-Vector2.new(0,15); data.NameTag.Color=(role=="Innocent") and Color3.fromRGB(0,0,0) or ROLE_COLORS[role]; data.NameTag.Visible=(role~="Innocent") end
                    if data.Line then data.Line.From=Vector2.new(Camera.ViewportSize.X/2,0); data.Line.To=Vector2.new(top2D.X,top2D.Y); data.Line.Color=ROLE_COLORS[role]; data.Line.Visible=true end
                else
                    if data.Box then data.Box.Visible=false end
                    if data.NameTag then data.NameTag.Visible=false end
                    if data.Line then data.Line.Visible=false end
                end
            end
        end
    end
    if _G.GunESPEnabled and currentGun then
        local pos,onScreen=Camera:WorldToViewportPoint(currentGun.Position)
        if onScreen then
            if gunBox then gunBox.Position=Vector2.new(pos.X-12,pos.Y-12); gunBox.Size=Vector2.new(24,24); gunBox.Color=Color3.fromRGB(255,255,0); gunBox.Visible=true end
            if gunLine then gunLine.From=Vector2.new(Camera.ViewportSize.X/2,0); gunLine.To=Vector2.new(pos.X,pos.Y); gunLine.Color=Color3.fromRGB(255,255,0); gunLine.Visible=true end
        else
            if gunBox then gunBox.Visible=false end
            if gunLine then gunLine.Visible=false end
        end
    else
        if gunBox then gunBox.Visible=false end
        if gunLine then gunLine.Visible=false end
    end
end)
