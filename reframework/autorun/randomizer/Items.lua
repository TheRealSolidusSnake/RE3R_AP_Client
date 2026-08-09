local Items = {}
Items.isInit = false -- keeps track of whether init things like hook need to run
Items.lastInteractable = nil
Items.cancelNextUI = false
Items.cancelNextSafeUI = false
Items.cancelNextStatueUI = false
Items.lastSafeMapIconCleanup = 0
Items.lastDisconnectWarningKey = nil
Items.lastDisconnectWarningTime = 0

function Items.RemoveSafeMapIcons(gimmickBody, itemPositions)
    -- Safes register a native gimmick marker separately from their reward item.
    -- Normally the safe FSM removes it, but the randomizer bypasses that path.
    if gimmickBody then
        local gimmickControl = nil
        pcall(function()
            gimmickControl = gimmickBody:get_field("_GimmickControl")
        end)

        if gimmickControl then
            pcall(function()
                gimmickBody:call("requestGimmickIconRemove", gimmickControl)
            end)
            pcall(function()
                gimmickControl:set_field("isRemovedMapIcon", true)
            end)
        else
            -- Some dials expose the control on the same object as the body.
            pcall(function()
                local control = gimmickBody:call(
                    "get_GameObject()"
                ):call(
                    "getComponent(System.Type)",
                    sdk.typeof(sdk.game_namespace("gimmick.action.GimmickControl"))
                )
                if control then
                    gimmickBody:call("requestGimmickIconRemove", control)
                    control:set_field("isRemovedMapIcon", true)
                end
            end)
        end
    end

    -- Also disable the reward's SetItem save record so MapIcons does not add
    -- a separate item marker after the physical reward has been destroyed.
    if itemPositions then
        pcall(function()
            Storage.MarkCheckedItem(itemPositions)
        end)
        pcall(function()
            itemPositions:call("setCleared()")
        end)

        local itemManager = sdk.get_managed_singleton(
            sdk.game_namespace("gamemastering.ItemManager")
        )
        local itemGuid = itemPositions:get_field("MyGuid")
        local location = Scene.getCurrentLocation()

        if itemManager and itemGuid and location ~= nil then
            local saveData = itemManager:call("getSetItemSaveData", itemGuid, location)

            if saveData then
                saveData:set_field("Enable", false)
            end
        end
    end
end

function Items.RemoveStoredSafeMapIcons(force)
    if not force and os.time() - Items.lastSafeMapIconCleanup < 2 then
        return
    end

    Items.lastSafeMapIconCleanup = os.time()

    local openedSafes = {
        {
            opened = Storage.dotSightSafe,
            controlName = "0232_sm42_019_SafeBoxDial01A_00_control"
        },
        {
            opened = Storage.hipPouchSafe,
            controlName = "sm42_019_SafeBoxDial01A_OfficeW_control"
        },
        {
            opened = Storage.dualMagSafe,
            controlName = "0101_sm42_019_SafeBoxDial01A_control"
        }
    }
    local scene = Scene.getSceneObject()

    if not scene then
        return
    end

    for _, safe in pairs(openedSafes) do
        if safe.opened then
            pcall(function()
                local controlObject = scene:call(
                    "findGameObject(System.String)",
                    safe.controlName
                )

                if not controlObject then
                    return
                end

                local gimmickControl = controlObject:call(
                    "getComponent(System.Type)",
                    sdk.typeof(sdk.game_namespace("gimmick.action.GimmickControl"))
                )
                local gimmickBody = gimmickControl and gimmickControl:get_field("_MyGimmickBody")

                -- Dial object often owns the map marker the player actually sees.
                local dialBody = controlObject:call(
                    "getComponent(System.Type)",
                    sdk.typeof(sdk.game_namespace("gimmick.action.GimmickBody"))
                )

                local controlTransform = controlObject:call("get_Transform()")
                local parentTransform = controlTransform and controlTransform:call("get_Parent()")
                local parentObject = parentTransform and parentTransform:call("get_GameObject()")
                local addItem = parentObject and parentObject:call(
                    "getComponent(System.Type)",
                    sdk.typeof(sdk.game_namespace("gimmick.option.AddItemToInventorySettings"))
                )
                local itemPositionObject = addItem and addItem:get_field("ItemPositions")
                local itemPositions = itemPositionObject and itemPositionObject:call(
                    "getComponent(System.Type)",
                    sdk.typeof(sdk.game_namespace("item.ItemPositions"))
                )

                Items.RemoveSafeMapIcons(gimmickBody or dialBody, itemPositions)
                if dialBody and dialBody ~= gimmickBody then
                    Items.RemoveSafeMapIcons(dialBody, itemPositions)
                end
            end)
        end
    end
