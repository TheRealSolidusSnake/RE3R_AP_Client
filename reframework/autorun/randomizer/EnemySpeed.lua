local EnemySpeed = {}
EnemySpeed.isInit = false
EnemySpeed.lastMode = nil

-- Slot-data speed names -> motion speed multipliers
local SPEED_MULTIPLIERS = {
    ["Slow"] = 0.5,
    ["Normal"] = 1.0,
    ["Fast"] = 1.5,
    ["Very Fast"] = 2.0,
    ["Extreme"] = 3.0,
}

-- Nemesis KindIDs across his forms (stalker through late-game)
local NEMESIS_KINDS = {
    "em4000", "em9000", "em9010", "em9020", "em9030", "em9040", "em9050",
    "em9091", "em9100", "em9200", "em9201", "em9210", "em9300",
    "em9400", "em9401", "em9410",
}

function EnemySpeed.Init()
    EnemySpeed.isInit = true
end

function EnemySpeed.GetEnemyManager()
    return sdk.get_managed_singleton(sdk.game_namespace("EnemyManager"))
end

function EnemySpeed.GetMode()
    return Archipelago.enemy_movement_speed_mode or "Off"
end

function EnemySpeed.GetMultiplier()
    local speedName = Archipelago.enemy_movement_speed or "Normal"
    return SPEED_MULTIPLIERS[speedName] or 1.0
end

function EnemySpeed.IsNemesis(enemy)
    if not enemy then
        return false
    end

    local kind = enemy:call("get_KindID")
    if not kind then
        return false
    end

    local kindText = string.lower(tostring(kind))
    for _, name in ipairs(NEMESIS_KINDS) do
        if string.find(kindText, name, 1, true) then
            return true
        end
    end

    return false
end

function EnemySpeed.IsGamePaused()
    local enemyManager = EnemySpeed.GetEnemyManager()
    if not enemyManager then
        return false
    end

    if enemyManager:call("get_IsPausing") then
        return true
    end

    if enemyManager:call("get_IsTimelinePausing") then
        return true
    end

    return false
end

function EnemySpeed.SetManagerSpeed(multiplier)
    local enemyManager = EnemySpeed.GetEnemyManager()
    if not enemyManager then
        return
    end

    -- Prefer setBaseMotionSpeed; fall back to the property setter if needed
    local ok = pcall(function()
        enemyManager:call("setBaseMotionSpeed", multiplier)
    end)

    if not ok then
        pcall(function()
            enemyManager:call("set_BaseMotionSpeed", multiplier)
        end)
    end
end

function EnemySpeed.SetEnemySpeed(enemy, multiplier)
    if not enemy then
        return
    end

    pcall(function()
        enemy:call("set_BaseMotionSpeed", multiplier)
    end)
end

function EnemySpeed.GetActiveEnemies()
    local enemies = {}
    local enemyManager = EnemySpeed.GetEnemyManager()
    if not enemyManager then
        return enemies
    end

    local activeList = enemyManager:call("get_ActiveEnemyList")
    if not activeList then
        return enemies
    end

    local count = activeList:call("get_Count")
    if not count or count < 1 or count > 512 then
        return enemies
    end

    for i = 0, count - 1 do
        local enemy = activeList:call("get_Item", i)
        if enemy then
            table.insert(enemies, enemy)
        end
    end

    return enemies
end

-- Called every UpdateBehavior tick. Cheap no-op when the option is Off.
function EnemySpeed.Update()
    if not EnemySpeed.isInit then
        return
    end

    local mode = EnemySpeed.GetMode()

    -- Turning the option off restores vanilla speed once, then does nothing
    if mode == "Off" or not mode then
        if EnemySpeed.lastMode and EnemySpeed.lastMode ~= "Off" then
            EnemySpeed.SetManagerSpeed(1.0)
        end

        EnemySpeed.lastMode = "Off"
        return
    end

    if not Scene:isInGame() then
        return
    end

    if not Archipelago.hasConnectedPrior then
        return
    end

    -- setBaseMotionSpeed during Carlos RPD / cutscene loads can stall the handoff.
    if Scene.isTransitioning and Scene.isTransitioning() then
        return
    end

    if EnemySpeed.IsGamePaused() then
        return
    end

    local multiplier = EnemySpeed.GetMultiplier()

    if mode == "Including Nemesis" then
        -- One manager call covers every enemy, including Nemesis
        EnemySpeed.SetManagerSpeed(multiplier)
    elseif mode == "Enemies Only" then
        -- Keep Nemesis at normal speed; speed up everyone else
        EnemySpeed.SetManagerSpeed(1.0)

        for _, enemy in ipairs(EnemySpeed.GetActiveEnemies()) do
            if not EnemySpeed.IsNemesis(enemy) then
                EnemySpeed.SetEnemySpeed(enemy, multiplier)
            end
        end
    end

    EnemySpeed.lastMode = mode
end

return EnemySpeed
