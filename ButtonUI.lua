-- Unified Fluent toggle + draggable imgButton (สร้างปุ่มเฉพาะถ้าไม่มี Keyboard)
-- LocalScript (StarterPlayerScripts หรือ PlayerGui)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local localPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local playerGui = localPlayer:WaitForChild("PlayerGui")
local coreGui = game:GetService("CoreGui")
local Camera = workspace.CurrentCamera

-- OPTION: ถ้าต้องการบังคับให้แสดงปุ่มแม้มีคีย์บอร์ด ให้ตั้งค่าเป็น true
local FORCE_SHOW_IMG_BUTTON = true

-- ตรวจว่าอุปกรณ์มีคีย์บอร์ดหรือไม่
local hasKeyboard = UserInputService.KeyboardEnabled
-- ถ้าอยากครอบคลุมกรณีพิเศษ (เช่น GamePad/Console) สามารถตรวจ GamepadEnabled / TouchEnabled เพิ่มได้
-- local hasGamepad = UserInputService.GamepadEnabled
-- local hasTouch = UserInputService.TouchEnabled

-- ถ้ามีคีย์บอร์ด และไม่ได้บังคับให้แสดง ให้ไม่สร้าง imgButton
local shouldCreateImgButton = (not hasKeyboard) or FORCE_SHOW_IMG_BUTTON

-- create/find toggle ScreenGui (เรายังสร้างไว้เพราะอาจต้องการ parent ปุ่ม)
local toggleGui = playerGui:FindFirstChild("Fluent_ToggleGui")
if shouldCreateImgButton and not toggleGui then
    toggleGui = Instance.new("ScreenGui")
    toggleGui.Name = "Fluent_ToggleGui"
    toggleGui.ResetOnSpawn = false
    toggleGui.DisplayOrder = 9999
    toggleGui.Parent = playerGui
end

-- imgButton variable (อาจเป็น nil ถ้าไม่สร้าง)
local imgButton = (shouldCreateImgButton and toggleGui) and toggleGui:FindFirstChild("FluentToggleButton") or nil

if shouldCreateImgButton and not imgButton and toggleGui then
    imgButton = Instance.new("ImageButton")
    imgButton.Name = "FluentToggleButton"
    imgButton.Size = UDim2.fromOffset(48, 48)
    -- ตำแหน่งเริ่มต้น: ตรงกลางด้านบน เลื่อนลง 40px (แก้ตามชอบ)
    imgButton.AnchorPoint = Vector2.new(0.5, 0)
    imgButton.Position = UDim2.new(0.5, 0, 0, 40)
    imgButton.BackgroundTransparency = 0
    imgButton.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    imgButton.BorderSizePixel = 0
    imgButton.Parent = toggleGui
    imgButton.Image = "rbxassetid://108471780442112" -- เปลี่ยนเป็น asset ที่ชอบ

    local uic = Instance.new("UICorner", imgButton)
    uic.CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", imgButton)
    stroke.Thickness = 1
    stroke.Transparency = 0.6

    -- NOTE: ไม่มี TextLabel แล้ว — ปุ่มเป็นแค่ ImageButton เท่านั้น
end

-- อ่านสถานะ representative ของ GUI (Enabled / Visible)
local function readGuiState(g)
    if not g then return nil end
    if typeof(g) == "Instance" then
        if g:IsA("ScreenGui") and g.Enabled ~= nil then
            return g.Enabled
        elseif g:IsA("GuiObject") and g.Visible ~= nil then
            return g.Visible
        else
            for _, d in pairs(g:GetDescendants()) do
                if d:IsA("GuiObject") then
                    return d.Visible
                end
            end
        end
    end
    return nil
end

-- หา Fluent GUI candidates (fallback ถ้าไม่สามารถเรียก Window API ได้)
local function findFluentCandidates()
    local found = {}
    local function pushOnce(obj)
        for _, v in ipairs(found) do if v == obj then return end end
        table.insert(found, obj)
    end

    -- search top-level ScreenGuis with "fluent" in name
    for _, sg in pairs(playerGui:GetChildren()) do
        if sg:IsA("ScreenGui") and tostring(sg.Name):lower():find("fluent") then
            pushOnce(sg)
        end
    end

    -- scan descendants for markers
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

    -- fallback: any ScreenGui that looks like UI
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

-- Utility: อย่าไปแตะ toggleGui/ปุ่มของเราเอง (works even if toggleGui is nil)
local function shouldSkipInstance(inst)
    if not inst then return false end
    if toggleGui and inst == toggleGui then return true end
    if imgButton and (inst == imgButton or imgButton:IsDescendantOf(inst) or (toggleGui and inst:IsDescendantOf(toggleGui))) then return true end
    return false
end

-- unified toggle function (Window:Minimize preferred)
local debounce = false
local function unifiedToggle()
    if debounce then return end
    debounce = true
    task.defer(function() task.wait(0.18); debounce = false end)

    -- Prefer using Window API if available (keeps TitleBar minimize state in sync)
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

-- connect click (only if imgButton exists)
if imgButton then
    imgButton.MouseButton1Click:Connect(function()
        local ok, err = pcall(unifiedToggle)
        if not ok then warn("[FluentToggle] error:", err) end
    end)
end

-- keybind handling (Ctrl+M) - always registered (works on devices with keyboard)
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.M and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
        if typeof(Window) == "table" and type(Window.Minimize) == "function" then
            pcall(function() Window:Minimize() end)
        else
            pcall(unifiedToggle)
        end
    end
end)

-- ========== Dragging for the imgButton (only if created) ==========
if imgButton then
    do
        local dragging = false
        local dragInput = nil
        local dragStart = Vector2.new(0, 0)
        local startPos = Vector2.new(0, 0)

        local function clampPosition(x, y)
            local absSize = imgButton.AbsoluteSize
            local minX = absSize.X * 0.5
            local maxX = Camera and (Camera.ViewportSize.X - absSize.X * 0.5) or minX
            local minY = 0
            local maxY = Camera and (Camera.ViewportSize.Y - absSize.Y) or minY
            local clampedX = math.clamp(x, minX, maxX)
            local clampedY = math.clamp(y, minY, maxY)
            return clampedX, clampedY
        end

        imgButton.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragInput = nil
                dragStart = input.Position
                startPos = Vector2.new(imgButton.Position.X.Offset, imgButton.Position.Y.Offset)
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                        dragInput = nil
                    end
                end)
            end
        end)

        imgButton.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                dragInput = input
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if dragging and dragInput and input == dragInput then
                local delta = input.Position - dragStart
                local newX = startPos.X + delta.X
                local newY = startPos.Y + delta.Y
                local clampedX, clampedY = clampPosition(newX, newY)
                imgButton.Position = UDim2.new(0, clampedX, 0, clampedY)
            end
        end)

        if Camera then
            Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
                local pos = imgButton.Position
                local clampedX, clampedY = clampPosition(pos.X.Offset, pos.Y.Offset)
                imgButton.Position = UDim2.new(0, clampedX, 0, clampedY)
            end)
        end
    end
end

-- End of unified toggle
