local httpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local InterfaceManager = {} do
	-- root folder ใหม่ (จะสร้างใหม่เลย ไม่คัดลอกจากที่เก่า)
	InterfaceManager.FolderRoot = "ATGHubSettings"

	-- default settings
    InterfaceManager.Settings = {
        Theme = "Dark",
        Acrylic = true,
        Transparency = true,
        MenuKeybind = "LeftControl"
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
		local success, id = pcall(function() return tostring(game.PlaceId) end)
		if success and id then return id end
		return "UnknownPlace"
	end

	local function getMapName()
		local ok, map = pcall(function() return Workspace:FindFirstChild("Map") end)
		if ok and map and map.IsA and map:IsA("Instance") then
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

	-- สร้างโฟลเดอร์โครงสร้างใหม่แบบสะอาด (ไม่ migrate/copy ของเก่า)
    function InterfaceManager:BuildFolderTree()
		local root = self.FolderRoot
		ensureFolder(root)

		local placeId = getPlaceId()
		local placeFolder = root .. "/" .. placeId
		ensureFolder(placeFolder)

		-- settings (global & per-place)
		ensureFolder(root .. "/settings")
		ensureFolder(placeFolder .. "/settings")

		-- themes (global & per-place)
		ensureFolder(root .. "/Themes")
		ensureFolder(placeFolder .. "/Themes")

		-- imports
		ensureFolder(root .. "/Imports")
    end

    function InterfaceManager:SetFolder(folder)
		self.FolderRoot = tostring(folder or "ATGHubSettings")
		self:BuildFolderTree()
	end

    function InterfaceManager:SetLibrary(library)
		self.Library = library
		-- on set, try to register themes from disk
		self:RegisterThemesToLibrary(library)
	end

	-- prefixed filename for settings -> "ATG Hub - <placeId> - <mapName>.json"
	local function getPrefixedSettingsFilename()
		local placeId = getPlaceId()
		local mapName = getMapName()
		local fname = "ATG Hub - " .. sanitizeFilename(placeId) .. " - " .. sanitizeFilename(mapName) .. ".json"
		return fname
	end

	local function getConfigFilePath(self)
		local root = self.FolderRoot
		local placeId = getPlaceId()
		local configFolder = root .. "/" .. placeId
		ensureFolder(configFolder)
		local fname = getPrefixedSettingsFilename()
		return configFolder .. "/" .. fname
	end

    function InterfaceManager:SaveSettings()
		local path = getConfigFilePath(self)
		local folder = path:match("^(.*)/[^/]+$")
		if folder then ensureFolder(folder) end
        local encoded = httpService:JSONEncode(self.Settings or {})
        writefile(path, encoded)
    end

    function InterfaceManager:LoadSettings()
        local path = getConfigFilePath(self)
        local legacyPath = self.FolderRoot .. "/options.json"

        if isfile(path) then
            local data = readfile(path)
            local success, decoded = pcall(httpService.JSONDecode, httpService, data)
            if success and type(decoded) == "table" then
                for i, v in next, decoded do self.Settings[i] = v end
            end
			return
        end

		-- ถ้าเจอ legacy options.json ให้ย้ายค่า (merge) แต่ไม่คัดลอกทุกไฟล์โฟลเดอร์
		if isfile(legacyPath) then
			local data = readfile(legacyPath)
			local success, decoded = pcall(httpService.JSONDecode, httpService, data)
			if success and type(decoded) == "table" then
				for i,v in next, decoded do self.Settings[i] = v end
				-- save to new per-place path
				local folder = path:match("^(.*)/[^/]+$")
				if folder then ensureFolder(folder) end
				local encoded = httpService:JSONEncode(self.Settings or {})
				writefile(path, encoded)
			end
			return
		end

		-- ถ้าไม่มีไฟล์ใดๆ ให้คง default
    end

	-- ================= Theme utilities =================

	-- scan Themes folders and return list of { name, path, ext }
	function InterfaceManager:ScanThemes()
		local themes = {}
		local root = self.FolderRoot
		local themePaths = {
			root .. "/Themes",
			root .. "/" .. getPlaceId() .. "/Themes"
		}
		for _, folder in ipairs(themePaths) do
			if isfolder(folder) and type(listfiles) == "function" then
				local ok, files = pcall(listfiles, folder)
				if ok and type(files) == "table" then
					for _, fpath in ipairs(files) do
						if fpath:match("%.lua$") or fpath:match("%.json$") then
							local base = fpath:match("([^/\\]+)$") or fpath
							local display = base
							display = display:gsub("^ATG Hub %- ", "")
							display = display:gsub("%.lua$", ""):gsub("%.json$", "")
							display = display:gsub("%_", " ")
							local ext = fpath:match("%.([a-zA-Z0-9]+)$")
							table.insert(themes, { name = display, path = fpath, ext = ext })
						end
					end
				end
			end
		end
		return themes
	end

	-- import theme content into global Themes (creates ATG Hub - <name>.<ext>)
	function InterfaceManager:ImportTheme(name, content, ext)
		ext = tostring(ext or "lua"):lower()
		if ext ~= "lua" and ext ~= "json" then ext = "lua" end
		local rootThemes = self.FolderRoot .. "/Themes"
		ensureFolder(rootThemes)
		local safe = sanitizeFilename(name)
		local fname = "ATG Hub - " .. safe .. "." .. ext
		local full = rootThemes .. "/" .. fname
		writefile(full, tostring(content or ""))
		-- immediately register so it shows up
		if self.Library then
			self:TryRegisterThemeFile(full, ext)
		end
		return full
	end

	-- try to parse theme file (lua/json) and register/merge into library
	function InterfaceManager:TryRegisterThemeFile(fullpath, ext)
		if not isfile(fullpath) then return false, "file not found" end
		local raw = readfile(fullpath)
		local themeTbl = nil
		if ext == "json" then
			local ok, dec = pcall(httpService.JSONDecode, httpService, raw)
			if ok and type(dec) == "table" then themeTbl = dec end
		else -- lua
			local ok, chunk = pcall(loadstring, raw)
			if ok and type(chunk) == "function" then
				local ok2, result = pcall(chunk)
				if ok2 and type(result) == "table" then themeTbl = result end
			end
		end

		if themeTbl and self.Library then
			local displayName = fullpath:match("([^/\\]+)$") or fullpath
			displayName = displayName:gsub("^ATG Hub %- ", ""):gsub("%.lua$",""):gsub("%.json$",""):gsub("%_"," ")
			-- prefer RegisterTheme API
			if type(self.Library.RegisterTheme) == "function" then
				pcall(function() self.Library:RegisterTheme(displayName, themeTbl) end)
				return true, "registered"
			end
			-- fallback: merge into table-style Library.Themes
			local lt = self.Library.Themes
			if type(lt) == "table" then
				-- detect map vs array
				local isMap = false
				for k,v in pairs(lt) do
					if type(k) ~= "number" then isMap = true break end
				end
				if isMap then
					self.Library.Themes[displayName] = themeTbl
					return true, "merged into map"
				else
					local exists = false
					for _,v in ipairs(lt) do if v == displayName then exists = true break end end
					if not exists then table.insert(self.Library.Themes, displayName) end
					self.Library.DynamicImportedThemes = self.Library.DynamicImportedThemes or {}
					self.Library.DynamicImportedThemes[displayName] = themeTbl
					return true, "added name + dynamic table"
				end
			end
		end

		return false, "could not parse or no library"
	end

	-- register all themes found on disk to Library (best-effort)
	function InterfaceManager:RegisterThemesToLibrary(library)
		if not library then return end
		local found = self:ScanThemes()
		for _, item in ipairs(found) do
			pcall(function()
				self:TryRegisterThemeFile(item.path, item.ext)
			end)
		end
	end

	-- build merged theme-name list (library + disk + dynamic imports)
	local function getLibraryThemeNames(library)
		local names = {}
		if not library then return {} end

		-- library built-in
		if type(library.Themes) == "table" then
			local numeric = true
			for k,v in pairs(library.Themes) do
				if type(k) ~= "number" then numeric = false break end
			end
			if numeric then
				for _,v in ipairs(library.Themes) do if type(v)=="string" then names[v]=true end end
			else
				for k,v in pairs(library.Themes) do if type(k)=="string" then names[k]=true end end
			end
		end

		-- dynamic imports
		if library.DynamicImportedThemes then
			for k,v in pairs(library.DynamicImportedThemes) do names[k]=true end
		end

		-- disk themes
		local disk = InterfaceManager:ScanThemes()
		for _, item in ipairs(disk) do names[item.name] = true end

		local out = {}
		for k,_ in pairs(names) do table.insert(out, k) end
		table.sort(out)
		return out
	end

    function InterfaceManager:BuildInterfaceSection(tab)
        assert(self.Library, "Must set InterfaceManager.Library")
		local Library = self.Library
        local Settings = InterfaceManager.Settings

        -- ensure folders exist & load config of this map before UI
		InterfaceManager:BuildFolderTree()
        InterfaceManager:LoadSettings()
		-- register disk themes now so Library gets them (best-effort)
		InterfaceManager:RegisterThemesToLibrary(Library)

		local section = tab:AddSection("Interface")

		-- merged name list
		local mergedValues = getLibraryThemeNames(Library)

		local InterfaceTheme = section:AddDropdown("InterfaceTheme", {
			Title = "Theme",
			Description = "Changes the interface theme.",
			Values = mergedValues,
			Default = Settings.Theme,
			Callback = function(Value)
				-- try library API first
				if type(Library.SetTheme) == "function" then
					pcall(function() Library:SetTheme(Value) end)
				else
					-- if theme was imported dynamically, try register+set
					if Library.DynamicImportedThemes and Library.DynamicImportedThemes[Value] then
						if type(Library.RegisterTheme) == "function" then
							pcall(function() Library:RegisterTheme(Value, Library.DynamicImportedThemes[Value]) end)
							pcall(function() Library:SetTheme(Value) end)
						end
					end
				end
                Settings.Theme = Value
                InterfaceManager:SaveSettings()
			end
		})

        InterfaceTheme:SetValue(Settings.Theme)

		-- add Refresh button to re-scan Themes folder (useful after dropping files manually)
		if section.AddButton then
			section:AddButton({
				Title = "Refresh Themes",
				Description = "Scan ATGHubSettings/Themes and update dropdown (use after adding files).",
				Callback = function()
					-- re-scan and re-register
					local newList = getLibraryThemeNames(Library)
					-- try to update dropdown values (best-effort — depends on dropdown API)
					if InterfaceTheme.SetValues then
						pcall(function() InterfaceTheme:SetValues(newList) end)
					elseif InterfaceTheme.SetOptions then
						pcall(function() InterfaceTheme:SetOptions(newList) end)
					elseif InterfaceTheme.UpdateValues then
						pcall(function() InterfaceTheme:UpdateValues(newList) end)
					else
						-- fallback: notify in console (UI may require re-open)
						print("[InterfaceManager] Refreshed themes (re-open menu if dropdown didn't update).")
					end
					-- also attempt to register any new files to library
					InterfaceManager:RegisterThemesToLibrary(Library)
				end
			})
		end

		-- acrylic toggle
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
				if type(Library.ToggleTransparency) == "function" then
					Library:ToggleTransparency(Value)
				end
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
