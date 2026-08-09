-- DeathLink send/receive + YAML / difficulty gating.

Archipelago.death_link = Archipelago.death_link or false
Archipelago.canDeathLink = Archipelago.canDeathLink or false
Archipelago.wasDeathLinked = Archipelago.wasDeathLinked or false
Archipelago.deathLinkTagActive = Archipelago.deathLinkTagActive or false
Archipelago.didWarnDeathLinkLocked = Archipelago.didWarnDeathLinkLocked or false
Archipelago.lastDeathLinkDiffCheck = Archipelago.lastDeathLinkDiffCheck

function Archipelago.CanBeKilled()
    -- Wait until the player is in game, with AP connected, before killing from DeathLink.
    return Scene.isInGame() and Archipelago.IsConnected()
end

-- DeathLink only runs if the YAML enables it AND the player has already beaten
-- the difficulty they're currently using (vanilla clear for that difficulty).
-- Stole the idea from Fuzzy — don't want Inferno DeathLink before vanilla Inferno.
function Archipelago.IsDeathLinkActive()
    if not Archipelago.death_link then
        return false
    end
    return Records.hasClearedDeathLinkDifficulty()
end

function Archipelago.UpdateDeathLinkTag(force)
    if not Archipelago.IsConnected() or AP_REF.APClient == nil then
        return
    end

    local shouldHaveTag = Archipelago.IsDeathLinkActive()
    if not force and shouldHaveTag == Archipelago.deathLinkTagActive then
        Archipelago.WarnDeathLinkLocked()
        return
    end

    local tags = { "Lua-APClientPP" }
    if AP_REF.APGameName == "" then
        table.insert(tags, "TextOnly")
    end
    if AP_REF.APTags ~= nil then
        for _, val in ipairs(AP_REF.APTags) do
            table.insert(tags, val)
        end
    end
    if shouldHaveTag then
        table.insert(tags, "DeathLink")
    end

    local ok = pcall(function()
        AP_REF.APClient:ConnectUpdate(nil, tags)
    end)
    if ok then
        Archipelago.deathLinkTagActive = shouldHaveTag
    end

    Archipelago.WarnDeathLinkLocked()
end

function Archipelago.WarnDeathLinkLocked()
    if Archipelago.didWarnDeathLinkLocked then
        return
    end
    if not Archipelago.death_link or Archipelago.IsDeathLinkActive() then
        return
    end

    local diffId = Records.getDeathLinkDifficultyId()
    local diffName = Records.DifficultyIdToName(diffId) or Lookups.difficulty or "this difficulty"
    diffName = tostring(diffName):gsub("^%l", string.upper)

    GUI.AddTexts({
        { message = "DeathLink locked: ", color = AP_REF.HexToImguiColor("fa3d2f") },
        { message = "beat " },
        { message = diffName, color = AP_REF.HexToImguiColor("d9d904") },
        { message = " once (vanilla) to enable it on this difficulty." },
    })
    Archipelago.didWarnDeathLinkLocked = true
end

function Archipelago.SendDeathLink()
    if not Archipelago.IsDeathLinkActive() then
        return
    end

    local player_self = Archipelago.GetPlayer()
    local timeOfDeath = math.floor(AP_REF.APClient:get_server_time())
    local playerName = tostring(player_self.alias)

    local deathLinkData = {
        time = timeOfDeath,
        cause = playerName .. " died.",
        source = playerName,
    }

    AP_REF.APClient:Bounce(deathLinkData, nil, nil, { "DeathLink" }) -- data, games, slots, tags
end

function Archipelago.BouncedHandler(json_rows)
    -- {
    --  "data" : {
    --      "source": "FuzzyLTTP",
    --      "cause": "FuzzyLTTP ran out of hearts.",
    --      "time": 346345764357
    --  },
    --  "cmd": "Bounced"
    --  "tags": { "DeathLink" }
    -- }

    if not Archipelago.IsDeathLinkActive() then
        return
    end

    if json_rows ~= nil and json_rows["tags"] ~= nil then
        for _, tag in pairs(json_rows["tags"]) do
            if tag == "DeathLink" then
                if Archipelago.CanBeKilled() then
                    if json_rows["data"]["cause"] then
                        GUI.AddTexts({
                            { message = "Deathlink received: " },
                            { message = tostring(json_rows["data"]["cause"]), color = "green" },
                        })
                    else
                        GUI.AddTexts({
                            { message = "Deathlink received from: " },
                            { message = tostring(json_rows["data"]["source"]), color = "green" },
                        })
                    end

                    Archipelago.wasDeathLinked = true
                    Player.Kill()
                end

                break
            end
        end
    end
end

function Archipelago.ResetDeathLinkState()
    Archipelago.death_link = false
    Archipelago.deathLinkTagActive = false
    Archipelago.didWarnDeathLinkLocked = false
    Archipelago.lastDeathLinkDiffCheck = nil
    Archipelago.canDeathLink = false
    Archipelago.wasDeathLinked = false
end

local function APBouncedHandler(json_rows)
    return Archipelago.BouncedHandler(json_rows)
end
AP_REF.on_bounced = APBouncedHandler

return true
