local Scene = {}

Scene.sceneObject = nil
Scene.mainFlowManager = nil
Scene.interactManager = nil
Scene.guiItemBox = nil

function Scene.getSceneObject()
    if Scene.sceneObject ~= nil then
        return Scene.sceneObject
    end

    Scene.sceneObject = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), sdk.find_type_definition("via.SceneManager"), "get_CurrentScene()")

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
    local masters = Scene.getSceneObject():findGameObjectsWithTag("Masters")
    local foundMaster = nil

    for k, master in pairs(masters) do
        if master:get_Name() == objectName then
            foundMaster = master

            break
        end
    end

    return foundMaster
end

function Scene.getMainFlowManager()
    if Scene.mainFlowManager ~= nil then
        return Scene.mainFlowManager
    end

    local gameMaster = Scene.getGameMaster()
    if not gameMaster then return nil end

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
    if not gimmickMaster then return nil end

    Scene.interactManager = gimmickMaster:call(
        "getComponent(System.Type)",
        sdk.typeof(sdk.game_namespace("gimmick.action.InteractManager"))
    )

    return Scene.interactManager
end

function Scene.getSaveDataManager()
    if Scene.saveDataManager ~= nil then
        return Scene.saveDataManager
    end

    local gameMaster = Scene.getGameMaster()

    Scene.saveDataManager = gameMaster:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gamemastering.SaveDataManager")))

    return Scene.saveDataManager
end

function Scene.getRecordManager()
    if Scene.recordManager ~= nil then
        return Scene.recordManager
    end

    local gameMaster = Scene.getGameMaster()

    Scene.recordManager = gameMaster:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gamemastering.RecordManager")))

    return Scene.recordManager
end

function Scene.getSurvivorType()
    local gameMaster = Scene.getGameMaster()
    if not gameMaster then return -1 end

    local survivorManager = gameMaster:call(
        "getComponent(System.Type)",
        sdk.typeof(sdk.game_namespace("SurvivorManager"))
    )
    if not survivorManager then return -1 end

    local survivors = survivorManager:get_field("ExistSurvivorInfoList")
    if not survivors then return -1 end

    for _, survivor in pairs(survivors:get_field("mItems")) do
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
    if not scene then return nil end

    Scene.guiItemBox = scene:findGameObject("GUI_ItemBox")
    return Scene.guiItemBox
end

function Scene.isUsingItemBox()
    local guiBox = Scene.getGUIItemBox()
    if not guiBox then
        return false
    end

    -- get_DrawSelf() can throw an error when RE3 reloads a scene or on death, so pcall that ish since that works just fine
    local success, result = pcall(function()
        return guiBox:get_DrawSelf()
    end)

    if not success then
        -- invalidate cached reference so the next lookup gets a fresh object
        Scene.guiItemBox = nil
        return false
    end

    return result
end

-- RE3-only: cached handle
Scene.guiInventory = nil

function Scene.getGUIInventory()
    if Scene.guiInventory ~= nil then
        return Scene.guiInventory
    end

    local scene = Scene.getSceneObject()
    if not scene then return nil end

    Scene.guiInventory = scene:findGameObject("GUI_Inventory")
    return Scene.guiInventory
end

function Scene.isUsingInventory()
    local guiInv = Scene.getGUIInventory()
    if not guiInv then
        return false
    end

    -- RTX is weird and doesn't use UIMaster? or it does but not in the way we touch it already
    -- so pcall since clients are merged and we'd like this to not throw errors on RTX
    local ok, drawn = pcall(function()
        return guiInv:get_DrawSelf()
    end)

    if not ok then
        Scene.guiInventory = nil
        return false
    end

    return drawn
end

function Scene.getDifficulty()
    local mainFlowManager = Scene.getMainFlowManager();
    
    if mainFlowManager ~= nil then
        local difficultySetting = mainFlowManager:call("get_CurrentDifficulty")

        if difficultySetting ~= nil then
            return difficultySetting
        end

        return -1
    end

    return -1
end

function Scene.isTitleScreen()
    return Scene.getMainFlowManager():get_IsInTitle()
end

function Scene.isInGame()
    local mainFlowManager = Scene.getMainFlowManager()
    if mainFlowManager == nil then
        return false
    end

    return mainFlowManager:get_IsInGame() or false
end

function Scene.isInPause()
    return Scene.getMainFlowManager():get_IsInPause()
end

function Scene.isInGameOver()
    local mainFlowManager = Scene.getMainFlowManager()
    if mainFlowManager == nil then
        return false
    end

    return Scene.getMainFlowManager():get_IsInGameOver()
end

function Scene.goToGameOver()
    return Scene.getMainFlowManager():call("goGameOverSimple", nil)
end

function Scene.isCharacterJill()
    return Scene.getSurvivorType() == 0
end

function Scene.isCharacterCarlos()
    return Scene.getSurvivorType() == 1
end

function Scene.isDifficultyAssisted()
    return Scene.getDifficulty() == 0
end

function Scene.isDifficultyStandard()
    return Scene.getDifficulty() == 1
end

function Scene.isDifficultyHardcore()
    return Scene.getDifficulty() == 2
end

function Scene.isDifficultyNightmare()
    return Scene.getDifficulty() == 3
end

function Scene.isDifficultyInferno()
    return Scene.getDifficulty() == 4
end

function Scene.getCurrentLocation()
    return Scene.getMainFlowManager():get_LoadLocation()
end

function Scene.getCurrentArea()
    return Scene.getMainFlowManager():get_LoadArea()
end

function Scene.getGameGUID()
    return Scene.getMainFlowManager():get_GameGUID()
end

function Scene.getSaveGUID()
    return Scene.getMainFlowManager():get_SaveGUID()
end

return Scene