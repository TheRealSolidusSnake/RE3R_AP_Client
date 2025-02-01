local GUI = {}
GUI.textList = {}
GUI.lastText = os.time()
GUI.logo = nil
GUI.font = "Prompt-Medium.ttf"
GUI.font_size = 24

function GUI.CheckForAndDisplayMessages()
    if next(GUI.textList) == nil then
        return
    end

    -- if the last text addition was X time ago or more, clear the text
    if os.time() - GUI.lastText > 15 then -- 15 seconds
        GUI.textList = {} -- clear all the messages
    end

    imgui.set_next_window_pos({ 50, 50})
    imgui.begin_window("Archipelago", nil,
        1 -- NoTitleBar
        | 2 -- NoResize
        | 4 -- NoMove
        | 8 -- NoScrollbar
        | 64 -- AlwaysAutoResize
        | 128 -- NoBackground
    )
    -- ImGui Window Flags (3rd arg) reference here: https://oprypin.github.io/crystal-imgui/ImGui/ImGuiWindowFlags.html
    
    local font = imgui.load_font(GUI.font, GUI.font_size)

    if (font ~= nil) then
        imgui.push_font(font)
    end

    imgui.push_style_var(14, Vector2f.new(0,0)) -- text padding

    for k, textArray in pairs(GUI.textList) do
        for k2, textItem in pairs(textArray) do
            if textItem.message ~= nil then
                if textItem.color then
                    imgui.text_colored(textItem.message, textItem.color)    
                else
                    imgui.text(textItem.message)
                end
            end

            imgui.same_line()
        end

        imgui.new_line()
    end

    imgui.pop_style_var(1)
    imgui.pop_font()
    imgui.end_window()
    imgui.end_window()
end

function GUI.AddText(message, color)
    local textObject = {}
    textObject.message = message
    
    -- convert legacy colors to a system yellow
    if color ~= nil and color ~= "" then
        textObject.color = AP_REF.HexToImguiColor("d9d904")
    end
        
    table.insert(GUI.textList, {textObject})
    GUI.lastText = os.time()
end

function GUI.AddTexts(textObjects)
    for k, textObject in pairs(textObjects) do   
        -- convert legacy colors to a system yellow
        if textObject.color == "green" then
            textObject.color = AP_REF.HexToImguiColor("d9d904")
        end
    end

    table.insert(GUI.textList, textObjects)
    GUI.lastText = os.time()
end

-- receiving item from self or another player
function GUI.AddReceivedItemText(item_name, item_color, sendingPlayer, selfPlayer, sentToBox)
    local textObjects = {}

    if sendingPlayer == selfPlayer then
        table.insert(textObjects, { message="Found your " })
    else
        table.insert(textObjects, { message="Received " })
    end
    
    table.insert(textObjects, { message=item_name, color=AP_REF.HexToImguiColor(item_color) })
    
    if sendingPlayer and sendingPlayer ~= selfPlayer then
        table.insert(textObjects, { message=" from " .. sendingPlayer })
    end

    if sentToBox then
        table.insert(textObjects, { message=". Sent to item box!" })
    else
        table.insert(textObjects, { message="!" })
    end

    GUI.AddTexts(textObjects)
end

-- sending item to another player
function GUI.AddSentItemText(player_sender, item_name, item_color, player_receiver, location)
    GUI.AddTexts({
        { message=player_sender .. " sent " },
        { message=item_name, color=AP_REF.HexToImguiColor(item_color) },
        { message=" to " .. player_receiver .. "!" }
    })
end

function GUI.ClearText()
    GUI.textList = {}
end

return GUI
