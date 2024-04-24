local Player = {}

function Player.WarpToPosition(vectorNew)
    local playerManager = sdk.get_managed_singleton(sdk.game_namespace("PlayerManager"))

    playerManager:setCurrentPosition(vectorNew)
end

return Player
