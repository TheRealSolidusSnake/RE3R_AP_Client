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

function Storage.Load()
    local existing_file = json.load_file(Storage.GetFilePath())
    
    if existing_file ~= nil then
        local unlocked_typewriters = existing_file['unlocked_typewriters'] or {}

        Storage.lastReceivedItemIndex = existing_file['last_received']
        Storage.lastSavedItemIndex = existing_file['last_saved']
        Storage.dotSightSafe = existing_file['opened_first_safe'] or false
        Storage.hipPouchSafe = existing_file['opened_second_safe'] or false
        Storage.dualMagSafe = existing_file['opened_third_safe'] or false
        Storage.receivedLockPick = existing_file['rec_lock_pick'] or false
        Storage.seenLockPick = existing_file['seen_lock_pick'] or false
        Storage.receivedBatteryPack = existing_file['rec_battery_pack'] or false
        Storage.seenBatteryPack = existing_file['seen_battery_pack'] or false
        Storage.clockDoorFixed = existing_file['clock_door_fixed'] or false
        
        for k, typewriter in pairs(unlocked_typewriters) do
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
        clock_door_fixed = Storage.clockDoorFixed
    }

    json.dump_file(Storage.GetFilePath(), stored_values)
end

-- this is called when interacting with typewriters because the user is assumed to save when they visit typewriters
-- we update the last saved item so we won't receive it again if we die and have to restart from our last save
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
end

return Storage
