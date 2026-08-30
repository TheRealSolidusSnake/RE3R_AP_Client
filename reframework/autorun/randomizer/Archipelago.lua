-- Archipelago connection / slot data.
-- Item receive, location checks, hints, and DeathLink live in sibling modules.

local Archipelago = {}

-- Connection / slot identity
Archipelago.seed = nil
Archipelago.slot = nil
Archipelago.hasConnectedPrior = false
Archipelago.isInit = false
Archipelago.waitingForSync = false
Archipelago.waitingForInvincibilityOff = false
Archipelago.pickupsBlocked = false -- New Disconnect Hook
Archipelago.didGameOver = false

-- Slot-data options 
Archipelago.apworld_version = nil
Archipelago.ammo_pack_modifier = nil
Archipelago.ammo_pack_type_amount = {}
Archipelago.damage_traps_can_kill = false
Archipelago.death_link = false
Archipelago.enemy_behavior = false
Archipelago.enemy_movement_speed_mode = "Off"
Archipelago.enemy_movement_speed = "Normal"
Archipelago.invisible_enemy_mode = "Off"
Archipelago.enemy_kills = false
Archipelago.files_as_locations = false

-- DeathLink session fields (owned by DeathLink.lua)
Archipelago.canDeathLink = false
Archipelago.wasDeathLinked = false
Archipelago.deathLinkTagActive = false
Archipelago.didWarnDeathLinkLocked = false
Archipelago.lastDeathLinkDiffCheck = nil

AP_REF.APGameName = "RE3Remake"

function Archipelago.Init()
    if not Archipelago.isInit then
        Archipelago.isInit = true
    end

    if Archipelago.HintsTick then
        Archipelago.HintsTick()
    end
end

function Archipelago.IsConnected()
    return AP_REF.APClient ~= nil and AP_REF.APClient:get_state() == AP_REF.AP.State.SLOT_CONNECTED
end

function Archipelago.GetPlayer()
    local player = {}

    if AP_REF.APClient == nil then
        return {}
    end

    player["slot"] = AP_REF.APClient:get_slot()
    player["seed"] = AP_REF.APClient:get_seed()
    player["number"] = AP_REF.APClient:get_player_number()
    player["alias"] = AP_REF.APClient:get_player_alias(player["number"])
    player["game"] = AP_REF.APClient:get_player_game(player["number"])

    return player
end

function Archipelago.Sync()
    if AP_REF.APClient == nil then
        return
    end

    SaveData.lastSyncTimestamp = os.time()
    AP_REF.APClient:Sync()
end

function Archipelago.DisableInGameClient(client_message)
    AP_REF.DisableInGameClient(client_message)
end

function Archipelago.EnableInGameClient()
    AP_REF.EnableInGameClient()
end

function APSlotConnectedHandler(slot_data)
    Archipelago.hasConnectedPrior = true
    Archipelago.pickupsBlocked = false
    if Files then
        Files.colliderRefreshNeeded = true
    end
    if AutoTab then
        AutoTab.Reset()
    end
    GUI.AddText("Connected.")

    return Archipelago.SlotDataHandler(slot_data)
end
AP_REF.on_slot_connected = APSlotConnectedHandler

function APSlotDisconnectedHandler()
    Archipelago.pickupsBlocked = Archipelago.hasConnectedPrior
    if Files then
        Files.colliderRefreshNeeded = true
    end
    GUI.AddText("Disconnected.")
    -- Keep the current slot's location data while disconnected.
    -- Interactionhooks need it to identify and block randomized pickups until reconnect.
    -- SlotDataHandler clears it when a different seed or slot connects.
end
AP_REF.on_socket_disconnected = APSlotDisconnectedHandler

