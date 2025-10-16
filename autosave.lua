-- SaveManager (ปรับปรุง: โครงสร้างไฟล์เรียบง่ายขึ้น, เพิ่ม Description(ไทย) + Title(อังกฤษ) ให้ UI)
local Toggle = Tabs.Main:AddToggle("MyToggle", { Title = "Toggle", Description = "สวิตช์เปิด/ปิดการทำงาน", Default = false })

Toggle:OnChanged(function()
    print("Toggle changed:", Options.MyToggle.Value)
end)

Options.MyToggle:SetValue(false)

local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local SaveManager = {} do
	-- root folder (can be changed via SetFolder)
	-- ค่าเริ่มต้นเก็บไว้เป็น ATGSettings ตามที่เดิม
	SaveManager.FolderRoot = "ATGSettings"
	SaveManager.Ignore = {}
	SaveManager.Options = {}
	SaveManager.Library = nil

	-- Parser สำหรับ option ต่าง ๆ (ไม่เปลี่ยน)
	SaveManager.Parser = {
		Toggle = {
			Save = function(idx, object) 
				return { type = "Toggle", idx = idx, value = object.Value } 
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then 
					SaveManager.Options[idx]:SetValue(data.value)
				end
			end,
		},
		Slider = {
			Save = function(idx, object)
				return { type = "Slider", idx = idx, value = tostring(object.Value) }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then 
					SaveManager.Options[idx]:SetValue(data.value)
				end
			end,
		},
		Dropdown = {
			Save = function(idx, object)
				return { type = "Dropdown", idx = idx, value = object.Value, mutli = object.Multi }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then 
					SaveManager.Options[idx]:SetValue(data.value)
				end
			end,
		},
		Colorpicker = {
			Save = function(idx, object)
				return { type = "Colorpicker", idx = idx, value = object.Value:ToHex(), transparency = object.Transparency }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then 
					SaveManager.Options[idx]:SetValueRGB(Color3.fromHex(data.value), data.transparency)
				end
			end,
		},
		Keybind = {
			Save = function(idx, object)
				return { type = "Keybind", idx = idx, mode = object.Mode, key = object.Value }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then 
					SaveManager.Options[idx]:SetValue(data.key, data.mode)
				end
			end,
		},
		Input = {
			Save = function(idx, object)
				return { type = "Input", idx = idx, text = object.Value }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] and type(data.text) == "string" then
					SaveManager.Options[idx]:SetValue(data.text)
				end
			end,
		},
	}

	-- helpers
	local function sanitizeFilename(name)
		name = tostring(name or "")
		name = name:gsub("%s+", "_")
		name = name:gsub("[^%w%-%_]", "")
		if name == "" then return "Unknown" end
		return name
	end

	local function getPlaceId()
		local ok, id = pcall(function() return tostring(game.PlaceId) end)
		if ok and id then return id end
		return "UnknownPlace"
	end

	local function getMapName()
		local ok, map = pcall(function() return Workspace:FindFirstChild("Map") end)
		if ok and map and map:IsA("Instance") then
			return sanitizeFilename(map.Name)
		end
		local ok2, wname = pcall(function() return Workspace.Name end)
		if ok2 and wname then return sanitizeFilename(wname) end
		return "UnknownMap"
	end

	local function ensureFolder(path)
		if not isfolder(path) then
			makefolder(path)
		end
	end

	-- ปรับโครงสร้างเป็น Root/<PlaceId>_<MapName>/settings เพื่อไม่ต้องสร้างชั้นลึกมาก
	local function getConfigsFolder(self)
		local root = tostring(self.FolderRoot or "ATGSettings")
		local placeId = getPlaceId()
		local mapName = getMapName()
		local folderName = sanitizeFilename(placeId .. "_" .. mapName)
		return root .. "/" .. folderName .. "/settings"
	end

	local function getConfigFilePath(self, name)
		local folder = getConfigsFolder(self)
		return folder .. "/" .. sanitizeFilename(name) .. ".json"
	end

	-- Build folder tree and migrate legacy configs if found (copy only)
	function SaveManager:BuildFolderTree()
		local root = tostring(self.FolderRoot or "ATGSettings")
		ensureFolder(root)

		-- สร้างเฉพาะโฟลเดอร์ที่จำเป็น: โฟลเดอร์ของการตั้งค่าสำหรับ place+map
		local configsFolder = getConfigsFolder(self)
		ensureFolder(configsFolder)

		-- legacy folder migration: <root>/settings (old layout)
		local legacySettingsFolder = root .. "/settings"
		if isfolder(legacySettingsFolder) then
			local files = listfiles(legacySettingsFolder)
			for i = 1, #files do
				local f = files[i]
				if f:sub(-5) == ".json" then
					local base = f:match("([^/\\]+)%.json$")
					if base and base ~= "options" then
						local dest = configsFolder .. "/" .. base .. ".json"
						-- copy only if destination does not exist yet
						if not isfile(dest) then
							local ok, data = pcall(readfile, f)
							if ok and data then
								pcall(writefile, dest, data)
							end
						end
					end
				end
			end

			-- migrate autoload.txt if present (copy only)
			local autopath = legacySettingsFolder .. "/autoload.txt"
			if isfile(autopath) then
				local autodata = readfile(autopath)
				local destAuto = configsFolder .. "/autoload.txt"
				if not isfile(destAuto) then
					pcall(writefile, destAuto, autodata)
				end
			end
		end
	end

	function SaveManager:SetIgnoreIndexes(list)
		for _, key in next, list do
			self.Ignore[key] = true
		end
	end

	function SaveManager:SetFolder(folder)
		self.FolderRoot = tostring(folder or "ATGSettings")
		self:BuildFolderTree()
	end

	function SaveManager:SetLibrary(library)
		self.Library = library
		self.Options = library.Options
	end

	function SaveManager:Save(name)
		if (not name) then
			return false, "no config file is selected"
		end

		local fullPath = getConfigFilePath(self, name)

		local data = { objects = {} }

		for idx, option in next, SaveManager.Options do
			if not self.Parser[option.Type] then continue end
			if self.Ignore[idx] then continue end

			table.insert(data.objects, self.Parser[option.Type].Save(idx, option))
		end

		local success, encoded = pcall(HttpService.JSONEncode, HttpService, data)
		if not success then
			return false, "failed to encode data"
		end

		-- ensure folder exists
		local folder = fullPath:match("^(.*)/[^/]+$")
		if folder then ensureFolder(folder) end

		local ok, err = pcall(function() writefile(fullPath, encoded) end)
		if not ok then
			return false, "failed to write file: " .. tostring(err)
		end

		return true
	end

	function SaveManager:Load(name)
		if (not name) then
			return false, "no config file is selected"
		end

		local file = getConfigFilePath(self, name)
		if not isfile(file) then return false, "invalid file" end

		local success, decoded = pcall(HttpService.JSONDecode, HttpService, readfile(file))
		if not success then return false, "decode error" end

		for _, option in next, decoded.objects do
			if self.Parser[option.type] then
				task.spawn(function() self.Parser[option.type].Load(option.idx, option) end)
			end
		end

		return true
	end

	function SaveManager:IgnoreThemeSettings()
		self:SetIgnoreIndexes({
			"InterfaceTheme", "AcrylicToggle", "TransparentToggle", "MenuKeybind"
		})
	end

	function SaveManager:RefreshConfigList()
		local folder = getConfigsFolder(self)
		if not isfolder(folder) then
			return {}
		end
		local list = listfiles(folder)
		local out = {}
		for i = 1, #list do
			local file = list[i]
			if file:sub(-5) == ".json" then
				local name = file:match("([^/\\]+)%.json$")
				if name and name ~= "options" then
					table.insert(out, name)
				end
			end
		end
		return out
	end

	function SaveManager:LoadAutoloadConfig()
		local autopath = getConfigsFolder(self) .. "/autoload.txt"
		if isfile(autopath) then
			local name = readfile(autopath)
			local success, err = self:Load(name)
			if not success then
				if self.Library and self.Library.Notify then
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = "Failed to load autoload config: " .. err,
						Duration = 7
					})
				end
			end

			if self.Library and self.Library.Notify then
				self.Library:Notify({
					Title = "Interface",
					Content = "Config loader",
					SubContent = string.format("Auto loaded config %q", name),
					Duration = 7
				})
			end
		end
	end

	-- UI: สร้าง section สำหรับจัดการ config (เติม Description ภาษาไทย + Title ภาษาอังกฤษ)
	function SaveManager:BuildConfigSection(tab)
		assert(self.Library, "Must set SaveManager.Library")

		local section = tab:AddSection("Configuration")

		section:AddInput("SaveManager_ConfigName",    { Title = "Config name", Description = "ชื่อไฟล์คอนฟิก (ไม่ต้องใส่นามสกุล .json)" })
		section:AddDropdown("SaveManager_ConfigList", { Title = "Config list", Values = self:RefreshConfigList(), AllowNull = true, Description = "รายการไฟล์คอนฟิกที่มีอยู่" })

		section:AddButton({
			Title = "Create config",
			Description = "สร้างไฟล์คอนฟิกใหม่จากค่าปัจจุบัน",
			Callback = function()
				local name = SaveManager.Options.SaveManager_ConfigName.Value

				if not name or name:gsub(" ", "") == "" then
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = "Invalid config name (empty)",
						Duration = 7
					})
				end

				local success, err = self:Save(name)
				if not success then
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = "Failed to save config: " .. err,
						Duration = 7
					})
				end

				self.Library:Notify({
					Title = "Interface",
					Content = "Config loader",
					SubContent = string.format("Created config %q", name),
					Duration = 7
				})

				SaveManager.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
				SaveManager.Options.SaveManager_ConfigList:SetValue(nil)
			end
		})

		section:AddButton({
			Title = "Load config",
			Description = "โหลดค่าจากไฟล์คอนฟิกที่เลือก",
			Callback = function()
				local name = SaveManager.Options.SaveManager_ConfigList.Value

				local success, err = self:Load(name)
				if not success then
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = "Failed to load config: " .. err,
						Duration = 7
					})
				end

				self.Library:Notify({
					Title = "Interface",
					Content = "Config loader",
					SubContent = string.format("Loaded config %q", name),
					Duration = 7
				})
			end
		})

		section:AddButton({
			Title = "Overwrite config",
			Description = "บันทึกทับไฟล์คอนฟิกที่เลือก",
			Callback = function()
				local name = SaveManager.Options.SaveManager_ConfigList.Value

				local success, err = self:Save(name)
				if not success then
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = "Failed to overwrite config: " .. err,
						Duration = 7
					})
				end

				self.Library:Notify({
					Title = "Interface",
					Content = "Config loader",
					SubContent = string.format("Overwrote config %q", name),
					Duration = 7
				})
			end
		})

		section:AddButton({
			Title = "Refresh list",
			Description = "อัปเดตรายการไฟล์คอนฟิก",
			Callback = function()
				SaveManager.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
				SaveManager.Options.SaveManager_ConfigList:SetValue(nil)
			end
		})

		local AutoloadButton
		AutoloadButton = section:AddButton({
			Title = "Set as autoload",
			Description = "ตั้งไฟล์ที่เลือกให้โหลดอัตโนมัติเมื่อเริ่ม",
			Callback = function()
				local name = SaveManager.Options.SaveManager_ConfigList.Value
				local autopath = getConfigsFolder(self) .. "/autoload.txt"
				writefile(autopath, tostring(name or ""))
				AutoloadButton:SetDesc("Current autoload config: " .. tostring(name or "none"))
				self.Library:Notify({
					Title = "Interface",
					Content = "Config loader",
					SubContent = string.format("Set %q to auto load", name),
					Duration = 7
				})
			end
		})

		-- populate current autoload desc if exists
		local autop = getConfigsFolder(self) .. "/autoload.txt"
		if isfile(autop) then
			local name = readfile(autop)
			AutoloadButton:SetDesc("Current autoload config: " .. name)
		else
			AutoloadButton:SetDesc("Current autoload config: none")
		end

		SaveManager:SetIgnoreIndexes({ "SaveManager_ConfigList", "SaveManager_ConfigName" })
	end

	-- initial build: สร้างโฟลเดอร์ที่จำเป็น (เรียบง่าย)
	SaveManager:BuildFolderTree()
end

return SaveManager
