local FixBoxes = {}
FixBoxes.isInit = false
FixBoxes.lastFix = os.time()
FixBoxes.mapMetadataPath = "ArchipelagoRE3R/box_map_data.json"
FixBoxes.mapMetadata = nil
FixBoxes.lastCapture = 0

-- Legacy hard-coded names kept as a fast path. The real fix is FixAllLoaded(),
-- which finds every EsGimmickRandomContainer currently in the scene — including
-- boxes whose object name doesn't match these strings.
local NAMED_BOXES = {
    "st03_0219_sm42_476_ES_BreakBox01_gimmick", -- South Side Breakable Box (Downtown)
    "st03_0216_sm42_476_ES_BreakBox06_gimmick", -- North Side Breakable Box (Downtown)
    "st03_0213_sm42_476_ES_BreakBox05_gimmick", -- Rooftop Breakable Box (Downtown)
    "st03_0226_sm42_476_ES_BreakBox10_gimmick", -- Substation Street Breakable Box (Downtown)
    "st03_0402_sm42_476_ES_BreakBox12_gimmick", -- Before Power Maze Breakable Box (Downtown)
    "st03_0402_sm42_476_ES_BreakBox14_gimmick", -- Power Maze Breakable Box (Downtown)
    "st03_0611_sm42_476_ES_BreakBox16_gimmick", -- Northwest Tunnel Breakable Box (Sewers)
    "st02_0217_sm42_476_ES_BreakableVLongBox01A_00_gimmick", -- West Hallway 1F (RPD)
    "st02_217_sm42_476_ES_BreakableVLongBox0A_00_gimmick",
    "st02_217_sm42_476_ES_BreakableVLongBox01A_00_gimmick",
    -- West Hallway 3F — live name uses short map id + 0A (not 01A).
    "st02_603_sm42_476_ES_BreakableVLongBox0A_00_gimmick",
    "st02_0603_sm42_476_ES_BreakableVLongBox0A_00_gimmick",
    "st02_0603_sm42_476_ES_BreakableVLongBox01A_00_gimmick",
    "st02_0603_sm42_476_ES_BreakableVLongBox01A_gimmick",
    -- STARS Hallway / West Hallway 2F — try short + long + 0A/01A.
    "st2_0412_sm42_476_ES_BreakableVLongBox01A_00_gimmick",
    "st02_0412_sm42_476_ES_BreakableVLongBox01A_00_gimmick",
    "st02_0412_sm42_476_ES_BreakableVLongBox0A_00_gimmick",
    "st02_412_sm42_476_ES_BreakableVLongBox0A_00_gimmick",
    "st02_412_sm42_476_ES_BreakableVLongBox01A_00_gimmick",
    "st2_0412_sm42_476_ES_BreakableVLongBox0A_00_gimmick",
    "st03_0804_sm42_476_ES_BreakableVLongBox01A_gimmick", -- Promenade (Clock Tower)
    "St04_0107_0_ES_BreakBox10", -- Near Operating Room (Hospital)
    "St04_0107_0_ES_BreakBox10_01", -- Near Locker (Hospital)
    "sm42_476_Break_box_Lobby1", -- Near Makeshift Sickroom as Jill (Hospital)
    "sm42_476_Break_box_Lobby2",
    "sm42_476_Break Box 1", -- Before Underground Storage as Jill (Hospital)
    "sm42_476_Break Box 10",
    "sm42_476_Break Box 20",
    "st05_0104_sm42_476_ES_BreakableVLongBox01A_00_gimmick", -- Laboratory Hallway 2F
    "st05_0202_sm42_476_ES_BreakableVLongBox01A_00_gimmick", -- Worker's Break Room
}

local function eachArrayElement(arr, fn)
    if arr == nil then
        return 0
    end

    local n = 0

    if arr.get_elements then
        local elements = nil
        pcall(function()
            elements = arr:get_elements()
        end)
        if elements then
            for _, item in pairs(elements) do
                if item ~= nil then
                    fn(item)
                    n = n + 1
                end
            end
            if n > 0 then
                return n
            end
        end
    end

    local size = nil
    pcall(function()
        size = arr:get_size()
    end)
    if size == nil then
        pcall(function()
            size = arr:call("get_size")
        end)
    end
    if size == nil then
        pcall(function()
            size = arr:call("get_Count")
        end)
    end
    size = tonumber(size)

    if size and size > 0 then
        for i = 0, size - 1 do
            local item = nil
            pcall(function()
                item = arr[i]
            end)
            if item == nil then
                pcall(function()
                    item = arr:call("get_Item", i)
                end)
            end
            if item ~= nil then
                fn(item)
                n = n + 1
            end
        end
    end

    return n
