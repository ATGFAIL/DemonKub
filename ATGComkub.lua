-- Key-checker + Place-based loader (ปรับตามคำขอ)
-- พฤติกรรมหลัก:
-- 1) หา hwid ด้วยฟังก์ชัน gethwid()
-- 2) อ่าน/จำคีย์+hwid ในไฟล์ local ("ATG_keyinfo.json")
-- 3) ถ้ามี key ในเครื่องแล้วแต่ hwid ในเครื่องเปลี่ยน -> Kick ทันที
-- 4) ถ้าไม่มี key ในเครื่อง จะอ่านจาก getgenv().key/_G.key แล้วส่งไปเช็คกับ /api/key/check
-- 5) ถ้า server ตอบรับ จะบันทึก key+hwid ไว้ในเครื่อง และรันสคริปต์เฉพาะแมพ
-- 6) ถ้า server ปฏิเสธ (404/403/invalid/etc) -> Kick ทันที

local KEY_SERVER_URL = "http://119.59.124.192:3000" -- เปลี่ยนเป็น URL จริงถ้าจำเป็น
local EXECUTOR_API_KEY = "Xy4Mz9Rt6LpB2QvH7WdK1JnC" -- ใส่ x-api-key จริงของ executor

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- -----------------------
-- http_request helper
-- -----------------------
local function http_request(opts)
    -- opts: { Url=..., Method='POST', Headers = {}, Body = '...' }
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

-- -----------------------
-- gethwid(): พยายามหลายวิธี แล้ว persist (writefile) ถ้าได้
-- -----------------------
local function gethwid()
    local fname = "ATG_hwid.txt"
    -- 1) ถ้ามีไฟล์เก็บ hwid คืนค่านั้นก่อน
    local ok, stored = pcall(function() if readfile then return readfile(fname) end end)
    if ok and stored and tostring(stored) ~= "" then
        return tostring(stored)
    end

    -- 2) พยายามใช้ identifyexecutor / getexecutor / syn.get_executor
    local hwid = nil
    pcall(function() if identifyexecutor then hwid = tostring(identifyexecutor()) end end)
    pcall(function() if not hwid and getexecutor then hwid = tostring(getexecutor()) end end)
    pcall(function() if not hwid and syn and syn.get_executor then hwid = tostring(syn.get_executor()) end end)

    -- 3) fallback: ใช้ LocalPlayer.UserId + random salt (แต่จะไม่เปลี่ยนบ่อยเพราะเราจะเขียนลงไฟล์)
    if not hwid then
        local pid = "anon"
        pcall(function() if LocalPlayer and LocalPlayer.UserId then pid = tostring(LocalPlayer.UserId) end end)
        hwid = pid .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000,999999))
    end

    -- 4) persist ถ้า writefile มี
    pcall(function()
        if writefile then
            writefile(fname, tostring(hwid))
        end
    end)

    return tostring(hwid)
end

local HWID = gethwid()

-- -----------------------
-- Local storage for key+hwid (remember)
-- -----------------------
local KEYINFO_FILE = "ATG_keyinfo.json"

local function read_local_keyinfo()
    local ok, content = pcall(function()
        if readfile and isfile and isfile(KEYINFO_FILE) then
            return readfile(KEYINFO_FILE)
        end
        -- some exploits expose readfile without isfile, try safely
        if readfile then
            return readfile(KEYINFO_FILE)
        end
        return nil
    end)
    if not ok or not content then return nil end

    local parsed
    local success, err = pcall(function() parsed = HttpService:JSONDecode(content) end)
    if not success then return nil end
    return parsed
end

local function write_local_keyinfo(tbl)
    pcall(function()
        local s = HttpService:JSONEncode(tbl)
        if writefile then
            writefile(KEYINFO_FILE, s)
        end
    end)
end

-- -----------------------
-- Kick helper (ปลอดภัยด้วย pcall)
-- -----------------------
local function safe_kick(msg)
    pcall(function()
        if LocalPlayer and LocalPlayer.Kick then
            LocalPlayer:Kick(tostring(msg or "Access denied"))
        end
    end)
end

