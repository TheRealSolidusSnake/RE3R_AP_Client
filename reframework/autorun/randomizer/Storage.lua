local Storage = {}
Storage.storageInitialized = false
Storage.lastReceivedItemIndex = -1
Storage.lastSavedItemIndex = -1

function Storage.Load()
    local existing_file = json.load_file(Storage.GetFilePath())
    
    if existing_file ~= nil then
        local unlocked_typewriters = existing_file['unlocked_typewriters'] or {}

        Storage.lastReceivedItemIndex = existing_file['last_received']
        Storage.lastSavedItemIndex = existing_file['last_saved']
        
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
        unlocked_typewriters = Typewriters.GetAllUnlocked() 
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
end

return Storage
