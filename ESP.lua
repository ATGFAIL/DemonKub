-- ATG ESP (optimized)
-- หลักการสำคัญ:
-- 1) ใช้ centralized update loop (Heartbeat) ที่ throttle ด้วย updateInterval (ไม่สร้าง RenderStepped per-player)
-- 2) Culling: ระยะ, อยู่ในหน้าจอ, (optionally) raycast สำหรับ visibility แบบ throttled
-- 3) Object pooling สำหรับ BillboardGui และ Highlight เพื่อลดการสร้าง/ทำลายบ่อย ๆ
-- 4) เก็บ state/config ที่ UI สามารถแก้ได้ และมี Reset/Presets
-- 5) เช็ค cleanup เมื่อ PlayerLeft หรือ Unload

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- state + config (เก็บค่า default ที่เหมาะสม)
local state = state or {} -- บันทึกข้ามสคริปต์ถ้ามี
state.espTable = state.espTable or {} -- map userId -> info
state.pools = state.pools or {billboards = {}, highlights = {}}
state.config = state.config or {
    enabled = false,
    updateRate = 10,             -- updates per second (10 => 0.1s interval)
    maxDistance = 250,           -- เมตร ในเกม units
    maxVisibleCount = 60,        -- limit จำนวน ESP แสดงพร้อมกัน (ป้องกัน overload)
    showName = true,
    showHealth = true,
    showDistance = true,
    espColor = Color3.fromRGB(255, 50, 50),
    labelScale = 1,              -- scale ของข้อความ (TextScaled true จะอิงขนาด parent)
    alwaysOnTop = false,         -- BillboardGui.AlwaysOnTop (ถ้า true จะไม่ถูกบัง)
    smartHideCenter = true,      -- ซ่อน label ถ้ามันบังหน้าจอกลาง (ปรับได้)
    centerHideRadius = 0.12,     -- % screen radius จาก center ที่จะซ่อน (0.12 => 12%)
    raycastOcclusion = false,    -- ถ้าต้องการเพิ่ม check line-of-sight (ถ้าเปิดจะทำงานแบบ throttled)
    raycastInterval = 0.6,       -- วินาทีต่อการ raycast ต่อตัว (ถ้าเปิด)
    highlightEnabled = false,
    highlightFillTransparency = 0.6,
    highlightOutlineTransparency = 0.6,
    teamCheck = true,            -- ไม่แสดง ESP ของเพื่อนร่วมทีม (ถ้าเกมมีทีม)
    ignoreLocalPlayer = true,    -- ไม่แสดงตัวเอง
}

-- pooling helpers
local function borrowBillboard()
    local pool = state.pools.billboards
    if #pool > 0 then
        return table.remove(pool)
    else
        -- สร้างใหม่
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "ATG_ESP"
        billboard.Size = UDim2.new(0, 150, 0, 30)
        billboard.StudsOffset = Vector3.new(0, 2.6, 0)
        billboard.Adornee = nil
        billboard.AlwaysOnTop = state.config.alwaysOnTop
        billboard.ResetOnSpawn = false

        local label = Instance.new("TextLabel")
        label.Name = "ATG_ESP_Label"
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.BorderSizePixel = 0
        label.Text = ""
        label.TextScaled = true
        label.Font = Enum.Font.GothamBold
        label.TextStrokeTransparency = 0.4
        label.TextStrokeColor3 = Color3.new(0,0,0)
        label.TextWrapped = true
        label.Parent = billboard

        return {billboard = billboard, label = label}
    end
end

local function returnBillboard(obj)
    if not obj or not obj.billboard then return end
    pcall(function()
        obj.label.Text = ""
        obj.billboard.Parent = nil
        obj.billboard.Adornee = nil
    end)
    table.insert(state.pools.billboards, obj)
end

