local Items = {}
Items.isInit = false -- keeps track of whether init things like hook need to run
Items.lastInteractable = nil
Items.cancelNextUI = false
Items.cancelNextSafeUI = false
Items.cancelNextStatueUI = false
Items.skipUiList = {}
Items.skipUiList["st05_0110_sm41_427_ES_VaccineFreezer01A_gimmick"] = true

function Items.Init()
    if not Items.isInit then
        Items.isInit = true

        Items.SetupInteractHook()
        Items.SetupDisconnectWaitHook()
        Items.SetupSafeUIHook()
        Items.SetupStatueUIHook()
    end
end

function Items.SetupInteractHook()
    local interactType = sdk.find_type_definition(sdk.game_namespace("gimmick.action.FeedbackFSM"))
    local interact_method = interactType:get_method("execute")

    -- main item hook, does all the AP stuff
    sdk.hook(interact_method, function(args)
        Archipelago.waitingForInvincibilityOff = true
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
                Items.cancelNextUI = true
            end

            return
        end
		
        -- force exit item pick up ui on some interactions
        if Items.skipUiList[item_name] ~= nil then
            local uiMaster = Scene.getSceneObject():findGameObject("UIMaster")
            local compGuiMaster = uiMaster:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gui.GUIMaster")))

            Items.cancelNextUI = false
            compGuiMaster:closeInventory()
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

            -- when Tyrell starts his computer cutscene, set a flag so we can remove the Main Hall door
            if item_name == "sm49_226_ES_Ch2_TyrellPC" and item_folder_path == "RopewayContents/World/Location_RPD/LocationLevel_RPD/Scenario/S02_0100/ES_S02_0100" then
    		print("Setting talkedToTyrell to true")
    		Storage.talkedToTyrell = true
	    end
        
            local isLocationRandomized = Archipelago.IsLocationRandomized(location_to_check)

            if Archipelago.IsItemLocation(location_to_check) and (Archipelago.SendLocationCheck(location_to_check) and not CutsceneObjects[item_name] or Archipelago.IsConnected()) then    
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

                -- local inputSystem = sdk.get_managed_singleton(sdk.game_namespace("InputSystem"))
                -- inputSystem:MouseCancelPC() -- this is so hacky, lol
            end
        end
    end)
end

function Items.SetupDisconnectWaitHook()
    local guiNewInventoryTypeDef = sdk.find_type_definition(sdk.game_namespace("gui.EsInventoryBehavior"))
    local guiNewInventoryMethod = guiNewInventoryTypeDef:get_method("setCaptionState")

    -- small hook that handles cancelling inventory UIs when having connected before and being not reconnected
    sdk.hook(guiNewInventoryMethod, function (args)
        if Items.cancelNextUI then
            local uiMaster = Scene.getSceneObject():findGameObject("UIMaster")
            local compGuiMaster = uiMaster:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gui.GUIMaster")))

            Items.cancelNextUI = false
            compGuiMaster:closeInventoryForce()
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

-- this was a test to swap items to a different visual item. might not work anymore.
function Items.SwapAllItemsTo(item_name)
    scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), sdk.find_type_definition("via.SceneManager"), "get_CurrentScene()")
    item_objects = scene:call("findGameObjectsWithTag(System.String)", "Item")

    for k, item in pairs(item_objects:get_elements()) do
        item_name = item:call("get_Name()")
        item_folder = item:call("get_Folder()")
        item_folder_path = item_folder:call("get_Path()")
        item_component = item:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("item.ItemPositions")))

        if item_component then
            item_id = item_component:get_field("InitializeItemId")

            if item_id then -- all item_numbers are hex to decimal, use decimal here
                if new_item_name == "spray" then
                    item_number = 1
                    item_count = 1
                elseif new_item_name == "handgun ammo" then
                    item_number = 15
                    item_count = 30
                elseif new_item_name == "wood crate" then
                    item_number = 294
                    item_count = 1
                elseif new_item_name == "picture block" then
                    item_number = 98
                    item_count = 1
                end

                item_component:set_field("InitializeItemId", item_number)
                item_component:set_field("InitializeCount", item_count)
                item_component:call("createInitializeItem()")
            end
        end
    end
end

return Items
