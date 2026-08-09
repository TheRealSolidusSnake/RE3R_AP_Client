local CutsceneObjects = {}
CutsceneObjects.isInit = false
CutsceneObjects.lastStop = os.time()
CutsceneObjects.clockWasPresent = false
CutsceneObjects.clockNeedsLoadClose = false
CutsceneObjects.clockHooksReady = false
CutsceneObjects.clockFollowUpAt = 0

-- EsGimmickJewelryBox.RNO_CLOSE seems to be the only way to maintain a closed clock puzzle door
-- I tried a bunch of different shit, but the first thing ended up being the best in the long run
local CLOCK_RNO_CLOSE = 5
local CLOCK_OBJECT_NAME = "0201_sm41_415_ES_JewelryBox01A_00_gimmick"
-- One delayed re-close after jewel vanish 
local CLOCK_FOLLOW_UP_SECONDS = 0.5

-- The old way of grabbing the Lock Pick wasn't good enough
-- The map would stay red because of the linked ItemPositions (sm73_304) MapClearing plus gimmick icons on EV322/EV325.
-- Disabling AddItem alone leaves the room red, we don't want that because of the new in-game map tracker
local LOCKPICK_ITEM_OBJECT = "EventPlay_EV322_k"
local LOCKPICK_MAP_OBJECT = "EventPlay_EV325_obj"
local LOCKPICK_FOLDER =
    "RopewayContents/World/Location_DownTown/LocationLevel_DownTown/Scenario/S03_1000/ES_S03_1000"

-- The RPD in general sucks ass in terms of randomizing items
-- but we can at least randomize the Electronic Gadget without triggers breaking
-- but vanishing/cancelling the pickup kills the place interact 
-- so let vanilla finish then strip it from our inventory immediately
local ELECTRONIC_GADGET_ITEM_ID = 165
local SHOWER_WALL_GADGET_OBJECT = "sm73_204"
local SHOWER_WALL_FOLDER =
    "RopewayContents/World/Location_RPD/LocationLevel_RPD/Scenario/S02_0300/ES_S02_0300/ShowerRoomBlownUp"

CutsceneObjects.pendingStripElectronicGadget = false
CutsceneObjects.pendingStripElectronicGadgetUntil = 0
CutsceneObjects.stripElectronicGadgetToCount = 0

local function getElectronicGadgetCount()
    local count = 0
    pcall(function()
        local inventoryManager = sdk.get_managed_singleton(sdk.game_namespace("gamemastering.InventoryManager"))
        if inventoryManager ~= nil then
            count = inventoryManager:call("getItemCount", ELECTRONIC_GADGET_ITEM_ID) or 0
        end
    end)
    return count
end

function CutsceneObjects.IsShowerWallGadget(itemName, folderPath)
    return itemName == SHOWER_WALL_GADGET_OBJECT and folderPath == SHOWER_WALL_FOLDER
end

function CutsceneObjects.BeginShowerWallGadgetStrip()
    Storage.rpdShowerWallChecked = true
    Storage.Update()
    CutsceneObjects.stripElectronicGadgetToCount = getElectronicGadgetCount()
    CutsceneObjects.pendingStripElectronicGadget = true
    CutsceneObjects.pendingStripElectronicGadgetUntil = os.clock() + 10
end

function CutsceneObjects.HandleShowerWallGadgetStrip()
    if not CutsceneObjects.pendingStripElectronicGadget then
        return
    end

    local count = getElectronicGadgetCount()
    local target = CutsceneObjects.stripElectronicGadgetToCount or 0

    if count > target then
        pcall(function()
            local inventoryManager = sdk.get_managed_singleton(sdk.game_namespace("gamemastering.InventoryManager"))
            if inventoryManager ~= nil then
                inventoryManager:call("reduceItem", ELECTRONIC_GADGET_ITEM_ID, count - target)
            end
        end)
        CutsceneObjects.pendingStripElectronicGadget = false
        log.info("[Randomizer] Stripped Electronic Gadget after Shower Wall check")
        return
    end

    if os.clock() >= CutsceneObjects.pendingStripElectronicGadgetUntil then
        CutsceneObjects.pendingStripElectronicGadget = false
    end
end

