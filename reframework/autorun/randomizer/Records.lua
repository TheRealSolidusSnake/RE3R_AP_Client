local Records = {}

-- MainFlowManager.Difficulty: EASY=0 Assisted, NORMAL=1 Standard,
-- HARD=2 Hardcore, SUPERHARD=3 Nightmare, UNLIMITED=4 Inferno
Records.DIFFICULTY = {
    assisted = 0,
    standard = 1,
    hardcore = 2,
    nightmare = 3,
    inferno = 4,
}

Records.DIFFICULTY_NAMES = {
    [0] = "assisted",
    [1] = "standard",
    [2] = "hardcore",
    [3] = "nightmare",
    [4] = "inferno",
}

function Records.DifficultyNameToId(name)
    if name == nil then
        return nil
    end

    local key = string.lower(tostring(name))
    return Records.DIFFICULTY[key]
end

function Records.DifficultyIdToName(id)
    local n = tonumber(id)
    if n == nil then
        return nil
    end
    return Records.DIFFICULTY_NAMES[n]
end

-- Vanilla clear for the main campaign on a given difficulty.
-- Scenario arg is leftover LEON_A (0) for RE3's single campaign.
function Records.hasClearedDifficulty(difficulty)
    local diff = tonumber(difficulty)
    if diff == nil or diff < 0 or diff > 4 then
        return false
    end

    local recordManager = Scene.getRecordManager()
    if recordManager == nil then
        return false
    end

    local ok, cleared = pcall(function()
        return recordManager:call("isClearedGame", 0, diff)
    end)

    return ok and cleared == true
end

function Records.hasClearedDifficultyName(name)
    local id = Records.DifficultyNameToId(name)
    if id == nil then
        return false
    end
    return Records.hasClearedDifficulty(id)
end

function Records.hasClearedCurrentDifficulty()
    local diff = Scene.getDifficulty()
    if diff == nil or tonumber(diff) == nil or tonumber(diff) < 0 then
        return false
    end
    return Records.hasClearedDifficulty(diff)
end

-- Difficulty used for DeathLink eligibility: prefer live session difficulty
-- while in-game, otherwise fall back to the YAML/AP difficulty.
function Records.getDeathLinkDifficultyId()
    if Scene.isInGame() then
        local current = tonumber(Scene.getDifficulty())
        if current ~= nil and current >= 0 and current <= 4 then
            return current
        end
    end

    return Records.DifficultyNameToId(Lookups.difficulty)
end

function Records.hasClearedDeathLinkDifficulty()
    local id = Records.getDeathLinkDifficultyId()
    if id == nil then
        return false
    end
    return Records.hasClearedDifficulty(id)
end

return Records
