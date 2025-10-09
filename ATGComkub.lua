-- Key-check + Loader (Roblox) - ปรับปรุงจากของคุณให้ใช้งานได้จริง
local KEY_SERVER_URL = "http://119.59.124.192:3000"
local EXECUTOR_API_KEY = "Xy4Mz9Rt6LpB2QvH7WdK1JnC"

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- wait for LocalPlayer (safe)
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    repeat
        Players.PlayerAdded:Wait()
        LocalPlayer = Players.LocalPlayer
    until LocalPlayer
end

-- ---------- HWID helper ----------
local function gethwid()
    -- try RbxAnalyticsService:GetClientId()
    local ok, svc = pcall(function() return game:GetService("RbxAnalyticsService") end)
    if ok and svc and svc.GetClientId then
        local ok2, id = pcall(function() return svc:GetClientId() end)
        if ok2 and id and tostring(id) ~= "" then return tostring(id) end
    end

    -- exploit-specific fallback examples
    if syn and syn.get_misc_id then
        local ok3, id2 = pcall(syn.get_misc_id)
        if ok3 and id2 and tostring(id2) ~= "" then return tostring(id2) end
    end

    -- last resort: stable fallback based on UserId (not secure but stable)
    return "rbx_user_" .. tostring(LocalPlayer.UserId or 0)
end

local HWID = gethwid()

-- ---------- Local storage helpers ----------
local KEYINFO_PATH = "keyinfo.json"

local function read_local_keyinfo()
    if type(isfile) == "function" and isfile(KEYINFO_PATH) then
        local ok, raw = pcall(readfile, KEYINFO_PATH)
        if ok and raw then
            local ok2, tbl = pcall(function() return HttpService:JSONDecode(raw) end)
            if ok2 and type(tbl) == "table" then
                return tbl
            end
        end
    end
    return nil
end

local function write_local_keyinfo(tbl)
    if type(writefile) == "function" then
        local ok, encoded = pcall(function() return HttpService:JSONEncode(tbl) end)
        if ok and encoded then
            pcall(writefile, KEYINFO_PATH, encoded)
            return true
        end
    end
    return false
end

-- ---------- Safe kick ----------
local function safe_kick(msg)
    pcall(function()
        if LocalPlayer and LocalPlayer.Kick then
            LocalPlayer:Kick(tostring(msg or "Access denied"))
        end
    end)
end

-- ---------- HTTP wrapper (รองรับหลาย exploit) ----------
local function http_request(opts)
    -- opts: { Url=..., Method='GET'/'POST', Headers = {}, Body = '...' }
    local tried = {}

    if syn and syn.request then
        local ok, res = pcall(syn.request, opts)
        if ok and res and (res.StatusCode or res.status) then
            return { StatusCode = res.StatusCode or res.status, Body = res.Body or res.body }
        end
        table.insert(tried, "syn.request")
    end

    if request then
        local ok, res = pcall(request, opts)
        if ok and res and (res.StatusCode or res.status) then
            return { StatusCode = res.StatusCode or res.status, Body = res.Body or res.body }
        end
        table.insert(tried, "request")
    end

    if http and http.request then
        local ok, res = pcall(http.request, opts)
        if ok and res and (res.StatusCode or res.status) then
            return { StatusCode = res.StatusCode or res.status, Body = res.Body or res.body }
        end
        table.insert(tried, "http.request")
    end

    -- HttpService fallback
    if HttpService and HttpService.RequestAsync then
        local ok, res = pcall(function()
            return HttpService:RequestAsync({
                Url = opts.Url,
                Method = opts.Method or "GET",
                Headers = opts.Headers or {},
                Body = opts.Body
            })
        end)
        if ok and res and res.StatusCode then
            return { StatusCode = res.StatusCode, Body = res.Body }
        end
        table.insert(tried, "HttpService:RequestAsync")
    end

    return nil, "no-http-method: tried "..table.concat(tried, ", ")
end

