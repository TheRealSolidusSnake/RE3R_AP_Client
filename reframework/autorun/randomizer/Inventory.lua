local Inventory = {}

function Inventory.GetMaxSlots()
    local inventoryManager = sdk.get_managed_singleton(sdk.game_namespace("gamemastering.InventoryManager"))
    local playerInventory = inventoryManager:get_CurrentInventory()
    local playerCurrentMaxSlots = playerInventory:get_field("_CurrentSlotSize")

    return playerCurrentMaxSlots
end

function Inventory.IncreaseMaxSlots(amount)
    local inventoryManager = sdk.get_managed_singleton(sdk.game_namespace("gamemastering.InventoryManager"))
    local playerInventory = inventoryManager:get_CurrentInventory()
    local playerCurrentMaxSlots = playerInventory:get_field("_CurrentSlotSize")

    playerInventory:call("set_CurrentSlotSize", playerCurrentMaxSlots + amount)
end

function Inventory.GetCurrentItems()
    local inventoryManager = sdk.get_managed_singleton(sdk.game_namespace("gamemastering.InventoryManager"))
    local playerInventory = inventoryManager:get_CurrentInventory()
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
    
                if slotItemId <= 0 and slotWeaponId <= 0 then
                    break
                end
    
                table.insert(items, item)
    
                local isFatSlot = item:call("get_IsFatSlot()")
    
                if item:call("get_IsFatSlot()") then
                    table.insert(items, item) -- list the same item in its two slots
                    skipNext = true
                end    
            else
                skipNext = false
            end    
        end
    end

    return items
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

function Inventory.AddItem(itemId, weaponId, weaponParts, bulletId, count)
    local inventoryManager = sdk.get_managed_singleton(sdk.game_namespace("gamemastering.InventoryManager"))
    local playerInventory = inventoryManager:get_CurrentInventory()
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

return Inventory
