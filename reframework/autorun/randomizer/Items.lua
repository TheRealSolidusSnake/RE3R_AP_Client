local Items = {}
Items.isInit = false -- keeps track of whether init things like hook need to run
Items.lastInteractable = nil
Items.cancelNextUI = false
Items.cancelNextSafeUI = false
Items.cancelNextStatueUI = false

function Items.Init()
    if not Items.isInit then
        Items.isInit = true

        Items.SetupInteractHook()
        Items.SetupSafeUIHook()
        Items.SetupStatueUIHook()
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
                    Storage.UpdateLastSavedItems()
                end
            end
        end

        -- nothing to do with AP if not connected
        if not Archipelago.IsConnected() then
            log.debug("Archipelago is not connected.")

            if Archipelago.hasConnectedPrior then
                GUI.AddText("Archipelago is not connected.")
            end

            return
        end

        -- if item_name and item_folder_path are not nil (even empty strings), do a location lookup to see if we should get an item
        if item_name ~= nil and item_folder_path ~= nil then
            local location_to_check = {}
            location_to_check['item_object'] = item_name
            location_to_check['parent_object'] = item_parent_name or ""
            location_to_check['folder_path'] = item_folder_path

            -- If we're interacting with the victory location, send victory and bail
            if Archipelago.CheckForVictoryLocation(location_to_check) then
                Archipelago.SendLocationCheck(location_to_check)
                GUI.AddText("Goal Completed!")

                return
            end

            -- If we run through a trigger named "AutoSaveArea", the game just auto-saved. So update last saved to last received.
            if string.find(item_name, "AutoSaveArea") then
                Storage.UpdateLastSavedItems()

                return
            end

            if item_name == "sm42_505_ES_C4Bomb01A_CH2_gimmick" and item_folder_path == "RopewayContents/World/Location_RPD/LocationLevel_RPD/Scenario/S02_0300/ES_S02_0300/ShowerRoomBlownUp" then

                GUI.AddText("Warning: Entering the STARS Office is a one way trip")
                GUI.AddText("The STARS Office also has permanently missable items in it")
                GUI.AddText("It is recommended that you complete all checks in the RPD prior to entering.")
            end

            if item_name == "msg15_wait" and item_folder_path == "RopewayContents/World/Location_Hospital/LocationLevel_Hospital/Scenario/S04_0300/ES_S04_0300/Msg" then

                GUI.AddText("Warning: Curing Jill will prevent you from getting earlier item checks")
                GUI.AddText("Locations in the Hospital will be gone forever if you happened to skip any")
                GUI.AddText("It is recommended that you complete all checks in the Hospital prior to curing Jill.")
            end

            -- attempt to close the Clock Puzzle door after interaction so we can randomize the locations
            if item_name == "WP6200" and item_folder_path == "RopewayContents/World/Location_DownTown/LocationLevel_DownTown/LocationFsm_DownTown/S03_1000/ES_S03_1000/Item/ES_S03_1000/I_100_Subway_Area/JewelryBox"
                or item_name == "sm71_101" and item_folder_path == "RopewayContents/World/Location_DownTown/LocationLevel_DownTown/LocationFsm_DownTown/S03_1000/ES_S03_1000/Item/ES_S03_1000/I_100_Subway_Area/JewelryBox"
                or item_name == "sm74_200" and item_folder_path == "RopewayContents/World/Location_DownTown/LocationLevel_DownTown/LocationFsm_DownTown/S03_1000/ES_S03_1000/Item/ES_S03_1000/I_100_Subway_Area/JewelryBox"
            then
                CutsceneObjects.ClockPuzzle()
            end

            local isLocationRandomized = Archipelago.IsLocationRandomized(location_to_check)

            if Archipelago.IsItemLocation(location_to_check) and (Archipelago.SendLocationCheck(location_to_check) and not CutsceneObjects[item_name] or Archipelago.IsConnected()) then
                Archipelago.waitingForInvincibilityOff = true
                -- if it's an item, call vanish and save to get rid of it
                if item_positions and isLocationRandomized then
                    item_positions:call('vanishItemAndSave()')
                end

                if string.find(item_name, "SafeBoxDial") then -- if it's a safe, cancel the next safe ui
                    Items.cancelNextSafeUI = true
                    Items.lastInteractable = feedbackParent
                elseif string.find(item_name, "HieroglyphicDialLock") then -- if it's a statue, cancel the next statue ui
                    Items.cancelNextStatueUI = true
                    Items.lastInteractable = feedbackParent
                end
            end
        Archipelago.waitingForInvincibilityOff = true
        end
    end)
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
            local compInteractBehavior = safeBoxControlObject:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gimmick.action.InteractBehavior")))

            Items.cancelNextSafeUI = false
            compGimmickGUI:call("SetCancel()") -- closes the safe interaction view / returns to player
            compInteractBehavior:get_field("MyInteract"):call("clear()") -- makes the safe no longer interactable via "use key"
        end
    end)
end

return Items