-- ---------- Check key with server ----------
local function check_key_with_server(key)
    if not key or key == "" then
        warn("[KeyClient] No key given")
        safe_kick("ต้องใส่คีย์ก่อนใช้งาน.")
        return false
    end

    local payloadTable = { key = tostring(key), hwid = tostring(HWID) }
    local payload = HttpService:JSONEncode(payloadTable)
    local headers = {
        ["Content-Type"] = "application/json",
        ["x-api-key"] = EXECUTOR_API_KEY
    }

    local res, err = http_request({
        Url = (KEY_SERVER_URL:gsub("/+$","")) .. "/api/key/check",
        Method = "POST",
        Headers = headers,
        Body = payload
    })

    if not res then
        warn("[KeyClient] HTTP failed:", tostring(err))
        safe_kick("ไม่สามารถติดต่อเซิร์ฟเวอร์ได้.")
        return false
    end

    local status = res.StatusCode or res.status
    local body = res.Body or res.body or ""
    local ok, j = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok or type(j) ~= "table" then
        warn("[KeyClient] Invalid JSON:", tostring(body))
        safe_kick("การตอบกลับจากเซิร์ฟเวอร์ไม่ถูกต้อง.")
        return false
    end

    if status == 404 then
        warn("[KeyClient] Key not found:", tostring(key))
        safe_kick("คีย์ไม่ถูกต้อง.")
        return false
    end

    if status == 403 then
        local errtxt = tostring(j.error or "Access denied")
        local lower = string.lower(errtxt)
        if string.find(lower, "bound to another") then
            warn("[KeyClient] Key bound to another HWID")
            safe_kick("คีย์นี้ผูกกับเครื่องอื่น.")
            return false
        end
        warn("[KeyClient] Key rejected:", errtxt)
        safe_kick("คีย์ถูกจำกัดการใช้งาน: " .. errtxt)
        return false
    end

    if j.ok then
        local server_hwid = tostring(j.hwid or "")
        if server_hwid ~= "" and server_hwid ~= tostring(HWID) then
            warn("[KeyClient] Server HWID mismatch. server_hwid=", server_hwid, " local_hwid=", HWID)
            safe_kick("คีย์นี้ผูกกับเครื่องอื่น.")
            return false
        end

        write_local_keyinfo({ key = key, hwid = HWID })
        if j.expires_in then
            pcall(function()
                print(string.format("[KeyClient] Expires in %d seconds", tonumber(j.expires_in)))
            end)
        end

        return true
    end

    warn("[KeyClient] Unexpected server response:", body)
    safe_kick("การยืนยันคีย์ล้มเหลว.")
    return false
end

-- ---------- Loader (allowedPlaces) ----------
local allowedPlaces = {
    [8069117419]      = { name = "demon",               url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/demon.lua" },
    [127742093697776] = { name = "Plants-Vs-Brainrots", url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/Plants-Vs-Brainrots.lua" },
    [96114180925459]  = { name = "Lasso-Animals",       url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/Lasso-Animals.lua" },
    [135880624242201] = { name = "Cut-Tree",            url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/cut-tree.lua" },
    [142823291]       = { name = "Murder-Mystery-2",    url = "https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/Murder-Mystery-2.lua" },
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

-- fetch script using our http_request (safer across exploits)
local function fetchScriptViaRequest(url)
    local res, err = http_request({ Url = url, Method = "GET" })
    if not res then return false, tostring(err) end
    if (res.StatusCode or res.status) >= 200 and (res.StatusCode or res.status) < 300 then
        return true, res.Body or res.body or ""
    end
    return false, ("HTTP %s"):format(tostring(res.StatusCode or res.status))
end

local function loadExtraScript(url, options)
    options = options or {}
    local retries = options.retries or 3
    local retryDelay = options.retryDelay or 1

    if not isValidLuaUrl(url) then
        return false, "Invalid URL (must be http(s) and end with .lua)"
    end

    for attempt = 1, retries do
        local ok, res = fetchScriptViaRequest(url)
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

-- ---------- Main flow ----------
local function main()
    -- read local or getgenv/_G key
    local localInfo = read_local_keyinfo()
    local key
    if localInfo and type(localInfo) == "table" and localInfo.key then
        key = localInfo.key
    else
        key = (getgenv and getgenv().key) or _G.key or nil
    end

    if not key then
        warn("[KeyClient] No key found locally or in getgenv/_G")
        safe_kick("ต้องใส่คีย์เพื่อใช้งาน (ตั้ง getgenv().key = \"YOUR_KEY\").")
        return
    end

    local ok, err = pcall(function() return check_key_with_server(key) end)
    if not ok then
        warn("[KeyClient] Error during key check:", tostring(err))
        safe_kick("เกิดข้อผิดพลาดระหว่างตรวจสอบคีย์.")
        return
    end
    if not err then
        -- check failed (check_key_with_server already kicked)
        return
    end

    -- ผ่านแล้ว -> โหลดสคริปต์สำหรับแมพนี้
    local placeConfig = allowedPlaces[game.PlaceId]
    if not placeConfig then
        logWarn("Script ไม่ทำงานในแมพนี้:", tostring(game.PlaceId))
        return
    end

    logInfo(("Script loaded for PlaceId %s (%s)"):format(tostring(game.PlaceId), tostring(placeConfig.name)))

    if not HttpService.HttpEnabled then
        logWarn("HttpService.HttpEnabled = false. จะพยายามใช้ exploit http (syn.request/request) แทน")
    end

    coroutine.wrap(function()
        logInfo("เริ่มโหลดสคริปต์สำหรับแมพ:", placeConfig.name, placeConfig.url)
        local ok2, result = loadExtraScript(placeConfig.url, { retries = 3, retryDelay = 1 })
        if ok2 then
            logInfo("✅ Extra script loaded successfully for", placeConfig.name)
        else
            logError("❌ ไม่สามารถโหลดสคริปต์เพิ่มเติมได้:", result)
        end
    end)()
end

-- run
main()
