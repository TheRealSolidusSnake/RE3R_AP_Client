local Tools = {}

function Tools.ShowGUI()
    local scenario_text = '   (not connected)'
    local deathlink_text = '   (not connected)'
    local deathlink_color = AP_REF.HexToImguiColor('FFFFFF')
    local enemy_behavior_text = '   (not connected)'
    local enemy_behavior_color = AP_REF.HexToImguiColor('777777')
    local enemy_kills_text = '   (not connected)'
    local enemy_kills_color = AP_REF.HexToImguiColor('777777')
    local version_text = tostring(Manifest.version)
    local version_mismatch = false

    -- if the lookups contain data, then we're connected, so do everything that needs connection
    if Lookups.difficulty then
        scenario_text = "   " .. Lookups.difficulty:gsub("^%l", string.upper)

        if Archipelago.death_link then
            deathlink_text = "On"
        else
            deathlink_text = "Off"
            deathlink_color = AP_REF.HexToImguiColor('777777')
        end

        if Archipelago.enemy_behavior and Archipelago.enemy_behavior ~= "Off" then
            enemy_behavior_text = "   " .. tostring(Archipelago.enemy_behavior)
            enemy_behavior_color = AP_REF.HexToImguiColor('FFFFFF')
        else
            enemy_behavior_text = "Off"
            enemy_behavior_color = AP_REF.HexToImguiColor('777777')
        end

        if Archipelago.enemy_kills and tostring(Archipelago.enemy_kills) ~= "None" and tostring(Archipelago.enemy_kills) ~= "Off" then
            enemy_kills_text = "   " .. tostring(Archipelago.enemy_kills)
            enemy_kills_color = AP_REF.HexToImguiColor('FFFFFF')
        else
            enemy_kills_text = "Off"
            enemy_kills_color = AP_REF.HexToImguiColor('777777')
        end

        if Archipelago.apworld_version == nil or Archipelago.apworld_version ~= Manifest.version then
            if Archipelago.apworld_version ~= nil then
                version_text = version_text .. ' (world is ' .. Archipelago.apworld_version .. ')'
            else
                version_text = version_text .. ' (world is outdated)'
            end

            version_mismatch = true
        else
            version_text = version_text .. ' (matches)'
        end
    end
    
    -- local player_character_text = "   (not in-game)"
    -- if Scene.isCharacterJill() then player_character_text = "   Jill" end
    -- if Scene.isCharacterCarlos() then player_character_text = "   Carlos" end

    imgui.set_next_window_size(Vector2f.new(320, 710), 0)
    imgui.begin_window("Archipelago Game Mod ", nil,
        8 -- NoScrollbar
    )

    imgui.text_colored(" Mod Version Number: ", -10825765)
    imgui.same_line() 

    if version_mismatch then
        imgui.text_colored("    " .. version_text, AP_REF.HexToImguiColor('fa3d2f'))
    else
        imgui.text("    " .. version_text)
    end

    imgui.text_colored(" AP Difficulty: ", -10825765)
    imgui.same_line()
    imgui.text(scenario_text)

    imgui.text_colored(" DeathLink: ", -10825765)
    imgui.same_line()
    imgui.text_colored("                         " .. deathlink_text, deathlink_color)

    imgui.text_colored(" Enemy Behavior: ", -10825765)
    imgui.same_line()
    imgui.text_colored("              " .. enemy_behavior_text, enemy_behavior_color)

    imgui.text_colored(" Enemy Kills: ", -10825765)
    imgui.same_line()
    imgui.text_colored("                   " .. enemy_kills_text, enemy_kills_color)
    imgui.new_line()

    imgui.separator()
    imgui.text_colored("         The default keyboard key to show or hide", AP_REF.HexToImguiColor('bbbbbb'))
    imgui.text_colored("         these windows is INSERT.", AP_REF.HexToImguiColor('bbbbbb'))
    imgui.separator()

    if Lookups.difficulty then
        imgui.new_line()
        imgui.text_colored(" Clock Puzzle Broken?", AP_REF.HexToImguiColor('09ba39'))
        imgui.text("    Click this button to fix ")
        imgui.text("    the puzzle door!")

        imgui.text("  ")
        imgui.same_line()
        
        if imgui.button("Fix Clock Puzzle") then
            GUI.AddText("Fixing Clock Puzzle...")
            CutsceneObjects.ClockPuzzle()
        end   
    
        imgui.new_line()
        imgui.text_colored(" Missing Items?", AP_REF.HexToImguiColor('09ba39'))
        imgui.text("    If you were sent items at the ")
        imgui.text("    start and didn't receive them,")
        imgui.text("    click this button.")

        imgui.text("  ")
        imgui.same_line()
        
        if imgui.button("Receive Items Again") then
            Storage.lastReceivedItemIndex = -1
            Storage.lastSavedItemIndex = -1
            Archipelago.waitingForSync = true
        end

        imgui.new_line()
        imgui.text_colored(" Missing a starting Hip Pouch?", AP_REF.HexToImguiColor('09ba39'))
        imgui.text("    Click this button to receive")
        imgui.text("    a hip pouch!")

        imgui.text("  ")
        imgui.same_line()
        
        if imgui.button("Receive Hip Pouch") then
            GUI.AddText("Receiving Hip Pouch...")
            Archipelago.ReceiveItem("Hip Pouch", nil, 1)
        end

        imgui.new_line()
        imgui.separator()
    end

    imgui.new_line()
    imgui.text_colored(" Credits:", -10825765)
    imgui.text_colored("   @Solidus", AP_REF.HexToImguiColor('08c9b9')) -- AP_REF.HexToImguiColor('08c9b9')) -- AP_REF.HexToImguiColor('5f9de8'))
    imgui.same_line()
    imgui.text("(Main Dev)")
    imgui.text_colored("   @Fuzzy", AP_REF.HexToImguiColor('3e84d6'))
    imgui.same_line()
    imgui.text("(Original Dev)")
    imgui.text_colored("   @Silvris", AP_REF.HexToImguiColor('3e84d6'))
    imgui.same_line()
    imgui.text("(AP client lib)")
    imgui.text_colored("   @Johnny Hamcobbler", AP_REF.HexToImguiColor('3e84d6'))
    imgui.same_line()
    imgui.text("(testing/client)")
    imgui.text_colored("   @Distegro", AP_REF.HexToImguiColor('3e84d6'))
    imgui.same_line()
    imgui.text("(Locations Write-up)")
    imgui.text_colored("   @JustNU", AP_REF.HexToImguiColor('3e84d6'))
    imgui.same_line()
    imgui.text("(Various Fixes)")
    imgui.text_colored("   @Ropeyred", AP_REF.HexToImguiColor('3e84d6'))
    imgui.same_line()
    imgui.text("(Enemy Kills)")
    imgui.new_line()

    imgui.end_window()
end

return Tools