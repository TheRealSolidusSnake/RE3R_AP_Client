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
FixBoxes = require("randomizer/FixBoxes")
GUI = require("randomizer/GUI")
GUIInventory = require("randomizer/GUIInventory")
GUISave = require("randomizer/GUISave")
GUISync = require("randomizer/GUISync")
Helpers = require("randomizer/Helpers")
Inventory = require("randomizer/Inventory")
ItemBox = require("randomizer/ItemBox")
ItemDuplicates = require("randomizer/ItemDuplicates")
ItemResend = require("randomizer/ItemResend")
Items = require("randomizer/Items")
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

    if Scene:isInGame() then 
        Archipelago.Init()
        CutsceneObjects.Init()
        DestroyObjects.Init()
        Enemy.Init()
        EnemyBehavior.Init()
        FixBoxes.Init()
        GUIInventory.Init()
        Items.Init()
        ItemDuplicates.Init()
        ItemResend.Init()
        SaveData.Init()

        if Archipelago.waitingForSync then
            Archipelago.waitingForSync = false
            Archipelago.Sync()
        end

        if Archipelago.CanReceiveItems() then
            Archipelago.ProcessItemsQueue()
        end

        ItemBox.DedupeCheck()
        ItemResend.CheckAll()

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
    else
        CutsceneObjects.isInit = false -- look for objects that should be disabled and disable them again
        DestroyObjects.isInit = false -- look for objects that should be destroyed and destroy them again
        FixBoxes.isInit = false -- look for boxes that should be a set item and set it again
        ItemDuplicates.isInit = false -- look for duplicate items that should be removed and remove them again
        ItemResend.isInit = false -- allow resend checks to re-init cleanly on next in-game load
        EnemyBehavior.isInit = false
        EnemyBehavior.safeRoomIds = nil
        EnemyBehavior.persistentColliderObject = nil
        EnemyBehavior.pendingActions = {}
        EnemyBehavior.currentSceneAddress = nil
        EnemyBehavior.nemesisZonesDisabled = nil
        EnemyBehavior.disabledNemesisZones = nil
    end

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
