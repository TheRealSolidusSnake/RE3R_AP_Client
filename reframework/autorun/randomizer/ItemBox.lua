local ItemBox = {}
ItemBox.waiting_to_dedupe = {}

-- owner from items.json: "jill" / "carlos" / "shared" (or "both"). missing = jill
local function normalizeOwner(value)
    if type(value) ~= "string" then
        return nil
    end

    local lowered = string.lower(value)
    if lowered == "carlos" then
        return "carlos"
    elseif lowered == "shared" or lowered == "both" then
        return "shared"
    elseif lowered == "jill" then
        return "jill"
    end

    return nil
end

-- Hardcoded fallback matching 0.2.7.5 ItemBox.AddItem lists, used if items.json
-- has no owner (or Lookups isn't ready yet). Keep in sync with that client.
-- 0.2.7.5 core list + other Carlos-only keys from current items.json owners.
local FALLBACK_CARLOS_ITEMS = {
    [33] = true,  -- Assault Rifle Ammo
    [96] = true,  -- Scope - Assault Rifle
    [97] = true,  -- Dual Magazine - Assault Rifle
    [98] = true,  -- Tactical Grip - Assault Rifle
    [161] = true, -- Battery
    [162] = true, -- Safety Deposit Key
    [164] = true, -- ID Card
    [165] = true, -- Electronic Gadget
    [211] = true, -- Hospital ID Card
    [213] = true, -- Cassette Tape
    [214] = true, -- Tape Player
    [215] = true, -- Vaccine Sample
    [217] = true, -- Detonator
    [218] = true, -- Locker Room Key
}
local FALLBACK_CARLOS_WEAPONS = {
    [21] = true, -- Assault Rifle
}
local FALLBACK_SHARED_ITEMS = {
    [1] = true,   -- First Aid Spray
    [2] = true,   -- Green Herb
    [3] = true,   -- Red Herb
    [31] = true,  -- Handgun Ammo
    [61] = true,  -- Gunpowder
    [261] = true, -- Hip Pouch
}
local FALLBACK_SHARED_WEAPONS = {
    [65] = true, -- Hand Grenade
    [66] = true, -- Flash Grenade
}

local function fallbackOwner(itemId, weaponId)
    itemId = tonumber(itemId) or -1
    weaponId = tonumber(weaponId) or -1

    if weaponId > 0 then
        if FALLBACK_CARLOS_WEAPONS[weaponId] then
            return "carlos"
        end
        if FALLBACK_SHARED_WEAPONS[weaponId] then
            return "shared"
        end
        return nil
    end

    if itemId > 0 then
        if FALLBACK_CARLOS_ITEMS[itemId] then
            return "carlos"
        end
        if FALLBACK_SHARED_ITEMS[itemId] then
            return "shared"
        end
    end

    return nil
end

-- figure out which box an item goes in. weapons and items can share the same
-- decimal (MAG vs Handgun Ammo are both 31), so match weapon vs non-weapon too
function ItemBox.GetItemOwner(itemId, weaponId)
    itemId = tonumber(itemId) or -1
    weaponId = tonumber(weaponId) or -1

    local lookingForWeapon = weaponId > 0
    local targetDecimal = lookingForWeapon and weaponId or itemId

    for _, item in pairs(Lookups.items or {}) do
        local decimal = tonumber(item.decimal)
        if decimal ~= nil and decimal == targetDecimal then
            local itemIsWeapon = item.type == "Weapon" or item.type == "Subweapon"

            if itemIsWeapon == lookingForWeapon then
                local fromJson = normalizeOwner(item.owner)
                if fromJson then
                    return fromJson
                end
                break
            end
        end
    end

    return fallbackOwner(itemId, weaponId) or "jill"
end

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

function ItemBox.IsCommonBox()
    local lockerManager = sdk.get_managed_singleton(sdk.game_namespace("gamemastering.ItemLockerManager"))
    if not lockerManager then
        return false
    end

    local common = false
    pcall(function()
        common = lockerManager:get_field("isCommonBoxEnable") == true
    end)
    return common
end

-- BareHand / WeaponId=0 stubs left in Carlos's StorageItems2nd when shared items
-- were dual-written while the common box was enabled. UI shows them as
-- "Invalid Weapon ID : getWeaponName()" with an infinity count.
function ItemBox.CleanupInvalidWeaponSlots()
    local cleaned = 0

    local function cleanStorageList(mItems)
        if not mItems then
            return
        end

        local elements = nil
        if mItems.get_elements then
            elements = mItems:get_elements()
        else
            elements = mItems
        end

        for _, item in pairs(elements or {}) do
            if item ~= nil then
                local itemId = tonumber(item:get_ItemId()) or -1
                local weaponId = tonumber(item:get_WeaponId()) or -1
                local isWeapon = false
                pcall(function()
                    isWeapon = item:call("isWeaponAll") == true
                end)

                -- Weapon-typed slot with no real weapon id and no item id.
                if isWeapon and itemId <= 0 and weaponId <= 0 then
                    pcall(function()
                        item:call("setBlank")
                    end)
                    cleaned = cleaned + 1
                end
            end
        end
    end

    -- Persistent Jill/Carlos lists (what the box UI actually binds to).
    pcall(function()
        local lockerManager = sdk.get_managed_singleton(sdk.game_namespace("gamemastering.ItemLockerManager"))
        local save = lockerManager and lockerManager:get_field("gameSaveData")
        local lockerSave = save and save:get_field("SaveData")
        if lockerSave then
            for _, fieldName in ipairs({ "_Items", "_Items2nd" }) do
                local list = lockerSave:get_field(fieldName)
                if list then
                    local arr = list:get_field("mItems")
                    cleanStorageList(arr)
                end
            end
        end
    end)

    -- Live world gimmick, if a box is loaded.
    local itemLocker = ItemBox.GetAnyAvailable()
    if itemLocker ~= nil then
        local control = itemLocker:call(
            "getComponent(System.Type)",
            sdk.typeof(sdk.game_namespace("gimmick.action.GimmickItemLockerControl"))
        )
        if control then
            for _, fieldName in ipairs({ "StorageItems", "StorageItems2nd" }) do
                local storage = control:get_field(fieldName)
                if storage then
                    cleanStorageList(storage:get_field("mItems"))
                end
            end
        end
    end

    return cleaned
end

function ItemBox.AddItem(itemId, weaponId, weaponParts, bulletId, count, targetOwner)
    itemId = tonumber(itemId) or -1
    weaponId = tonumber(weaponId) or -1
    weaponParts = tonumber(weaponParts) or 0
    bulletId = tonumber(bulletId) or 0
    count = tonumber(count) or 1

    if weaponId <= 0 and itemId <= 0 then
        return false
    end

    targetOwner = targetOwner or ItemBox.GetItemOwner(itemId, weaponId) or "jill"

    -- write persistent storage first — that's what the box UI actually shows for
    -- Jill/Carlos. the world gimmick alone can "succeed" and still not show up
    local function addPersistent(survivorType)
        if survivorType == nil then
            return false
        end

        local lockerManager = sdk.get_managed_singleton(sdk.game_namespace("gamemastering.ItemLockerManager"))
        if lockerManager == nil then
            return false
        end

        -- AddStrage(survivor, itemId, ItemNum, weaponType, bulletId, BulletNum)
        -- The last arg is BulletNum, not parts. For a weapon slot that's the
        -- number the box shows, so count goes there -- passing parts (always 0)
        -- is what made grenades read as 0. Parts only apply to setWeapon below.
        -- Prefer WeaponType -1 for items. 0 is BareHand and was creating
        -- "Invalid Weapon ID" stubs in Carlos's StorageItems2nd.
        local ok = false
        if weaponId > 0 then
            ok = pcall(function()
                lockerManager:call("AddStrage", survivorType, 0, 1, weaponId, bulletId, count)
            end)
        else
            ok = pcall(function()
                lockerManager:call("AddStrage", survivorType, itemId, count, -1, 0, 0)
            end)
            if not ok then
                ok = pcall(function()
                    lockerManager:call("AddStrage", survivorType, itemId, count, 0, 0, 0)
                end)
            end
        end

        return ok
    end

    -- AddStrage wants a SurvivorDefine.SurvivorType, not a 0/1 index. JILL is
    -- actually 2, so the old hardcoded 0/1 pointed at whoever sits at those
    -- values and that's how Jill's launcher ended up in Carlos' list.
    local jill = Scene.getSurvivorEnumValue("JILL")
    local carlos = Scene.getSurvivorEnumValue("CARLOS")

    -- Jill and Carlos keep their own stores, even if the game has the common
    -- box flag set. Shared goes to both so whoever isn't active still finds
    -- their copy waiting.
    local survivors = { jill }
    if targetOwner == "carlos" then
        survivors = { carlos }
    elseif targetOwner == "shared" then
        survivors = { jill, carlos }
    end

    local added = false
    for _, survivorType in ipairs(survivors) do
        added = addPersistent(survivorType) or added
    end

    -- also poke the loaded locker gimmick so an open box stays in sync
    local itemLocker = ItemBox.GetAnyAvailable()
    if itemLocker ~= nil then
        local gimmickItemLockerControlComponent = itemLocker:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gimmick.action.GimmickItemLockerControl")))
        local storageItems = gimmickItemLockerControlComponent:get_field("StorageItems")
        local storageItems2nd = gimmickItemLockerControlComponent:get_field("StorageItems2nd")
        local mItems = storageItems:get_field("mItems")
        local mItems2nd = storageItems2nd:get_field("mItems")

        local targetStorages = { mItems }
        if targetOwner == "carlos" then
            targetStorages = { mItems2nd }
        elseif targetOwner == "shared" then
            targetStorages = { mItems, mItems2nd }
        end

        local function slotIsWritable(item)
            local blank = false
            pcall(function()
                blank = item:call("isBlank") == true
            end)
            if blank then
                return true
            end

            local slotItemId = tonumber(item:get_ItemId()) or -1
            local slotWeaponId = tonumber(item:get_WeaponId()) or -1
            -- WeaponId 0 is BareHand, not empty. Only treat true empties as free.
            return slotItemId <= 0 and slotWeaponId < 0
        end

        local function addItemToStorage(storage)
            for _, item in pairs(storage:get_elements()) do
                if item ~= nil and slotIsWritable(item) then
                    pcall(function()
                        item:call("setBlank")
                    end)

                    if weaponId > 0 then
                        item:setWeapon(weaponId, weaponParts, count, bulletId, 0)
                    else
                        local okSet = pcall(function()
                            item:call("setItem", itemId, count)
                        end)
                        if not okSet then
                            item:set_ItemId(itemId)
                            item:set_Count(count)
                        end
                    end
                    return true
                end
            end
            return false
        end

        for _, storage in ipairs(targetStorages) do
            if storage then
                added = addItemToStorage(storage) or added
            end
        end
    end

    return added
end

function ItemBox.DedupeItem(itemName, found)
    table.insert(ItemBox.waiting_to_dedupe, { itemName = itemName, found = found })
end

function ItemBox.DedupeItemId(itemId, weaponId, found)
    table.insert(ItemBox.waiting_to_dedupe, {
        itemId = tonumber(itemId) or -1,
        weaponId = tonumber(weaponId) or -1,
        found = found,
    })
end

function ItemBox.DedupeCheck()
    if #ItemBox.waiting_to_dedupe == 0 then
        return
    end

    local itemLocker = ItemBox.GetAnyAvailable()
    if itemLocker == nil then
        return
    end

    local control = itemLocker:call(
        "getComponent(System.Type)",
        sdk.typeof(sdk.game_namespace("gimmick.action.GimmickItemLockerControl"))
    )
    if not control then
        ItemBox.waiting_to_dedupe = {}
        return
    end

    local storageLists = {
        control:get_field("StorageItems"),
    }
    -- Common/shared box: StorageItems2nd is often the same slots. Blanking
    -- "duplicates" across both views deletes the only kept copy.
    if not ItemBox.IsCommonBox() then
        table.insert(storageLists, control:get_field("StorageItems2nd"))
    end

    -- ItemPersist may block setBlank on Lock Pick / Battery Pack; allow during
    -- this deferred pass (Inventory dedupe already ended its allow window).
    local needs_allow = false
    for _, dedupe in pairs(ItemBox.waiting_to_dedupe) do
        local id = tonumber(dedupe.itemId) or -1
        if id == 151 or id == 186 then
            needs_allow = true
            break
        end
    end
    if needs_allow and ItemPersist and ItemPersist.BeginAllowRemoves then
        ItemPersist.BeginAllowRemoves("box dedupe")
    end

    for _, dedupe in pairs(ItemBox.waiting_to_dedupe) do
        local itemId = tonumber(dedupe.itemId) or -1
        local weaponId = tonumber(dedupe.weaponId) or -1
        local itemName = dedupe.itemName
        local found = dedupe.found
        local kept = found == true

        for _, storageItems in pairs(storageLists) do
            if storageItems then
                local mItems = storageItems:get_field("mItems")
                if mItems and mItems.get_elements then
                    for _, v in pairs(mItems:get_elements()) do
                        if v ~= nil then
                            local matches = false
                            if itemId > 0 or weaponId > 0 then
                                local defaultItem = v:get_field("DefaultItem")
                                if defaultItem then
                                    local slotItemId = defaultItem:get_field("ItemId")
                                    local slotWeaponId = defaultItem:get_field("WeaponId")
                                    matches = (itemId > 0 and slotItemId == itemId)
                                        or (weaponId > 0 and slotWeaponId == weaponId)
                                end
                            elseif itemName and v.getName then
                                matches = v:getName() == itemName
                            end

                            if matches then
                                if kept then
                                    v:setBlank()
                                else
                                    kept = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    ItemBox.waiting_to_dedupe = {}

    if needs_allow and ItemPersist and ItemPersist.EndAllowRemoves then
        ItemPersist.EndAllowRemoves()
    end
end

return ItemBox
