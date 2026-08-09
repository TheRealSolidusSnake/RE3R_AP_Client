local EnemyInvisible = {}
EnemyInvisible.isInit = false
EnemyInvisible.lastMode = nil

-- Nemesis KindIDs across his forms (stalker through late-game)
local NEMESIS_KINDS = {
    "em4000", "em9000", "em9010", "em9020", "em9030", "em9040", "em9050",
    "em9091", "em9100", "em9200", "em9201", "em9210", "em9300",
    "em9400", "em9401", "em9410",
}

function EnemyInvisible.Init()
    EnemyInvisible.isInit = true
end

function EnemyInvisible.GetEnemyManager()
    return sdk.get_managed_singleton(sdk.game_namespace("EnemyManager"))
end

function EnemyInvisible.GetMode()
    return Archipelago.invisible_enemy_mode or "Off"
end

function EnemyInvisible.IsNemesis(enemy)
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

function EnemyInvisible.IsGamePaused()
    local enemyManager = EnemyInvisible.GetEnemyManager()
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

-- The manager has a cheat invisible flag; leave it off so enemies can still attack
function EnemyInvisible.ClearManagerInvisibleFlag()
    local enemyManager = EnemyInvisible.GetEnemyManager()
    if not enemyManager then
        return
    end

    pcall(function()
        enemyManager:set_field("_IsInvisible", false)
    end)
end

function EnemyInvisible.SetMeshVisible(mesh, visible)
    if not mesh then
        return
    end

    pcall(function() mesh:call("set_DrawDefault", visible) end)
    pcall(function() mesh:call("set_DrawShadowCast", visible) end)
    pcall(function() mesh:call("set_Enabled", true) end)
end

function EnemyInvisible.SetEnemyVisible(enemy, visible)
    if not enemy then
        return
    end

    -- Keep the GameObject itself updating/drawing; only hide the mesh
    local gameObject = enemy:call("get_GameObject")
    if gameObject then
        pcall(function() gameObject:call("set_DrawSelf", true) end)
        pcall(function() gameObject:call("set_UpdateSelf", true) end)
    end

    EnemyInvisible.SetMeshVisible(enemy:call("get_Mesh"), visible)

    local subMeshes = enemy:call("get_SubMeshes")
    if not subMeshes then
        return
    end

    local count = subMeshes:call("get_Count")
    if not count or count < 1 or count > 64 then
        return
    end

    for i = 0, count - 1 do
        EnemyInvisible.SetMeshVisible(subMeshes:call("get_Item", i), visible)
    end
end

function EnemyInvisible.GetActiveEnemies()
    local enemies = {}
    local enemyManager = EnemyInvisible.GetEnemyManager()
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
function EnemyInvisible.Update()
    if not EnemyInvisible.isInit then
        return
    end

    local mode = EnemyInvisible.GetMode()

    -- Turning the option off restores visibility once, then does nothing
    if mode == "Off" or not mode then
        if EnemyInvisible.lastMode and EnemyInvisible.lastMode ~= "Off" then
            EnemyInvisible.ClearManagerInvisibleFlag()

            for _, enemy in ipairs(EnemyInvisible.GetActiveEnemies()) do
                EnemyInvisible.SetEnemyVisible(enemy, true)
            end
        end

        EnemyInvisible.lastMode = "Off"
        return
    end

    if not Scene:isInGame() then
        return
    end

    if not Archipelago.hasConnectedPrior then
        return
    end

    -- Mesh toggles during Carlos RPD / cutscene loads can stall the handoff.
    if Scene.isTransitioning and Scene.isTransitioning() then
        return
    end

    if EnemyInvisible.IsGamePaused() then
        return
    end

    EnemyInvisible.ClearManagerInvisibleFlag()

    for _, enemy in ipairs(EnemyInvisible.GetActiveEnemies()) do
        -- "Enemies Only" keeps Nemesis visible; everything else is hidden
        local stayVisible = (mode == "Enemies Only" and EnemyInvisible.IsNemesis(enemy))
        EnemyInvisible.SetEnemyVisible(enemy, stayVisible)
    end

    EnemyInvisible.lastMode = mode
end

return EnemyInvisible
