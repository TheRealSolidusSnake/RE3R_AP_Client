local ItemDuplicates = {}
ItemDuplicates.isInit = false

-- We want to dedupe basically everything, since the player shouldn't have multiple copies
-- of anything except ammo, crafting, and healing really

local keys_to_dedupe = {
    "Fire Hose", "Bolt Cutters", "Lock Pick", "Battery Pack", "Kendo Gate Key",
    "Safety Deposit Key", "Battery", "Hospital ID Card", "Cassette Tape",
    "Tape Player", "Vaccine Sample", "Electronic Gadget", "Detonator",
    "Locker Room Key", "Fuse 1", "Fuse 2", "Fuse 3", "Override Key",
    "Culture Sample", "Liquid-Filled Test Tube", "Vaccine"
}

local gating_to_dedupe = {
    "Green Jewel", "Blue Jewel", "Red Jewel", "ID Card"
}

local weapons_to_dedupe = {
    "G19", "G18", "M3 Shotgun", "Assault Rifle", "MAG", "MGL Grenade Launcher"
}

local upgrades_to_dedupe = {
    "Dot Sight - G19", "Extended Mag - G19", "Moderator - G19",
    "Tactical Stock - M3", "Semi-Auto Barrel - M3", "Shell Holder - M3",
    "Scope - Assault Rifle", "Dual Magazine - Assault Rifle",
    "Tactical Grip - Assault Rifle", "Extended Barrel - MAG",
    "Supply Case - Shotgun Shells", "Supply Case - Flame Rounds"
}

ItemDuplicates.duplicates_to_look_for = {}

local function add_list(list)
    for _, name in ipairs(list) do
        ItemDuplicates.duplicates_to_look_for[name] = true
    end
end

add_list(keys_to_dedupe)
add_list(gating_to_dedupe)
add_list(weapons_to_dedupe)
add_list(upgrades_to_dedupe)

function ItemDuplicates.Init()
    if not ItemDuplicates.isInit then
        ItemDuplicates.isInit = true
        ItemDuplicates.DedupeAll()
    end
end

function ItemDuplicates.Check(item_name)
    return ItemDuplicates.duplicates_to_look_for[item_name] ~= nil
end

function ItemDuplicates.DedupeAll()
    for item_name in pairs(ItemDuplicates.duplicates_to_look_for) do
        ItemDuplicates.Dedupe(item_name)
    end
end

function ItemDuplicates.Dedupe(item_name)
    if not ItemDuplicates.duplicates_to_look_for[item_name] then
        return false
    end

    -- Prefer the copy in inventory over item box
    local found_in_inventory = Inventory.DedupeItem(item_name, false)
    ItemBox.DedupeItem(item_name, found_in_inventory)
end

return ItemDuplicates