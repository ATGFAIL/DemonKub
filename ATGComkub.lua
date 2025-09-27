-- -----------------------
-- Allowed PlaceIds
-- -----------------------
local allowedPlaces = {
    [8069117419] = "demon", -- ตัวอย่างแมพ 1
    [126509999114328] = "99afk"  -- ตัวอย่างแมพ 2
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
elseif placeType == "99afk" then
    loadExtraScript("https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/99afk.lua")
end
