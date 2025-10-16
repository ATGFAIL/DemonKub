-- SaveManager.lua
-- ปรับปรุงโดย: ChatGPT (อัปเดตเพื่อใช้ชื่อแมพ, ลดการสร้างโฟลเดอร์, เปลี่ยนปุ่ม autoload เป็น Toggle,
-- เพิ่ม Title (อังกฤษ) และ Description (ไทย) ให้กับ UI ทุกตัวในส่วน Configuration)

-- ตัวอย่างการใช้งาน (ตัวอย่างนี้เป็นคอมเมนต์):
-- local Toggle = Tabs.Main:AddToggle("MyToggle", { Title = "Example Toggle", Description = "ทดสอบสวิตช์ (เปิด/ปิด) -- คำอธิบายภาษาไทย", Default = false })
-- Toggle:OnChanged(function()
--     print("Toggle changed:", Options.MyToggle.Value)
-- end)
-- SaveManager จะจัดการไฟล์คอนฟิกให้ในโฟลเดอร์: <FolderRoot>/<MapName>/settings

local httpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local SaveManager = {} do
    -- root folder (can be changed via SetFolder)
    SaveManager.FolderRoot = "ATGSettings"
    SaveManager.Ignore = {}
    SaveManager.Options = {}
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

    -- get configs folder for current map (simplified layout: <Root>/<MapName>/settings)
    local function getConfigsFolder(self)
        local root = self.FolderRoot
        local mapName = getMapName()
        return root .. "/" .. mapName .. "/settings"
    end

    local function getConfigFilePath(self, name)
        local folder = getConfigsFolder(self)
        return folder .. "/" .. name .. ".json"
    end

    -- Build folder tree and migrate legacy configs if found (copy only)
    function SaveManager:BuildFolderTree()
        local root = self.FolderRoot
        ensureFolder(root)

        local mapName = getMapName()
        local mapFolder = root .. "/" .. mapName
        ensureFolder(mapFolder)

        local settingsFolder = mapFolder .. "/settings"
        ensureFolder(settingsFolder)

        -- legacy folder: <root>/settings (old layout). If files exist there, copy them into current map settings
        local legacySettingsFolder = root .. "/settings"
        if isfolder(legacySettingsFolder) then
            local files = listfiles(legacySettingsFolder)
            for i = 1, #files do
                local f = files[i]
                if f:sub(-5) == ".json" then
                    local base = f:match("([^/\\]+)%.json$")
                    if base and base ~= "options" then
                        local dest = settingsFolder .. "/" .. base .. ".json"
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
                local destAuto = settingsFolder .. "/autoload.txt"
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

        local success, encoded = pcall(httpService.JSONEncode, httpService, data)
        if not success then
            return false, "failed to encode data"
        end

        -- ensure folder exists
        local folder = fullPath:match("^(.*)/[^/]+$")
        if folder then ensureFolder(folder) end

        writefile(fullPath, encoded)
        return true
    end

    function SaveManager:Load(name)
        if (not name) then
            return false, "no config file is selected"
        end

        local file = getConfigFilePath(self, name)
        if not isfile(file) then return false, "invalid file" end

        local success, decoded = pcall(httpService.JSONDecode, httpService, readfile(file))
        if not success then return false, "decode error" end

        for _, option in next, decoded.objects do
            if self.Parser[option.type] then
                task.spawn(function() self.Parser[option.type].Load(option.idx, option) end)
            end
        end

        return true
    end

    function SaveManager:IgnoreThemeSettings()
        self:SetIgnoreIndexes({ "InterfaceTheme", "AcrylicToggle", "TransparentToggle", "MenuKeybind" })
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
                return self.Library:Notify({
                    Title = "Interface",
                    Content = "Config loader",
                    SubContent = "Failed to load autoload config: " .. err,
                    Duration = 7
                })
            end

            self.Library:Notify({
                Title = "Interface",
                Content = "Config loader",
                SubContent = string.format("Auto loaded config %q", name),
                Duration = 7
            })
        end
    end

    function SaveManager:BuildConfigSection(tab)
        assert(self.Library, "Must set SaveManager.Library")

        local section = tab:AddSection("Configuration")

        -- Config name (Title in English, Description in Thai)
        section:AddInput("SaveManager_ConfigName",    { Title = "Config name", Description = "ชื่อไฟล์สำหรับบันทึกค่าการตั้งค่า (ภาษาไทย)" })

        -- Config list dropdown
        section:AddDropdown("SaveManager_ConfigList", { Title = "Config list", Description = "รายการคอนฟิกที่มีอยู่ (เลือกเพื่อโหลด/แก้ไข)", Values = self:RefreshConfigList(), AllowNull = true })

        -- Create config
        section:AddButton({
            Title = "Create config",
            Description = "สร้างไฟล์คอนฟิกจากการตั้งค่าปัจจุบัน",
            Callback = function()
                local name = SaveManager.Options.SaveManager_ConfigName.Value

                if name:gsub(" ", "") == "" then
                    return self.Library:Notify({
                        Title = "Interface",
                        Content = "Config loader",
                        SubContent = "ชื่อคอนฟิกไม่ถูกต้อง (เว้นว่าง)",
                        Duration = 7
                    })
                end

                local success, err = self:Save(name)
                if not success then
                    return self.Library:Notify({
                        Title = "Interface",
                        Content = "Config loader",
                        SubContent = "การบันทึกคอนฟิกล้มเหลว: " .. err,
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

        -- Load config
        section:AddButton({
            Title = "Load config",
            Description = "โหลดการตั้งค่าจากไฟล์คอนฟิกที่เลือก",
            Callback = function()
                local name = SaveManager.Options.SaveManager_ConfigList.Value

                local success, err = self:Load(name)
                if not success then
                    return self.Library:Notify({
                        Title = "Interface",
                        Content = "Config loader",
                        SubContent = "การโหลดคอนฟิกล้มเหลว: " .. err,
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

        -- Overwrite config
        section:AddButton({
            Title = "Overwrite config",
            Description = "บันทึกทับไฟล์คอนฟิกที่เลือกด้วยการตั้งค่าปัจจุบัน",
            Callback = function()
                local name = SaveManager.Options.SaveManager_ConfigList.Value

                local success, err = self:Save(name)
                if not success then
                    return self.Library:Notify({
                        Title = "Interface",
                        Content = "Config loader",
                        SubContent = "การบันทึกทับล้มเหลว: " .. err,
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

        -- Refresh list
        section:AddButton({
            Title = "Refresh list",
            Description = "อัพเดตรายการไฟล์คอนฟิกจากโฟลเดอร์",
            Callback = function()
                SaveManager.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
                SaveManager.Options.SaveManager_ConfigList:SetValue(nil)
            end
        })

        -- สมมติว่ามีฟังก์ชัน getConfigsFolder(self) และ SaveManager, self.Library, ฯลฯ ตามโค้ดคุณ
local AutoToggle = section:AddToggle("SaveManager_AutoLoad", {
    Title = "Autoload",
    Description = "ตั้งค่าให้โหลดคอนฟิกนี้อัตโนมัติเมื่อเริ่มเกม",
    Default = false
})

-- guard flag เพื่อไม่ให้ OnChanged ทำงานขณะเรากำลังตั้งค่าเริ่มต้น
local initializing = true

-- helper paths
local autopath = getConfigsFolder(self) .. "/autoload.txt"

-- ฟังก์ชันช่วย: ตั้งคำอธิบายของ toggle แบบปลอดภัย (เช็คว่ามีเมธอด SetDesc หรือไม่)
local function setToggleDesc(val)
    if AutoToggle.SetDesc then
        AutoToggle:SetDesc(val)
    end
end

-- OnChanged callback (จะไม่ทำงานในช่วง initializing)
AutoToggle:OnChanged(function()
    if initializing then return end  -- ถ้าเรากำลังตั้งค่าเริ่มต้น ให้ข้าม
    local name = SaveManager.Options.SaveManager_ConfigList.Value

    if SaveManager.Options.SaveManager_AutoLoad.Value then
        -- ถ้าเปิด แต่ไม่มีคอนฟิกที่เลือก => แจ้งเตือนแล้ว revert
        if not name or name == "" then
            self.Library:Notify({
                Title = "Interface",
                Content = "Config loader",
                SubContent = "โปรดเลือกคอนฟิกก่อนตั้งค่า Autoload",
                Duration = 7
            })
            -- revert toggle (ใช้ SetValue เพื่อให้ UI อัปเดต)
            SaveManager.Options.SaveManager_AutoLoad:SetValue(false)
            return
        end

        -- เขียนไฟล์อย่างปลอดภัย
        pcall(function() writefile(autopath, name) end)
        setToggleDesc("กำลังโหลดอัตโนมัติ: " .. name)

        self.Library:Notify({
            Title = "Interface",
            Content = "Config loader",
            SubContent = string.format("Set %q to autoload", name),
            Duration = 7
        })
    else
        -- ปิด autoload -> ลบไฟล์ถ้ามี
        pcall(function()
            if isfile(autopath) then
                pcall(delfile, autopath)
            end
        end)
        setToggleDesc("ไม่มีการโหลดอัตโนมัติ")

        self.Library:Notify({
            Title = "Interface",
            Content = "Config loader",
            SubContent = "Autoload cleared",
            Duration = 7
        })
    end
end)

-- === ตอนเริ่มต้นของสคริปต์: อ่านไฟล์ก่อน แล้วตั้งค่า dropdown + toggle แบบเงียบ ๆ ===
do
    -- รีเฟรชรายการคอนฟิกก่อน เพื่อให้ dropdown มีค่า
    if SaveManager.Options and SaveManager.Options.SaveManager_ConfigList and SaveManager.Options.SaveManager_ConfigList.SetValues then
        SaveManager.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
    end

    if isfile(autopath) then
        local ok, name = pcall(readfile, autopath)
        if ok and name and name ~= "" then
            -- ตั้ง dropdown ให้เป็นคอนฟิกที่บันทึกไว้ (ถ้ามีใน list)
            if SaveManager.Options.SaveManager_ConfigList.SetValue then
                SaveManager.Options.SaveManager_ConfigList:SetValue(name)
            end
            -- ตั้ง toggle แต่ไม่ให้ callback ทำงานเพราะ initializing = true
            if SaveManager.Options.SaveManager_AutoLoad.SetValue then
                SaveManager.Options.SaveManager_AutoLoad:SetValue(true)
            end
            setToggleDesc("กำลังโหลดอัตโนมัติ: " .. name)
        else
            -- ถ้าอ่านไฟล์ไม่ได้ ให้ลบไฟล์ทิ้ง (optional)
            pcall(delfile, autopath)
            setToggleDesc("ไม่มีการโหลดอัตโนมัติ")
        end
    else
        setToggleDesc("ไม่มีการโหลดอัตโนมัติ")
    end

    -- เสร็จขั้นตอน initialization -> ปลด guard เพื่อให้ callback ทำงานตามปกติ
    initializing = false
end

-- หากต้องการ อย่าลืมเพิ่ม index ให้ SaveManager ไม่เซฟ toggle เป็นส่วนหนึ่งของ config ปกติ
SaveManager:SetIgnoreIndexes({ "SaveManager_ConfigList", "SaveManager_ConfigName", "SaveManager_AutoLoad" })

    -- initial build
    SaveManager:BuildFolderTree()
end

return SaveManager
