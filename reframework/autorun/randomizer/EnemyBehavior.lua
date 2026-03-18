local EnemyBehavior = {}

EnemyBehavior.isInit = false
EnemyBehavior.safeRoomIds = nil
EnemyBehavior.persistentColliderObject = nil
EnemyBehavior.pendingActions = {}
EnemyBehavior.currentSceneAddress = nil
EnemyBehavior.nemesisZonesDisabled = nil
EnemyBehavior.disabledNemesisZones = nil

function EnemyBehavior.Init()
    if EnemyBehavior.isInit then
        return
    end

    EnemyBehavior.isInit = true
    EnemyBehavior.RefreshFromSlotData()
    EnemyBehavior.SetupHooks()
end

function EnemyBehavior.GetBehaviorMode()
    return Archipelago.enemy_behavior or "Off"
end

function EnemyBehavior.RefreshFromSlotData()
    return EnemyBehavior.GetBehaviorMode()
end

function EnemyBehavior.IsEnabled()
    return EnemyBehavior.GetBehaviorMode() ~= "Off"
end

function EnemyBehavior.DoorsEnabled()
    local mode = EnemyBehavior.GetBehaviorMode()
    return mode == "Doors" or mode == "Unsafe Rooms" or mode == "Full"
end

function EnemyBehavior.UnsafeRoomsEnabled()
    local mode = EnemyBehavior.GetBehaviorMode()
    return mode == "Unsafe Rooms" or mode == "Full"
end

function EnemyBehavior.UnsafeStalkerEnabled()
    return EnemyBehavior.GetBehaviorMode() == "Full"
end

function EnemyBehavior.PreventDespawnEnabled()
    return EnemyBehavior.UnsafeRoomsEnabled()
end

function EnemyBehavior.GetCurrentScene()
    return Scene.getSceneObject()
end

function EnemyBehavior.GetCurrentSceneAddress()
    local scene = EnemyBehavior.GetCurrentScene()
    if not scene then
        return nil
    end

    local ok, address = pcall(function()
        return tostring(scene)
    end)

    if ok then
        return address
    end

    return nil
end

function EnemyBehavior.QueueAction(key, callback)
    EnemyBehavior.pendingActions[key] = callback
end

function EnemyBehavior.GetComponent(gameObjectOrComponent, typeName)
    if not gameObjectOrComponent then
        return nil
    end

    local gameObject = gameObjectOrComponent
    if gameObject.get_GameObject then
        local ok, result = pcall(function()
            return gameObjectOrComponent:get_GameObject()
        end)

        if ok and result ~= nil then
            gameObject = result
        end
    end

    local ok, component = pcall(function()
        return gameObject:call("getComponent(System.Type)", sdk.typeof(typeName))
    end)

    if ok then
        return component
    end

    return nil
end

function EnemyBehavior.GetPlayerGameObject()
    local ok, playerManager = pcall(function()
        return sdk.get_managed_singleton(sdk.game_namespace("PlayerManager"))
    end)

    if not ok or playerManager == nil then
        return nil
    end

    local okPlayer, playerObject = pcall(function()
        return playerManager:call("get_CurrentPlayer")
    end)

    if okPlayer then
        return playerObject
    end

    return nil
end

function EnemyBehavior.LoadSafeRoomIds()
    if EnemyBehavior.safeRoomIds ~= nil then
        return EnemyBehavior.safeRoomIds
    end

    EnemyBehavior.safeRoomIds = {}

    local scene = Scene.getSceneObject()
    if not scene then
        return EnemyBehavior.safeRoomIds
    end

    local ok, catalogs = pcall(function()
        return scene:call(
            "findComponents(System.Type)",
            sdk.typeof(sdk.game_namespace("level.MansionSafeRoomRegister"))
        )
    end)

    if not ok or catalogs == nil then
        return EnemyBehavior.safeRoomIds
    end

    local catalogElements = catalogs.get_elements and catalogs:get_elements() or catalogs

    for _, catalog in pairs(catalogElements) do
        if catalog and catalog.SafeRoomMapList then
            local safeRoomList = catalog.SafeRoomMapList
            local safeRoomElements = safeRoomList.get_elements and safeRoomList:get_elements() or safeRoomList

            for _, safeRoomId in pairs(safeRoomElements) do
                if safeRoomId and safeRoomId.value__ ~= nil then
                    EnemyBehavior.safeRoomIds[safeRoomId.value__] = true
                end
            end
        end
    end

    return EnemyBehavior.safeRoomIds
