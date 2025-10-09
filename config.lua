local httpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local InterfaceManager = {} do
	-- root folder (can be changed via SetFolder)
	InterfaceManager.FolderRoot = "FluentSettings"

	-- default settings
    InterfaceManager.Settings = {
        Theme = "Dark",
        Acrylic = true,
        Transparency = true,
        MenuKeybind = "LeftControl"
    }

	-- helpers
	local function sanitizeFilename(name)
		-- แทนที่ตัวอักษรที่ไม่ปลอดภัยด้วย underscore
		-- เก็บแค่ A-Z a-z 0-9 - _ และ space (space -> underscore)
		name = tostring(name or "")
		-- เปลี่ยน space -> _
		name = name:gsub("%s+", "_")
		-- ลบตัวอักษรที่ไม่ใช่ alnum, -, _
		name = name:gsub("[^%w%-%_]", "")
		if name == "" then
			return "Unknown"
		end
		return name
	end

	local function getPlaceId()
		-- game.PlaceId จะเป็นตัวเลข; แปลงเป็น string
		local success, id = pcall(function() return tostring(game.PlaceId) end)
		if success and id then
			return id
		end
		return "UnknownPlace"
	end

	local function getMapName()
		-- พยายามหา object "Map" ใน Workspace เพื่อเอาชื่อแมพ
		local ok, map = pcall(function() return Workspace:FindFirstChild("Map") end)
		if ok and map and map:IsA("Instance") then
			return sanitizeFilename(map.Name)
		end
		-- ถ้าไม่เจอ ให้ลองใช้ Workspace.Name หรือ ให้ชื่อ UnknownMap
		local ok2, wname = pcall(function() return Workspace.Name end)
		if ok2 and wname then
			return sanitizeFilename(wname)
		end
		return "UnknownMap"
	end

	local function ensureFolder(path)
		if not isfolder(path) then
			makefolder(path)
		end
	end

	-- สร้างโครงสร้างโฟลเดอร์ root -> placeId
    function InterfaceManager:BuildFolderTree()
		local root = self.FolderRoot
		ensureFolder(root)

		local placeId = getPlaceId()
		local placeFolder = root .. "/" .. placeId
		ensureFolder(placeFolder)

		-- เก็บโฟลเดอร์ settings เป็น legacy / อาจมีประโยชน์
		local settingsFolder = root .. "/settings"
		if not isfolder(settingsFolder) then
			makefolder(settingsFolder)
		end

		-- สร้างอีกชั้นเพื่อความยืดหยุ่น (optional)
		local placeSettingsFolder = placeFolder .. "/settings"
		if not isfolder(placeSettingsFolder) then
			makefolder(placeSettingsFolder)
		end
    end

    function InterfaceManager:SetFolder(folder)
		-- รับค่า root folder ใหม่ (string)
		self.FolderRoot = tostring(folder or "FluentSettings")
		self:BuildFolderTree()
	end

    function InterfaceManager:SetLibrary(library)
		self.Library = library
	end

	-- ได้ path สำหรับไฟล์ config ของแมพปัจจุบัน
	local function getConfigFilePath(self)
		local root = self.FolderRoot
		local placeId = getPlaceId()
		local mapName = getMapName()
		-- รูปแบบ: <root>/<placeId>/<mapName>.json
		return root .. "/" .. placeId .. "/" .. mapName .. ".json"
	end

    function InterfaceManager:SaveSettings()
		local path = getConfigFilePath(self)
		-- ensure folder (in caseไม่ถูกสร้าง)
		local folder = path:match("^(.*)/[^/]+$")
		if folder then
			ensureFolder(folder)
		end

        local encoded = httpService:JSONEncode(self.Settings or {})
        writefile(path, encoded)
    end

    function InterfaceManager:LoadSettings()
        -- โหลดไฟล์ config ของแมพปัจจุบัน (ถ้ามี)
        local path = getConfigFilePath(self)

		-- legacy path (เดิมเป็น <FolderRoot>/options.json) — ถ้าเจอ เราจะ migrate ให้เป็น per-map file
		local legacyPath = self.FolderRoot .. "/options.json"

        if isfile(path) then
            local data = readfile(path)
            local success, decoded = pcall(httpService.JSONDecode, httpService, data)
            if success and type(decoded) == "table" then
                for i, v in next, decoded do
                    self.Settings[i] = v
                end
            end
			return
        end

		-- ถ้าไม่มี per-map file แต่มี legacy file ให้ migrate (คัดลอก)
		if isfile(legacyPath) then
			local data = readfile(legacyPath)
			local success, decoded = pcall(httpService.JSONDecode, httpService, data)
			if success and type(decoded) == "table" then
				-- นำค่า legacy มา merge แล้วบันทึกใหม่ใน path ใหม่
				for i,v in next, decoded do
					self.Settings[i] = v
				end
				-- ensure folder
				local folder = path:match("^(.*)/[^/]+$")
				if folder then ensureFolder(folder) end
				local encoded = httpService:JSONEncode(self.Settings or {})
				writefile(path, encoded)
			end
			return
		end

		-- ถ้าไม่มีไฟล์ใดๆ ให้ใช้ค่า default ที่มีอยู่แล้ว (ไม่ทำอะไร)
    end

    function InterfaceManager:BuildInterfaceSection(tab)
        assert(self.Library, "Must set InterfaceManager.Library")
		local Library = self.Library
        local Settings = InterfaceManager.Settings

        -- โหลดค่า config ของแมพนี้ก่อนแสดง UI
        InterfaceManager:LoadSettings()

		local section = tab:AddSection("Interface")

		local InterfaceTheme = section:AddDropdown("InterfaceTheme", {
			Title = "Theme",
			Description = "Changes the interface theme.",
			Values = Library.Themes,
			Default = Settings.Theme,
			Callback = function(Value)
				Library:SetTheme(Value)
                Settings.Theme = Value
                InterfaceManager:SaveSettings()
			end
		})

        InterfaceTheme:SetValue(Settings.Theme)
	
		if Library.UseAcrylic then
			section:AddToggle("AcrylicToggle", {
				Title = "Acrylic",
				Description = "The blurred background requires graphic quality 8+",
				Default = Settings.Acrylic,
				Callback = function(Value)
					Library:ToggleAcrylic(Value)
                    Settings.Acrylic = Value
                    InterfaceManager:SaveSettings()
				end
			})
		end
	
		section:AddToggle("TransparentToggle", {
			Title = "Transparency",
			Description = "Makes the interface transparent.",
			Default = Settings.Transparency,
			Callback = function(Value)
				Library:ToggleTransparency(Value)
				Settings.Transparency = Value
                InterfaceManager:SaveSettings()
			end
		})
	
		local MenuKeybind = section:AddKeybind("MenuKeybind", { Title = "Minimize Bind", Default = Settings.MenuKeybind })
		MenuKeybind:OnChanged(function()
			Settings.MenuKeybind = MenuKeybind.Value
            InterfaceManager:SaveSettings()
		end)
		Library.MinimizeKeybind = MenuKeybind
    end
end

return InterfaceManager
