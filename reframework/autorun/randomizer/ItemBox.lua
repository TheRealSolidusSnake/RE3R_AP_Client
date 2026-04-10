local ItemBox = {}
ItemBox.waiting_to_dedupe = {}

function ItemBox.GetAnyAvailable()
    local scene = Scene.getSceneObject()
    if not scene then
        return nil
    end

    local gimmick_objects = scene:call("findGameObjectsWithTag(System.String)", "Gimmick")
    
    -- there's occasionally an error about trying to loop an REManagedObject, so don't do that
    if type(gimmick_objects) ~= "table" then
        if gimmick_objects.get_elements then
            gimmick_objects = gimmick_objects:get_elements()
        else
            return nil -- if it's not something that we can call "get_elements" on, then it might as well be nil
        end
    end

    for k, gimmick in pairs(gimmick_objects) do
        gimmickName = gimmick:call("get_Name()")

        -- if the gimmick contains "ItemLocker" and contains "_control", it's an item box
        -- not checking if it *starts* with "ItemLocker" because Capcom likes to add crap to the beginning of the names (looking at you RE3R)
        -- (also, Lua is a terrible language with no modern features)
        if string.find(gimmickName, "ItemLocker") and string.find(gimmickName, "_control") then
            local compGimmickControl = gimmick:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gimmick.action.GimmickControl")))

            -- now, check if the item box has a map assigned and that map is active
            if compGimmickControl ~= nil and compGimmickControl:get_field("_IsPairComplete") then
                return gimmick
            end
        end
    end

    return nil
end

function ItemBox.GetItems()
    itemLocker = ItemBox.GetAnyAvailable()
    itemList = {}

    -- check that the item box we got is actually available first
    if itemLocker ~= nil then
        gimmickItemLockerControlComponent = itemLocker:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gimmick.action.GimmickItemLockerControl")))
        storageItems = gimmickItemLockerControlComponent:get_field("StorageItems")
        mItems = storageItems:get_field("mItems")
        foundOpenSlot = false

        for i, item in pairs(mItems) do
            if item ~= nil then
                defaultItem = item:get_field("DefaultItem")
                -- ItemId, WeaponId, WeaponParts, BulletId, Count

                itemId = defaultItem:get_field("ItemId")
                weaponId = defaultItem:get_field("WeaponId")

                -- if we found an empty slot, the item list is complete
                if itemId > 0 or weaponId > 0 then
                    table.insert(itemList, item)
                end
            end
        end
    end

    return itemList
end

function ItemBox.GetItemNames()
    local itemNames = {}

    for k, v in pairs(ItemBox.GetItems()) do
        if v ~= nil then
            table.insert(itemNames, v:call("getName()"))
        end
    end

    return itemNames
end

function ItemBox.AddItem(itemId, weaponId, weaponParts, bulletId, count)
    local itemLocker = ItemBox.GetAnyAvailable()

    if itemLocker ~= nil then
        local gimmickItemLockerControlComponent = itemLocker:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gimmick.action.GimmickItemLockerControl")))
        local storageItems = gimmickItemLockerControlComponent:get_field("StorageItems")
        local storageItems2nd = gimmickItemLockerControlComponent:get_field("StorageItems2nd")
        local mItems = storageItems:get_field("mItems")
        local mItems2nd = storageItems2nd:get_field("mItems")

        -- Define lists of stuff that needs to go to either Carlos, or to both characters (all items default to Jill)
        local carlosItems = {33, 96, 97, 98, 162, 164, 214, 218} -- Assault Rifle Parts/Ammo, ID Card, Tape Player and Locker Room Key
        local carlosWeapons = {21} -- Assault Rifle
        local bothItems = {1, 2, 3, 31, 61, 261} -- Healing, Handgun Ammo/Powder, Hip Pouch
        local bothWeapons = {65, 66} -- Grenades

        -- Helper function to check if an ID is in a list
        local function isInList(id, list)
            for _, v in ipairs(list) do
                if v == id then
                    return true
                end
            end
            return false
        end

        -- Determine target storage for items being added
        local targetStorage = mItems -- Default to Jill's storage

        if isInList(itemId, carlosItems) then
            targetStorage = mItems2nd
        elseif isInList(weaponId, carlosWeapons) then
            targetStorage = mItems2nd
        elseif isInList(itemId, bothItems) then
            targetStorage = {mItems, mItems2nd}
        elseif isInList(weaponId, bothWeapons) then
            targetStorage = {mItems, mItems2nd}
        end

        -- Add item to the appropriate storage(s)
        local function addItemToStorage(storage)
            for i, item in pairs(storage:get_elements()) do
                local slotItemId = item:get_ItemId()
                local slotWeaponId = item:get_WeaponId()

                if slotItemId <= 0 and slotWeaponId <= 0 then
                    if weaponId > 0 then
                        item:setWeapon(weaponId, 0, count, tonumber(bulletId), 0)
                    else
                        item:set_ItemId(itemId)
                    item:set_Count(count) -- love the consistency with player inv
                    end
                    return -- Exit after adding the item
                end
            end
        end

        if type(targetStorage) == "table" then
            for _, storage in ipairs(targetStorage) do
                addItemToStorage(storage)
            end
        else
            addItemToStorage(targetStorage)
        end
    end
end

function ItemBox.DedupeItem(itemName, found)
    table.insert(ItemBox.waiting_to_dedupe, { itemName=itemName, found=found })
end

function ItemBox.DedupeCheck()
    if #ItemBox.waiting_to_dedupe == 0 then
        return
    end

    local itemName = ItemBox.waiting_to_dedupe
    local found = ItemBox.found_dedupe
    local itemLocker = ItemBox.GetAnyAvailable()

    if itemLocker ~= nil then
        for d, dedupe in pairs(ItemBox.waiting_to_dedupe) do
            local itemName = dedupe["itemName"]
            local found = dedupe["found"]

            local gimmickItemLockerControlComponent = itemLocker:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gimmick.action.GimmickItemLockerControl")))
            local storageItems = gimmickItemLockerControlComponent:get_field("StorageItems")
            local mItems = storageItems:get_field("mItems")

            for k, v in pairs(mItems) do
                if v ~= nil then
                    if v:getName() == itemName then
                        if found or firstIndex ~= nil then
                            v:setBlank()
                        else
                            firstIndex = k
                        end
                    end
                end   
            end
        end

        ItemBox.waiting_to_dedupe = {}
    end
end

return ItemBox
