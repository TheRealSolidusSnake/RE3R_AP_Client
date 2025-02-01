local Player = {}
Player.waitingForKill = false

function Player.GetPlayerManager()
    return sdk.get_managed_singleton(sdk.game_namespace("PlayerManager"))
end

function Player.GetGameObject()
    -- I'd normally use player.gameobj here but, apparently, it can sometimes randomly be nil, which is bad
    -- So this just uses the get current player method from the PlayerManager in-game instead
    local playerManager = Player.GetPlayerManager()

    return playerManager:call("get_CurrentPlayer()")
end

function Player.GetHitPointController()
    return Helpers.component(Player.GetGameObject(), "HitPointController")
end

function Player.GetSurvivorConditionComponent()
    return Helpers.component(Player.GetGameObject(), "survivor.SurvivorCondition")
end

function Player.GetBurnConditionComponent()
    return Helpers.component(Player.GetGameObject(), "effect.script.EsPlBurnupController")
end

function Player.GetCurrentPosition()
    return Player.GetGameObject():get_Transform():get_Position()
end

function Player.WarpToPosition(vectorNew)
    local playerManager = Player.GetPlayerManager()

    playerManager:setCurrentPosition(vectorNew)
end

function Player.LookAt(transform)
    Player.GetGameObject():get_Transform():lookAt(transform)
end

function Player.Damage(can_kill)
    local hpc = Player.GetHitPointController()
    local currentHealth = tonumber(hpc:get_field("<CurrentHitPoint>k__BackingField"))
    
    currentHealth = currentHealth - 500 -- starting health is 1200, 800 to like 300/400 is Caution, lower is Danger

    if currentHealth <= 0 then
        currentHealth = 1 -- don't drop health below 1
    end

    if can_kill == true and currentHealth == 1 then
        Player.Kill()      
    else
        hpc:set_field("<CurrentHitPoint>k__BackingField", currentHealth)
    end
end

function Player.Kill()
    local burn = Player.GetBurnConditionComponent()

    if Scene.isInPause() or Scene.isUsingItemBox() or not Scene.isInGame() then
        Player.waitingForKill = true

        return
    end
    
    Player.waitingForKill = false
    Scene.goToGameOver()
    burn:set_field("bRequestBurnUp", true)
end

-- the game sets an invincible flag on the player when picking up an item,
--    which apparently normally gets unset by something on the item itself
-- since we're vanishing items, we need to manually unset the invincible flag
function Player.TurnOffInvincibility()
    local playerObj = Player.GetGameObject()

    if playerObj then
        local compHitPoint = Player.GetHitPointController()
        local compHitPoint2nd = Player.GetHitPointController()
        local compHitPoint3rd = Player.GetHitPointController()

        compHitPoint:call("set_Invincible(System.Boolean)", false)
        compHitPoint:set_field("<Invincible>k__BackingField", false)
        compHitPoint2nd:call("set_SecondInvincible(System.Boolean)", false)
        compHitPoint2nd:set_field("<SecondInvincible>k__BackingField", false)
    	compHitPoint3rd:call("set_TrackInvincible(System.Boolean)", true)
        compHitPoint3rd:set_field("<TrackInvincible>k__BackingField", true)

        return true
    else
        return false
    end
end

return Player
