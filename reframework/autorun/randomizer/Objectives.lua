local Objectives = {}
Objectives.isInit = false

function Objectives.Init()
    if not Objectives.isInit then
        Objectives.isInit = true

        Objectives.Destroy()
    end
end

function Objectives.GetPurposeGUI()
    local guiPurpose = scene:call("findGameObject(System.String)", "GUI_Purpose")

    return guiPurpose
end

function Objectives.Destroy()
    local guiPurpose = Objectives.GetPurposeGUI()

    if guiPurpose ~= nil then
        guiPurpose:call("destroy", guiPurpose)
    end
end

return Objectives