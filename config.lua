local httpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local InterfaceManager = {} do
	-- root folder (default changed)
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
		if name == "" then
			return "Unknown"
		end
		return name
	end

	local function getPlaceId()
		local success, id = pcall(function() return tostring(game.PlaceId) end)
		if success and id then
			return id
		end
		return "UnknownPlace"
	end

	local function getMapName()
		local ok, map = pcall(function() return Workspace:FindFirstChild("Map") end)
		if ok and map and map.IsA and map:IsA("Instance") then
			return sanitizeFilename(map.Name)
		end
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

	-- best-effort copy helpers for migrating legacy folder
	local function copyFile(src, dst)
		if not isfile(src) then return false end
		local ok, content = pcall(readfile, src)
		if not ok then return false end
		local folder = dst:match("^(.*)/[^/]+$")
		if folder and not isfolder(folder) then makefolder(folder) end
		pcall(writefile, dst, content)
		return true
	end

	local function copyFilesInFolder(srcFolder, dstFolder)
		-- listfiles might not exist in every executor; guard with pcall
		if not listfiles then return end
		local ok, files = pcall(listfiles, srcFolder)
		if not ok or type(files) ~= "table" then return end
		ensureFolder(dstFolder)
		for _, f in ipairs(files) do
			local base = f:match("([^/\\]+)$") or f
			local dst = dstFolder .. "/" .. base
			pcall(copyFile, f, dst)
		end
	end

	-- Migrate legacy FluentSettings -> new root (best-effort, non-destructive)
	function InterfaceManager:MigrateLegacyFolder(oldName, newName)
		if not isfolder(oldName) then
			return false, "no legacy folder"
		end
		if not newName or newName == "" then newName = self.FolderRoot end
		ensureFolder(newName)

		-- copy root-level files
		pcall(copyFilesInFolder, oldName, newName)

		-- copy common subfolders
		local subs = { "Themes", "settings", "Imports" }
		for _, sub in ipairs(subs) do
			local s = oldName .. "/" .. sub
			local d = newName .. "/" .. sub
			if isfolder(s) then
				pcall(copyFilesInFolder, s, d)
			end
		end

		return true, "migrated"
	end

	-- build folder tree with Themes, Imports, per-place folders
    function InterfaceManager:BuildFolderTree()
		local root = self.FolderRoot

		-- auto-migrate if old folder exists and differs
		if root ~= "FluentSettings" and isfolder("FluentSettings") and not isfolder(root) then
			-- best-effort copy, do not delete originals
			pcall(function() self:MigrateLegacyFolder("FluentSettings", root) end)
		end

		ensureFolder(root)

		local placeId = getPlaceId()
		local placeFolder = root .. "/" .. placeId
		ensureFolder(placeFolder)

		-- legacy settings folder (kept)
		local settingsFolder = root .. "/settings"
		ensureFolder(settingsFolder)

		-- per-place settings
		local placeSettingsFolder = placeFolder .. "/settings"
		ensureFolder(placeSettingsFolder)

		-- global themes + per-place themes
		local themesRoot = root .. "/Themes"
		ensureFolder(themesRoot)

		local placeThemes = placeFolder .. "/Themes"
		ensureFolder(placeThemes)

		-- imports (where user-imported raw files can be dropped)
		local imports = root .. "/Imports"
		ensureFolder(imports)
    end

    function InterfaceManager:SetFolder(folder)
		self.FolderRoot = tostring(folder or "ATGHubSettings")
		-- try to migrate legacy FluentSettings -> new folder if present
		pcall(function() self:MigrateLegacyFolder("FluentSettings", self.FolderRoot) end)
		self:BuildFolderTree()
	end

    function InterfaceManager:SetLibrary(library)
		self.Library = library
		-- try to register themes immediately when library set
		self:RegisterThemesToLibrary(library)
	end

	-- helper: prefixed filename for settings -> "ATG Hub - <placeId> - <mapName>.json"
	local function getPrefixedSettingsFilename()
		local placeId = getPlaceId()
		local mapName = getMapName()
		local fname = "ATG Hub - " .. sanitizeFilename(placeId) .. " - " .. sanitizeFilename(mapName) .. ".json"
		return fname
	end

	-- config path per place
	local function getConfigFilePath(self)
		local root = self.FolderRoot
		local placeId = getPlaceId()
		-- ensure subfolders exist
		local configFolder = root .. "/" .. placeId
		ensureFolder(configFolder)
		local fname = getPrefixedSettingsFilename()
		return configFolder .. "/" .. fname
	end

    function InterfaceManager:SaveSettings()
		local path = getConfigFilePath(self)
		-- ensure folder (in case)
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

		if isfile(legacyPath) then
			local data = readfile(legacyPath)
			local success, decoded = pcall(httpService.JSONDecode, httpService, data)
			if success and type(decoded) == "table" then
				for i,v in next, decoded do
					self.Settings[i] = v
				end
				-- save to new path
				local folder = path:match("^(.*)/[^/]+$")
				if folder then ensureFolder(folder) end
				local encoded = httpService:JSONEncode(self.Settings or {})
				writefile(path, encoded)
			end
			return
		end

		-- ไม่มีไฟล์ใดๆ -> ใช้ default
    end

	-- ==== Theme file utilities ====
	-- returns table of { name = displayName, path = fullPath, ext = "lua"/"json" }
	function InterfaceManager:ScanThemes()
		local themes = {}
		local root = self.FolderRoot
		local themePaths = {
			root .. "/Themes",
			root .. "/" .. getPlaceId() .. "/Themes"
		}
		for _, folder in ipairs(themePaths) do
			if isfolder(folder) and listfiles then
				for _, fname in ipairs(listfiles(folder) or {}) do
					local lfname = fname
					if lfname:match("%.lua$") or lfname:match("%.json$") then
						local base = lfname:match("([^/\\]+)$") or lfname
						local display = base
						display = display:gsub("^ATG Hub %- ", "")
						display = display:gsub("%.lua$", ""):gsub("%.json$", "")
						display = display:gsub("%_", " ")
						local ext = lfname:match("%.([a-zA-Z0-9]+)$")
						table.insert(themes, { name = display, path = lfname, ext = ext })
					end
				end
			end
		end
		return themes
	end

	-- import theme content (string) into root Themes folder
	-- name: suggested theme name (used for filename)
	-- content: raw file content (string)
	-- ext: "lua" or "json" (defaults to lua)
	function InterfaceManager:ImportTheme(name, content, ext)
		ext = tostring(ext or "lua"):lower()
		if ext ~= "lua" and ext ~= "json" then ext = "lua" end
		local rootThemes = self.FolderRoot .. "/Themes"
		ensureFolder(rootThemes)

		local safe = sanitizeFilename(name)
		local fname = "ATG Hub - " .. safe .. "." .. ext
		local full = rootThemes .. "/" .. fname

		-- overwrite if exists
		writefile(full, tostring(content or ""))

		-- attempt to register immediately
		if self.Library then
			self:TryRegisterThemeFile(full, ext)
		end

		return full
	end

	-- try to load a theme file and register to library if possible
	function InterfaceManager:TryRegisterThemeFile(fullpath, ext)
		if not isfile(fullpath) then return false, "file not found" end
		local raw = readfile(fullpath)
		local themeTbl = nil
		if ext == "json" then
			local ok, dec = pcall(httpService.JSONDecode, httpService, raw)
			if ok and type(dec) == "table" then
				themeTbl = dec
			end
		else -- lua
			local ok, chunk = pcall(loadstring, raw)
			if ok and type(chunk) == "function" then
				local ok2, result = pcall(chunk)
				if ok2 and type(result) == "table" then
					themeTbl = result
				end
			end
		end

		if themeTbl and self.Library then
			local displayName = fullpath:match("([^/\\]+)$") or fullpath
			displayName = displayName:gsub("^ATG Hub %- ", ""):gsub("%.lua$",""):gsub("%.json$",""):gsub("%_"," ")
			if type(self.Library.RegisterTheme) == "function" then
				pcall(function() self.Library:RegisterTheme(displayName, themeTbl) end)
				return true, "registered"
			else
				local lt = self.Library.Themes
				if type(lt) == "table" then
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

	-- helper to produce a list of theme names (merge library + imported ones)
	local function getLibraryThemeNames(library)
		local names = {}
		if not library then return names end

		-- if library.Themes is an array of strings
		if type(library.Themes) == "table" then
			local numeric = true
			for k,v in pairs(library.Themes) do
				if type(k) ~= "number" then numeric = false break end
			end
			if numeric then
				for _,v in ipairs(library.Themes) do
					if type(v) == "string" then names[v] = true end
				end
			else
				for k,v in pairs(library.Themes) do
					if type(k) == "string" then names[k] = true end
				end
			end
		end

		-- also include dynamic imports if any
		if library.DynamicImportedThemes then
			for k,v in pairs(library.DynamicImportedThemes) do
				names[k] = true
			end
		end

		-- include on-disk themes
		local disk = InterfaceManager:ScanThemes()
		for _, item in ipairs(disk) do
			names[item.name] = true
		end

		-- convert to array
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

		local section = tab:AddSection("Interface")

		-- generate merged values
		local mergedValues = getLibraryThemeNames(Library)

		local InterfaceTheme = section:AddDropdown("InterfaceTheme", {
			Title = "Theme",
			Description = "Changes the interface theme.",
			Values = mergedValues,
			Default = Settings.Theme,
			Callback = function(Value)
				-- try to set using library API if available
				if type(Library.SetTheme) == "function" then
					pcall(function() Library:SetTheme(Value) end)
				end

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

		-- optional: add UI buttons to import themes (if UI supports AddButton)
		if section.AddButton then
			section:AddButton({
				Title = "Import Theme (paste)",
				Description = "Import a theme file (lua or json) by pasting content via script.",
				Callback = function()
					print("Use InterfaceManager:ImportTheme(name, content, ext) from code to import theme files.")
				end
			})
		end
    end
end

return InterfaceManager
