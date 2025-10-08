-- Optimized ESP (Single update loop, pooling, UI hooks, save/load)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- Detect Drawing API if available (exploit env). If your safeNewDrawing exists, use it.
local hasDrawing = (typeof(Drawing) == "table") or (type(safeNewDrawing) == "function")
local useSafeNewDrawing = (type(safeNewDrawing) == "function")

-- Defaults
local DEFAULT_CONFIG = {
    enabled = false,
    renderMode = "2D", -- "2D" (Drawing) or "Billboard"
    updateRate = 10, -- updates per second
    maxDistance = 250, -- meters
    showName = true,
    showHealth = true,
    showDistance = true,
    textSize = 16,
    espColor = Color3.fromRGB(255, 50, 50),
    boxThickness = 1,
    labelOffsetY = 2.6, -- studs (for billboard)
    highlightEnabled = true,
    highlightFillTransparency = 0.7,
    highlightOutlineTransparency = 0.4,
    occlusionCheck = false, -- raycast check (may be expensive if enabled)
    hideIfCentered = false, -- if true, hide ESP when near screen center (reduce obstruction)
    hideCenterRadius = 0.12, -- fraction of screen (0..0.5)
}

-- Config persistence file name (for exploit runners)
local CONFIG_FILENAME = "atg_esp_config.json"

-- state
local state = {
    config = DEFAULT_CONFIG,
    espTable = {}, -- [player] = info
    running = false,
}

-- helper: deep copy table
local function deepCopy(t)
    local nt = {}
    for k,v in pairs(t) do
        if type(v) == "table" then nt[k] = deepCopy(v) else nt[k] = v end
    end
    return nt
end

-- Load config (supports writefile/readfile in exploit env; falls back to _G)
local function SaveConfig()
    local ok, err = pcall(function()
        local json = HttpService:JSONEncode(state.config)
        if writefile then
            writefile(CONFIG_FILENAME, json)
        else
            _G.ATG_ESP_SAVED_CONFIG = json
        end
    end)
    if not ok then warn("ESP: SaveConfig failed:", err) end
end

local function LoadConfig()
    local ok, content = pcall(function()
        if readfile and isfile and isfile(CONFIG_FILENAME) then
            return readfile(CONFIG_FILENAME)
        else
            return _G and _G.ATG_ESP_SAVED_CONFIG
        end
    end)
    if ok and content then
        local suc, decoded = pcall(function() return HttpService:JSONDecode(content) end)
        if suc and type(decoded) == "table" then
            -- merge with defaults
            local merged = deepCopy(DEFAULT_CONFIG)
            for k,v in pairs(decoded) do merged[k] = v end
            state.config = merged
            return
        end
    end
    -- fallback default
    state.config = deepCopy(DEFAULT_CONFIG)
end

-- Reset config to defaults
local function ResetConfig()
    state.config = deepCopy(DEFAULT_CONFIG)
    SaveConfig()
end

-- Utility: safe property set to avoid expensive updates if not necessary
local function safeSet(obj, prop, value)
    if not obj then return end
    if obj[prop] ~= value then
        obj[prop] = value
    end
end