function CutsceneObjects.Init()
    if Archipelago.IsConnected() and not CutsceneObjects.isInit then
        CutsceneObjects.isInit = true
        CutsceneObjects.lastStop = os.time()
        CutsceneObjects.Shotgun()
        CutsceneObjects.Lockpick()
        CutsceneObjects.OverrideKey()
        CutsceneObjects.CultureSample()
        CutsceneObjects.SetupClockPuzzleHook()
    end

    CutsceneObjects.HandleShowerWallGadgetStrip()

    local present = Helpers.gameObject(CLOCK_OBJECT_NAME) ~= nil

    if not present then
        CutsceneObjects.clockWasPresent = false
    elseif Storage and Storage.clockDoorFixed and not CutsceneObjects.clockWasPresent then
        CutsceneObjects.clockWasPresent = true
        CutsceneObjects.clockNeedsLoadClose = true
        CutsceneObjects.ClockPuzzle()
    elseif present then
        CutsceneObjects.clockWasPresent = true
    end

    -- Single follow-up close after a jewel take, once the vanish settles.
    if CutsceneObjects.clockFollowUpAt > 0
        and os.clock() >= CutsceneObjects.clockFollowUpAt
    then
        CutsceneObjects.clockFollowUpAt = 0
        CutsceneObjects.ClockPuzzle()
    end

    -- Re-scan cutscene objects every 5s (must bump lastStop or after the first timeout we hard-crash on nil components).
    if os.time() - CutsceneObjects.lastStop > 5 then
        CutsceneObjects.isInit = false
        CutsceneObjects.lastStop = os.time()
    end
end

function CutsceneObjects.ClockPuzzle()
    local clockObject = Helpers.gameObject(CLOCK_OBJECT_NAME)
    if not clockObject then
        return false
    end

    local clockComponent = Helpers.component(clockObject, "gimmick.action.EsGimmickJewelryBox")
    if not clockComponent then
        return false
    end

    local ok, currentRno = pcall(function()
        return clockComponent:get_field("_Rno")
    end)
    if not ok then
        return false
    end

    local currentVal = currentRno
    pcall(function()
        currentVal = sdk.to_int64(currentRno)
    end)

    if currentVal ~= CLOCK_RNO_CLOSE then
        clockComponent:set_field("_Rno", CLOCK_RNO_CLOSE)
    end

    return true
end

-- Mark the door as needing close, but don't repeatedly call in such a short time
function CutsceneObjects.RequestClockPuzzleClose(followUpSeconds)
    followUpSeconds = followUpSeconds or CLOCK_FOLLOW_UP_SECONDS
    if Storage and not Storage.clockDoorFixed then
        Storage.clockDoorFixed = true
        Storage.Update()
    end
    local closed = CutsceneObjects.ClockPuzzle()
    if followUpSeconds > 0 then
        CutsceneObjects.clockFollowUpAt = os.clock() + followUpSeconds
    end
    return closed
end

-- updateInit restores "open" for the door state from SaveData after loading the area. 
-- One-shot close after that init only — never on every init while clockDoorFixed (double close on jewel take).
function CutsceneObjects.SetupClockPuzzleHook()
    if CutsceneObjects.clockHooksReady then
        return
    end

    local jewelryType = sdk.find_type_definition(
        sdk.game_namespace("gimmick.action.EsGimmickJewelryBox")
    )
    if not jewelryType then
        return
    end

    local updateInit = jewelryType:get_method("updateInit()")
    if updateInit then
        sdk.hook(updateInit, function(args)
            -- no-op pre
        end, function(retval)
            if CutsceneObjects.clockNeedsLoadClose then
                CutsceneObjects.ClockPuzzle()
                CutsceneObjects.clockNeedsLoadClose = false
            end
            return retval
        end)
    end

    CutsceneObjects.clockHooksReady = true
    log.info("[Randomizer] Hooked EsGimmickJewelryBox.updateInit for clock door load-close")
end

function CutsceneObjects.Shotgun()
    local shotgunObject = Helpers.gameObject("0503_sm44_404_ES_ShotgunCase01A_gimmick")
    if not shotgunObject then
        return
    end
    local shotgunComponent = Helpers.component(shotgunObject, "gimmick.action.EsGimmickOpenObject")
    if not shotgunComponent then
        return
    end
    shotgunComponent:set_field("bGetItemForce", false)
end

function CutsceneObjects.IsLockPickLocation(itemName, folderPath)
    return folderPath == LOCKPICK_FOLDER
        and (
            itemName == LOCKPICK_ITEM_OBJECT
            or itemName == LOCKPICK_MAP_OBJECT
        )
end

function CutsceneObjects.ShouldClearLockPickMap()
    if Storage and Storage.seenLockPick then
        return true
    end

    for _, loc in pairs((Lookups and Lookups.locations) or {}) do
        if loc
            and loc.sent
            and loc.item_object == LOCKPICK_ITEM_OBJECT
            and loc.folder_path == LOCKPICK_FOLDER
        then
            return true
        end
    end

    return false
