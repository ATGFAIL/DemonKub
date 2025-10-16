-- Unified Fluent toggle + draggable imgButton (mobile / no-keyboard friendly)
-- เพิ่ม UIStroke ที่สีวิ่งตลอดเวลา (RGB hue cycle)
-- LocalScript (StarterPlayerScripts หรือ PlayerGui)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local localPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local playerGui = localPlayer:WaitForChild("PlayerGui")
local coreGui = game:GetService("CoreGui")
local Camera = workspace.CurrentCamera

-- OPTION: ถ้าต้องการบังคับให้แสดงปุ่มแม้มีคีย์บอร์ด ให้ตั้งค่าเป็น true
local FORCE_SHOW_IMG_BUTTON = false

-- START: กำหนดตำแหน่งเริ่มต้น (center Y เป็นพิกเซลจากขอบบน)
local START_Y = 1

-- ปรับแต่ง stroke animation ที่นี่
local STROKE_THICKNESS_BASE = 1        -- ความหนาพื้นฐานของเส้น
local STROKE_THICKNESS_PULSE = 1.5     -- จำนวนที่เพิ่ม/ลดสำหรับ pulse
local STROKE_PULSE_SPEED = 2.0         -- ความเร็วของการ pulse (Hz)
local STROKE_HUE_SPEED = 0.09          -- ความเร็วของการเปลี่ยน hue (cycles per second)
local STROKE_SATURATION = 0.95         -- ความอิ่มของสี (0-1)
local STROKE_VALUE = 1.0               -- ความสว่างของสี (0-1)
local STROKE_TRANSP_BASE = 0.05        -- โปร่งแสงพื้นฐาน
local STROKE_TRANSP_PULSE = 0.12       -- การเปลี่ยนแปลงโปร่งแสง

-- ตรวจสถานะ input (keyboard/touch/gamepad)
local hasKeyboard = UserInputService.KeyboardEnabled
local hasTouch = UserInputService.TouchEnabled
local hasGamepad = UserInputService.GamepadEnabled

-- ตัดสินใจว่าจะสร้าง imgButton หรือไม่
local shouldCreateImgButton = FORCE_SHOW_IMG_BUTTON or (not hasKeyboard) or (hasTouch and not hasKeyboard) or (hasGamepad and not hasKeyboard)

-- สร้างหรือหา ScreenGui parent
local toggleGui = playerGui:FindFirstChild("Fluent_ToggleGui")
if shouldCreateImgButton and not toggleGui then
    toggleGui = Instance.new("ScreenGui")
    toggleGui.Name = "Fluent_ToggleGui"
    toggleGui.ResetOnSpawn = false
    toggleGui.DisplayOrder = 9999
    toggleGui.Parent = playerGui
end

-- หา/สร้างปุ่ม
local imgButton = (shouldCreateImgButton and toggleGui) and toggleGui:FindFirstChild("FluentToggleButton") or nil

if shouldCreateImgButton and not imgButton and toggleGui then
    imgButton = Instance.new("ImageButton")
    imgButton.Name = "FluentToggleButton"
    imgButton.Size = UDim2.fromOffset(48, 48)
    -- ใช้ anchor เป็นกึ่งกลาง -> การลาก/clamp จะคิดเป็น center coordinates
    imgButton.AnchorPoint = Vector2.new(0.5, 0.5)
    imgButton.Position = UDim2.new(0.5, 0, 0, START_Y) -- center x = 50% ของจอ, center y = START_Y px จากบน
    imgButton.BackgroundTransparency = 0
    imgButton.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    imgButton.BorderSizePixel = 0
    imgButton.Parent = toggleGui
    imgButton.Image = "rbxassetid://114090251469395" -- เปลี่ยน asset ตามชอบ

    local uic = Instance.new("UICorner", imgButton)
    uic.CornerRadius = UDim.new(0, 8)

    -- สร้าง UIStroke ถ้ายังไม่มี (ตั้งชื่อเพื่อไม่สร้างซ้ำ)
    local stroke = imgButton:FindFirstChild("FluentStroke")
    if not stroke then
        stroke = Instance.new("UIStroke")
        stroke.Name = "FluentStroke"
        stroke.Parent = imgButton
        stroke.Thickness = STROKE_THICKNESS_BASE
        stroke.Transparency = STROKE_TRANSP_BASE
        stroke.LineJoinMode = Enum.LineJoinMode.Round -- ถ้ามีเวอร์ชันที่รองรับ
    end
end

