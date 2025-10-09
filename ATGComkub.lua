local KEY_SERVER_URL = "http://119.59.124.192:3000"
local EXECUTOR_API_KEY = "Xy4Mz9Rt6LpB2QvH7WdK1JnC"

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ✅ จำลองฟังก์ชัน gethwid
local function gethwid()
    return game:GetService("RbxAnalyticsService"):GetClientId()
end

-- ✅ อ่าน/เขียนไฟล์ local
local function read_local_keyinfo()
    local path = "keyinfo.json"
    if isfile and isfile(path) then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfile(path))
        end)
        if ok then return data end
    end
    return nil
end

local function write_local_keyinfo(data)
    local path = "keyinfo.json"
    if writefile then
        writefile(path, HttpService:JSONEncode(data))
    end
end

local HWID = gethwid()

local function safe_kick(msg)
    pcall(function()
        LocalPlayer:Kick(tostring(msg or "Access denied"))
    end)
end

-- ✅ HTTP wrapper
local function http_request(opts)
    local funcs = { syn and syn.request, request, http_request }
    for _, fn in ipairs(funcs) do
        if fn then
            local ok, res = pcall(fn, opts)
            if ok and res then
                return { StatusCode = res.StatusCode or res.status, Body = res.Body or res.body }
            end
        end
    end
    if HttpService.RequestAsync then
        local ok, res = pcall(function()
            return HttpService:RequestAsync(opts)
        end)
        if ok and res then
            return { StatusCode = res.StatusCode, Body = res.Body }
        end
    end
end

-- ✅ ฟังก์ชัน bind key
local function bind_key_to_hwid(key)
    local payload = HttpService:JSONEncode({ key = key, hwid = HWID })
    local res = http_request({
        Url = KEY_SERVER_URL .. "/api/key/bind",
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
            ["x-api-key"] = EXECUTOR_API_KEY
        },
        Body = payload
    })
    if not res then return false end
    local ok, j = pcall(function() return HttpService:JSONDecode(res.Body) end)
    return ok and j.ok
end

-- ✅ ฟังก์ชันเช็ค key
local function check_key_or_kick(key)
    local payload = HttpService:JSONEncode({ key = key, hwid = HWID })
    local res = http_request({
        Url = KEY_SERVER_URL .. "/api/key/check",
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
            ["x-api-key"] = EXECUTOR_API_KEY
        },
        Body = payload
    })

    if not res then
        safe_kick("ไม่สามารถติดต่อเซิร์ฟเวอร์ได้.")
        return false
    end

    local ok, j = pcall(function() return HttpService:JSONDecode(res.Body) end)
    if not ok or not j then
        safe_kick("ข้อมูลจากเซิร์ฟเวอร์ไม่ถูกต้อง.")
        return false
    end

    if res.StatusCode == 404 then
        safe_kick("คีย์ไม่ถูกต้อง.")
        return false
    elseif res.StatusCode == 403 then
        safe_kick("คีย์ถูกจำกัดการใช้งาน: " .. tostring(j.error))
        return false
    elseif j.ok then
        if j.hwid == "" then
            print("[KeyCheck] Binding new HWID...")
            bind_key_to_hwid(key)
        elseif j.hwid ~= HWID then
            safe_kick("คีย์นี้ผูกกับเครื่องอื่น.")
            return false
        end
        write_local_keyinfo({ key = key, hwid = HWID })
        print("[KeyCheck] ✅ Key verified and saved.")
        return true
    end
end

-- ✅ main
local function main()
    local info = read_local_keyinfo()
    local key = (info and info.key) or (getgenv and getgenv().key) or _G.key
    if not key then
        safe_kick("กรุณาใส่คีย์ก่อนใช้งาน (getgenv().key = 'YOUR_KEY')")
        return
    end
    check_key_or_kick(key)
end

main()

    -- ถ้าถึงตรงนี้แปลว่า key ถูกยืนยันและ hwid ตรง -> โหลดสคริปต์ของแมพ
    -- -----------------------
    -- Loader ส่วน allowedPlaces (เดิม)
    -- -----------------------
    local RunService  = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    local allowedPlaces = {
        [8069117419]          = { name = "demon",               url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/demon.lua" },
        [127742093697776]     = { name = "Plants-Vs-Brainrots", url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/Plants-Vs-Brainrots.lua" },
        [96114180925459]      = { name = "Lasso-Animals",       url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/Lasso-Animals.lua" },
        [135880624242201]     = { name = "Cut-Tree",            url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/cut-tree.lua" },
        [142823291]           = { name = "Murder-Mystery-2",     url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/Murder-Mystery-2.lua" },
    }

    local function logInfo(...) print("🟩 [Loader]", ...) end
    local function logWarn(...) warn("🟨 [Loader]", ...) end
    local function logError(...) warn("🛑 [Loader]", ...) end

    local function isValidLuaUrl(url)
        if type(url) ~= "string" then return false end
        if not url:match("^https?://") then return false end
        if not url:lower():match("%.lua$") then return false end
        return true
    end

    local placeConfig = allowedPlaces[game.PlaceId]
    if not placeConfig then
        logWarn("Script ไม่ทำงานในแมพนี้:", tostring(game.PlaceId))
        return
    end

    logInfo(("Script loaded for PlaceId %s (%s)"):format(tostring(game.PlaceId), tostring(placeConfig.name)))

    if not HttpService.HttpEnabled then
        logError("HttpService.HttpEnabled = false. ไม่สามารถโหลดสคริปต์จาก URL ได้.")
        -- return -- ถ้าต้องการให้หยุดให้ uncomment
    end

    local function fetchScript(url)
        local ok, result = pcall(function() return game:HttpGet(url, true) end)
        return ok, result
    end

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
                local execOk, execRes = pcall(function()
                    local f, loadErr = loadstring(res)
                    if not f then error(("loadstring error: %s"):format(tostring(loadErr))) end
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
                wait(retryDelay)
            end
        end

        return false, ("All %d attempts failed for %s"):format(retries, url)
    end

    coroutine.wrap(function()
        logInfo("เริ่มโหลดสคริปต์สำหรับแมพ:", placeConfig.name, placeConfig.url)
        local ok, result = loadExtraScript(placeConfig.url, { retries = 3, retryDelay = 1 })

        if ok then
            logInfo("✅ Extra script loaded successfully for", placeConfig.name)
        else
            logError("❌ ไม่สามารถโหลดสคริปต์เพิ่มเติมได้:", result)
        end
    end)()
end

-- run
main()
