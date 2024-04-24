-- This script doesn't work at all on RE8 (Village). This will be helpful for someone later, though: 
-- - https://cdn.discordapp.com/attachments/925838720534446100/1091125439537348628/image.png?ex=65a9a4c0&is=65972fc0&hm=fc9697872bbd65587bd4bb5d148509a497132201128a8176c16cb008511db2dc&
-- - https://cdn.discordapp.com/attachments/925838720534446100/1092203626568613898/image.png?ex=65ad90e4&is=659b1be4&hm=69b6ab91e182c81d6ab45b60afe89672e1423c479c87e780d93dceddbaa8491a&
--

-- Also doesn't work with RE4R. Things feel more obscured in this one than the others. Did find:
-- - GameObjects that start with "DropItem_" with a number of question marks after -> chainsaw.DropItem (component)
--   -> _ItemData -> ItemID, Count, AmmoItemID, AmmoCount, Durability
--      OR
--   -> _Item -> _ItemId, _CurrentDurability, _CurrentItemCount, _ItemType (lists things like "Powder(4)"), _ItemSize (size in inv, e.g., "_1x1_")
-- - _Item -> _ItemType in the above has Key(0), Ammo(1), Parts(3), Powder(4), Gun(5), Melee(6), Throwing(7), etc.
-- - Could mean that the chainsaw.InteractHolder (component) is the source of interactions that we'd want to hook somewhere
-- - This mod has the item interaction stuff in it, I think:
--   - https://www.nexusmods.com/residentevil42023/mods/1063
-- - These mods also have a lot of relevant Lua code for inventory items, but not ground items: 
--   - https://www.nexusmods.com/residentevil42023/mods/896
--   - https://www.nexusmods.com/residentevil42023/mods/126
--   - https://www.nexusmods.com/residentevil42023/mods/1057
--

local Inspect = {}
Inspect.currentMapID = nil -- only used by RE2R and RE3R currently

local InspectItem = {}
local InspectPlayer = {}
local InspectTypewriter = {}

function InspectItem.GetName(gameObject)
    return gameObject:call("get_Name()") or ""
end

function InspectItem.GetParentName(gameObject)
    local transform = sdk.to_managed_object(gameObject:call('get_Transform()'))
    local transform_parent = sdk.to_managed_object(transform:call('get_Parent()'))

    if transform_parent then
        local gameobject_parent = sdk.to_managed_object(transform_parent:call('get_GameObject()'))
        local comp_item_positions = nil
        
        if game == "RE2R" or game == "RE3R" then
            comp_item_positions = gameobject_parent:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("item.ItemPositions")))
        end

        if game == "RE7" then
            comp_item_positions = gameobject_parent:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("Item")))
        end

        -- only return the parent name if it's an item; otherwise, we don't care
        if comp_item_positions then
            return gameobject_parent:call("get_Name()") or ""
        else
            return ""
        end
    end

    return ""
end

function InspectItem.GetFolderPath(gameObject)
    local gameobject_folder = gameObject:call("get_Folder()")
    
    if gameobject_folder then 
        return gameobject_folder:call("get_Path()") 
    end

    return ""
end

function InspectPlayer.GetPosition()
    local player_position = nil

    if game == "RE2R" or game == "RE3R" then
        local player_manager = sdk.get_managed_singleton(sdk.game_namespace("PlayerManager"))
        player_position = player_manager:call("get_CurrentPosition()")
    end

    if game == "RE7" then
        local player_object = player.gameobj -- apparently REF defines this?
        local player_transform = player_object:call("get_Transform")
        player_position = player_transform:call("get_Position")
    end

    local x = Inspect._Round(player_position.x)
    local y = Inspect._Round(player_position.y)
    local z = Inspect._Round(player_position.z)

    return { x = x, y = y, z = z }
end

function InspectPlayer.GetPositionString()
    local pos = InspectPlayer.GetPosition()

    if not pos then return "" end

    return "[" .. pos["x"] .. ", " .. pos["y"] .. ", " .. pos["z"] .. "]"
end

function InspectTypewriter.IsTypewriter(gameObject)
    local gameobject_name = InspectItem.GetName(gameObject)
    local gameobject_parent = InspectItem.GetParentName(gameObject)

    if game == "RE2R" or game == "RE3R" then
        if string.match(gameobject_name, "Typewriter") then
            return true
        end
    end

    if game == "RE7" then
        if string.match(gameobject_name, "SaveMenuInteract") then
            return true
        end
    end

    return false
end

function InspectTypewriter.GetLocationId(gameObject)
    if game == "RE2R" or game == "RE3R" then
        local comp_gimmick_control = gameObject:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gimmick.action.GimmickControl")))
        
        return comp_gimmick_control:call("get_MyLocation()")
    end

    if game == "RE7" then
        local comp_interact_base = gameObject:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("InteractObjectBase")))
        local search_object = comp_interact_base:get_field("_SearchObject")
        local comp_map_object = search_object:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("MapObject")))
        local map_data = comp_map_object:get_field("Data")

        return map_data:get_field("Chapter")
    end

    return nil
end

