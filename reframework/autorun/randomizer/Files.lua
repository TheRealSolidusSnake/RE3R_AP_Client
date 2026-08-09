local Files = {}

Files.isInit = false
Files.applyingReceivedFile = false
Files.suppressedReads = {}
Files.lastReplay = 0
Files.physicalGetFileId = nil
Files.pendingPhysicalFile = nil
Files.recentPhysicalChecks = {}
Files.lastDisconnectWarningTime = 0
Files.fileObjectNames = {}
Files.fileColliders = {}
Files.colliderScene = nil
Files.colliderRefreshNeeded = true
-- World re-activation after AP getFile / inventory retire the prop.
-- Pending finds are retried on an interval (not every frame — that lagged hard).
Files.pendingWorldRevives = {}
Files.worldRevived = {}
-- Resolved prop handles, keyed by file id, so the retry tick is a couple of
-- getters instead of a fresh scene scan. Dropped whenever the scene swaps.
Files.trackedWorldFiles = {}
Files.reviveScene = nil
Files.reviveFailureLogged = {}
Files.reviveSearchBackoff = {}
Files.menuContextCheckedAt = nil
Files.menuContextCached = false
Files.pendingAuditMapKey = nil
Files.pendingAuditAt = nil
Files.needsFileReplay = true
Files.lastReviveMapId = nil
Files.lastPendingReviveProcess = 0
Files.pendingReviveInterval = 2.0 -- seconds between pending scene scans
-- NEST 2 Employee Regulations doubles as the map for the area, so examining it
-- hands over the map for free. Hold that back until AP sends us the file.
Files.mapFileId = 15
Files.mapGrantWindow = 3 -- seconds the map grant may trail the pickup by

local function file_id_name(fileId)
    return string.format("Mes_File_%02d", tonumber(fileId))
end

local function get_manager()
    return sdk.get_managed_singleton(
        sdk.game_namespace("gamemastering.UIFileManager")
    )
end

function Files.IsEnabled()
    return Archipelago and Archipelago.files_as_locations == true
end

function Files.CanCheck()
    return Files.IsEnabled() and Archipelago.IsConnected()
end

function Files.WarnDisconnected()
    if os.clock() - Files.lastDisconnectWarningTime < 1 then
        return
    end

    Files.lastDisconnectWarningTime = os.clock()
    GUI.AddText("Reconnect to Archipelago before examining this file.")
end

function Files.GetLocation(fileId)
    local idName = type(fileId) == "string" and fileId or file_id_name(fileId)

    for _, location in pairs(Lookups.files or {}) do
        if location.file_id == idName then
            return location
        end
    end

    return nil
end

function Files.IsReceivedFileId(fileId)
    fileId = tonumber(fileId)
    if not fileId or not Storage or not Storage.receivedFiles then
        return false
    end

    return Storage.receivedFiles[file_id_name(fileId)] == true
end

function Files.MarkWorldCollected(fileId)
    fileId = tonumber(fileId)
    if not fileId or not Storage then
        return
    end

    Storage.collectedFiles = Storage.collectedFiles or {}
    local key = file_id_name(fileId)
    if Storage.collectedFiles[key] then
        return
    end

    Storage.collectedFiles[key] = true
    Storage.Update()
end

local function is_file_location_sent(location)
    if not location or not location.file_id then
        return false
    end

    if location.sent then
        return true
    end

    for _, loc in pairs(Lookups.locations or {}) do
        if loc.file_id == location.file_id and loc.sent then
            return true
        end
    end

    return false
end

-- True once the in-world document has been examined (AP location sent).
-- Trust loc.sent over collected_files — that flag can go stale (e.g. AP getFile
-- retired a prop and set the flag without a real world examine), which then
-- permanently blocks revive for files the player never saw.
function Files.IsWorldCheckDone(fileId)
    fileId = tonumber(fileId)
    if not fileId then
        return false
    end

    local location = Files.GetLocation(fileId)
    if is_file_location_sent(location) then
        Files.MarkWorldCollected(fileId)
        return true
    end

    local key = file_id_name(fileId)
    if Storage and Storage.collectedFiles and Storage.collectedFiles[key] then
        Storage.collectedFiles[key] = nil
        Storage.Update()
        log.info("[Randomizer] Cleared stale collected_files for " .. key)
    end

    return false
end

local function reset_triggers_for_owner(gameObject)
    if not gameObject then
        return
    end

    local interactManager = Scene.getInteractManager()
    if not interactManager then
        return
    end

    local ownerName = nil
    pcall(function()
        ownerName = gameObject:call("get_Name()")
    end)
    if not ownerName then
        return
    end

    local listNames = {
        "_TrgWks",
        "_TrgWks_Activated",
        "_TrgWks_Excluded",
        "_TrgWks_Invalid",
        "_TrgWks_Needupdate"
    }

    for _, listName in ipairs(listNames) do
        local list = interactManager:get_field(listName)
        if list then
            local count = 0
            pcall(function()
                count = list:call("get_Count") or 0
            end)
            for index = 0, count - 1 do
                local work = nil
                pcall(function()
                    work = list:call("get_Item", index)
                end)
                local trigger = work and work:get_field("Tr")
                if trigger then
                    local owner = nil
                    pcall(function()
                        owner = trigger:call("get_Owner()")
                    end)
                    local name = nil
                    pcall(function()
                        name = owner and owner:call("get_Name()")
                    end)
                    if name == ownerName then
                        pcall(function()
                            trigger:set_field("_DoneSucceed", false)
                            trigger:call("set_IsEnabled(System.Boolean)", true)
                            trigger:call("set_IsActive(System.Boolean)", true)
                            trigger:call("clearActivated()")
                        end)
                    end
                end
            end
        end
    end

    pcall(function()
        interactManager:call("clearTriggerLock()")
    end)
