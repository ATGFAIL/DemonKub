-- Key-checker + Place-based loader (รวมกัน)
--  - หา/เก็บ HWID เครื่องลูกข่าย
--  - ส่ง HWID ไปที่ /api/key/check (x-api-key = EXECUTOR_API_KEY)
--  - ถ้า key มี hwid อยู่แล้วและไม่ตรง -> LocalPlayer:Kick()
--  - ถ้าผ่าน -> โหลดสคริปต์ของแมพตาม allowedPlaces

local KEY_SERVER_URL = "http://119.59.124.192:3000" -- ใส่ URL จริงของคุณ
local EXECUTOR_API_KEY = "Xy4Mz9Rt6LpB2QvH7WdK1JnC" -- ใส่ค่า x-api-key จริงของคุณ

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- อ่าน key จาก getgenv แบบที่คุณต้องการ
local key = (getgenv and getgenv().key) or _G.key or nil

-- ------------------------------------------------------------------
-- http_request helper: รองรับ syn.request / request / http_request / HttpService:RequestAsync
-- คืนค่า table { StatusCode = n, Body = s } หรือ nil, err
-- ------------------------------------------------------------------
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

-- ------------------------------------------------------------------
-- หา HWID: พยายามหลายวิธี (readfile/writefile, identifyexecutor, syn.get_executor, getexecutor, fallbacks)
-- ------------------------------------------------------------------
local function get_or_create_hwid()
    local fname = "ATG_hwid.txt"
    -- 1) try readfile (persisted)
    local ok, content = pcall(function() if readfile then return readfile(fname) end end)
    if ok and content and tostring(content) ~= "" then
        return tostring(content)
    end

    -- 2) exploit specific identifiers
    local hwid = nil
    pcall(function()
        if identifyexecutor then
            hwid = tostring(identifyexecutor())
        end
    end)
    pcall(function()
        if not hwid and getexecutor then
            hwid = tostring(getexecutor())
        end
    end)
    pcall(function()
        if not hwid and syn and syn.get_executor then
            hwid = tostring(syn.get_executor())
        end
    end)
    pcall(function()
        -- some exploits expose .getname or similar; try a few variations (safe pcall)
        if not hwid and (typeof or type) and type(syn) == "table" and syn.get_env and syn.get_env()._G then
            -- ignore, just a safe attempt placeholder
        end
    end)

    -- 3) fallback: player.UserId plus random salt to make reasonably unique
    if not hwid then
        local pid = "anon"
        pcall(function() if LocalPlayer and LocalPlayer.UserId then pid = tostring(LocalPlayer.UserId) end end)
        hwid = pid .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000,999999))
    end

    -- 4) try persist the hwid (writefile) so it remains across runs (if exploit supports)
    pcall(function()
        if writefile then
            writefile(fname, hwid)
        end
    end)

    return hwid
end

local HWID = get_or_create_hwid()

-- ------------------------------------------------------------------
-- ส่ง key+hwid ไปที่ /api/key/check
--  - server implementation (ตามที่คุณให้มาด้านบน) จะ bind hwid ถ้า row.hwid ว่าง
--  - ถ้า server ตอบว่า key ผูกกับ hwid อื่น -> kick
-- ------------------------------------------------------------------
local function check_key_or_kick(key)
    if not key or key == "" then
        warn("[KeyCheck] No key provided. Set (getgenv()).key = \"YOUR_KEY\"")
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
        return false
    end

    local status = res.StatusCode or res.status
    local body = res.Body or res.body or tostring(res)

    local ok, j = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok then
        warn("[KeyCheck] Invalid JSON from server:", tostring(body))
        return false
    end

    -- ถ้า server ส่งรหัสสถานะ 403 -> ปฏิเสธ (อาจเป็น banned/revoked/expired/bound mismatch)
    if status == 403 then
        local errtxt = tostring(j.error or "")
        local lower = string.lower(errtxt)
        -- ถ้า server แจ้งว่า bound to another -> kick ทันที
        if string.find(lower, "bound") or string.find(lower, "another hwid") or string.find(lower, "bound to another") or string.find(lower, "bound to") then
            pcall(function()
                if LocalPlayer and LocalPlayer.Kick then
                    -- แจ้งข้อความก่อน kick สั้น ๆ (delay เล็กน้อยให้เห็น)
                    pcall(function()
                        -- พยายามแสดงข้อความก่อน kick (some exploits support SetCore/SendNotification, but simple warn is used)
                    end)
                    LocalPlayer:Kick("คีย์ผูกกับเครื่องอื่น (HWID mismatch).")
                end
            end)
            return false
        end
        -- banned / revoked / expired - แสดงเตือนแล้วหยุด
        if string.find(lower, "banned") or string.find(lower, "revoked") or string.find(lower, "expired") then
            warn("[KeyCheck] Access denied: " .. tostring(j.error))
            return false
        end
        warn("[KeyCheck] Access denied (403). Msg: " .. tostring(j.error))
        return false
    end

    -- status 2xx + j.ok true -> ผ่าน
    if j.ok then
        -- server อาจคืนค่า j.hwid ถ้ามีข้อมูล; ถ้ามีและไม่ตรง -> kick (safety double-check)
        local server_hwid = tostring(j.hwid or "")
        if server_hwid ~= "" and server_hwid ~= tostring(HWID) then
            pcall(function()
                if LocalPlayer and LocalPlayer.Kick then
                    LocalPlayer:Kick("คีย์ผูกกับ HWID อื่น (access denied).")
                end
            end)
            return false
        end
        -- ถ้า j.ok true และ (server_hwid == HWID) หรือ server_hwid == "" (server ผูกเรียบร้อย) -> ผ่าน
        print("[KeyCheck] Key valid. HWID:", tostring(HWID))
        return true
    end

    -- fallback: ถ้า server ไม่คืน ok -> แสดง error
    warn("[KeyCheck] Server rejected key: " .. tostring(j.error or "unknown"))
    return false
end

-- ------------------------------------------------------------------
-- main: ตรวจคีย์ก่อนโหลดส่วนที่เหลือ
-- ------------------------------------------------------------------
if not key then
    warn("[KeyCheck] No key found. Set (getgenv()).key = \"ATGKK...\" and re-run loader.")
    return
end

local passed = false
local ok, err = pcall(function() passed = check_key_or_kick(key) end)
if not ok then
    warn("[KeyCheck] Unexpected error during key check:", tostring(err))
    passed = false
end

if not passed then
    -- ไม่ผ่าน -> หยุด ไม่โหลดสคริปต์ต่อ (หรือผู้เล่นถูก kick แล้ว)
    return
end

-- ------------------------------------------------------------------
-- ส่วน loader ของคุณ (allowedPlaces) — จะทำงานต่อเมื่อ key ผ่านแล้ว
-- ------------------------------------------------------------------
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
