local game_name = reframework:get_game_name()
if game_name ~= "re3" then
    re.msg("This script is only for RE3")
    return
end

log.debug("[Randomizer] Loading mod...")

-- START globals
AP_REF = require("AP_REF/core")

Manifest = require("randomizer/Manifest")
Lookups = require("randomizer/Lookups")

Archipelago = require("randomizer/Archipelago")
CutsceneObjects = require("randomizer/CutsceneObjects")
DestroyObjects = require("randomizer/DestroyObjects")
Enemy = require("randomizer/Enemy")
EnemyBehavior = require("randomizer/EnemyBehavior")
EnemySpeed = require("randomizer/EnemySpeed")
EnemyInvisible = require("randomizer/EnemyInvisible")
Files = require("randomizer/Files")
FixBoxes = require("randomizer/FixBoxes")
GUI = require("randomizer/GUI")
GUIInventory = require("randomizer/GUIInventory")
GUISave = require("randomizer/GUISave")
GUISync = require("randomizer/GUISync")
Helpers = require("randomizer/Helpers")
HospitalDefenseSkip = require("randomizer/HospitalDefenseSkip")
Inventory = require("randomizer/Inventory")
ItemBox = require("randomizer/ItemBox")
ItemDuplicates = require("randomizer/ItemDuplicates")
ItemIndicator = require("randomizer/ItemIndicator")
ItemPersist = require("randomizer/ItemPersist")
Items = require("randomizer/Items")
Logic = require("randomizer/Logic")
Player = require("randomizer/Player")
Records = require("randomizer/Records")
SaveData = require("randomizer/SaveData")
Scene = require("randomizer/Scene")
Storage = require("randomizer/Storage")
Typewriters = require("randomizer/Typewriters")
Tools = require("randomizer/Tools")
-- END globals

-- For debugging / trying out functionality:
-- Player.GetInventorySlots()
-- ItemBox.GetItems()

-- Door gimmicks (like Door_2_1_003_gimmick) have a GimmickDoor comp
--   that has references to "MyRooms" and "MyLocations", and something about "IsPairComplete"

re.on_pre_application_entry("UpdateBehavior", function()
    -- if not Scene:isInGame() then
    --     Archipelago.DisableInGameClient("Start a new game or load a file before connecting to AP.");
    -- else
    --     Archipelago.EnableInGameClient();
    -- end

    -- Also run while inventory/get-item UI is open (IsInGame can flicker false).
    local inGameOrInventory = Scene:isInGame() or Scene.isUsingInventory()

    if inGameOrInventory then
        -- Install hooks even during transitions (EnemyBehavior must see
        -- isTransitioning and allow scenario standby teardown for Carlos).
        Archipelago.Init()
        Enemy.Init()
        EnemyBehavior.Init()
        EnemySpeed.Init()
        EnemyInvisible.Init()
        Files.Init()
        FixBoxes.Init()
        GUIInventory.Init()
        Items.Init()
        ItemDuplicates.Init()
        ItemIndicator.Init()
        ItemPersist.Init()
        SaveData.Init()
        CutsceneObjects.Init()

        if Scene:isInGame() and not Scene.isTransitioning() then
            DestroyObjects.Init()

            if Archipelago.waitingForSync then
                Archipelago.waitingForSync = false
                Archipelago.Sync()
            end

            -- Re-evaluate DeathLink when the live difficulty becomes known / changes.
            local deathLinkDiff = Records.getDeathLinkDifficultyId()
            if deathLinkDiff ~= Archipelago.lastDeathLinkDiffCheck then
                Archipelago.lastDeathLinkDiffCheck = deathLinkDiff
                Archipelago.UpdateDeathLinkTag()
            end

            Archipelago.ProcessImmediateItemsQueue()

            if Archipelago.CanReceiveItems() then
                Archipelago.ProcessItemsQueue()
            end

            -- Carlos's inventory is often created later; keep both survivors synced.
            Inventory.SyncHipPouchSlots()

            -- Off mode is a no-op; enabled modes apply here (no on_frame).
            EnemySpeed.Update()
            EnemyInvisible.Update()

            ItemDuplicates.Update()
            ItemBox.DedupeCheck()

            -- if the game randomly forgets that the player exists and tries to leave the invincibility flag on from item pickup,
            --   relentlessly check for the player existing until it does, then turn that flag off
            if Archipelago.waitingForInvincibilityOff then
                if Player.TurnOffInvincibility() then
                    Archipelago.waitingForInvincibilityOff = false
                end
            end

            if Player.waitingForKill then
                Player.Kill()
            else
                Archipelago.canDeathLink = true
                Archipelago.wasDeathLinked = false
            end
        end
    else
        CutsceneObjects.isInit = false -- look for objects that should be disabled and disable them again
        DestroyObjects.isInit = false -- look for objects that should be destroyed and destroy them again
        FixBoxes.isInit = false -- look for boxes that should be a set item and set it again
        ItemDuplicates.isInit = false -- look for duplicate items that should be removed and remove them again
        ItemDuplicates.lastDedupeTime = 0
        EnemyBehavior.isInit = false
        EnemyBehavior.safeRoomIds = nil
        EnemyBehavior.persistentColliderObject = nil
        EnemyBehavior.pendingActions = {}
        EnemyBehavior.currentSceneAddress = nil
        EnemyBehavior.nemesisZonesDisabledUntil = nil
        EnemyBehavior.disabledNemesisZones = nil
        EnemySpeed.isInit = false
        EnemySpeed.lastMode = nil
        EnemyInvisible.isInit = false
        EnemyInvisible.lastMode = nil
    end

    -- These completion handlers must keep running while an inventory or file
    -- viewer is open; Scene:isInGame() is false while those UIs are active.
    Files.FinishPhysicalFile()
    Items.HandleDisconnectWait()

    if Scene:isInGameOver() then
        if Archipelago.canDeathLink and not Archipelago.wasDeathLinked then
            Archipelago.canDeathLink = false
            Archipelago:SendDeathLink()
        end
        
        -- now handled by SaveData load hook
        --
        -- if not Archipelago.waitingForSync then
        --     Archipelago.waitingForSync = true
        -- end

        Archipelago.didGameOver = true
    end
end)

re.on_frame(function ()
    -- ... one day OpieOP
    -- if Scene:isTitleScreen() then
    --     GUI.ShowRandomizerLogo()
    -- end

    if reframework:is_drawing_ui() then
        Tools.ShowGUI()
    end

    if Scene:isInGame() or Scene:isInGameOver() then
        GUI.CheckDifficultyWarning()
        GUI.CheckVersionWarning()
        GUI.CheckForAndDisplayMessages()
    else
        -- if the player isn't in-game or on game over screen, GUI isn't showing, so keep the timer to clear messages at 0 until they are
        GUI.lastText = os.time()
    end

    if Scene:isInGame() then 
        GUIInventory.CheckForAndDisplayMessages()
        GUISave.CheckForAndDisplayMessages()
        GUISync.CheckForAndDisplayMessages()
        ItemIndicator.Draw()

        -- only show the typewriter window when the user presses the reframework hotkey
        if reframework:is_drawing_ui() then
            Typewriters.DisplayWarpMenu()
        end
    end
end)

re.on_draw_ui(function () -- this is only called when Script Generated UI is visible
    -- nothing, but could add some debug stuff here one day
end)

log.debug("[Randomizer] Mod loaded.")
