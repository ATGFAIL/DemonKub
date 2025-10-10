-- Loader v2 — improved
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- config: ใส่ placeId => { name=..., url=..., integrity=nil (optional), retries=?, retryDelay=? }
local allowedPlaces = {
    [8069117419]          = { name = "demon",               url = "https://api.luarmor.net/files/v3/loaders/ac8370afd7ed657e592868fe5e6ff1cf.lua", retries=3, retryDelay=1 },
    [127742093697776]     = { name = "Plants-Vs-Brainrots", url = "https://api.luarmor.net/files/v3/loaders/059cb863ce855658c5a1b050dab6fbaf.lua", retries=3, retryDelay=1 },
    [96114180925459]      = { name = "Lasso-Animals",       url = "https://api.luarmor.net/files/v3/loaders/49ef22e94528a49b6f1f7b0de2a98367.lua", retries=3, retryDelay=1 },
    [135880624242201]     = { name = "Cut-Tree",            url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/cut-tree.lua", retries=3, retryDelay=1 },
    [142823291]           = { name = "Murder-Mystery-2",     url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/Murder-Mystery-2.lua", retries=3, retryDelay=1 },
}

-- Simple logger w/ timestamp
local function ts() return os.date("%Y-%m-%d %H:%M:%S") end
local function logInfo(...) print(string.format("[%s] 🟩 [Loader]", ts()), ...) end
local function logWarn(...) warn(string.format("[%s] 🟨 [Loader]", ts()), ...) end
local function logError(...) warn(string.format("[%s] 🛑 [Loader]", ts()), ...) end

local function isValidLuaUrl(url)
    if type(url) ~= "string" or url == "" then return false end
    if not url:match("^https?://") then return false end
    -- allow query strings but require .lua somewhere near end
    if not url:lower():match("%.lua($|%?)") then return false end
    return true
end

-- prefer HttpService:GetAsync but allow game:HttpGet on some exploitors/stub envs
local function httpGet(url)
    local ok, res = pcall(function()
        if HttpService and HttpService.HttpEnabled then
            -- GetAsync is the "official" method
            return HttpService:GetAsync(url, true)
        elseif game.HttpGet then
            return game:HttpGet(url, true)
        else
            error("No HTTP method available.")
        end
    end)
    return ok, res
end

-- safe load function: try loadstring -> load -> load_chunk fallback
local function compileLua(code)
    if type(code) ~= "string" then return false, "code is not string" end
    local f, err = loadstring and loadstring(code) or load(code)
    if not f then
        return false, ("compile error: %s"):format(tostring(err))
    end
    -- protect execution in pcall
    local ok, result = pcall(function() return f() end)
    if ok then
        return true, result
    else
        return false, ("runtime error: %s"):format(tostring(result))
    end
end

-- fetch with retries and exponential backoff
local function fetchWithRetries(url, opts)
    opts = opts or {}
    local retries = opts.retries or 3
    local retryDelay = opts.retryDelay or 1
    local attempt = 0

    if not isValidLuaUrl(url) then
        return false, "Invalid URL: must be http(s) and end with .lua"
    end

    while attempt < retries do
        attempt = attempt + 1
        local ok, res = httpGet(url)
        if ok and type(res) == "string" and #res > 0 then
            return true, res
        else
            logWarn(("Attempt %d/%d failed to fetch %s -> %s"):format(attempt, retries, url, tostring(res)))
            -- exponential backoff with jitter
            if attempt < retries then
                local waitTime = retryDelay * (2 ^ (attempt - 1))
                -- small random jitter so parallel clients don't sync
                waitTime = waitTime + math.random() * 0.3
                task.wait(waitTime)
            end
        end
    end

    return false, ("All %d attempts failed for %s"):format(retries, url)
end

-- Main loader (run in safe task)
task.spawn(function()
    -- ensure client context: LocalPlayer must exist
    local player = Players.LocalPlayer
    if not player then
        logError("Script must run in a LocalScript (no LocalPlayer). Aborting.")
        return
    end

    local placeConfig = allowedPlaces[game.PlaceId]
    if not placeConfig then
        logError(("PlaceId %s not supported. Kicking user."):format(tostring(game.PlaceId)))
        -- avoid abrupt kick during dev; only kick in live env
        if not RunService:IsStudio() then
            player:Kick("[ ATG ] NOT SUPPORT")
        end
        return
    end

    logInfo(("Loaded loader for PlaceId %s (%s)"):format(tostring(game.PlaceId), tostring(placeConfig.name)))

    if not HttpService.HttpEnabled then
        logError("HttpService.HttpEnabled = false. Cannot fetch external script.")
        -- fallback: try local ModuleScript if exists
        local fallbackName = "Fallback_" .. tostring(placeConfig.name)
        local mod = ReplicatedStorage:FindFirstChild(fallbackName)
        if mod and mod:IsA("ModuleScript") then
            local ok, res = pcall(require, mod)
            if ok then
                logInfo("✅ Loaded fallback ModuleScript:", fallbackName)
                return
            else
                logError("Fallback ModuleScript require failed:", res)
            end
        end
        return
    end

    logInfo("เริ่มโหลดสคริปต์สำหรับแมพ:", placeConfig.name, placeConfig.url)
    local okFetch, codeOrErr = fetchWithRetries(placeConfig.url, { retries = placeConfig.retries or 3, retryDelay = placeConfig.retryDelay or 1 })

    if not okFetch then
        logError("❌ ไม่สามารถดาวน์โหลดสคริปต์ได้:", codeOrErr)
        return
    end

    -- optional: minimal integrity check (e.g., expected length or external signature)
    if placeConfig.integrity then
        -- NOTE: Roblox doesn't provide sha256 in standard lib; so this is a placeholder for external verification
        -- If you want integrity, compute hash on server and pass via secure channel, or embed signed code
        logInfo("Integrity field present but no verification implemented. Consider signed scripts.")
    end

    -- compile and run
    local okRun, runRes = compileLua(codeOrErr)
    if okRun then
        logInfo("✅ Extra script executed successfully for", placeConfig.name)
    else
        logError("Execution failed:", runRes)
        -- fallback attempt: find ModuleScript version
        local fallbackName = "Fallback_" .. tostring(placeConfig.name)
        local mod = ReplicatedStorage:FindFirstChild(fallbackName)
        if mod and mod:IsA("ModuleScript") then
            local succ, res = pcall(require, mod)
            if succ then
                logInfo("✅ Loaded fallback ModuleScript:", fallbackName)
            else
                logError("Fallback ModuleScript require failed:", res)
            end
        end
    end
end)
