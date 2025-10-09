-- ATG ESP (optimized) — patched version (UI sync + Reset fixes)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- state + config (เก็บค่า default ที่เหมาะสม)
local state = state or {}
state.espTable = state.espTable or {}
state.pools = state.pools or {billboards = {}, highlights = {}}
state.config = state.config or {
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

-- Helpers: pooling...
local function borrowBillboard()
    local pool = state.pools.billboards
    if #pool > 0 then
        return table.remove(pool)
    else
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

-- util
local function getHRP(player)
    if not player or not player.Character then return nil end
    return player.Character:FindFirstChild("HumanoidRootPart")
end
local function getHumanoid(char)
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end
local function isSameTeam(a,b)
    if not a or not b then return false end
    if a.Team and b.Team and a.Team == b.Team then return true end
    return false
end

-- entries
local function ensureEntryForPlayer(p)
    if not p then return end
    local uid = p.UserId
    if state.espTable[uid] then return state.espTable[uid] end

    local info = {
        player = p,
        billboardObj = nil,
        highlightObj = nil,
        lastVisible = false,
        lastScreenPos = Vector2.new(0,0),
        lastDistance = math.huge,
        lastRaycast = -999,
        connected = true,
        charConn = nil
    }

    info.charConn = p.CharacterAdded:Connect(function(char)
        task.wait(0.05)
        if info.billboardObj and info.billboardObj.billboard then
            local head = char:FindFirstChild("Head") or char:FindFirstChild("UpperTorso") or char:FindFirstChild("HumanoidRootPart")
            if head then info.billboardObj.billboard.Adornee = head end
        end
        if info.highlightObj then info.highlightObj.Adornee = char end
    end)

    state.espTable[uid] = info
    return info
end

local function cleanupEntry(uid)
    local info = state.espTable[uid]
    if not info then return end
    pcall(function()
        if info.charConn then info.charConn:Disconnect() info.charConn = nil end
        if info.billboardObj then returnBillboard(info.billboardObj) info.billboardObj = nil end
        if info.highlightObj then returnHighlight(info.highlightObj) info.highlightObj = nil end
    end)
    state.espTable[uid] = nil
end

-- visibility
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
    if dist > state.config.maxDistance then return false end

    local head = p.Character:FindFirstChild("Head") or p.Character:FindFirstChild("UpperTorso") or theirHRP
    if not head then return false end
    local screenPos, onScreen = Camera:WorldToViewportPoint(head.Position)
    if not onScreen then return false end

    if state.config.smartHideCenter then
        local sx = screenPos.X / Camera.ViewportSize.X
        local sy = screenPos.Y / Camera.ViewportSize.Y
        local dx = sx - 0.5
        local dy = sy - 0.5
        local d = math.sqrt(dx*dx + dy*dy)
        if d < state.config.centerHideRadius then return false end
    end

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
            if r and r.Instance and not r.Instance:IsDescendantOf(p.Character) then return false end
        end
    end

    return true
end

-- label text
local function buildLabelText(p)
    local parts = {}
    if state.config.showName then table.insert(parts, p.DisplayName or p.Name) end
    local hum = getHumanoid(p.Character)
    if state.config.showHealth and hum then table.insert(parts, "HP:" .. math.floor(hum.Health)) end
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

-- centralized updater
local accumulator = 0
local updateInterval = 1 / math.max(1, state.config.updateRate)
local lastVisibleCount = 0

local function performUpdate(dt)
    accumulator = accumulator + dt
    updateInterval = 1 / math.max(1, state.config.updateRate)
    if accumulator < updateInterval then return end
    accumulator = accumulator - updateInterval

    local visibleCount = 0
    local players = Players:GetPlayers()
    for _, p in ipairs(players) do
        if p ~= LocalPlayer or not state.config.ignoreLocalPlayer then ensureEntryForPlayer(p) end
    end

    for uid, info in pairs(state.espTable) do
        local p = info.player
        if not p or not p.Parent then
            cleanupEntry(uid)
        else
            local canShow = state.config.enabled and shouldShowFor(info)
            if canShow and visibleCount >= state.config.maxVisibleCount then canShow = false end

            if canShow then
                visibleCount = visibleCount + 1
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

                if info.billboardObj and info.billboardObj.label then
                    local txt = buildLabelText(p)
                    if info.billboardObj.label.Text ~= txt then info.billboardObj.label.Text = txt end
                    if info.billboardObj.label.TextColor3 ~= state.config.espColor then info.billboardObj.label.TextColor3 = state.config.espColor end
                    info.billboardObj.billboard.Size = UDim2.new(0, math.clamp(120 + (#txt * 4), 100, 280), 0, math.clamp(16 * state.config.labelScale, 12, 48))
                    info.billboardObj.billboard.AlwaysOnTop = state.config.alwaysOnTop
                end
            else
                if info.billboardObj then returnBillboard(info.billboardObj) info.billboardObj = nil end
                if info.highlightObj then returnHighlight(info.highlightObj) info.highlightObj = nil end
            end
        end
    end

    lastVisibleCount = visibleCount
end

-- connect heartbeat
if state._espHeartbeatConn then pcall(function() state._espHeartbeatConn:Disconnect() end) state._espHeartbeatConn = nil end
state._espHeartbeatConn = RunService.Heartbeat:Connect(performUpdate)

-- cleanup on leave
Players.PlayerRemoving:Connect(function(p) if not p then return end cleanupEntry(p.UserId) end)

-- UI sync helpers (รองรับหลายไลบรารี)
local uiRefs = {} -- store widgets by key

local function trySetWidgetValue(widget, val)
    if not widget then return end
    pcall(function()
        -- common APIs across various UI libs
        if widget.SetValue then widget:SetValue(val) end
        if widget.Set then widget:Set(val) end
        if widget.SetState then widget:SetState(val) end
        if widget.SetValueNoCallback then widget:SetValueNoCallback(val) end
        -- some libs store .Value property
        if widget.Value ~= nil then widget.Value = val end
    end)
end

-- function to apply config to runtime (and update visuals immediately)
local function applyConfigToState(cfg)
    -- shallow copy allowed (cfg is a table)
    for k, v in pairs(cfg) do state.config[k] = v end

    -- immediate side-effects
    updateInterval = 1 / math.max(1, state.config.updateRate)

    -- update existing billboards / highlights
    for uid, info in pairs(state.espTable) do
        if info.billboardObj and info.billboardObj.billboard then
            local bb = info.billboardObj.billboard
            local label = info.billboardObj.label
            label.TextColor3 = state.config.espColor
            bb.AlwaysOnTop = state.config.alwaysOnTop
            bb.Size = UDim2.new(0, math.clamp(120 + (#label.Text * 4), 100, 280), 0, math.clamp(16 * state.config.labelScale, 12, 48))
        end
        if info.highlightObj then
            local hl = info.highlightObj
            hl.FillColor = state.config.espColor
            hl.FillTransparency = state.config.highlightFillTransparency
            hl.OutlineColor = state.config.espColor
            hl.OutlineTransparency = state.config.highlightOutlineTransparency
            hl.Enabled = state.config.highlightEnabled
            if not state.config.highlightEnabled then
                returnHighlight(hl)
                info.highlightObj = nil
            end
        end
    end
end

-- Exposed API
local ESP_API = {}

function ESP_API.ToggleEnabled(v)
    state.config.enabled = v
    if not v then
        for uid,info in pairs(state.espTable) do
            if info.billboardObj then returnBillboard(info.billboardObj) info.billboardObj = nil end
            if info.highlightObj then returnHighlight(info.highlightObj) info.highlightObj = nil end
        end
    end
end

function ESP_API.SetColor(c)
    state.config.espColor = c
    -- live update
    for _,info in pairs(state.espTable) do
        if info.billboardObj and info.billboardObj.label then info.billboardObj.label.TextColor3 = c end
        if info.highlightObj then
            info.highlightObj.FillColor = c
            info.highlightObj.OutlineColor = c
        end
    end
end

function ESP_API.SetShowName(v) state.config.showName = v end
function ESP_API.SetShowHealth(v) state.config.showHealth = v end
function ESP_API.SetShowDistance(v) state.config.showDistance = v end
function ESP_API.SetUpdateRate(v)
    state.config.updateRate = math.clamp(math.floor(v), 1, 60)
    updateInterval = 1 / state.config.updateRate
end
function ESP_API.SetMaxDistance(v) state.config.maxDistance = math.max(20, v) end
function ESP_API.SetLabelScale(v)
    state.config.labelScale = math.clamp(v, 0.5, 3)
    -- apply to existing labels
    for _,info in pairs(state.espTable) do
        if info.billboardObj and info.billboardObj.label and info.billboardObj.billboard then
            local label = info.billboardObj.label
            info.billboardObj.billboard.Size = UDim2.new(0, math.clamp(120 + (#label.Text * 4), 100, 280), 0, math.clamp(16 * state.config.labelScale, 12, 48))
        end
    end
end
function ESP_API.SetAlwaysOnTop(v)
    state.config.alwaysOnTop = v
    for _,info in pairs(state.espTable) do
        if info.billboardObj and info.billboardObj.billboard then info.billboardObj.billboard.AlwaysOnTop = v end
    end
end
function ESP_API.SetHighlightEnabled(v)
    state.config.highlightEnabled = v
    -- toggle highlights on existing entries
    for _,info in pairs(state.espTable) do
        if v and not info.highlightObj and info.player and info.player.Character then
            local hl = borrowHighlight()
            hl.Adornee = info.player.Character
            hl.Parent = info.player.Character
            hl.Enabled = true
            hl.FillColor = state.config.espColor
            hl.FillTransparency = state.config.highlightFillTransparency
            hl.OutlineColor = state.config.espColor
            hl.OutlineTransparency = state.config.highlightOutlineTransparency
            info.highlightObj = hl
        elseif (not v) and info.highlightObj then
            returnHighlight(info.highlightObj)
            info.highlightObj = nil
        end
    end
end
function ESP_API.SetHighlightFillTrans(v) state.config.highlightFillTransparency = math.clamp(v, 0, 1) end
function ESP_API.SetHighlightOutlineTrans(v) state.config.highlightOutlineTransparency = math.clamp(v, 0, 1) end

function ESP_API.ResetConfig()
    local defaults = {
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
    -- replace state.config
    state.config = defaults
    -- apply runtime changes
    applyConfigToState(state.config)
    -- update UI elements if present
    -- try to update known widgets in uiRefs
    pcall(function()
        trySetWidgetValue(uiRefs.ESPToggle, state.config.enabled)
        trySetWidgetValue(uiRefs.ESPColor, state.config.espColor)
        trySetWidgetValue(uiRefs.ESP_Name, state.config.showName)
        trySetWidgetValue(uiRefs.ESP_Health, state.config.showHealth)
        trySetWidgetValue(uiRefs.ESP_Distance, state.config.showDistance)
        trySetWidgetValue(uiRefs.ESP_Highlight, state.config.highlightEnabled)
        trySetWidgetValue(uiRefs.ESP_HighlightFill, state.config.highlightFillTransparency)
        trySetWidgetValue(uiRefs.ESP_HighlightOutline, state.config.highlightOutlineTransparency)
        trySetWidgetValue(uiRefs.ESP_Rate, state.config.updateRate)
        trySetWidgetValue(uiRefs.ESP_MaxDist, state.config.maxDistance)
        trySetWidgetValue(uiRefs.ESP_LabelScale, state.config.labelScale)
        trySetWidgetValue(uiRefs.ESP_AlwaysOnTop, state.config.alwaysOnTop)
    end)
end

-- expose API
_G.ATG_ESP_API = ESP_API

-- UI hookup (store refs and ensure OnChanged hooks update state)
if Tabs and Tabs.ESP then
    -- store ref for safe-set on Reset
    uiRefs.ESPToggle = Tabs.ESP:AddToggle("ESPToggle", { Title = "ESP", Default = state.config.enabled })
    if uiRefs.ESPToggle then uiRefs.ESPToggle:OnChanged(function(v) ESP_API.ToggleEnabled(v) end) end

    uiRefs.ESPColor = Tabs.ESP:AddColorpicker("ESPColor", { Title = "ESP Color", Default = state.config.espColor })
    if uiRefs.ESPColor then uiRefs.ESPColor:OnChanged(function(c) ESP_API.SetColor(c) end) end

    uiRefs.ESP_Name = Tabs.ESP:AddToggle("ESP_Name", { Title = "Show Name", Default = state.config.showName })
    if uiRefs.ESP_Name then uiRefs.ESP_Name:OnChanged(function(v) ESP_API.SetShowName(v) end) end

    uiRefs.ESP_Health = Tabs.ESP:AddToggle("ESP_Health", { Title = "Show Health", Default = state.config.showHealth })
    if uiRefs.ESP_Health then uiRefs.ESP_Health:OnChanged(function(v) ESP_API.SetShowHealth(v) end) end

    uiRefs.ESP_Distance = Tabs.ESP:AddToggle("ESP_Distance", { Title = "Show Distance", Default = state.config.showDistance })
    if uiRefs.ESP_Distance then uiRefs.ESP_Distance:OnChanged(function(v) ESP_API.SetShowDistance(v) end) end

    uiRefs.ESP_Highlight = Tabs.ESP:AddToggle("ESP_Highlight", { Title = "Highlight", Default = state.config.highlightEnabled })
    if uiRefs.ESP_Highlight then uiRefs.ESP_Highlight:OnChanged(function(v) ESP_API.SetHighlightEnabled(v) end) end

    uiRefs.ESP_HighlightFill = Tabs.ESP:AddSlider("ESP_HighlightFill", { Title = "Highlight Fill Transparency", Default = state.config.highlightFillTransparency, Min = 0, Max = 1, Rounding = 0.01 })
    if uiRefs.ESP_HighlightFill then uiRefs.ESP_HighlightFill:OnChanged(function(v) ESP_API.SetHighlightFillTrans(v) end) end

    uiRefs.ESP_HighlightOutline = Tabs.ESP:AddSlider("ESP_HighlightOutline", { Title = "Highlight Outline Transparency", Default = state.config.highlightOutlineTransparency, Min = 0, Max = 1, Rounding = 0.01 })
    if uiRefs.ESP_HighlightOutline then uiRefs.ESP_HighlightOutline:OnChanged(function(v) ESP_API.SetHighlightOutlineTrans(v) end) end

    uiRefs.ESP_Rate = Tabs.ESP:AddSlider("ESP_Rate", { Title = "Update Rate (per sec)", Default = state.config.updateRate, Min = 1, Max = 60, Rounding = 1 })
    if uiRefs.ESP_Rate then uiRefs.ESP_Rate:OnChanged(function(v) ESP_API.SetUpdateRate(v) end) end

    uiRefs.ESP_MaxDist = Tabs.ESP:AddSlider("ESP_MaxDist", { Title = "Max Distance", Default = state.config.maxDistance, Min = 50, Max = 1000, Rounding = 1 })
    if uiRefs.ESP_MaxDist then uiRefs.ESP_MaxDist:OnChanged(function(v) ESP_API.SetMaxDistance(v) end) end

    uiRefs.ESP_LabelScale = Tabs.ESP:AddSlider("ESP_LabelScale", { Title = "Label Scale", Default = state.config.labelScale, Min = 0.5, Max = 3, Rounding = 0.1 })
    if uiRefs.ESP_LabelScale then uiRefs.ESP_LabelScale:OnChanged(function(v) ESP_API.SetLabelScale(v) end) end

    uiRefs.ESP_AlwaysOnTop = Tabs.ESP:AddToggle("ESP_AlwaysOnTop", { Title = "AlwaysOnTop", Default = state.config.alwaysOnTop })
    if uiRefs.ESP_AlwaysOnTop then uiRefs.ESP_AlwaysOnTop:OnChanged(function(v) ESP_API.SetAlwaysOnTop(v) end) end

    Tabs.ESP:AddButton({
        Title = "Reset ESP Config",
        Description = "Reset to sane defaults",
        Callback = function()
            ESP_API.ResetConfig()
            print("ESP config reset. UI should be synced.")
        end
    })
end

-- end