end

-- Hook registration only — safe during in-game AP connect grace.
function Items.InitHooksOnly()
    if Items.isInit then
        return
    end

    Items.isInit = true
    Items.SetupInteractHook()
    Items.SetupDisconnectWaitHook()
    Items.SetupSafeUIHook()
    Items.SetupStatueUIHook()
end

function Items.Init()
    Items.InitHooksOnly()

    Items.RemoveStoredSafeMapIcons()
    if HospitalDefenseSkip then
        HospitalDefenseSkip.Update()
    end
end

function Items.SetupInteractHook()
    local interactType = sdk.find_type_definition(sdk.game_namespace("gimmick.action.FeedbackFSM"))
    local interact_method = interactType:get_method("execute")

    -- main item hook, does all the AP stuff
    sdk.hook(interact_method, function(args)
        feedbackFSM = sdk.to_managed_object(args[2])
        feedbackParent = sdk.to_managed_object(feedbackFSM:get_field('_Owner'))
        
        item_name = feedbackParent:call("get_Name()")
        item_folder = feedbackParent:call("get_Folder()")
        item_folder_path = nil
        item_parent_name = nil
        item_positions = nil

        if item_folder then
            item_folder_path = item_folder:call("get_Path()")
        end

        if item_name and item_folder and feedbackParent then
            item_transform = sdk.to_managed_object(feedbackParent:call('get_Transform()'))
            item_transform_parent = sdk.to_managed_object(item_transform:call('get_Parent()'))

            if item_transform_parent then
                item_parent = sdk.to_managed_object(item_transform_parent:call('get_GameObject()'))
                item_parent_name = item_parent:call("get_Name()")
                item_positions = item_parent:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("item.ItemPositions")))

                if not item_name or not item_folder_path or not item_positions then
                    item_parent_name = "" -- unset so we know it's a non-standard item location
                end
            else
                -- non-item things like typewriters here, so do typewriter interaction tracking
                if string.match(item_name, "Typewriter") then
                    if not Typewriters.unlocked_typewriters[item_name] then
                        Typewriters.AddUnlockedText("", item_name)
                    end

                    Typewriters.Unlock("", item_name)
                end
            end
        end

        -- if item_name and item_folder_path are not nil (even empty strings), do a location lookup to see if we should get an item
        if item_name ~= nil and item_folder_path ~= nil then
            local location_to_check = {}
            location_to_check['item_object'] = item_name
            location_to_check['parent_object'] = item_parent_name or ""
            location_to_check['folder_path'] = item_folder_path
            if item_positions and Storage and Storage.GetGuidString then
                local guid = Storage.GetGuidString(
                    item_positions:get_field("MyGuid")
                )
                if guid ~= nil and guid ~= "" then
                    location_to_check['object_guid'] = guid
                end
            end

            local function locationMatches(loc)
                if not loc then
                    return false
                end
                local dataGuid = location_to_check.object_guid
                local locGuid = loc.object_guid
                local hasDataGuid = dataGuid ~= nil and dataGuid ~= ""
                local hasLocGuid = locGuid ~= nil and locGuid ~= ""
                if hasDataGuid and hasLocGuid
                    and string.lower(tostring(dataGuid))
                        == string.lower(tostring(locGuid))
                then
                    return true
                end
                -- Guid-keyed rows are GUID-only (same as Archipelago matching).
                if hasLocGuid then
                    return false
                end
                return loc.item_object == location_to_check.item_object
                    and loc.parent_object == location_to_check.parent_object
                    and loc.folder_path == location_to_check.folder_path
            end

            local isKnownFile = false
            for _, fileLocation in pairs(Lookups.files or {}) do
                if locationMatches(fileLocation) then
                    isKnownFile = true
                    break
                end
            end

            if LocationCapture and location_to_check.object_guid then
                if location_to_check.file_id or isKnownFile then
                    location_to_check.capture_kind = "files"
                else
                    location_to_check.capture_kind = "locations"
                end
                pcall(function()
                    LocationCapture.Capture(location_to_check)
                end)
            end

            -- Reject pickups before FeedbackFSM can open a UI, award an item, or retire the world object.
            -- Closing the UI afterward is too late.
            if not Archipelago.IsConnected() then
                log.debug("Archipelago is not connected.")

                local isKnownLocation = isKnownFile
                if not isKnownLocation then
                    for _, location in pairs(Lookups.locations or {}) do
                        if locationMatches(location) then
                            isKnownLocation = true
                            break
                        end
                    end
                end

                if Archipelago.hasConnectedPrior and isKnownLocation then
                    local warningKey = table.concat({
                        tostring(location_to_check.item_object),
                        tostring(location_to_check.parent_object),
                        tostring(location_to_check.folder_path)
                    }, "|")
                    if Items.lastDisconnectWarningKey ~= warningKey then
                        GUI.AddText(
                            "Archipelago is disconnected. Pickup was blocked; reconnect and try again."
                        )
                        Items.lastDisconnectWarningKey = warningKey
                        Items.lastDisconnectWarningTime = os.clock()
                    end

                    if not isKnownFile then
                        Items.cancelNextUI = true
                        Items.cancelNextUIExpires = os.clock() + 3
                    end
                end

                return
            end

            -- Physical documents also pass through FeedbackFSM.execute before
            -- UIFileManager.getFile. Match the source file table directly so
            -- this generic item hook cannot send their AP checks first.
            if Archipelago.files_as_locations and isKnownFile then
                return
            end

            -- If we're interacting with the victory location, send victory and bail
            if Archipelago.CheckForVictoryLocation(location_to_check) then
                Archipelago.SendLocationCheck(location_to_check) -- doesn't check for fail, but game is over, so release if needed, can fix later
                GUI.AddText("Goal Completed!")

                return
            end

            -- If we run through a trigger with "AutoSaveArea" or "CheckPoint" in the name, the game just auto-saved. 
            --    So a save point and not an item, so return out. 
            --    (Used to update last saved to last received, but handled in SaveData hooks now.)
            if string.find(item_name, "AutoSaveArea") then
                -- Storage.UpdateLastSavedItems()

                return
            end

            if HospitalDefenseSkip then
                local skip = HospitalDefenseSkip.OnInteract(item_name, item_folder_path)
                if skip ~= nil then
                    return skip
                end
            end

            -- In-Game messages to warn the players if they are about to f themselves by going through a "one way"

            if item_name == "sm42_505_ES_C4Bomb01A_CH2_gimmick" and item_folder_path == "RopewayContents/World/Location_RPD/LocationLevel_RPD/Scenario/S02_0300/ES_S02_0300/ShowerRoomBlownUp" then
                GUI.AddRainbowWarning({
                    "Warning: Entering the STARS Office is a one way trip",
                    "The STARS Office also has permanently missable items in it",
                    "It is recommended you complete all checks in the RPD prior to entering the office",
                })
            end

            if item_name == "msg15_wait" and item_folder_path == "RopewayContents/World/Location_Hospital/LocationLevel_Hospital/Scenario/S04_0300/ES_S04_0300/Msg" then

                GUI.AddRainbowWarning({
                    "Warning: Curing Jill will prevent you from getting earlier item checks",
                    "Locations in the Hospital will be gone forever if you happened to skip any",
                    "It is recommended you complete all checks in the Hospital prior to curing Jill",
                })
            end

            -- We check if we've seen the cutscenes/physical location of the item to determine if we should be giving it back to the player or not
            -- Lock Pick: AP check is EV322_k; map marker is EV325_obj. Clear both paths.
            if CutsceneObjects
                and CutsceneObjects.IsLockPickLocation
                and CutsceneObjects.IsLockPickLocation(item_name, item_folder_path)
            then
                CutsceneObjects.MarkLockPickSeen()
            end

            if item_name == "sm73_305" and
            item_folder_path == "RopewayContents/World/Location_DownTown/LocationLevel_DownTown/LocationFsm_DownTown/S03_1000/ES_S03_1000/Item/ES_S03_1000/KeyItem" then
                if not Storage.seenBatteryPack then
                    Storage.seenBatteryPack = true
                    Storage.Update()
                end
            end

            -- Close the Clock Puzzle door after each jewel check.
            -- Vanish can leave the gimmick open; 
            -- RequestClockPuzzleClose settles that race and persists clockDoorFixed for area-load re-close.
            if (
                item_name == "WP6200" and item_folder_path == "RopewayContents/World/Location_DownTown/LocationLevel_DownTown/LocationFsm_DownTown/S03_1000/ES_S03_1000/Item/ES_S03_1000/I_100_Subway_Area/JewelryBox"
            ) or (
                item_name == "sm71_101" and item_folder_path == "RopewayContents/World/Location_DownTown/LocationLevel_DownTown/LocationFsm_DownTown/S03_1000/ES_S03_1000/Item/ES_S03_1000/I_100_Subway_Area/JewelryBox"
            ) or (
                item_name == "sm74_200" and item_folder_path == "RopewayContents/World/Location_DownTown/LocationLevel_DownTown/LocationFsm_DownTown/S03_1000/ES_S03_1000/Item/ES_S03_1000/I_100_Subway_Area/JewelryBox"
            ) then
                CutsceneObjects.RequestClockPuzzleClose()
            end


            -- We were attempting to "destroy" the safe item (which worked but left the icon)
            -- We now clear the icon properly so it clears the map after the location is checked
            local safeStorageKey = nil

            if item_name == "0232_sm42_019_SafeBoxDial01A_00_control" and 
            item_folder_path == "RopewayContents/World/Location_DownTown/LocationLevel_DownTown/LocationFsm_DownTown/S03_1000/ES_S03_1000/SafeBox" then
                safeStorageKey = "dotSightSafe"
            end

            if item_name == "sm42_019_SafeBoxDial01A_OfficeW_control" and 
            item_folder_path == "RopewayContents/World/Location_RPD/LocationLevel_RPD/LocationFsm_RPD/common/ES_common/1FW/WestOffice/IronSafe_1FWOffice" then
                safeStorageKey = "hipPouchSafe"
            end

            if item_name == "0101_sm42_019_SafeBoxDial01A_control" and 
            item_folder_path == "RopewayContents/World/Location_Hospital/LocationLevel_Hospital/LocationFsm_Hospital/common/ES_common/SafeBox" then
                safeStorageKey = "dualMagSafe"
            end

            local translatedLocation = Archipelago._GetLocationFromLocationData(
                Archipelago.SanitizeLocationData(location_to_check),
                true
            )
            -- Files are identified by file_id (not a separate location_type field).
            local isFileLocation = translatedLocation
                and translatedLocation.raw_data
                and translatedLocation.raw_data.file_id ~= nil

            -- Files have their own getFile/openFile hooks. Processing them
            -- here as normal items sends the same AP location multiple times.
            if isFileLocation then
                return
            end

            local isLocationRandomized = Archipelago.IsLocationRandomized(location_to_check)

            if Archipelago.IsItemLocation(location_to_check) then
                local locationSentSuccess = Archipelago.SendLocationCheck(location_to_check)
                Archipelago.waitingForInvincibilityOff = true
                if locationSentSuccess == nil then -- both true and false responses are valid for removing the location, nil is not
                    GUI.AddText("Location did not send because of a connection issue. Please verify that your AP room is up and try again.")
                    Items.cancelNextUI = true
                    Items.cancelNextUIExpires = os.clock() + 3
                    return
                end

                if safeStorageKey and not Storage[safeStorageKey] then
                    Storage[safeStorageKey] = true
                    Storage.Update()
                end

                -- AP checks get cleared off when checked if we use Poptracker
                -- so we try to mirror that by persistently removing map icons
                -- for locations we've already checked, regardless of death etc
                Storage.MarkCheckedItem(item_positions)

                -- Shower Wall gadget; I couldn't randomize it before with how we handle items..
                -- so let vanilla FSM finish, then strip the granted Electronic Gadget
                if item_positions and isLocationRandomized then
                    if CutsceneObjects and CutsceneObjects.IsShowerWallGadget(item_name, item_folder_path) then
                        CutsceneObjects.BeginShowerWallGadgetStrip()
                    else
                        item_positions:call('vanishItemAndSave()')
                    end
                end

                if string.find(item_name, "SafeBoxDial") then -- if it's a safe, cancel the next safe ui
                    Items.cancelNextSafeUI = true
                    Items.lastInteractable = feedbackParent
                elseif string.find(item_name, "HieroglyphicDialLock") then -- if it's a statue, cancel the next statue ui
                    Items.cancelNextStatueUI = true
                    Items.lastInteractable = feedbackParent
                end
                -- local inputSystem = sdk.get_managed_singleton(sdk.game_namespace("InputSystem"))
                -- inputSystem:MouseCancelPC() -- this is so hacky, lol
            elseif location_to_check.object_guid then
                -- Guid-keyed JSON rows no longer tuple-fallback. Surface why.
                Archipelago.ExplainGuidMatchFailure(location_to_check)
            end
        end

        Archipelago.waitingForInvincibilityOff = true
    end)
