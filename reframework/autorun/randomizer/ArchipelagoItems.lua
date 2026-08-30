-- AP item receive / queue / logic-inventory tracking.

Archipelago.itemsQueue = {}
Archipelago.isProcessingItems = false -- this is set to true when the queue is being processed so we don't over-give
Archipelago.debugItems = false -- set true to log the item receive/queue pipeline when diagnosing stalls
Archipelago.lastCanReceiveLog = nil -- avoids spamming the CanReceiveItems reason every frame
Archipelago.hasReceivedItemsBefore = false -- this is set to true when the items received handler is called for the first time on the current connection

-- Collected AP items for client-side in-logic checks (ReceivedItems only).
Archipelago.collectedItemByIndex = {} -- [index] = item name
Archipelago.collectedItemCounts = {} -- [item name] = count
Archipelago.collectedStamp = 0

local function debug_item_log(message)
    if Archipelago.debugItems then
        log.info("[Randomizer][ItemDebug] " .. tostring(message))
    end
end

local function apply_trap(name)
    if name == "Parasite Trap" then
        return Player.Parasite()
    end

    return Player.Puke()
end

-- Traps that landed while Carlos was out. Jill owes us one, so hand it over
-- now that she's back. One per tick, otherwise a parasite and its cure both
-- land on the same frame and only the cure sticks.
function Archipelago.ProcessPendingTraps()
    local pending = Storage.pendingTraps
    if pending == nil or #pending == 0 or not Scene.isCharacterJill() then
        return
    end

    local name = table.remove(pending, 1)
    Storage.Update()

    apply_trap(name)
    GUI.AddText("Delivering the " .. name .. " Carlos dodged earlier.")
end

local function rebuild_collected_counts()
    local counts = {}
    for _, name in pairs(Archipelago.collectedItemByIndex) do
        if type(name) == "string" and name ~= "" then
            counts[name] = (counts[name] or 0) + 1
        end
    end
    Archipelago.collectedItemCounts = counts
    Archipelago.collectedStamp = (Archipelago.collectedStamp or 0) + 1
    if Logic and Logic.Invalidate then
        Logic.Invalidate()
    end
end

function Archipelago.TrackReceivedItems(items_received)
    if type(items_received) ~= "table" then
        return
    end

    local saw_zero = false
    for _, row in pairs(items_received) do
        if row and row["index"] == 0 then
            saw_zero = true
            break
        end
    end
    if saw_zero then
        Archipelago.collectedItemByIndex = {}
    end

    local changed = saw_zero
    for _, row in pairs(items_received) do
        if row and row["index"] ~= nil and row["item"] ~= nil then
            local item_data = Archipelago._GetItemFromItemsData({ id = row["item"] })
            local name = item_data and item_data["name"] and AP_REF.Sanitize(item_data["name"]) or nil
            if name and Archipelago.collectedItemByIndex[row["index"]] ~= name then
                Archipelago.collectedItemByIndex[row["index"]] = name
                changed = true
            end
        end
    end

    if changed then
        rebuild_collected_counts()
    end
end

function Archipelago.GetCollectedItemCount(itemName)
    if type(itemName) ~= "string" or itemName == "" then
        return 0
    end
    return Archipelago.collectedItemCounts[itemName] or 0
end

-- sent by server when items are received
function APItemsReceivedHandler(items_received)
    local result = Archipelago.ItemsReceivedHandler(items_received)
    return result
end
AP_REF.on_items_received = APItemsReceivedHandler

