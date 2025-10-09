-- Key-check Client (Roblox) - ใช้งานกับ server.js ที่ให้มา
-- ตั้งค่า
local KEY_SERVER_URL = "http://119.59.124.192:3000" -- เปลี่ยนเป็น URL/IP ของเซิร์ฟจริงถ้าจำเป็น
local EXECUTOR_API_KEY = "Xy4Mz9Rt6LpB2QvH7WdK1JnC" -- ต้องตรงกับ API_KEY ของ server (x-api-key)

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ---------- HWID helper ----------
-- พยายามใช้ GetClientId (ค่อนข้างเสถียร) ถ้าไม่มีให้ fallback เป็น hash ของ UserId+machine
local function gethwid()
    -- ถ้ามี RbxAnalyticsService ให้ใช้ GetClientId
    local ok, svc = pcall(function() return game:GetService("RbxAnalyticsService") end)
    if ok and svc and svc.GetClientId then
        local ok2, id = pcall(function() return svc:GetClientId() end)
        if ok2 and id then return tostring(id) end
    end

    -- fallback: ถ้า exploit มีฟังก์ชันเฉพาะ (ตัวอย่าง)
    if syn and syn.get_misc_id then
        local ok3, id2 = pcall(syn.get_misc_id)
        if ok3 and id2 then return tostring(id2) end
    end

    -- fallback สุดท้าย: userId + machine random (try to be stable across runs by storing local file)
    local fallback = "rbx_" .. tostring(LocalPlayer and LocalPlayer.UserId or 0)
    return fallback
end

local HWID = gethwid()

-- ---------- Local storage helpers ----------
local KEYINFO_PATH = "keyinfo.json"

local function read_local_keyinfo()
    if type(isfile) == "function" and isfile(KEYINFO_PATH) then
        local ok, raw = pcall(readfile, KEYINFO_PATH)
        if ok and raw then
            local ok2, tbl = pcall(HttpService.JSONDecode, HttpService, raw)
            if ok2 and type(tbl) == "table" then
                return tbl
            end
        end
    end
    -- ถ้าไม่มี filesystem หรืออ่านไม่ผ่าน -> รีเทิร์น nil
    return nil
end

local function write_local_keyinfo(tbl)
    if type(writefile) == "function" then
        local ok, encoded = pcall(HttpService.JSONEncode, HttpService, tbl)
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
    -- opts: { Url=..., Method='POST', Headers = {}, Body = '...' }
    -- try syn.request
    if syn and syn.request then
        local ok, res = pcall(syn.request, opts)
        if ok and res and (res.StatusCode or res.status) then
            return { StatusCode = res.StatusCode or res.status, Body = res.Body or res.body }
        end
    end

    -- try request (other exploits)
    if request then
        local ok, res = pcall(request, opts)
        if ok and res and (res.StatusCode or res.status) then
            return { StatusCode = res.StatusCode or res.status, Body = res.Body or res.body }
        end
    end

    -- try http_request (some env)
    if http_request then
        local ok, res = pcall(http_request, opts)
        if ok and res and (res.StatusCode or res.status) then
            return { StatusCode = res.StatusCode or res.status, Body = res.Body or res.body }
        end
    end

    -- fallback to HttpService:RequestAsync
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
    end

    return nil, "no-http-method"
end

-- ---------- Main check function ----------
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

    -- ถ้าไม่เจอ key
    if status == 404 then
        warn("[KeyClient] Key not found:", tostring(key))
        safe_kick("คีย์ไม่ถูกต้อง.")
        return false
    end

    -- 403 -> revoked / banned / expired / bound-mismatch
    if status == 403 then
        local errtxt = tostring(j.error or "Access denied")
        local lower = string.lower(errtxt)
        if string.find(lower, "bound to another") or string.find(lower, "bound to another hwid") or string.find(lower, "bound to another hwid") or string.find(lower, "bound to another hwid") then
            warn("[KeyClient] Key bound to another HWID")
            safe_kick("คีย์นี้ผูกกับเครื่องอื่น.")
            return false
        end
        -- banned/revoked/expired
        warn("[KeyClient] Key rejected:", errtxt)
        safe_kick("คีย์ถูกจำกัดการใช้งาน: " .. errtxt)
        return false
    end

    -- success
    if j.ok then
        -- server จะ bind hwid ให้ถ้ายังว่าง (server.js ของแกทำอันนี้แล้ว)
        local server_hwid = tostring(j.hwid or "")
        if server_hwid ~= "" and server_hwid ~= tostring(HWID) then
            -- ถ้า server บอกผูกกับ HWID อื่น -> kick
            warn("[KeyClient] Server HWID mismatch. server_hwid=", server_hwid, " local_hwid=", HWID)
            safe_kick("คีย์นี้ผูกกับเครื่องอื่น.")
            return false
        end

        -- บันทึก local
        local wrote = write_local_keyinfo({ key = key, hwid = HWID })
        if wrote then
            print("[KeyClient] Key verified and saved locally. HWID:", HWID)
        else
            print("[KeyClient] Key verified (could not save locally). HWID:", HWID)
        end

        -- optional: can show expire info
        if j.expires_in then
            print(string.format("[KeyClient] Expires in %d seconds", tonumber(j.expires_in)))
        end

        return true
    end

    warn("[KeyClient] Unexpected server response:", body)
    safe_kick("การยืนยันคีย์ล้มเหลว.")
    return false
end

-- ---------- Main flow ----------
local function main()
    -- อ่าน local info ถ้ามี
    local localInfo = read_local_keyinfo()
    local key = nil
    if localInfo and type(localInfo) == "table" and localInfo.key then
        -- ถ้ามี local key แต่ hwid ที่เก็บไว้ไม่ตรง -> บังคับเช็คใหม่ (server จะ kick ถ้ามีปัญหา)
        if localInfo.hwid and tostring(localInfo.hwid) ~= tostring(HWID) then
            warn("[KeyClient] Stored hwid differs from current HWID. stored="..tostring(localInfo.hwid) .. " current="..tostring(HWID))
            -- พยายามเช็คกับ server เพื่อความปลอดภัย (server จะ reject ถาผูกกับเครื่องอื่น)
            key = localInfo.key
        else
            -- local stored key น่าจะใช้ได้ แต่ยังเช็ค server อีกครั้งเพื่อ safety (update last_used, expiry)
            key = localInfo.key
        end
    else
        -- ไม่มี local -> หา key จาก getgenv/_G
        key = (getgenv and getgenv().key) or _G.key or nil
    end

    if not key then
        warn("[KeyClient] No key found locally or in getgenv/_G")
        safe_kick("ต้องใส่คีย์เพื่อใช้งาน (ตั้ง getgenv().key = \"YOUR_KEY\").")
        return
    end

    -- เรียกเช็คกับ server (server จะ bind ถ้ายังไม่ผูก)
    local ok = false
    local okstatus, err = pcall(function() ok = check_key_with_server(key) end)
    if not okstatus then
        warn("[KeyClient] Unexpected error during check:", tostring(err))
        safe_kick("เกิดข้อผิดพลาดระหว่างตรวจสอบคีย์.")
        return
    end
    if not ok then
        -- check_key_with_server จะ kick ถ้าจำเป็น แต่เผื่อ fallback
        return
    end

    -- ถ้าผ่าน มาที่นี่ได้ = เข้าเล่นต่อได้
    print("[KeyClient] Access granted. Enjoy the game.")
end

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
