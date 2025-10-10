-- Loader ปรับปรุงโดย ATG-like suggestions
local HttpService = game:GetService("HttpService")
local RunService  = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- -----------------------
-- Allowed Place configuration (ใส่ placeId => { name = "...", url = "https://.../file.lua", allowed_domains = {...} })
-- -----------------------
local allowedPlaces = {
    [8069117419]      = { name = "demon",               url = "https://api.luarmor.net/files/v3/loaders/ac8370afd7ed657e592868fe5e6ff1cf.lua", allowed_domains = { "api.luarmor.net", "raw.githubusercontent.com" } },
    [127742093697776] = { name = "Plants-Vs-Brainrots", url = "https://api.luarmor.net/files/v3/loaders/059cb863ce855658c5a1b050dab6fbaf.lua", allowed_domains = { "api.luarmor.net" } },
    [96114180925459]  = { name = "Lasso-Animals",       url = "https://api.luarmor.net/files/v3/loaders/49ef22e94528a49b6f1f7b0de2a98367.lua", allowed_domains = { "api.luarmor.net" } },
    [135880624242201] = { name = "Cut-Tree",            url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/cut-tree.lua", allowed_domains = { "raw.githubusercontent.com", "githubusercontent.com" } },
    [142823291]       = { name = "Murder-Mystery-2",    url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/Murder-Mystery-2.lua", allowed_domains = { "raw.githubusercontent.com" } },
}

-- -----------------------
-- Helpers / Logger (emoji เก๋ๆ)
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

local function safeLower(s)
    return (type(s) == "string") and s:lower() or ""
end

-- ตรวจสอบว่าเป็น URL .lua หรือ GitHub raw ที่น่าจะถูกต้อง
local function isValidLuaUrl(url)
    if type(url) ~= "string" then return false end
    if not url:match("^https?://") then return false end
    -- allow URLs that ends with .lua (case-insensitive) OR common raw github patterns
    local lower = safeLower(url)
    if lower:match("%.lua$") then return true end
    if lower:match("raw%.githubusercontent%.com") or lower:match("githubusercontent%.com") then return true end
    if lower:match("api%.luarmor%.net") then return true end
    return false
end

local function getHostnameFromUrl(url)
    local host = url:match("^https?://([^/]+)")
    if host then
        host = host:match("([^:]+)") -- strip :port if any
    end
    return host
end

-- -----------------------
-- Basic environment checks
-- -----------------------
local placeConfig = allowedPlaces[game.PlaceId]
if not placeConfig then
    -- Kick เฉพาะ client ที่เป็น LocalScript; ป้องกัน server script เรียก
    if Players.LocalPlayer then
        Players.LocalPlayer:Kick("[ ATG ] NOT SUPPORT")
    else
        logError("PlaceId not supported and no LocalPlayer found. Stopping loader.")
    end
    return
end

logInfo(("Script loaded for PlaceId %s (%s)"):format(tostring(game.PlaceId), tostring(placeConfig.name)))

-- Early HttpService check
if not HttpService.HttpEnabled then
    logError("HttpService.HttpEnabled = false. ไม่สามารถโหลดสคริปต์จาก URL ได้.")
    -- fallback: ถ้ามี ModuleScript ใน ReplicatedStorage ให้ใช้ (ตัวอย่าง commented ไว้ด้านล่าง)
    -- return
end

-- -----------------------
-- Fetch helpers (with pcall, timeout-friendly)
-- -----------------------
local function fetchScript(url)
    if not HttpService.HttpEnabled then
        return false, "HttpService disabled"
    end

    local ok, res = pcall(function()
        -- prefer GetAsync as it's standard; but keep :HttpGet as fallback for some executors
        -- note: some exploit runners override game:HttpGet; pcall to be safe
        if HttpService.GetAsync then
            return HttpService:GetAsync(url, true)
        else
            return game:HttpGet(url, true)
        end
    end)
    if not ok then
        return false, res
    end
    return true, res
end

-- limit size (ป้องกันโหลดไฟล์ใหญ่เกินไป)
local MAX_SCRIPT_BYTES = 200 * 1024 -- 200 KB

local function loadExtraScript(url, options)
    options = options or {}
    local retries = options.retries or 3
    local retryDelay = options.retryDelay or 1
    local allowed_domains = placeConfig.allowed_domains or {}

    if not isValidLuaUrl(url) then
        return false, "Invalid URL (must be https and .lua or approved raw host)"
    end

    local host = getHostnameFromUrl(url)
    if #allowed_domains > 0 then
        local okHost = false
        for _, d in ipairs(allowed_domains) do
            if safeLower(host):match(d) then
                okHost = true
                break
            end
        end
        if not okHost then
            return false, ("Host '%s' not allowed for this place"):format(tostring(host))
        end
    end

    local loadFn = loadstring or load -- compatibility
    for attempt = 1, retries do
        local ok, res = fetchScript(url)
        if ok and type(res) == "string" and #res > 0 then
            if #res > MAX_SCRIPT_BYTES then
                logWarn(("Remote script too large (%d bytes)"):format(#res))
                return false, "Remote script exceeds size limit"
            end

            -- try to load (safe pcall)
            local execOk, execRes = pcall(function()
                local f, loadErr = loadFn(res)
                if not f then
                    error(("load error: %s"):format(tostring(loadErr)))
                end
                -- run in protected environment: try to set an environment table if supported
                -- Note: setfenv exists in Lua 5.1; Roblox may not allow environment modification.
                -- We simply execute the chunk; user script is responsible for its own safety.
                return f()
            end)

            if execOk then
                return true, execRes
            else
                logWarn(("Attempt %d: failed to execute script from %s -> %s"):format(attempt, url, tostring(execRes)))
            end
        else
            logWarn(("Attempt %d: failed to fetch %s -> %s"):format(attempt, url, tostring(res)))
        end

        if attempt < retries then
            task.wait(retryDelay)
        end
    end

    return false, ("All %d attempts failed for %s"):format(retries, url)
end

-- -----------------------
-- Runner (non-blocking)
-- -----------------------
coroutine.wrap(function()
    logInfo("เริ่มโหลดสคริปต์สำหรับแมพ:", placeConfig.name, placeConfig.url)
    local ok, result = loadExtraScript(placeConfig.url, { retries = 3, retryDelay = 1 })

    if ok then
        logInfo("✅ Extra script loaded successfully for", placeConfig.name)
    else
        logError("❌ ไม่สามารถโหลดสคริปต์เพิ่มเติมได้:", result)
        -- fallback example: require ModuleScript from ReplicatedStorage
        local fallbackName = "Fallback_" .. tostring(placeConfig.name)
        local mod = ReplicatedStorage:FindFirstChild(fallbackName)
        if mod and mod:IsA("ModuleScript") then
            local success, modRes = pcall(require, mod)
            if success then
                logInfo("✅ Loaded fallback ModuleScript for", placeConfig.name)
            else
                logError("Fallback ModuleScript error:", modRes)
            end
        else
            logWarn("No fallback ModuleScript found:", fallbackName)
        end
    end
end)()
