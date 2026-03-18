local Records = {}

function Records.hasBeatenLeonA()
    local recordManager = Scene.getRecordManager()

    return recordManager:call("get_IsClearedMainScenario1stLeon")
end

function Records.hasBeatenLeonB()
    local recordManager = Scene.getRecordManager()

    return recordManager:call("get_IsClearedMainScenario2ndLeon")
end

function Records.hasBeatenClaireA()
    local recordManager = Scene.getRecordManager()

    return recordManager:call("get_IsClearedMainScenario1stClaire")
end

function Records.hasBeatenClaireB()
    local recordManager = Scene.getRecordManager()

    return recordManager:call("get_IsClearedMainScenario2ndClaire")
end

function Records.hasUnlockedLeonB()
    local recordManager = Scene.getRecordManager()

    return recordManager:call("get_IsOpenedLeonB")
end

function Records.hasUnlockedClaireB()
    local recordManager = Scene.getRecordManager()

    return recordManager:call("get_IsOpenedClaireB")
end

return Records