end

local function clearGimmickMapIcon(objectName)
    local gameObject = Helpers.gameObject(objectName)
    if not gameObject then
        return false
    end

    local control = Helpers.component(gameObject, "gimmick.action.GimmickControl")
    if not control then
        return false
    end

    pcall(function()
        control:set_field("isRemovedMapIcon", true)
    end)

    local body = nil
    pcall(function()
        body = control:get_field("_MyGimmickBody")
    end)
    if body then
        pcall(function()
            body:call("requestGimmickIconRemove", control)
        end)
    end

    -- UIMapManager keeps a separate saved gimmick marker list.
    -- Amazing job, Capcom
    pcall(function()
        local mapManager = sdk.get_managed_singleton(
            sdk.game_namespace("gamemastering.UIMapManager")
        )
        local hashType = sdk.find_type_definition("via.murmur_hash")
        if mapManager and hashType then
            local hash = hashType:get_method("calc32(System.String)"):call(
                nil,
                objectName
            )
            if hash then
                mapManager:call("removeGimmickData(System.UInt32)", hash)
                mapManager:call("set_IsUpdateGimmickData(System.Boolean)", true)
            end
        end
    end)

    return true
end

-- Clear linked corpse ItemPositions (sm73_304) — this owns the map-clear unit
-- We don't want the map to stay red with the new in-game map tracker
local function clearLockPickItemPositions()
    local lockpickObject = Helpers.gameObject(LOCKPICK_ITEM_OBJECT)
    if not lockpickObject then
        return false
    end

    local addItem = Helpers.component(
        lockpickObject,
        "gimmick.option.AddItemToInventorySettings"
    )
    if not addItem then
        return false
    end

    local itemPosObject = nil
    pcall(function()
        itemPosObject = addItem:get_field("ItemPositions")
    end)
    if itemPosObject ~= nil then
        -- GameObjectRef may need get_Target; some builds already yield a GO.
        local target = nil
        pcall(function()
            target = itemPosObject:call("get_Target()")
        end)
        if target then
            itemPosObject = target
        end
    end
    if not itemPosObject or not DestroyObjects or not DestroyObjects.ClearItemAndMap then
        return false
    end

    return DestroyObjects.ClearItemAndMap(itemPosObject)
end

-- AP check + map marker can live on EV322 and/or EV325. Clear both + ItemPositions.
function CutsceneObjects.ClearLockPickMapIcon()
    local cleared = clearLockPickItemPositions()
    if clearGimmickMapIcon(LOCKPICK_ITEM_OBJECT) then
        cleared = true
    end
    if clearGimmickMapIcon(LOCKPICK_MAP_OBJECT) then
        cleared = true
    end
    return cleared
end

function CutsceneObjects.MarkLockPickSeen()
    if not Storage.seenLockPick then
        Storage.seenLockPick = true
        Storage.Update()
    end
    CutsceneObjects.ClearLockPickMapIcon()
end

function CutsceneObjects.Lockpick()
    local lockpickObject = Helpers.gameObject(LOCKPICK_ITEM_OBJECT)
    if lockpickObject then
        local lockpickComponent = Helpers.component(
            lockpickObject,
            "gimmick.option.AddItemToInventorySettings"
        )
        if lockpickComponent then
            lockpickComponent:set_field("Enable", false)
        end
    end

    -- Re-apply map clear after area reloads / AP sync of an already-checked spot.
    -- To mimic the way poptracker would behave
    if CutsceneObjects.ShouldClearLockPickMap() then
        CutsceneObjects.MarkLockPickSeen()
    end
end

function CutsceneObjects.OverrideKey()
    local overrideObject = Helpers.gameObject("sm42_503_ES_LabMonitor04A_00_gimmick")
    if not overrideObject then
        return
    end
    local overrideComponent = Helpers.component(overrideObject, "gimmick.option.AddItemToInventorySettings")
    if not overrideComponent then
        return
    end
    overrideComponent:set_field("Enable", false)
end

function CutsceneObjects.CultureSample()
    local cultureObject = Helpers.gameObject("st05_0107_sm41_426_ES_GrowthMachine01A_gimmick")
    if not cultureObject then
        return
    end
    local cultureComponent = Helpers.component(cultureObject, "gimmick.option.AddItemToInventorySettings")
    if not cultureComponent then
        return
    end
    cultureComponent:set_field("Enable", false)
end

return CutsceneObjects
