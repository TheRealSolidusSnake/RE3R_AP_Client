local ItemDuplicates = {}
ItemDuplicates.isInit = false

-- Unique items we don't want to stack as extras in the item box
-- Lookups are resolved to gameIDs so non-English clients work
ItemDuplicates.duplicates_to_look_for = {
    ["G18"] = true,
    ["MAG"] = true,
    ["MGL Grenade Launcher"] = true,
    ["M3 Shotgun"] = true,
    ["Lock Pick"] = true,
}

ItemDuplicates.idByName = nil

-- Hard fallbacks so dedupe still works before Lookups.items is loaded.
ItemDuplicates.hardcodedIds = {
    ["Lock Pick"] = { itemId = 151, weaponId = -1 },
    ["Bolt Cutters"] = { itemId = 152, weaponId = -1 },
    ["Fire Hose"] = { itemId = 181, weaponId = -1 },
    ["Blue Jewel"] = { itemId = 188, weaponId = -1 },
    ["Green Jewel"] = { itemId = 187, weaponId = -1 },
    ["Red Jewel"] = { itemId = 189, weaponId = -1 },
}

local function buildIdLookup()
    ItemDuplicates.idByName = {}

    for name, ids in pairs(ItemDuplicates.hardcodedIds) do
        if ItemDuplicates.duplicates_to_look_for[name] then
            ItemDuplicates.idByName[name] = {
                itemId = ids.itemId,
                weaponId = ids.weaponId,
            }
        end
    end

    for _, item in pairs(Lookups.items or {}) do
        local name = item.name
        if name and ItemDuplicates.duplicates_to_look_for[name] then
            local decimal = tonumber(item.decimal)
            if decimal then
                if item.type == "Weapon" or item.type == "Subweapon" then
                    ItemDuplicates.idByName[name] = {
                        itemId = -1,
                        weaponId = decimal,
                    }
                else
                    ItemDuplicates.idByName[name] = {
                        itemId = decimal,
                        weaponId = -1,
                    }
                end
            end
        end
    end
end

local function idsForName(item_name)
    if ItemDuplicates.idByName == nil then
        buildIdLookup()
    end

    return ItemDuplicates.idByName[item_name] or ItemDuplicates.hardcodedIds[item_name]
end

local function slotMatchesIds(slotItemId, slotWeaponId, itemId, weaponId)
    itemId = tonumber(itemId) or -1
    weaponId = tonumber(weaponId) or -1
    slotItemId = tonumber(slotItemId) or -1
    slotWeaponId = tonumber(slotWeaponId) or -1

    if itemId > 0 and slotItemId == itemId then
        return true
    end
    if weaponId > 0 and slotWeaponId == weaponId then
        return true
    end

    return false
end

-- Walk a persistent Jill/Carlos store. Works with no world locker loaded, and
-- unlike HasItem it can see weapons.
local function countInStore(fieldName, itemId, weaponId)
    local lockerManager = sdk.get_managed_singleton(sdk.game_namespace("gamemastering.ItemLockerManager"))
    local save = lockerManager and lockerManager:get_field("gameSaveData")
    local lockerSave = save and save:get_field("SaveData")
    local list = lockerSave and lockerSave:get_field(fieldName)
    local mItems = list and list:get_field("mItems")
    if not mItems then
        return 0
    end

    local elements = mItems
    if mItems.get_elements then
        elements = mItems:get_elements()
    end

    local found = 0
    for _, item in pairs(elements or {}) do
        if item ~= nil then
            local blank = false
            pcall(function()
                blank = item:call("isBlank") == true
            end)

            if not blank then
                local slotItemId = tonumber(item:get_ItemId()) or -1
                local slotWeaponId = tonumber(item:get_WeaponId()) or -1
                if slotMatchesIds(slotItemId, slotWeaponId, itemId, weaponId) then
                    found = found + 1
                end
            end
        end
    end

    return found
end

function ItemDuplicates.Init()
    if not ItemDuplicates.isInit then
        ItemDuplicates.isInit = true
        ItemDuplicates.idByName = nil
        ItemDuplicates.lastDedupeTime = 0
        -- One-shot clean on load/reset. Do NOT run every frame.
        if ItemBox and ItemBox.CleanupInvalidWeaponSlots then
            ItemBox.CleanupInvalidWeaponSlots()
        end
        ItemDuplicates.DedupeAll()
        ItemDuplicates.lastDedupeTime = os.time()
    end
end

-- Occasional sweep only (load edge cases). Not per-frame.
function ItemDuplicates.Update()
    local now = os.time()
    if (ItemDuplicates.lastDedupeTime or 0) == 0 then
        ItemDuplicates.lastDedupeTime = now
        return
    end
    if (now - ItemDuplicates.lastDedupeTime) < 30 then
        return
    end
    ItemDuplicates.lastDedupeTime = now
    ItemDuplicates.DedupeAll()
end

