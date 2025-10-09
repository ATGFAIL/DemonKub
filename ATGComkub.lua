-- Key-checker (client-side). วางไว้ก่อนโหลดสคริปต์หลักของคุณ
local KEY_SERVER_URL = "http://119.59.124.192:3000" -- เปลี่ยนเป็น URL จริงของคุณ
local EXECUTOR_API_KEY = "Xy4Mz9Rt6LpB2QvH7WdK1JnC" -- เปลี่ยนเป็นค่าจริง
-- หาคีย์จาก getgenv (แบบที่คุณต้องการใช้)
local key = (getgenv and getgenv().key) or _G.key or nil

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- http_request helper: รองรับ syn.request / request / http_request / HttpService:RequestAsync
local function http_request(opts)
    if syn and syn.request then
        local ok, res = pcall(syn.request, opts)
        if ok and res then return { StatusCode = res.StatusCode, Body = res.Body } end
    end
    if request then
        local ok, res = pcall(request, opts)
        if ok and res then return { StatusCode = res.StatusCode or res.status, Body = res.Body or res.body } end
    end
    if http_request then
        local ok, res = pcall(http_request, opts)
        if ok and res then return { StatusCode = res.StatusCode or res.status, Body = res.Body or res.body } end
    end
    if HttpService and HttpService.RequestAsync then
        local ok, res = pcall(function()
            return HttpService:RequestAsync({
                Url = opts.Url,
                Method = opts.Method or "GET",
                Headers = opts.Headers or {},
                Body = opts.Body
            })
        end)
        if ok and res then
            return { StatusCode = res.StatusCode, Body = res.Body }
        end
    end
    return nil, "no-http-method"
end

-- สร้าง/เก็บ HWID แบบง่าย: อ่านจากไฟล์ถ้ามี (writefile/readfile), ถ้าไม่มีใช้ identifyexecutor / syn.get_executor / UserId fallback
local function get_or_create_hwid()
    local fname = "ATG_hwid.txt"
    -- try readfile
    local ok, content = pcall(function() if readfile then return readfile(fname) end end)
    if ok and content and content ~= "" then
        return tostring(content)
    end

    local hwid = nil
    pcall(function()
        if identifyexecutor then hwid = tostring(identifyexecutor()) end
        if not hwid and getexecutor then hwid = tostring(getexecutor()) end
        if not hwid and syn and syn.get_executor then hwid = tostring(syn.get_executor()) end
    end)

    if not hwid then
        local pid = "anon"
        pcall(function() if LocalPlayer and LocalPlayer.UserId then pid = tostring(LocalPlayer.UserId) end end)
        hwid = pid .. "_" .. tostring(math.random(100000,999999))
    end

    -- try persist
    pcall(function()
        if writefile then writefile(fname, hwid) end
    end)

    return hwid
end

local HWID = get_or_create_hwid()

-- ตรวจคีย์กับ key server — เฉพาะกรณี mismatch HWID => kick
local function check_key_or_kick(key)
    if not key or key == "" then
        warn("[KeyCheck] No key provided. Set (getgenv()).key = \"YOUR_KEY\"")
        return false
    end

    local url = KEY_SERVER_URL:gsub("/+$","") .. "/api/key/check"
    local payload = HttpService:JSONEncode({ key = tostring(key), hwid = tostring(HWID) })
    local headers = {
        ["Content-Type"] = "application/json",
        ["x-api-key"] = EXECUTOR_API_KEY
    }

    local res, err = http_request({ Url = url, Method = "POST", Headers = headers, Body = payload })
    if not res then
        warn("[KeyCheck] HTTP request failed:", tostring(err))
        return false
    end

    local status = res.StatusCode or res.status
    local body = res.Body or res.body or tostring(res)

    local ok, j = pcall(function() return HttpService:JSONDecode(body) end)
    if status == 403 then
        -- 403 from server: could be revoked / banned / bound to another hwid / expired
        if ok and type(j) == "table" and j.error then
            local errtxt = tostring(j.error):lower()
            -- ถ้า server ระบุว่า 'bound'/'another' ให้ kick
            if string.find(errtxt, "bound") or string.find(errtxt, "another hwid") or string.find(errtxt, "bound to another") or string.find(errtxt, "key bound to another") then
                pcall(function()
                    if LocalPlayer and LocalPlayer.Kick then
                        LocalPlayer:Kick("Key bound to another HWID (access denied).")
                    end
                end)
                return false
            end
            -- กรณี banned/revoked/expired ให้แสดงข้อความและไม่โหลดต่อ (ไม่ kick โดยตรง)
            if string.find(errtxt, "banned") or string.find(errtxt, "revoked") or string.find(errtxt, "expired") then
                warn("[KeyCheck] Access denied: "..tostring(j.error))
                return false
            end
        end
        -- generic 403 -> deny
        warn("[KeyCheck] Access denied (403).")
        return false
    end

    if ok and type(j) == "table" and j.ok then
        -- success (server either bound hwid now, or hwid matched)
        print("[KeyCheck] Key ok. HWID:", tostring(HWID))
        return true
    end

    -- fallback: if server returned non-OK payload
    warn("[KeyCheck] Invalid response from server:", tostring(body))
    return false
end

-- main
if not key then
    warn("[KeyCheck] No key found. Set (getgenv()).key = \"ATGKK...\" and re-run loader.")
    return
end

local passed = false
local ok, err = pcall(function() passed = check_key_or_kick(key) end)
if not ok then
    warn("[KeyCheck] Unexpected error:", tostring(err))
    passed = false
end

if not passed then
    -- ไม่ผ่านการตรวจ (หรือโดน kick) -> หยุด ไม่โหลดสคริปต์ต่อ
    return
end

local HttpService = game:GetService("HttpService")
local RunService  = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- -----------------------
-- Allowed Place configuration
-- -----------------------
-- เพิ่มรายการได้ง่าย: ใส่ placeId => { name = "...", url = "https://.../file.lua" }
local allowedPlaces = {
    [8069117419]          = { name = "demon",               url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/demon.lua" },
    [127742093697776]     = { name = "Plants-Vs-Brainrots", url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/Plants-Vs-Brainrots.lua" },
    [96114180925459]      = { name = "Lasso-Animals",       url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/Lasso-Animals.lua" },
    [135880624242201]     = { name = "Cut-Tree",            url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/cut-tree.lua" },
    [142823291]           = { name = "Murder-Mystery-2",     url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/Murder-Mystery-2.lua" },
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
    logWarn("Script ไม่ทำงานในแมพนี้:", tostring(game.PlaceId))
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
