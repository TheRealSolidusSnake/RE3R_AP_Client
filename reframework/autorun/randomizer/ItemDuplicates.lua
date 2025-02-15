local ItemDuplicates = {}

ItemDuplicates.duplicates_to_look_for = {}
ItemDuplicates.duplicates_to_look_for["MGL Grenade Launcher"] = true
ItemDuplicates.duplicates_to_look_for["M3 Shotgun"] = true
ItemDuplicates.duplicates_to_look_for["Battery Pack"] = true
ItemDuplicates.duplicates_to_look_for["Kendo Gate Key"] = true

function ItemDuplicates.Check(item_name)
    if ItemDuplicates.duplicates_to_look_for[item_name] == nil then
        return false
    end

    local names_in_inventory = Inventory.GetItemNames()
    local names_in_itembox = ItemBox.GetItemNames()

    for k, v in pairs(names_in_inventory) do
        if v == item_name then 
            return true 
        end
    end

    for k, v in pairs(names_in_itembox) do
        if v == item_name then 
            return true 
        end
    end

    return false
end

return ItemDuplicates