end

-- Draw/Update on the object are only the "self" half of the state; the engine
-- ANDs them with every parent folder. A prop whose folder is parked reports
-- DrawSelf/UpdateSelf true while get_Draw/get_Update stay false, so it is
-- invisible and cannot be interacted with. Always judge revives on these.
local function world_object_is_live(gameObject)
    if not gameObject then
        return false
    end

    local live = false
    pcall(function()
        live = gameObject:call("get_Draw()") == true
            and gameObject:call("get_Update()") == true
    end)

    return live
end

-- Parked folders are invisible to scene:findFolder, so the only handle we get on
-- one is through an object we already resolved. Walk up until an active ancestor
-- is found, then activate back down.
local function activate_folder_chain(folder)
    local parked = {}
    local depth = 0

    while folder and depth < 16 do
        local active = false
        pcall(function()
            active = folder:call("get_Active()") == true
        end)
        if active then
            break
        end

        table.insert(parked, folder)

        local parent = nil
        pcall(function()
            parent = folder:call("get_Parent()")
        end)
        folder = parent
        depth = depth + 1
    end

    for index = #parked, 1, -1 do
        local target = parked[index]
        pcall(function()
            target:call("set_Standby(System.Boolean)", false)
            target:call("set_DrawSelf(System.Boolean)", true)
            target:call("set_UpdateSelf(System.Boolean)", true)
            target:call("activate()")
        end)
    end

    return #parked > 0
end

local function describe_world_object(gameObject)
    local folderPath = "<none>"
    local drawSelf, updateSelf, draw, update = false, false, false, false

    pcall(function()
        local folder = gameObject:call("get_Folder()")
        if folder then
            folderPath = folder:call("get_Path()") or folderPath
        end
    end)
    pcall(function()
        drawSelf = gameObject:call("get_DrawSelf()") == true
        updateSelf = gameObject:call("get_UpdateSelf()") == true
        draw = gameObject:call("get_Draw()") == true
        update = gameObject:call("get_Update()") == true
    end)

    return string.format(
        "drawSelf=%s updateSelf=%s draw=%s update=%s folder=%s",
        tostring(drawSelf),
        tostring(updateSelf),
        tostring(draw),
        tostring(update),
        tostring(folderPath)
    )
end

-- getFile leaves the scene object in place but turns Draw/Update off.
-- Turn those back on so the check can still be examined.
local function revive_world_file_object(gameObject)
    if not gameObject then
        return false
    end

    local folder = nil
    pcall(function()
        folder = gameObject:call("get_Folder()")
    end)
    if folder then
        activate_folder_chain(folder)
    end

    pcall(function()
        -- Self flags are the ones getFile clears.
        gameObject:call("set_DrawSelf(System.Boolean)", true)
        gameObject:call("set_UpdateSelf(System.Boolean)", true)
    end)

    local colliders = nil
    pcall(function()
        colliders = gameObject:call(
            "getComponent(System.Type)",
            sdk.typeof("via.physics.Colliders")
        )
    end)
    if colliders then
        pcall(function()
            colliders:call("set_Enabled(System.Boolean)", true)
        end)
    end

    reset_triggers_for_owner(gameObject)
    return world_object_is_live(gameObject)
end

local fileLocationEnumCache = nil

local function get_file_location_enum_id(name)
    if fileLocationEnumCache == nil then
        fileLocationEnumCache = {}
        local typedef = sdk.find_type_definition("offline.FileLocation.ID")
        if typedef then
            for _, fieldName in ipairs({
                "invalid", "Tutorial", "DownTown", "UpTown", "RPD",
                "ClockTower", "Hospital", "Hospital2", "Laboratory",
                "Etcetera", "Report", "Unknown"
            }) do
                local field = typedef:get_field(fieldName)
                if field then
                    local ok, value = pcall(function()
                        return field:get_data(nil)
                    end)
                    if ok and value ~= nil then
                        fileLocationEnumCache[fieldName] = tonumber(value) or value
                    end
                end
            end
        end
    end

    return fileLocationEnumCache[name]
end

-- Map files.json paths to populate the files tab 
function Files.ResolveFileLocationId(fileId)
    local location = Files.GetLocation(fileId)
    local folder = location and location.folder_path or ""

    if string.find(folder, "Location_ClockTower", 1, true) then
        return get_file_location_enum_id("ClockTower")
    end

    if string.find(folder, "Location_RPD", 1, true) then
        return get_file_location_enum_id("RPD")
    end

    if string.find(folder, "Location_Hospital", 1, true)
        or string.find(folder, "Location_Hospital2", 1, true)
    then
        if string.find(folder, "Hospital2", 1, true)
            or string.find(folder, "NEST", 1, true)
        then
            return get_file_location_enum_id("Hospital2")
                or get_file_location_enum_id("Hospital")
        end
        return get_file_location_enum_id("Hospital")
    end

    if string.find(folder, "Location_Laboratory", 1, true)
        or string.find(folder, "Location_Nest", 1, true)
        or string.find(folder, "Location_NEST", 1, true)
    then
        return get_file_location_enum_id("Laboratory")
    end

    if string.find(folder, "Location_UpTown", 1, true) then
        return get_file_location_enum_id("UpTown")
    end

    if string.find(folder, "Location_DownTown", 1, true) then
        return get_file_location_enum_id("DownTown")
    end

    local manager = get_manager()

    if manager then
        local ok, native = pcall(function()
            return manager:call("getFileLocation", tonumber(fileId))
        end)

        if ok and native ~= nil then
            local nativeId = tonumber(native) or native
            local invalidId = get_file_location_enum_id("invalid") or 0
            if nativeId ~= invalidId then
                return nativeId
            end
        end
    end
    return nil
