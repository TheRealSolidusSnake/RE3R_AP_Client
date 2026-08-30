local Storage = {}
Storage.storageInitialized = false
Storage.lastReceivedItemIndex = -1
Storage.lastSavedItemIndex = -1
Storage.dotSightSafe = false
Storage.hipPouchSafe = false
Storage.dualMagSafe = false
Storage.receivedLockPick = false
Storage.seenLockPick = false
Storage.receivedBatteryPack = false
Storage.seenBatteryPack = false
Storage.clockDoorFixed = false
Storage.rpdSafetyDepositKeyProgress = false
Storage.rpdBatteryProgress = false
Storage.rpdShowerWallChecked = false
Storage.rpdShowerObjectiveProgress = false
-- Vanilla T-Junction patrol-car ammo (unreachable without hose bust).
Storage.downtownCopCarCleared = false
Storage.receivedFiles = {}
Storage.collectedFiles = {}
-- Map a file was carrying, held back at the world pickup until AP sends it.
Storage.deferredMapItems = {}
-- Parasite/Puke traps that landed on Carlos, waiting for Jill to be back.
Storage.pendingTraps = {}
Storage.checkedItemGuids = {}
Storage.receivedHipPouches = 0

function Storage.GetGuidString(guid)
    if not guid then
        return ""
    end

    local ok, result = pcall(function()
        return string.format(
            "%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
            guid:get_field("mData1"),
            guid:get_field("mData2"),
            guid:get_field("mData3"),
            guid:get_field("mData4_0"),
            guid:get_field("mData4_1"),
            guid:get_field("mData4_2"),
            guid:get_field("mData4_3"),
            guid:get_field("mData4_4"),
            guid:get_field("mData4_5"),
            guid:get_field("mData4_6"),
            guid:get_field("mData4_7")
        )
    end)

    return ok and result or ""
end

function Storage.MarkCheckedItem(itemPositions)
    if not itemPositions then
        return
    end

    local guid = Storage.GetGuidString(itemPositions:get_field("MyGuid"))
    if guid == "" or Storage.checkedItemGuids[guid] then
        return
    end

    Storage.checkedItemGuids[guid] = true
    Storage.Update()
end

function Storage.IsItemGuidChecked(guid)
    local guidString = type(guid) == "string" and guid or Storage.GetGuidString(guid)
    return guidString ~= "" and Storage.checkedItemGuids[guidString] == true
end

function Storage.Load()
    local existing_file = json.load_file(Storage.GetFilePath())
    
    if existing_file ~= nil then
        local unlocked_typewriters = existing_file['unlocked_typewriters'] or {}

        Storage.lastReceivedItemIndex = existing_file['last_received'] or -1
        Storage.lastSavedItemIndex = existing_file['last_saved'] or -1
        Storage.dotSightSafe = existing_file['opened_first_safe'] or false
        Storage.hipPouchSafe = existing_file['opened_second_safe'] or false
        Storage.dualMagSafe = existing_file['opened_third_safe'] or false
        Storage.receivedLockPick = existing_file['rec_lock_pick'] or false
        Storage.seenLockPick = existing_file['seen_lock_pick'] or false
        Storage.receivedBatteryPack = existing_file['rec_battery_pack'] or false
        Storage.seenBatteryPack = existing_file['seen_battery_pack'] or false
        Storage.clockDoorFixed = existing_file['clock_door_fixed'] or false
        -- Reset Scripts reload Storage after CutsceneObjects already saw the
        -- gimmick with clockDoorFixed=false, so stream-in close never fires.
        -- Re-request close once the flag is restored from disk.
        if Storage.clockDoorFixed
            and CutsceneObjects
            and CutsceneObjects.RequestClockPuzzleClose
        then
            CutsceneObjects.RequestClockPuzzleClose(0.75)
        end
        Storage.rpdSafetyDepositKeyProgress = existing_file['rpd_safety_deposit_key_progress'] or false
        Storage.rpdBatteryProgress = existing_file['rpd_battery_progress'] or false
        Storage.rpdShowerWallChecked = existing_file['rpd_shower_wall_checked'] or false
        Storage.rpdShowerObjectiveProgress = existing_file['rpd_shower_objective_progress'] or false
        Storage.downtownCopCarCleared = existing_file['downtown_cop_car_cleared'] or false
        Storage.receivedFiles = existing_file['received_files'] or {}
        Storage.collectedFiles = existing_file['collected_files'] or {}
        Storage.deferredMapItems = existing_file['deferred_map_items'] or {}
        Storage.pendingTraps = existing_file['pending_traps'] or {}
        if Files then
            Files.needsFileReplay = true
        end
        Storage.checkedItemGuids = existing_file['checked_item_guids'] or {}
        Storage.receivedHipPouches = existing_file['received_hip_pouches'] or 0

        for _, typewriter in pairs(unlocked_typewriters) do
            Typewriters.Unlock("", typewriter)
        end
    else
        Storage.Update()
    end

    Storage.storageInitialized = true
