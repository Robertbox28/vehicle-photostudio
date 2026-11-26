-- Feste Orte: Kartensymbol, NPC/Marker und Menü (Fotostudio / Galerie)
local QBCore = exports['qb-core']:GetCoreObject()
local P = Config.Points or {}
local LOCS = (Config.PlayerStudio and Config.PlayerStudio.locations) or {}

local blips, peds = {}, {}
local menuOpen = false
local useTarget = false

---------------------------------------------------------------------
-- Menü
---------------------------------------------------------------------
local function openMenu(i)
    local loc = LOCS[i]
    if not loc or menuOpen then return end
    if VPS_IsStudioActive and VPS_IsStudioActive() then return end
    if VPS_IsGalleryOpen and VPS_IsGalleryOpen() then return end

    QBCore.Functions.TriggerCallback('vps:points:info', function(info)
        info = info or {}
        local m = loc.menu or { studio = true, gallery = true, admin = true }
        local items = {}

        if m.studio ~= false and info.playerStudio then
            local price = (info.price or 0) > 0 and ('Kosten: $' .. info.price) or 'Kostenlos'
            items[#items + 1] = { id = 'studio', label = 'Fahrzeug fotografieren', desc = 'Eines deiner Fahrzeuge ins Studio holen · ' .. price }
        end
        if m.gallery ~= false and info.gallery then
            items[#items + 1] = { id = 'gallery', label = 'Meine Fotos', desc = 'Alle Fotos deiner Fahrzeuge ansehen' }
        end
        if m.admin ~= false and info.admin then
            items[#items + 1] = { id = 'adminStudio', label = 'Katalog-Studio', desc = 'Katalogbilder aufnehmen (Admin)', admin = true }
            if info.gallery then
                items[#items + 1] = { id = 'catalog', label = 'Fahrzeugkatalog', desc = 'Alle Katalogbilder und fehlende Fotos (Admin)', admin = true }
            end
        end
        if #items == 0 then
            return QBCore.Functions.Notify('Hier ist gerade nichts verfügbar.', 'error')
        end

        menuOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'menu', loc = i, title = loc.label or 'Fotostudio', items = items })
    end)
end

RegisterNUICallback('menuSelect', function(data, cb)
    cb('ok')
    menuOpen = false
    SetNuiFocus(false, false)
    local loc = LOCS[tonumber(data.loc) or 0]
    local id = data.id

    if id == 'studio' then
        TriggerServerEvent('vehicle-photostudio:server:openPlayer')
    elseif id == 'gallery' and VPS_OpenGallery then
        VPS_OpenGallery('player')
    elseif id == 'adminStudio' then
        local st = loc and loc.studio
        ExecuteCommand('photostudio' .. (st and (' ' .. st) or ''))
    elseif id == 'catalog' and VPS_OpenGallery then
        VPS_OpenGallery('catalog')
    end
end)

RegisterNUICallback('menuClose', function(_, cb)
    menuOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNetEvent('vps:client:pointMenu', function(data)
    openMenu(data and data.locIndex)
end)

---------------------------------------------------------------------
-- Blips, NPCs, qb-target
---------------------------------------------------------------------
local function spawnPed(i, loc)
    local hash = joaat(loc.ped)
    if not IsModelInCdimage(hash) then
        return print(('[photostudio] NPC-Modell nicht gefunden: %s'):format(loc.ped))
    end
    RequestModel(hash)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(10) end
    local c = loc.coords
    local ped = CreatePed(4, hash, c.x, c.y, c.z - 1.0, loc.heading or 0.0, false, true)
    SetModelAsNoLongerNeeded(hash)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_PAPARAZZI', 0, true)
    peds[i] = ped
    return ped
end

local function targetOptions(i, loc)
    return {
        options = { {
            type = 'client', event = 'vps:client:pointMenu', icon = 'fas fa-camera',
            label = loc.label or 'Fotostudio', locIndex = i,
        } },
        distance = P.distance or 2.0,
    }
end

CreateThread(function()
    Wait(1000)
    local tname = P.targetName or 'qb-target'
    useTarget = P.useTarget ~= false and GetResourceState(tname) == 'started'

    for i, loc in ipairs(LOCS) do
        if loc.blip ~= false then
            local b = loc.blip or {}
            local blip = AddBlipForCoord(loc.coords.x, loc.coords.y, loc.coords.z)
            SetBlipSprite(blip, b.sprite or 225)
            SetBlipColour(blip, b.color or 3)
            SetBlipScale(blip, b.scale or 0.7)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(loc.label or 'Fotostudio')
            EndTextCommandSetBlipName(blip)
            blips[#blips + 1] = blip
        end

        local ped = loc.ped and spawnPed(i, loc)
        if useTarget then
            if ped then
                exports[tname]:AddTargetEntity(ped, targetOptions(i, loc))
            else
                exports[tname]:AddCircleZone('vps_point_' .. i, loc.coords, 1.2,
                    { name = 'vps_point_' .. i, debugPoly = false, useZ = true }, targetOptions(i, loc))
            end
        end
    end
end)

---------------------------------------------------------------------
-- Ohne qb-target: Marker + E
---------------------------------------------------------------------
CreateThread(function()
    Wait(1500)
    if useTarget or #LOCS == 0 then return end
    local mc = P.markerColor or { r = 110, g = 155, b = 255, a = 150 }
    while true do
        local sleep = 1000
        local studioActive = VPS_IsStudioActive and VPS_IsStudioActive()
        if not studioActive and not menuOpen then
            local pos = GetEntityCoords(PlayerPedId())
            for i, loc in ipairs(LOCS) do
                local d = #(pos - loc.coords)
                if d < 20.0 then
                    sleep = 0
                    if P.drawMarker ~= false and not loc.ped then
                        DrawMarker(27, loc.coords.x, loc.coords.y, loc.coords.z - 0.97, 0, 0, 0, 0, 0, 0,
                            1.2, 1.2, 1.0, mc.r, mc.g, mc.b, mc.a, false, false, 2, false, nil, nil, false)
                    end
                    if d < (P.distance or 2.0) then
                        BeginTextCommandDisplayHelp('STRING')
                        AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ ' .. (loc.label or 'Fotostudio'))
                        EndTextCommandDisplayHelp(0, false, true, -1)
                        if IsControlJustReleased(0, 38) then openMenu(i) end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, b in ipairs(blips) do RemoveBlip(b) end
    for _, ped in pairs(peds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    if useTarget then
        for i, loc in ipairs(LOCS) do
            if not loc.ped then pcall(function() exports[P.targetName or 'qb-target']:RemoveZone('vps_point_' .. i) end) end
        end
    end
end)