end

function Files.ClearVanillaOwnership(fileId)
    local manager = get_manager()
    fileId = tonumber(fileId)
    if not manager or not fileId then
        return
    end

    pcall(function()
        manager:call(
            "setFileVariableData(offline.File.ID, System.Boolean)",
            fileId,
            false
        )
    end)
end

-- Full vanilla unlock. Retires the world prop — only safe after the AP
-- location check has been sent (or there's no world prop left to examine).
function Files.WriteVanillaOwnership(fileId)
    local manager = get_manager()
    fileId = tonumber(fileId)
    if not manager or not fileId then
        return false
    end

    Files.applyingReceivedFile = true
    local ok, err = pcall(function()
        manager:call("getFile", fileId)
        manager:call("readFile", fileId)
    end)
    Files.applyingReceivedFile = false

    if not ok then
        log.error(
            "[Randomizer] Failed vanilla file unlock for "
                .. file_id_name(fileId)
                .. ": "
                .. tostring(err)
        )
    end

    return ok
end

local function add_unique_name(list, seen, name)
    if type(name) ~= "string" or name == "" or seen[name] then
        return
    end
    seen[name] = true
    table.insert(list, name)
end

-- Clock Tower entries wrongly used Mes_File_XX as item_object; downtown uses File0XX.
local function world_file_name_candidates(objectName, fileId)
    local names = {}
    local seen = {}
    add_unique_name(names, seen, objectName)
    fileId = tonumber(fileId)
    if fileId then
        add_unique_name(names, seen, string.format("File%03d", fileId))
        add_unique_name(names, seen, string.format("file%03d", fileId))
        add_unique_name(names, seen, string.format("File%02d", fileId))
        add_unique_name(names, seen, string.format("file%02d", fileId))
        add_unique_name(names, seen, file_id_name(fileId))
    end
    return names
end

local function activate_folder_path(scene, folderPath)
    if not scene or type(folderPath) ~= "string" or folderPath == "" then
        return nil
    end

    local folder = nil
    pcall(function()
        folder = scene:call("findFolder(System.String)", folderPath)
    end)
    if not folder then
        local shortName = string.match(folderPath, "([^/]+)$")
        if shortName then
            pcall(function()
                folder = scene:call("findFolder(System.String)", shortName)
            end)
        end
    end
    if not folder then
        return nil
    end

    pcall(function()
        folder:call("set_Standby(System.Boolean)", false)
        folder:call("activate()")
        folder:call("activate(System.Boolean)", true)
        folder:call("set_DrawSelf(System.Boolean)", true)
        folder:call("set_UpdateSelf(System.Boolean)", true)
    end)
    return folder
end

-- Figure out the world file prop. When activateFolder is true (revive path), wake
-- the folder first. Quiet mode is for read-only callers (e.g. ItemIndicator).
function Files.FindWorldObject(objectName, folderPath, fileId, activateFolder)
    local scene = Scene and Scene.getSceneObject and Scene.getSceneObject()
    if not scene then
        return nil
    end

    local folder = nil
    if activateFolder then
        folder = activate_folder_path(scene, folderPath)
    elseif type(folderPath) == "string" and folderPath ~= "" then
        pcall(function()
            folder = scene:call("findFolder(System.String)", folderPath)
        end)
        if not folder then
            local shortName = string.match(folderPath, "([^/]+)$")
            if shortName then
                pcall(function()
                    folder = scene:call("findFolder(System.String)", shortName)
                end)
            end
        end
    end

    local names = world_file_name_candidates(objectName, fileId)
    for _, name in ipairs(names) do
        local gameObject = nil
        if folder then
            pcall(function()
                gameObject = scene:call(
                    "findGameObject(System.String, via.Folder)",
                    name,
                    folder
                )
            end)
        end
        -- Quiet indicator lookups with a resolved folder must not fall back to
        -- a same-named GO elsewhere (wrong transform / far standby instance).
        if not gameObject and (not folder or activateFolder) then
            pcall(function()
                gameObject = scene:call("findGameObject(System.String)", name)
            end)
        end
        if gameObject then
            return gameObject, name
        end
    end

    return nil
end

local function find_world_file_object(scene, objectName, folderPath, fileId)
    -- scene arg kept for call-site compatibility; FindWorldObject resolves it.
    return Files.FindWorldObject(objectName, folderPath, fileId, true)
end

function Files.QueueWorldRevive(fileId)
    fileId = tonumber(fileId)
    if not fileId or not Files.IsEnabled() then
        return
    end

    local location = Files.GetLocation(fileId)
    if not location then
        return
    end
    -- Already examined in-world — do not bring the prop back.
    if Files.IsWorldCheckDone(fileId) then
        return
    end

    local objectName = location.item_object
    if (not objectName or objectName == "") and location.file_id then
        objectName = location.file_id
    end
    if not objectName or objectName == "" then
        return
    end

    -- Ownership from an earlier AP getFile keeps re-retiring the prop.
    Files.ClearVanillaOwnership(fileId)
    Files.worldRevived[objectName] = nil
    Files.pendingWorldRevives[fileId] = {
        objectName = objectName,
        folderPath = location.folder_path or "",
    }
end

local function audit_extract_file_id(value)
    if value == nil then
        return nil
    end
    if type(value) == "number" then
        return value
    end

    local number = tonumber(value)
    if number ~= nil then
        return number
    end

    -- Enum values stringify as "Mes_File_13(13)".
    local inner = string.match(tostring(value), "%((%-?%d+)%)")
    return inner and tonumber(inner) or tonumber(tostring(value))
end

local function each_live_file_settings(scene, fn)
    local components = nil
    pcall(function()
        components = scene:call(
            "findComponents(System.Type)",
            sdk.typeof(sdk.game_namespace("gimmick.option.EsFileGetSettings"))
        )
    end)
    if not components then
        return
    end

    if components.get_elements then
        local elements = nil
        pcall(function()
            elements = components:get_elements()
        end)
        if elements then
            for _, component in pairs(elements) do
                if component ~= nil then
                    pcall(fn, component)
                end
            end
            return
        end
    end

    local size = nil
    pcall(function()
        size = components:get_size()
    end)
    size = tonumber(size)
    if not size or size < 1 then
        return
    end
    if size > 256 then
        size = 256
    end

    for index = 0, size - 1 do
        local component = nil
        pcall(function()
            component = components[index]
        end)
        if component == nil then
            pcall(function()
                component = components:call("get_Item", index)
            end)
        end
        if component ~= nil then
            pcall(fn, component)
        end
    end
end

local function each_settings_file_id(component, fn)
    local settingList = nil
    pcall(function()
        settingList = component:get_field("SettingList")
    end)
    if not settingList then
        return
    end

    local function handle_param(param)
        if not param then
            return
        end

        local fileIdList = nil
        pcall(function()
            fileIdList = param:get_field("FileIdList")
        end)
        if not fileIdList then
            return
        end

        local count = 0
        pcall(function()
            count = fileIdList:call("get_Count") or 0
        end)

        for index = 0, count - 1 do
            local raw = nil
            pcall(function()
                raw = fileIdList:call("get_Item", index)
            end)
            local fileId = audit_extract_file_id(raw)
            if fileId then
                fn(fileId)
            end
        end
    end

    if settingList.get_elements then
        local elements = nil
        pcall(function()
            elements = settingList:get_elements()
        end)
        if elements then
            for _, param in pairs(elements) do
                handle_param(param)
            end
            return
        end
    end

    -- Param[] native array, then the List-like shape as a fallback.
    local length = nil
    pcall(function()
        length = settingList:get_size()
    end)
    length = tonumber(length)

    if length and length > 0 then
        for index = 0, math.min(length, 16) - 1 do
            local param = nil
            pcall(function()
                param = settingList[index]
            end)
            if param == nil then
                pcall(function()
                    param = settingList:call("GetValue", index)
                end)
            end
            handle_param(param)
        end
        return
    end

    local count = nil
    pcall(function()
        count = settingList:call("get_Count")
    end)
    count = tonumber(count)

    if count and count > 0 then
        for index = 0, math.min(count, 16) - 1 do
            local param = nil
            pcall(function()
                param = settingList:call("get_Item", index)
            end)
            handle_param(param)
        end
    end
end

-- Read-only record of which AP file props the game actually has loaded. We no
-- longer touch files we were never sent, so without this a document that simply
-- never spawns leaves no trace at all.
function Files.AuditLoadedFileProps(mapKey)
    local scene = Scene.getSceneObject()
    if not scene then
        return
    end

    local present = {}
    each_live_file_settings(scene, function(component)
        each_settings_file_id(component, function(fileId)
            local location = Files.GetLocation(fileId)
            if location and not Files.IsWorldCheckDone(fileId) then
                present[fileId] = true
            end
        end)
    end)

    local ids = {}
    for fileId in pairs(present) do
        table.insert(ids, fileId)
    end
    table.sort(ids)

    log.info(
        "[Randomizer] Map "
        .. tostring(mapKey)
        .. " unchecked file props loaded: "
        .. (#ids > 0 and table.concat(ids, ", ") or "none")
    )
end

-- Vanilla ownership is what convinces the world a document is spent. Only the
-- received files get the full revive treatment, but any file we have not
-- checked yet should still read as unowned so the game keeps building its prop.
-- This is a flag write per file, so it is cheap enough to redo on every map.
function Files.ClearOwnershipForUncheckedFiles()
    for _, location in pairs(Lookups.files or {}) do
        local fileId = tonumber(string.match(tostring(location.file_id or ""), "(%d+)$"))
        if fileId and not Files.IsWorldCheckDone(fileId) then
            Files.ClearVanillaOwnership(fileId)
        end
    end
end

function Files.QueueAllReceivedWorldRevives()
    for fileIdNameValue, received in pairs(Storage.receivedFiles or {}) do
        if received then
            local fileId = tonumber(string.match(fileIdNameValue, "(%d+)$"))
            if fileId then
                Files.QueueWorldRevive(fileId)
            end
        end
    end
end

function Files.ProcessPendingWorldRevives()
    if not Archipelago.hasConnectedPrior or not Files.IsEnabled() then
        return
    end

    local scene = Scene.getSceneObject()
    if not scene then
        return
    end

    if Files.reviveScene ~= scene then
        Files.reviveScene = scene
        Files.trackedWorldFiles = {}
        Files.reviveSearchBackoff = {}
    end

    local now = os.clock()

    for fileId, pending in pairs(Files.pendingWorldRevives) do
        if Files.IsWorldCheckDone(fileId) then
            Files.pendingWorldRevives[fileId] = nil
            Files.trackedWorldFiles[fileId] = nil
        else
            -- Legacy pending entries were a bare object-name string.
            local objectName = pending
            local folderPath = nil
            if type(pending) == "table" then
                objectName = pending.objectName
                folderPath = pending.folderPath
            end

            -- Rooms stream in and out, so a resolved prop can be destroyed and
            -- rebuilt. Reuse the handle while it lasts and re-scan when it dies.
            local tracked = Files.trackedWorldFiles[fileId]
            local gameObject = tracked and tracked.gameObject
            local resolvedName = tracked and tracked.name
            local stillValid = false

            if gameObject then
                pcall(function()
                    stillValid = gameObject:call("get_Valid()") == true
                end)
            end

            if not stillValid then
                gameObject, resolvedName = nil, nil
                Files.trackedWorldFiles[fileId] = nil

                -- Most of the queue belongs to areas that are nowhere near the
                -- player, and the name search walks the whole scene. Back those
                -- off so the tick only pays for props that can actually appear.
                local backoff = Files.reviveSearchBackoff[fileId]
                if not backoff or now >= backoff.nextAt then
                    gameObject, resolvedName = find_world_file_object(
                        scene,
                        objectName,
                        folderPath,
                        fileId
                    )

                    if gameObject then
                        Files.reviveSearchBackoff[fileId] = nil
                        Files.trackedWorldFiles[fileId] =
                            { gameObject = gameObject, name = resolvedName }
                    else
                        local attempts = (backoff and backoff.attempts or 0) + 1
                        Files.reviveSearchBackoff[fileId] = {
                            attempts = attempts,
                            nextAt = now + math.min(2 ^ attempts, 30)
                        }
                    end
                end
            end

            local entry = Files.trackedWorldFiles[fileId]
            local throttled = entry
                and entry.lastAttempt
                and (now - entry.lastAttempt) < 5

            if gameObject and not throttled and not world_object_is_live(gameObject) then
                local key = resolvedName or objectName
                if entry then
                    entry.lastAttempt = now
                end
                Files.ClearVanillaOwnership(fileId)

                if revive_world_file_object(gameObject) then
                    if not Files.worldRevived[key] then
                        Files.worldRevived[key] = true
                        log.info("[Randomizer] Re-activated world file " .. tostring(key))
                    end
                else
                    -- Keep it queued: the prop is still unreachable, and whatever
                    -- is holding it down needs to show up in the log.
                    Files.worldRevived[key] = nil
                    if not Files.reviveFailureLogged[key] then
                        Files.reviveFailureLogged[key] = true
                        log.info(
                            "[Randomizer] World file "
                            .. tostring(key)
                            .. " still not reachable: "
                            .. describe_world_object(gameObject)
                        )
                    end
                end
            end
        end
    end
end

local function has_pending_world_revives()
    for _ in pairs(Files.pendingWorldRevives) do
        return true
    end
    return false
end

-- new rooms bring in new File_* props — re-queue anything still unchecked
function Files.RefreshWorldFileRevivesOnMapChange()
    if not Archipelago.hasConnectedPrior or not Files.IsEnabled() then
        return
    end
    if Scene and Scene.isTransitioning and Scene.isTransitioning() then
        return
    end

    local mapManager = sdk.get_managed_singleton(sdk.game_namespace("gamemastering.UIMapManager"))
    if not mapManager then
        return
    end

    local mapId = nil
    pcall(function()
        mapId = mapManager:call("get_SceneMapId")
    end)
    if mapId == nil then
        return
    end

    if Files.pendingAuditAt and os.clock() >= Files.pendingAuditAt then
        local auditMapKey = Files.pendingAuditMapKey
        Files.pendingAuditAt = nil
        Files.pendingAuditMapKey = nil
        Files.AuditLoadedFileProps(auditMapKey)
    end

    local mapKey = tostring(mapId)
    if Files.lastReviveMapId ~= mapKey then
        Files.lastReviveMapId = mapKey
        Files.worldRevived = {}
        Files.reviveFailureLogged = {}
        -- A new map means props that were unreachable a moment ago may exist now.
        Files.reviveSearchBackoff = {}
        Files.trackedWorldFiles = {}
        Files.ClearOwnershipForUncheckedFiles()
        Files.QueueAllReceivedWorldRevives()
        log.info("[Randomizer] File world-revive pass for map " .. mapKey)
        Files.ProcessPendingWorldRevives()
        -- Props keep spawning for a while after the map id flips, so auditing
        -- right now would just report an empty room every time.
        Files.pendingAuditMapKey = mapKey
        Files.pendingAuditAt = os.clock() + 5
        Files.lastPendingReviveProcess = os.clock()
        return
    end

    -- Props often spawn a moment after the map id flips; retry pending finds
    -- on a short interval instead of scanning the scene every frame.
    if not has_pending_world_revives() then
        return
    end

    local now = os.clock()
    if (now - (Files.lastPendingReviveProcess or 0)) < (Files.pendingReviveInterval or 2.0) then
        return
    end

    Files.lastPendingReviveProcess = now
    Files.ProcessPendingWorldRevives()
end

function Files.RebuildFileObjectNames()
    Files.fileObjectNames = {}

    for _, location in pairs(Lookups.files or {}) do
        if location.item_object and location.item_object ~= "" then
            Files.fileObjectNames[location.item_object] = true
        end
    end

    Files.colliderRefreshNeeded = true
end

function Files.RefreshPhysicalFileColliders()
    if not Archipelago.hasConnectedPrior or not Files.IsEnabled() then
        return
    end

    local scene = Scene.getSceneObject()
    if not scene then
        return
    end

    if Files.colliderScene ~= scene then
        Files.colliderScene = scene
        Files.fileColliders = {}
        Files.colliderRefreshNeeded = true
    end

    if not Files.colliderRefreshNeeded then
        return
    end
    Files.colliderRefreshNeeded = false

    local shouldBlock = Archipelago.pickupsBlocked
    for objectName, _ in pairs(Files.fileObjectNames) do
        local gameObject = scene:call(
            "findGameObject(System.String)",
            objectName
        )
        local colliders = gameObject and gameObject:call(
            "getComponent(System.Type)",
            sdk.typeof("via.physics.Colliders")
        )

        if colliders then
            local beforeEnabled = colliders:call("get_Enabled()") == true
            local state = Files.fileColliders[colliders]
            if not state then
                state = {
                    originalEnabled = beforeEnabled,
                    blocked = false
                }
                Files.fileColliders[colliders] = state
            end

            if shouldBlock and not state.blocked then
                colliders:call("set_Enabled(System.Boolean)", false)
                state.blocked = true
            elseif not shouldBlock and state.blocked then
                colliders:call(
                    "set_Enabled(System.Boolean)",
                    state.originalEnabled
                )
                state.blocked = false
            end
        end
    end
end

function Files.HasFile(fileId)
    local manager = get_manager()
    if not manager then
        return false
    end

    local ok, result = pcall(function()
        local location = manager:call("getFileLocation", tonumber(fileId))
        if location == nil then
            return false
        end
        return manager:call("hasFile", tonumber(fileId), location) == true
    end)

    return ok and result or false
end

-- Hand over a map we held back when the document was examined in-world.
local function grant_deferred_map(fileId)
    local key = file_id_name(fileId)
    local itemId = Storage.deferredMapItems and Storage.deferredMapItems[key]
    if not itemId then
        return
    end

    local mapManager = sdk.get_managed_singleton(
        sdk.game_namespace("gamemastering.UIMapManager")
    )
    if not mapManager then
        return
    end

    Files.applyingReceivedFile = true
    pcall(function()
        mapManager:call("getMap", itemId)
    end)
    Files.applyingReceivedFile = false

    Storage.deferredMapItems[key] = nil
    Storage.Update()

    log.info("[Randomizer] Granted held map for " .. key)
end

function Files.ApplyReceivedFile(item)
    if not item or not item.file_id then
        return false
    end

    local fileId = tonumber(string.match(item.file_id, "(%d+)$"))
    if not fileId then
        return false
    end

    Storage.receivedFiles[item.file_id] = true
    Storage.Update()

    grant_deferred_map(fileId)

    -- World location already collected: menu ownership is faked by the hasFile / getFileVariableData hooks. 
    -- Do not getFile again — that reloads / re-retires the document
    if Files.IsWorldCheckDone(fileId) then

        local manager = get_manager()

        if manager then
            Files.applyingReceivedFile = true
            pcall(function()
                manager:call("readFile", fileId)
            end)
            Files.applyingReceivedFile = false
        end

        return true
    end

    -- Still need the world prop examinable so the location can be checked.
    Files.ClearVanillaOwnership(fileId)
    Files.QueueWorldRevive(fileId)
    Files.ProcessPendingWorldRevives()

    -- Mark read for UI "new" flags without calling getFile.
    local manager = get_manager()

    if manager then
        Files.applyingReceivedFile = true
        pcall(function()
            manager:call("readFile", fileId)
        end)
        Files.applyingReceivedFile = false
    end

    return true
end

-- The Files tab is populated by telling the game we own AP-received files. The
-- world side asks the same manager when it decides whether to build a file prop,
-- so answering "owned" everywhere deletes the check before the player can reach
-- it. Only claim ownership while a menu is actually on screen.
-- These lookups get hit far more often than once a frame, so the answer is
-- cached for a slice of a frame rather than re-queried per call.
function Files.IsMenuContext()
    local now = os.clock()
    if Files.menuContextCheckedAt and (now - Files.menuContextCheckedAt) < 0.05 then
        return Files.menuContextCached
    end

    local gui = sdk.get_managed_singleton(sdk.game_namespace("gui.GUIMaster"))
    local open = false

    if gui then
        pcall(function()
            open = gui:call("get_IsOpenInventory()") == true
                or gui:call("get_IsOpenFile()") == true
                or gui:call("isBusyFile()") == true
        end)
    end

    Files.menuContextCheckedAt = now
    Files.menuContextCached = open
    return open
end

function Files.ShouldReportOwned(fileId)
    if not Files.IsEnabled() or not Files.IsReceivedFileId(fileId) then
        return false
    end

    return Files.IsMenuContext()
end

function Files.SetupOwnedLookupHooks(managerType)
    if Files.ownedLookupHooksInstalled then
        return
    end

    Files.ownedLookupHooksInstalled = true

    local getVar = managerType:get_method("getFileVariableData")

    if getVar then
        sdk.hook(getVar, function(args)
            Files.pendingOwnedLookupFileId = sdk.to_int64(args[3])
        end, function(retval)

            local fileId = Files.pendingOwnedLookupFileId
            Files.pendingOwnedLookupFileId = nil
            if Files.ShouldReportOwned(fileId) then
                return sdk.to_ptr(true)
            end
            return retval
        end)
    end

    local hasFile = managerType:get_method("hasFile")
    if hasFile then
        sdk.hook(hasFile, function(args)
            Files.pendingHasFileId = sdk.to_int64(args[3])
            Files.pendingHasFileLoc = sdk.to_int64(args[4])
        end, function(retval)
            local fileId = Files.pendingHasFileId
            local loc = Files.pendingHasFileLoc
            Files.pendingHasFileId = nil
            Files.pendingHasFileLoc = nil

            if not Files.ShouldReportOwned(fileId) then
                return retval
            end

            local resolved = Files.ResolveFileLocationId(fileId)
            if resolved ~= nil and tonumber(resolved) == tonumber(loc) then
                return sdk.to_ptr(true)
            end

            return retval
        end)
    end

    local hasFileList = managerType:get_method("hasFileList")
    if hasFileList then
        sdk.hook(hasFileList, function(args)
            Files.pendingHasFileListLoc = sdk.to_int64(args[3])
        end, function(retval)
            local loc = Files.pendingHasFileListLoc
            Files.pendingHasFileListLoc = nil

            if not Files.IsEnabled() or loc == nil then
                return retval
            end

            for fileIdNameValue, received in pairs(Storage.receivedFiles or {}) do
                if received then
                    local fileId = tonumber(string.match(fileIdNameValue, "(%d+)$"))
                    if fileId and Files.ShouldReportOwned(fileId) then
                        local resolved = Files.ResolveFileLocationId(fileId)
                        if resolved ~= nil and tonumber(resolved) == tonumber(loc) then
                            return sdk.to_ptr(true)
                        end
                    end
                end
            end

            return retval
        end)
    end
end

local function intercept_physical_file(fileId)
    if not Files.CanCheck() or Files.applyingReceivedFile then
        return false
    end

    local location = Files.GetLocation(fileId)
    if not location then
        return false
    end

    -- A checked AP location can reappear after loading an older in-game save.
    -- Retire it silently instead of presenting a misleading duplicate warning.
    local result = Archipelago.SendLocationCheck(
        { file_id = location.file_id },
        false
    )
    if result == nil then
        GUI.AddText("File location did not send. Reconnect and examine it again.")
        return true
    end

    -- result true = newly sent, false = already checked. Either way the
    -- in-world document is done — never revive it on later replays.
    Files.MarkWorldCollected(fileId)

    Files.recentPhysicalChecks[tonumber(fileId)] = os.clock()

    -- Let this first getFile call complete so the game's normal interaction
    -- removes and saves the physical document. We close its viewer and clear
    -- the vanilla ownership flag immediately afterward; only an AP-received
    -- File item remains unlocked in the Files menu.
    fileId = tonumber(fileId)
    Files.suppressedReads[fileId] = os.clock() + 300
    Files.physicalGetFileId = fileId
    return true
end

function Files.SetupHooks()
    local managerType = sdk.find_type_definition(
        sdk.game_namespace("gamemastering.UIFileManager")
    )
    if not managerType then
        log.error("[Randomizer] Could not find UIFileManager for file checks.")
        return
    end

    Files.SetupOwnedLookupHooks(managerType)

    -- Physical acquisition was verified to call getFile. Do not hook readFile:
    -- that method is also used when opening an already-owned file from menus.
    for _, methodName in ipairs({ "getFile" }) do
        local hookedMethodName = methodName
        local method = managerType:get_method(hookedMethodName)
        if method then
            sdk.hook(method, function(args)
                if Files.applyingReceivedFile then
                    return
                end

                local fileId = sdk.to_int64(args[3])
                if not Files.IsEnabled() then
                    log.info(
                        "[Randomizer] File API: "
                        .. hookedMethodName
                        .. " "
                        .. file_id_name(fileId)
                    )
                    return
                end

                if not Archipelago.IsConnected() then
                    Files.WarnDisconnected()
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end
                local suppressUntil = Files.suppressedReads[fileId]

                if suppressUntil and suppressUntil >= os.clock() then
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end

                Files.suppressedReads[fileId] = nil
                if intercept_physical_file(fileId) then
                    -- The native call makes the world pickup disappear and
                    -- records that disappearance in the game save.
                    return
                end
            end, function(retval)
                local fileId = Files.physicalGetFileId
                if fileId then
                    Files.physicalGetFileId = nil
                    Files.pendingPhysicalFile = {
                        id = fileId,
                        startedAt = os.clock(),
                        expiresAt = os.clock() + 3
                    }
                end

                return retval
            end)
        else
            log.error("[Randomizer] Could not hook UIFileManager." .. methodName .. ".")
        end
    end

    -- Maps are their own Item.ID grant, nothing to do with UIFileManager, so
    -- the file interception never saw this coming. Only the one file carries
    -- one, and only while its pickup is still in flight.
    local mapType = sdk.find_type_definition(
        sdk.game_namespace("gamemastering.UIMapManager")
    )
    local getMapMethod = mapType and mapType:get_method("getMap")

    if getMapMethod then
        sdk.hook(getMapMethod, function(args)
            if not Files.IsEnabled() or Files.applyingReceivedFile then
                return
            end

            local checkedAt = Files.recentPhysicalChecks[Files.mapFileId]
            if not checkedAt
                or os.clock() - checkedAt >= Files.mapGrantWindow
            then
                return
            end

            -- AP already gave us the file, so the map is ours to keep.
            if Files.IsReceivedFileId(Files.mapFileId) then
                return
            end

            -- Remember which map it was so we can hand it over on receipt.
            Storage.deferredMapItems = Storage.deferredMapItems or {}
            Storage.deferredMapItems[file_id_name(Files.mapFileId)] =
                sdk.to_int64(args[3])
            Storage.Update()

            return sdk.PreHookResult.SKIP_ORIGINAL
        end)
    else
        log.error("[Randomizer] Could not hook UIMapManager.getMap.")
    end

    local guiType = sdk.find_type_definition(
        sdk.game_namespace("gui.GUIMaster")
    )
    local openFileMethod = guiType and guiType:get_method("openFile")

    if not openFileMethod then
        log.error("[Randomizer] Could not hook GUIMaster.openFile.")
        return
    end

    -- A physical pickup uses openFile; viewing an owned document from the
    -- Files menu uses openFilePreview. Complete the physical interaction
    -- callbacks without opening the viewer at all.
    sdk.hook(openFileMethod, function(args)
        if not Files.IsEnabled() then
            return
        end

        local fileId = sdk.to_int64(args[3])
        local location = Files.GetLocation(fileId)
        if not location then
            return
        end

        if not Archipelago.IsConnected() then
            Files.WarnDisconnected()
            return
        else
            local recentCheck = Files.recentPhysicalChecks[fileId]
            if not recentCheck or os.clock() - recentCheck >= 2 then
                local result = Archipelago.SendLocationCheck({
                    file_id = location.file_id
                }, false)
                if result == nil then
                    GUI.AddText("File location did not send. Reconnect and examine it again.")
                    Items.cancelNextUI = true
                    Items.cancelNextUIExpires = os.clock() + 3
                    return
                end
                Files.MarkWorldCollected(fileId)
                Files.recentPhysicalChecks[fileId] = os.clock()
            end
        end

        -- Ensure the native acquired state exists long enough for the
        -- interaction's close callback to retire the physical world object.
        local manager = get_manager()
        if manager then
            Files.applyingReceivedFile = true
            pcall(function()
                manager:call("getFile(offline.File.ID)", fileId)
            end)
            Files.applyingReceivedFile = false
        end

        local callbackOnOpened = sdk.to_managed_object(args[6])
        local callbackOnClosed = sdk.to_managed_object(args[7])

        if callbackOnOpened then
            pcall(function()
                callbackOnOpened:call("Invoke()")
            end)
        end
        if callbackOnClosed then
            pcall(function()
                callbackOnClosed:call("Invoke()")
            end)
        end

        Files.suppressedReads[fileId] = os.clock() + 300
        Files.physicalGetFileId = nil
        Files.pendingPhysicalFile = {
            id = fileId,
            startedAt = os.clock(),
            expiresAt = os.clock() + 1,
            viewerSkipped = true
        }

        return sdk.PreHookResult.SKIP_ORIGINAL
    end)
end

function Files.FinishPhysicalFile()
    local pending = Files.pendingPhysicalFile
    if not pending then
        return
    end

    local gui = sdk.get_managed_singleton(
        sdk.game_namespace("gui.GUIMaster")
    )
    local isOpen = false

    if gui then
        pcall(function()
            isOpen = gui:call("get_IsOpenFile()") == true
        end)
    end

    -- Wait until the viewer has actually opened so closeFile can run the
    -- interaction's normal completion callback. That callback is what makes
    -- the physical file vanish cleanly.
    if pending.viewerSkipped then
        if os.clock() - pending.startedAt < 0.1 then
            return
        end
    elseif isOpen and gui then
        local closed = pcall(function()
            gui:call("closeFile(System.Boolean)", false)
        end)

        if not closed then
            return
        end
    elseif os.clock() < pending.expiresAt then
        return
    end

    local manager = get_manager()
    if manager then
        if Files.IsReceivedFileId(pending.id) then
            -- World check is done; now it's safe for getFile to retire the prop.
            Files.WriteVanillaOwnership(pending.id)
        else
            pcall(function()
                manager:call(
                    "setFileVariableData(offline.File.ID, System.Boolean)",
                    pending.id,
                    false
                )
            end)
        end
    end

    Files.pendingPhysicalFile = nil
end

function Files.ReplayReceivedFiles()
    if not Files.needsFileReplay or not Files.CanCheck() then
        return
    end

    local manager = get_manager()
    if not manager then
        return
    end

    Files.needsFileReplay = false

    -- Received files are the ones an earlier getFile could have retired, so they
    -- get the world revive. Everything else unchecked just needs its ownership
    -- flag cleared so the game keeps spawning the prop on its own.
    Files.ClearOwnershipForUncheckedFiles()

    for fileIdNameValue, received in pairs(Storage.receivedFiles or {}) do
        if received then
            local fileId = tonumber(string.match(fileIdNameValue, "(%d+)$"))
            if fileId and not Files.IsWorldCheckDone(fileId) then
                Files.QueueWorldRevive(fileId)
            end
        end
    end

    Files.ProcessPendingWorldRevives()
end

function Files.Init()
    if not Files.isInit then
        Files.isInit = true
        Files.SetupHooks()
    end

    -- Never revive/unlock files during Carlos RPD (or any) scene load.
    -- getFile + world scans here can stall isEndLoadingGameScene on a black screen.
    if Scene and Scene.isTransitioning and Scene.isTransitioning() then
        return
    end

    Files.RefreshPhysicalFileColliders()
    Files.RefreshWorldFileRevivesOnMapChange()
    Files.ReplayReceivedFiles()
end

return Files
