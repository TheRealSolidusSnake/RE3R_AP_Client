local CutsceneObjects = {}
CutsceneObjects.isInit = false
CutsceneObjects.lastStop = os.time()

function CutsceneObjects.Init()
    if Archipelago.IsConnected() and not CutsceneObjects.isInit then
        CutsceneObjects.isInit = true
        CutsceneObjects.Shotgun()
        CutsceneObjects.Lockpick()
        CutsceneObjects.OverrideKey()
        CutsceneObjects.CultureSample()
    end

    -- if the last check for cutscene objects was X time ago or more, try again
    if os.time() - CutsceneObjects.lastStop > 5 then -- 5 seconds
        CutsceneObjects.isInit = false
    end
end

function CutsceneObjects.ClockPuzzle()
    local clockObject = Helpers.gameObject("0201_sm41_415_ES_JewelryBox01A_00_gimmick")
    if not clockObject then
        return false
    end

    local clockComponent = Helpers.component(clockObject, "gimmick.action.EsGimmickJewelryBox")
    if not clockComponent then
        return false
    end

    local ok, currentRno = pcall(function()
        return clockComponent:get_field("_Rno")
    end)

    if not ok then
        return false
    end

    if currentRno ~= 5 then
        clockComponent:set_field("_Rno", 5)
    end

    return true
end

function CutsceneObjects.Shotgun()
    local shotgunObject = Helpers.gameObject("0503_sm44_404_ES_ShotgunCase01A_gimmick")
    if not shotgunObject then
        return
    end
    local shotgunComponent = Helpers.component(shotgunObject, "gimmick.action.EsGimmickOpenObject")
    shotgunComponent:set_field("bGetItemForce", false)
end

function CutsceneObjects.Lockpick()
    local lockpickObject = Helpers.gameObject("EventPlay_EV322_k")
    if not lockpickObject then
        return
    end
    local lockpickComponent = Helpers.component(lockpickObject, "gimmick.option.AddItemToInventorySettings")
    lockpickComponent:set_field("Enable", false)
end

function CutsceneObjects.OverrideKey()
    local overrideObject = Helpers.gameObject("sm42_503_ES_LabMonitor04A_00_gimmick")
    if not overrideObject then
        return
    end
    local overrideComponent = Helpers.component(overrideObject, "gimmick.option.AddItemToInventorySettings")
    overrideComponent:set_field("Enable", false)
end

function CutsceneObjects.CultureSample()
    local cultureObject = Helpers.gameObject("st05_0107_sm41_426_ES_GrowthMachine01A_gimmick")
    if not cultureObject then
        return
    end
    local cultureComponent = Helpers.component(cultureObject, "gimmick.option.AddItemToInventorySettings")
    cultureComponent:set_field("Enable", false)
end

return CutsceneObjects