local ItemBox = {}

function ItemBox.GetAnyAvailable()
    local gimmick_objects = scene:call("findGameObjectsWithTag(System.String)", "Gimmick")

    if type(gimmick_objects) ~= "table" then
        if gimmick_objects.get_elements then
            gimmick_objects = gimmick_objects:get_elements()
        else
            return nil
        end
    end

    for k, gimmick in pairs(gimmick_objects) do
        gimmickName = gimmick:call("get_Name()")

        if string.find(gimmickName, "ItemLocker") and string.find(gimmickName, "_control") then
            local compGimmickControl = gimmick:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gimmick.action.GimmickControl")))

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
                        item:set_Count(count)
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

return ItemBox