-- -----------------------
-- check_key_or_kick: ส่งไปเซิร์ฟ, ถ้าไม่ผ่าน -> kick
-- ถ้าผ่าน -> บันทึก key+hwid ลงไฟล์
-- -----------------------
local function check_key_or_kick(key)
    if not key or key == "" then
        warn("[KeyCheck] No key provided.")
        safe_kick("ต้องใส่คีย์ก่อนจะเล่น (No key provided).")
        return false
    end

    local url = KEY_SERVER_URL:gsub("/+$","") .. "/api/key/check"
    local payloadTable = { key = tostring(key), hwid = tostring(HWID) }
    local payload = HttpService:JSONEncode(payloadTable)
    local headers = {
        ["Content-Type"] = "application/json",
        ["x-api-key"] = EXECUTOR_API_KEY
    }

    local res, err = http_request({ Url = url, Method = "POST", Headers = headers, Body = payload })
    if not res then
        warn("[KeyCheck] HTTP request failed:", tostring(err))
        safe_kick("ไม่สามารถติดต่อเซิร์ฟเวอร์ได้ (HTTP failed).")
        return false
    end

    local status = res.StatusCode or res.status
    local body = res.Body or res.body or tostring(res)
    local ok, j = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok then
        warn("[KeyCheck] Invalid JSON from server:", tostring(body))
        safe_kick("การตอบกลับจากเซิร์ฟเวอร์ไม่ถูกต้อง.")
        return false
    end

    -- 404 -> key ไม่พบ
    if status == 404 then
        warn("[KeyCheck] Key not found:", tostring(key))
        safe_kick("คีย์ไม่ถูกต้อง (Key not found).")
        return false
    end

    -- 403 -> revoked/banned/expired/bound-mismatch
    if status == 403 then
        local errtxt = tostring(j.error or "Access denied")
        local lower = string.lower(errtxt)
        if string.find(lower, "bound") or string.find(lower, "another hwid") or string.find(lower, "bound to another") or string.find(lower, "bound to") then
            warn("[KeyCheck] Key bound to another HWID:", tostring(j.error))
            safe_kick("คีย์ผูกกับเครื่องอื่น (HWID mismatch).")
            return false
        end
        -- banned/revoked/expired
        safe_kick("คีย์ถูกจำกัดการใช้งาน: " .. tostring(j.error or "Access denied"))
        return false
    end

    -- status 2xx + ok true -> ผ่าน
    if j.ok then
        local server_hwid = tostring(j.hwid or "")
        if server_hwid ~= "" and server_hwid ~= tostring(HWID) then
            -- server บอกว่าผูกกับ hwid อื่น -> kick
            warn("[KeyCheck] Server HWID mismatch. server_hwid=", server_hwid, " local_hwid=", HWID)
            safe_kick("คีย์นี้ผูกกับเครื่องอื่น (Key bound to another HWID).")
            return false
        end

        -- success -> บันทึก local keyinfo (key + hwid)
        write_local_keyinfo({ key = tostring(key), hwid = tostring(HWID) })
        print("[KeyCheck] Key validated and saved locally. HWID:", HWID)
        return true
    end

    -- fallback
    warn("[KeyCheck] Server rejected key:", tostring(j.error or "unknown"))
    safe_kick("การยืนยันคีย์ล้มเหลว: " .. tostring(j.error or "unknown"))
    return false
end

-- -----------------------
-- main flow: โหลด/เช็ค local keyinfo ก่อน
-- -----------------------
local function main()
    -- อ่าน local keyinfo ถ้ามี
    local localInfo = read_local_keyinfo()
    if localInfo and type(localInfo) == "table" and localInfo.key then
        -- ถ้า local key มี แต่ hwid ที่เก็บไว้ไม่ตรงกับ hwid ปัจจุบัน -> kick (ตามที่ร้องขอ)
        if localInfo.hwid and tostring(localInfo.hwid) ~= tostring(HWID) then
            warn("[KeyCheck] Local stored key exists but HWID changed. stored_hwid=", tostring(localInfo.hwid), " current_hwid=", HWID)
            safe_kick("คีย์ที่บันทึกไว้ถูกใช้บนเครื่องอื่น หรือ HWID ของเครื่องคุณเปลี่ยน (Key+HWID mismatch).")
            return
        end

        -- local key+hwid ตรงกัน (หรือไม่มี stored hwid) -> ตรวจสอบกับ server อีกครั้งเพื่อ safety
        local passed = false
        local ok, err = pcall(function() passed = check_key_or_kick(localInfo.key) end)
        if not ok then
            warn("[KeyCheck] Unexpected error during key check:", tostring(err))
            safe_kick("เกิดข้อผิดพลาดระหว่างตรวจสอบคีย์.")
            return
        end
        if not passed then
            -- check_key_or_kick จะ kick อยู่แล้ว แต่เผื่อเคสอื่นๆ ให้หยุด
            return
        end
    else
        -- ถ้าไม่มี local keyinfo -> หาคีย์จาก getgenv / _G
        local key = (getgenv and getgenv().key) or _G.key or nil
        if not key or key == "" then
            warn("[KeyCheck] No key provided (not stored locally and not in getgenv/_G).")
            safe_kick("ต้องใส่คีย์เพื่อใช้งาน (Set getgenv().key = \"YOUR_KEY\").")
            return
        end

        -- ถ้ามี localInfo แต่ key แตกต่างจาก getgenv: เราจะพยายามเช็คคีย์ที่ให้มา (override) — ถ้าผ่านจะเขียนทับ
        local passed = false
        local ok, err = pcall(function() passed = check_key_or_kick(key) end)
        if not ok then
            warn("[KeyCheck] Unexpected error during key check:", tostring(err))
            safe_kick("เกิดข้อผิดพลาดระหว่างตรวจสอบคีย์.")
            return
        end
        if not passed then
            -- check_key_or_kick จะ kick อยู่แล้ว
            return
        end
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