end

function EnemyBehavior.IsSafeRoomDoor(door)
    if not door then
        return false
    end

    local safeRoomIds = EnemyBehavior.LoadSafeRoomIds()
    if not safeRoomIds then
        return false
    end

    local roomA = nil
    local roomB = nil

    local ok = pcall(function()
        roomA = door._MyRooms[0]
        roomB = door._MyRooms[1]
    end)

    if not ok then
        return false
    end

    local roomASafe = roomA ~= nil and roomA.value__ ~= nil and safeRoomIds[roomA.value__] == true
    local roomBSafe = roomB ~= nil and roomB.value__ ~= nil and safeRoomIds[roomB.value__] == true

    return roomASafe or roomBSafe
end

function EnemyBehavior.GetOrCreatePersistentColliderObject()
    local scene = EnemyBehavior.GetCurrentScene()
    if not scene then
        return nil
    end

    local existing = nil
    pcall(function()
        existing = scene:call("findGameObject(System.String)", "EnemyBehaviorColliders")
    end)

    if existing ~= nil then
        EnemyBehavior.persistentColliderObject = existing
        return existing
    end

    local gameObjectType = sdk.find_type_definition("via.GameObject")
    if gameObjectType == nil then
        return nil
    end

    local createMethod = gameObjectType:get_method("create(System.String)")
    if createMethod == nil then
        return nil
    end

    local ok, created = pcall(function()
        return createMethod:call(nil, "EnemyBehaviorColliders")
    end)

    if ok and created ~= nil then
        EnemyBehavior.persistentColliderObject = created:add_ref()
        return EnemyBehavior.persistentColliderObject
    end

    return nil
end

function EnemyBehavior.GetPersistentColliderComponent()
    local colliderObject = EnemyBehavior.GetOrCreatePersistentColliderObject()
    if not colliderObject then
        return nil
    end

    local colliders = EnemyBehavior.GetComponent(colliderObject, "via.physics.Colliders")
    if colliders ~= nil then
        pcall(function()
            colliders:set_Static(true)
        end)
        return colliders
    end

    local collidersType = sdk.find_type_definition("via.physics.Colliders")
    if collidersType == nil then
        return nil
    end

    local ok, created = pcall(function()
        return colliderObject:call("createComponent(System.Type)", collidersType:get_runtime_type())
    end)

    if ok and created ~= nil then
        pcall(function()
            created:set_Static(true)
        end)
        return created
    end

    return nil
end

function EnemyBehavior.AddColliderPathsToLookup(lookupTable, colliderComponent)
    if lookupTable == nil or colliderComponent == nil then
        return lookupTable
    end

    local count = 0
    local okCount = pcall(function()
        count = colliderComponent:getCollidersCount()
    end)

    if not okCount then
        return lookupTable
    end

    for i = 0, count - 1 do
        local okCollider, collider = pcall(function()
            return colliderComponent:getColliders(i)
        end)

        if okCollider and collider ~= nil then
            local okPath, resourcePath = pcall(function()
                local shape = collider:get_Shape()
                local resource = shape and shape:get_Resource()
                return resource and resource:get_ResourcePath() or nil
            end)

            if okPath and resourcePath ~= nil and lookupTable[resourcePath] == nil then
                lookupTable[resourcePath] = collider
            end
        end
    end

    return lookupTable
end