end

function Items.SetupDisconnectWaitHook()
    -- I couldn't revive the old disconnect hook for RTX.. so we changed it a quite a bit so most interacts disappear/reappear if we disconnect/reconnect to AP
    local itemPositionsType = sdk.find_type_definition(
        sdk.game_namespace("item.ItemPositions")
    )
    local checkItemPickMethod = itemPositionsType and itemPositionsType:get_method(
        "checkEnableItemPick"
    )

    if checkItemPickMethod then
        sdk.hook(checkItemPickMethod, nil, function(retval)
            if Archipelago.pickupsBlocked then
                return sdk.to_ptr(false)
            end

            return retval
        end)
    else
        log.error(
            "[Randomizer] Could not hook ItemPositions.checkEnableItemPick."
        )
    end

    local playerInventoryType = sdk.find_type_definition(
        sdk.game_namespace("survivor.Inventory")
    )
    local setSlotSignatures = {
        "setSlot(System.Int32, offline.gamemastering.Item.ID, System.Int32, offline.gamemastering.InventoryManager.PrimitiveItem, offline.gamemastering.InventoryManager.ItemExData)",
        "setSlot(System.Int32, offline.EquipmentDefine.WeaponType, offline.EquipmentDefine.WeaponParts, offline.gamemastering.Item.ID, System.Int32, offline.gamemastering.InventoryManager.ItemExData)"
    }

    if playerInventoryType then
        for _, signature in ipairs(setSlotSignatures) do
            local setSlotMethod = playerInventoryType:get_method(signature)
            if setSlotMethod then
                sdk.hook(setSlotMethod, function(args)
                    if Items.cancelNextUI
                        and Archipelago.pickupsBlocked
                    then
                        return sdk.PreHookResult.SKIP_ORIGINAL
                    end
                end, function(retval)
                    if CutsceneObjects and CutsceneObjects.pendingStripElectronicGadget then
                        CutsceneObjects.HandleShowerWallGadgetStrip()
                    end
                    return retval
                end)
            else
                log.error(
                    "[Randomizer] Could not hook survivor.Inventory."
                    .. signature
                )
            end
        end
    else
        log.error("[Randomizer] Could not find survivor.Inventory.")
    end

    local addItemType = sdk.find_type_definition(
        sdk.game_namespace("gimmick.option.AddItemToInventorySettings")
    )
    if addItemType then
        local buildItemMethod = addItemType:get_method("BuildItemData")
        local addSelectedMethod = addItemType:get_method("AddSelectedStock")

        if buildItemMethod then
            sdk.hook(buildItemMethod, function(args)
                if Items.cancelNextUI
                    and Archipelago.pickupsBlocked
                then
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end
            end)
        end

        if addSelectedMethod then
            sdk.hook(addSelectedMethod, function(args)
                if Items.cancelNextUI
                    and Archipelago.pickupsBlocked
                then
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end
            end)
        end
    else
        log.error(
            "[Randomizer] Could not find AddItemToInventorySettings."
        )
    end

    local inventoryType = sdk.find_type_definition(
        sdk.game_namespace("gui.EsInventoryBehavior")
    )
    if not inventoryType then
        log.error("[Randomizer] Could not find EsInventoryBehavior.")
        return
    end

    for _, methodName in ipairs({
        "openGetItemMode",
        "openGetItemMode_Type02"
    }) do
        local openGetItemMethod = inventoryType:get_method(methodName)
        if openGetItemMethod then
            sdk.hook(openGetItemMethod, function(args)
                if not Items.cancelNextUI then
                    return
                end

                Player.RemovePlayerRestriction()
                return sdk.PreHookResult.SKIP_ORIGINAL
            end)
        else
            log.error(
                "[Randomizer] Could not hook EsInventoryBehavior."
                .. methodName
                .. "."
            )
        end
    end

    local captionMethod = inventoryType and inventoryType:get_method(
        "setCaptionState"
    )

    if not captionMethod then
        log.error(
            "[Randomizer] Could not hook EsInventoryBehavior.setCaptionState."
        )
        return
    end

    sdk.hook(captionMethod, function(args)
        if not Items.cancelNextUI then
            return
        end

        local inventory = sdk.to_managed_object(args[2])
        if not inventory then
            return
        end

        Items.cancelNextUI = false
        Items.cancelNextUIExpires = nil
        inventory:call("forceClose()")
    end)
