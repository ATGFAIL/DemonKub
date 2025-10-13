-- FPSBooster_VisualOnly.lua
-- ปรับปรุง: เก็บเฉพาะการปรับภาพ/กราฟิก และเอา Notification / ฟังก์ชันที่ไม่เกี่ยวกับภาพออกทั้งหมด
-- วางที่ StarterPlayerScripts (client)

if not game:IsLoaded() then
    repeat task.wait() until game:IsLoaded()
end

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local LocalPlayer = Players.LocalPlayer
local Workspace = workspace

-- =======================
-- CONFIG: ปรับได้
-- =======================
local Config = {
    Features = {
        NoParticles = true,
        NoTrails = true,
        NoBeams = true,
        NoCameraEffects = true,   -- ปิด PostEffect (หน้าจอ)
        NoExplosions = true,      -- ทำให้ Explosions เล็ก/มองไม่เห็น/ปรับให้เบา
        NoClothes = false,        -- ถ้าต้องการลบเสื้อผ้าเพื่อประสิทธิภาพ ให้เป็น true (ลบคือการทำลาย instance — เป็นการเปลี่ยนภาพ)
        LowWaterGraphics = true,
        NoShadows = true,
        LowRendering = true,
        LowQualityParts = true,
        ResetMaterials = true,
    },

    Meshes = {
        Destroy = false,              -- ถ้าต้องการลบ MeshPart ให้เป็น true
        LowerQualityMeshParts = true,
        RemoveMeshTexture = false,
    },

    Images = {
        Invisible = true,      -- ทำให้ decal / texture โปร่ง (ภาพ)
        Destroy = false,
    },

    Queue = {
        Enabled = true,
        BatchSize = 120,
        BatchInterval = 0.08,
        MaxDistance = 400,
    },

    Ignore = {
        ClassNames = { ["Terrain"]=true, ["Folder"]=true },
        InstanceNames = {},
        CollectionsIgnoreTag = "PerfIgnore",
        CollectionsFastTag = "PerfTarget",
    },

    Compatibility = {
        UseHiddenProperty = true, -- ใช้ sethiddenproperty ถ้ามี (visual-only tweaks)
    }
}

-- =======================
-- saved state (weak-key) เพื่อ restore properties ภาพ
-- =======================
local savedState = {
    lighting = {},
    instances = setmetatable({}, { __mode = "k" })
}

local pcall = pcall
local type = type
local ipairs = ipairs
local pairs = pairs

-- =======================
-- Helpers
-- =======================
local function isInstanceIgnored(inst)
    if not inst then return true end
    if CollectionService:HasTag(inst, Config.Ignore.CollectionsIgnoreTag) then return true end
    if Config.Ignore.ClassNames[inst.ClassName] then return true end
    if Config.Ignore.InstanceNames[inst.Name] then return true end
    if LocalPlayer and LocalPlayer.Character and inst:IsDescendantOf(LocalPlayer.Character) then
        return true
    end
    return false
end

local function isTooFar(inst)
    local cam = Workspace.CurrentCamera
    if not cam then return false end
    if inst:IsA("BasePart") and inst.Position then
        local ok, mag = pcall(function()
            return (inst.Position - cam.CFrame.Position).Magnitude
        end)
        if ok and mag then
            return mag > Config.Queue.MaxDistance
        end
    end
    return false
end

local function savePropertyOnce(obj, prop, value)
    if not obj then return end
    local entry = savedState.instances[obj]
    if not entry then
        entry = {}
        savedState.instances[obj] = entry
    end
    if entry[prop] == nil then
        entry[prop] = value
    end
end

