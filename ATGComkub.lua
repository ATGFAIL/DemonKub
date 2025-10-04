-- -----------------------
-- Allowed PlaceIds
-- -----------------------
local allowedPlaces = {
    [8069117419] = "demon", -- ตัวอย่างแมพ 1
    [127742093697776] = "Plants-Vs-Brainrots",
    [96114180925459] = "Lasso-Animals"
}

-- ตรวจสอบแมพ
local placeType = allowedPlaces[game.PlaceId]
if not placeType then
    warn("❌ Script ไม่ทำงานในแมพนี้:", game.PlaceId)
    return
end

print("✅ Script Loaded in allowed map:", game.PlaceId)

-- ฟังก์ชันโหลดสคริปต์
local function loadExtraScript(url)
    local success, result = pcall(function()
        return loadstring(game:HttpGet(url))()
    end)
    if success then
        print("✅ Extra script loaded successfully!")
    else
        warn("❌ Failed to load extra script:", result)
    end
end

-- เลือกโหลดตามแมพ
if placeType == "demon" then
    loadExtraScript("https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/demon.lua")
elseif placeType == "Plants-Vs-Brainrots" then
    loadExtraScript("https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/Plants-Vs-Brainrots.lua")
elseif placeType == "Lasso-Animals" then
    loadExtraScript("https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/Lasso-Animals.lua")
end
