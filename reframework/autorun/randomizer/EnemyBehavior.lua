local EnemyBehavior = {}

EnemyBehavior.isInit = false
EnemyBehavior.safeRoomIds = nil
EnemyBehavior.currentSceneAddress = nil
EnemyBehavior.nemesisZonesDisabledUntil = nil
EnemyBehavior.disabledNemesisZones = nil
EnemyBehavior.disabledNemesisZoneAnchor = nil
EnemyBehavior.disabledNemesisZoneTriggeredAt = nil
EnemyBehavior.frameCallbacksInstalled = false
EnemyBehavior.knownDoors = {}
EnemyBehavior.smallCollidersManagedSceneAddress = nil
EnemyBehavior.enemyDoorStates = {}
EnemyBehavior.enemyWanderStates = {}
EnemyBehavior.sceneDoorsCollectedAddress = nil


EnemyBehavior.isRE3 = (reframework:get_game_name() == "re3")
EnemyBehavior.allMaps = nil
EnemyBehavior.allMapsArray = nil

function EnemyBehavior.BuildAllMapsArray()
    if not EnemyBehavior.isRE3 then
        return nil
    end

    if EnemyBehavior.allMapsArray ~= nil then
        return EnemyBehavior.allMapsArray
    end

    local mapType = sdk.find_type_definition(sdk.game_namespace("gamemastering.Map.ID"))
    if mapType == nil then
        return nil
    end

    EnemyBehavior.allMaps = {}
    for _, field in ipairs(mapType:get_fields()) do
        if field:is_static() then
            EnemyBehavior.allMaps[#EnemyBehavior.allMaps + 1] = field:get_data()
        end
    end

    local arrTypeName = sdk.game_namespace("EnemySpawnController.MapInfo")
    local arr = sdk.create_managed_array(arrTypeName, #EnemyBehavior.allMaps):add_ref()
    for i = 1, #EnemyBehavior.allMaps do
        local ok, item = pcall(function()
            local obj = sdk.create_instance(arrTypeName, true):add_ref()
            obj:call(".ctor")
            obj.MapID = EnemyBehavior.allMaps[i]
            obj.Area.mSize = 2
            obj.Area[0] = 0
            obj.Area[1] = 1
            return obj
        end)
        if ok and item ~= nil then
            arr[i - 1] = item
        end
    end

    EnemyBehavior.allMapsArray = arr
    return EnemyBehavior.allMapsArray
end

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


function EnemyBehavior.GetIterableElements(collection)
    if collection == nil then
        return {}
    end

    local okMethod, hasMethod = pcall(function()
        return collection.get_elements ~= nil
    end)

    if okMethod and hasMethod then
        local okElements, elements = pcall(function()
            return collection:get_elements()
        end)

        if okElements and elements ~= nil then
            return elements
        end
    end

    local okCount, count = pcall(function()
        return collection:get_Count()
    end)

    if okCount and type(count) == "number" then
        local result = {}
        for i = 0, count - 1 do
            local okItem, item = pcall(function()
                return collection[i]
            end)
            if okItem then
                result[#result + 1] = item
            end
        end
        return result
    end

    local okLen, len = pcall(function()
        return #collection
    end)

    if okLen and type(len) == "number" then
        local result = {}
        for i = 1, len do
            local okItem, item = pcall(function()
                return collection[i]
            end)
            if okItem then
                result[#result + 1] = item
            end
        end
        return result
    end

    return {}
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

function EnemyBehavior.GetPlayerPosition()
    local player = EnemyBehavior.GetPlayerGameObject()
    if not player then
        return nil
    end

    local ok, transform = pcall(function()
        return player:get_Transform()
    end)

    if not ok or not transform then
        return nil
    end

    local okPos, pos = pcall(function()
        return transform:get_Position()
    end)

    if okPos then
        return pos
    end

    return nil
end

function EnemyBehavior.GetEnemyManager()
    local ok, enemyManager = pcall(function()
        return sdk.get_managed_singleton(sdk.game_namespace("EnemyManager"))
    end)

    if ok then
        return enemyManager
    end

    return nil
end

function EnemyBehavior.IsStalkerContext(ctx)
    if ctx == nil then
        return false
    end

    local ok, tdName = pcall(function()
        return ctx:get_type_definition():get_full_name()
    end)

    if ok and tdName ~= nil then
        if string.find(tdName, "Em9000", 1, true) ~= nil or string.find(tdName, "Em9100", 1, true) ~= nil then
            return true
        end
    end

    local kindValue = nil
    pcall(function()
        kindValue = tostring(ctx:get_KindID())
    end)

    return kindValue == "9000" or kindValue == "9100"
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

    local catalogElements = EnemyBehavior.GetIterableElements(catalogs)

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

function EnemyBehavior.RegisterDoor(door)
    if not door then
        return
    end

    local name = nil
    local gameObject = nil
    local transform = nil
    local center = nil
    local rooms = {}

    pcall(function()
        gameObject = door:get_GameObject()
        name = gameObject and gameObject:get_Name() or nil
        transform = gameObject and gameObject:get_Transform() or nil
        center = door.get_Center and door:get_Center() or nil

        if door._MyRooms ~= nil then
            rooms[1] = door._MyRooms[0] and door._MyRooms[0].value__ or nil
            rooms[2] = door._MyRooms[1] and door._MyRooms[1].value__ or nil
        end
    end)

    if name ~= nil then
        EnemyBehavior.knownDoors[name] = {
            door = door,
            gameObject = gameObject,
            transform = transform,
            center = center,
            rooms = rooms
        }
    end
end

function EnemyBehavior.RefreshKnownDoors()
    if not EnemyBehavior.DoorsEnabled() then
        return
    end

    local scene = EnemyBehavior.GetCurrentScene()
    if not scene then
        return
    end

    local sceneAddress = EnemyBehavior.GetCurrentSceneAddress()
    if sceneAddress ~= nil and EnemyBehavior.sceneDoorsCollectedAddress == sceneAddress then
        return
    end

    EnemyBehavior.knownDoors = {}

    local doorTypes = {
        sdk.game_namespace("escape.gimmick.action.EsGimmickDoorBase"),
        sdk.game_namespace("gimmick.action.GimmickAutoDoor")
    }

    for _, typeName in ipairs(doorTypes) do
        local ok, components = pcall(function()
            return scene:call("findComponents(System.Type)", sdk.typeof(typeName))
        end)

        if ok and components ~= nil then
            local elements = EnemyBehavior.GetIterableElements(components)
            for _, door in pairs(elements) do
                if door ~= nil then
                    EnemyBehavior.RegisterDoor(door)
                end
            end
        end
    end

    EnemyBehavior.sceneDoorsCollectedAddress = sceneAddress
end

function EnemyBehavior.ManageSmallColliders()
    if not EnemyBehavior.IsEnabled() then
        return
    end

    local scene = EnemyBehavior.GetCurrentScene()
    if not scene then
        return
    end

    local sceneAddress = EnemyBehavior.GetCurrentSceneAddress()
    if sceneAddress ~= nil and EnemyBehavior.smallCollidersManagedSceneAddress == sceneAddress then
        return
    end

    local ok, colliderComponents = pcall(function()
        return scene:call("findComponents(System.Type)", sdk.typeof("via.physics.Colliders"))
    end)

    if not ok or colliderComponents == nil then
        return
    end

    local elements = EnemyBehavior.GetIterableElements(colliderComponents)

    for _, colliderComponent in pairs(elements) do
        if colliderComponent ~= nil then
            local okBounds, extentLength = pcall(function()
                return colliderComponent:get_BoundingAabb():getExtent():length()
            end)

            if okBounds and extentLength ~= nil and extentLength < 5.0 then
                local count = 0
                local okCount = pcall(function()
                    count = colliderComponent:getCollidersCount()
                end)

                if okCount then
                    local changedAny = false

                    for i = 0, count - 1 do
                        local okCollider, collider = pcall(function()
                            return colliderComponent:getColliders(i)
                        end)

                        if okCollider and collider ~= nil then
                            pcall(function()
                                local filterInfo = collider:get_FilterInfo()
                                local filterResource = collider:get_CollisionFilterResource()
                                local filterName = filterResource and filterResource:ToString() or ""

                                if filterInfo ~= nil
                                    and filterInfo:get_MaskBits() == 8
                                    and string.find(filterName, "TerrainEm", 1, true) ~= nil then
                                    collider:set_Enabled(false)
                                    changedAny = true
                                end
                            end)
                        end
                    end

                    if changedAny then
                        pcall(function()
                            colliderComponent:onDirty()
                        end)
                    end
                end
            end
        end
    end

    EnemyBehavior.smallCollidersManagedSceneAddress = sceneAddress
end

function EnemyBehavior.ConfigureDoorForEnemies(door)
    if not door or not EnemyBehavior.DoorsEnabled() then
        return
    end

    EnemyBehavior.RegisterDoor(door)

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

    EnemyBehavior.RegisterDoor(door)

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
EnemyBehavior.disabledNemesisZoneAnchor = nil
EnemyBehavior.disabledNemesisZoneTriggeredAt = nil
        EnemyBehavior.nemesisZonesDisabledUntil = nil
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

    local zoneElements = EnemyBehavior.GetIterableElements(zones)
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
    EnemyBehavior.disabledNemesisZoneAnchor = collectedZones[1]

    for _, zone in pairs(collectedZones) do
        pcall(function()
            local colliders = EnemyBehavior.GetComponent(zone, "via.physics.Colliders")
            if colliders ~= nil and colliders.set_Enabled then
                colliders:set_Enabled(false)
            end
        end)
    end

    local now = EnemyBehavior.GetGameTimeSeconds()
    EnemyBehavior.disabledNemesisZoneTriggeredAt = now
    EnemyBehavior.nemesisZonesDisabledUntil = now and (now + 10.0) or nil
end

function EnemyBehavior.GetEnemyList()
    local enemyManager = EnemyBehavior.GetEnemyManager()
    if enemyManager == nil then
        return {}
    end

    local enemyList = nil
    pcall(function()
        enemyList = enemyManager["<EnemyList>k__BackingField"]
    end)

    if enemyList == nil or enemyList.mItems == nil then
        return {}
    end

    local elements = EnemyBehavior.GetIterableElements(enemyList.mItems)
    local result = {}

    for _, regInfo in pairs(elements) do
        if regInfo ~= nil then
            local ctx = nil
            pcall(function()
                ctx = regInfo["<Context>k__BackingField"]
            end)

            if ctx ~= nil then
                result[#result + 1] = ctx
            end
        end
    end

    return result
end

function EnemyBehavior.GetEnemyContextKey(ctx)
    if ctx == nil then
        return nil
    end

    local key = nil
    pcall(function()
        local gameObject = ctx:get_GameObject()
        local name = gameObject and gameObject:get_Name() or "Enemy"
        key = name .. string.format(" @ 0x%x", ctx:get_address())
    end)

    return key
end

function EnemyBehavior.GetEnemyMotionNode(enemyController)
    if enemyController == nil then
        return ""
    end

    local motionFsm = nil
    pcall(function()
        motionFsm = enemyController["<MotionFsm>k__BackingField"]
    end)

    if motionFsm == nil or not motionFsm.getCurrentNodeName then
        return ""
    end

    local ok, nodeName = pcall(function()
        return motionFsm:getCurrentNodeName(0)
    end)

    if ok and nodeName ~= nil then
        return nodeName
    end

    return ""
end

function EnemyBehavior.GetEnemyFindState(enemyController)
    if enemyController == nil then
        return nil
    end

    local hateController = nil
    pcall(function()
        hateController = enemyController["<HateController>k__BackingField"]
    end)

    if hateController == nil then
        return nil
    end

    local rawState = nil
    pcall(function()
        rawState = hateController["<FindState>k__BackingField"]
    end)

    if rawState == 0 then
        return "Lost"
    elseif rawState == 1 then
        return "Attention"
    elseif rawState == 2 then
        return "Finding"
    end

    return nil
end

function EnemyBehavior.ConfigureEnemyContext(ctx)
    if not EnemyBehavior.IsEnabled() or ctx == nil then
        return
    end

    local common = nil
    local param = nil
    pcall(function()
        common = ctx.CommonContextParam
        param = ctx.ContextParam
    end)

    if common ~= nil then
        pcall(function() common.AreaRestrictEnable = false end)
        pcall(function() common.PermitInvalidAssign = true end)
        pcall(function() common.OverwriteAreaMoveNum = true end)
        pcall(function() common.AreaMoveEnableNum = 99 end)
        pcall(function() common._TerritoryType = 0 end)
        pcall(function() common._TerritoryTurnBackPointType = 0 end)
        pcall(function() common._TerritoryForceFind = false end)
        pcall(function() common.AreaRestrictTurnBackMapID = false end)
        pcall(function() common.UseAreaRestrictTurnBackPosition = false end)
        pcall(function() common._setRestrictTurnBackMapID = false end)
        pcall(function() common.IgnoreHideDeadEnemies = true end)
        pcall(function() common._TerritoryTurnBackMapID = 0 end)
        pcall(function()
            if common.RestrictAreaList ~= nil and common.RestrictAreaList.Clear then
                common.RestrictAreaList:Clear()
            end
        end)
        pcall(function() common.LimitedAreaSet = false end)
        pcall(function() common.AutoAssignMode = true end)
    end

    if param ~= nil then
        pcall(function() param.ForceFindingPlayerKeep = EnemyBehavior.IsStalkerContext(ctx) end)
        pcall(function() param["<LiteMode>k__BackingField"] = false end)
    end
end

function EnemyBehavior.ConfigureEnemyRuntime(ctx)
    if not EnemyBehavior.IsEnabled() or ctx == nil then
        return
    end

    local enemyController = nil
    local gameObject = nil
    local gcc = nil
    local areaRestricter = nil
    local navi = nil
    local stay = nil

    pcall(function()
        enemyController = ctx["<EnemyController>k__BackingField"]
        gameObject = ctx["<EnemyGameObject>k__BackingField"]
    end)

    if enemyController == nil or gameObject == nil then
        return
    end

    pcall(function()
        gcc = enemyController["<EnemyGimmickConfiscateController>k__BackingField"]
        navi = enemyController["<NaviMoveSupporter>k__BackingField"]
        stay = enemyController["<StayAreaController>k__BackingField"]
    end)

    areaRestricter = EnemyBehavior.GetComponent(gameObject, sdk.game_namespace("EnemyAreaRestrictController"))

    if gcc ~= nil then
        pcall(function()
            gcc.DoorAllMapActiveCheck = false
        end)
    end

    if areaRestricter ~= nil then
        pcall(function()
            if areaRestricter.LimitedAreaList ~= nil and areaRestricter.LimitedAreaList.Clear then
                areaRestricter.LimitedAreaList:Clear()
            end
        end)
        pcall(function()
            if areaRestricter.RestrictAreaList ~= nil and areaRestricter.RestrictAreaList.Clear then
                areaRestricter.RestrictAreaList:Clear()
            end
        end)
        pcall(function()
            areaRestricter._MoveNum = 99
        end)
    end

    if stay ~= nil then
        local enemyManager = EnemyBehavior.GetEnemyManager()
        if enemyManager ~= nil then
            pcall(function()
                stay["<StayLocationID>k__BackingField"] = enemyManager["<LastPlayerStayLocationID>k__BackingField"]
                stay.AssignMapID = enemyManager["<LastPlayerStaySceneArea>k__BackingField"]
            end)
        end
    end

    if EnemyBehavior.IsStalkerContext(ctx) then
        pcall(function()
            ctx["<IsStayActiveArea>k__BackingField"] = true
        end)
        pcall(function()
            if enemyController["<GroundFixer>k__BackingField"] ~= nil then
                enemyController["<GroundFixer>k__BackingField"].Mode = 2
            end
        end)
    end

    if navi ~= nil then
        pcall(function()
            navi:set_Enabled(true)
        end)
    end
end

function EnemyBehavior.GetDoorContactInfo(gcc)
    if gcc == nil then
        return nil, nil, nil
    end

    local contactList = nil
    local contactEntry = nil
    local gimmick = nil
    local doorObject = nil

    local ok = pcall(function()
        contactList = gcc.ContactGimmickList
        if contactList == nil or contactList.mItems == nil then
            return
        end

        contactEntry = contactList.mItems[0]
        if contactEntry == nil then
            return
        end

        gimmick = contactEntry:get_Gimmick()
        if gimmick ~= nil and gimmick.get_GameObject then
            doorObject = gimmick:get_GameObject()
        end
    end)

    if not ok then
        return nil, nil, nil
    end

    return contactEntry, gimmick, doorObject
end

function EnemyBehavior.GetContactDoor(contactEntry, gimmick, doorObject)
    if doorObject ~= nil then
        local okName, ownerName = pcall(function()
            return doorObject:get_Name()
        end)

        if okName and ownerName ~= nil and EnemyBehavior.knownDoors[ownerName] ~= nil then
            return EnemyBehavior.knownDoors[ownerName].door, ownerName
        end
    end

    if gimmick ~= nil then
        local resolvedDoor = nil
        pcall(function()
            resolvedDoor = gimmick._GimmickBody or gimmick._Gimmick or gimmick
        end)

        if resolvedDoor ~= nil then
            local okName, name = pcall(function()
                local go = resolvedDoor:get_GameObject()
                return go and go:get_Name() or nil
            end)

            if okName and name ~= nil then
                return resolvedDoor, name
            end
        end
    end

    return nil, nil
end

function EnemyBehavior.CanForceDoorInteraction(door, contactEntry)
    if door == nil then
        return false
    end

    local canInteract = false
    pcall(function()
        local isAutoDoor = false
        if contactEntry ~= nil and contactEntry.get_Class then
            isAutoDoor = (contactEntry:get_Class() == 4)
        end

        if isAutoDoor then
            return
        end

        if door.get_IsOpened and door:get_IsOpened() then
            return
        end

        if door.get_IsLocked and door:get_IsLocked() then
            return
        end

        if door._SaveData ~= nil and not door._SaveData.HasOpened then
            return
        end

        canInteract = true
    end)

    return canInteract
end

function EnemyBehavior.UpdateEnemyDoorRoutine(ctx, enemyController, gcc)
    if not EnemyBehavior.DoorsEnabled() or gcc == nil then
        return
    end

    local ctxKey = EnemyBehavior.GetEnemyContextKey(ctx)
    if ctxKey == nil then
        return
    end

    local state = EnemyBehavior.enemyDoorStates[ctxKey] or {}
    EnemyBehavior.enemyDoorStates[ctxKey] = state

    pcall(function()
        gcc.DoorAllMapActiveCheck = false
    end)

    local contactEntry, gimmick, doorObject = EnemyBehavior.GetDoorContactInfo(gcc)
    local door, doorName = EnemyBehavior.GetContactDoor(contactEntry, gimmick, doorObject)

    local doorAlreadyOpen = false
    if door ~= nil then
        pcall(function()
            doorAlreadyOpen = door.get_IsOpened and door:get_IsOpened() or false
        end)
    end

    if doorAlreadyOpen then
        state.doorName = nil
        state.startTime = nil
        state.lastForceTime = EnemyBehavior.GetGameTimeSeconds()
        return
    end

    if door == nil or not EnemyBehavior.CanForceDoorInteraction(door, contactEntry) then
        state.doorName = nil
        state.startTime = nil
        return
    end

    EnemyBehavior.ConfigureDoorForEnemies(door)
    EnemyBehavior.ConfigureAutoDoorForEnemies(door)

    local nodeName = EnemyBehavior.GetEnemyMotionNode(enemyController)
    local isWalking = string.find(nodeName, "WALK", 1, true) ~= nil

    if not isWalking then
        state.doorName = nil
        state.startTime = nil
        return
    end

    local now = EnemyBehavior.GetGameTimeSeconds()
    if state.doorName ~= doorName then
        state.doorName = doorName
        state.startTime = now
        state.lastForceTime = state.lastForceTime or 0
        return
    end

    if now == nil or state.startTime == nil then
        return
    end

    if now - state.startTime < 1.5 then
        return
    end

    if state.lastForceTime ~= nil and (now - state.lastForceTime) < 6.0 then
        return
    end

    local ok = pcall(function()
        local targetObject = nil
        if contactEntry ~= nil and contactEntry.get_Gimmick then
            local contactGimmick = contactEntry:get_Gimmick()
            if contactGimmick ~= nil and contactGimmick.get_GameObject then
                targetObject = contactGimmick:get_GameObject()
            end
        end

        if targetObject == nil and door.get_GameObject then
            targetObject = door:get_GameObject()
        end

        if targetObject ~= nil then
            gcc:requestGimmickInteractForce(targetObject)
            state.lastForceTime = now
            state.startTime = now
        end
    end)

    if not ok then
        state.lastForceTime = now
    end
end

function EnemyBehavior.TryAssignWanderDoor(ctx, enemyController, transform, navi)
    if not EnemyBehavior.DoorsEnabled() or navi == nil then
        return
    end

    local findState = EnemyBehavior.GetEnemyFindState(enemyController)
    if findState ~= "Lost" then
        return
    end

    local nodeName = EnemyBehavior.GetEnemyMotionNode(enemyController)
    if string.find(nodeName, "STANDING", 1, true) == nil then
        return
    end

    local ctxKey = EnemyBehavior.GetEnemyContextKey(ctx)
    if ctxKey == nil then
        return
    end

    local state = EnemyBehavior.enemyWanderStates[ctxKey] or {}
    EnemyBehavior.enemyWanderStates[ctxKey] = state

    local now = EnemyBehavior.GetGameTimeSeconds()
    if now == nil then
        return
    end

    if state.lastAssignTime ~= nil and (now - state.lastAssignTime) < 4.0 then
        return
    end

    if next(EnemyBehavior.knownDoors) == nil then
        return
    end

    local enemyPos = nil
    pcall(function()
        enemyPos = transform:get_Position()
    end)

    local playerPos = EnemyBehavior.GetPlayerPosition()
    local bestDoor = nil
    local bestDistance = nil

    for _, doorInfo in pairs(EnemyBehavior.knownDoors) do
        local door = doorInfo.door
        local center = doorInfo.center

        if door ~= nil and center ~= nil then
            local validDoor = false
            pcall(function()
                local locked = door.get_IsLocked and door:get_IsLocked() or false
                local opened = door.get_IsOpened and door:get_IsOpened() or false
                local saveOpened = door._SaveData == nil or door._SaveData.HasOpened
                validDoor = (not locked) and saveOpened and (not opened)
            end)

            if validDoor and enemyPos ~= nil then
                local distance = (center - enemyPos):length()
                local nearPlayer = playerPos ~= nil and (center - playerPos):length() < 3.5

                if not nearPlayer and distance > 1.5 and distance < 18.0 then
                    if bestDoor == nil or distance < bestDistance then
                        bestDoor = doorInfo
                        bestDistance = distance
                    end
                end
            end
        end
    end

    if bestDoor == nil or bestDoor.center == nil then
        return
    end

    pcall(function()
        navi["<NaviTargetPos>k__BackingField"] = bestDoor.center
        if navi.syncNavigationTarget then
            navi:syncNavigationTarget()
        end
        state.lastAssignTime = now
    end)
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
    end)
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


function EnemyBehavior.SetupEnemySpawnControllerHook()
    if not EnemyBehavior.isRE3 then
        return
    end

    local spawnControllerType = sdk.find_type_definition(sdk.game_namespace("EnemySpawnController"))
    if spawnControllerType == nil then
        return
    end

    local method = spawnControllerType:get_method("setActivity")
    if method == nil then
        return
    end

    sdk.hook(method, function(args)
        local ok, err = pcall(function()
            if not EnemyBehavior.IsEnabled() then
                return
            end

            local obj = sdk.to_managed_object(args[2])
            if obj == nil then
                return
            end

            local allMapsArray = EnemyBehavior.BuildAllMapsArray()
            if allMapsArray == nil then
                return
            end

            pcall(function()
                obj.EnableMapIDList.mItems = allMapsArray:MemberwiseClone()
                obj.EnableMapIDList.mSize = #EnemyBehavior.allMaps
                obj.EnableOffToOn = true
            end)
        end)

        if not ok then
            log.debug("[EnemyBehavior] spawn controller hook error: " .. tostring(err))
        end
    end)
end

function EnemyBehavior.SetupEnemySpawnHook()
    local commonContextType = sdk.find_type_definition(sdk.game_namespace("enemy.EmCommonContext"))
    if commonContextType == nil then
        return
    end

    local requestEnemyCreateMethod = commonContextType:get_method("requestEnemyCreate")
    if requestEnemyCreateMethod == nil then
        return
    end

    sdk.hook(requestEnemyCreateMethod, function(args)
        local ok, err = pcall(function()
            local ctx = sdk.to_managed_object(args[2])
            EnemyBehavior.ConfigureEnemyContext(ctx)
        end)

        if not ok then
            log.debug("[EnemyBehavior] spawn hook error: " .. tostring(err))
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

        if ownerName == nil then
            return
        end

        if EnemyBehavior.knownDoors[ownerName] ~= nil then
            return sdk.PreHookResult.SKIP_ORIGINAL
        end

        if string.find(ownerName, "Door_", 1, true) ~= nil then
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end)
end

function EnemyBehavior.UpdateEnemyAggression()
    if not EnemyBehavior.IsEnabled() then
        return
    end

    EnemyBehavior.RefreshKnownDoors()

    local contexts = EnemyBehavior.GetEnemyList()
    for _, ctx in ipairs(contexts) do
        local enemyController = nil
        local gameObject = nil
        local transform = nil
        local gcc = nil
        local navi = nil

        pcall(function()
            enemyController = ctx["<EnemyController>k__BackingField"]
            gameObject = ctx["<EnemyGameObject>k__BackingField"]
            transform = gameObject and gameObject:get_Transform() or nil
            gcc = enemyController and enemyController["<EnemyGimmickConfiscateController>k__BackingField"] or nil
            navi = enemyController and enemyController["<NaviMoveSupporter>k__BackingField"] or nil
        end)

        if enemyController ~= nil and gameObject ~= nil and transform ~= nil then
            EnemyBehavior.ConfigureEnemyRuntime(ctx)
            EnemyBehavior.UpdateEnemyDoorRoutine(ctx, enemyController, gcc)
            EnemyBehavior.TryAssignWanderDoor(ctx, enemyController, transform, navi)
        end
    end
end

function EnemyBehavior.SetupFrameCallbacks()
    if EnemyBehavior.frameCallbacksInstalled then
        return
    end

    EnemyBehavior.frameCallbacksInstalled = true

    re.on_frame(function()
        local sceneAddress = EnemyBehavior.GetCurrentSceneAddress()
        if sceneAddress ~= nil and EnemyBehavior.currentSceneAddress ~= sceneAddress then
            EnemyBehavior.currentSceneAddress = sceneAddress
            EnemyBehavior.safeRoomIds = nil
            EnemyBehavior.knownDoors = {}
            EnemyBehavior.smallCollidersManagedSceneAddress = nil
            EnemyBehavior.sceneDoorsCollectedAddress = nil


EnemyBehavior.isRE3 = (reframework:get_game_name() == "re3")
EnemyBehavior.allMaps = nil
EnemyBehavior.allMapsArray = nil

function EnemyBehavior.BuildAllMapsArray()
    if not EnemyBehavior.isRE3 then
        return nil
    end

    if EnemyBehavior.allMapsArray ~= nil then
        return EnemyBehavior.allMapsArray
    end

    local mapType = sdk.find_type_definition(sdk.game_namespace("gamemastering.Map.ID"))
    if mapType == nil then
        return nil
    end

    EnemyBehavior.allMaps = {}
    for _, field in ipairs(mapType:get_fields()) do
        if field:is_static() then
            EnemyBehavior.allMaps[#EnemyBehavior.allMaps + 1] = field:get_data()
        end
    end

    local arrTypeName = sdk.game_namespace("EnemySpawnController.MapInfo")
    local arr = sdk.create_managed_array(arrTypeName, #EnemyBehavior.allMaps):add_ref()
    for i = 1, #EnemyBehavior.allMaps do
        local ok, item = pcall(function()
            local obj = sdk.create_instance(arrTypeName, true):add_ref()
            obj:call(".ctor")
            obj.MapID = EnemyBehavior.allMaps[i]
            obj.Area.mSize = 2
            obj.Area[0] = 0
            obj.Area[1] = 1
            return obj
        end)
        if ok and item ~= nil then
            arr[i - 1] = item
        end
    end

    EnemyBehavior.allMapsArray = arr
    return EnemyBehavior.allMapsArray
end
            EnemyBehavior.enemyDoorStates = {}
            EnemyBehavior.enemyWanderStates = {}
        end

        if not Scene:isInGame() then
            return
        end

        EnemyBehavior.ManageSmallColliders()

        if EnemyBehavior.disabledNemesisZones ~= nil then
            local now = EnemyBehavior.GetGameTimeSeconds()
            local shouldEnable = false

            if now == nil or EnemyBehavior.nemesisZonesDisabledUntil == nil then
                shouldEnable = true
            elseif now >= EnemyBehavior.nemesisZonesDisabledUntil then
                local playerObject = EnemyBehavior.GetPlayerGameObject()
                local anchorObject = nil
                if EnemyBehavior.disabledNemesisZoneAnchor ~= nil then
                    pcall(function()
                        anchorObject = EnemyBehavior.disabledNemesisZoneAnchor:get_GameObject()
                    end)
                end

                if playerObject == nil or anchorObject == nil then
                    shouldEnable = true
                else
                    local distanceMethod = sdk.find_type_definition("offline.MathEx")
                    distanceMethod = distanceMethod and distanceMethod:get_method("distance(via.GameObject, via.GameObject)") or nil

                    if distanceMethod == nil then
                        shouldEnable = true
                    else
                        local okDistance, distanceValue = pcall(function()
                            return distanceMethod:call(nil, anchorObject, playerObject:get_GameObject())
                        end)

                        if not okDistance or distanceValue == nil or distanceValue > 6.5 then
                            shouldEnable = true
                        end
                    end
                end
            end

            if shouldEnable then
                EnemyBehavior.SetNemesisZoneCollidersEnabled(true)
            end
        end

        local enemyManager = EnemyBehavior.GetEnemyManager()
        if enemyManager ~= nil and EnemyBehavior.UnsafeRoomsEnabled() then
            pcall(function()
                enemyManager["<PlayerInSafeRoom>k__BackingField"] = false
            end)
        end

        EnemyBehavior.UpdateEnemyAggression()
    end)
end

function EnemyBehavior.SetupHooks()
    EnemyBehavior.SetupSafeRoomHook()
    EnemyBehavior.SetupDoorHooks()
    EnemyBehavior.SetupAutoDoorHooks()
    EnemyBehavior.SetupEnemySpawnControllerHook()
    EnemyBehavior.SetupEnemySpawnHook()
    EnemyBehavior.SetupEnemyRelocationHook()
    EnemyBehavior.SetupAreaRestrictionHook()
    EnemyBehavior.SetupEnemyDoorAggroHook()
    EnemyBehavior.SetupFrameCallbacks()
end

return EnemyBehavior