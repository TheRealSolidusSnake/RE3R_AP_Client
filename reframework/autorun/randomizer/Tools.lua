local Tools = {}

function Tools.ShowGUI()
    local scenario_text = '   (not connected)'
    local deathlink_text = '   (not connected)'
    local deathlink_color = AP_REF.HexToImguiColor('FFFFFF')
    
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
    end
    
    -- local player_character_text = "   (not in-game)"
    -- if Scene.isCharacterJill() then player_character_text = "   Jill" end
    -- if Scene.isCharacterCarlos() then player_character_text = "   Carlos" end

    imgui.set_next_window_size(Vector2f.new(185, 425), 0)
    imgui.begin_window("Archipelago Game Mod ", nil,
        8 -- NoScrollbar
    )

    imgui.text_colored("Mod Version Number: ", -10825765)
    imgui.text("   " .. tostring(Manifest.version))
    imgui.new_line()
    imgui.text_colored("AP Scenario & Difficulty:   ", -10825765)
    imgui.text(scenario_text)
    imgui.new_line()
    imgui.text_colored("DeathLink:   ", -10825765)
    imgui.text_colored(deathlink_text, deathlink_color)
    imgui.new_line()
    -- imgui.text_colored("Current Player Character:   ", -10825765)
    -- imgui.text(player_character_text)
    -- imgui.new_line()
    imgui.text_colored("Credits:", -10825765)
    imgui.text("@Solidus")
    imgui.text("   - Main campaign")
    imgui.text("@Fuzzy")
    imgui.text("   - Original dev")
    imgui.text("   - Goated with teh sauce")
    imgui.text("@Silvris")
    imgui.text("   - Client Dev")
    imgui.text("@Johnny Hamcobbler")
    imgui.text("   - Testing & Client Help")
    imgui.text("@DiStegro")
    imgui.text("   - Locations write-up")
    imgui.new_line()

    if Lookups.character and Lookups.scenario then
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