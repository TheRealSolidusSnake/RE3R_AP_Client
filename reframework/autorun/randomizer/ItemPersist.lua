-- Prevent the game from stripping certain AP-granted key items on save/load.
-- Marks items as legitimately acquired; blocks rare RemoveItem/removeItem calls.
-- Does NOT hook setBlank — that path is extremely hot and caused frame lag once
-- receivedLockPick/receivedBatteryPack became true after AP connect.

local ItemPersist = {}

ItemPersist.isInit = false
ItemPersist.debug = false

-- When true, remove hooks stand down so ItemDuplicates can strip extras.
ItemPersist.allowDedupeRemoves = false

ItemPersist.protectedIds = {
    [151] = true, -- Lock Pick
    [186] = true, -- Battery Pack
}

local function log(msg)
    if not ItemPersist.debug then
        return
    end
    pcall(function()
        log.debug("[ItemPersist] " .. tostring(msg))
    end)
end

local function get_item_manager()
    return sdk.get_managed_singleton(sdk.game_namespace("gamemastering.ItemManager"))
end

local function extract_item_id(value)
    if value == nil then
        return nil
    end
    if type(value) == "number" then
        return value
    end

    local as_num = tonumber(value)
    if as_num ~= nil then
        return as_num
    end

    local s = tostring(value)
    local inner = string.match(s, "%((%-?%d+)%)")
    if inner then
        return tonumber(inner)
    end

    return tonumber(s)
end

local function is_received(item_id)
    if item_id == 151 then
        return Storage and Storage.receivedLockPick == true
    end
    if item_id == 186 then
        return Storage and Storage.receivedBatteryPack == true
    end
    return false
end

local function any_protected_received()
    return (Storage and Storage.receivedLockPick == true)
        or (Storage and Storage.receivedBatteryPack == true)
end

function ItemPersist.ShouldProtect(item_id)
    item_id = extract_item_id(item_id)
    if item_id == nil or not ItemPersist.protectedIds[item_id] then
        return false
    end
    if ItemPersist.allowDedupeRemoves then
        return false
    end
    return is_received(item_id)
end

function ItemPersist.IsProtectedId(item_id)
    item_id = extract_item_id(item_id)
    return item_id ~= nil and ItemPersist.protectedIds[item_id] == true
end

function ItemPersist.BeginAllowRemoves(reason)
    ItemPersist.allowDedupeRemoves = true
    log("allow removes ON (" .. tostring(reason) .. ")")
end

function ItemPersist.EndAllowRemoves()
    ItemPersist.allowDedupeRemoves = false
    log("allow removes OFF")
end

function ItemPersist.MarkAcquired(item_id)
    item_id = extract_item_id(item_id)
    if item_id == nil then
        return false
    end

    local im = get_item_manager()
    if im == nil then
        return false
    end

    local ok_once = pcall(function()
        im:call("setGetItemOnce", item_id)
    end)
    local ok_search = pcall(function()
        im:call("searchItem", item_id)
    end)

    log("MarkAcquired(" .. tostring(item_id) .. ") once=" .. tostring(ok_once)
        .. " search=" .. tostring(ok_search))

    return ok_once or ok_search
end

function ItemPersist.MarkProtectedFromName(item_name)
    if item_name == "Lock Pick" then
        return ItemPersist.MarkAcquired(151)
    end
    if item_name == "Battery Pack" then
        return ItemPersist.MarkAcquired(186)
    end
    return false
end

function ItemPersist.SetupRemoveHooks()
    local locker_td = sdk.find_type_definition(sdk.game_namespace("gamemastering.ItemLockerManager"))
    if locker_td then
        local method = locker_td:get_method("RemoveItem(offline.gamemastering.Item.ID, System.Int32)")
            or locker_td:get_method("RemoveItem")

        if method then
            sdk.hook(method, function(args)
                if ItemPersist.allowDedupeRemoves or not any_protected_received() then
                    return
                end
                local item_id = extract_item_id(sdk.to_int64(args[3]) & 0xFFFFFFFF)
                if ItemPersist.ShouldProtect(item_id) then
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end
            end)
        end

        local load_method = locker_td:get_method("loadGameSaveData")
        if load_method then
            sdk.hook(load_method, function(args)
            end, function(retval)
                if Storage.receivedLockPick then
                    ItemPersist.MarkAcquired(151)
                end
                if Storage.receivedBatteryPack then
                    ItemPersist.MarkAcquired(186)
                end
                return retval
            end)
        end
    end

    local inv_td = sdk.find_type_definition(sdk.game_namespace("gamemastering.InventoryManager"))
    if inv_td then
        local method = inv_td:get_method("removeItem(offline.gamemastering.Item.ID)")
            or inv_td:get_method("removeItem")

        if method then
            sdk.hook(method, function(args)
                if ItemPersist.allowDedupeRemoves or not any_protected_received() then
                    return
                end
                local item_id = extract_item_id(sdk.to_int64(args[3]) & 0xFFFFFFFF)
                if ItemPersist.ShouldProtect(item_id) then
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end
            end)
        end

        local reduce = inv_td:get_method("reduceItem(offline.gamemastering.Item.ID, System.Int32)")
            or inv_td:get_method("reduceItem")
        if reduce then
            sdk.hook(reduce, function(args)
                if ItemPersist.allowDedupeRemoves or not any_protected_received() then
                    return
                end
                local item_id = extract_item_id(sdk.to_int64(args[3]) & 0xFFFFFFFF)
                if ItemPersist.ShouldProtect(item_id) then
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end
            end)
        end
    end
end

function ItemPersist.Init()
    if ItemPersist.isInit then
        return
    end

    ItemPersist.isInit = true
    ItemPersist.SetupRemoveHooks()
    log("initialized")

    if Storage and Storage.receivedLockPick then
        ItemPersist.MarkAcquired(151)
    end
    if Storage and Storage.receivedBatteryPack then
        ItemPersist.MarkAcquired(186)
    end
end

return ItemPersist