end

local function fixContainer(comp)
    if comp == nil then
        return false
    end

    local changed = false

    -- Field is fixItem; accessors are get_FixItem / set_FixItem.
    -- Don't use set_field("FixItem") — REFramework logs that even inside pcall.
    local alreadyFixed = false
    pcall(function()
        alreadyFixed = comp:call("get_FixItem") == true
    end)

    if not alreadyFixed then
        local ok = pcall(function()
            comp:call("set_FixItem", true)
        end)
        if not ok then
            -- Fallback for builds where only the raw field works
            pcall(function()
                comp:set_field("fixItem", true)
            end)
        end
        changed = true
    end

    -- Un-hide / re-enable hit if the gimmick got stuck inactive mid-seed.
    pcall(function()
        if comp:call("get_IsHide") == true then
            comp:call("set_IsHide", false)
            changed = true
        end
    end)
    pcall(function()
        if comp:call("get_Enabled") == false then
            comp:call("set_Enabled", true)
            changed = true
        end
    end)

    return changed
end

local function getListCount(list)
    if not list then
        return 0
    end
    local count = nil
    pcall(function()
        count = list:call("get_Count")
    end)
    return tonumber(count) or 0
end

local function getListItem(list, index)
    if not list then
        return nil
    end
    local item = nil
    local ok = pcall(function()
        item = list:call("get_Item", index)
    end)
    return ok and item or nil
end

local function guidString(guid)
    if not guid then
        return ""
    end
    if Storage and Storage.GetGuidString then
        return string.lower(Storage.GetGuidString(guid) or "")
    end
    return string.lower(tostring(guid) or "")
end

local function loadMapMetadata()
    if FixBoxes.mapMetadata ~= nil then
        return
    end
    FixBoxes.mapMetadata = json.load_file(FixBoxes.mapMetadataPath) or {}
end

local function findLocationByItemGuid(itemGuid)
    if not itemGuid or itemGuid == "" then
        return nil
    end
    local needle = string.lower(tostring(itemGuid))
    for _, location in pairs(Lookups.locations or {}) do
        if location.object_guid
            and string.lower(tostring(location.object_guid)) == needle
        then
            return location
        end
    end
    return nil
end

local function getBoxItemGuid(comp)
    local itemGuid = ""
    pcall(function()
        local itemPositions = comp:call("get_generatedItemPositions")
        if itemPositions then
            itemGuid = guidString(itemPositions:get_field("MyGuid"))
        end
    end)
    return itemGuid
end

