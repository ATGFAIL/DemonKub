-- -----------------------
-- Allowed PlaceIds
-- -----------------------
local allowedPlaces = {
    [8069117419] = true, -- ตัวอย่างแมพ 1
    [1234567890] = true  -- เพิ่มแมพอื่นถ้าต้องการ
}

-- ตรวจสอบแมพ
if not allowedPlaces[game.PlaceId] then
    warn("❌ Script ไม่ทำงานในแมพนี้:", game.PlaceId)
    return
end

print("✅ Script Loaded in allowed map:", game.PlaceId)

-- ถ้าแมพตรง ให้โหลด loadstring ตัวอื่น
local function loadExtraScript()
    local success, result = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/ATGFAIL/ATGHub/main/Demon.lua"))()
    end)
    if success then
        print("✅ Extra script loaded successfully!")
    else
        warn("❌ Failed to load extra script:", result)
    end
end

-- เรียกฟังก์ชัน
loadExtraScript()
