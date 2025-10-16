local httpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local InterfaceManager = {} do
	-- root folder (single clean folder)
	InterfaceManager.FolderRoot = "ATGHubSettings"

	-- default settings
    InterfaceManager.Settings = {
        Theme = "Dark",
        Acrylic = true,
        Transparency = true,
        MenuKeybind = "LeftControl"
    }

	-- internal index: map displayName -> { path, ext }
	InterfaceManager.DiskThemeIndex = {}

	-- helpers
	local function sanitizeFilename(name)
		name = tostring(name or "")
		name = name:gsub("%s+", "_")
		name = name:gsub("[^%w%-%_]", "")
		if name == "" then return "Unknown" end
		return name
	end

	local function getMapFolderName()
		-- ใช้ชื่อของ object "Map" ใน Workspace ถ้ามี
		local ok, map = pcall(function() return Workspace:FindFirstChild("Map") end)
		if ok and map and map:IsA and map:IsA("Instance") then
			return sanitizeFilename(map.Name)
		end
		-- fallback: ใช้ Workspace.Name
		local ok2, wname = pcall(function() return Workspace.Name end)
		if ok2 and wname then return sanitizeFilename(wname) end
		return "UnknownMap"
	end

	local function ensureFolder(path)
		if not isfolder(path) then
			makefolder(path)
		end
	end

	-- build folder tree (clean create, no migration)
    function InterfaceManager:BuildFolderTree()
		local root = self.FolderRoot
		ensureFolder(root)

		local mapFolder = root .. "/" .. getMapFolderName()
		ensureFolder(mapFolder)

		ensureFolder(root .. "/settings")           -- global settings
		ensureFolder(mapFolder .. "/settings")     -- per-map settings

		ensureFolder(root .. "/Themes")            -- global themes
		ensureFolder(mapFolder .. "/Themes")       -- per-map themes (optional)

		ensureFolder(root .. "/Imports")           -- manual import drop
    end

    function InterfaceManager:SetFolder(folder)
		self.FolderRoot = tostring(folder or "ATGHubSettings")
		self:BuildFolderTree()
	end

    function InterfaceManager:SetLibrary(library)
		self.Library = library
		-- register themes found on disk to library (best-effort)
		self:RegisterThemesToLibrary(library)
	end

	-- prefixed filename for per-map settings: ATG Hub - <mapName>.json
	local function getPrefixedSettingsFilename()
		local mapName = getMapFolderName()
		local fname = "ATG Hub - " .. sanitizeFilename(mapName) .. ".json"
		return fname
	end

	local function getConfigFilePath(self)
		local root = self.FolderRoot
		local mapFolder = root .. "/" .. getMapFolderName()
		ensureFolder(mapFolder)
		local fname = getPrefixedSettingsFilename()
		return mapFolder .. "/" .. fname
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
		local legacyPath = self.FolderRoot .. "/options.json" -- keep merge if exists

        if isfile(path) then
            local data = readfile(path)
            local success, decoded = pcall(httpService.JSONDecode, httpService, data)
            if success and type(decoded) == "table" then
                for i, v in next, decoded do self.Settings[i] = v end
            end
			return
        end

		if isfile(legacyPath) then
			local data = readfile(legacyPath)
			local success, decoded = pcall(httpService.JSONDecode, httpService, data)
			if success and type(decoded) == "table" then
				for i,v in next, decoded do self.Settings[i] = v end
				-- save to new per-map path
				local folder = path:match("^(.*)/[^/]+$")
				if folder then ensureFolder(folder) end
				local encoded = httpService:JSONEncode(self.Settings or {})
				writefile(path, encoded)
			end
			return
		end
		-- otherwise keep defaults
    end

	-- ================= Theme utilities =================

	-- scan Themes folders and update DiskThemeIndex
	function InterfaceManager:ScanThemes()
		self.DiskThemeIndex = {}
		local root = self.FolderRoot
		local themePaths = {
			root .. "/Themes",
			root .. "/" .. getMapFolderName() .. "/Themes"
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
							self.DiskThemeIndex[display] = { path = fpath, ext = ext }
						end
					end
				end
			end
		end
		-- return list of display names
		local out = {}
		for name,_ in pairs(self.DiskThemeIndex) do table.insert(out, name) end
		table.sort(out)
		return out
	end

	-- import theme content into global Themes folder
	function InterfaceManager:ImportTheme(name, content, ext)
		ext = tostring(ext or "lua"):lower()
		if ext ~= "lua" and ext ~= "json" then ext = "lua" end
		local rootThemes = self.FolderRoot .. "/Themes"
		ensureFolder(rootThemes)
		local safe = sanitizeFilename(name)
		local fname = "ATG Hub - " .. safe .. "." .. ext
		local full = rootThemes .. "/" .. fname
		writefile(full, tostring(content or ""))
		-- update index
		self:ScanThemes()
		-- attempt to register immediately
		if self.Library then self:TryRegisterThemeFile(full, ext) end
		return full
	end

	-- parse a theme file (return table or nil + err)
	function InterfaceManager:ParseThemeFile(fullpath, ext)
		if not isfile(fullpath) then return nil, "file not found" end
		local raw = readfile(fullpath)
		if ext == "json" then
			local ok, dec = pcall(httpService.JSONDecode, httpService, raw)
			if ok and type(dec) == "table" then return dec end
			return nil, "json decode failed"
		end
		-- lua
		local ok, chunk = pcall(loadstring, raw)
		if not ok or type(chunk) ~= "function" then
			return nil, "lua load failed"
		end
		local ok2, result = pcall(chunk)
		if ok2 and type(result) == "table" then
			return result
		end
		-- maybe module used globals/tasks and returned nothing; try to run with 'return ' prefix
		local ok3, chunk2 = pcall(loadstring, "return " .. raw)
		if ok3 and type(chunk2) == "function" then
			local ok4, res2 = pcall(chunk2)
			if ok4 and type(res2) == "table" then return res2 end
		end
		return nil, "no table returned"
	end

	-- try to register theme file to library (and keep dynamic table)
	function InterfaceManager:TryRegisterThemeFile(fullpath, ext)
		local ok, themeTbl = pcall(function() return self:ParseThemeFile(fullpath, ext) end)
		if not ok or type(themeTbl) ~= "table" then return false, "parse failed" end

		if not self.Library then
			-- just store to dynamic store so dropdown can use it later
			self.Library = self.Library or {}
			self.Library.DynamicImportedThemes = self.Library.DynamicImportedThemes or {}
			local displayName = fullpath:match("([^/\\]+)$") or fullpath
			displayName = displayName:gsub("^ATG Hub %- ", ""):gsub("%.lua$",""):gsub("%.json$",""):gsub("%_"," ")
			self.Library.DynamicImportedThemes[displayName] = themeTbl
			return true, "stored dynamic (no library)"
		end

		-- prefer RegisterTheme API
		local displayName = fullpath:match("([^/\\]+)$") or fullpath
		displayName = displayName:gsub("^ATG Hub %- ", ""):gsub("%.lua$",""):gsub("%.json$",""):gsub("%_"," ")
		if type(self.Library.RegisterTheme) == "function" then
			pcall(function() self.Library:RegisterTheme(displayName, themeTbl) end)
			-- also store dynamic copy
			self.Library.DynamicImportedThemes = self.Library.DynamicImportedThemes or {}
			self.Library.DynamicImportedThemes[displayName] = themeTbl
			return true, "registered"
		end

		-- fallback: if Library.Themes is a map, merge as table
		local lt = self.Library.Themes
		if type(lt) == "table" then
			-- detect map vs array
			local isMap = false
			for k,v in pairs(lt) do if type(k) ~= "number" then isMap = true break end end
			if isMap then
				self.Library.Themes[displayName] = themeTbl
				self.Library.DynamicImportedThemes = self.Library.DynamicImportedThemes or {}
				self.Library.DynamicImportedThemes[displayName] = themeTbl
				return true, "merged into map"
			else
				-- append name to array and save theme table in DynamicImportedThemes
				local exists = false
				for _,v in ipairs(lt) do if v == displayName then exists = true break end end
				if not exists then table.insert(self.Library.Themes, displayName) end
				self.Library.DynamicImportedThemes = self.Library.DynamicImportedThemes or {}
				self.Library.DynamicImportedThemes[displayName] = themeTbl
				return true, "added name + dynamic table"
			end
		end

		return false, "could not merge into library"
	end

	-- register all disk themes to library / dynamic store
	function InterfaceManager:RegisterThemesToLibrary(library)
		if not library and not self.Library then return end
		self:ScanThemes()
		for name,info in pairs(self.DiskThemeIndex) do
			pcall(function()
				self:TryRegisterThemeFile(info.path, info.ext)
			end)
		end
	end

	-- load theme table by display name (search library dynamic, library map, disk)
	function InterfaceManager:LoadThemeTableByName(name)
		if not name then return nil, "no name" end
		-- check dynamic store
		if self.Library and self.Library.DynamicImportedThemes and self.Library.DynamicImportedThemes[name] then
			return self.Library.DynamicImportedThemes[name]
		end
		-- check library.Themes if it's map style
		if self.Library and type(self.Library.Themes) == "table" then
			-- map style?
			local isMap = false
			for k,_ in pairs(self.Library.Themes) do if type(k) ~= "number" then isMap = true break end end
			if isMap and self.Library.Themes[name] and type(self.Library.Themes[name]) == "table" then
				return self.Library.Themes[name]
			end
		end
		-- check disk
		if self.DiskThemeIndex[name] then
			local info = self.DiskThemeIndex[name]
			local ok, tbl = pcall(function() return self:ParseThemeFile(info.path, info.ext) end)
			if ok and type(tbl) == "table" then
				-- store into dynamic for later
				self.Library = self.Library or {}
				self.Library.DynamicImportedThemes = self.Library.DynamicImportedThemes or {}
				self.Library.DynamicImportedThemes[name] = tbl
				return tbl
			end
		end
		return nil, "not found"
	end

	-- APPLY theme by name (best-effort)
	function InterfaceManager:ApplyTheme(name)
		if not name then return false, "no name" end

		-- try library SetTheme directly (preferred)
		if self.Library and type(self.Library.SetTheme) == "function" then
			local ok, err = pcall(function() self.Library:SetTheme(name) end)
			if ok then return true, "SetTheme called" end
		end

		-- otherwise try to get theme table and apply via other APIs
		local tbl, err = self:LoadThemeTableByName(name)
		if not tbl then return false, "load failed: "..tostring(err) end

		-- if library supports RegisterTheme + SetTheme, register then set
		if self.Library and type(self.Library.RegisterTheme) == "function" and type(self.Library.SetTheme) == "function" then
			pcall(function() self.Library:RegisterTheme(name, tbl) end)
			pcall(function() self.Library:SetTheme(name) end)
			return true, "registered+set"
		end

		-- if library supports ApplyThemeFromTable or similar, try that
		if self.Library and type(self.Library.ApplyThemeFromTable) == "function" then
			pcall(function() self.Library:ApplyThemeFromTable(tbl) end)
			return true, "applied via ApplyThemeFromTable"
		end

		-- fallback: try to insert into Library.Themes map and attempt SetTheme
		if self.Library then
			if type(self.Library.Themes) ~= "table" then
				self.Library.Themes = {}
			end
			-- if map, set
			local isMap = false
			for k,_ in pairs(self.Library.Themes) do if type(k) ~= "number" then isMap = true break end end
			if isMap then
				self.Library.Themes[name] = tbl
				if type(self.Library.SetTheme) == "function" then pcall(function() self.Library:SetTheme(name) end) end
				return true, "merged into Library.Themes map"
			else
				-- array-style library: append name and store dynamic table
				local exists = false
				for _,v in ipairs(self.Library.Themes) do if v == name then exists = true break end end
				if not exists then table.insert(self.Library.Themes, name) end
				self.Library.DynamicImportedThemes = self.Library.DynamicImportedThemes or {}
				self.Library.DynamicImportedThemes[name] = tbl
				if type(self.Library.SetTheme) == "function" then pcall(function() self.Library:SetTheme(name) end) end
				return true, "added name + dynamic table"
			end
		end

		return false, "no library to apply"
	end

	-- helper to produce merged dropdown-friendly theme name list
	local function getMergedThemeNames(library, selfRef)
		local names = {}
		-- library built-in
		if library and type(library.Themes) == "table" then
			local numeric = true
			for k,v in pairs(library.Themes) do if type(k) ~= "number" then numeric = false break end end
			if numeric then
				for _,v in ipairs(library.Themes) do if type(v) == "string" then names[v] = true end end
			else
				for k,v in pairs(library.Themes) do if type(k) == "string" then names[k] = true end end
			end
		end
		-- dynamic imports
		if library and library.DynamicImportedThemes then
			for k,_ in pairs(library.DynamicImportedThemes) do names[k] = true end
		end
		-- disk themes
		if selfRef and selfRef.DiskThemeIndex then
			for k,_ in pairs(selfRef.DiskThemeIndex) do names[k] = true end
		end
		local out = {}
		for k,_ in pairs(names) do table.insert(out, k) end
		table.sort(out)
		return out
	end

    function InterfaceManager:BuildInterfaceSection(tab)
        assert(self.Library, "Must set InterfaceManager.Library")
		local Library = self.Library
        local Settings = InterfaceManager.Settings

        -- ensure folders exist & load config before UI
		InterfaceManager:BuildFolderTree()
        InterfaceManager:LoadSettings()
		-- scan/register disk themes
		InterfaceManager:ScanThemes()
		InterfaceManager:RegisterThemesToLibrary(Library)

		local section = tab:AddSection("Interface")

		-- merged name list
		local mergedValues = getMergedThemeNames(Library, InterfaceManager)

		local InterfaceTheme = section:AddDropdown("InterfaceTheme", {
			Title = "Theme",
			Description = "Changes the interface theme.",
			Values = mergedValues,
			Default = Settings.Theme,
			Callback = function(Value)
				-- apply the theme (best-effort)
				local ok, msg = InterfaceManager:ApplyTheme(Value)
				if not ok then
					warn("[InterfaceManager] ApplyTheme failed:", msg)
				end
                Settings.Theme = Value
                InterfaceManager:SaveSettings()
			end
		})

        InterfaceTheme:SetValue(Settings.Theme)

		-- add Refresh button
		if section.AddButton then
			section:AddButton({
				Title = "Refresh Themes",
				Description = "Scan ATGHubSettings/Themes and update dropdown.",
				Callback = function()
					InterfaceManager:ScanThemes()
					InterfaceManager:RegisterThemesToLibrary(Library)
					local newList = getMergedThemeNames(Library, InterfaceManager)
					if InterfaceTheme.SetValues then
						pcall(function() InterfaceTheme:SetValues(newList) end)
					elseif InterfaceTheme.SetOptions then
						pcall(function() InterfaceTheme:SetOptions(newList) end)
					elseif InterfaceTheme.UpdateValues then
						pcall(function() InterfaceTheme:UpdateValues(newList) end)
					else
						print("[InterfaceManager] Refreshed theme list, re-open menu if dropdown didn't update.")
					end
				end
			})
		end

		-- other toggles
		if Library.UseAcrylic then
			section:AddToggle("AcrylicToggle", {
				Title = "Acrylic",
				Description = "The blurred background requires graphic quality 8+",
				Default = Settings.Acrylic,
				Callback = function(Value)
					if type(Library.ToggleAcrylic) == "function" then pcall(function() Library:ToggleAcrylic(Value) end) end
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
				if type(Library.ToggleTransparency) == "function" then pcall(function() Library:ToggleTransparency(Value) end) end
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
