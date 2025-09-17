local Tools = {}

function Tools.ShowGUI()
    local scenario_text = '   (not connected)'
    local deathlink_text = '   (not connected)'
    local deathlink_color = AP_REF.HexToImguiColor('FFFFFF')
    local version_text = '   ' .. tostring(Manifest.version)
    local version_mismatch = false

    -- if the lookups contain data, then we're connected, so do everything that needs connection
    if Lookups.character and Lookups.scenario then
        scenario_text = "   " .. Lookups.character:gsub("^%l", string.upper) .. " " .. string.upper(Lookups.scenario) .. 
            " - " .. Lookups.difficulty:gsub("^%l", string.upper)

        if Archipelago.death_link then
            deathlink_text = "   On"
            deathlink_color = AP_REF.HexToImguiColor('fa3d2f')
        else
            deathlink_text = "   Off"
            deathlink_color = AP_REF.HexToImguiColor('777777')
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

    imgui.set_next_window_size(Vector2f.new(200, 715), 0)
    imgui.begin_window("Archipelago Game Mod ", nil,
        8 -- NoScrollbar
    )

    imgui.text_colored("Mod Version Number: ", -10825765)
    
    if version_mismatch then
        imgui.text_colored(version_text, AP_REF.HexToImguiColor('fa3d2f'))
    else
        imgui.text(version_text)
    end

    imgui.new_line()
    imgui.text_colored("AP Scenario & Difficulty:   ", -10825765)
    imgui.text(scenario_text)
    imgui.new_line()
    imgui.text_colored("DeathLink:   ", -10825765)
    imgui.text_colored(deathlink_text, deathlink_color)
    imgui.new_line()

    imgui.separator()
    imgui.text(" The default keyboard key to")
    imgui.text(" show or hide these windows is")
    imgui.text(" INSERT.")
    imgui.separator()

    imgui.new_line()
    imgui.text_colored("Credits:", -10825765)
    imgui.text("@Solidus")
    imgui.text("   - Main campaign")
    imgui.text("@Fuzzy")
    imgui.text("   - Original Dev")
    imgui.text("   - Goated With Teh Sauce")
    imgui.text("@Silvris")
    imgui.text("   - Client Dev")
    imgui.text("@Johnny Hamcobbler")
    imgui.text("   - Testing & Client Help")
    imgui.text("@DiStegro")
    imgui.text("   - Locations Write-up")
    imgui.text("@JustNU")
    imgui.text("   - Various Fixes")
    imgui.new_line()

    if Lookups.character and Lookups.scenario then
        imgui.text_colored("Clock Puzzle Broken?", -10825765)
        imgui.text("Click this button to fix")
        imgui.text(" the puzzle door!")

        if imgui.button("Fix Clock Puzzle") then
            GUI.AddText("Fixing Clock Puzzle...")
            CutsceneObjects.ClockPuzzle()
        end

        imgui.new_line()
        imgui.text_colored("Missing a starting Pouch?", -10825765)
        imgui.text("Click this button to receive")
        imgui.text(" a hip pouch!")

        if imgui.button("Receive Hip Pouch") then
            GUI.AddText("Receiving Hip Pouch...")
            Archipelago.ReceiveItem("Hip Pouch", nil, 1)
        end

        imgui.new_line()
        imgui.text_colored("Missing Items?", -10825765)
        imgui.text("If you were sent items at the ")
        imgui.text("start and didn't receive them,")
        imgui.text("click this button.")

        if imgui.button("Receive Items Again") then
            Storage.lastReceivedItemIndex = -1
            Storage.lastSavedItemIndex = -1
            Archipelago.waitingForSync = true
        end

    end

    imgui.end_window()
end

return Tools