function Archipelago.SlotDataHandler(slot_data)
    local player = Archipelago.GetPlayer()

    if (Archipelago.seed ~= nil and player["seed"] ~= Archipelago.seed)
        or (Archipelago.slot ~= nil and player["slot"] ~= Archipelago.slot)
    then
        GUI.AddText("Resetting mods because seed or slot name was changed.")

        Archipelago.Reset()
        Lookups.Reset()
        Storage.Reset()
    end

    Archipelago.seed = player["seed"]
    Archipelago.slot = player["slot"]

    if slot_data.apworld_version ~= nil then
        Archipelago.apworld_version = slot_data.apworld_version
    end

    if slot_data.ammo_pack_modifier ~= nil then
        Archipelago.ammo_pack_modifier = slot_data.ammo_pack_modifier
    end

    if slot_data.damage_traps_can_kill ~= nil then
        Archipelago.damage_traps_can_kill = slot_data.damage_traps_can_kill
    end

    if slot_data.death_link ~= nil then
        Archipelago.death_link = slot_data.death_link
    end
    Archipelago.didWarnDeathLinkLocked = false

    if slot_data.enemy_behavior ~= nil then
        Archipelago.enemy_behavior = slot_data.enemy_behavior
    end

    if slot_data.enemy_movement_speed_mode ~= nil then
        Archipelago.enemy_movement_speed_mode = slot_data.enemy_movement_speed_mode
    end

    if slot_data.enemy_movement_speed ~= nil then
        Archipelago.enemy_movement_speed = slot_data.enemy_movement_speed
    end

    if slot_data.invisible_enemy_mode ~= nil then
        Archipelago.invisible_enemy_mode = slot_data.invisible_enemy_mode
    end

    if slot_data.enemy_kills ~= nil then
        Archipelago.enemy_kills = slot_data.enemy_kills
    end

    if slot_data.files_as_locations ~= nil then
        local filesOption = string.lower(tostring(slot_data.files_as_locations))
        Archipelago.files_as_locations =
            filesOption == "all" or filesOption == "true" or filesOption == "1"
    end

    local difficulty = "standard"
    if slot_data ~= nil and slot_data.difficulty ~= nil then
        difficulty = string.lower(tostring(slot_data.difficulty))
    end
    Lookups.Load(difficulty)
    Files.RebuildFileObjectNames()
    Storage.Load()

    GUI.AddTexts({
        { message = "AP Difficulty: " },
        { message = string.upper(Lookups.difficulty or "standard"), color = "green" },
    })

    if Archipelago.enemy_behavior then
        GUI.AddTexts({
            { message = "Enemy Behavior: " },
            { message = string.upper(Archipelago.enemy_behavior), color = "yellow" },
        })
    end

    if Archipelago.enemy_movement_speed_mode and Archipelago.enemy_movement_speed_mode ~= "Off" then
        GUI.AddTexts({
            { message = "Enemy Speed: " },
            {
                message = string.upper(
                    tostring(Archipelago.enemy_movement_speed)
                        .. " ("
                        .. tostring(Archipelago.enemy_movement_speed_mode)
                        .. ")"
                ),
                color = "yellow",
            },
        })
    end

    if Archipelago.invisible_enemy_mode and Archipelago.invisible_enemy_mode ~= "Off" then
        GUI.AddTexts({
            { message = "Invisible Enemies: " },
            { message = string.upper(tostring(Archipelago.invisible_enemy_mode)), color = "yellow" },
        })
    end

    if Archipelago.enemy_kills then
        GUI.AddTexts({
            { message = "Enemy Kills: " },
            { message = string.upper(tostring(Archipelago.enemy_kills)), color = "yellow" },
        })
    end

    if Archipelago.files_as_locations then
        GUI.AddTexts({
            { message = "Files as Locations: " },
            { message = "ALL", color = "yellow" },
        })
    end

    -- core.lua may have already attached the DeathLink tag from slot data;
    -- force a sync so uncleared difficulties drop the tag immediately.
    if Archipelago.UpdateDeathLinkTag then
        Archipelago.UpdateDeathLinkTag(true)
    end

    for _, typewriter_name in pairs(slot_data.unlocked_typewriters or {}) do
        Typewriters.AddUnlockedText(typewriter_name, "", true) -- true for "no_save_warning"
        Typewriters.Unlock(typewriter_name, "")
    end

    if Archipelago.ClearHints then
        Archipelago.ClearHints()
    end
    if Archipelago.RequestHints then
        Archipelago.RequestHints()
    end
    Archipelago.hintsRetryAt = os.clock() + 2.0
end

-- Server print/JSON packets (sent-item toasts, hint notices).
function APPrintJSONHandler(json_rows, command)
    return Archipelago.PrintJSONHandler(json_rows, command)
