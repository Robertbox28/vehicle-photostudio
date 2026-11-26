-- Persönliche Fahrzeuge der Spieler fotografieren (player_vehicles + Tuning)
local QBCore = exports['qb-core']:GetCoreObject()
local PS = Config.PlayerStudio or {}
local resName = GetCurrentResourceName()

local function notify(src, msg, typ, len)
    TriggerClientEvent('QBCore:Notify', src, msg, typ or 'primary', len)
end

---------------------------------------------------------------------
-- Datenbank
---------------------------------------------------------------------
MySQL.ready(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `vehicle_photos` (
            `id`         INT AUTO_INCREMENT PRIMARY KEY,
            `citizenid`  VARCHAR(50)  NOT NULL,
            `plate`      VARCHAR(16)  NOT NULL,
            `model`      VARCHAR(60)  NOT NULL,
            `angle`      VARCHAR(30)  NOT NULL,
            `url`        VARCHAR(255) NOT NULL,
            `file_id`    VARCHAR(100) NULL,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY `plate_angle` (`plate`, `angle`),
            KEY `citizenid` (`citizenid`)
        )
    ]])
end)

local function trimPlate(p)
    return (tostring(p or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

---------------------------------------------------------------------
-- Exports (z.B. für Auktionshaus / Garage / Handy)
---------------------------------------------------------------------
local function getPhotos(plate)
    local rows = MySQL.query.await('SELECT angle, url FROM vehicle_photos WHERE plate = ?', { trimPlate(plate) }) or {}
    local out = {}
    for _, r in ipairs(rows) do out[r.angle] = r.url end
    return out
end

local function getPhoto(plate, angle)
    local photos = getPhotos(plate)
    if angle then return photos[angle] end
    return photos[Config.MainAngle] or select(2, next(photos))
end

exports('GetVehiclePhotos', getPhotos)
exports('GetVehiclePhoto', getPhoto)

-- Für NUI/Client-Skripte: QBCore-Callback
QBCore.Functions.CreateCallback('vehicle-photostudio:server:getPhotos', function(_, cb, plate)
    cb(getPhotos(plate))
end)

---------------------------------------------------------------------
-- Fahrzeugliste des Spielers
---------------------------------------------------------------------
local function playerVehicles(citizenid)
    local sql = 'SELECT vehicle, plate, mods FROM player_vehicles WHERE citizenid = ?'
    if PS.onlyInGarage then sql = sql .. ' AND state = 1' end
    local rows = MySQL.query.await(sql, { citizenid }) or {}

    local list = {}
    for _, r in ipairs(rows) do
        local v = QBCore.Shared.Vehicles[r.vehicle] or {}
        local ok, props = pcall(json.decode, r.mods or '{}')
        list[#list + 1] = {
            model = r.vehicle,
            plate = trimPlate(r.plate),
            name  = v.name or r.vehicle,
            brand = v.brand,
            props = ok and props or {},
        }
    end
    table.sort(list, function(a, b) return a.plate < b.plate end)
    return list
end

-- Gibt den Eingang zurück, an dem der Spieler steht ({} wenn überall erlaubt), sonst nil
local function nearStudio(src)
    if not PS.locations or #PS.locations == 0 then return {} end
    local pos = GetEntityCoords(GetPlayerPed(src))
    for _, l in ipairs(PS.locations) do
        if #(pos - l.coords) <= (l.radius or 10.0) then return l end
    end
    return nil
end

---------------------------------------------------------------------
-- Öffnen
---------------------------------------------------------------------
local function openForPlayer(src, targetSrc, isAdmin, wantStudio)
    if not PS.enabled then return end
    local Player = QBCore.Functions.GetPlayer(targetSrc)
    if not Player then return notify(src, 'Spieler nicht gefunden.', 'error') end

    if GetConvar(Config.Upload.tokenConvar or 'fivemanage_token', '') == '' then
        return notify(src, 'Fotostudio ist nicht eingerichtet (Fivemanage-Token fehlt).', 'error')
    end
    if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= 0 then
        return notify(src, 'Steig zuerst aus dem Fahrzeug aus.', 'error')
    end
    local wantSt = wantStudio and VPS.findStudio(wantStudio)
    local entrance = isAdmin and {} or nearStudio(src)
    -- "hier" geht mit hereAnywhere auch ohne Eingang
    local locked = false
    if not entrance and wantSt and wantSt.here and PS.allowHere and PS.hereAnywhere then
        entrance = {}
        locked = true -- ausserhalb eines Eingangs: nur "hier", kein Wechsel zu anderen Orten
    end
    if not entrance then
        return notify(src, 'Hier gibt es kein Fotostudio.', 'error')
    end
    if entrance.studio and not VPS.findStudio(entrance.studio) then
        print(('[photostudio] Eingang "%s": Studio-Ort "%s" gibt es nicht in Config.Studios'):format(entrance.label or '?', entrance.studio))
    end

    -- Ort: Eingang bestimmt ihn; "hier" nur wenn erlaubt (Admins immer)
    local chosenStudio = entrance.studio
    if wantStudio then
        local st = VPS.findStudio(wantStudio)
        if not st then return notify(src, 'Unbekannter Ort: ' .. tostring(wantStudio), 'error') end
        if not isAdmin and st.here and not PS.allowHere then
            return notify(src, 'Fotos am aktuellen Standort sind nicht erlaubt.', 'error')
        end
        if not isAdmin and not st.here then
            return notify(src, 'Diesen Ort kannst du hier nicht wählen.', 'error')
        end
        chosenStudio = st.name
    end

    local list = playerVehicles(Player.PlayerData.citizenid)
    if #list == 0 then return notify(src, 'Keine Fahrzeuge gefunden.', 'error') end

    local allowed = {}
    for _, e in ipairs(list) do allowed[e.plate] = e.model end

    if not isAdmin and (PS.price or 0) > 0 then
        local Self = QBCore.Functions.GetPlayer(src)
        if not Self.Functions.RemoveMoney(PS.account or 'bank', PS.price, 'vehicle-photostudio') then
            return notify(src, ('Du brauchst $%d für das Fotostudio.'):format(PS.price), 'error')
        end
    end

    local ci = Player.PlayerData.charinfo or {}
    VPS.startSession(src, 'player', list, nil, {
        citizenid = Player.PlayerData.citizenid,
        ownerName = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', ''),
        allowed   = allowed,
        admin     = isAdmin,
        photos    = 0,
        lastPhoto = 0,
        studio    = chosenStudio,
        lockStudio = locked,
    })
end

if PS.enabled then
    QBCore.Commands.Add(PS.command or 'fotostudio', 'Eigene Fahrzeuge fotografieren', {
        { name = 'hier', help = 'optional: "hier" = am aktuellen Standort fotografieren' }
    }, false, function(source, args)
        openForPlayer(source, source, false, args[1])
    end, PS.permission)

    QBCore.Commands.Add(PS.adminCommand or 'photoplayer', 'Fahrzeuge eines Spielers fotografieren', {
        { name = 'id',  help = 'Spieler-ID' },
        { name = 'ort', help = 'optional: Studio-Ort oder "hier"' },
    }, false, function(source, args)
        openForPlayer(source, tonumber(args[1]) or source, true, args[2])
    end, Config.Permission)
end

-- Infos für das Menü an den festen Orten
QBCore.Functions.CreateCallback('vps:points:info', function(src, cb)
    local admin = QBCore.Functions.HasPermission(src, Config.Permission) or QBCore.Functions.HasPermission(src, 'god')
    local allowed = (not PS.permission) or QBCore.Functions.HasPermission(src, PS.permission)
    cb({
        admin        = admin,
        playerStudio = PS.enabled and allowed,
        price        = PS.price or 0,
        gallery      = Config.Gallery and Config.Gallery.enabled or false,
    })
end)

-- Zum Öffnen über qb-target / Ped / Marker:  TriggerServerEvent('vehicle-photostudio:server:openPlayer')
RegisterNetEvent('vehicle-photostudio:server:openPlayer', function()
    local src = source
    if PS.permission and not QBCore.Functions.HasPermission(src, PS.permission) then return end
    openForPlayer(src, src, false)
end)

---------------------------------------------------------------------
-- Foto
---------------------------------------------------------------------
local allowedAngles = {}
for _, a in ipairs(PS.angles or {}) do allowedAngles[a] = true end

function VPS.playerCapture(src, s, angle, plate, st)
    local function done(ok, label)
        TriggerClientEvent('vps:client:captureDone', src, ok, label)
    end

    plate = trimPlate(plate)
    angle = tostring(angle or ''):gsub('[^%w_%-]', '')
    local model = s.allowed[plate]
    if not model then return done(false, 'Fahrzeug gehört nicht dir') end
    if not s.admin then
        if not allowedAngles[angle] then return done(false, 'Winkel nicht erlaubt') end
        if s.photos >= (PS.maxPhotos or 12) then return done(false, 'Foto-Limit erreicht') end
        if GetGameTimer() - s.lastPhoto < (PS.cooldown or 0) * 1000 - 500 then return done(false, 'Bitte kurz warten') end
    end
    s.lastPhoto = GetGameTimer()
    s.photos = s.photos + 1

    local safePlate = plate:gsub('[^%w]', '')
    local file = ('%s_%s.%s'):format(safePlate, angle, Config.Encoding)

    exports['screenshot-basic']:requestClientScreenshot(src, {
        encoding = Config.Encoding,
        quality  = Config.Quality,
    }, function(err, dataUri)
        if err or not dataUri then
            print(('[photostudio] Screenshot fehlgeschlagen (%s): %s'):format(file, tostring(err)))
            return done(false, file)
        end

        local meta = { plate = plate, model = model, angle = angle, citizenid = s.citizenid }
        VPS.uploadFivemanage(dataUri, file, meta, function(url, id)
            if not url then return done(false, file .. ' (Upload)') end

            local old = MySQL.scalar.await('SELECT file_id FROM vehicle_photos WHERE plate = ? AND angle = ?', { plate, angle })
            MySQL.insert.await([[
                INSERT INTO vehicle_photos (citizenid, plate, model, angle, url, file_id)
                VALUES (?, ?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE citizenid = VALUES(citizenid), model = VALUES(model),
                    url = VALUES(url), file_id = VALUES(file_id)
            ]], { s.citizenid, plate, model, angle, url, id })

            if PS.deleteOld and old and old ~= id then VPS.deleteFivemanage(old) end

            -- Discord
            local v = QBCore.Shared.Vehicles[model] or {}
            local fields = {
                { name = 'Kennzeichen', value = '`' .. plate .. '`',     inline = true },
                { name = 'Modell',      value = '`' .. model .. '`',     inline = true },
                { name = 'Winkel',      value = VPS.angleLabel(angle),   inline = true },
            }
            if Config.Discord and Config.Discord.player and Config.Discord.player.showOwner then
                local owner = (s.ownerName and s.ownerName ~= '') and s.ownerName or s.citizenid
                fields[#fields + 1] = { name = 'Besitzer', value = owner, inline = true }
            end
            if st then
                fields[#fields + 1] = { name = 'Ort', value = st.label or st.name, inline = true }
            end
            if s.admin then
                fields[#fields + 1] = { name = 'Aufgenommen von', value = (GetPlayerName(src) or '-') .. ' (Admin)', inline = true }
            end
            VPS.discord('player', angle, {
                title  = (v.brand and (v.brand .. ' ') or '') .. (v.name or model),
                fields = fields,
            }, url)

            -- Hook für andere Resourcen
            TriggerEvent('vehicle-photostudio:server:photoTaken', src, {
                citizenid = s.citizenid, plate = plate, model = model, angle = angle, url = url,
            })
            done(true, ('%s (%s) gespeichert'):format(plate, angle))
        end, PS.path or 'player-vehicles')
    end)
end
