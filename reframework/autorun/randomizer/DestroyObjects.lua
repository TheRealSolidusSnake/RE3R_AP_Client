local DestroyObjects = {}
DestroyObjects.isInit = false
DestroyObjects.lastRemoval = os.time()

function DestroyObjects.Init()
    if not DestroyObjects.isInit then
        DestroyObjects.isInit = true
        DestroyObjects.DestroyAll()
    end

    -- if the last check for objects to remove was X time ago or more, trigger another removal
    if os.time() - DestroyObjects.lastRemoval > 15 then -- 15 seconds
        DestroyObjects.isInit = false
    end
end

function DestroyObjects.DestroyAll()
    local destroyables = {
        DestroyObjects.GetPurposeGUI(),
        DestroyObjects.GetAdasSecretWeaponLadder(),
        DestroyObjects.GetSherrysKey()
    }

    -- if we talked to Marvin, remove the shutter and the panel interact that lets you put a fuse in it to open the shutter
    if Storage.talkedToMarvin then
        table.insert(destroyables, DestroyObjects.GetMainHallShutter())
        table.insert(destroyables, DestroyObjects.GetMainHallShutterFusePanel())
    end

    for k, obj in pairs(destroyables) do
        if obj ~= nil then
            obj:call("destroy", obj)
        end        
    end
end

function DestroyObjects.GetPurposeGUI()
    return Scene.getSceneObject():findGameObject("GUI_Purpose")
end

function DestroyObjects.GetAdasSecretWeaponLadder()
    return Scene.getSceneObject():findGameObject("ADA_PlayCF535_00_HoldHackingGun")
end

function DestroyObjects.GetSherrysKey()
    return Scene.getSceneObject():findGameObject("OrphanAsylum_PlayEvent_CF360")
end

function DestroyObjects.GetMainHallShutter()
    return Scene.getSceneObject():findGameObject("sm60_033_PipeShutter01A_gimmick")
end

function DestroyObjects.GetMainHallShutterFusePanel()
    return Scene.getSceneObject():findGameObject("sm42_167_FuseBox01A_control")
end

return DestroyObjects