end
AP_REF.on_print_json = APPrintJSONHandler

function Archipelago.PrintJSONHandler(json_rows, command)
    local player_sender, player_receiver, sender_number, receiver_number, item_id, location_id, item, location =
        nil
    local player = Archipelago.GetPlayer()
    local item_color = "06bda1"

    local isHint = false
    if type(command) == "table" and (command.type == "Hint" or command["type"] == "Hint") then
        isHint = true
    elseif #json_rows > 0 and json_rows[1]["text"] ~= nil and string.find(json_rows[1]["text"], "%[Hint%]") then
        isHint = true
    end

    if isHint then
        if Archipelago.RequestHints then
            Archipelago.RequestHints()
        end
        return
    end

    for _, row in pairs(json_rows) do
        if row["type"] ~= nil and row["type"] == "player_id" and not player_sender then
            player_sender = AP_REF.APClient:get_player_alias(tonumber(row["text"]))
            sender_number = tonumber(row["text"])
        elseif row["type"] ~= nil and row["type"] == "player_id" and player_sender then
            player_receiver = AP_REF.APClient:get_player_alias(tonumber(row["text"]))
            receiver_number = tonumber(row["text"])
        elseif row["type"] ~= nil and row["type"] == "item_id" then
            item_id = tonumber(row["text"])

            if (row["flags"] & 1) > 0 then
                item_color = "AF99EF"
            elseif (row["flags"] & 2) > 0 then
                item_color = AP_REF.APUsefulColor
            elseif (row["flags"] & 4) > 0 then
                item_color = AP_REF.APTrapColor
            else
                item_color = "06bda1"
            end
        elseif row["type"] ~= nil and row["type"] == "location_id" then
            location_id = tonumber(row["text"])
        end
    end

    if player_sender and item_id and player_receiver and location_id then
        if player["alias"] ~= nil and player_sender == player["alias"] then
            local lastRow = json_rows[#json_rows]
            if not Storage.lastSavedItemIndex
                or lastRow == nil
                or lastRow["index"] == nil
                or lastRow["index"] > Storage.lastSavedItemIndex
            then
                if player_receiver then
                    item = AP_REF.APClient:get_item_name(
                        item_id,
                        AP_REF.APClient:get_player_game(receiver_number)
                    )
                    location = AP_REF.APClient:get_location_name(location_id, player["game"])

                    GUI.AddSentItemText(player_sender, item, item_color, player_receiver, location)
                end
            end
        end
    end
end

function Archipelago.Reset()
    Archipelago.seed = nil
    Archipelago.slot = nil
    Archipelago.apworld_version = nil
    Archipelago.ammo_pack_modifier = nil
    Archipelago.ammo_pack_type_amount = {}
    Archipelago.damage_traps_can_kill = false
    Archipelago.enemy_behavior = false
    Archipelago.enemy_movement_speed_mode = "Off"
    Archipelago.enemy_movement_speed = "Normal"
    Archipelago.invisible_enemy_mode = "Off"
    Archipelago.enemy_kills = false
    Archipelago.files_as_locations = false
    Archipelago.pickupsBlocked = false
    Archipelago.didGameOver = false
    Archipelago.waitingForSync = false
    Archipelago.waitingForInvincibilityOff = false

    if Archipelago.ResetDeathLinkState then
        Archipelago.ResetDeathLinkState()
    else
        Archipelago.death_link = false
        Archipelago.deathLinkTagActive = false
        Archipelago.didWarnDeathLinkLocked = false
        Archipelago.lastDeathLinkDiffCheck = nil
        Archipelago.canDeathLink = false
        Archipelago.wasDeathLinked = false
    end

    if Archipelago.ResetItemsState then
        Archipelago.ResetItemsState()
    end
    if Archipelago.ResetLocationsState then
        Archipelago.ResetLocationsState()
    end
    if Archipelago.ClearHints then
        Archipelago.ClearHints()
    end
end

-- sibling modules hang their handlers / helpers off this table
_G.Archipelago = Archipelago
require("randomizer/ArchipelagoLocations") -- before Items (queue uses location lookup)
require("randomizer/ArchipelagoItems")
require("randomizer/ArchipelagoHints")
require("randomizer/DeathLink")

return Archipelago