-- =======================
-- Optimize single instance (ภาพ/visual-related only)
-- =======================
local function optimizeInstance(inst)
    if not inst or isInstanceIgnored(inst) then return end
    if not CollectionService:HasTag(inst, Config.Ignore.CollectionsFastTag) and isTooFar(inst) then
        return
    end

    local class = inst.ClassName

    -- Particle / Trail / Smoke / Fire / Sparkles
    if (class == "ParticleEmitter" or class == "Trail" or class == "Smoke" or class == "Fire" or class == "Sparkles")
            and Config.Features.NoParticles then
        if pcall(function() return inst.Enabled end) then
            savePropertyOnce(inst, "Enabled", inst.Enabled)
        end
        pcall(function() inst.Enabled = false end)
        pcall(function() if inst.Rate then inst.Rate = 0 end end)
        return
    end

    -- Beam (visual)
    if class == "Beam" and Config.Features.NoBeams then
        if pcall(function() return inst.Enabled end) then
            savePropertyOnce(inst, "Enabled", inst.Enabled)
        end
        pcall(function() inst.Enabled = false end)
        return
    end

    -- PostEffect (หน้าจอ / camera effects)
    if inst:IsA("PostEffect") and Config.Features.NoCameraEffects then
        if pcall(function() return inst.Enabled end) then
            savePropertyOnce(inst, "Enabled", inst.Enabled)
        end
        pcall(function() inst.Enabled = false end)
        return
    end

    -- Explosion (ปรับค่าเพื่อให้เบาและมองไม่เห็น)
    if inst:IsA("Explosion") and Config.Features.NoExplosions then
        pcall(function()
            if inst.BlastPressure ~= nil then savePropertyOnce(inst, "BlastPressure", inst.BlastPressure) end
            if inst.BlastRadius ~= nil then savePropertyOnce(inst, "BlastRadius", inst.BlastRadius) end
            if inst.Visible ~= nil then savePropertyOnce(inst, "Visible", inst.Visible) end
            inst.BlastPressure = 1
            inst.BlastRadius = 1
            if inst.Visible ~= nil then inst.Visible = false end
        end)
        return
    end

    -- Clothing / SurfaceAppearance / BaseWrap (เป็นภาพของตัวละคร)
    if (inst:IsA("Clothing") or inst:IsA("SurfaceAppearance") or inst:IsA("BaseWrap")) and Config.Features.NoClothes then
        pcall(function() savePropertyOnce(inst, "Parent", inst.Parent) end)
        pcall(function() inst:Destroy() end)
        return
    end

    -- MeshPart (ลดคุณภาพภาพ)
    if inst:IsA("MeshPart") then
        if Config.Meshes.LowerQualityMeshParts or Config.Features.LowQualityParts then
            pcall(function()
                if inst.RenderFidelity ~= nil then savePropertyOnce(inst, "RenderFidelity", inst.RenderFidelity) end
                if inst.Reflectance ~= nil then savePropertyOnce(inst, "Reflectance", inst.Reflectance) end
                if inst.Material ~= nil then savePropertyOnce(inst, "Material", inst.Material) end
                inst.RenderFidelity = 2
                inst.Reflectance = 0
                inst.Material = Enum.Material.Plastic
            end)
        end
        if Config.Meshes.RemoveMeshTexture and pcall(function() return inst.TextureID end) then
            savePropertyOnce(inst, "TextureID", inst.TextureID)
            pcall(function() inst.TextureID = "" end)
        end
        if Config.Meshes.Destroy then
            pcall(function() inst:Destroy() end)
        end
        return
    end

    -- BasePart (ทั่วไป) -> ลด material ให้เป็น plastic
    if inst:IsA("BasePart") and not inst:IsA("MeshPart") then
        if Config.Features.LowQualityParts then
            pcall(function()
                if inst.Material ~= nil then savePropertyOnce(inst, "Material", inst.Material) end
                if inst.Reflectance ~= nil then savePropertyOnce(inst, "Reflectance", inst.Reflectance) end
                inst.Material = Enum.Material.Plastic
                inst.Reflectance = 0
            end)
        end
        -- CastShadow: ปิดถ้ารองรับ
        if Config.Features.NoShadows and inst.CastShadow ~= nil then
            savePropertyOnce(inst, "CastShadow", inst.CastShadow)
            pcall(function() inst.CastShadow = false end)
        end
        return
    end

    -- Decal / Texture / FaceInstance / ShirtGraphic (ภาพ)
    if inst:IsA("Decal") or inst:IsA("Texture") or inst:IsA("FaceInstance") or inst:IsA("ShirtGraphic") then
        if Config.Images.Invisible then
            pcall(function() savePropertyOnce(inst, "Transparency", inst.Transparency) end)
            pcall(function() inst.Transparency = 1 end)
        end
        if Config.Images.Destroy then
            pcall(function() inst:Destroy() end)
        end
        return
    end

    -- TextLabel ใน workspace (world labels)
    if inst:IsA("TextLabel") and inst:IsDescendantOf(Workspace) then
        pcall(function()
            savePropertyOnce(inst, "Font", inst.Font)
            savePropertyOnce(inst, "TextSize", inst.TextSize)
            inst.Font = Enum.Font.SourceSans
            inst.TextScaled = false
            inst.RichText = false
            inst.TextSize = 14
        end)
        return
    end

    -- Model: ปรับ LOD ถ้ามี
    if inst:IsA("Model") then
        if Config.Features.LowRendering then
            pcall(function()
                if inst.LevelOfDetail ~= nil then savePropertyOnce(inst, "LevelOfDetail", inst.LevelOfDetail) end
                inst.LevelOfDetail = 1
            end)
        end
        return
    end