-- helper: หาผู้สมัคร UI แบบ "Fluent" (เหมือนเดิม)
local function findFluentCandidates()
    local found = {}
    local function pushOnce(obj)
        for _, v in ipairs(found) do if v == obj then return end end
        table.insert(found, obj)
    end

    for _, sg in pairs(playerGui:GetChildren()) do
        if sg:IsA("ScreenGui") and tostring(sg.Name):lower():find("fluent") then
            pushOnce(sg)
        end
    end

    local markers = {"TabDisplay", "ContainerCanvas", "AcrylicPaint", "TitleBar", "TabHolder", "Fluent"}
    local function scan(parent)
        for _, obj in pairs(parent:GetDescendants()) do
            if obj:IsA("GuiObject") then
                local n = tostring(obj.Name):lower()
                for _, m in ipairs(markers) do
                    if n:find(m:lower()) then
                        local ancestor = obj
                        while ancestor.Parent and not ancestor.Parent:IsA("PlayerGui") and not ancestor.Parent:IsA("CoreGui") and ancestor.Parent ~= workspace do
                            ancestor = ancestor.Parent
                        end
                        local sg = ancestor
                        while sg and not sg:IsA("ScreenGui") do sg = sg.Parent end
                        if sg then pushOnce(sg) else pushOnce(ancestor) end
                    end
                end

                if (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) and obj.Text then
                    local t = tostring(obj.Text):lower()
                    if t:find("fluent") or t:find("interface") or t:find("by dawid") then
                        local ancestor = obj
                        while ancestor.Parent and not ancestor.Parent:IsA("PlayerGui") and not ancestor.Parent:IsA("CoreGui") and ancestor.Parent ~= workspace do
                            ancestor = ancestor.Parent
                        end
                        local sg = ancestor
                        while sg and not sg:IsA("ScreenGui") do sg = sg.Parent end
                        if sg then pushOnce(sg) else pushOnce(ancestor) end
                    end
                end
            end
        end
    end

    scan(playerGui)
    pcall(function() scan(coreGui) end)

    if #found == 0 then
        for _, sg in pairs(playerGui:GetChildren()) do
            if sg:IsA("ScreenGui") then
                for _, d in pairs(sg:GetDescendants()) do
                    if d:IsA("GuiObject") then
                        pushOnce(sg)
                        break
                    end
                end
            end
        end
    end

    return found
end

local function shouldSkipInstance(inst)
    if not inst then return false end
    if toggleGui and inst == toggleGui then return true end
    if imgButton and (inst == imgButton or imgButton:IsDescendantOf(inst) or (toggleGui and inst:IsDescendantOf(toggleGui))) then return true end
    return false
end

-- unified toggle (ยังใช้เดิม)
local debounce = false
local function unifiedToggle()
    if debounce then return end
    debounce = true
    task.defer(function() task.wait(0.18); debounce = false end)

    local usedWindow = false
    if typeof(Window) == "table" and type(Window.Minimize) == "function" then
        pcall(function() Window:Minimize() end)
        usedWindow = true
    end

    if not usedWindow then
        local candidates = findFluentCandidates()
        if #candidates == 0 then
            for _, sg in pairs(playerGui:GetChildren()) do
                if sg:IsA("ScreenGui") and not shouldSkipInstance(sg) then
                    pcall(function()
                        if sg.Enabled ~= nil then
                            sg.Enabled = not sg.Enabled
                        else
                            for _, v in pairs(sg:GetDescendants()) do
                                if v:IsA("GuiObject") then v.Visible = not v.Visible end
                            end
                        end
                    end)
                end
            end
            return
        end

        for _, c in ipairs(candidates) do
            if not shouldSkipInstance(c) then
                pcall(function()
                    if c:IsA("ScreenGui") and c.Enabled ~= nil then
                        c.Enabled = not c.Enabled
                    elseif c:IsA("GuiObject") and c.Visible ~= nil then
                        c.Visible = not c.Visible
                    else
                        for _, v in pairs(c:GetDescendants()) do
                            if not shouldSkipInstance(v) and v:IsA("GuiObject") and v.Visible ~= nil then
                                v.Visible = not v.Visible
                            end
                        end
                    end
                end)
            end
        end
    end
end

-- Activated สำหรับ touch / mouse / controller
if imgButton then
    imgButton.Activated:Connect(function()
        local ok, err = pcall(unifiedToggle)
        if not ok then warn("[FluentToggle] error:", err) end
    end)
end

-- keybind (keyboard) - ถ้ามี keyboard
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.M and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
            if typeof(Window) == "table" and type(Window.Minimize) == "function" then
                pcall(function() Window:Minimize() end)
            else
                pcall(unifiedToggle)
            end
        end
    end
end)

