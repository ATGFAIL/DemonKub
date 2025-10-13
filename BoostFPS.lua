-- LocalScript: client_performance_boost.lua
-- ใส่ไว้ที่ StarterPlayerScripts หรือ LocalPlayer สถานที่ที่รันบน client

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- ====== CONFIG ======
local config = {
    qualityLevel = 2,         -- พยายามตั้งค่า quality level (0..10) (ค่าต่ำ = คุณภาพต่ำขึ้น แต่ลื่นขึ้น)
    disableParticles = true,  -- ปิด ParticleEmitter
    disableTrails = true,     -- ปิด Trail
    disableBeams = true,      -- ปิด Beam
    disableLights = true,     -- ปิด PointLight/SpotLight/SurfaceLight
    disableShadows = true,    -- ปิด CastShadow กับ GlobalShadows
    hideDecals = false,       -- ซ่อน decal (โปรดระวัง: อาจทำให้วัตถุดูแปลก)
    decalTransparency = 1,    -- ความโปร่งใสเมื่อซ่อน decal (0..1)
    reduceTextureMemory = false, -- พยายามลดรายละเอียด texture โดยซ่อนบางอย่าง (ใช้ระวัง)
    maintainNewDescendants = true, -- ปิด effect ที่ spawn ใหม่ ให้รักษาผล
}
-- ======================

-- เก็บ state เดิมเพื่อ restore
local savedState = {}

local function safePcall(f, ...)
    local ok, res = pcall(f, ...)
    return ok, res
end

-- 1) พยายามปรับ Quality Level (UserSettings.GameSettings.SavedQualityLevel)
do
    pcall(function()
        local ok, userSettings = pcall(function() return UserSettings() end)
        if ok and userSettings and userSettings.GameSettings then
            -- แยก pcall เผื่อ property เข้าถึงไม่ได้
            pcall(function()
                userSettings.GameSettings.SavedQualityLevel = config.qualityLevel
            end)
        end
    end)
end

-- 2) ปรับ Lighting เบื้องต้นเพื่อลดเงา/เอฟเฟ็กต์หนัก ๆ
pcall(function()
    if config.disableShadows then
        if Lighting.GlobalShadows ~= nil then
            savedState.GlobalShadows = Lighting.GlobalShadows
            Lighting.GlobalShadows = false
        end
    end

    -- ลดเอฟเฟ็กต์ทางแสงที่อาจหนัก
    if Lighting.FogEnd and typeof(Lighting.FogEnd) == "number" then
        savedState.FogEnd = Lighting.FogEnd
        Lighting.FogEnd = math.max(1000, Lighting.FogEnd)
    end
    if Lighting.OutdoorAmbient and typeof(Lighting.OutdoorAmbient) == "Color3" then
        savedState.OutdoorAmbient = Lighting.OutdoorAmbient
        Lighting.OutdoorAmbient = Color3.fromRGB(128,128,128)
    end
    if Lighting.Brightness then
        savedState.Brightness = Lighting.Brightness
        Lighting.Brightness = math.clamp(Lighting.Brightness * 0.9, 0, 5)
    end
end)

-- helper เพื่อบันทึก state ก่อนแก้
local function saveIfNotSaved(obj, prop, val)
    if not savedState[obj] then savedState[obj] = {} end
    if savedState[obj][prop] == nil then
        savedState[obj][prop] = val
    end
end