end

-- =======================
-- Circular queue (simple)
-- =======================
local Queue = {}
Queue.__index = Queue

function Queue.new(cap)
    cap = math.max(32, cap or 1024)
    return setmetatable({ data = {}, head = 1, tail = 0, size = 0, capacity = cap }, Queue)
end

function Queue:push(x)
    if self.size >= self.capacity then
        self.capacity = self.capacity * 2
    end
    self.tail = self.tail + 1
    self.data[self.tail] = x
    self.size = self.size + 1
end

function Queue:popBatch(n)
    n = math.min(n or 1, self.size)
    local out = {}
    for i = 1, n do
        out[i] = self.data[self.head]
        self.data[self.head] = nil
        self.head = self.head + 1
        self.size = self.size - 1
    end
    if self.head > 10000 then
        local newData = {}
        for i = 1, self.size do
            newData[i] = self.data[self.head + i - 1]
        end
        self.data = newData
        self.head = 1
        self.tail = self.size
    end
    return out
end

function Queue:isEmpty()
    return self.size == 0
end

local workQueue = Queue.new(2048)

-- =======================
-- Schedule initial scan (ไม่ทำ GetDescendants ทีเดียวหนัก ๆ)
-- =======================
local function scheduleInitialScan()
    for _, root in ipairs(Workspace:GetChildren()) do
        workQueue:push(root)
        if root:IsA("Model") or root:IsA("Folder") then
            for _, c in ipairs(root:GetChildren()) do
                workQueue:push(c)
            end
        end
    end
    workQueue:push(Lighting)
    workQueue:push(MaterialService)
end

-- DescendantAdded: push ลง queue แบบ non-blocking
if Config.Queue.Enabled then
    Workspace.DescendantAdded:Connect(function(inst)
        task.delay(0.15, function()
            if inst and not isInstanceIgnored(inst) then
                workQueue:push(inst)
            end
        end)
    end)
end

-- =======================
-- Heartbeat: process batches
-- =======================
local elapsed = 0
local function heartbeat(dt)
    elapsed = elapsed + dt
    if elapsed < Config.Queue.BatchInterval then return end
    elapsed = 0

    if workQueue:isEmpty() then return end
    local batch = workQueue:popBatch(Config.Queue.BatchSize)
    for i = 1, #batch do
        local node = batch[i]
        if node and node.Parent ~= nil then
            if node:IsA("Model") or node:IsA("Folder") or node:IsA("DataModel") then
                for _, child in ipairs(node:GetChildren()) do
                    optimizeInstance(child)
                end
            else
                optimizeInstance(node)
            end
        end
    end
end

local hbConn = RunService.Heartbeat:Connect(heartbeat)