-- ========== Dragging (center-based, mobile friendly) ==========
if imgButton then
    do
        -- state
        local dragging = false
        local dragInput = nil
        local dragStart = Vector2.new(0, 0)     -- input start pos (absolute)
        local startCenter = Vector2.new(0, 0)   -- button center absolute at start
        local currentVpSize = Vector2.new(0, 0)

        local function getViewport()
            if Camera and Camera.ViewportSize then
                return Camera.ViewportSize
            elseif workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize then
                return workspace.CurrentCamera.ViewportSize
            else
                local root = playerGui
                if root and root.AbsoluteSize then
                    return root.AbsoluteSize
                end
                return Vector2.new(0, 0)
            end
        end

        local function updateVpSize()
            local vs = getViewport()
            currentVpSize = Vector2.new(vs.X or 0, vs.Y or 0)
        end

        updateVpSize()

        -- clamp center coordinate so that button center stays onscreen (can reach edges)
        local function clampCenter(cx, cy)
            local absSize = imgButton.AbsoluteSize
            updateVpSize()
            local vpW, vpH = currentVpSize.X, currentVpSize.Y
            if vpW <= 0 or vpH <= 0 then
                return cx, cy
            end
            local halfW = absSize.X * 0.5
            local halfH = absSize.Y * 0.5
            local minX = halfW * 0.5 -- tiny allowance (avoid fully offscreen)
            local maxX = math.max(halfW, vpW - halfW)
            local minY = halfH * 0.5
            local maxY = math.max(halfH, vpH - halfH)
            local ncx = math.clamp(cx, minX, maxX)
            local ncy = math.clamp(cy, minY, maxY)
            return ncx, ncy
        end

        -- Start drag
        imgButton.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragInput = input
                dragStart = input.Position

                -- compute current center absolute (AbsolutePosition is top-left)
                local absPos = imgButton.AbsolutePosition
                local absSize = imgButton.AbsoluteSize
                startCenter = Vector2.new(absPos.X + absSize.X * 0.5, absPos.Y + absSize.Y * 0.5)
            end
        end)

        -- Record movement input (mouse movement / touch move)
        imgButton.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                dragInput = input
            end
        end)

        -- Global InputChanged to get positions (this works for touch/mouse movement)
        UserInputService.InputChanged:Connect(function(input)
            if dragging and dragInput and input == dragInput and input.Position then
                local delta = input.Position - dragStart
                local newCenter = startCenter + delta
                local cx, cy = clampCenter(newCenter.X, newCenter.Y)
                -- set Position using center coordinates (AnchorPoint = 0.5,0.5)
                imgButton.Position = UDim2.fromOffset(cx, cy)
            end
        end)

        -- Release when input ends
        UserInputService.InputEnded:Connect(function(input)
            if dragging and dragInput and input == dragInput then
                dragging = false
                dragInput = nil
            end
        end)

        -- viewport change: ensure button stays onscreen (re-clamp)
        if Camera then
            Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
                updateVpSize()
                local absPos = imgButton.AbsolutePosition
                local absSize = imgButton.AbsoluteSize
                local centerX = absPos.X + absSize.X * 0.5
                local centerY = absPos.Y + absSize.Y * 0.5
                local cx, cy = clampCenter(centerX, centerY)
                imgButton.Position = UDim2.fromOffset(cx, cy)
            end)
        else
            RunService.RenderStepped:Wait()
            local absPos = imgButton.AbsolutePosition
            local absSize = imgButton.AbsoluteSize
            local centerX = absPos.X + absSize.X * 0.5
            local centerY = absPos.Y + absSize.Y * 0.5
            local cx, cy = clampCenter(centerX, centerY)
            imgButton.Position = UDim2.fromOffset(cx, cy)
        end

        -- --- Stroke animation (RenderStepped) ---
        local stroke = imgButton:FindFirstChild("FluentStroke")
        local animateConn
        if stroke then
            -- ensure initial settings
            stroke.Thickness = STROKE_THICKNESS_BASE
            stroke.Transparency = STROKE_TRANSP_BASE

            local function animate(dt)
                local t = tick()
                -- hue cycles 0..1
                local h = (t * STROKE_HUE_SPEED) % 1
                -- slightly vary saturation/value if desired
                local s = STROKE_SATURATION
                local v = STROKE_VALUE
                -- set color from HSV
                stroke.Color = Color3.fromHSV(h, s, v)

                -- pulse thickness
                local pulse = (math.sin(t * STROKE_PULSE_SPEED * math.pi * 2) + 1) / 2 -- 0..1
                stroke.Thickness = STROKE_THICKNESS_BASE + pulse * STROKE_THICKNESS_PULSE

                -- optional subtle transparency pulse for shimmer
                stroke.Transparency = STROKE_TRANSP_BASE + pulse * STROKE_TRANSP_PULSE
            end

            animateConn = RunService.RenderStepped:Connect(animate)

            -- cleanup if button removed
            imgButton.AncestryChanged:Connect(function(child, parent)
                if not parent and animateConn then
                    animateConn:Disconnect()
                    animateConn = nil
                end
            end)
        end
    end
end

-- End of script
