-- wait for LocalPlayer if not ready (safe in LocalScript)
if not LocalPlayer or typeof(LocalPlayer) == "Instance" and LocalPlayer.ClassName == "" then
    LocalPlayer = Players.LocalPlayer
end

do
    -- config
    local enforcementRate = 0.1 -- วินาที (0.1 = 10 ครั้ง/วินาที) -> ตอบสนองดีขึ้น แต่ไม่เกินไป
    local WalkMin, WalkMax = 8, 200
    local JumpMin, JumpMax = 10, 300

    local DesiredWalkSpeed = 16
    local DesiredJumpPower = 50

    local WalkEnabled = true
    local JumpEnabled = true

    -- เก็บค่าเดิมของ humanoid (weak table ตาม instance)
    local originalValues = setmetatable({}, { __mode = "k" })

    local currentHumanoid = nil
    local heartbeatConn = nil
    local lastApplyTick = 0

    local function clamp(v, a, b)
        if v < a then return a end
        if v > b then return b end
        return v
    end

    local function findHumanoid()
        if not Players.LocalPlayer then return nil end
        local char = Players.LocalPlayer.Character
        if not char then return nil end
        return char:FindFirstChildWhichIsA("Humanoid")
    end

    local function saveOriginal(hum)
        if not hum then return end
        if not originalValues[hum] then
            local ok, ws, jp, usejp = pcall(function()
                return hum.WalkSpeed, hum.JumpPower, hum.UseJumpPower
            end)
            if ok then
                originalValues[hum] = { WalkSpeed = ws or 16, JumpPower = jp or 50, UseJumpPower = usejp }
            else
                originalValues[hum] = { WalkSpeed = 16, JumpPower = 50, UseJumpPower = true }
            end
        end
    end

    local function restoreOriginal(hum)
        if not hum then return end
        local orig = originalValues[hum]
        if orig then
            pcall(function()
                if orig.UseJumpPower ~= nil then
                    hum.UseJumpPower = orig.UseJumpPower
                end
                hum.WalkSpeed = orig.WalkSpeed or 16
                hum.JumpPower = orig.JumpPower or 50
            end)
            originalValues[hum] = nil
        end
    end

    local function applyToHumanoid(hum)
        if not hum then return end
        saveOriginal(hum)

        -- Walk
        if WalkEnabled then
            local desired = clamp(math.floor(DesiredWalkSpeed + 0.5), WalkMin, WalkMax)
            if hum.WalkSpeed ~= desired then
                pcall(function() hum.WalkSpeed = desired end)
            end
        end

        -- Jump: ensure UseJumpPower true, then set JumpPower
        if JumpEnabled then
            pcall(function()
                -- set UseJumpPower true to ensure JumpPower is respected
                if hum.UseJumpPower ~= true then
                    hum.UseJumpPower = true
                end
            end)

            local desiredJ = clamp(math.floor(DesiredJumpPower + 0.5), JumpMin, JumpMax)
            if hum.JumpPower ~= desiredJ then
                pcall(function() hum.JumpPower = desiredJ end)
            end
        end
    end

    local function startEnforcement()
        if heartbeatConn then return end
        local acc = 0
        heartbeatConn = RunService.Heartbeat:Connect(function(dt)
            acc = acc + dt
            if acc < enforcementRate then return end
            acc = 0

            local hum = findHumanoid()
            if hum then
                currentHumanoid = hum
                -- apply only when enabled; if both disabled, avoid applying
                if WalkEnabled or JumpEnabled then
                    applyToHumanoid(hum)
                end
            else
                -- no humanoid: clear currentHumanoid
                currentHumanoid = nil
            end
        end)
    end

    local function stopEnforcement()
        if heartbeatConn then
            heartbeatConn:Disconnect()
            heartbeatConn = nil
        end
    end

    -- Toggle handlers
    local function setWalkEnabled(v)
        WalkEnabled = not not v
        if WalkEnabled then
            -- immediately apply
            local hum = findHumanoid()
            if hum then
                applyToHumanoid(hum)
            end
            startEnforcement()
        else
            -- restore walk value on current humanoid if we recorded it
            if currentHumanoid then
                -- only restore WalkSpeed (not touching Jump here)
                local orig = originalValues[currentHumanoid]
                if orig and orig.WalkSpeed ~= nil then
                    pcall(function() currentHumanoid.WalkSpeed = orig.WalkSpeed end)
                end
            end

            -- if both disabled, we can stop enforcement and restore jump if needed
            if not JumpEnabled then
                if currentHumanoid then
                    restoreOriginal(currentHumanoid)
                end
                stopEnforcement()
            end
        end
    end

    local function setJumpEnabled(v)
        JumpEnabled = not not v
        if JumpEnabled then
            local hum = findHumanoid()
            if hum then
                applyToHumanoid(hum)
            end
            startEnforcement()
        else
            if currentHumanoid then
                -- restore JumpPower and UseJumpPower
                local orig = originalValues[currentHumanoid]
                if orig and (orig.JumpPower ~= nil or orig.UseJumpPower ~= nil) then
                    pcall(function()
                        if orig.UseJumpPower ~= nil then
                            currentHumanoid.UseJumpPower = orig.UseJumpPower
                        end
                        if orig.JumpPower ~= nil then
                            currentHumanoid.JumpPower = orig.JumpPower
                        end
                    end)
                end
            end

            if not WalkEnabled then
                if currentHumanoid then
                    restoreOriginal(currentHumanoid)
                end
                stopEnforcement()
            end
        end
    end

    -- sliders callbacks
    local function setWalkSpeed(v)
        DesiredWalkSpeed = clamp(v, WalkMin, WalkMax)
        if WalkEnabled then
            local hum = findHumanoid()
            if hum then applyToHumanoid(hum) end
            startEnforcement()
        end
    end

    local function setJumpPower(v)
        DesiredJumpPower = clamp(v, JumpMin, JumpMax)
        if JumpEnabled then
            local hum = findHumanoid()
            if hum then applyToHumanoid(hum) end
            startEnforcement()
        end
    end

    -- CharacterAdded handling to apply as soon as possible
    if Players.LocalPlayer then
        Players.LocalPlayer.CharacterAdded:Connect(function(char)
            -- small wait for humanoid to exist
            local hum = nil
            for i = 1, 20 do
                hum = char:FindFirstChildWhichIsA("Humanoid")
                if hum then break end
                task.wait(0.05)
            end
            if hum and (WalkEnabled or JumpEnabled) then
                applyToHumanoid(hum)
                startEnforcement()
            end
        end)
    end

    -- UI
    local speedSlider = Section:AddSlider("WalkSpeedSlider", {
        Title = "WalkSpeed",
        Default = DesiredWalkSpeed, Min = WalkMin, Max = WalkMax, Rounding = 0,
        Callback = function(Value) setWalkSpeed(Value) end
    })
    speedSlider:OnChanged(setWalkSpeed)

    local jumpSlider = Section:AddSlider("JumpPowerSlider", {
        Title = "JumpPower",
        Default = DesiredJumpPower, Min = JumpMin, Max = JumpMax, Rounding = 0,
        Callback = function(Value) setJumpPower(Value) end
    })
    jumpSlider:OnChanged(setJumpPower)

    local walkToggle = Section:AddToggle("EnableWalkToggle", {
        Title = "Enable Walk",
        Description = "เปิด/ปิดการบังคับ WalkSpeed",
        Default = WalkEnabled,
        Callback = function(value) setWalkEnabled(value) end
    })
    walkToggle:OnChanged(setWalkEnabled)

    local jumpToggle = Section:AddToggle("EnableJumpToggle", {
        Title = "Enable Jump",
        Description = "เปิด/ปิดการบังคับ JumpPower",
        Default = JumpEnabled,
        Callback = function(value) setJumpEnabled(value) end
    })
    jumpToggle:OnChanged(setJumpEnabled)

    Section:AddButton({
        Title = "Reset to defaults",
        Description = "คืนค่า Walk/Jump ไปค่าเริ่มต้น (16, 50)",
        Callback = function()
            DesiredWalkSpeed = 16
            DesiredJumpPower = 50
            speedSlider:SetValue(DesiredWalkSpeed)
            jumpSlider:SetValue(DesiredJumpPower)
            if WalkEnabled or JumpEnabled then
                local hum = findHumanoid()
                if hum then applyToHumanoid(hum) end
            end
        end
    })

    -- start enforcement if either is enabled initially
    if WalkEnabled or JumpEnabled then startEnforcement() end
end
