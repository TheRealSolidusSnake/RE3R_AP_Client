local HospitalDefenseSkip = {}

-- Hospital defense "skip": keep clearing enemies until the section ends naturally. 
-- Cutscenes seemed to play after every event regardless.. will try to get an actual skip eventually
HospitalDefenseSkip.pending = false
HospitalDefenseSkip.done = false
HospitalDefenseSkip.notified = false
HospitalDefenseSkip.startMapId = nil

local function clear_enemies()
    -- Siege manager only tracks zombies (Em0000s). 
    -- Hunters live on EnemyManager's active list instead. 
    pcall(function()
        local siege = sdk.get_managed_singleton(sdk.game_namespace("escape.enemy.EsSiegeWarfareManager"))
        if siege then
            siege:call("DestroyZombies", true)
            siege:call("DestroyOutFieldZombies", true)
        end
    end)

    pcall(function()
        local enemyManager = sdk.get_managed_singleton(sdk.game_namespace("EnemyManager"))
        if not enemyManager then
            return
        end

        local active = enemyManager:call("get_ActiveEnemyList()")
        if not active then
            return
        end

        local count = tonumber(active:call("get_Count()")) or 0

        -- walk backwards so removals don't shift the list under us
        for i = count - 1, 0, -1 do
            pcall(function()
                local enemy = active:call("get_Item", i)
                if enemy then
                    enemy:call("applyDead()")
                end
            end)
        end
    end)
end

local function has_left_defense_map()
    if HospitalDefenseSkip.startMapId == nil then
        return false
    end

    local current = nil
    pcall(function()
        current = Scene.getCurrentLocation()
    end)

    if current == nil then
        return false
    end

    return tonumber(current) ~= tonumber(HospitalDefenseSkip.startMapId)
end

function HospitalDefenseSkip.Finish(reason)
    if HospitalDefenseSkip.done then
        return
    end

    HospitalDefenseSkip.done = true
    HospitalDefenseSkip.pending = false
    log.info("[Randomizer] Hospital defense skip ended (" .. tostring(reason) .. ")")
end

-- Do NOT suppress gimmick_Hospital/roujousen — that folder owns the C4 detonation.
function HospitalDefenseSkip.ShouldSuppressInteract(itemName, folderPath)
    if not HospitalDefenseSkip.pending then
        return false
    end

    local path = tostring(folderPath or "")
    if path:find("ES_S04_0300/BesiegedBattle/BattleText", 1, true)
        or path:find("ES_S04_0300/Msg", 1, true)
    then
        return true
    end

    local name = tostring(itemName or "")
    if name:find("^msg_b") or name == "EmissiveChange" then
        return true
    end

    return false
end

function HospitalDefenseSkip.Request()
    if HospitalDefenseSkip.done or HospitalDefenseSkip.pending then
        return
    end

    HospitalDefenseSkip.pending = true
    HospitalDefenseSkip.notified = false
    pcall(function()
        HospitalDefenseSkip.startMapId = Scene.getCurrentLocation()
    end)

    clear_enemies()

    if not HospitalDefenseSkip.notified then
        HospitalDefenseSkip.notified = true
        GUI.AddText("Hospital defense cleared — hang out until you can plant the detonator.")
        log.info("[Randomizer] Hospital defense skip armed")
    end
end

function HospitalDefenseSkip.Update()
    if HospitalDefenseSkip.done or not HospitalDefenseSkip.pending then
        return
    end

    clear_enemies()

    -- section ends when GameRankControl_end / EV430 / Jill handoff changes the map
    if has_left_defense_map() then
        HospitalDefenseSkip.Finish("left defense map")
    end
end

function HospitalDefenseSkip.OnInteract(itemName, folderPath)
    if itemName == "EV840_StartBattle" then
        HospitalDefenseSkip.Request()
        return nil
    end

    if itemName == "st04_0102_GameRankControl_end" or itemName == "EV430_start_toCH4-2_01" then
        if HospitalDefenseSkip.pending then
            HospitalDefenseSkip.Finish("natural end node")
        end
        return nil
    end

    if HospitalDefenseSkip.ShouldSuppressInteract(itemName, folderPath) then
        return sdk.PreHookResult.SKIP_ORIGINAL
    end

    return nil
end

return HospitalDefenseSkip
