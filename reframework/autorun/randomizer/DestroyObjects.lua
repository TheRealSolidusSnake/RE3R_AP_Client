local DestroyObjects = {}
DestroyObjects.isInit = false
DestroyObjects.lastRemoval = os.time()

function DestroyObjects.Init()
    if Archipelago.IsConnected() and not DestroyObjects.isInit then
        DestroyObjects.isInit = true
        DestroyObjects.DestroyAll()
    end

    -- Reset the init flag every 15 seconds
    if os.time() - DestroyObjects.lastRemoval > 15 then -- 15 seconds
        DestroyObjects.isInit = false
    end
end

function DestroyObjects.DestroyAll()
    local destroyables = {
        DestroyObjects.GetPurposeGUI()
    }

    -- Only add the door to destroyables if talkedToTyrell is true
    if Storage.talkedToTyrell then
        table.insert(destroyables, DestroyObjects.GetMainHallDoor())
    end

    -- Destroy all objects in the table
    for k, obj in pairs(destroyables) do
        if obj ~= nil then
            obj:call("destroy", obj)
        end        
    end
end

function DestroyObjects.GetPurposeGUI()
    return Scene.getSceneObject():findGameObject("GUI_Purpose")
end

function DestroyObjects.GetMainHallDoor()
    return Scene.getSceneObject():findGameObject("Door_2_1_030w_gimmick")
end

return DestroyObjects