-- Loader (fixed & more robust)
local HttpService = game:GetService("HttpService")
local RunService  = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- -----------------------
-- Allowed Place configuration (fixed)
-- -----------------------
local common99 = { name = "99 Nights in the Forest", url = "https://api.luarmor.net/files/v3/loaders/3be199e8307561dc3cfb7855a31269dd.lua" }
local allowedPlaces = {
    [8069117419]          = { name = "demon",               url = "https://api.luarmor.net/files/v3/loaders/ac8370afd7ed657e592868fe5e6ff1cf.lua" },
    [127742093697776]     = { name = "Plants-Vs-Brainrots", url = "https://api.luarmor.net/files/v3/loaders/059cb863ce855658c5a1b050dab6fbaf.lua" },
    [96114180925459]      = { name = "Lasso-Animals",       url = "https://api.luarmor.net/files/v3/loaders/49ef22e94528a49b6f1f7b0de2a98367.lua" },
    [135880624242201]     = { name = "Cut-Tree",            url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/cut-tree.lua" },
    [142823291]           = { name = "Murder-Mystery-2",    url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/Murder-Mystery-2.lua" },
}
-- map two placeIds to the same config
allowedPlaces[126509999114328] = common99
allowedPlaces[79546208627805]   = common99

-- -----------------------
-- Logger helpers
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
    if not url:match("^https?://") then return false end
    if not url:lower():match("%.lua$") then return false end
    return true
end

-- -----------------------
-- Basic checks
-- -----------------------
local placeConfig = allowedPlaces[game.PlaceId]
if not placeConfig then
    if LocalPlayer then
        LocalPlayer:Kick("[ ATG ] NOT SUPPORT")
    else
        logError("Not supported placeId:", tostring(game.PlaceId))
    end
    return
end

logInfo(("Script loaded for PlaceId %s (%s)"):format(tostring(game.PlaceId), tostring(placeConfig.name)))

-- If HttpService disabled, try fallback ModuleScript (don't immediately attempt network)
if not HttpService.HttpEnabled then
    logWarn("HttpService.HttpEnabled = false. จะพยายามโหลด fallback ModuleScript ถ้ามี.")
    local fallback = ReplicatedStorage:FindFirstChild("Fallback_" .. tostring(placeConfig.name))
    if fallback and fallback:IsA("ModuleScript") then
        local ok, res = pcall(require, fallback)
        if ok then
            logInfo("✅ Loaded fallback ModuleScript for", placeConfig.name)
        else
            logError("Fallback ModuleScript error:", res)
        end
    else
        logError("No fallback ModuleScript found and HttpService disabled. Stopping loader.")
    end
    return
end

-- -----------------------
-- HTTP helpers (try multiple methods)
-- -----------------------
local function tryHttpGet(url)
    -- Prefer game:HttpGet if available (many executors), else use HttpService:GetAsync
    if type(game.HttpGet) == "function" then
        return game:HttpGet(url, true)
    elseif HttpService and type(HttpService.GetAsync) == "function" then
        return HttpService:GetAsync(url, true)
    else
        error("No HTTP-get method available in this environment.")
    end
end

local function fetchScript(url)
    local ok, result = pcall(function() return tryHttpGet(url) end)
    if ok then
        return true, result
    else
        return false, result
    end
end

-- -----------------------
-- Loader with retries & safe exec
-- -----------------------
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
            -- try to load chunk (support loadstring or load)
            local loader = loadstring or load
            if not loader then
                return false, "No loader (loadstring/load) available to compile script."
            end

            local f, loadErr = pcall(function() return loader(res) end)
            if not f or type(loadErr) ~= "function" then
                logWarn(("Attempt %d: failed to compile script -> %s"):format(attempt, tostring(loadErr)))
            else
                -- execute safely
                local execOk, execRes = pcall(function() return loadErr() end)
                if execOk then
                    return true, execRes
                else
                    logWarn(("Attempt %d: runtime error executing script -> %s"):format(attempt, tostring(execRes)))
                end
            end
        else
            logWarn(("Attempt %d: failed to fetch %s -> %s"):format(attempt, url, tostring(res)))
        end

        if attempt < retries then
            -- use task.wait when available (more modern)
            if type(task) == "table" and type(task.wait) == "function" then
                task.wait(retryDelay)
            else
                wait(retryDelay)
            end
        end
    end

    return false, ("All %d attempts failed for %s"):format(retries, url)
end

-- Run loader in a coroutine so UI/main thread not blocked
coroutine.wrap(function()
    logInfo("เริ่มโหลดสคริปต์สำหรับแมพ:", placeConfig.name, placeConfig.url)
    local ok, result = loadExtraScript(placeConfig.url, { retries = 3, retryDelay = 1 })

    if ok then
        logInfo("✅ Extra script loaded successfully for", placeConfig.name)
    else
        logError("❌ ไม่สามารถโหลดสคริปต์เพิ่มเติมได้:", result)
        -- optional fallback try ModuleScript in ReplicatedStorage
        local mod = ReplicatedStorage:FindFirstChild("Fallback_" .. tostring(placeConfig.name))
        if mod and mod:IsA("ModuleScript") then
            local success, modRes = pcall(require, mod)
            if success then
                logInfo("✅ Loaded fallback ModuleScript for", placeConfig.name)
            else
                logError("Fallback ModuleScript error:", modRes)
            end
        end
    end
end)()
