local CutsceneItems = {}
CutsceneItems.isInit = false
CutsceneItems.lastStop = os.time()

function CutsceneItems.Init()
    if Archipelago.IsConnected() and not CutsceneItems.isInit then
        CutsceneItems.isInit = true
        CutsceneItems.Shotgun()
        CutsceneItems.Lockpick()
        CutsceneItems.OverrideKey()
        CutsceneItems.CultureSample()
    end

    -- if the last check for cutscene objects was X time ago or more, trigger another removal
    if os.time() - CutsceneItems.lastStop > 15 then -- 15 seconds
        CutsceneItems.isInit = false
    end
end

function CutsceneItems.Shotgun()
    local shotgunObject = Helpers.gameObject("0503_sm44_404_ES_ShotgunCase01A_gimmick")
    if not shotgunObject then
        return
    end
    local conditionComponent = Helpers.component(shotgunObject, "gimmick.action.EsGimmickOpenObject")
    conditionComponent:set_field("bGetItemForce", false)
end

function CutsceneItems.Lockpick()
    local lockpickObject = Helpers.gameObject("EventPlay_EV322_k")
    if not lockpickObject then
        return
    end
    local lockpickComponent = Helpers.component(lockpickObject, "gimmick.option.AddItemToInventorySettings")
    lockpickComponent:set_field("Enable", false)
end

function CutsceneItems.OverrideKey()
    local overrideObject = Helpers.gameObject("sm42_503_ES_LabMonitor04A_00_gimmick")
    if not overrideObject then
        return
    end
    local overrideComponent = Helpers.component(overrideObject, "gimmick.option.AddItemToInventorySettings")
    overrideComponent:set_field("Enable", false)
end

function CutsceneItems.CultureSample()
    local cultureObject = Helpers.gameObject("st05_0107_sm41_426_ES_GrowthMachine01A_gimmick")
    if not cultureObject then
        return
    end
    local cultureComponent = Helpers.component(cultureObject, "gimmick.option.AddItemToInventorySettings")
    cultureComponent:set_field("Enable", false)
end

return CutsceneItems