-- 3) ฟังก์ชันปิด component หนัก ๆ ใน workspace
local function optimizeDescendant(d)
    -- อย่าไปยุ่งกับของในตัวผู้เล่นเอง (character ของ local player)
    if player and player.Character and d:IsDescendantOf(player.Character) then
        return
    end

    if config.disableParticles and d:IsA("ParticleEmitter") then
        saveIfNotSaved(d, "Enabled", d.Enabled)
        pcall(function() d.Enabled = false end)
        pcall(function() d.Rate = 0 end)
    end

    if config.disableTrails and d:IsA("Trail") then
        saveIfNotSaved(d, "Enabled", d.Enabled)
        pcall(function() d.Enabled = false end)
    end

    if config.disableBeams and d:IsA("Beam") then
        saveIfNotSaved(d, "Enabled", d.Enabled)
        pcall(function() d.Enabled = false end)
    end

    if config.disableLights and (d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") or d:IsA("DirectionalLight")) then
        saveIfNotSaved(d, "Enabled", d.Enabled)
        pcall(function() d.Enabled = false end)
    end

    if config.hideDecals and d:IsA("Decal") then
        saveIfNotSaved(d, "Transparency", d.Transparency)
        pcall(function() d.Transparency = config.decalTransparency end)
    end

    if config.disableShadows and d:IsA("BasePart") then
        if d.CastShadow ~= nil then
            saveIfNotSaved(d, "CastShadow", d.CastShadow)
            pcall(function() d.CastShadow = false end)
        end
    end

    -- ถ้าเลือกลด texture memory แบบรุนแรง (ระวัง) ให้ซ่อนบาง mesh/texture ที่ไม่สำคัญ
    if config.reduceTextureMemory then
        if d:IsA("Decal") or d:IsA("Texture") then
            saveIfNotSaved(d, "Transparency", d.Transparency)
            pcall(function() d.Transparency = 1 end)
        elseif d:IsA("MeshPart") or d:IsA("SpecialMesh") then
            -- งดการแก้แปลง mesh แบบถาวร — แค่ลดรายละเอียดโดยทำให้โปร่งบางครั้ง
            if d:IsA("BasePart") and d.LocalTransparencyModifier ~= nil then
                saveIfNotSaved(d, "LocalTransparencyModifier", d.LocalTransparencyModifier)
                pcall(function() d.LocalTransparencyModifier = 0.3 end)
            end
        end
    end
end

-- เรียกครั้งแรกบนทุก object ที่มีอยู่แล้ว
for _, d in ipairs(workspace:GetDescendants()) do
    local ok, _ = pcall(optimizeDescendant, d)
end

-- 4) ถ้าต้องการให้จับ object ใหม่ ๆ ที่ spawn ขึ้นมาด้วย
if config.maintainNewDescendants then
    workspace.DescendantAdded:Connect(function(d)
        -- ให้สั้น ๆ: ยกเว้นของตัวผู้เล่นเอง
        local ok, _ = pcall(optimizeDescendant, d)
    end)
end

-- 5) ลดการอัปเดต GUI / Particle heavy objects ใน StarterGui / PlayerGui ถ้าต้องการ
pcall(function()
    local function optimizeGui(gui)
        for _, obj in ipairs(gui:GetDescendants()) do
            if obj:IsA("ParticleEmitter") or obj:IsA("Beam") or obj:IsA("Trail") then
                pcall(function() obj.Enabled = false end)
            end
            -- ถ้ามีวีดีโอ/เว็บวิดีโอ embed อาจหนัก — ปิด/หยุดมัน (ขึ้นอยู่กับ plugin)
        end
    end

    if player and player:FindFirstChild("PlayerGui") then
        optimizeGui(player.PlayerGui)
    end

    player.PlayerGui.ChildAdded:Connect(function(c)
        pcall(function() optimizeGui(c) end)
    end)
end)

-- ฟังก์ชันคืนค่าเดิม (restore)
local function restoreAll()
    -- Lighting
    pcall(function()
        if savedState.GlobalShadows ~= nil and Lighting.GlobalShadows ~= nil then
            Lighting.GlobalShadows = savedState.GlobalShadows
        end
        if savedState.FogEnd ~= nil then Lighting.FogEnd = savedState.FogEnd end
        if savedState.OutdoorAmbient ~= nil then Lighting.OutdoorAmbient = savedState.OutdoorAmbient end
        if savedState.Brightness ~= nil then Lighting.Brightness = savedState.Brightness end
    end)

    -- savedState เก็บแบบ: savedState[obj][prop] = value
    for obj, props in pairs(savedState) do
        -- บางครั้ง object อาจถูกลบไปแล้ว -> pcall
        for prop, val in pairs(props) do
            pcall(function()
                if obj and obj.Parent ~= nil then
                    obj[prop] = val
                end
            end)
        end
    end

    -- ลอง restore quality level (ถ้าเก็บไว้)
    pcall(function()
        local ok, userSettings = pcall(function() return UserSettings() end)
        if ok and userSettings and userSettings.GameSettings and savedState.QualityLevel then
            pcall(function() userSettings.GameSettings.SavedQualityLevel = savedState.QualityLevel end)
        end
    end)
end

-- (Optional) ให้ผู้ใช้กดปุ่มเพื่อ restore — ไม่จำเป็น แต่สะดวกสำหรับเทส
local ContextActionService = game:GetService("ContextActionService")
pcall(function()
    ContextActionService:BindAction("RestorePerfScript", function() restoreAll() end, false, Enum.KeyCode.F6)
end)

-- แจ้งผล
print("[PerfBoost] applied client-side optimizations. Press F6 to attempt restore (if supported).")
