local ItemDuplicates = {}
ItemDuplicates.isInit = false
ItemDuplicates.duplicates_to_look_for = {}

ItemDuplicates.duplicates_to_look_for["G18"] = true
ItemDuplicates.duplicates_to_look_for["MAG"] = true
ItemDuplicates.duplicates_to_look_for["MGL Grenade Launcher"] = true
ItemDuplicates.duplicates_to_look_for["M3 Shotgun"] = true
ItemDuplicates.duplicates_to_look_for["Battery Pack"] = true
ItemDuplicates.duplicates_to_look_for["Kendo Gate Key"] = true
ItemDuplicates.duplicates_to_look_for["Lock Pick"] = true

function ItemDuplicates.Init()
    if not ItemDuplicates.isInit then
        ItemDuplicates.isInit = true
    end
end

function ItemDuplicates.Count(item_name)
    if ItemDuplicates.duplicates_to_look_for[item_name] == nil then
        return 0
    end

    local count = 0
    local names_in_inventory = Inventory.GetItemNames() or {}
    local names_in_itembox = ItemBox.GetItemNames() or {}

    for _, v in pairs(names_in_inventory) do
        if v == item_name then
            count = count + 1
        end
    end

    for _, v in pairs(names_in_itembox) do
        if v == item_name then
            count = count + 1
        end
    end

    return count
end

function ItemDuplicates.Check(item_name)
    return ItemDuplicates.Count(item_name) > 1
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

    if not ItemDuplicates.Check(item_name) then
        return false
    end

    -- prefer the copy of the item that's in the inventory, if present
    local found = Inventory.DedupeItem(item_name, false)
    ItemBox.DedupeItem(item_name, found)

    return true
end

return ItemDuplicates