-- Collect-only: write hash/map/pos/guid into box_map_data.json for later map icons.
-- Does not register icons on the map.
function FixBoxes.CaptureMapData()
    if os.clock() - FixBoxes.lastCapture < 1.5 then
        return
    end
    FixBoxes.lastCapture = os.clock()
    loadMapMetadata()

    local changed = false
    local mapManager = sdk.get_managed_singleton(
        sdk.game_namespace("gamemastering.UIMapManager")
    )

    -- Prefer native gimmick registrations (fired when you walk by / contact).
    if mapManager then
        local gimmickData = nil
        pcall(function()
            gimmickData = mapManager:call("get_getGimmickData")
        end)
        for index = 0, getListCount(gimmickData) - 1 do
            local info = getListItem(gimmickData, index)
            local hash = info and tonumber(info:call("get_Hash"))
            if hash then
                local key = tostring(hash)
                local record = FixBoxes.mapMetadata[key] or {}
                local position = info:call("get_Position")
                local mapId = tonumber(info:call("get_MapId"))
                local msgId = info:call("get_MsgId")

                if record.hash ~= hash
                    or record.map ~= mapId
                    or (position and (
                        record.x ~= position.x
                        or record.y ~= position.y
                        or record.z ~= position.z
                    ))
                then
                    record.hash = hash
                    record.map = mapId
                    if position then
                        record.x, record.y, record.z = position.x, position.y, position.z
                    end
                    changed = true
                end

                if msgId and Storage and Storage.GetGuidString then
                    local msgGuid = guidString(msgId)
                    if msgGuid ~= "" then
                        FixBoxes.mapMetadata._meta = FixBoxes.mapMetadata._meta or {}
                        if FixBoxes.mapMetadata._meta.msg_guid ~= msgGuid then
                            FixBoxes.mapMetadata._meta.msg_guid = msgGuid
                            changed = true
                        end
                    end
                end

                FixBoxes.mapMetadata[key] = record
            end
        end
    end

    -- Match live boxes to hashes so we can attach item_guid / location names.
    local scene = Scene and Scene.getSceneObject and Scene.getSceneObject()
    if scene then
        local comps = nil
        pcall(function()
            comps = scene:call(
                "findComponents(System.Type)",
                sdk.typeof(sdk.game_namespace(
                    "escape.gimmick.action.EsGimmickRandomContainer"
                ))
            )
        end)
        eachArrayElement(comps, function(comp)
            local messenger = nil
            local hash = nil
            pcall(function()
                messenger = comp:call("get_gimmickIconMessenger")
                hash = messenger and tonumber(messenger:get_field("Hash"))
            end)
            if not hash then
                return
            end

            local key = tostring(hash)
            local record = FixBoxes.mapMetadata[key] or { hash = hash }
            local itemGuid = getBoxItemGuid(comp)
            if itemGuid ~= "" and record.item_guid ~= itemGuid then
                record.item_guid = itemGuid
                changed = true
                local location = findLocationByItemGuid(itemGuid)
                if location then
                    if record.region ~= location.region then
                        record.region = location.region
                        changed = true
                    end
                    if record.location_name ~= location.name then
                        record.location_name = location.name
                        changed = true
                    end
                end
            end

            -- If this box isn't in the gimmick list yet, still store transform + hash.
            if record.x == nil then
                pcall(function()
                    local go = comp:call("get_GameObject")
                    local t = go and go:call("get_Transform")
                    local p = t and t:call("get_Position")
                    if p then
                        record.x, record.y, record.z = p.x, p.y, p.z
                        changed = true
                    end
                end)
            end

            FixBoxes.mapMetadata[key] = record
        end)
    end

    if changed then
        pcall(function()
            json.dump_file(FixBoxes.mapMetadataPath, FixBoxes.mapMetadata)
        end)
    end
end

function FixBoxes.Init()
    if Archipelago.IsConnected() and not FixBoxes.isInit then
        FixBoxes.isInit = true
        FixBoxes.FixAll()
    end

    -- Re-run periodically so newly streamed room boxes get FixItem too.
    if os.time() - FixBoxes.lastFix > 10 then
        FixBoxes.isInit = false
        FixBoxes.lastFix = os.time()
    end

    if Archipelago.IsConnected() and Scene and Scene.isInGame and Scene:isInGame() then
        FixBoxes.CaptureMapData()
    end
end

function FixBoxes.Finally(boxName)
    local boxObject = Helpers.gameObject(boxName)
    if boxObject == nil then
        return false
    end

    local boxComponent = Helpers.component(
        boxObject,
        "escape.gimmick.action.EsGimmickRandomContainer"
    )
    if boxComponent == nil then
        return false
    end

    fixContainer(boxComponent)
    return true
end

-- Set FixItem on every breakable-box container currently loaded.
-- This covers misnamed / unlisted boxes (e.g. West Hallway 3F / STARS Hallway).
function FixBoxes.FixAllLoaded()
    local scene = Scene and Scene.getSceneObject and Scene.getSceneObject()
    if not scene then
        return 0
    end

    local comps = nil
    pcall(function()
        comps = scene:call(
            "findComponents(System.Type)",
            sdk.typeof(sdk.game_namespace("escape.gimmick.action.EsGimmickRandomContainer"))
        )
    end)
    if comps == nil then
        return 0
    end

    local fixed = 0
    eachArrayElement(comps, function(comp)
        if fixContainer(comp) then
            fixed = fixed + 1
        end
    end)

    return fixed
end

function FixBoxes.FixAll()
    FixBoxes.lastFix = os.time()

    for _, boxName in ipairs(NAMED_BOXES) do
        FixBoxes.Finally(boxName)
    end

    FixBoxes.FixAllLoaded()
end

-- Kept so map-icon code can call them safely.
function FixBoxes.RefreshMapIcons()
end

function FixBoxes.RemoveMapIconForItemPositions(itemPositions)
end

return FixBoxes