function InspectTypewriter.GetMapId(gameObject)
    if game == "RE2R" or game == "RE3R" then
        local comp_gimmick_control = gameObject:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gimmick.action.GimmickControl")))
        local comp_gimmick_body = comp_gimmick_control:call("get_MyGimmickBody()")
        
        return comp_gimmick_body:get_field("AssignMapID")
    end

    if game == "RE7" then
        local comp_interact_base = gameObject:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("InteractObjectBase")))
        local search_object = comp_interact_base:get_field("_SearchObject")
        local comp_map_object = search_object:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("MapObject")))
        local map_data = comp_map_object:get_field("Data")

        return map_data:get_field("RoomID")
    end

    return nil
end

function Inspect.GetGameByNamespace()
    local namespace_name = sdk.game_namespace("")

    if namespace_name == "app.ropeway." then return "RE2R" end
    if namespace_name == "offline." then return "RE3R" end -- what a stupid namespace name
    if namespace_name == "app." then
        -- this is a silly way to tell the difference between RE7 and RE8
        if player.gameobj:get_Name() == "Pl1000" then 
            return "RE7"
        else -- player.gameobj:get_Name() == "pl1000"
            return "RE8" 
        end
    end
    if namespace_name == "chainsaw." then return "RE4R" end -- awesome namespace name

    return nil
end

function Inspect.Log(message, value)
    if not message and not value then 
        log.debug("")
        return
    end

    if not value then
        log.debug("| REF_Inspect | " .. tostring(message))
        return
    end

    log.debug("| REF_Inspect | " .. tostring(message) .. ": " .. tostring(value))
end

function Inspect._Setup()
    Inspect._SetupHook()
end

function Inspect._SetupHook()
    if game == "RE2R" or game == "RE3R" then
        -- main interactions hook
        local interactType = sdk.find_type_definition(sdk.game_namespace("gimmick.action.FeedbackFSM"))

        if interactType then
            local interact_method = interactType:get_method("execute")

            sdk.hook(interact_method, function(args)
                local compFeedbackFSM = sdk.to_managed_object(args[2])
                local parentOfComponent = sdk.to_managed_object(compFeedbackFSM:get_field('_Owner'))

                Inspect.Log() -- intentional line break
                Inspect.Log("Item Object", InspectItem.GetName(parentOfComponent))
                Inspect.Log("Parent Object", InspectItem.GetParentName(parentOfComponent))
                Inspect.Log("Folder Path", InspectItem.GetFolderPath(parentOfComponent))
                Inspect.Log("Player Position", InspectPlayer.GetPositionString())

                if InspectTypewriter.IsTypewriter(parentOfComponent) then
                    Inspect.Log("Typewriter Location ID", InspectTypewriter.GetLocationId(parentOfComponent))
                    Inspect.Log("Typewriter Map ID", InspectTypewriter.GetMapId(parentOfComponent))
                end
            end)
        end

        -- map switching (i.e., room switching) hook
        local interactType = sdk.find_type_definition(sdk.game_namespace("EnvironmentStandbyManager"))

        if interactType then
            local interact_method = interactType:get_method("getStandbyController")

            sdk.hook(interact_method, function(args)
                local compEnvStandby = sdk.to_managed_object(args[2])
                local currentMapID = compEnvStandby:call("get_CurrentMap")

                if currentMapID ~= Inspect.currentMapID then
                    Inspect.currentMapID = currentMapID
                    Inspect.Log("Current Map ID", currentMapID)
                end
            end)
        end
    end

    if game == "RE7" then
        local interactType = sdk.find_type_definition(sdk.game_namespace("InteractObjectBase"))

        if interactType then
            local interact_method = interactType:get_method("FsmExecute")

            sdk.hook(interact_method, function(args)
                local compFeedbackFSM = sdk.to_managed_object(args[2])
                local parentOfComponent = sdk.to_managed_object(compFeedbackFSM:call("get_GameObject"))

                Inspect.Log() -- intentional line break
                Inspect.Log("Item Object", InspectItem.GetName(parentOfComponent))
                Inspect.Log("Parent Object", InspectItem.GetParentName(parentOfComponent))
                Inspect.Log("Folder Path", InspectItem.GetFolderPath(parentOfComponent))
                Inspect.Log("Player Position", InspectPlayer.GetPositionString())

                if InspectTypewriter.IsTypewriter(parentOfComponent) then
                    Inspect.Log("Recorder Location ID", InspectTypewriter.GetLocationId(parentOfComponent))
                    Inspect.Log("Recorder Map ID", InspectTypewriter.GetMapId(parentOfComponent))
                end
            end)
        end
    end
end

function Inspect._Round(number)
    return math.ceil(number * 100) / 100 -- two decimal places
end

-- this gets used a lot, so just define it outside the function scopes
game = Inspect.GetGameByNamespace()

-- run all the setup once
re.on_pre_application_entry("UpdateBehavior", function()
    if not Inspect.didInit then
        Inspect.didInit = true

        Inspect._Setup()
    end
end)

Inspect.Log("Script loaded!")

if game ~= nil then
    Inspect.Log("Game identified as " .. tostring(game) .. ".")
end