function EnemyBehavior.CopyPersistentMapColliders()
    if not EnemyBehavior.PreventDespawnEnabled() then
        return
    end

    local scene = EnemyBehavior.GetCurrentScene()
    if not scene then
        return
    end

    local destinationComponent = EnemyBehavior.GetPersistentColliderComponent()
    if destinationComponent == nil then
        return
    end

    local existingByPath = EnemyBehavior.AddColliderPathsToLookup({}, destinationComponent)
    local sourceByPath = {}

    local ok, streamingControllers = pcall(function()
        return scene:call(
            "findComponents(System.Type)",
            sdk.typeof(sdk.game_namespace("environment.EnvironmentStreamingTexureController"))
        )
    end)

    if not ok or streamingControllers == nil then
        return
    end

    local streamingElements = streamingControllers.get_elements and streamingControllers:get_elements() or streamingControllers

    for _, streamingController in pairs(streamingElements) do
        local colliderComponent = EnemyBehavior.GetComponent(streamingController, "via.physics.Colliders")
        if colliderComponent ~= nil then
            EnemyBehavior.AddColliderPathsToLookup(sourceByPath, colliderComponent)
        end
    end

    for resourcePath, sourceCollider in pairs(sourceByPath) do
        if existingByPath[resourcePath] == nil then
            local okAdd = pcall(function()
                local nextIndex = destinationComponent:getCollidersCount()
                local newCollider = sdk.create_instance("via.physics.Collider"):add_ref()
                newCollider:set_GameObject(EnemyBehavior.persistentColliderObject)
                newCollider:set_UserData(sdk.create_instance("via.physics.UserData"):add_ref())
                newCollider:set_CollisionFilterResource(sourceCollider:get_CollisionFilterResource())
                newCollider:set_CollisionMaterialResource(sourceCollider:get_CollisionMaterialResource())

                local newShape = sdk.create_instance("via.physics.MeshShape", true):add_ref()
                newShape:call(".ctor")
                newShape:set_Resource(sourceCollider:get_Shape():get_Resource())
                newCollider:set_Shape(newShape)
                newCollider:get_FilterInfo():set_MaskBits(8)

                destinationComponent:setCollidersCount(nextIndex + 1)
                destinationComponent:setColliders(nextIndex, newCollider)
            end)

            if not okAdd then
                log.debug("[EnemyBehavior] Failed to copy persistent map collider for " .. tostring(resourcePath))
            end
        end
    end
end

function EnemyBehavior.ConfigureDoorForEnemies(door)
    if not door or not EnemyBehavior.DoorsEnabled() then
        return
    end

    local doorSetParam = nil
    local ok = pcall(function()
        doorSetParam = door:get_DoorSetParam()
    end)

    if not ok or doorSetParam == nil then
        return
    end

    local hasOpened = false
    pcall(function()
        hasOpened = door._SaveData ~= nil and door._SaveData.HasOpened
    end)

    if not hasOpened then
        return
    end

    local isSafeRoomDoor = EnemyBehavior.IsSafeRoomDoor(door)

    if doorSetParam.EnemyCanInteract ~= nil then
        doorSetParam.EnemyCanInteract = doorSetParam.EnemyCanInteract or EnemyBehavior.UnsafeRoomsEnabled() or not isSafeRoomDoor
    end

    if EnemyBehavior.UnsafeStalkerEnabled() then
        pcall(function()
            if doorSetParam.BossThrough ~= nil then
                doorSetParam.BossThrough = true
            end
        end)
    end

    pcall(function()
        door["<SuspendByMap>k__BackingField"] = false
    end)
end

function EnemyBehavior.ConfigureAutoDoorForEnemies(door)
    if not door or not EnemyBehavior.DoorsEnabled() then
        return
    end

    pcall(function()
        if door._Options ~= nil and (door._SaveData == nil or door._SaveData.HasOpened) then
            if door._Options.NoLockForEnemy ~= nil then
                door._Options.NoLockForEnemy = true
            end
        end
    end)

    pcall(function()
        door["<SuspendByMap>k__BackingField"] = false
    end)

    pcall(function()
        local gameObject = door:get_GameObject()
        if not gameObject then
            return
        end

        local transform = gameObject:get_Transform()
        if not transform then
            return
        end

        local enemyHitObject = transform:find("EmHit")
        if not enemyHitObject then
            return
        end

        local colliders = EnemyBehavior.GetComponent(enemyHitObject, "via.physics.Colliders")
        if colliders and colliders.set_Enabled then
            colliders:set_Enabled(false)
        end
    end)
end

function EnemyBehavior.GetGameTimeSeconds()
    local ok, gameClock = pcall(function()
        return sdk.get_managed_singleton(sdk.game_namespace("GameClock"))
    end)

    if not ok or gameClock == nil then
        return nil
    end

    local okTime, value = pcall(function()
        return gameClock:get_ActualPlayingTime() * 0.000001
    end)

    if okTime then
        return value
    end

    return nil