-- =======================
-- Lighting / Terrain tweaks (visual-only)
-- =======================
local function tweakLighting()
    pcall(function()
        if Config.Features.NoShadows then
            savedState.lighting.GlobalShadows = Lighting.GlobalShadows
            Lighting.GlobalShadows = false
            savedState.lighting.FogEnd = Lighting.FogEnd
            Lighting.FogEnd = 9e9
            pcall(function() Lighting.ShadowSoftness = 0 end)
            if Config.Compatibility.UseHiddenProperty and sethiddenproperty then
                pcall(function() sethiddenproperty(Lighting, "Technology", 2) end)
            end
        end

        if Config.Features.LowWaterGraphics then
            local terrain = Workspace:FindFirstChildOfClass("Terrain")
            if terrain then
                savedState.lighting.Terrain = savedState.lighting.Terrain or {}
                savedState.lighting.Terrain.WaterWaveSize = terrain.WaterWaveSize
                savedState.lighting.Terrain.WaterWaveSpeed = terrain.WaterWaveSpeed
                savedState.lighting.Terrain.WaterReflectance = terrain.WaterReflectance
                savedState.lighting.Terrain.WaterTransparency = terrain.WaterTransparency

                pcall(function()
                    terrain.WaterWaveSize = 0
                    terrain.WaterWaveSpeed = 0
                    terrain.WaterReflectance = 0
                    terrain.WaterTransparency = 0
                end)

                if Config.Compatibility.UseHiddenProperty and sethiddenproperty then
                    pcall(function() sethiddenproperty(terrain, "Decoration", false) end)
                end
            end
        end

        if Config.Features.LowRendering then
            pcall(function()
                settings().Rendering.QualityLevel = 1
                settings().Rendering.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level04
            end)
        end

        if Config.Features.ResetMaterials then
            pcall(function()
                for _, v in pairs(MaterialService:GetChildren()) do
                    pcall(function() v:Destroy() end)
                end
                MaterialService.Use2022Materials = false
            end)
        end
    end)
end

-- =======================
-- Restore function (visual properties)
-- =======================
local function restoreAll()
    -- Lighting
    pcall(function()
        for k, v in pairs(savedState.lighting) do
            pcall(function()
                if k == "Terrain" and Workspace:FindFirstChildOfClass("Terrain") then
                    local terrain = Workspace:FindFirstChildOfClass("Terrain")
                    terrain.WaterWaveSize = v.WaterWaveSize
                    terrain.WaterWaveSpeed = v.WaterWaveSpeed
                    terrain.WaterReflectance = v.WaterReflectance
                    terrain.WaterTransparency = v.WaterTransparency
                    if sethiddenproperty then
                        pcall(function() sethiddenproperty(terrain, "Decoration", true) end)
                    end
                else
                    if Lighting[k] ~= nil then
                        Lighting[k] = v
                    end
                end
            end)
        end
    end)

    -- Instances: คืนค่า properties ที่บันทึกไว้
    for obj, props in pairs(savedState.instances) do
        if obj and obj.Parent ~= nil then
            for prop, val in pairs(props) do
                pcall(function()
                    if obj and obj.Parent then
                        obj[prop] = val
                    end
                end)
            end
        end
    end
end

-- Expose minimal API (no notifications)
_G.FPSBooster = _G.FPSBooster or {}
_G.FPSBooster.Config = Config
_G.FPSBooster.Restore = restoreAll
_G.FPSBooster.Queue = workQueue
_G.FPSBooster.Stop = function()
    if hbConn then
        hbConn:Disconnect()
        hbConn = nil
    end
end

-- =======================
-- Initialization: schedule and background queueing (non-blocking)
-- =======================
tweakLighting()
scheduleInitialScan()

task.spawn(function()
    local quickParents = {Workspace, Lighting, MaterialService}
    for _, p in ipairs(quickParents) do
        for _, child in ipairs(p:GetChildren()) do
            if not isInstanceIgnored(child) then
                workQueue:push(child)
            end
        end
        task.wait(0.02)
    end

    -- full pass but chunked เพื่อไม่ให้ hitch
    local all = Workspace:GetDescendants()
    local idx = 1
    local chunk = 400
    while idx <= #all do
        local stop = math.min(#all, idx + chunk - 1)
        for i = idx, stop do
            local v = all[i]
            if v and not isInstanceIgnored(v) then
                workQueue:push(v)
            end
        end
        idx = idx + chunk
        task.wait(0.06)
    end
end)

-- เสร็จสิ้น: ไม่มีการแสดงแจ้งเตือนหรือ log ใด ๆ
-- ใช้งาน: _G.FPSBooster.Restore() เพื่อคืนค่า (เรียกจาก client ของคุณ)