-- Count by gameIDs, not localized display names (0.2.9 bug cause I'm dumb).
function ItemDuplicates.Count(item_name)
    if ItemDuplicates.duplicates_to_look_for[item_name] == nil then
        return 0
    end

    local ids = idsForName(item_name)
    if not ids then
        return 0
    end

    local count = 0
    local itemId, weaponId = ids.itemId, ids.weaponId

    for _, playerInventory in pairs(Inventory.GetAllInventories()) do
        local slots = nil
        pcall(function()
            slots = playerInventory:call("get_Slots")
        end)
        if slots == nil then
            slots = playerInventory:get_field("_Slots")
        end

        local slotCount = 0
        if slots then
            pcall(function()
                slotCount = tonumber(slots:call("get_Count")) or 0
            end)
        end

        if slotCount > 0 then
            local skipNext = false
            for i = 0, slotCount - 1 do
                if skipNext then
                    skipNext = false
                else
                    local item = nil
                    pcall(function()
                        item = slots:call("get_Item", i)
                    end)
                    if item ~= nil then
                        local slotItemId = tonumber(item:call("get_ItemID()")) or -1
                        local slotWeaponId = tonumber(item:call("get_WeaponType()")) or -1
                        if slotMatchesIds(slotItemId, slotWeaponId, itemId, weaponId) then
                            count = count + 1
                            -- Fat (2-slot) items occupy the next index with the same id;
                            -- counting both makes one Battery Pack look like two.
                            local fat = false
                            pcall(function()
                                fat = item:call("get_IsFatSlot()") == true
                            end)
                            if fat then
                                skipNext = true
                            end
                        end
                    end
                end
            end
        elseif slots then
            local mItems = slots:get_field("mItems")
            if mItems and mItems.get_elements then
                local skipNext = false
                for _, item in pairs(mItems:get_elements()) do
                    if skipNext then
                        skipNext = false
                    elseif item ~= nil then
                        local slotItemId = tonumber(item:call("get_ItemID()")) or -1
                        local slotWeaponId = tonumber(item:call("get_WeaponType()")) or -1
                        if slotMatchesIds(slotItemId, slotWeaponId, itemId, weaponId) then
                            count = count + 1
                            local fat = false
                            pcall(function()
                                fat = item:call("get_IsFatSlot()") == true
                            end)
                            if fat then
                                skipNext = true
                            end
                        end
                    end
                end
            end
        end
    end

    -- Persistent box storage. Don't use HasItem here: it only takes an Item.ID,
    -- so it's blind to weapons, and every unique we track but the Lock Pick is
    -- one. That's how a second MAG / launcher got through.
    -- These are all one-of-a-kind, so they live in exactly one store. Summing
    -- both can't double-count and it still finds a Jill weapon that ended up
    -- sat in Carlos' list.
    local common = ItemBox and ItemBox.IsCommonBox and ItemBox.IsCommonBox()
    local boxCount = countInStore("_Items", itemId, weaponId)
        + countInStore("_Items2nd", itemId, weaponId)

    if boxCount == 0 then
        local itemLocker = ItemBox.GetAnyAvailable()
        if itemLocker then
            local control = itemLocker:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gimmick.action.GimmickItemLockerControl")))
            if control then
                local storageLists = {
                    control:get_field("StorageItems"),
                }
                -- Separate Jill/Carlos boxes: count both. Common box: StorageItems2nd
                -- is often the same slots again — walking both double-counts one item.
                if not common then
                    table.insert(storageLists, control:get_field("StorageItems2nd"))
                end
                for _, storageItems in pairs(storageLists) do
                    if storageItems then
                        local mItems = storageItems:get_field("mItems")
                        if mItems and mItems.get_elements then
                            for _, item in pairs(mItems:get_elements()) do
                                if item ~= nil then
                                    local defaultItem = item:get_field("DefaultItem")
                                    if defaultItem then
                                        local slotItemId = defaultItem:get_field("ItemId")
                                        local slotWeaponId = defaultItem:get_field("WeaponId")
                                        if slotMatchesIds(slotItemId, slotWeaponId, itemId, weaponId) then
                                            boxCount = boxCount + 1
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return count + boxCount
end

function ItemDuplicates.Check(item_name)
    -- Skip receiving another copy once one already exists.
    return ItemDuplicates.Count(item_name) >= 1
end

function ItemDuplicates.DedupeAll()
    for item_name, _ in pairs(ItemDuplicates.duplicates_to_look_for) do
        ItemDuplicates.Dedupe(item_name)
    end
end

function ItemDuplicates.Dedupe(item_name)
    if ItemDuplicates.duplicates_to_look_for[item_name] == nil then
        return false
    end

    local ids = idsForName(item_name)
    if not ids then
        return false
    end

    local before = ItemDuplicates.Count(item_name)
    if before <= 1 then
        return false
    end

    -- Prefer keeping one inventory copy, then wipe extras from the live box UI.
    -- Do NOT call ItemLockerManager.RemoveItem from a recounted total: a bad
    -- Count (common-box double HasItem, fat-slot double, etc.) deletes the
    -- only persistent copy — that is how Fire Hose / Red Jewel vanished.
    --
    -- ItemPersist shields the last Lock Pick / Battery Pack copy; stand down
    -- while we strip extras so setBlank/remove are not blocked mid-dedupe.
    local allow = ItemPersist
        and ItemPersist.BeginAllowRemoves
        and (item_name == "Lock Pick")

    if allow then
        ItemPersist.BeginAllowRemoves("dedupe " .. item_name)
    end

    local found = Inventory.DedupeItemId(ids.itemId, ids.weaponId, false)
    ItemBox.DedupeItemId(ids.itemId, ids.weaponId, found)

    if allow then
        ItemPersist.EndAllowRemoves()
    end

    return true
end

return ItemDuplicates