local function borrowHighlight()
    local pool = state.pools.highlights
    if #pool > 0 then
        return table.remove(pool)
    else
        local hl = Instance.new("Highlight")
        hl.Name = "ATG_ESP_Highlight"
        hl.Enabled = false
        return hl
    end
end

local function returnHighlight(hl)
    if not hl then return end
    pcall(function()
        hl.Enabled = false
        hl.Adornee = nil
        hl.Parent = nil
    end)
    table.insert(state.pools.highlights, hl)
end

-- helper utilities
local function getHRP(player)
    if not player or not player.Character then return nil end
    return player.Character:FindFirstChild("HumanoidRootPart")
end
local function getHumanoid(char)
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

local function isSameTeam(a,b)
    -- best-effort: ถ้าตัวเกมมี Team, compare Team property
    if not a or not b then return false end
    if a.Team and b.Team and a.Team == b.Team then
        return true
    end
    return false
end

-- create / remove logic (doesn't connect RenderStepped per-player)
local function ensureEntryForPlayer(p)
    if not p then return end
    local uid = p.UserId
    if state.espTable[uid] then return state.espTable[uid] end

    local info = {
        player = p,
        billboardObj = nil, -- {billboard,label}
        highlightObj = nil, -- Highlight instance
        lastVisible = false,
        lastScreenPos = Vector2.new(0,0),
        lastDistance = math.huge,
        lastRaycast = -999,
        connected = true, -- if we have CharacterAdded connection
        charConn = nil
    }

    -- connect character added to reattach Adornee when respawn
    info.charConn = p.CharacterAdded:Connect(function(char)
        -- small delay ให้เวลา Head สร้าง
        task.wait(0.05)
        if info.billboardObj and info.billboardObj.billboard then
            local head = char:FindFirstChild("Head") or char:FindFirstChild("UpperTorso") or char:FindFirstChild("HumanoidRootPart")
            if head then
                info.billboardObj.billboard.Adornee = head
            end
        end
        if info.highlightObj then
            info.highlightObj.Adornee = char
        end
    end)

    state.espTable[uid] = info
    return info
end

local function cleanupEntry(uid)
    local info = state.espTable[uid]
    if not info then return end
    pcall(function()
        if info.charConn then info.charConn:Disconnect() info.charConn = nil end
        if info.billboardObj then
            returnBillboard(info.billboardObj)
            info.billboardObj = nil
        end
        if info.highlightObj then
            returnHighlight(info.highlightObj)
            info.highlightObj = nil
        end
    end)
    state.espTable[uid] = nil
end

-- visibility check (distance + on-screen + optional raycast)
local function shouldShowFor(info)
    if not info or not info.player then return false end
    local p = info.player
    if not p.Character or not p.Character.Parent then return false end
    if state.config.ignoreLocalPlayer and p == LocalPlayer then return false end
    if state.config.teamCheck and isSameTeam(p, LocalPlayer) then return false end

    local myHRP = getHRP(LocalPlayer)
    local theirHRP = getHRP(p)
    if not myHRP or not theirHRP then return false end

    local dist = (myHRP.Position - theirHRP.Position).Magnitude
    if dist > state.config.maxDistance then
        return false
    end

    -- screen check
    local head = p.Character:FindFirstChild("Head") or p.Character:FindFirstChild("UpperTorso") or theirHRP
    if not head then return false end
    local screenPos, onScreen = Camera:WorldToViewportPoint(head.Position)
    if not onScreen then return false end

    -- smartCenter hide: ถ้า label อยู่ใกล้หน้าจอกลางมากเกินไป
    if state.config.smartHideCenter then
        local sx = screenPos.X / Camera.ViewportSize.X
        local sy = screenPos.Y / Camera.ViewportSize.Y
        local cx = 0.5
        local cy = 0.5
        local dx = sx - cx
        local dy = sy - cy
        local d = math.sqrt(dx*dx + dy*dy)
        if d < state.config.centerHideRadius then
            return false
        end
    end

    -- optional throttled raycast occlusion (ถ้าเปิด)
    if state.config.raycastOcclusion then
        local now = tick()
        if now - info.lastRaycast >= state.config.raycastInterval then
            info.lastRaycast = now
            local origin = Camera.CFrame.Position
            local direction = (head.Position - origin)
            local rayParams = RaycastParams.new()
            rayParams.FilterDescendantsInstances = {LocalPlayer.Character}
            rayParams.FilterType = Enum.RaycastFilterType.Blacklist
            local r = workspace:Raycast(origin, direction, rayParams)
            -- ถ้าวัตถุติดกันและไม่ใช่ตัวเป้าหมาย แปลว่าไม่ visible
            if r and r.Instance and not r.Instance:IsDescendantOf(p.Character) then
                return false
            end
        else
            -- ใช้ last known result (ไม่ทำ raycast ทุก frame)
            -- ถ้าไม่มี last result ให้อนุรักษ์ default true
        end
    end

    return true
end

-- update label content (only when changed)
local function buildLabelText(p)
    local parts = {}
    if state.config.showName then table.insert(parts, p.DisplayName or p.Name) end
    local hum = getHumanoid(p.Character)
    if state.config.showHealth and hum then
        table.insert(parts, "HP:" .. math.floor(hum.Health))
    end
    if state.config.showDistance then
        local myHRP = getHRP(LocalPlayer)
        local theirHRP = getHRP(p)
        if myHRP and theirHRP then
            local d = math.floor((myHRP.Position - theirHRP.Position).Magnitude)
            table.insert(parts, "[" .. d .. "m]")
        end
    end
    return table.concat(parts, " | ")
end

-- main centralized updater (throttled)
local accumulator = 0
local updateInterval = 1 / math.max(1, state.config.updateRate) -- secs
local lastVisibleCount = 0

local function performUpdate(dt)
    accumulator = accumulator + dt
    updateInterval = 1 / math.max(1, state.config.updateRate)
    if accumulator < updateInterval then return end
    accumulator = accumulator - updateInterval

    -- gather players (and ensure entries exist)
    local visibleCount = 0
    local players = Players:GetPlayers()
    for _, p in ipairs(players) do
        if p ~= LocalPlayer or not state.config.ignoreLocalPlayer then
            ensureEntryForPlayer(p)
        end
    end

    -- iterate entries and decide show/hide
    for uid, info in pairs(state.espTable) do
        local p = info.player
        if not p or not p.Parent then
            cleanupEntry(uid)
        else
            local canShow = state.config.enabled and shouldShowFor(info)
            if canShow and visibleCount >= state.config.maxVisibleCount then
                -- เกิน limit: ซ่อนเพื่อความเสถียร
                canShow = false
            end

            if canShow then
                visibleCount = visibleCount + 1
                -- ensure billboard exists
                if not info.billboardObj then
                    local obj = borrowBillboard()
                    local head = p.Character and (p.Character:FindFirstChild("Head") or p.Character:FindFirstChild("UpperTorso") or getHRP(p))
                    if head then
                        obj.billboard.Parent = head
                        obj.billboard.Adornee = head
                        obj.billboard.AlwaysOnTop = state.config.alwaysOnTop
                        info.billboardObj = obj
                    else
                        returnBillboard(obj)
                        info.billboardObj = nil
                    end
                end

                -- ensure highlight if enabled
                if state.config.highlightEnabled and not info.highlightObj then
                    local hl = borrowHighlight()
                    hl.Adornee = p.Character
                    hl.Parent = p.Character
                    hl.Enabled = true
                    hl.FillColor = state.config.espColor
                    hl.FillTransparency = state.config.highlightFillTransparency
                    hl.OutlineColor = state.config.espColor
                    hl.OutlineTransparency = state.config.highlightOutlineTransparency
                    info.highlightObj = hl
                elseif (not state.config.highlightEnabled) and info.highlightObj then
                    returnHighlight(info.highlightObj)
                    info.highlightObj = nil
                end

                -- update label text & color only when changed
                if info.billboardObj and info.billboardObj.label then
                    local txt = buildLabelText(p)
                    if info.billboardObj.label.Text ~= txt then
                        info.billboardObj.label.Text = txt
                    end
                    -- color
                    if info.billboardObj.label.TextColor3 ~= state.config.espColor then
                        info.billboardObj.label.TextColor3 = state.config.espColor
                    end
                    -- scale / Size adjustments
                    info.billboardObj.billboard.Size = UDim2.new(0, math.clamp(120 + (#txt * 4), 100, 280), 0, math.clamp(16 * state.config.labelScale, 12, 48))
                end

            else
                -- hide (recycle billboard/highlight)
                if info.billboardObj then
                    returnBillboard(info.billboardObj)
                    info.billboardObj = nil
                end
                if info.highlightObj then
                    returnHighlight(info.highlightObj)
                    info.highlightObj = nil
                end
            end
        end
    end

    lastVisibleCount = visibleCount
end

-- main connection (unbind old if exists)
if state._espHeartbeatConn then
    pcall(function() state._espHeartbeatConn:Disconnect() end)
    state._espHeartbeatConn = nil
end

state._espHeartbeatConn = RunService.Heartbeat:Connect(performUpdate)

-- Player join/leave cleanup
Players.PlayerRemoving:Connect(function(p)
    if not p then return end
    cleanupEntry(p.UserId)
end)

-- UI integration: (ใช้ API ที่ให้มาในตัวอย่าง Tabs.*)
-- ฟังก์ชัน applyConfig เพื่อ sync ค่าจาก UI ไป state.config
local function applyConfigFromUI(uiConfig)
    for k,v in pairs(uiConfig) do
        state.config[k] = v
    end
end

-- Exposed functions for the UI to hook into:
local ESP_API = {}

function ESP_API.ToggleEnabled(v)
    state.config.enabled = v
    if not v then
        -- immediate cleanup of visuals but keep entries
        for uid,info in pairs(state.espTable) do
            if info.billboardObj then
                returnBillboard(info.billboardObj)
                info.billboardObj = nil
            end
            if info.highlightObj then
                returnHighlight(info.highlightObj)
                info.highlightObj = nil
            end
        end
    end
end

function ESP_API.SetColor(c)
    state.config.espColor = c
end

function ESP_API.SetShowName(v) state.config.showName = v end
function ESP_API.SetShowHealth(v) state.config.showHealth = v end
function ESP_API.SetShowDistance(v) state.config.showDistance = v end
function ESP_API.SetUpdateRate(v) state.config.updateRate = math.clamp(v, 1, 60) end
function ESP_API.SetMaxDistance(v) state.config.maxDistance = math.max(20, v) end
function ESP_API.SetLabelScale(v) state.config.labelScale = math.clamp(v, 0.5, 3) end
function ESP_API.SetAlwaysOnTop(v) state.config.alwaysOnTop = v end
function ESP_API.SetHighlightEnabled(v) state.config.highlightEnabled = v end
function ESP_API.SetHighlightFillTrans(v) state.config.highlightFillTransparency = math.clamp(v, 0, 1) end
function ESP_API.SetHighlightOutlineTrans(v) state.config.highlightOutlineTransparency = math.clamp(v, 0, 1) end
function ESP_API.ResetConfig()
    state.config = {
        enabled = false,
        updateRate = 10,
        maxDistance = 250,
        maxVisibleCount = 60,
        showName = true,
        showHealth = true,
        showDistance = true,
        espColor = Color3.fromRGB(255, 50, 50),
        labelScale = 1,
        alwaysOnTop = false,
        smartHideCenter = true,
        centerHideRadius = 0.12,
        raycastOcclusion = false,
        raycastInterval = 0.6,
        highlightEnabled = false,
        highlightFillTransparency = 0.6,
        highlightOutlineTransparency = 0.6,
        teamCheck = true,
        ignoreLocalPlayer = true,
    }
end

-- expose API object for UI code below
_G.ATG_ESP_API = ESP_API

-- Example: UI hookup (ปรับให้เข้ากับ API Tabs.* ที่ให้มา)
-- สมมติมี Tabs.ESP อยู่แล้ว
if Tabs and Tabs.ESP then
    local espToggle = Tabs.ESP:AddToggle("ESPToggle", { Title = "ESP", Default = state.config.enabled })
    espToggle:OnChanged(function(v) ESP_API.ToggleEnabled(v) end)

    local color = Tabs.ESP:AddColorpicker("ESPColor", { Title = "ESP Color", Default = state.config.espColor })
    color:OnChanged(function(c) ESP_API.SetColor(c) end)

    Tabs.ESP:AddToggle("ESP_Name", { Title = "Show Name", Default = state.config.showName }):OnChanged(function(v) ESP_API.SetShowName(v) end)
    Tabs.ESP:AddToggle("ESP_Health", { Title = "Show Health", Default = state.config.showHealth }):OnChanged(function(v) ESP_API.SetShowHealth(v) end)
    Tabs.ESP:AddToggle("ESP_Distance", { Title = "Show Distance", Default = state.config.showDistance }):OnChanged(function(v) ESP_API.SetShowDistance(v) end)

    Tabs.ESP:AddToggle("ESP_Highlight", { Title = "Highlight", Default = state.config.highlightEnabled }):OnChanged(function(v) ESP_API.SetHighlightEnabled(v) end)
    Tabs.ESP:AddSlider("ESP_HighlightFill", { Title = "Highlight Fill Transparency", Default = state.config.highlightFillTransparency, Min = 0, Max = 1, Rounding = 0.01 }):OnChanged(function(v) ESP_API.SetHighlightFillTrans(v) end)
    Tabs.ESP:AddSlider("ESP_HighlightOutline", { Title = "Highlight Outline Transparency", Default = state.config.highlightOutlineTransparency, Min = 0, Max = 1, Rounding = 0.01 }):OnChanged(function(v) ESP_API.SetHighlightOutlineTrans(v) end)

    Tabs.ESP:AddSlider("ESP_Rate", { Title = "Update Rate (per sec)", Default = state.config.updateRate, Min = 1, Max = 60, Rounding = 1 }):OnChanged(function(v) ESP_API.SetUpdateRate(v) end)
    Tabs.ESP:AddSlider("ESP_MaxDist", { Title = "Max Distance", Default = state.config.maxDistance, Min = 50, Max = 1000, Rounding = 1 }):OnChanged(function(v) ESP_API.SetMaxDistance(v) end)
    Tabs.ESP:AddSlider("ESP_LabelScale", { Title = "Label Scale", Default = state.config.labelScale, Min = 0.5, Max = 3, Rounding = 0.1 }):OnChanged(function(v) ESP_API.SetLabelScale(v) end)
    Tabs.ESP:AddToggle("ESP_AlwaysOnTop", { Title = "AlwaysOnTop", Default = state.config.alwaysOnTop }):OnChanged(function(v) ESP_API.SetAlwaysOnTop(v) end)

    Tabs.ESP:AddButton({
        Title = "Reset ESP Config",
        Description = "Reset to sane defaults",
        Callback = function()
            ESP_API.ResetConfig()
            -- อัพเดต UI values (ถ้า API library มี method SetValue ให้เรียก; ตัวอย่างไม่รู้ API ชื่อเฉพาะ)
            -- ถ้าไม่มีให้แอยด์ผู้ใช้รีสตาร์ท UI หรือเราจะเก็บค่าเริ่มต้นไว้แยก
            print("ESP config reset. Reopen UI to sync values.")
        end
    })
end

-- end of script
