local Inventory = {}

local BASE_SLOT_SIZE = 8
local MAX_SLOT_SIZE = 20
local MAX_HIP_POUCHES = 6 -- 8 + (6 * 2) = 20

function Inventory.GetPlayerInventory()
    local inventory_manager = sdk.get_managed_singleton(sdk.game_namespace("gamemastering.InventoryManager"))
    if inventory_manager == nil then
        return nil
    end

    return inventory_manager:get_CurrentInventory()
end

-- RE3 keeps separate Inventory objects per survivor (Jill / Carlos).
function Inventory.GetAllInventories()
    local inventory_manager = sdk.get_managed_singleton(sdk.game_namespace("gamemastering.InventoryManager"))
    if inventory_manager == nil then
        return {}
    end

    local inventories = {}
    local seen = {}
    local list = inventory_manager:call("get_Inventories")

    if list ~= nil then
        local count = tonumber(list:call("get_Count")) or 0
        for i = 0, count - 1 do
            local inv = list:call("get_Item", i)
            if inv ~= nil and not seen[inv] then
                seen[inv] = true
                table.insert(inventories, inv)
            end
        end
    end

    local current = inventory_manager:call("get_CurrentInventory")
    if current ~= nil and not seen[current] then
        table.insert(inventories, current)
    end

    return inventories
end

function Inventory.GetSlotSize(inventory)
    if inventory == nil then
        return 0
    end

    local slots = inventory:call("get_CurrentSlotSize")
    if slots == nil then
        slots = inventory:get_field("_CurrentSlotSize")
    end

    return tonumber(slots) or 0
end

function Inventory.GetMaxSlots()
    return Inventory.GetSlotSize(Inventory.GetPlayerInventory())
end

function Inventory.GetReceivedHipPouchCount()
    -- Only trust Storage for this. Reading CurrentSlotSize to infer pouches is
    -- circular — SyncHipPouchSlots writes that size from this count, so a bad
    -- base (or leftover inflate) invents phantom pouches that never shrink.
    local pouches = tonumber(Storage.receivedHipPouches) or 0
    if pouches < 0 then
        pouches = 0
    elseif pouches > MAX_HIP_POUCHES then
        pouches = MAX_HIP_POUCHES
    end

    if pouches ~= Storage.receivedHipPouches then
        Storage.receivedHipPouches = pouches
    end

    return pouches
end

function Inventory.GetTargetSlotSize()
    return math.min(BASE_SLOT_SIZE + (Inventory.GetReceivedHipPouchCount() * 2), MAX_SLOT_SIZE)
end

-- Manual/debug only. NEVER call every frame during a character swap — the game
-- queues Carlos loadout prefabs here, and wiping them stalls NOW LOADING.
function Inventory.ClearPrefabStandbyRequests()
    local inventory_manager = sdk.get_managed_singleton(
        sdk.game_namespace("gamemastering.InventoryManager")
    )
    if inventory_manager == nil then
        return false
    end

    local cleared = false
    for _, field_name in ipairs({
        "ItemPrefabStandbyRequestList",
        "WeaponPrefabStandbyRequestList"
    }) do
        pcall(function()
            local list = inventory_manager:get_field(field_name)
            if list == nil then
                return
            end
            local count = list:call("get_Count") or 0
            if count > 0 then
                list:call("Clear")
                cleared = true
            end
        end)
    end

    return cleared
end

-- Keep every loaded survivor inventory at the shared Hip Pouch size.
-- Carlos's inventory often shows up later, so this also gets called from the update loop.
function Inventory.SyncHipPouchSlots()
    if Scene.isTransitioning() then
        return false
    end

    local target = Inventory.GetTargetSlotSize()
    local changed = false

    for _, inventory in pairs(Inventory.GetAllInventories()) do
        local current = Inventory.GetSlotSize(inventory)
        -- Only expand, never shrink. Carlos's hospital Hip Pouch is still a
        -- vanilla (non-AP) pickup, and the game grows slots outside Storage.
        if current > 0 and current < target then
            inventory:call("set_CurrentSlotSize", target)
            changed = true
        end
    end

    return changed
end