end

function Storage.Update()
    local player = Archipelago.GetPlayer()
    
    -- no point in writing if filename is bad
    if not player["seed"] or not player["slot"] then
        return
    end

    stored_values = { 
        last_received = Storage.lastReceivedItemIndex, 
        last_saved = Storage.lastSavedItemIndex,
        unlocked_typewriters = Typewriters.GetAllUnlocked(),
        opened_first_safe = Storage.dotSightSafe, 
        opened_second_safe = Storage.hipPouchSafe, 
        opened_third_safe = Storage.dualMagSafe, 
        rec_lock_pick = Storage.receivedLockPick,
        seen_lock_pick = Storage.seenLockPick,
        rec_battery_pack = Storage.receivedBatteryPack,
        seen_battery_pack = Storage.seenBatteryPack,
        clock_door_fixed = Storage.clockDoorFixed,
        rpd_safety_deposit_key_progress = Storage.rpdSafetyDepositKeyProgress,
        rpd_battery_progress = Storage.rpdBatteryProgress,
        rpd_shower_wall_checked = Storage.rpdShowerWallChecked,
        rpd_shower_objective_progress = Storage.rpdShowerObjectiveProgress,
        downtown_cop_car_cleared = Storage.downtownCopCarCleared,
        received_files = Storage.receivedFiles,
        collected_files = Storage.collectedFiles,
        deferred_map_items = Storage.deferredMapItems,
        pending_traps = Storage.pendingTraps,
        checked_item_guids = Storage.checkedItemGuids,
        received_hip_pouches = Storage.receivedHipPouches or 0
    }

    json.dump_file(Storage.GetFilePath(), stored_values)
end

-- Save hooks update the last saved item so reconnect/death replay starts from
-- the same point as the game's save.
function Storage.UpdateLastSavedItems()
    Storage.lastSavedItemIndex = Storage.lastReceivedItemIndex
    Storage.Update()
end

function Storage.GetFilePath()
    local player = Archipelago.GetPlayer()

    return Lookups.filepath .. "_storage/" .. player["seed"] .. "_" .. player["slot"] .. ".json"
end

function Storage.Reset()
    Storage.storageInitialized = false
    Storage.lastReceivedItemIndex = -1
    Storage.lastSavedItemIndex = -1
    Storage.dotSightSafe = false
    Storage.hipPouchSafe = false
    Storage.dualMagSafe = false
    Storage.receivedLockPick = false
    Storage.seenLockPick = false
    Storage.receivedBatteryPack = false
    Storage.seenBatteryPack = false
    Storage.clockDoorFixed = false
    Storage.rpdSafetyDepositKeyProgress = false
    Storage.rpdBatteryProgress = false
    Storage.rpdShowerWallChecked = false
    Storage.rpdShowerObjectiveProgress = false
    Storage.downtownCopCarCleared = false
    Storage.receivedFiles = {}
    Storage.collectedFiles = {}
    Storage.deferredMapItems = {}
    Storage.pendingTraps = {}
    Storage.checkedItemGuids = {}
    Storage.receivedHipPouches = 0
end

return Storage
