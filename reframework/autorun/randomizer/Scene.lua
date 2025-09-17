local Scene = {}

Scene.sceneObject = nil
Scene.mainFlowManager = nil
Scene.interactManager = nil
Scene.guiItemBox = nil

function Scene.getSceneObject()
    if Scene.sceneObject ~= nil then
        return Scene.sceneObject
    end

    local mgr = sdk.get_native_singleton("via.SceneManager")
    if mgr == nil then
        return nil
    end

    Scene.sceneObject = sdk.call_native_func(
        mgr,
        sdk.find_type_definition("via.SceneManager"),
        "get_CurrentScene()"
    )

    return Scene.sceneObject
end

function Scene.getGameMaster()
    return Scene.getMasterObject("30_GameMaster")
end

function Scene.getGimmickMaster()
    return Scene.getMasterObject("70_GimmickMaster")
end

function Scene.getUIMaster()
    return Scene.getMasterObject("UIMaster")
end

function Scene.getMasterObject(objectName)
    local scene = Scene.getSceneObject()
    if not scene then
        return nil
    end

    local masters = scene:findGameObjectsWithTag("Masters")
    if not masters then
        return nil
    end

    for _, master in pairs(masters) do
        if master and master:get_Name() == objectName then
            return master
        end
    end

    return nil
end

function Scene.getMainFlowManager()
    if Scene.mainFlowManager ~= nil then
        return Scene.mainFlowManager
    end

    local gameMaster = Scene.getGameMaster()
    if not gameMaster then
        return nil
    end

    Scene.mainFlowManager = gameMaster:call(
        "getComponent(System.Type)",
        sdk.typeof(sdk.game_namespace("gamemastering.MainFlowManager"))
    )

    return Scene.mainFlowManager
end

function Scene.getInteractManager()
    if Scene.interactManager ~= nil then
        return Scene.interactManager
    end

    local gimmickMaster = Scene.getGimmickMaster()
    if not gimmickMaster then
        return nil
    end

    Scene.interactManager = gimmickMaster:call(
        "getComponent(System.Type)",
        sdk.typeof(sdk.game_namespace("gimmick.action.InteractManager"))
    )

    return Scene.interactManager
end

function Scene.getSurvivorType()
    local gameMaster = Scene.getGameMaster()
    if not gameMaster then
        return -1
    end

    local survivorManager = gameMaster:call(
        "getComponent(System.Type)",
        sdk.typeof(sdk.game_namespace("SurvivorManager"))
    )
    if not survivorManager then
        return -1
    end

    local survivors = survivorManager:get_field("ExistSurvivorInfoList")
    if not survivors then
        return -1
    end

    for _, survivor in pairs(survivors:get_field("mItems") or {}) do
        if survivor then
            local isActive = survivor:get_field("<IsActivePlayer>k__BackingField")
            if isActive then
                return survivor:get_field("<SurvivorType>k__BackingField")
            end
        end
    end

    return -1
end

function Scene.getGUIItemBox()
    if Scene.guiItemBox ~= nil then
        return Scene.guiItemBox
    end

    local scene = Scene.getSceneObject()
    if not scene then
        return nil
    end

    Scene.guiItemBox = scene:call("findGameObject(System.String)", "GUI_ItemBox")
    return Scene.guiItemBox
end

-- Safe wrappers for MainFlowManager checks
function Scene.isTitleScreen()
    local mfm = Scene.getMainFlowManager()
    return mfm and mfm:get_IsInTitle() or false
end

function Scene.isInGame()
    local mfm = Scene.getMainFlowManager()
    return mfm and mfm:get_IsInGame() or false
end

function Scene.isInPause()
    local mfm = Scene.getMainFlowManager()
    return mfm and mfm:get_IsInPause() or false
end

function Scene.isInGameOver()
    local mfm = Scene.getMainFlowManager()
    return mfm and mfm:get_IsInGameOver() or false
end

function Scene.goToGameOver()
    local mfm = Scene.getMainFlowManager()
    if not mfm then
        return false
    end
    return mfm:call("goGameOverSimple", nil)
end

function Scene.isUsingItemBox()
    local guiBox = Scene.getGUIItemBox()
    return guiBox and guiBox:get_DrawSelf() or false
end

function Scene.isCharacterJill()
    return Scene.getSurvivorType() == 0
end

function Scene.isCharacterCarlos()
    return Scene.getSurvivorType() == 1
end

function Scene.getCurrentLocation()
    local mfm = Scene.getMainFlowManager()
    return mfm and mfm:get_LoadLocation() or nil
end

function Scene.getCurrentArea()
    local mfm = Scene.getMainFlowManager()
    return mfm and mfm:get_LoadArea() or nil
end

function Scene.getGameGUID()
    local mfm = Scene.getMainFlowManager()
    return mfm and mfm:get_GameGUID() or nil
end

function Scene.getSaveGUID()
    local mfm = Scene.getMainFlowManager()
    return mfm and mfm:get_SaveGUID() or nil
end

return Scene