local HttpService = game:GetService("HttpService")
local RunService  = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- -----------------------
-- Allowed Place configuration
-- -----------------------
-- เพิ่มรายการได้ง่าย: ใส่ placeId => { name = "...", url = "https://.../file.lua" }
local allowedPlaces = {
    [8069117419]          = { name = "demon",               url = "https://api.luarmor.net/files/v3/loaders/ac8370afd7ed657e592868fe5e6ff1cf.lua" },
    [127742093697776]     = { name = "Plants-Vs-Brainrots", url = "https://api.luarmor.net/files/v3/loaders/059cb863ce855658c5a1b050dab6fbaf.lua" },
    [96114180925459]      = { name = "Lasso-Animals",       url = "https://api.luarmor.net/files/v3/loaders/49ef22e94528a49b6f1f7b0de2a98367.lua" },
    [135880624242201]     = { name = "Cut-Tree",            url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/cut-tree.lua" },
    [142823291]           = { name = "Murder-Mystery-2",     url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/Murder-Mystery-2.lua" },
    [126509999114328]     = { name = "99 Nights in the Forest", url = "https://api.luarmor.net/files/v3/loaders/3be199e8307561dc3cfb7855a31269dd.lua" },
    [79546208627805]     = { name = "99 Nights in the Forest", url = "https://api.luarmor.net/files/v3/loaders/3be199e8307561dc3cfb7855a31269dd.lua" },
}

-- -----------------------
-- Helpers / Logger
-- -----------------------
local function logInfo(...)
    print("🟩 [Loader]", ...)
end

local function logWarn(...)
    warn("🟨 [Loader]", ...)
end

local function logError(...)
    warn("🛑 [Loader]", ...)
end

local function isValidLuaUrl(url)
    if type(url) ~= "string" then return false end
    -- basic checks: http/https and ends with .lua (case-insensitive)
    if not url:match("^https?://") then return false end
    if not url:lower():match("%.lua$") then return false end
    return true
end

-- -----------------------
-- Basic environment checks
-- -----------------------
local placeConfig = allowedPlaces[game.PlaceId]
if not placeConfig then
    game.Players.LocalPlayer:Kick("[ ATG ] NOT SUPPORT")
    return
end

logInfo(("Script loaded for PlaceId %s (%s)"):format(tostring(game.PlaceId), tostring(placeConfig.name)))

-- Check HttpService availability early
if not HttpService.HttpEnabled then
    logError("HttpService.HttpEnabled = false. ไม่สามารถโหลดสคริปต์จาก URL ได้.")
    -- ถ้าต้องการให้ทำงานต่อแม้ Http ปิด ให้ใส่ fallback (เช่น require ModuleScript) ด้านล่าง
    -- return
end

-- -----------------------
-- Script loader (with retries)
-- -----------------------
local function fetchScript(url)
    local ok, result = pcall(function()
        -- second arg true = skip cache; บาง executor อาจรองรับ
        return game:HttpGet(url, true)
    end)
    return ok, result
end

-- options: retries (default 3), retryDelay (seconds)
local function loadExtraScript(url, options)
    options = options or {}
    local retries = options.retries or 3
    local retryDelay = options.retryDelay or 1

    if not isValidLuaUrl(url) then
        return false, "Invalid URL (must be http(s) and end with .lua)"
    end

    for attempt = 1, retries do
        local ok, res = fetchScript(url)
        if ok and type(res) == "string" and #res > 0 then
            -- attempt to execute safely
            local execOk, execRes = pcall(function()
                -- loadstring may not exist in some environments; pcall + loadstring used here
                local f, loadErr = loadstring(res)
                if not f then
                    error(("loadstring error: %s"):format(tostring(loadErr)))
                end
                return f()
            end)

            if execOk then
                return true, execRes
            else
                -- execution failed
                logWarn(("Attempt %d: failed to execute script from %s -> %s"):format(attempt, url, tostring(execRes)))
            end
        else
            logWarn(("Attempt %d: failed to fetch %s -> %s"):format(attempt, url, tostring(res)))
        end

        if attempt < retries then
            -- non-blocking small delay (coroutine.wrap allows the outer call to continue)
            wait(retryDelay)
        end
    end

    return false, ("All %d attempts failed for %s"):format(retries, url)
end

-- Run loader inside coroutine so main thread isn't blocked by network retries
coroutine.wrap(function()
    logInfo("เริ่มโหลดสคริปต์สำหรับแมพ:", placeConfig.name, placeConfig.url)
    local ok, result = loadExtraScript(placeConfig.url, { retries = 3, retryDelay = 1 })

    if ok then
        logInfo("✅ Extra script loaded successfully for", placeConfig.name)
    else
        logError("❌ ไม่สามารถโหลดสคริปต์เพิ่มเติมได้:", result)
        -- ตัวอย่าง fallback: ถ้ามี ModuleScript เก็บไว้ใน ReplicatedStorage ให้ require แทน
        -- local mod = ReplicatedStorage:FindFirstChild("Fallback_" .. placeConfig.name)
        -- if mod and mod:IsA("ModuleScript") then
        --     local success, modRes = pcall(require, mod)
        --     if success then
        --         logInfo("✅ Loaded fallback ModuleScript for", placeConfig.name)
        --     else
        --         logError("Fallback ModuleScript error:", modRes)
        --     end
        -- end
    end
end)()

