repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local treesFolder = workspace:WaitForChild("TreesFolder")
local gameEvent = ReplicatedStorage:WaitForChild("Signal"):WaitForChild("Game")
local treeEvent = ReplicatedStorage:WaitForChild("Signal"):WaitForChild("Tree")

-- UI lib (ตามที่ส่งมา)
local lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/UI-Libs/main/Vape.txt"))()
local win = lib:Window("ATG Hub", Color3.fromRGB(44, 120, 224), Enum.KeyCode.RightControl)
local tab = win:Tab("Tree AutoCut")

-- === State & config ===
-- Auto Cut (รอบละ 3 วินาที, ใช้รัศมี)
local autoCutEnabled = false
local batchInterval = 3
local autoLoopToken = 0
local autoHeartbeatConn = nil
local perModelCooldown_auto = 1.0
local lastFiredAt_auto = {}

-- Cut Aura (ยิงทุก Model แบบโหด ไม่จำกัดระยะ รอบละ 0.5s)
local auraEnabled = false
local auraInterval = 0.5
local auraLoopToken = 0
local auraHeartbeatConn = nil
-- สำหรับ Aura เราจะไม่ใช้ cooldown (ยิงทุกตัวทุกรอบ)
--local lastFiredAt_aura = {}

-- Shared realtime listeners
local descendantAddedConn = nil
local childRemovedConn = nil

-- Radius + WalkSpeed (สำหรับ AutoCut)
local scanRadius = 500
local currentWalkSpeed = 16

-- Character connection
local characterConn = nil

-- Helper: หา ancestor model ถ้าส่ง part มา
local function findAncestorModel(inst)
    while inst and inst ~= treesFolder and inst.Parent do
        if inst:IsA("Model") and inst.Parent and inst.Parent:IsDescendantOf(treesFolder) then
            return inst
        end
        inst = inst.Parent
    end
    return nil
end

-- Helper: หา basepart ที่ใกล้ reference มากที่สุด -> ตำแหน่ง + dist2
local function getClosestPartPositionToRef(model, referencePos)
    if not model then return nil end
    local bestPos = nil
    local bestDist2 = math.huge
    for _, v in ipairs(model:GetDescendants()) do
        if v:IsA("BasePart") then
            local pos = v.Position
            local dx = pos.X - referencePos.X
            local dy = pos.Y - referencePos.Y
            local dz = pos.Z - referencePos.Z
            local d2 = dx*dx + dy*dy + dz*dz
            if d2 < bestDist2 then
                bestDist2 = d2
                bestPos = pos
            end
        end
    end
    if not bestPos then
        local ok, pp = pcall(function() return model.PrimaryPart end)
        if ok and pp and pp:IsA("BasePart") then
            bestPos = pp.Position
            local dx = bestPos.X - referencePos.X
            local dy = bestPos.Y - referencePos.Y
            local dz = bestPos.Z - referencePos.Z
            bestDist2 = dx*dx + dy*dy + dz*dz
        end
    end
    return bestPos, bestDist2
end

-- Fire helpers
local function fireDamage_auto(model)
    if not model or not model.Name then return end
    local now = tick()
    if lastFiredAt_auto[model] and (now - lastFiredAt_auto[model]) < perModelCooldown_auto then
        return
    end
    lastFiredAt_auto[model] = now
    task.spawn(function()
        local args = { [1] = "damage", [2] = model.Name }
        pcall(function() treeEvent:FireServer(unpack(args)) end)
    end)
end

-- Aura: ยิงทุก Model โดยไม่สนระยะและไม่มี cooldown (โหด)
local function fireDamage_aura(model)
    if not model or not model.Name then return end
    task.spawn(function()
        local args = { [1] = "damage", [2] = model.Name }
        pcall(function() treeEvent:FireServer(unpack(args)) end)
    end)
end

-- Batch scan for Auto Cut (uses radius relative to player)
local function doAutoBatchOnce(token)
    if not autoCutEnabled or token ~= autoLoopToken then return end
    local char = player.Character
    local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso"))
    if not hrp then return end
    local hrpPos = hrp.Position
    local r2 = scanRadius * scanRadius

    for _, obj in ipairs(treesFolder:GetDescendants()) do
        if not autoCutEnabled or token ~= autoLoopToken then return end
        if obj:IsA("Model") then
            local pos, dist2 = getClosestPartPositionToRef(obj, hrpPos)
            if pos and dist2 and dist2 <= r2 then
                fireDamage_auto(obj)
            end
        end
    end
end

-- Batch scan for Aura: ยิงทุก Model ที่เจอ (ไม่จำกัดระยะ)
local function doAuraBatchOnce(token)
    if not auraEnabled or token ~= auraLoopToken then return end
    for _, obj in ipairs(treesFolder:GetDescendants()) do
        if not auraEnabled or token ~= auraLoopToken then return end
        if obj:IsA("Model") then
            fireDamage_aura(obj)
        end
    end
end

-- Start/stop loops (Heartbeat)
local function startAutoLoop()
    if autoHeartbeatConn then
        autoHeartbeatConn:Disconnect()
        autoHeartbeatConn = nil
    end
    autoLoopToken = autoLoopToken + 1
    local myToken = autoLoopToken
    doAutoBatchOnce(myToken) -- รอบแรกทันที
    local acc = 0
    autoHeartbeatConn = RunService.Heartbeat:Connect(function(dt)
        if not autoCutEnabled or myToken ~= autoLoopToken then
            if autoHeartbeatConn then autoHeartbeatConn:Disconnect() autoHeartbeatConn = nil end
            return
        end
        acc = acc + dt
        if acc >= batchInterval then
            acc = acc - batchInterval
            doAutoBatchOnce(myToken)
        end
    end)
end

