local Inventory = {}

function Inventory.GetPlayerInventory()
    local inventoryManager = sdk.get_managed_singleton(sdk.game_namespace("gamemastering.InventoryManager"))

    if inventoryManager == nil then
        return nil
    end

    local playerInventory = inventoryManager:get_CurrentInventory()

    return playerInventory
end

function Inventory.GetMaxSlots()
    local playerInventory = Inventory.GetPlayerInventory()
    local playerCurrentMaxSlots = playerInventory:get_field("_CurrentSlotSize")

    return playerCurrentMaxSlots
end

function Inventory.IncreaseMaxSlots(amount)
    local playerInventory = Inventory.GetPlayerInventory()
    local playerCurrentMaxSlots = playerInventory:get_field("_CurrentSlotSize")

    playerInventory:call("set_CurrentSlotSize", playerCurrentMaxSlots + amount)
end

function Inventory.GetCurrentItems()
    local playerInventory = Inventory.GetPlayerInventory()
    local playerInventorySlots = playerInventory:get_field("_Slots")
    local playerCurrentMaxSlots = playerInventory:get_field("_CurrentSlotSize")
    local mItems = playerInventorySlots:get_field("mItems")
    local items = {}
    local skipNext = false

    for i, item in pairs(mItems:get_elements()) do
        if item ~= nil then
            if not skipNext then -- skip this slot if it's not available because of a "fat slot"
                local slotItemId = item:call("get_ItemID()")
                local slotWeaponId = item:call("get_WeaponType()")
    
                if slotItemId > 0 or slotWeaponId > 0 then
                    table.insert(items, item)
        
                    local isFatSlot = item:call("get_IsFatSlot()")
        
                    if item:call("get_IsFatSlot()") then
                        table.insert(items, item) -- list the same item in its two slots
                        skipNext = true
                    end                    
                end
            else
                skipNext = false
            end    
        end
    end

    return items
end

function Inventory.GetItemNames()
    local itemNames = {}

    for k, v in pairs(Inventory.GetCurrentItems()) do
        if v ~= nil then
            table.insert(itemNames, v:call("get_Name()"))
        end
    end

    return itemNames
end

function Inventory.HasSpaceForItem()
    local currentItems = Inventory.GetCurrentItems()
    
    -- the player shouldn't have no items at all, they should at least have a weapon or something
    -- so if the count comes back zero, that likely means an item box isn't loaded
    if #currentItems == 0 then
        return false
    end

    return #currentItems + 2 < Inventory.GetMaxSlots() -- leave a 2 slot padding for non-randomized pickups
end

function Inventory.HasItemId(item_id, weapon_id)
    local currentItems = Inventory.GetCurrentItems()

    for k, item in pairs(currentItems) do
        if item:call("get_ItemID()") == item_id or item:call("get_WeaponType()") == weapon_id then
            return true
        end
    end

    return false
end

function Inventory.AddItem(itemId, weaponId, weaponParts, bulletId, count)
    local playerInventory = Inventory.GetPlayerInventory()
    local playerInventorySlots = playerInventory:get_field("_Slots")
    local mItems = playerInventorySlots:get_field("mItems")
    local slotEmpty = playerInventory:getSlotEmpty()
    
    if slotEmpty ~= nil then
        local slotIndex = slotEmpty:get_Index()

        -- if the "empty" slot isn't actually blank, let AP send the item to the item box instead to avoid overwriting
        if not playerInventory:isBlankSlot(slotIndex) then
            return false
        end

        if weaponId > 0 then -- is a weapon
            playerInventory:setSlot(slotIndex, weaponId, 0, tonumber(bulletId), count, 0)
        else -- is an item
            playerInventory:setSlot(slotIndex, itemId, count, 0, 0)
        end

        return true
    end

    return false
end

function Inventory.SwapItem(fromItemIds, fromWeaponIds, itemId, weaponId, weaponParts, bulletId, count)
    local playerInventory = Inventory.GetPlayerInventory()
    local playerInventorySlots = playerInventory:get_field("_Slots")
    local playerCurrentMaxSlots = playerInventory:get_field("_CurrentSlotSize")
    local mItems = playerInventorySlots:get_field("mItems")
    local items = {}
    
    for i, item in pairs(mItems:get_elements()) do
        if item ~= nil then
            local slotItemId = item:call("get_ItemID()")
            local slotWeaponId = item:call("get_WeaponType()")
            local slotIndex = item:get_Index()

            if fromItemIds then
                for k, fromItemId in pairs(fromItemIds) do
                    if slotItemId == fromItemId then
                        if itemId > 0 then -- is an item
                            playerInventory:setSlot(slotIndex, itemId, count, 0, 0)
                        end
            
                        return true
                    end
                end
            end

            if fromWeaponIds then
                for k, fromWeaponId in pairs(fromWeaponIds) do
                    if slotWeaponId == fromWeaponId then
                        if weaponId > 0 then -- is a weapon
                            local set_slot_weapon_string = "setSlot(System.Int32, " .. sdk.game_namespace("EquipmentDefine.WeaponType") .. ", " .. sdk.game_namespace("EquipmentDefine.WeaponParts") .. ", " .. sdk.game_namespace("gamemastering.Item.ID") .. ", System.Int32, " .. sdk.game_namespace("gamemastering.InventoryManager.ItemExData") .. ")"
                            playerInventory:call(set_slot_weapon_string, slotIndex, weaponId, 0, tonumber(bulletId), count, 0)
                        end
            
                        return true
                    end
                end
            end
        end
    end

    return false
end

return Inventory