end

function Items.HandleDisconnectWait()
    if not Items.cancelNextUI then
        return
    end

    if Archipelago.IsConnected() then
        Items.cancelNextUI = false
        Items.cancelNextUIExpires = nil
        Items.lastDisconnectWarningKey = nil
        Items.lastDisconnectWarningTime = 0
        return
    end

    local gui = sdk.get_managed_singleton(
        sdk.game_namespace("gui.GUIMaster")
    )
    if not gui then
        return
    end

    local fileOpen = false
    local inventoryOpen = false

    pcall(function()
        fileOpen = gui:call("get_IsOpenFile()") == true
            or gui:call("isBusyFile()") == true
    end)
    pcall(function()
        inventoryOpen = gui:call("get_IsOpenInventory()") == true
    end)

    local closed = false
    if fileOpen then
        closed = pcall(function()
            -- A disconnected pickup must not run the completion callback:
            -- that callback retires the physical document.
            gui:call("closeFile(System.Boolean)", true)
        end)
    elseif inventoryOpen then
        closed = pcall(function()
            gui:call("closeInventoryForce()")
        end)
    end

    if closed or (
        Items.cancelNextUIExpires
        and os.clock() >= Items.cancelNextUIExpires
    ) then
        Items.cancelNextUI = false
        Items.cancelNextUIExpires = nil
    end
