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

    -- Destroy all objects in the table
    for k, obj in pairs(destroyables) do
        if obj ~= nil then
            obj:call("destroy", obj)
        end        
    end
end

function DestroyObjects.GetPurposeGUI()
    return scene:call("findGameObject(System.String)", "GUI_Purpose")
end

return DestroyObjects