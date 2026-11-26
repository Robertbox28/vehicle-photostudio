local QBCore = exports['qb-core']:GetCoreObject()

local active, busy, cancel, hideUI = false, false, false, false
local mode = 'single'
local queue, queueIndex = {}, 1
local cam, veh = nil, nil
-- Alte Config mit Config.Presets weiter unterstützen
if not Config.Studios and Config.Presets then
    Config.Studios = {}
    for name, p in pairs(Config.Presets) do
        Config.Studios[#Config.Studios + 1] = { name = name, label = name, coords = p.coords, heading = p.heading, onGround = p.onGround, pitch = p.pitch }
    end
    Config.DefaultStudio = Config.DefaultStudio or Config.Preset
end

local studioIdx = 1
local studioLocked = false
local function studio() return Config.Studios[studioIdx] or Config.Studios[1] end
local function studioIndex(name)
    if not name then return nil end
    for i, s in ipairs(Config.Studios) do
        if s.name == name then return i end
    end
end
local function studioTime() return studio().time or Config.Time end
local function studioAllowed(i)
    local st = Config.Studios[i]
    if st.here and mode == 'player' and not (Config.PlayerStudio and Config.PlayerStudio.allowHere) then return false end
    local list = Config.PlayerStudio and Config.PlayerStudio.studios
    if mode ~= 'player' or list == nil then return true end
    for _, n in ipairs(list) do
        if st.name == n then return true end
    end
    return false
end
local function canSwitchStudio()
    if studioLocked or #Config.Studios < 2 then return false end
    local n = 0
    for i = 1, #Config.Studios do
        if studioAllowed(i) then n = n + 1 end
    end
    return n > 1 or (n == 1 and not studioAllowed(studioIdx))
end

-- "Aktueller Standort": Eintrag aus der Position des Spielers bauen
-- (wird bei jedem Öffnen neu gesetzt, steht am Ende von Config.Studios)
local function setupHereStudio()
    local H = Config.HereStudio
    if not H or not H.enabled then return end
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped) + GetEntityForwardVector(ped) * (H.forward or 0.0)
    local found, gz = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 2.0, false)
    local entry = {
        name        = H.name or 'hier',
        label       = H.label or 'Aktueller Standort',
        coords      = vector3(pos.x, pos.y, found and gz or (pos.z - 1.0)),
        heading     = (GetEntityHeading(ped) + (H.headingOffset or 0.0)) % 360.0,
        onGround    = true,
        here        = true,
        keepTime    = H.keepTime,
        keepWeather = H.keepWeather,
        suffix      = H.suffix,
    }
    local idx = studioIndex(entry.name)
    if idx then Config.Studios[idx] = entry else Config.Studios[#Config.Studios + 1] = entry end
end

local view = { angle = 1, yawOff = 0.0, pitchOff = 0.0, zoom = 1.0 }
local saved = {}
local capturePromise = nil
local lastResult = ''
local colorIdx, filterIdx = 1, Config.DefaultFilter or 1
local origColors = nil
local extraDelay = 0
local HQ = (Config.HighQuality and Config.HighQuality.enabled) and Config.HighQuality or {}
local function camFov() return HQ.fov or Config.FOV end
local lastCaptureAt = -100000

-- Einstellungen aus Config.VehicleOverrides für das aktuelle Fahrzeug
local function ov()
    local e = queue[queueIndex]
    return (e and Config.VehicleOverrides and Config.VehicleOverrides[e.model]) or {}
end

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function angleIndex(name)
    for i, a in ipairs(Config.Angles) do
        if a.name == name then return i end
    end
end

local function colorIndex(name)
    for i, c in ipairs(Config.Colors) do
        if c.name == name then return i end
    end
end

-- Farbe aus Override (fest) oder aktuelle Auswahl (G)
local function activeColorIdx()
    local forced = ov().color
    return (forced and colorIndex(forced)) or colorIdx
end

local function applyColor()
    if not veh or not DoesEntityExist(veh) then return end
    local c = Config.Colors[activeColorIdx()]
    SetVehicleModKit(veh, 0)

    if not c or c.original then
        ClearVehicleCustomPrimaryColour(veh)
        ClearVehicleCustomSecondaryColour(veh)
        if origColors then
            SetVehicleColours(veh, origColors[1], origColors[2])
            SetVehicleExtraColours(veh, origColors[3], origColors[4])
        end
        return
    end

    local paint = c.paint or 0
    SetVehicleModColor_1(veh, paint, 0, 0)
    SetVehicleModColor_2(veh, paint, 0)
    SetVehicleCustomPrimaryColour(veh, c.r, c.g, c.b)
    SetVehicleCustomSecondaryColour(veh, c.r2 or c.r, c.g2 or c.g, c.b2 or c.b)
end

local function applyFilter()
    local f = Config.Filters[filterIdx]
    if f and f.modifier then
        SetTimecycleModifier(f.modifier)
        SetTimecycleModifierStrength(f.strength or 1.0)
    else
        ClearTimecycleModifier()
    end
end

local function resetView(angle)
    view.angle = angle or view.angle
    view.yawOff, view.pitchOff, view.zoom = 0.0, 0.0, 1.0
end

local function drawTxt(x, y, scale, text)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextColour(255, 255, 255, 235)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function loadModel(hash)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return false end
    RequestModel(hash)
    local timeout = GetGameTimer() + (Config.ModelLoadTimeout or 8000)
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then return false end
        Wait(10)
    end
    return true
end

local function deleteVehicle()
    if veh and DoesEntityExist(veh) then DeleteEntity(veh) end
    veh = nil
end

local function spawnVehicle(model)
    deleteVehicle()
    local hash = joaat(model)
    if not loadModel(hash) then
        print(('[photostudio] Modell nicht gefunden: %s'):format(model))
        return false
    end

    local st = studio()
    local c = st.coords
    RequestCollisionAtCoord(c.x, c.y, c.z)
    veh = CreateVehicle(hash, c.x, c.y, c.z, st.heading or 0.0, false, false)
    SetModelAsNoLongerNeeded(hash)

    if st.onGround then
        local t = GetGameTimer() + 3000
        while not HasCollisionLoadedAroundEntity(veh) and GetGameTimer() < t do Wait(10) end
        SetVehicleOnGroundProperly(veh)
    end

    FreezeEntityPosition(veh, true)
    SetEntityInvincible(veh, true)
    if HQ.lodMultiplier then SetVehicleLodMultiplier(veh, HQ.lodMultiplier) end
    if HQ.perfectCar then
        SetVehicleFixed(veh)
        SetVehicleDeformationFixed(veh)
        SetVehicleEngineHealth(veh, 1000.0)
        SetVehicleBodyHealth(veh, 1000.0)
    end
    SetVehicleDirtLevel(veh, 0.0)
    WashDecalsFromVehicle(veh, 1.0)
    SetVehicleNumberPlateText(veh, Config.Plate)
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleLights(veh, 1)
    SetVehicleModKit(veh, 0)

    local entry = queue[queueIndex]

    if entry and entry.props then
        -- Persönliches Fahrzeug: Tuning, Lack, Felgen, Kennzeichen des Spielers
        QBCore.Functions.SetVehicleProperties(veh, entry.props)
        SetVehicleNumberPlateText(veh, entry.plate)
        SetVehicleDirtLevel(veh, 0.0)
        WashDecalsFromVehicle(veh, 1.0)
        SetVehicleFixed(veh)
    else
        -- Overrides für eigene Fahrzeuge
        local o = ov()
        if o.extras then
            for id, on in pairs(o.extras) do
                if DoesExtraExist(veh, id) then SetVehicleExtra(veh, id, not on) end -- true = deaktivieren
            end
        end
        if o.mods then
            for modType, idx in pairs(o.mods) do SetVehicleMod(veh, modType, idx, false) end
        end
        if o.livery then
            SetVehicleLivery(veh, o.livery)
            if GetNumVehicleMods(veh, 48) > 0 then SetVehicleMod(veh, 48, o.livery, false) end
        end
        if o.roofLivery then SetVehicleRoofLivery(veh, o.roofLivery) end
        if o.tint then SetVehicleWindowTint(veh, o.tint) end

        local p, s = GetVehicleColours(veh)
        local pe, wh = GetVehicleExtraColours(veh)
        origColors = { p, s, pe, wh }
        applyColor()
    end

    extraDelay = ((entry and (entry.custom or entry.props)) and (Config.CustomExtraDelay or 0) or 0) + (HQ.textureWait or 0)
    Wait(200)
    return true
end

local function updateCamera()
    if not veh or not DoesEntityExist(veh) then return end
    local a = Config.Angles[view.angle]
    local o = ov()
    local yaw = math.rad(a.yaw + view.yawOff + (o.yaw or 0.0))
    local pitch = math.rad((studio().pitch or a.pitch) + view.pitchOff + (o.pitch or 0.0))

    local mn, mx = GetModelDimensions(GetEntityModel(veh))
    local center = vector3((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, (mn.z + mx.z) / 2 + (o.height or 0.0))
    local radius = #(mx - mn) / 2
    local dist = (radius / math.sin(math.rad(camFov() / 2))) * Config.Padding * (a.zoom or 1.0) * view.zoom * (o.zoom or 1.0)

    local dir = vector3(math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    local camLocal = center + dir * dist
    local camPos = GetOffsetFromEntityInWorldCoords(veh, camLocal.x, camLocal.y, camLocal.z)
    local target = GetOffsetFromEntityInWorldCoords(veh, center.x, center.y, center.z)

    if not cam then
        cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0, camFov(), false, 0)
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, true)
    end
    SetCamCoord(cam, camPos.x, camPos.y, camPos.z)
    SetCamFov(cam, camFov())
    if HQ.dof then
        -- scharf vom vorderen bis zum hinteren Rand des Fahrzeugs, dahinter weich
        SetCamUseShallowDofMode(cam, true)
        SetCamNearDof(cam, math.max(0.1, dist - radius))
        SetCamFarDof(cam, dist + radius * 1.2)
        SetCamDofStrength(cam, HQ.dofStrength or 0.6)
    end
    PointCamAtCoord(cam, target.x, target.y, target.z)
    SetFocusPosAndVel(camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0)
end

local function currentEntry()
    return queue[queueIndex]
end

---------------------------------------------------------------------
-- Capture
---------------------------------------------------------------------
RegisterNetEvent('vps:client:captureDone', function(ok, file)
    lastResult = ok and ('Gespeichert: ' .. file) or ('Fehler bei: ' .. file)
    if capturePromise then
        capturePromise:resolve(ok)
        capturePromise = nil
    end
end)

local function capture(angleIdx)
    local entry = currentEntry()
    if not entry or not veh then return false end
    view.angle = angleIdx
    updateCamera()

    hideUI = true
    Wait(Config.CaptureDelay + extraDelay + (ov().delay or 0))
    extraDelay = 0 -- Extra-Wartezeit für Addon-Texturen nur vor dem ersten Foto

    -- Spieler-Modus: Server-Cooldown einhalten
    if mode == 'player' then
        local waitUntil = lastCaptureAt + ((Config.PlayerStudio.cooldown or 0) * 1000) + 100
        while GetGameTimer() < waitUntil do Wait(50) end
        lastCaptureAt = GetGameTimer()
    end

    local p = promise.new()
    capturePromise = p
    local color = nil
    if mode ~= 'player' then
        local cIdx = activeColorIdx()
        color = (cIdx ~= 1) and Config.Colors[cIdx].name or nil
    end
    TriggerServerEvent('vps:server:capture', entry.model, Config.Angles[angleIdx].name, color, entry.plate, studio().name)

    SetTimeout(45000, function()
        if capturePromise == p then
            capturePromise = nil
            p:resolve(false)
        end
    end)

    local ok = Citizen.Await(p)
    hideUI = false
    return ok
end

-- Spieler-Modus: nur die Winkel aus Config.PlayerStudio.angles
local function angleAllowed(i)
    if mode ~= 'player' then return true end
    for _, n in ipairs(Config.PlayerStudio.angles or {}) do
        if Config.Angles[i].name == n then return true end
    end
    return false
end

local function stepAngle(dir)
    local i = view.angle
    for _ = 1, #Config.Angles do
        i = (i - 1 + dir) % #Config.Angles + 1
        if angleAllowed(i) then break end
    end
    resetView(i)
end

local function captureAllAngles()
    local names = (mode == 'player') and (Config.PlayerStudio.angles or {}) or Config.BatchAngles
    for _, name in ipairs(names) do
        if cancel or not active then break end
        local idx = angleIndex(name)
        if idx then
            resetView(idx)
            capture(idx)
        end
    end
end

---------------------------------------------------------------------
-- Studio-Ort
---------------------------------------------------------------------
local function applyWeather()
    local st = studio()
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    if st.keepWeather and st.keepTime then
        -- echtes Wetter/Uhrzeit: Server-Sync wieder einschalten
        NetworkClearClockTimeOverride()
        TriggerEvent('qb-weathersync:client:EnableSync')
        return
    end
    TriggerEvent('qb-weathersync:client:DisableSync')
    if not st.keepWeather then
        local w = st.weather or Config.Weather
        SetWeatherTypeOvertimePersist(w, 0.0)
        SetWeatherTypeNowPersist(w)
        SetOverrideWeather(w)
    end
end

-- Spieler (unsichtbar) zum aktuellen Ort bringen und Umgebung laden lassen
local function moveToStudio()
    local c = studio().coords
    local ped = PlayerPedId()
    SetEntityCoords(ped, c.x, c.y, c.z + 25.0, false, false, false, false)
    FreezeEntityPosition(ped, true)
    SetFocusPosAndVel(c.x, c.y, c.z, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(c.x, c.y, c.z)
    if studio().here then
        ClearAreaOfVehicles(c.x, c.y, c.z, 8.0, false, false, false, false, false)
    else
        ClearAreaOfEverything(c.x, c.y, c.z, 60.0, false, false, false, false)
    end
    applyWeather()
    local t = GetGameTimer() + 2000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < t do Wait(10) end
    Wait(300)
end

local function switchStudio(dir)
    local n = #Config.Studios
    local i = studioIdx
    for _ = 1, n do
        i = (i - 1 + dir) % n + 1
        if studioAllowed(i) then break end
    end
    if i == studioIdx then busy = false return end

    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Wait(10) end
    deleteVehicle()
    studioIdx = i
    moveToStudio()
    if spawnVehicle(currentEntry().model) then updateCamera() end
    DoScreenFadeIn(300)
    lastResult = 'Ort: ' .. (studio().label or studio().name)
    busy = false
end

---------------------------------------------------------------------
-- Studio betreten / verlassen
---------------------------------------------------------------------
local function exitStudio()
    if not active then return end
    active = false
    if VPS_IsGalleryOpen and VPS_IsGalleryOpen() then VPS_CloseGallery() end
    DoScreenFadeOut(300)
    while not IsScreenFadedOut() do Wait(10) end

    deleteVehicle()
    if cam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(cam, false)
        cam = nil
    end
    ClearFocus()
    ClearTimecycleModifier()

    local ped = PlayerPedId()
    SetEntityCoords(ped, saved.coords.x, saved.coords.y, saved.coords.z, false, false, false, false)
    SetEntityHeading(ped, saved.heading)
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    DisplayRadar(true)

    ClearOverrideWeather()
    ClearWeatherTypePersist()
    TriggerEvent('qb-weathersync:client:EnableSync')
    Config.OnExit()

    TriggerServerEvent('vps:server:exit')
    DoScreenFadeIn(500)
    QBCore.Functions.Notify('Fotostudio verlassen. ' .. lastResult, 'success')
end

local function drawHelp()
    local entry = currentEntry()
    local a = Config.Angles[view.angle]
    local title = entry and ('%s %s (%s)%s  [%d/%d]'):format(entry.brand or '', entry.name or entry.model,
        entry.plate or entry.model, entry.custom and ' ~g~[eigen]~s~' or '', queueIndex, #queue) or '-'

    local place = studio().label or studio().name
    local bHint = canSwitchStudio() and '~y~B~s~ Ort   ' or ''

    drawTxt(0.015, 0.64, 0.45, '~b~Vehicle Photo Studio~s~  ' .. title)
    if mode == 'batch' then
        drawTxt(0.015, 0.675, 0.38, ('Ort: ~y~%s~s~   Serienaufnahme läuft …  ~y~BACKSPACE~s~ abbrechen'):format(place))
    elseif mode == 'player' then
        local fil = Config.Filters[filterIdx]
        drawTxt(0.015, 0.675, 0.38, ('Ort: ~y~%s~s~   Winkel: ~y~%s~s~   Filter: ~y~%s~s~   Zoom: %.2f')
            :format(place, a.label, fil and fil.label or '-', view.zoom))
        drawTxt(0.015, 0.70, 0.34, '~y~←/→~s~ Winkel   ~y~↑/↓~s~ Zoom   ~y~Q/E~s~ drehen   ~y~R/F~s~ Höhe   ~y~X~s~ Reset')
        drawTxt(0.015, 0.722, 0.34, bHint .. (Config.PlayerStudio.filters and '~y~H~s~ Filter   ' or '') .. '~y~Bild↑/Bild↓~s~ Fahrzeug wechseln')
        drawTxt(0.015, 0.744, 0.34, '~y~ENTER~s~ Foto   ~y~LEERTASTE~s~ alle Winkel   ~y~TAB~s~ Meine Fotos   ~y~BACKSPACE~s~ Beenden')
    else
        local col = Config.Colors[activeColorIdx()]
        local fil = Config.Filters[filterIdx]
        drawTxt(0.015, 0.675, 0.38, ('Ort: ~y~%s~s~   Winkel: ~y~%s~s~   Farbe: ~y~%s~s~   Filter: ~y~%s~s~   Zoom: %.2f')
            :format(place, a.label, col and col.label or '-', fil and fil.label or '-', view.zoom))
        drawTxt(0.015, 0.70, 0.34, '~y~←/→~s~ Winkel   ~y~↑/↓~s~ Zoom   ~y~Q/E~s~ drehen   ~y~R/F~s~ Höhe   ~y~X~s~ Reset')
        drawTxt(0.015, 0.722, 0.34, bHint .. '~y~G~s~ Farbe   ~y~H~s~ Filter   (mit ~y~SHIFT~s~ rückwärts)   ~y~Bild↑/Bild↓~s~ Fahrzeug')
        drawTxt(0.015, 0.744, 0.34, '~y~ENTER~s~ Foto   ~y~LEERTASTE~s~ alle Winkel   ~y~TAB~s~ Galerie   ~y~BACKSPACE~s~ Beenden')
    end
    if lastResult ~= '' then drawTxt(0.015, 0.770, 0.32, '~g~' .. lastResult) end
end

local function frameLoop()
    CreateThread(function()
        while active do
            HideHudAndRadarThisFrame()
            if HQ.hideFeed then ThefeedHideThisFrame() end
            if HQ.lodScale then OverrideLodscaleThisFrame(HQ.lodScale) end
            if HQ.dof then SetUseHiDof() end
            DisableAllControlActions(0)
            SetVehicleDensityMultiplierThisFrame(0.0)
            SetPedDensityMultiplierThisFrame(0.0)
            SetRandomVehicleDensityMultiplierThisFrame(0.0)
            SetParkedVehicleDensityMultiplierThisFrame(0.0)
            if not studio().keepTime then
                local t = studioTime()
                NetworkOverrideClockTime(t.hour, t.minute or 0, 0)
            end

            local gOpen = VPS_IsGalleryOpen and VPS_IsGalleryOpen()
            if not hideUI and not gOpen then drawHelp() end

            if not gOpen and IsDisabledControlJustPressed(0, 194) then -- Backspace
                if mode == 'batch' then
                    cancel = true
                elseif not busy then
                    exitStudio()
                end
            end

            if (mode == 'single' or mode == 'player') and not busy and active and not gOpen then
                local ft = GetFrameTime()
                local changed = false

                if IsDisabledControlJustPressed(0, 175) then stepAngle(1); changed = true end
                if IsDisabledControlJustPressed(0, 174) then stepAngle(-1); changed = true end
                if IsDisabledControlPressed(0, 172) then view.zoom = math.max(0.4, view.zoom - ft * 0.6); changed = true end
                if IsDisabledControlPressed(0, 173) then view.zoom = math.min(2.5, view.zoom + ft * 0.6); changed = true end
                if IsDisabledControlPressed(0, 44)  then view.yawOff = view.yawOff - ft * 40.0; changed = true end
                if IsDisabledControlPressed(0, 38)  then view.yawOff = view.yawOff + ft * 40.0; changed = true end
                if IsDisabledControlPressed(0, 45)  then view.pitchOff = math.min(60.0, view.pitchOff + ft * 20.0); changed = true end
                if IsDisabledControlPressed(0, 23)  then view.pitchOff = math.max(-30.0, view.pitchOff - ft * 20.0); changed = true end
                if IsDisabledControlJustPressed(0, 73) then resetView(); changed = true end

                if changed then updateCamera() end

                local dir = IsDisabledControlPressed(0, 21) and -1 or 1 -- SHIFT = rückwärts
                if mode ~= 'player' and IsDisabledControlJustPressed(0, 47) then -- G (nicht bei Spielerautos)
                    colorIdx = (colorIdx - 1 + dir) % #Config.Colors + 1
                    applyColor()
                end
                if (mode ~= 'player' or Config.PlayerStudio.filters) and IsDisabledControlJustPressed(0, 74) then -- H
                    filterIdx = (filterIdx - 1 + dir) % #Config.Filters + 1
                    applyFilter()
                end

                if IsDisabledControlJustPressed(0, 37) and Config.Gallery and Config.Gallery.studioKey and VPS_OpenGallery then -- TAB = Galerie
                    VPS_OpenGallery(mode == 'player' and 'player' or 'catalog')
                end

                if IsDisabledControlJustPressed(0, 29) and canSwitchStudio() then -- B = Ort wechseln
                    busy = true
                    CreateThread(function() switchStudio(dir) end)
                end

                local step = IsDisabledControlJustPressed(0, 10) and -1 or (IsDisabledControlJustPressed(0, 11) and 1 or 0)
                if step ~= 0 then
                    busy = true
                    CreateThread(function()
                        queueIndex = (queueIndex - 1 + step) % #queue + 1
                        if spawnVehicle(currentEntry().model) then updateCamera() end
                        busy = false
                    end)
                end

                if IsDisabledControlJustPressed(0, 191) then -- Enter
                    busy = true
                    CreateThread(function() capture(view.angle); busy = false end)
                elseif IsDisabledControlJustPressed(0, 22) then -- Space
                    busy = true
                    CreateThread(function()
                        local keep = view.angle
                        captureAllAngles()
                        resetView(keep); updateCamera()
                        busy = false
                    end)
                end
            end

            Wait(0)
        end
    end)
end

local function runBatch()
    busy, cancel = true, false
    local done, failed = 0, {}
    for i = queueIndex, #queue do
        if cancel or not active then break end
        queueIndex = i
        if spawnVehicle(queue[i].model) then
            if #Config.BatchColors > 0 then
                for _, cname in ipairs(Config.BatchColors) do
                    if cancel or not active then break end
                    colorIdx = colorIndex(cname) or 1
                    applyColor()
                    Wait(150)
                    captureAllAngles()
                end
            else
                captureAllAngles()
            end
            done = done + 1
        else
            failed[#failed + 1] = queue[i].model
        end
    end
    busy = false
    lastResult = ('%d Fahrzeuge fotografiert%s'):format(done, cancel and ' (abgebrochen)' or '')
    if #failed > 0 then print('[photostudio] Fehlgeschlagen: ' .. table.concat(failed, ', ')) end
    exitStudio()
end

RegisterNetEvent('vps:client:open', function(newMode, list, startModel, opts)
    if active then return end
    mode, queue, queueIndex = newMode, list, 1
    opts = opts or {}
    studioLocked = opts.lock == true
    setupHereStudio()
    studioIdx = studioIndex(opts.studio) or studioIndex(Config.DefaultStudio) or 1
    if not studioAllowed(studioIdx) then studioIdx = studioIndex(Config.DefaultStudio) or 1 end
    if startModel then
        for i, e in ipairs(queue) do
            if e.model == startModel then queueIndex = i break end
        end
    end
    active, busy, cancel, hideUI, lastResult = true, false, false, false, ''
    colorIdx, filterIdx = 1, Config.DefaultFilter or 1
    if mode == 'player' and not Config.PlayerStudio.filters then filterIdx = 1 end
    resetView(angleIndex(Config.MainAngle) or 1)
    if not angleAllowed(view.angle) then stepAngle(1) end
    applyFilter()

    DoScreenFadeOut(300)
    while not IsScreenFadedOut() do Wait(10) end

    local ped = PlayerPedId()
    saved.coords, saved.heading = GetEntityCoords(ped), GetEntityHeading(ped)
    Config.OnEnter()

    DisplayRadar(false)

    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)
    moveToStudio()
    Wait(200)

    frameLoop()

    if spawnVehicle(currentEntry().model) then updateCamera() end
    DoScreenFadeIn(500)

    if mode == 'batch' then CreateThread(runBatch) end
end)

-- Hilfsbefehl: fertige Zeile für Config.Studios ausgeben (F8)
-- Z-Wert ist die Fußhöhe minus 1 m = ungefähr der Boden
RegisterCommand('vpspos', function()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local msg = ("{ name = 'neu', label = 'Neuer Ort', coords = vector3(%.2f, %.2f, %.2f), heading = %.1f, onGround = true },")
        :format(c.x, c.y, c.z - 1.0, GetEntityHeading(ped))
    print(msg)
    QBCore.Functions.Notify('Zeile für Config.Studios in der F8-Konsole', 'primary')
end, false)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and active then
        cancel = true
        exitStudio()
    end
end)

function VPS_IsStudioActive() return active end

---------------------------------------------------------------------
-- Galerie (NUI)
---------------------------------------------------------------------
local galleryOpen = false

function VPS_IsGalleryOpen() return galleryOpen end

local function openGallery(kind)
    if galleryOpen or not (Config.Gallery and Config.Gallery.enabled) then return end
    QBCore.Functions.TriggerCallback('vps:gallery:get', function(data)
        if not data then
            return QBCore.Functions.Notify('Keine Berechtigung für diese Galerie.', 'error')
        end
        galleryOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({
            action     = 'open',
            kind       = data.kind,
            items      = data.items,
            canDelete  = data.canDelete,
            inStudio   = active,
            mainAngle  = Config.MainAngle,
        })
    end, kind)
end

local function closeGallery()
    galleryOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNUICallback('close', function(_, cb)
    galleryOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

-- Lokale Katalogbilder kommen vom Server (latent, weil groß)
RegisterNUICallback('image', function(data, cb)
    TriggerServerEvent('vps:gallery:reqImage', data.reqId, data.file)
    cb('ok')
end)

RegisterNetEvent('vps:gallery:image', function(reqId, dataUri)
    SendNUIMessage({ action = 'image', reqId = reqId, src = dataUri or nil })
end)

RegisterNUICallback('delete', function(data, cb)
    QBCore.Functions.TriggerCallback('vps:gallery:delete', function(ok)
        cb({ ok = ok == true })
    end, data)
end)

-- Aus dem Katalog direkt ins Studio (nur ausserhalb des Studios)
RegisterNUICallback('photograph', function(data, cb)
    cb('ok')
    closeGallery()
    if not active and type(data.model) == 'string' and data.model:match('^[%w_%-]+$') then
        ExecuteCommand('photostudio ' .. data.model)
    end
end)

if Config.Gallery and Config.Gallery.enabled then
    RegisterCommand(Config.Gallery.playerCommand or 'meinefotos', function()
        openGallery('player')
    end, false)
    RegisterCommand(Config.Gallery.adminCommand or 'fotokatalog', function()
        openGallery('catalog')
    end, false)

    CreateThread(function()
        Wait(2000)
        TriggerEvent('chat:addSuggestion', '/' .. (Config.Gallery.playerCommand or 'meinefotos'), 'Fotos deiner Fahrzeuge ansehen')
        TriggerEvent('chat:addSuggestion', '/' .. (Config.Gallery.adminCommand or 'fotokatalog'), 'Fahrzeugkatalog-Bilder ansehen (Admin)')
    end)
end

VPS_OpenGallery = openGallery
VPS_CloseGallery = closeGallery
