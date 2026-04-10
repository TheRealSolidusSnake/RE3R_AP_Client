local ItemResend = {}

ItemResend.isInit = false
ItemResend.lastCheckTime = 0
ItemResend.checkIntervalSeconds = 1

function ItemResend.Init()
    if not ItemResend.isInit then
        ItemResend.isInit = true
        ItemResend.lastCheckTime = 0
    end
end

function ItemResend.ShouldCheckNow()
    local now = os.time()

    if ItemResend.lastCheckTime == nil or (now - ItemResend.lastCheckTime) >= ItemResend.checkIntervalSeconds then
        ItemResend.lastCheckTime = now
        return true
    end

    return false
end

function ItemResend.HasItem(item_name)
    local names_in_inventory = Inventory.GetItemNames()
    local names_in_itembox = ItemBox.GetItemNames()

    for _, v in pairs(names_in_inventory) do
        if v == item_name then
            return true
        end
    end

    for _, v in pairs(names_in_itembox) do
        if v == item_name then
            return true
        end
    end

    return false
end

function ItemResend.GiveLockPick()
    local itemId = 151
    local weaponId = -1
    local weaponParts = 0
    local bulletId = 0
    local count = 1

    if Inventory.HasSpaceForItem() then
        local addedToInventory = Inventory.AddItem(itemId, weaponId, weaponParts, bulletId, count)

        if addedToInventory then
            return "inventory"
        end
    end

    ItemBox.AddItem(itemId, weaponId, weaponParts, bulletId, count)
    return "item box"
end

function ItemResend.GiveBatteryPack()
    local itemId = 186
    local weaponId = -1
    local weaponParts = 0
    local bulletId = 0
    local count = 1

    ItemBox.AddItem(itemId, weaponId, weaponParts, bulletId, count)
    return "item box"
end

function ItemResend.ShouldKeepResendingLockPick()
    if not Storage.receivedLockPick then
        return false
    end

    if Storage.seenLockPick then
        return false
    end

    return true
end

function ItemResend.CheckLockPick()
    if not ItemResend.ShouldKeepResendingLockPick() then
        return
    end

    if ItemResend.HasItem("Lock Pick") then
        return
    end

    local restoredTo = ItemResend.GiveLockPick()
    GUI.AddText("Lock Pick was missing, restoring it to the " .. restoredTo .. ".")
end

function ItemResend.ShouldKeepResendingBatteryPack()
    if not Storage.receivedBatteryPack then
        return false
    end

    if Storage.seenBatteryPack then
        return false
    end

    return true
end

function ItemResend.CheckBatteryPack()
    if not ItemResend.ShouldKeepResendingBatteryPack() then
        return
    end

    if ItemResend.HasItem("Battery Pack") then
        return
    end

    local restoredTo = ItemResend.GiveBatteryPack()
    GUI.AddText("Battery Pack was missing, restoring it to the " .. restoredTo .. ".")
end

function ItemResend.CheckAll()
    ItemResend.CheckLockPick()
    ItemResend.CheckBatteryPack()
end

function ItemResend.Update()
    if not ItemResend.isInit then
        return
    end

    if not ItemResend.ShouldCheckNow() then
        return
    end

    if not Archipelago.CanReceiveItems() then
        return
    end

    ItemResend.CheckAll()
end

return ItemResend
