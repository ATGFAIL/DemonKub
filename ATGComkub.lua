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
-- run
main()
