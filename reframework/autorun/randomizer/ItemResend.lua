local ItemResend = {}

ItemResend.isInit = false

function ItemResend.Init()
    if not ItemResend.isInit then
        ItemResend.isInit = true
    end
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

    -- match the client receive behavior since I'm unsure if I can just "add" it any other way
    ItemBox.AddItem(itemId, weaponId, weaponParts, bulletId, count)
    return true
end

function ItemResend.GiveBatteryPack()
    local itemId = 186
    local weaponId = -1
    local weaponParts = 0
    local bulletId = 0
    local count = 1

    ItemBox.AddItem(itemId, weaponId, weaponParts, bulletId, count)
    return true
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

    ItemResend.GiveLockPick()
    GUI.AddText("Lock Pick was missing, restoring it to the item box.")
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

    ItemResend.GiveBatteryPack()
    GUI.AddText("Battery Pack was missing, restoring it to the item box.")
end

function ItemResend.CheckAll()
    ItemResend.CheckLockPick()
    ItemResend.CheckBatteryPack()
end

return ItemResend