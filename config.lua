-- InterfaceManager (ATGHubSettings + dynamic theme apply)
local httpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local InterfaceManager = {} do
	-- root folder ใหม่ (สร้างใหม่สะอาดๆ)
	InterfaceManager.FolderRoot = "ATGHubSettings"

	-- default settings
	InterfaceManager.Settings = {
		Theme = "Dark",
		Acrylic = true,
		Transparency = true,
		MenuKeybind = "LeftControl"
	}

	-- internal
	local function sanitizeFilename(name)
		name = tostring(name or "")
		name = name:gsub("%s+", "_")
		name = name:gsub("[^%w%-%_]", "")
		if name == "" then return "Unknown" end
		return name
	end

	local function getMapName()
		local ok, map = pcall(function() return Workspace:FindFirstChild("Map") end)
		if ok and map and type(map.Name) == "string" then
			return sanitizeFilename(map.Name)
		end
		-- fallback to place name or "UnknownMap"
		local ok2, wn = pcall(function() return Workspace.Name end)
		if ok2 and wn then return sanitizeFilename(wn) end
		return "UnknownMap"
	end

	local function ensureFolder(path)
		if not isfolder(path) then makefolder(path) end
	end

	-- Build folders: root, Themes, <map>/Themes, settings, Imports
	function InterfaceManager:BuildFolderTree()
		local root = self.FolderRoot
		ensureFolder(root)

		local mapName = getMapName()
		local mapFolder = root .. "/" .. mapName
		ensureFolder(mapFolder)

		-- global & per-map settings
		ensureFolder(root .. "/settings")
		ensureFolder(mapFolder .. "/settings")

		-- global & per-map themes
		ensureFolder(root .. "/Themes")
		ensureFolder(mapFolder .. "/Themes")

		-- imports
		ensureFolder(root .. "/Imports")
	end

	function InterfaceManager:SetFolder(folder)
		self.FolderRoot = tostring(folder or "ATGHubSettings")
		self:BuildFolderTree()
	end

	function InterfaceManager:SetLibrary(lib)
		self.Library = lib
		-- register disk themes at set time
		self:RegisterThemesToLibrary(lib)
	end

	-- config file path uses map name (not PlaceId)
	local function getPrefixedSettingsFilename()
		local mapName = getMapName()
		local fname = "ATG Hub - " .. sanitizeFilename(mapName) .. ".json"
		return fname
	end

	local function getConfigFilePath(self)
		local root = self.FolderRoot
		local mapName = getMapName()
		local configFolder = root .. "/" .. mapName
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
			local ok, dec = pcall(httpService.JSONDecode, httpService, data)
			if ok and type(dec) == "table" then
				for k,v in pairs(dec) do self.Settings[k] = v end
			end
			return
		end

		-- ถ้ามี legacy options.json ให้ merge ค่า (แต่ไม่คัดลอกโฟลเดอร์ทั้งหมด)
		if isfile(legacyPath) then
			local data = readfile(legacyPath)
			local ok, dec = pcall(httpService.JSONDecode, httpService, data)
			if ok and type(dec) == "table" then
				for k,v in pairs(dec) do self.Settings[k] = v end
				local folder = path:match("^(.*)/[^/]+$")
				if folder then ensureFolder(folder) end
				writefile(path, httpService:JSONEncode(self.Settings or {}))
			end
			return
		end
		-- else use defaults
	end

	-- ================= Theme scanning/importing =================

	-- scan Themes folders and return list of { name, path, ext }
	function InterfaceManager:ScanThemes()
		local out = {}
		local root = self.FolderRoot
		local mapName = getMapName()
		local paths = {
			root .. "/Themes",
			root .. "/" .. mapName .. "/Themes"
		}
		for _, folder in ipairs(paths) do
			if isfolder(folder) and type(listfiles) == "function" then
				local ok, files = pcall(listfiles, folder)
				if ok and type(files) == "table" then
					for _, f in ipairs(files) do
						if f:match("%.lua$") or f:match("%.json$") then
							local base = f:match("([^/\\]+)$") or f
							local display = base:gsub("^ATG Hub %- ", ""):gsub("%.lua$",""):gsub("%.json$",""):gsub("%_"," ")
							local ext = f:match("%.([a-zA-Z0-9]+)$")
							table.insert(out, { name = display, path = f, ext = ext })
						end
					end
				end
			end
		end
		return out
	end

	-- write theme file to global Themes
	function InterfaceManager:ImportTheme(name, content, ext)
		ext = tostring(ext or "lua"):lower()
		if ext ~= "lua" and ext ~= "json" then ext = "lua" end
		local rootThemes = self.FolderRoot .. "/Themes"
		ensureFolder(rootThemes)
		local safe = sanitizeFilename(name)
		local fname = "ATG Hub - " .. safe .. "." .. ext
		local full = rootThemes .. "/" .. fname
		writefile(full, tostring(content or ""))
		-- try to register immediately
		if self.Library then
			self:TryRegisterThemeFile(full, ext)
		end
		return full
	end

	-- parse a theme file and return themeTable (or nil)
	local function parseThemeFile(fullpath, ext)
		if not isfile(fullpath) then return nil end
		local raw = readfile(fullpath)
		if ext == "json" then
			local ok, dec = pcall(httpService.JSONDecode, httpService, raw)
			if ok and type(dec) == "table" then return dec end
			return nil
		else
			-- lua: try loadstring and expect return table
			local ok, chunk = pcall(loadstring, raw)
			if not ok or type(chunk) ~= "function" then return nil end
			local ok2, result = pcall(chunk)
			if ok2 and type(result) == "table" then return result end
			return nil
		end
	end

	-- Try to register a theme file to the library (best-effort)
	function InterfaceManager:TryRegisterThemeFile(fullpath, ext)
		local themeTbl = parseThemeFile(fullpath, ext)
		if not themeTbl then return false, "could not parse theme" end
		if not self.Library then return false, "no library" end

		local displayName = fullpath:match("([^/\\]+)$") or fullpath
		displayName = displayName:gsub("^ATG Hub %- ", ""):gsub("%.lua$",""):gsub("%.json$",""):gsub("%_"," ")

		-- Prefer API: Library:RegisterTheme(name, table)
		if type(self.Library.RegisterTheme) == "function" then
			pcall(function() self.Library:RegisterTheme(displayName, themeTbl) end)
			-- also store dynamic import table if needed
			self.Library.DynamicImportedThemes = self.Library.DynamicImportedThemes or {}
			self.Library.DynamicImportedThemes[displayName] = themeTbl
			return true, "registered"
		end

		-- Fallback: if Library.Themes is map, put it there
		if type(self.Library.Themes) == "table" then
			local isMap = false
			for k,v in pairs(self.Library.Themes) do
				if type(k) ~= "number" then isMap = true break end
			end
			if isMap then
				self.Library.Themes[displayName] = themeTbl
				self.Library.DynamicImportedThemes = self.Library.DynamicImportedThemes or {}
				self.Library.DynamicImportedThemes[displayName] = themeTbl
				return true, "merged into map"
			else
				-- array: push name, and keep table in DynamicImportedThemes
				local exists = false
				for _,v in ipairs(self.Library.Themes) do if v == displayName then exists = true break end end
				if not exists then table.insert(self.Library.Themes, displayName) end
				self.Library.DynamicImportedThemes = self.Library.DynamicImportedThemes or {}
				self.Library.DynamicImportedThemes[displayName] = themeTbl
				return true, "added name + dynamic table"
			end
		end

		return false, "no suitable integration"
	end

	-- Register all disk themes to library
	function InterfaceManager:RegisterThemesToLibrary(library)
		if not library then return end
		local found = self:ScanThemes()
		for _, item in ipairs(found) do
			pcall(function() self:TryRegisterThemeFile(item.path, item.ext) end)
		end
	end

	-- ================ Theme apply logic (best-effort, dynamic accent update) ================

	-- low-level: try to push a single Accent color to Library (multiple API tries)
	local function tryUpdateAccentToLibrary(lib, color)
		if not lib or not color then return end
		-- try API names that library might expose
		local ok
		if type(lib.UpdateAccent) == "function" then pcall(lib.UpdateAccent, lib, color) end
		if type(lib.SetAccent) == "function" then pcall(lib.SetAccent, lib, color) end
		if type(lib.SetAccentColor) == "function" then pcall(lib.SetAccentColor, lib, color) end
		-- try setting fields directly
		pcall(function() lib.Accent = color end)
		pcall(function() lib.CurrentAccent = color end)
		-- if library has a refresh hook
		if type(lib.RefreshTheme) == "function" then pcall(lib.RefreshTheme, lib) end
		if type(lib.ApplyTheme) == "function" then pcall(lib.ApplyTheme, lib, lib.CurrentTheme or {}) end
	end

	-- Apply theme by name (search in dynamic imports, library map, or disk), and start polling Accent if theme is dynamic
	function InterfaceManager:ApplyThemeByName(name)
		if not name or not self.Library then return false, "no name or library" end
		local lib = self.Library

		-- first, if library has a SetTheme that accepts name, prefer that
		if type(lib.SetTheme) == "function" then
			local ok, err = pcall(function() lib:SetTheme(name) end)
			if ok then
				-- after set, if theme table exists in DynamicImportedThemes, start poll
				local themeTbl = (lib.DynamicImportedThemes and lib.DynamicImportedThemes[name]) or nil
				if themeTbl and type(themeTbl) == "table" then
					self:StartThemeAccentPoll(themeTbl)
				end
				return true, "SetTheme(name) called"
			end
		end

		-- next try dynamic imports map
		if lib.DynamicImportedThemes and lib.DynamicImportedThemes[name] then
			local themeTbl = lib.DynamicImportedThemes[name]
			-- try RegisterTheme + SetTheme if possible
			if type(lib.RegisterTheme) == "function" then
				pcall(function() lib:RegisterTheme(name, themeTbl) end)
				pcall(function() lib:SetTheme(name) end)
			elseif type(lib.ApplyTheme) == "function" then
				pcall(function() lib:ApplyTheme(themeTbl) end)
			else
				-- try set fields directly
				pcall(function() lib.CurrentTheme = themeTbl end)
				if type(lib.RefreshTheme) == "function" then pcall(function() lib:RefreshTheme() end) end
			end
			-- start polling dynamic Accent
			self:StartThemeAccentPoll(themeTbl)
			return true, "applied from DynamicImportedThemes"
		end

		-- fallback: scan disk and try to parse theme file and apply table
		local found = self:ScanThemes()
		for _, item in ipairs(found) do
			if item.name == name then
				local themeTbl = parseThemeFile(item.path, item.ext)
				if themeTbl then
					if type(lib.RegisterTheme) == "function" then
						pcall(function() lib:RegisterTheme(name, themeTbl) end)
						pcall(function() lib:SetTheme(name) end)
					elseif type(lib.ApplyTheme) == "function" then
						pcall(function() lib:ApplyTheme(themeTbl) end)
					else
						pcall(function() lib.CurrentTheme = themeTbl end)
						if type(lib.RefreshTheme) == "function" then pcall(function() lib:RefreshTheme() end) end
					end
					self:StartThemeAccentPoll(themeTbl)
					return true, "applied from disk"
				end
			end
		end

		return false, "could not apply theme"
	end

	-- poll Theme.Accent and push to library (if theme updates Accent dynamically)
	function InterfaceManager:StartThemeAccentPoll(themeTbl)
		if not themeTbl or type(themeTbl) ~= "table" then return end
		-- avoid starting multiple pollers for same table
		themeTbl._ATG_POLLING = themeTbl._ATG_POLLING or true
		task.spawn(function()
			local last = nil
			while themeTbl._ATG_POLLING do
				local acc = themeTbl.Accent
				-- if Accent is function, call it (support function-based themes)
				if type(acc) == "function" then
					local ok, res = pcall(acc)
					if ok and res then acc = res end
				end
				-- if color changed, push to lib
				if acc and (not last or acc ~= last) then
					tryUpdateAccentToLibrary(self.Library, acc)
					last = acc
				end
				task.wait(0.05)
			end
		end)
	end

	-- Register all disk themes to library (best-effort)
	function InterfaceManager:RegisterThemesToLibrary(library)
		if not library then return end
		local found = self:ScanThemes()
		for _, item in ipairs(found) do
			pcall(function() self:TryRegisterThemeFile(item.path, item.ext) end)
		end
	end

	-- ======== UI Builder ========
	local function getLibraryThemeNames(library)
		local names = {}
		if not library then return {} end

		-- library.Themes as array or map
		if type(library.Themes) == "table" then
			local numeric = true
			for k,v in pairs(library.Themes) do if type(k) ~= "number" then numeric = false break end end
			if numeric then
				for _,v in ipairs(library.Themes) do if type(v) == "string" then names[v] = true end end
			else
				for k,v in pairs(library.Themes) do if type(k) == "string" then names[k] = true end end
			end
		end

		-- dynamic imports
		if library.DynamicImportedThemes then
			for k,v in pairs(library.DynamicImportedThemes) do names[k] = true end
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

		InterfaceManager:BuildFolderTree()
		InterfaceManager:LoadSettings()
		InterfaceManager:RegisterThemesToLibrary(Library)

		local section = tab:AddSection("Interface")

		local mergedValues = getLibraryThemeNames(Library)
		local InterfaceTheme = section:AddDropdown("InterfaceTheme", {
			Title = "Theme",
			Description = "Changes the interface theme.",
			Values = mergedValues,
			Default = Settings.Theme,
			Callback = function(Value)
				-- apply using our helper which will attempt various APIs + dynamic accent polling
				InterfaceManager:ApplyThemeByName(Value)
				Settings.Theme = Value
				InterfaceManager:SaveSettings()
			end
		})
		InterfaceTheme:SetValue(Settings.Theme)

		-- Refresh button for manual rescan
		if section.AddButton then
			section:AddButton({
				Title = "Refresh Themes",
				Description = "Rescan ATGHubSettings/Themes and update dropdown.",
				Callback = function()
					InterfaceManager:RegisterThemesToLibrary(Library)
					local newList = getLibraryThemeNames(Library)
					if InterfaceTheme.SetValues then
						pcall(function() InterfaceTheme:SetValues(newList) end)
					elseif InterfaceTheme.SetOptions then
						pcall(function() InterfaceTheme:SetOptions(newList) end)
					else
						print("[InterfaceManager] Themes refreshed. Re-open menu if dropdown not updated.")
					end
				end
			})
		end

		-- rest of the UI controls...
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
