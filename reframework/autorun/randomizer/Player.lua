local Player = {}

function Player.GetGameObject()
    return player.gameobj
end

function Player.GetCurrentPosition()
    return Player.GetGameObject():get_Transform():get_Position()
end

function Player.WarpToPosition(vectorNew)
    local playerManager = sdk.get_managed_singleton(sdk.game_namespace("PlayerManager"))

    playerManager:setCurrentPosition(vectorNew)
end

function Player.LookAt(transform)
    Player.GetGameObject():get_Transform():lookAt(transform)
end

return Player
