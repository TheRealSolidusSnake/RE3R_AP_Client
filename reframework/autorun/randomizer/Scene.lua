local Scene = {}

Scene.sceneObject = nil
Scene.mainFlowManager = nil
Scene.interactManager = nil
Scene.guiItemBox = nil
Scene.guiInventory = nil
Scene.saveDataManager = nil
Scene.recordManager = nil

local function invalidateSceneCaches()
    Scene.mainFlowManager = nil
    Scene.interactManager = nil
    Scene.guiItemBox = nil
    Scene.guiInventory = nil
    Scene.saveDataManager = nil
    Scene.recordManager = nil
end

function Scene.getSceneObject()
    local ok, currentScene = pcall(function()
        return sdk.call_native_func(
            sdk.get_native_singleton("via.SceneManager"),
            sdk.find_type_definition("via.SceneManager"),
            "get_CurrentScene()"
        )
    end)

    if not ok or currentScene == nil then
        Scene.sceneObject = nil
        invalidateSceneCaches()
        return nil
    end

    if currentScene ~= Scene.sceneObject then
        Scene.sceneObject = currentScene
        invalidateSceneCaches()
    end

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
    if not gameMaster then return nil end

    Scene.saveDataManager = gameMaster:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gamemastering.SaveDataManager")))

    return Scene.saveDataManager
end

function Scene.getRecordManager()
    if Scene.recordManager ~= nil then
        return Scene.recordManager
    end

    local gameMaster = Scene.getGameMaster()
    if not gameMaster then return nil end

    Scene.recordManager = gameMaster:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("gamemastering.RecordManager")))

    return Scene.recordManager
end

function Scene.getSurvivorType()
    local survivorManager = sdk.get_managed_singleton(
        sdk.game_namespace("SurvivorManager")
    )
    if not survivorManager then
        return -1
    end

    local player = survivorManager:call("get_Player()")
    if not player then
        return -1
    end

    return player:call("get_SurvivorType()")
end

-- SurvivorType is not a 0/1 index -- JILL is 2 -- so anything handing the game
-- a survivor has to look the value up by name.
function Scene.getSurvivorEnumValue(name)
    local typeDefinition = sdk.find_type_definition(
        sdk.game_namespace("SurvivorDefine.SurvivorType")
    )
    local field = typeDefinition and typeDefinition:get_field(name)
    if not field then
        return nil
    end

    local ok, value = pcall(function()
        return field:get_data(nil)
    end)
    return ok and value or nil
end

function Scene.getGUIItemBoxFromGUIMaster()
    local gui = sdk.get_managed_singleton(sdk.game_namespace("gui.GUIMaster"))
    if not gui then
        return nil
    end

    local ok, ref = pcall(function()
        return gui:get_field("RefItemBoxUI")
    end)
    if not ok or ref == nil then
        return nil
    end

    local okTarget, target = pcall(function()
        return ref:call("get_Target")
    end)
    if not okTarget or target == nil then
        return nil
    end

    return target
end

function Scene.getGUIItemBox()
    if Scene.guiItemBox ~= nil then
        return Scene.guiItemBox
    end

    local scene = Scene.getSceneObject()
    if scene then
        local ok, guiBox = pcall(function()
            return scene:findGameObject("GUI_ItemBox")
        end)
        if ok and guiBox then
            Scene.guiItemBox = guiBox
            return Scene.guiItemBox
        end
    end

    Scene.guiItemBox = Scene.getGUIItemBoxFromGUIMaster()
    return Scene.guiItemBox
end

function Scene.isUsingItemBox()
    local gui = sdk.get_managed_singleton(sdk.game_namespace("gui.GUIMaster"))
    if not gui then
        return false
    end

    local ok, result = pcall(function()
        return gui:call("isBusyItemBox")
    end)

    return ok and result == true
end

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
    local gui = sdk.get_managed_singleton(sdk.game_namespace("gui.GUIMaster"))
    if not gui then
        return false
    end

    local ok, result = pcall(function()
        return gui:call("get_IsOpenInventory")
    end)

    if not ok then
        return false
    end

    return result
end

-- The map is its own page but the inventory stays "open" behind it, so
-- isUsingInventory alone isn't enough to tell them apart.
function Scene.isUsingMap()
    local gui = sdk.get_managed_singleton(sdk.game_namespace("gui.GUIMaster"))
    if not gui then
        return false
    end

    local ok, result = pcall(function()
        return gui:call("get_IsOpenMap")
    end)

    return ok and result == true
end

-- True while the NOW LOADING overlay / game-scene load has not finished.
-- get_IsInGame can already be true during this window (e.g. Carlos RPD intro).
function Scene.isLoadingGameScene()
    local mainFlowManager = Scene.getMainFlowManager()
    if mainFlowManager == nil then
        return false
    end

    local ok, ended = pcall(function()
        return mainFlowManager:call("isEndLoadingGameScene")
    end)
    if not ok then
        return false
    end

    return ended == false
end

function Scene.isInterlude()
    local mainFlowManager = Scene.getMainFlowManager()
    if mainFlowManager == nil then
        return false
    end

    local ok, interlude = pcall(function()
        return mainFlowManager:call("get_IsInterlude")
    end)
    if not ok then
        return false
    end

    return interlude == true
end

-- True while LoadSurvivorType and the live player disagree (Jill↔Carlos swap).
-- Do NOT call setupPlayerUpdate() — that advances the setup state machine.
function Scene.isSurvivorSwapPending()
    local mainFlowManager = Scene.getMainFlowManager()
    if mainFlowManager == nil then
        return false
    end

    local okLoad, loadType = pcall(function()
        return mainFlowManager:call("get_LoadSurvivorType")
    end)
    if not okLoad or loadType == nil then
        return false
    end

    loadType = tonumber(loadType)
    if loadType == nil or loadType < 0 then
        return false
    end

    local current = tonumber(Scene.getSurvivorType())
    if current == nil then
        return false
    end

    return loadType ~= current
end

-- Character swap / scene load / interlude. Mod code must not touch inventory,
-- scenario flags, or destroy objects here or NOW LOADING never ends.
function Scene.isTransitioning()
    return Scene.isLoadingGameScene()
        or Scene.isInterlude()
        or Scene.isSurvivorSwapPending()
end

-- Safe to open inventory / get-item UI / mutate slots. Opening inventory during
-- load/interlude can stall isEndLoadingGameScene forever on "NOW LOADING".
function Scene.isSafeForItemPresentation()
    if not Scene.isInGame() then
        return false
    end
    if Scene.isTransitioning() then
        return false
    end
    if Scene.isUsingItemBox() then
        return false
    end
    if Scene.isInGameOver() then
        return false
    end

    return true
end

function Scene.ForceCloseInventory()
    local gui = sdk.get_managed_singleton(sdk.game_namespace("gui.GUIMaster"))
    if not gui then
        return false
    end

    local ok = pcall(function()
        gui:call("closeInventoryForce()")
    end)
    return ok
end

-- NOTE: Do not call FadeManager.clearFade to "unstick" NOW LOADING.
-- That can drop you at 0,0,0 with CurrentPlayer=null (OOB / wrong character).
-- Prevention is Scene.isTransitioning() gates around inventory/scenario work.

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
    local jill = Scene.getSurvivorEnumValue("JILL")
    return jill ~= nil
        and tonumber(Scene.getSurvivorType()) == tonumber(jill)
end

function Scene.isCharacterCarlos()
    local carlos = Scene.getSurvivorEnumValue("CARLOS")
    return carlos ~= nil
        and tonumber(Scene.getSurvivorType()) == tonumber(carlos)
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