-- Create or recycle ESP visuals for a player
local function createESPForPlayer(player)
    if not player or player == LocalPlayer then return end
    if state.espTable[player] then return end

    local info = {
        player = player,
        billboard = nil, -- BillboardGui (if used)
        label = nil,
        drawings = nil, -- {box, text, line}
        highlight = nil,
        lastVisible = false,
        lastText = "",
        lastColor = nil,
        charConn = nil,
    }
    state.espTable[player] = info

    -- cleanup function
    local function cleanup()
        pcall(function()
            if info.billboard then info.billboard:Destroy() info.billboard = nil end
            if info.label then info.label:Destroy() info.label = nil end
            if info.drawings then
                for _,d in pairs(info.drawings) do
                    if d and type(d.Destroy) == "function" then
                        d:Remove() -- Drawing API uses Remove()
                    elseif d and type(d) == "userdata" then
                        -- fallback
                        pcall(function() d:Remove() end)
                    end
                end
                info.drawings = nil
            end
            if info.highlight then
                info.highlight:Destroy()
                info.highlight = nil
            end
            if info.charConn then info.charConn:Disconnect() info.charConn = nil end
        end)
        state.espTable[player] = nil
    end

    -- create highlight object (but don't enable Adornee until char exists)
    if state.config.highlightEnabled then
        local ok, h = pcall(function()
            local hl = Instance.new("Highlight")
            hl.Name = "ATG_ESP_Highlight"
            hl.FillColor = state.config.espColor
            hl.FillTransparency = state.config.highlightFillTransparency
            hl.OutlineTransparency = state.config.highlightOutlineTransparency
            hl.Enabled = false
            hl.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui") or game:GetService("CoreGui") -- safe parent
            return hl
        end)
        if ok and h then info.highlight = h end
    end

    -- create billboard if mode is Billboard
    if state.config.renderMode == "Billboard" then
        local function createBillboard(char)
            if not char or not char.Parent then return end
            local head = char:FindFirstChild("Head")
            if not head then return end

            pcall(function()
                if info.billboard then info.billboard:Destroy() info.billboard = nil end
                local bb = Instance.new("BillboardGui")
                bb.Name = "ATG_ESP_BB"
                bb.Size = UDim2.new(0, 200, 0, 36)
                bb.AlwaysOnTop = true
                bb.StudsOffset = Vector3.new(0, state.config.labelOffsetY, 0)
                bb.Adornee = head
                bb.Parent = head

                local label = Instance.new("TextLabel")
                label.Name = "ATG_ESP_LABEL"
                label.Size = UDim2.fromScale(1,1)
                label.BackgroundTransparency = 1
                label.TextScaled = true
                label.Font = Enum.Font.GothamBold
                label.Text = ""
                label.TextColor3 = state.config.espColor
                label.TextStrokeTransparency = 0.4
                label.Parent = bb

                info.billboard = bb
                info.label = label
            end)
        end

        -- attach to existing character
        if player.Character and player.Character.Parent then
            createBillboard(player.Character)
        end
        -- reconnect on respawn
        info.charConn = player.CharacterAdded:Connect(function(char)
            task.wait(0.05)
            if state.config.renderMode == "Billboard" then createBillboard(char) end
            if info.highlight and state.config.highlightEnabled then
                pcall(function() info.highlight.Adornee = char end)
                info.highlight.Enabled = state.config.enabled
            end
        end)
    else
        -- Drawing mode (2D). Create drawing objects now (will be positioned each update)
        if hasDrawing then
            local ok, d = pcall(function()
                local box, nameText
                if useSafeNewDrawing then
                    box = safeNewDrawing("Square", {Thickness = state.config.boxThickness, Filled = false, Visible = false})
                    nameText = safeNewDrawing("Text", {Size = state.config.textSize, Center = true, Outline = true, Visible = false, Text = player.Name})
                else
                    box = Drawing.new("Square")
                    box.Thickness = state.config.boxThickness
                    box.Filled = false
                    box.Visible = false
                    nameText = Drawing.new("Text")
                    nameText.Size = state.config.textSize
                    nameText.Center = true
                    nameText.Outline = true
                    nameText.Visible = false
                    nameText.Text = player.Name
                end
                return {box = box, text = nameText}
            end)
            if ok and d then info.drawings = d end
        end
        -- connect charAdded to set highlight adornee
        info.charConn = player.CharacterAdded:Connect(function(char)
            task.wait(0.05)
            if info.highlight and state.config.highlightEnabled then
                pcall(function() info.highlight.Adornee = char end)
                info.highlight.Enabled = state.config.enabled
            end
        end)
    end

    -- PlayerRemoving cleanup hook (in case this function called before global hook)
    player.AncestryChanged:Connect(function()
        if not player.Parent then
            cleanup()
        end
    end)

    -- expose cleanup in info for external use
    info.cleanup = cleanup
end

local function removeESPForPlayer(player)
    local info = state.espTable[player]
    if not info then return end
    pcall(function()
        if info.cleanup then info.cleanup() end
    end)
end

-- Global players hooks
Players.PlayerAdded:Connect(function(p)
    -- Small delay to allow Player object to fully init
    task.defer(function()
        if state.config.enabled and p ~= LocalPlayer then
            createESPForPlayer(p)
        end
    end)
end)
Players.PlayerRemoving:Connect(function(p)
    removeESPForPlayer(p)
end)

-- initial spawn: create entries for existing players
local function initPlayers()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and state.config.enabled then
            createESPForPlayer(p)
        end
    end
end

-- Utility: check if part is visible (occlusion) - optional and may be expensive if many checks
local function isVisibleFromCamera(worldPos)
    if not state.config.occlusionCheck then return true end
    local origin = Camera.CFrame.Position
    local direction = (worldPos - origin)
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {LocalPlayer.Character or Workspace}
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.IgnoreWater = true
    local result = Workspace:Raycast(origin, direction.Unit * math.clamp(direction.Magnitude, 0, 1000), rayParams)
    if not result then return true end
    -- if hit point is very close to worldPos, consider visible
    local hitPos = result.Position
    return (hitPos - worldPos).Magnitude < 0.5
end

-- Build label text from toggles
local function buildLabelText(player)
    local parts = {}
    if state.config.showName then table.insert(parts, player.DisplayName or player.Name) end
    if state.config.showHealth then
        local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if hum then table.insert(parts, "HP:" .. tostring(math.floor(hum.Health))) end
    end
    if state.config.showDistance then
        local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local theirHRP = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if myHRP and theirHRP then
            local d = math.floor((myHRP.Position - theirHRP.Position).Magnitude)
            table.insert(parts, "[" .. d .. "m]")
        end
    end
    return table.concat(parts, " | ")
end

-- Single update loop (throttled by config.updateRate)
local accum = 0
local function startLoop()
    if state.running then return end
    state.running = true
    accum = 0
    RunService.Heartbeat:Connect(function(dt)
        if not state.running then return end
        accum = accum + dt
        local rate = math.clamp(tonumber(state.config.updateRate) or DEFAULT_CONFIG.updateRate, 1, 60)
        local interval = 1 / rate
        if accum < interval then return end
        accum = 0

        -- iterate players
        local camCFrame = Camera.CFrame
        local viewportSize = Camera.ViewportSize
        for player, info in pairs(state.espTable) do
            local visible = false
            local labelText = ""
            if not player or not player.Character or not player.Character.Parent then
                -- ensure visuals hidden
                if info.label then safeSet(info.label, "Text", "") end
                if info.drawings then
                    if info.drawings.box then info.drawings.box.Visible = false end
                    if info.drawings.text then info.drawings.text.Visible = false end
                end
                if info.billboard then info.billboard.Enabled = false end
                if info.highlight then info.highlight.Enabled = false end
            else
                local hrp = player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Head")
                if hrp then
                    local dist = (Camera.CFrame.Position - hrp.Position).Magnitude
                    if dist <= state.config.maxDistance then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position + Vector3.new(0, state.config.labelOffsetY, 0))
                        -- hide if offscreen or behind camera
                        if onScreen then
                            -- optional: hide when it's near center to avoid obstruction
                            local hideCenter = false
                            if state.config.hideIfCentered then
                                local cx = screenPos.X / viewportSize.X - 0.5
                                local cy = screenPos.Y / viewportSize.Y - 0.5
                                local radius = state.config.hideCenterRadius
                                hideCenter = (math.abs(cx) < radius and math.abs(cy) < radius)
                            end

                            if not hideCenter then
                                -- occlusion check (optional)
                                if isVisibleFromCamera(hrp.Position) then
                                    visible = true
                                end
                            end
                        end
                    end
                end
                labelText = buildLabelText(player)
            end

            -- apply visuals based on renderMode
            if state.config.renderMode == "Billboard" then
                if info.billboard and info.label then
                    info.billboard.Enabled = visible and state.config.enabled
                    if visible and state.config.enabled then
                        if info.label.Text ~= labelText then info.label.Text = labelText end
                        if info.label.TextColor3 ~= state.config.espColor then info.label.TextColor3 = state.config.espColor end
                    end
                end
            else
                if info.drawings then
                    -- Drawing objects expect 2D coords
                    if visible and state.config.enabled then
                        local hrp = player.Character and (player.Character:FindFirstChild("Head") or player.Character:FindFirstChild("HumanoidRootPart"))
                        if hrp then
                            local pos3 = hrp.Position + Vector3.new(0, state.config.labelOffsetY, 0)
                            local screenPos, onScreen = Camera:WorldToViewportPoint(pos3)
                            if onScreen then
                                local x = screenPos.X
                                local y = screenPos.Y
                                local t = info.drawings.text
                                local b = info.drawings.box
                                if t then
                                    t.Text = labelText
                                    t.Position = Vector2.new(x, y - (state.config.textSize))
                                    t.Color = state.config.espColor
                                    t.Size = state.config.textSize
                                    t.Visible = true
                                end
                                if b then
                                    -- small box around head (approx)
                                    local size = state.config.boxThickness * 20
                                    b.Position = Vector2.new(x - size/2, y - size/2)
                                    b.Size = Vector2.new(size, size)
                                    b.Color = state.config.espColor
                                    b.Visible = true
                                end
                            else
                                -- offscreen
                                if info.drawings.text then info.drawings.text.Visible = false end
                                if info.drawings.box then info.drawings.box.Visible = false end
                            end
                        end
                    else
                        if info.drawings.text then info.drawings.text.Visible = false end
                        if info.drawings.box then info.drawings.box.Visible = false end
                    end
                end
            end

            -- highlight enable/disable
            if info.highlight then
                info.highlight.Enabled = visible and state.config.highlightEnabled and state.config.enabled
                -- update color/transparency if changed
                safeSet(info.highlight, "FillColor", state.config.espColor)
                safeSet(info.highlight, "FillTransparency", state.config.highlightFillTransparency)
                safeSet(info.highlight, "OutlineTransparency", state.config.highlightOutlineTransparency)
            end
        end
    end)