end

function EnemyBehavior.SetNemesisZoneCollidersEnabled(enabled)
    if EnemyBehavior.disabledNemesisZones == nil then
        return
    end

    for _, zone in pairs(EnemyBehavior.disabledNemesisZones) do
        if zone ~= nil then
            pcall(function()
                local colliders = EnemyBehavior.GetComponent(zone, "via.physics.Colliders")
                if colliders ~= nil and colliders.set_Enabled then
                    colliders:set_Enabled(enabled)
                end
            end)
        end
    end

    if enabled then
        EnemyBehavior.disabledNemesisZones = nil
        EnemyBehavior.nemesisZonesDisabled = nil
    end
end

function EnemyBehavior.TemporarilyDisableNemesisSafeRoomZones(isCurrentlySafeRoom)
    if not EnemyBehavior.UnsafeStalkerEnabled() then
        return
    end

    local scene = EnemyBehavior.GetCurrentScene()
    local player = EnemyBehavior.GetPlayerGameObject()
    if scene == nil or player == nil then
        return
    end

    local okZones, zones = pcall(function()
        return scene:call("findComponents(System.Type)", sdk.typeof("offline.escape.enemy.em9000.EsNemesisControlZoneGroup"))
    end)

    if not okZones or zones == nil then
        return
    end

    local zoneElements = zones.get_elements and zones:get_elements() or zones
    local distanceMethod = sdk.find_type_definition("offline.MathEx")
    distanceMethod = distanceMethod and distanceMethod:get_method("distance(via.GameObject, via.GameObject)") or nil

    local shouldDisable = false
    local collectedZones = {}

    for _, zone in pairs(zoneElements) do
        if zone ~= nil then
            collectedZones[#collectedZones + 1] = zone

            if not shouldDisable and distanceMethod ~= nil then
                local okDistance, zoneObject = pcall(function()
                    return zone:get_GameObject()
                end)

                if okDistance and zoneObject ~= nil then
                    local okValue, distanceValue = pcall(function()
                        return distanceMethod:call(nil, zoneObject, player:get_GameObject())
                    end)

                    if okValue and distanceValue < 4.0 then
                        shouldDisable = true
                    end
                end
            end
        end
    end

    if isCurrentlySafeRoom then
        shouldDisable = true
    end

    if not shouldDisable or #collectedZones == 0 then
        return
    end

    EnemyBehavior.disabledNemesisZones = collectedZones

    for _, zone in pairs(collectedZones) do
        pcall(function()
            local colliders = EnemyBehavior.GetComponent(zone, "via.physics.Colliders")
            if colliders ~= nil and colliders.set_Enabled then
                colliders:set_Enabled(false)
            end
        end)
    end

    local now = EnemyBehavior.GetGameTimeSeconds()
    EnemyBehavior.nemesisZonesDisabled = now and (now + 10.0) or nil
end

function EnemyBehavior.SetupSafeRoomHook()
    local mansionManagerType = sdk.find_type_definition(sdk.game_namespace("MansionManager"))
    if mansionManagerType == nil then
        log.debug("[EnemyBehavior] MansionManager type not found.")
        return
    end

    local method = mansionManagerType:get_method(
        "isSafeRoom(" .. sdk.game_namespace("gamemastering.Map.ID") .. ", " .. sdk.game_namespace("gamemastering.Map.Area") .. ")"
    )

    if method == nil then
        log.debug("[EnemyBehavior] MansionManager.isSafeRoom not found.")
        return
    end

    sdk.hook(method, nil, function(retval)
            if not EnemyBehavior.UnsafeRoomsEnabled() then
                return retval
            end

            local isCurrentlySafeRoom = false
            pcall(function()
                isCurrentlySafeRoom = (sdk.to_int64(retval) & 1) == 1
            end)

            EnemyBehavior.TemporarilyDisableNemesisSafeRoomZones(isCurrentlySafeRoom)

            return sdk.to_ptr(false)
        end
    )
end

function EnemyBehavior.DoorHook(args)
    local ok, err = pcall(function()
        if not EnemyBehavior.DoorsEnabled() then
            return
        end

        local door = sdk.to_managed_object(args[2])
        EnemyBehavior.ConfigureDoorForEnemies(door)
    end)

    if not ok then
        log.debug("[EnemyBehavior] door hook error: " .. tostring(err))
    end
end

function EnemyBehavior.SetupDoorHooks()
    local doorType = sdk.find_type_definition(sdk.game_namespace("escape.gimmick.action.EsGimmickDoorBase"))
    if doorType == nil then
        log.debug("[EnemyBehavior] EsGimmickDoorBase type not found.")
        return
    end

    local onOpenedMethod = doorType:get_method("onOpened")
    if onOpenedMethod ~= nil then
        sdk.hook(onOpenedMethod, EnemyBehavior.DoorHook)
    end

    local setupStaticCollidersMethod = doorType:get_method("setupStaticColliders")
    if setupStaticCollidersMethod ~= nil then
        sdk.hook(setupStaticCollidersMethod, EnemyBehavior.DoorHook)
    end

    local findColliderMethod = doorType:get_method("findCollider")
    if findColliderMethod ~= nil then
        sdk.hook(findColliderMethod, EnemyBehavior.DoorHook)
    end
end

function EnemyBehavior.SetupAutoDoorHooks()
    local autoDoorType = sdk.find_type_definition(sdk.game_namespace("gimmick.action.GimmickAutoDoor"))
    if autoDoorType == nil then
        log.debug("[EnemyBehavior] GimmickAutoDoor type not found.")
        return
    end

    local checkSideMethod = autoDoorType:get_method("checkSide")
    if checkSideMethod == nil then
        log.debug("[EnemyBehavior] GimmickAutoDoor.checkSide not found.")
        return
    end

    sdk.hook(checkSideMethod, function(args)
        local ok, err = pcall(function()
            if not EnemyBehavior.DoorsEnabled() then
                return
            end

            local door = sdk.to_managed_object(args[2])
            EnemyBehavior.ConfigureAutoDoorForEnemies(door)
        end)

        if not ok then
            log.debug("[EnemyBehavior] auto door hook error: " .. tostring(err))
        end
    end)
end

function EnemyBehavior.SetupEnemyRelocationHook()
    local enemyParamType = sdk.find_type_definition(sdk.game_namespace("enemy.EmCommonParam"))
    if enemyParamType == nil then
        return
    end

    local relocationMethod = enemyParamType:get_method("genRelocationDelayTime(System.Boolean)")
    if relocationMethod == nil then
        return
    end

    sdk.hook(relocationMethod, function(args)
        if not EnemyBehavior.UnsafeRoomsEnabled() then
            return
        end

        local enteringSafeRoom = sdk.to_int64(args[3]) == 1
        if enteringSafeRoom then
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end)
end

function EnemyBehavior.SetupAreaRestrictionHook()
    local restrictionType = sdk.find_type_definition(sdk.game_namespace("enemy.EnemyAreaRestriction"))
    if restrictionType == nil then
        return
    end

    local method = restrictionType:get_method("setupRestrictArea")
    if method == nil then
        return
    end

    sdk.hook(method, function(args)
        if not EnemyBehavior.DoorsEnabled() then
            return
        end

        return sdk.PreHookResult.SKIP_ORIGINAL
    end)
end

function EnemyBehavior.SetupEnemyDoorAggroHook()
    local hateControllerType = sdk.find_type_definition(sdk.game_namespace("EnemyHateController"))
    if hateControllerType == nil then
        return
    end

    local method = hateControllerType:get_method("find")
    if method == nil then
        return
    end

    sdk.hook(method, function(args)
        if not EnemyBehavior.DoorsEnabled() then
            return
        end

        local ok, attackData = pcall(function()
            return sdk.to_managed_object(args[5])
        end)

        if not ok or not attackData then
            return
        end

        local attackOwner = nil
        pcall(function()
            attackOwner = attackData["<AttackOwnerObject>k__BackingField"]
        end)

        if not attackOwner then
            return
        end

        local ownerName = nil
        pcall(function()
            ownerName = attackOwner:get_Name()
        end)

        if ownerName ~= nil and string.find(ownerName, "Door_") ~= nil then
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end)
end

function EnemyBehavior.SetupScenarioDespawnHook()
    local managerType = sdk.find_type_definition(sdk.game_namespace("gamemastering.ScenarioSequenceManager"))
    if managerType == nil then
        return
    end

    local method = managerType:get_method("removeScenarioStandbyController")
    if method == nil then
        return
    end

    sdk.hook(method, function(args)
        if not EnemyBehavior.PreventDespawnEnabled() then
            return
        end

        if EnemyBehavior.GetPlayerGameObject() == nil then
            return
        end

        log.debug("[EnemyBehavior] Prevented scenario standby removal.")
        return sdk.PreHookResult.SKIP_ORIGINAL
    end)
end

function EnemyBehavior.SetupPersistentColliderBuildHook()
    local standbyType = sdk.find_type_definition(sdk.game_namespace("EnvironmentStandbyController"))
    if standbyType == nil then
        return
    end

    local method = standbyType:get_method("buildAdditionalFolderController")
    if method == nil then
        return
    end

    sdk.hook(method, function(args)
        EnemyBehavior.QueueAction("copy_persistent_map_colliders", function()
            EnemyBehavior.pendingActions["copy_persistent_map_colliders"] = nil
            EnemyBehavior.CopyPersistentMapColliders()
        end)
    end)
end

function EnemyBehavior.SetupFrameCallbacks()
    if EnemyBehavior.frameCallbacksInstalled then
        return
    end

    EnemyBehavior.frameCallbacksInstalled = true

    re.on_application_entry("PrepareRendering", function()
        local callbacks = {}
        for key, callback in pairs(EnemyBehavior.pendingActions) do
            callbacks[key] = callback
        end

        for key, callback in pairs(callbacks) do
            local ok, err = pcall(callback)
            if not ok then
                log.debug("[EnemyBehavior] Deferred action failed: " .. tostring(key) .. " / " .. tostring(err))
                EnemyBehavior.pendingActions[key] = nil
            end
        end
    end)

    re.on_frame(function()
        if not EnemyBehavior.PreventDespawnEnabled() then
            return
        end

        if not Scene:isInGame() then
            return
        end

        local currentSceneAddress = EnemyBehavior.GetCurrentSceneAddress()
        if currentSceneAddress ~= EnemyBehavior.currentSceneAddress then
            EnemyBehavior.currentSceneAddress = currentSceneAddress
            EnemyBehavior.QueueAction("copy_scene_colliders", function()
                EnemyBehavior.pendingActions["copy_scene_colliders"] = nil
                EnemyBehavior.safeRoomIds = nil
                EnemyBehavior.SetNemesisZoneCollidersEnabled(true)
                EnemyBehavior.CopyPersistentMapColliders()
            end)
        end

        if EnemyBehavior.disabledNemesisZones ~= nil then
            local now = EnemyBehavior.GetGameTimeSeconds()
            local shouldEnable = false

            if now == nil or EnemyBehavior.nemesisZonesDisabled == nil then
                shouldEnable = true
            elseif now >= EnemyBehavior.nemesisZonesDisabledUntil then
                shouldEnable = true
            end

            if shouldEnable then
                EnemyBehavior.SetNemesisZoneCollidersEnabled(true)
            end
        end

        local enemyManager = nil
        pcall(function()
            enemyManager = sdk.get_managed_singleton(sdk.game_namespace("EnemyManager"))
        end)

        if enemyManager ~= nil and EnemyBehavior.UnsafeRoomsEnabled() then
            pcall(function()
                enemyManager["<PlayerInSafeRoom>k__BackingField"] = false
            end)
        end
    end)
end

function EnemyBehavior.SetupHooks()
    EnemyBehavior.SetupSafeRoomHook()
    EnemyBehavior.SetupDoorHooks()
    EnemyBehavior.SetupAutoDoorHooks()
    EnemyBehavior.SetupEnemyRelocationHook()
    EnemyBehavior.SetupAreaRestrictionHook()
    EnemyBehavior.SetupEnemyDoorAggroHook()
    EnemyBehavior.SetupScenarioDespawnHook()
    EnemyBehavior.SetupPersistentColliderBuildHook()
    EnemyBehavior.SetupFrameCallbacks()
end

return EnemyBehavior