end

function Items.SetupStatueUIHook()
    local gimmickStatueBehavior = sdk.find_type_definition(sdk.game_namespace("gimmick.action.GimmickDialLockBehavior"))
    local safeLateUpdateMethod = gimmickStatueBehavior:get_method("lateUpdate")

    -- checks to see if a safe gui close was requested and, if so, close it
    sdk.hook(safeLateUpdateMethod, function (args)
        if Items.cancelNextStatueUI then
            local compFromHook = sdk.to_managed_object(args[2])
            local statueObject = compFromHook:call('get_GameObject()') -- the dial gimmick
            local compGimmickGUI = statueObject:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gui.RopewayGimmickAttachmentGUI")))
            local statueName = statueObject:call("get_Name()")
            local lastInteractableName = Items.lastInteractable:call("get_Name()")

            if string.gsub(tostring(lastInteractableName), '_control', '_gimmick') ~= statueName then
                return
            end

            compFromHook:call("setFinished()")

            if compFromHook:get_field("_CurState") > 1 then
                Items.cancelNextStatueUI = false
                Items.lastInteractable = nil
                compGimmickGUI:call("SetCancel()") -- closes the safe interaction view / returns to player
            end
        end
    end)
end

function Items.SetupSafeUIHook()
    local gimmickSafeBoxBehavior = sdk.find_type_definition(sdk.game_namespace("gui.GimmickSafeBoxDialBehavior"))
    local safeLateUpdateMethod = gimmickSafeBoxBehavior:get_method("CheckInput")

    -- checks to see if a safe gui close was requested and, if so, close it
    sdk.hook(safeLateUpdateMethod, function (args)
        if Items.cancelNextSafeUI then
            local compFromHook = sdk.to_managed_object(args[2])
            local safeBoxObject = compFromHook:call('get_GameObject()') -- the dial gimmick
            local compGimmickGUI = safeBoxObject:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gui.RopewayGimmickAttachmentGUI")))
            local compGimmickBody = safeBoxObject:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gimmick.action.GimmickBody")))
            local safeBoxControlObject = compGimmickBody:get_field("_GimmickControl"):call("get_GameObject()")
            local safeBoxControlParent = safeBoxControlObject:get_Transform():get_Parent():get_GameObject()
            local compDialSettings = safeBoxControlObject:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gimmick.option.AttachmentSafeBoxDialSettings")))
            local compAddItem = safeBoxControlParent:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gimmick.option.AddItemToInventorySettings")))
            local itemPosObject = compAddItem:get_field("ItemPositions")
            local itemPositions = itemPosObject:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("item.ItemPositions")))

            -- Open first, then clear reward. Destroying/vanishing before
            -- TransmitCorrectAnswer can leave the door shut. Hide/destroy the
            -- reward immediately after so it does not sit in the bay.
            local rewardObject = itemPosObject
            Items.cancelNextSafeUI = false
            compGimmickGUI:call("SetSatisfy()")
            compAddItem:set_field("Enable", false)
            compDialSettings:call("TransmitCorrectAnswer", compGimmickGUI)

            pcall(function()
                if rewardObject then
                    rewardObject:call("set_DrawSelf(System.Boolean)", false)
                end
            end)
            pcall(function()
                itemPositions:call("vanishItemAndSave()")
            end)
            Items.RemoveSafeMapIcons(compGimmickBody, itemPositions)
            DestroyObjects.DestroyGameObject(rewardObject)
            DestroyObjects.DestroyOpenedSafeRewards()
        end
    end)
