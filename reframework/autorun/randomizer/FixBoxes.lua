local FixBoxes = {}
FixBoxes.isInit = false
FixBoxes.lastFix = os.time()

function FixBoxes.Init()
    if Archipelago.IsConnected() and not FixBoxes.isInit then
        FixBoxes.isInit = true
        FixBoxes.FixAll()
    end

    -- if the last check for objects to remove was X time ago or more, trigger another removal
    if os.time() - FixBoxes.lastFix > 15 then -- 15 seconds
        FixBoxes.isInit = false
    end
end

-- Function to force breakable boxes to send properly (FINALLY!)
function FixBoxes.Finally(boxName)
    local boxObject = Helpers.gameObject(boxName)

    if boxObject == nil then
        return
    end

    local boxComponent = Helpers.component(boxObject, "escape.gimmick.action.EsGimmickRandomContainer")
    if boxComponent ~= nil then
        boxComponent:set_field("fixItem", true)
    end
end

function FixBoxes.FixAll()
    FixBoxes.Finally("st03_0219_sm42_476_ES_BreakBox01_gimmick") -- South Side Breakable Box (Downtown)
    FixBoxes.Finally("st03_0216_sm42_476_ES_BreakBox06_gimmick") -- North Side Breakable Box (Downtown)
    FixBoxes.Finally("st03_0213_sm42_476_ES_BreakBox05_gimmick") -- Rooftop Breakable Box (Downtown)
    FixBoxes.Finally("st03_0226_sm42_476_ES_BreakBox10_gimmick") -- Substation Street Breakable Box (Downtown)
    FixBoxes.Finally("st03_0402_sm42_476_ES_BreakBox12_gimmick") -- Before Power Maze Breakable Box (Downtown)
    FixBoxes.Finally("st03_0611_sm42_476_ES_BreakBox16_gimmick") -- Northwest Tunnel Breakable Box (Sewers)
    FixBoxes.Finally("st02_0217_sm42_476_ES_BreakableVLongBox01A_00_gimmick") -- West Hallway 1F Breakable Box (RPD)
    FixBoxes.Finally("st02_603_sm42_476_ES_BreakableVLongBox0A_00_gimmick") -- West Hallway 3F Breakable Box (RPD)
    FixBoxes.Finally("st03_0804_sm42_476_ES_BreakableVLongBox01A_gimmick") -- Promenade Breakable Box (RPD)
    FixBoxes.Finally("St04_0107_0_ES_BreakBox10") -- Breakable Box Near Operating Room (Hospital)
    FixBoxes.Finally("St04_0107_0_ES_BreakBox10_01") -- Breakable Box Near Locker (Hospital)
    FixBoxes.Finally("sm42_476_Break_box_Lobby1") -- Breakable Box Near Makeshift Sickroom as Jill (Hospital)
    FixBoxes.Finally("sm42_476_Break_box_Lobby2") -- Breakable Box Near Makeshift Sickroom as Jill (Hospital)
    FixBoxes.Finally("sm42_476_Break Box 1") -- Breakable Box Before Underground Storage as Jill (Hospital)
    FixBoxes.Finally("sm42_476_Break Box 10") -- Breakable Box Inside Underground Storage as Jill (Hospital)
    FixBoxes.Finally("sm42_476_Break Box 20") -- Breakable Box Inside Underground Storage as Jill (Hospital)
    FixBoxes.Finally("st05_0104_sm42_476_ES_BreakableVLongBox01A_00_gimmick") -- Laboratory Hallway 2F Box (NEST)
    FixBoxes.Finally("st05_0202_sm42_476_ES_BreakableVLongBox01A_00_gimmick") -- Worker's Break Room Box (NEST)
end

return FixBoxes