function Archipelago.ItemsReceivedHandler(items_received)
    local items_waiting = {}
    local damage_trap_received = false
    local parasite_trap_received = false
    local puke_trap_received = false

    -- keep logic inventory in sync even for already-processed indices
    pcall(Archipelago.TrackReceivedItems, items_received)

    debug_item_log(
        "ItemsReceivedHandler: received " .. tostring(#items_received)
        .. " row(s); lastSavedItemIndex=" .. tostring(Storage.lastSavedItemIndex)
        .. " lastReceivedItemIndex=" .. tostring(Storage.lastReceivedItemIndex)
    )

    -- If the AP room was regenerated/restarted, item numbering can reset while
    -- our stored indices are still from the old session. A live server always
    -- resyncs the full list (max index >= our count) or appends at index = count,
    -- so a batch whose highest index is below what we've already recorded means
    -- the server's item list reset.
    local max_incoming_index = nil
    for _, row in pairs(items_received) do
        if row["index"] ~= nil
            and (max_incoming_index == nil or row["index"] > max_incoming_index)
        then
            max_incoming_index = row["index"]
        end
    end

    if max_incoming_index ~= nil
        and (Storage.lastReceivedItemIndex or -1) >= 0
        and max_incoming_index < (Storage.lastReceivedItemIndex or -1)
    then
        debug_item_log(
            "  server item numbering reset detected (maxIncomingIndex="
            .. tostring(max_incoming_index) .. " < lastReceivedItemIndex="
            .. tostring(Storage.lastReceivedItemIndex)
            .. "); resetting local item indices"
        )
        Storage.lastSavedItemIndex = -1
        Storage.lastReceivedItemIndex = -1
        Storage.Update()
    end

    -- add all of the randomized items to an item queue to wait for send
    for k, row in pairs(items_received) do
        -- if the index of the incoming item is greater than the index of our last item at save, check to see if it's randomized
        -- because ONLY non-randomized items escape the queue; everything else gets queued
        if row["index"] ~= nil and (not Storage.lastSavedItemIndex or row["index"] > Storage.lastSavedItemIndex) then
            local item_data = Archipelago._GetItemFromItemsData({ id = row["item"] })

            -- An id the data package can't name would otherwise abort the whole
            -- batch, dropping every remaining item in this resync.
            if not item_data or not item_data["name"] then
                debug_item_log(
                    "  skipping row index=" .. tostring(row["index"])
                    .. ": unresolvable item id " .. tostring(row["item"])
                )
                goto continue_row
            end

            local item_name = AP_REF.Sanitize(item_data["name"])
            local location_data = nil
            local is_randomized = 1

            if row["location"] ~= nil and row["location"] > 0 then
                location_data = Archipelago._GetLocationFromLocationData({ id = row["location"] })

                if location_data and location_data['raw_data']['randomized'] ~= nil then
                    is_randomized = location_data['raw_data']['randomized']
                end
            end

            if item_name == "Victory" then
                Archipelago.ReceiveItem(item_name)
            end

            if item_name and
                not (item_name == "Victory") and 
                not (item_name == "Damage Trap" and damage_trap_received) and
                not (item_name == "Parasite Trap" and parasite_trap_received) and
                not (item_name == "Puke Trap" and puke_trap_received)
            then
                if item_name == "Damage Trap" then
                    damage_trap_received = true
                end
                if item_name == "Parasite Trap" then
                    parasite_trap_received = true
                end
                if item_name == "Puke Trap" then
                    puke_trap_received = true
                end

                if item_name and row["player"] ~= nil and is_randomized == 0 then
                    debug_item_log(
                        "  '" .. tostring(item_name) .. "' index=" .. tostring(row["index"])
                        .. " is_randomized=0 -> receiving directly"
                    )
                    Archipelago.ReceiveItem(AP_REF.Sanitize(item_name), row["player"], is_randomized)
                else
                    debug_item_log(
                        "  '" .. tostring(item_name) .. "' index=" .. tostring(row["index"])
                        .. " is_randomized=" .. tostring(is_randomized) .. " -> queued"
                    )
                    table.insert(Archipelago.itemsQueue, row)

                    -- Files / traps / hip pouches never wait on an item box
                    -- (ProcessImmediateItemsQueue drains them). Don't list them
                    -- in the "waiting for nearby item box" toast.
                    local waiting_ref = nil
                    for _, candidate in pairs(Lookups.items) do
                        if AP_REF.Sanitize(candidate.name) == item_name then
                            waiting_ref = candidate
                            break
                        end
                    end
                    if not Archipelago.IsImmediateEffectItem(item_name, waiting_ref) then
                        table.insert(items_waiting, item_name)
                    end
                end
            end
        else
            debug_item_log(
                "  row index=" .. tostring(row["index"])
                .. " skipped (<= lastSavedItemIndex="
                .. tostring(Storage.lastSavedItemIndex) .. ")"
            )
        end

        ::continue_row::
    end

    if not Archipelago.CanReceiveItems() and #items_waiting > 0 then
    	GUI.AddTexts({
        	{ message="Item(s) waiting for nearby item box: " },
        	{ message=table.concat(items_waiting, ", "), color=AP_REF.HexToImguiColor("AAAAAA") }
        })
    end

    Archipelago.hasReceivedItemsBefore = true
end

-- Log CanReceiveItems decisions, but only when the reason changes so we don't
-- flood the console every frame while an item is queued.
local function log_can_receive(result, reason)
    local key = tostring(result) .. "|" .. tostring(reason)
    if Archipelago.debugItems and Archipelago.lastCanReceiveLog ~= key then
        Archipelago.lastCanReceiveLog = key
        debug_item_log("CanReceiveItems=" .. tostring(result) .. " (" .. tostring(reason) .. ")")
    end
    return result
end

function Archipelago.CanReceiveItems()
    if not Scene.isInGame() then return log_can_receive(false, "not in game") end
    if Scene.isTransitioning() then return log_can_receive(false, "scene/character transition") end
    if not Archipelago.IsConnected() then return log_can_receive(false, "not connected") end
    if Scene.isUsingItemBox() then return log_can_receive(false, "item box UI busy") end
    if Inventory.GetPlayerInventory() == nil then return log_can_receive(false, "no player inventory") end
    if #Archipelago.itemsQueue == 0 then
        Archipelago.lastCanReceiveLog = nil
        return false
    end

    local row = Archipelago.itemsQueue[1]
    local item_data = row and Archipelago._GetItemFromItemsData({
        id = row["item"]
    })
    local item_name = item_data and AP_REF.Sanitize(item_data["name"])
    local item_ref = nil

    for _, item in pairs(Lookups.items) do
        if AP_REF.Sanitize(item.name) == item_name then
            item_ref = item
            break
        end
    end

    -- effects that don't enter inventory never need an item box
    if not item_ref
        or item_name == "Victory"
        or item_name == "Hip Pouch"
        or item_ref.type == "Trap"
        or item_ref.type == "File"
    then
        return log_can_receive(true, "'" .. tostring(item_name) .. "' needs no inventory slot")
    end

    local item_id = -1
    local weapon_id = -1
    if item_ref.type == "Weapon" or item_ref.type == "Subweapon" then
        weapon_id = tonumber(item_ref.decimal) or -1
    else
        item_id = tonumber(item_ref.decimal) or -1
    end

    local item_owner = ItemBox.GetItemOwner(item_id, weapon_id)
    local active_owner = nil
    if Scene.isCharacterJill() then
        active_owner = "jill"
    elseif Scene.isCharacterCarlos() then
        active_owner = "carlos"
    end

    -- Same test ReceiveItem uses. If it'll fit in hand we don't need a box.
    if active_owner ~= nil
        and (item_owner == "shared" or item_owner == active_owner)
        and item_ref.type ~= "Weapon"
        and Inventory.HasSpaceForItem()
        and not Inventory.IsFatItem(item_id, weapon_id, 0)
    then
        return log_can_receive(true, "'" .. tostring(item_name) .. "' fits "
            .. tostring(active_owner) .. " inventory")
    end

    -- weapons, fat items, wrong character, or a full inventory all need the box
    local box_available = ItemBox.GetAnyAvailable() ~= nil
    return log_can_receive(box_available,
        "'" .. tostring(item_name) .. "' owner=" .. tostring(item_owner)
        .. " active=" .. tostring(active_owner)
        .. " boxAvailable=" .. tostring(box_available))
end

function Archipelago.ProcessItemsQueue()
    -- if we're already processing items, wait for that to finish
    if Archipelago.isProcessingItems then
        return
    end

    if #Archipelago.itemsQueue == 0 then
        Archipelago.isProcessingItems = false
        return
    end

    Archipelago.isProcessingItems = true
    local row = table.remove(Archipelago.itemsQueue, 1)
    local delivered = true

    -- one item per update -- stops a compatible first item from dragging later
    -- incompatible ones through while no item box is loaded
    if row["index"] ~= nil
        and (not Storage.lastSavedItemIndex
            or row["index"] > Storage.lastSavedItemIndex)
    then
        local item_data = Archipelago._GetItemFromItemsData({
            id = row["item"]
        })
        local item_name = item_data and AP_REF.Sanitize(item_data["name"])
        local location_data = nil
        local is_randomized = 1

        if row["location"] ~= nil and row["location"] > 0 then
            location_data = Archipelago._GetLocationFromLocationData({
                id = row["location"]
            })

            if location_data
                and location_data['raw_data']['randomized'] ~= nil
            then
                is_randomized =
                    location_data['raw_data']['randomized']
            end
        end

        if item_name and row["player"] ~= nil then
            if Archipelago.didGameOver
                and item_name == "Damage Trap"
            then
                GUI.AddText(
                    "Received Damage Trap, but currently respawning. Ignoring."
                )
            else
                delivered = Archipelago.ReceiveItem(
                    item_name,
                    row["player"],
                    is_randomized
                ) ~= false
            end
        end

        if delivered
            and row["index"] ~= nil
            and (not Storage.lastReceivedItemIndex
                or row["index"] > Storage.lastReceivedItemIndex)
        then
            Storage.lastReceivedItemIndex = row["index"]
        end
    end

    if delivered then
        Storage.Update()
        Archipelago.didGameOver = false
    else
        table.insert(Archipelago.itemsQueue, 1, row)
    end

    Archipelago.isProcessingItems = false
end

-- Items that never need inventory/item-box space can get stuck forever behind
-- an earlier queued item waiting on a full pack or missing box. Pull those
-- effect items out of order (same pattern as Files).
function Archipelago.IsImmediateEffectItem(itemName, itemRef)
    if not itemName then
        return false
    end

    if itemName == "Victory" or itemName == "Hip Pouch" then
        return true
    end

    if itemRef and (itemRef.type == "Trap" or itemRef.type == "File") then
        return true
    end

    return false
end

function Archipelago.ProcessImmediateItemsQueue()
    if not Scene.isInGame() or not Archipelago.IsConnected() then
        return
    end

    -- hip pouch / traps are fine later; mutating during load can stall
    -- character transitions (Carlos RPD) on NOW LOADING
    if Scene.isTransitioning() then
        return
    end

    if Inventory.GetPlayerInventory() == nil then
        return
    end

    local received_any = false
    for index = #Archipelago.itemsQueue, 1, -1 do
        local row = Archipelago.itemsQueue[index]
        local item_data = row["item"] and Archipelago._GetItemFromItemsData({ id = row["item"] })
        local item_name = item_data and AP_REF.Sanitize(item_data["name"])
        local item_ref = nil

        for _, candidate in pairs(Lookups.items) do
            if item_name and AP_REF.Sanitize(candidate.name) == item_name then
                item_ref = candidate
                break
            end
        end

        local is_file = item_ref and item_ref.type == "File"
        local can_process = Archipelago.IsImmediateEffectItem(item_name, item_ref)
            and not (is_file and not Archipelago.files_as_locations)
            and not (Archipelago.didGameOver and item_name == "Damage Trap")

        if can_process then
            table.remove(Archipelago.itemsQueue, index)
            Archipelago.ReceiveItem(item_name, row["player"], 1)

            if row["index"] ~= nil and row["index"] > (Storage.lastReceivedItemIndex or -1) then
                Storage.lastReceivedItemIndex = row["index"]
            end
            received_any = true
        end
    end

    if received_any then
        Storage.Update()
    end
end

-- old name kept around for older call sites / hot-reloads
function Archipelago.ProcessFileItemsQueue()
    Archipelago.ProcessImmediateItemsQueue()
end

function Archipelago.ReceiveItem(item_name, sender, is_randomized)
    local item_ref = nil
    local item_number = nil
    local item_ammo = nil

    -- nil means "caller forgot"; treat as randomized so we still grant.
    if is_randomized == nil then
        is_randomized = 1
    end

    debug_item_log("ReceiveItem ENTER: '" .. tostring(item_name)
        .. "' is_randomized=" .. tostring(is_randomized))

    -- check for specific duplicates and, if true, don't receive this copy since we already have one
    if ItemDuplicates and ItemDuplicates.Check(item_name) then
        -- Still mark AP receipt so ItemPersist can protect if re-enabled.
        if item_name == "Lock Pick" then
            Storage.receivedLockPick = true
            Storage.Update()
            if ItemPersist then ItemPersist.MarkAcquired(151) end
        elseif item_name == "Battery Pack" then
            Storage.receivedBatteryPack = true
            Storage.Update()
            if ItemPersist then ItemPersist.MarkAcquired(186) end
        end

        GUI.AddText("Received a " .. item_name .. ", but you already have one. Skipping.")
        return
    end

    for k, item in pairs(Lookups.items) do
        if AP_REF.Sanitize(item.name) == item_name then
            item_ref = item
            item_number = item.decimal
            
            -- if it's a weapon, look up its ammo as well and set to item_ammo
            if item.type == "Weapon" and item.ammo ~= nil then
                for k2, item2 in pairs(Lookups.items) do
                    if AP_REF.Sanitize(item2.name) == item.ammo then
                        item_ammo = item2.decimal

                        break
                    end
                end
            end

            break
        end
    end

    if item_ref and item_ref.type == "File" then
        local player_self = Archipelago.GetPlayer()
        sender = sender or player_self.number
        local applied = Files.ApplyReceivedFile(item_ref)

        if applied then
            GUI.AddReceivedItemText(
                item_name,
                "06bda1",
                tostring(AP_REF.APClient:get_player_alias(sender)),
                tostring(player_self.alias),
                false
            )
        else
            GUI.AddText("Received " .. item_name .. "; it will unlock when the file manager is ready.")
        end
        return
    end

    if item_ref and item_number then
        local item_id, weapon_id, weapon_parts, bullet_id, count = nil

        if item_ref.type == "Weapon" or item_ref.type == "Subweapon" then
            item_id = -1
            weapon_id = item_number

            if item_ref.type == "Weapon" then
                bullet_id = item_ammo
            end
        else
            item_id = item_number
            weapon_id = -1
        end

        count = item_ref.count

        if count == nil then
            count = 1
        end

        if item_ref.type == "Ammo" and Archipelago.ammo_pack_modifier ~= "None" then
            local pmod = Archipelago.ammo_pack_modifier -- typing is hard
            local random_min = 1
            local random_max = math.ceil(count * 1.5) -- originally did 2x here, but high rolls made things too easy, this balanced out some

            -- if Max, cap the ammo at the game's defined maximum for each ammo pack (if the pack count is green in-game, it's at the max)
            if pmod == "Max" then 
                local ammo_maxes = {
                    ["Handgun Ammo"] = 60,
                    ["Shotgun Shells"] = 20,
                    ["Assault Rifle Ammo"] = 200,
                    ["MAG Ammo"] = 20,
                    ["Flame Rounds"] = 10,
                    ["Acid Rounds"] = 10,
                    ["Explosive Rounds"] = 10,
		    ["Mine Rounds"] = 10,
                }

                if ammo_maxes[item_ref.name] ~= nil then
                    count = ammo_maxes[item_ref.name]
                else
                    count = 500
                end
            end
            if pmod == "Double" then count = count * 2 end
            if pmod == "Half" then count = math.ceil(count / 2) end
            if pmod == "Only Three" then count = 3 end
            if pmod == "Only Two" then count = 2 end
            if pmod == "Only One" then count = 1 end
            if pmod == "Random Always" then count = math.random(random_min, random_max) end
            
            if pmod == "Random By Type" then
                if Archipelago.ammo_pack_type_amount[item_name] == nil then
                    Archipelago.ammo_pack_type_amount[item_name] = math.random(random_min, random_max)
                end

                count = Archipelago.ammo_pack_type_amount[item_name]
            end
        end

        if item_ref.progression == 1 then
            item_color = "ce28f7"
        elseif item_ref.type ~= "Lore" and item_ref.type ~= "Trap" then
            item_color = AP_REF.APUsefulColor
        elseif item_ref.type == "Trap" then
            item_color = AP_REF.APTrapColor
        else
            item_color = "06bda1"
        end
        
        local player_self = Archipelago.GetPlayer()
        local sent_to_box = false

        if sender == nil then
            sender = player_self.number
        end

        -- Match 0.2.9 / Working Beta: only AP-grant when the location is
        -- randomized. randomized:0 spots keep their vanilla world pickup;
        -- AP still toasts so the check is acknowledged.
        if is_randomized > 0 then
            if item_name == "Damage Trap" then
                Player.Damage(Archipelago.damage_traps_can_kill)
                GUI.AddReceivedItemText(item_name, item_color, tostring(AP_REF.APClient:get_player_alias(sender)), tostring(player_self.alias), sent_to_box)

                return
            end

            -- Parasite/Puke only work on Jill. Carlos has no parasite state, so
            -- park it and let it off the next time she's the one playing.
            if item_name == "Parasite Trap" or item_name == "Puke Trap" then
                if not Scene.isCharacterJill() then
                    Storage.pendingTraps = Storage.pendingTraps or {}
                    table.insert(Storage.pendingTraps, item_name)
                    Storage.Update()

                    GUI.AddText("Received " .. item_name .. ", holding it until Jill is back.")

                    return
                end

                apply_trap(item_name)

                GUI.AddReceivedItemText(item_name, item_color, tostring(AP_REF.APClient:get_player_alias(sender)), tostring(player_self.alias), sent_to_box)

                return
            end

            -- Hip Pouches expand every survivor inventory (Jill + Carlos).
            -- Cap is 20: 8 base + 5 AP pouches + 1 vanilla Carlos-hospital pouch.
            if item_name == "Hip Pouch" then
                if Inventory.IncreaseMaxSlots(2) then
                    GUI.AddReceivedItemText(item_name, item_color, tostring(AP_REF.APClient:get_player_alias(sender)), tostring(player_self.alias), sent_to_box)
                else
                    GUI.AddText("Received Hip Pouch, but inventory is at maximum size. Ignoring.")
                end

                return
            end

            local item_owner = ItemBox.GetItemOwner(item_id, weapon_id)
            local active_owner = nil
            if Scene.isCharacterJill() then
                active_owner = "jill"
            elseif Scene.isCharacterCarlos() then
                active_owner = "carlos"
            end

            -- Inventory first, but only when the character holding it can
            -- actually use it. True weapons need the box equip flow and fat
            -- (2-slot) items would have setSlot stomp the next slot, so those
            -- still get boxed. Grenades are fine in hand.
            -- HasSpaceForItem keeps 2 slots free so vanilla 2-slot pickups
            -- (the sewer Battery Pack) always have somewhere to go.
            local added_to_inventory = false
            if active_owner ~= nil
                and (item_owner == "shared" or item_owner == active_owner)
                and item_ref.type ~= "Weapon"
                and Inventory.GetPlayerInventory() ~= nil
                and Inventory.HasSpaceForItem()
                and not Inventory.IsFatItem(item_id, weapon_id, weapon_parts)
            then
                added_to_inventory = Inventory.AddItem(
                    tonumber(item_id),
                    tonumber(weapon_id),
                    weapon_parts,
                    bullet_id,
                    tonumber(count)
                )
            end

            debug_item_log("  distribute '" .. tostring(item_name)
                .. "' itemId=" .. tostring(item_id) .. " weaponId=" .. tostring(weapon_id)
                .. " owner=" .. tostring(item_owner) .. " active=" .. tostring(active_owner)
                .. " toInventory=" .. tostring(added_to_inventory))

            if added_to_inventory then
                -- Inventory only reaches the active survivor. With separate
                -- boxes, mirror a shared item into the other character's box
                -- so they still have a copy. With the common box, one physical
                -- store is shared — mirroring would double the AP grant.
                if item_owner == "shared" and not ItemBox.IsCommonBox() then
                    local other_owner = (active_owner == "jill") and "carlos" or "jill"
                    local mirrored = ItemBox.AddItem(
                        tonumber(item_id),
                        tonumber(weapon_id),
                        weapon_parts,
                        bullet_id,
                        tonumber(count),
                        other_owner
                    )
                    debug_item_log("  shared copy to " .. other_owner
                        .. " mirrored=" .. tostring(mirrored))
                end
            else
                sent_to_box = ItemBox.AddItem(
                    tonumber(item_id),
                    tonumber(weapon_id),
                    weapon_parts,
                    bullet_id,
                    tonumber(count),
                    item_owner
                )

                debug_item_log("  ItemBox.AddItem owner=" .. tostring(item_owner)
                    .. " sentToBox=" .. tostring(sent_to_box))

                if not sent_to_box then
                    GUI.AddText("Could not place received item; no inventory or item box slot was available.")
                    -- don't advance the AP index so we retry when there's room
                    return false
                end
            end
        end

        if item_name == "Lock Pick" then
            Storage.receivedLockPick = true
            Storage.Update()
            if ItemPersist then ItemPersist.MarkAcquired(151) end
        end

        if item_name == "Battery Pack" then
            Storage.receivedBatteryPack = true
            Storage.Update()
            if ItemPersist then ItemPersist.MarkAcquired(186) end
        end

        GUI.AddReceivedItemText(item_name, item_color, tostring(AP_REF.APClient:get_player_alias(sender)), tostring(player_self.alias), sent_to_box)
    end
end

function Archipelago._GetItemFromItemsData(item_data)
    local player = Archipelago.GetPlayer()
    local translated_item = {}
    
    translated_item['name'] = AP_REF.APClient:get_item_name(item_data['id'], player['game'])

    if not translated_item['name'] then
        return nil
    end

    translated_item['id'] = item_data['id']

    -- now that we have name and id, return them
    return translated_item
end

function Archipelago.ResetItemsState()
    Archipelago.itemsQueue = {}
    Archipelago.isProcessingItems = false
    Archipelago.lastCanReceiveLog = nil
    Archipelago.hasReceivedItemsBefore = false
    Archipelago.collectedItemByIndex = {}
    Archipelago.collectedItemCounts = {}
    Archipelago.collectedStamp = (Archipelago.collectedStamp or 0) + 1
    if Logic and Logic.Invalidate then
        Logic.Invalidate()
    end
end

return true