end

-- this was a test to swap items to a different visual item. might not work anymore.
-- it definitely doesn't work anymore, or at least without massive rework to the client to allow it to work.
-- function Items.SwapAllItemsTo(item_name)
    -- scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), sdk.find_type_definition("via.SceneManager"), "get_CurrentScene()")
    -- item_objects = scene:call("findGameObjectsWithTag(System.String)", "Item")

    -- for k, item in pairs(item_objects:get_elements()) do
        -- item_name = item:call("get_Name()")
        -- item_folder = item:call("get_Folder()")
        -- item_folder_path = item_folder:call("get_Path()")
        -- item_component = item:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("item.ItemPositions")))

        -- if item_component then
            -- item_id = item_component:get_field("InitializeItemId")

            -- if item_id then -- all item_numbers are hex to decimal, use decimal here
                -- if new_item_name == "spray" then
                    -- item_number = 1
                    -- item_count = 1
                -- elseif new_item_name == "handgun ammo" then
                    -- item_number = 15
                    -- item_count = 30
                -- elseif new_item_name == "wood crate" then
                    -- item_number = 294
                    -- item_count = 1
                -- elseif new_item_name == "picture block" then
                    -- item_number = 98
                    -- item_count = 1
                -- end

                -- item_component:set_field("InitializeItemId", item_number)
                -- item_component:set_field("InitializeCount", item_count)
                -- item_component:call("createInitializeItem()")
            -- end
        --end
    -- end
-- end

return Items