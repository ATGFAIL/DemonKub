-- Unified Fluent toggle + draggable imgButton (รองรับมือถือ / แพลตฟอร์มไม่มีคีย์บอร์ด)
-- LocalScript (StarterPlayerScripts หรือ PlayerGui)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local localPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local playerGui = localPlayer:WaitForChild("PlayerGui")
local coreGui = game:GetService("CoreGui")
local Camera = workspace.CurrentCamera

-- OPTION: ถ้าต้องการบังคับให้แสดงปุ่มแม้มีคีย์บอร์ด ให้ตั้งค่าเป็น true
local FORCE_SHOW_IMG_BUTTON = false

-- ตรวจสถานะ input
local hasKeyboard = UserInputService.KeyboardEnabled
local hasTouch = UserInputService.TouchEnabled
local hasGamepad = UserInputService.GamepadEnabled

-- ตัดสินใจว่าจะสร้าง imgButton หรือไม่
-- แสดงเมื่อบังคับให้โชว์ หรือไม่มี keyboard (เน้นกรณีมือถือ/คอนโซล) หรือถ้ามี touch แต่ไม่มี keyboard
local shouldCreateImgButton = FORCE_SHOW_IMG_BUTTON or (not hasKeyboard) or (hasTouch and not hasKeyboard) or (hasGamepad and not hasKeyboard)

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
    -- ตั้ง AnchorPoint เป็น (0,0) เพื่อให้การลาก/คำนวณตำแหน่งง่ายขึ้น
    imgButton.AnchorPoint = Vector2.new(0, 0)
    -- ตำแหน่งเริ่มต้น: ตรงกลางด้านบน (ปรับด้วย -width/2) เพื่อให้ดูเหมือนเดิม
    imgButton.Position = UDim2.new(0.5, -24, 0, 40)
    imgButton.BackgroundTransparency = 0
    imgButton.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    imgButton.BorderSizePixel = 0
    imgButton.Parent = toggleGui
    imgButton.Image = "rbxassetid://114090251469395" -- เปลี่ยนเป็น asset ที่ชอบ

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

-- connect click / activate (only if imgButton exists)
-- ใช้ Activated แทน MouseButton1Click เพื่อรองรับ touch / controller activation
if imgButton then
    imgButton.Activated:Connect(function()
        local ok, err = pcall(unifiedToggle)
        if not ok then warn("[FluentToggle] error:", err) end
    end)
end

-- keybind handling (Ctrl+M) - always registered (works on devices with keyboard)
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
    -- (เพิ่ม) ถ้าต้องการให้ gamepad ปุ่มใดปุ่มหนึ่งเป็น toggle คุณสามารถเพิ่มเงื่อนไขที่นี่
    -- ตัวอย่าง (ไม่เปิดใช้งานโดยค่าเริ่มต้น):
    -- if input.UserInputType == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.ButtonStart then
    --     pcall(unifiedToggle)
    -- end
end)

-- ========== Dragging for the imgButton (only if created) ==========
if imgButton then
    do
        local dragging = false
        local dragInput = nil
        local dragStart = Vector2.new(0, 0) -- input start pos
        local startPos = Vector2.new(0, 0)  -- button top-left at start

        local function clampPosition(x, y)
            local absSize = imgButton.AbsoluteSize
            local vpW = (Camera and Camera.ViewportSize.X) or (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.X) or 0
            local vpH = (Camera and Camera.ViewportSize.Y) or (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y) or 0
            if vpW == 0 or vpH == 0 then
                -- fallback: ถ้าไม่มี camera info ให้อนุญาตตำแหน่งไม่ติดขอบมาก
                return math.max(0, x), math.max(0, y)
            end
            local minX = 0
            local maxX = math.max(0, vpW - absSize.X)
            local minY = 0
            local maxY = math.max(0, vpH - absSize.Y)
            local clampedX = math.clamp(x, minX, maxX)
            local clampedY = math.clamp(y, minY, maxY)
            return clampedX, clampedY
        end

        -- InputBegan on imgButton: เริ่ม drag สำหรับ MouseButton1 / Touch
        imgButton.InputBegan:Connect(function(input)
            -- ถ้าเป็น mouse left หรือ touch ให้เริ่มจับ
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragInput = input
                dragStart = input.Position
                -- ใช้ AbsolutePosition ของปุ่มเป็นตำแหน่งเริ่มต้น (top-left)
                startPos = Vector2.new(imgButton.AbsolutePosition.X, imgButton.AbsolutePosition.Y)

                -- เชื่อมฟังค์ชัน End detection ของ input นี้
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                        dragInput = nil
                    end
                end)
            end
        end)

        -- InputChanged: ถ้ามี movement หรือ touch move ให้บันทึก input
        imgButton.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                dragInput = input
            end
        end)

        -- Global InputChanged: คำนวณตำแหน่งใหม่เมื่อ input ที่ใช้เป็น dragInput เคลื่อน
        UserInputService.InputChanged:Connect(function(input)
            if dragging and dragInput and input == dragInput and input.Position then
                local delta = input.Position - dragStart
                local newX = startPos.X + delta.X
                local newY = startPos.Y + delta.Y
                local clampedX, clampedY = clampPosition(newX, newY)
                -- ตั้ง Position โดยใช้ fromOffset (top-left)
                imgButton.Position = UDim2.fromOffset(clampedX, clampedY)
            end
        end)

        -- ปรับตำแหน่งปุ่มเมื่อขนาด viewport เปลี่ยน (ป้องกันปุ่มหลุดนอกจอ)
        if Camera then
            Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
                -- ใช้ AbsolutePosition/AbsoluteSize เพื่อคำนวณ clamp ปัจจุบัน
                local absPos = imgButton.AbsolutePosition
                local clampedX, clampedY = clampPosition(absPos.X, absPos.Y)
                imgButton.Position = UDim2.fromOffset(clampedX, clampedY)
            end)
        end
    end
end

-- End of unified toggle