end

-- Start/Stop ESP
local function enableESP(val)
    state.config.enabled = val and true or false
    if state.config.enabled then
        -- create for existing players
        initPlayers()
        -- enable highlights adornee for those with characters
        for p, info in pairs(state.espTable) do
            if info.highlight and p.Character then
                pcall(function() info.highlight.Adornee = p.Character end)
            end
        end
        startLoop()
    else
        -- disable visuals but keep objects (so re-enabling is fast)
        for p, info in pairs(state.espTable) do
            if info.billboard then info.billboard.Enabled = false end
            if info.drawings then
                if info.drawings.text then info.drawings.text.Visible = false end
                if info.drawings.box then info.drawings.box.Visible = false end
            end
            if info.highlight then info.highlight.Enabled = false end
        end
    end
end

-- Expose Save/Load/Reset functions and UI binding examples
-- UI integration (example): hook your Tabs.ESP UI elements to these functions
-- Example usage with provided UI API:
--   local espToggle = Tabs.ESP:AddToggle("ESPToggle", { Title = "ESP", Default = state.config.enabled })
--   espToggle:OnChanged(function(v) enableESP(v) SaveConfig() end)
--   local rateSlider = Tabs.ESP:AddSlider("ESP_UpdateRate", { Title="Update Rate", Default = state.config.updateRate, Min = 1, Max = 60, Rounding = 1 })
--   rateSlider:OnChanged(function(v) state.config.updateRate = v SaveConfig() end)
--   local distSlider = Tabs.ESP:AddSlider("ESP_MaxDist", { Title="Max Distance", Default = state.config.maxDistance, Min = 50, Max = 1000, Rounding = 1 })
--   distSlider:OnChanged(function(v) state.config.maxDistance = v SaveConfig() end)
--   local colorPicker = Tabs.ESP:AddColorpicker("ESP_Color", { Title = "ESP Color", Default = state.config.espColor })
--   colorPicker:OnChanged(function(c) state.config.espColor = c SaveConfig() end)
--   Tabs.ESP:AddToggle("ESP_Highlight", { Title = "Highlight", Default = state.config.highlightEnabled }):OnChanged(function(v) state.config.highlightEnabled = v SaveConfig() end)
--   Tabs.ESP:AddButton({ Title = "Reset ESP Config", Description = "Reset to defaults", Callback = function() ResetConfig() end })
--   Tabs.ESP:AddButton({ Title = "Save Config", Description = "Save current config", Callback = function() SaveConfig() end })
--   Tabs.ESP:AddButton({ Title = "Load Config", Description = "Load saved config", Callback = function() LoadConfig() enableESP(state.config.enabled) end })

-- Load saved config then start with current value
LoadConfig()
-- (example) If you want ESP enabled by default from saved config:
if state.config.enabled then
    enableESP(true)
end

-- Provide API for external scripts to control quickly:
return {
    Enable = enableESP,
    CreateForPlayer = createESPForPlayer,
    RemoveForPlayer = removeESPForPlayer,
    SaveConfig = SaveConfig,
    LoadConfig = LoadConfig,
    ResetConfig = ResetConfig,
    GetConfig = function() return deepCopy(state.config) end,
}