function Inventory.IncreaseMaxSlots(amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then
        return false
    end

    local pouches = Inventory.GetReceivedHipPouchCount()
    if pouches >= MAX_HIP_POUCHES then
        Inventory.SyncHipPouchSlots()
        return false
    end

    local add_pouches = math.floor(amount / 2)
    if add_pouches < 1 then
        add_pouches = 1
    end

    Storage.receivedHipPouches = math.min(pouches + add_pouches, MAX_HIP_POUCHES)
    Inventory.SyncHipPouchSlots()
    Storage.Update()
    return true
end

function Inventory.GetCurrentItems()
    local player_inventory = Inventory.GetPlayerInventory()
    if player_inventory == nil then
        return {}
    end

    local slots = player_inventory:get_field("_Slots")
    local max_slots = tonumber(player_inventory:get_field("_CurrentSlotSize")) or 0
    if slots == nil or max_slots <= 0 then
        return {}
    end

    local mItems = slots:get_field("mItems")
    if mItems == nil then
        return {}
    end

    -- mItems isn't kept in slot order, so element N is not slot N. Key each
    -- slot by its own Index and walk that instead.
    local by_index = {}
    for _, slot in pairs(mItems:get_elements()) do
        if slot ~= nil then
            by_index[slot:call("get_Index")] = slot
        end
    end

    local items = {}
    for i = 0, max_slots - 1 do
        local item = by_index[i]
        if item ~= nil then
            local item_id = item:call("get_ItemID()") or -1
            local weapon_id = item:call("get_WeaponType()") or -1

            if item_id > 0 or weapon_id > 0 then
                table.insert(items, item)

                -- Fat (2-slot) items occupy two cells; list them twice so
                -- #items matches slots used, same as RE2.
                if item:call("get_IsFatSlot()") == true then
                    table.insert(items, item)
                end
            end
        end
    end

    return items
end

function Inventory.GetItemNames()
    local item_names = {}

    for k, v in pairs(Inventory.GetCurrentItems()) do
        if v ~= nil then
            table.insert(item_names, v:call("get_Name()"))
        end
    end

    return item_names
end

function Inventory.HasSpaceForItem()
    local current_items = Inventory.GetCurrentItems()

    -- the player shouldn't have no items at all, they should at least have a weapon or something
    -- so if the count comes back zero, that likely means an item box isn't loaded
    if #current_items == 0 then
        return false
    end

    local max_slots = Inventory.GetMaxSlots()
    if max_slots <= 0 then
        return false
    end

    -- leave a 2 slot padding for non-randomized pickups (Battery etc).
    -- #items already counts fat pieces twice.
    return #current_items + 2 < max_slots
end

-- Two-slot ("fat") items overwrite the next inventory slot when placed via setSlot.
-- Same as RE2 -- always send these to the item box instead.
function Inventory.IsFatItem(item_id, weapon_id, weapon_parts)
    local inv_manager = sdk.get_managed_singleton(
        sdk.game_namespace("gamemastering.InventoryManager")
    )
    if inv_manager == nil then
        return false
    end

    item_id = tonumber(item_id) or -1
    weapon_id = tonumber(weapon_id) or -1
    weapon_parts = tonumber(weapon_parts) or 0

    if weapon_id > 0 then
        local ok, fat = pcall(function()
            return inv_manager:call("isFatWeapon", weapon_id, weapon_parts)
        end)
        return ok and fat == true
    end

    if item_id > 0 then
        local ok, fat = pcall(function()
            return inv_manager:call("isFatItem", item_id)
        end)
        return ok and fat == true
    end

    return false
end

function Inventory.HasItemId(item_id, weapon_id)
    local current_items = Inventory.GetCurrentItems()
    item_id = tonumber(item_id) or -1
    weapon_id = tonumber(weapon_id) or -1

    for k, item in pairs(current_items) do
        local slot_item_id = tonumber(item:call("get_ItemID()")) or -1
        local slot_weapon_id = tonumber(item:call("get_WeaponType()")) or -1

        -- Only match the category we were asked about. Comparing weapon_id == -1
        -- against empty slots used to false-positive "already have" for every item.
        if item_id > 0 and slot_item_id == item_id then
            return true
        end
        if weapon_id > 0 and slot_weapon_id == weapon_id then
            return true
        end
    end

    return false
end

function Inventory.AddItem(item_id, weapon_id, weapon_parts, bullet_id, count)
    -- fat (2-slot) items must not use setSlot; they clobber the next slot.
    if Inventory.IsFatItem(item_id, weapon_id, weapon_parts) then
        return false
    end

    -- keep the 2-slot reserve; callers should send to the item box instead.
    if not Inventory.HasSpaceForItem() then
        return false
    end

    local player_inventory = Inventory.GetPlayerInventory()
    local slot_empty = player_inventory:getSlotEmpty()

    if slot_empty ~= nil then
        local slot_index = slot_empty:get_Index()

        -- if the "empty" slot isn't actually blank, let AP send the item to the item box instead to avoid overwriting
        if not player_inventory:isBlankSlot(slot_index) then
            return false
        end

        if weapon_id > 0 then -- is a weapon
            player_inventory:setSlot(slot_index, weapon_id, 0, tonumber(bullet_id), count, 0)
        else -- is an item
            player_inventory:setSlot(slot_index, item_id, count, 0, 0)
        end

        return true
    end

    return false
end

function Inventory.DedupeItem(item_name, found)
    -- old name-based path; prefer DedupeItemId so language packs don't break it
    local player_inventory = Inventory.GetPlayerInventory()
    local player_inventory_slots = player_inventory:get_field("_Slots")
    local first_index = nil

    for k, v in pairs(player_inventory_slots:get_field("mItems")) do
        if v ~= nil then
            if v:get_Name() == item_name then
                if found or first_index ~= nil then
                    v:remove()
                else
                    first_index = v:get_Index()
                end
            end
        end
    end

    if first_index ~= nil then
        return true
    end

    return false -- returns whether the item was found or not
end

function Inventory.DedupeItemId(item_id, weapon_id, found)
    item_id = tonumber(item_id) or -1
    weapon_id = tonumber(weapon_id) or -1
    local kept = found == true

    -- Prefer Inventory.removeSlot(index). Slot:remove() can no-op depending on
    -- how the slot list is held; grab indices first so we don't mutate while iterating.
    for _, player_inventory in pairs(Inventory.GetAllInventories()) do
        local slots = nil
        pcall(function()
            slots = player_inventory:call("get_Slots")
        end)
        if slots == nil then
            slots = player_inventory:get_field("_Slots")
        end
        if slots == nil then
            goto continue_inv
        end

        local indices = {}
        local count = 0
        pcall(function()
            count = tonumber(slots:call("get_Count")) or 0
        end)

        if count > 0 then
            for i = 0, count - 1 do
                local v = nil
                pcall(function()
                    v = slots:call("get_Item", i)
                end)
                if v ~= nil then
                    local slot_item_id = tonumber(v:call("get_ItemID()")) or -1
                    local slot_weapon_id = tonumber(v:call("get_WeaponType()")) or -1
                    local matches = (item_id > 0 and slot_item_id == item_id)
                        or (weapon_id > 0 and slot_weapon_id == weapon_id)

                    if matches then
                        if kept then
                            local idx = tonumber(v:call("get_Index")) or i
                            table.insert(indices, idx)
                        else
                            kept = true
                        end
                    end
                end
            end
        else
            -- Fallback: older list layout used mItems + get_elements().
            local mItems = slots:get_field("mItems")
            if mItems and mItems.get_elements then
                for _, v in pairs(mItems:get_elements()) do
                    if v ~= nil then
                        local slot_item_id = tonumber(v:call("get_ItemID()")) or -1
                        local slot_weapon_id = tonumber(v:call("get_WeaponType()")) or -1
                        local matches = (item_id > 0 and slot_item_id == item_id)
                            or (weapon_id > 0 and slot_weapon_id == weapon_id)

                        if matches then
                            if kept then
                                table.insert(indices, tonumber(v:call("get_Index")) or 0)
                            else
                                kept = true
                            end
                        end
                    end
                end
            end
        end

        table.sort(indices, function(a, b) return a > b end)
        for _, idx in ipairs(indices) do
            local removed = false
            pcall(function()
                removed = player_inventory:call("removeSlot", idx) == true
            end)
            if not removed then
                pcall(function()
                    local slot = player_inventory:call("getSlot", idx)
                    if slot ~= nil then
                        slot:call("remove")
                    end
                end)
            end
        end

        ::continue_inv::
    end

    return kept
end

function Inventory.SwapItem(from_item_ids, from_weapon_ids, item_id, weapon_id, weapon_parts, bullet_id, count)
    local player_inventory = Inventory.GetPlayerInventory()
    local player_inventory_slots = player_inventory:get_field("_Slots")
    local mItems = player_inventory_slots:get_field("mItems")

    for i, item in pairs(mItems:get_elements()) do
        if item ~= nil then
            local slot_item_id = item:call("get_ItemID()")
            local slot_weapon_id = item:call("get_WeaponType()")
            local slot_index = item:get_Index()

            if from_item_ids then
                for k, from_item_id in pairs(from_item_ids) do
                    if slot_item_id == from_item_id then
                        if item_id > 0 then -- is an item
                            player_inventory:setSlot(slot_index, item_id, count, 0, 0)
                        end

                        return true
                    end
                end
            end

            if from_weapon_ids then
                for k, from_weapon_id in pairs(from_weapon_ids) do
                    if slot_weapon_id == from_weapon_id then
                        if weapon_id > 0 then -- is a weapon
                            local set_slot_weapon_string = "setSlot(System.Int32, " .. sdk.game_namespace("EquipmentDefine.WeaponType") .. ", " .. sdk.game_namespace("EquipmentDefine.WeaponParts") .. ", " .. sdk.game_namespace("gamemastering.Item.ID") .. ", System.Int32, " .. sdk.game_namespace("gamemastering.InventoryManager.ItemExData") .. ")"
                            player_inventory:call(set_slot_weapon_string, slot_index, weapon_id, 0, tonumber(bullet_id), count, 0)
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