local function stopAutoLoop()
    autoCutEnabled = false
    autoLoopToken = autoLoopToken + 1
    if autoHeartbeatConn then
        autoHeartbeatConn:Disconnect()
        autoHeartbeatConn = nil
    end
    lastFiredAt_auto = {}
end

local function startAuraLoop()
    if auraHeartbeatConn then
        auraHeartbeatConn:Disconnect()
        auraHeartbeatConn = nil
    end
    auraLoopToken = auraLoopToken + 1
    local myToken = auraLoopToken
    doAuraBatchOnce(myToken) -- รอบแรกทันที
    local acc = 0
    auraHeartbeatConn = RunService.Heartbeat:Connect(function(dt)
        if not auraEnabled or myToken ~= auraLoopToken then
            if auraHeartbeatConn then auraHeartbeatConn:Disconnect() auraHeartbeatConn = nil end
            return
        end
        acc = acc + dt
        if acc >= auraInterval then
            acc = acc - auraInterval
            doAuraBatchOnce(myToken)
        end
    end)
end

local function stopAuraLoop()
    auraEnabled = false
    auraLoopToken = auraLoopToken + 1
    if auraHeartbeatConn then
        auraHeartbeatConn:Disconnect()
        auraHeartbeatConn = nil
    end
end

-- Realtime descendant handler: เมื่อมี Model ใหม่โผล่ จะยิงทันทีถ้าโหมดที่เกี่ยวข้องเปิดอยู่
local function onDescendantAdded(inst)
    local m = findAncestorModel(inst)
    if not m then return end

    if auraEnabled then
        fireDamage_aura(m)
    end

    if autoCutEnabled then
        local char = player.Character
        local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso"))
        if hrp then
            local hrpPos = hrp.Position
            local pos, dist2 = getClosestPartPositionToRef(m, hrpPos)
            if pos and dist2 and dist2 <= (scanRadius * scanRadius) then
                fireDamage_auto(m)
            end
        end
    end
end

local function onChildRemoved(inst)
    if inst:IsA("Model") then
        lastFiredAt_auto[inst] = nil
    else
        local m = findAncestorModel(inst)
        if m then
            lastFiredAt_auto[m] = nil
        end
    end
end

local function connectTreeListeners()
    if descendantAddedConn then return end
    descendantAddedConn = treesFolder.DescendantAdded:Connect(onDescendantAdded)
    if treesFolder.DescendantRemoving then
        childRemovedConn = treesFolder.DescendantRemoving:Connect(onChildRemoved)
    else
        childRemovedConn = treesFolder.ChildRemoved:Connect(onChildRemoved)
    end
end

local function disconnectTreeListeners()
    if descendantAddedConn then
        descendantAddedConn:Disconnect()
        descendantAddedConn = nil
    end
    if childRemovedConn then
        childRemovedConn:Disconnect()
        childRemovedConn = nil
    end
end

-- Character / WalkSpeed functions
local function applyWalkSpeedToCharacter(char)
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then hum.WalkSpeed = currentWalkSpeed end
end

local function onCharacterAdded(char)
    applyWalkSpeedToCharacter(char)
end

if player.Character then applyWalkSpeedToCharacter(player.Character) end
if characterConn then characterConn:Disconnect() end
characterConn = player.CharacterAdded:Connect(onCharacterAdded)

-- UI: Auto Cut Toggle (เมื่อเปิดจะ Fire "play" ก่อนแล้วเริ่ม batch & listeners)
tab:Toggle("Auto Cut Tree", false, function(state)
    if state then
        pcall(function() gameEvent:FireServer("play") end)
        if autoCutEnabled then return end
        autoCutEnabled = true
        connectTreeListeners()
        startAutoLoop()
    else
        stopAutoLoop()
        if not auraEnabled then disconnectTreeListeners() end
    end
end)

-- UI: Cut Aura Toggle (โหด: ยิงทุก Model รอบละ 0.5s, ไม่จำกัดระยะ)
tab:Toggle("Cut Aura (โหด)", false, function(state)
    if state then
        if auraEnabled then return end
        auraEnabled = true
        connectTreeListeners()
        startAuraLoop()
    else
        stopAuraLoop()
        if not autoCutEnabled then disconnectTreeListeners() end
    end
end)

-- UI: Radius Slider 0..5000 (สำหรับ AutoCut เท่านั้น)
tab:Slider("Radius (studs)", 0, 5000, scanRadius, function(value)
    local v = tonumber(value) or scanRadius
    if v < 0 then v = 0 end
    if v > 5000 then v = 5000 end
    scanRadius = v
end)

-- UI: WalkSpeed Slider 0..200
tab:Slider("WalkSpeed", 0, 200, currentWalkSpeed, function(value)
    local v = tonumber(value) or currentWalkSpeed
    if v < 0 then v = 0 end
    if v > 200 then v = 200 end
    currentWalkSpeed = v
    if player.Character then
        local hum = player.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = currentWalkSpeed end
    end
end)

-- Optional: หยุดทุกอย่างพร้อมกัน (เรียกถ้าต้องการ)
local function stopEverything()
    stopAutoLoop()
    stopAuraLoop()
    disconnectTreeListeners()
    if characterConn then
        characterConn:Disconnect()
        characterConn = nil
    end
end

-- หมายเหตุ:
-- - Cut Aura โหดจริง: ยิงทุกรอบทุก Model ที่เจอ ไม่จำกัดระยะ หาก Models จำนวนมากหรือ server rate-limit อาจเกิด lag/ถูก block ได้
-- - ถ้าต้องการเพิ่ม limit เช่น ยิงเฉพาะ N ตัวต่อรอบ หรือลดระยะ/เพิ่ม cooldown บอกได้ เดี๋ยวปรับให้
