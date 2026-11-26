local QBCore = exports['qb-core']:GetCoreObject()

local resName = GetCurrentResourceName()
local sessions = {}
VPS = VPS or {}            -- geteilt mit server_player.lua
VPS.sessions = sessions
local index = json.decode(LoadResourceFile(resName, 'images/index.json') or '{}') or {}

---------------------------------------------------------------------
-- index.json (Daten für Website / Katalog)
---------------------------------------------------------------------
local saveQueued = false
local function saveIndex()
    if saveQueued then return end
    saveQueued = true
    SetTimeout(2000, function()
        saveQueued = false
        SaveResourceFile(resName, 'images/index.json', json.encode(index), -1)
    end)
end

---------------------------------------------------------------------
-- Eigene Fahrzeuge (Config.CustomVehicles + automatische Erkennung)
---------------------------------------------------------------------
local customVehicles = {}

local function addCustom(model, data, explicit)
    if type(model) ~= 'string' or model == '' then return end
    model = model:lower()
    local e = customVehicles[model] or { model = model }
    for k, v in pairs(data or {}) do
        if v ~= nil and v ~= '' and (explicit or e[k] == nil) then e[k] = v end
    end
    if explicit then e.explicit = true end
    customVehicles[model] = e
end

-- liest modelName / gameName / vehicleMakeName aus einer vehicles.meta
local function readVehiclesMeta(res, file)
    local content = LoadResourceFile(res, file)
    if not content then return 0 end

    local found = {}
    for pos, name in content:gmatch('()<modelName>%s*([^<]-)%s*</modelName>') do
        found[#found + 1] = { pos = pos, name = name }
    end
    for i, f in ipairs(found) do
        local chunk = content:sub(f.pos, found[i + 1] and (found[i + 1].pos - 1) or #content)
        addCustom(f.name, {
            name     = chunk:match('<gameName>%s*([^<]-)%s*</gameName>'),
            brand    = chunk:match('<vehicleMakeName>%s*([^<]-)%s*</vehicleMakeName>'),
            resource = res,
        })
    end
    return #found
end

local function scanResources()
    local ad = Config.AutoDetect or {}
    if not ad.enabled then return end

    local only, skip = {}, {}
    for _, r in ipairs(ad.resources or {}) do only[r] = true end
    for _, r in ipairs(ad.ignore or {}) do skip[r] = true end

    local total, globs = 0, {}
    for i = 0, GetNumResources() - 1 do
        local res = GetResourceByFindIndex(i)
        if res and GetResourceState(res) == 'started' and not skip[res] and (next(only) == nil or only[res]) then
            local seen = {}
            for j = 0, GetNumResourceMetadata(res, 'data_file') - 1 do
                if GetResourceMetadata(res, 'data_file', j) == 'VEHICLE_METADATA_FILE' then
                    local raw = GetResourceMetadata(res, 'data_file_extra', j)
                    local path = raw
                    local ok, dec = pcall(json.decode, raw or '')
                    if ok and type(dec) == 'table' then path = dec[1] elseif ok and type(dec) == 'string' then path = dec end

                    if type(path) == 'string' then
                        if path:find('[%*%?]') then
                            globs[#globs + 1] = res .. ' (' .. path .. ')'
                        elseif not seen[path] then
                            seen[path] = true
                            total = total + readVehiclesMeta(res, path)
                        end
                    end
                end
            end
        end
    end

    print(('[photostudio] %d eigene Fahrzeuge erkannt (gesamt mit Config: %d)'):format(total, (function()
        local n = 0 for _ in pairs(customVehicles) do n = n + 1 end return n end)()))
    if #globs > 0 then
        print('[photostudio] Nicht automatisch lesbar (Wildcard-Pfade) -> Modelle in Config.CustomVehicles eintragen:')
        for _, g in ipairs(globs) do print('   - ' .. g) end
    end
end

local function loadCustom()
    customVehicles = {}
    for _, v in ipairs(Config.CustomVehicles or {}) do
        if type(v) == 'string' then
            addCustom(v, {}, true)
        elseif type(v) == 'table' and v.model then
            addCustom(v.model, { name = v.name, brand = v.brand, category = v.category, price = v.price }, true)
        end
    end
    scanResources()
end

local function vehicleInfo(model)
    local s, c = QBCore.Shared.Vehicles[model], customVehicles[model]
    if not s and not c then return nil end
    s, c = s or {}, c or {}
    local pick = function(k) return (c.explicit and c[k]) or s[k] or c[k] end
    return {
        name     = pick('name') or model,
        brand    = pick('brand'),
        category = pick('category') or 'custom',
        price    = pick('price'),
        custom   = customVehicles[model] ~= nil,
    }
end

CreateThread(function()
    Wait(3000) -- warten bis alle Fahrzeug-Resourcen gestartet sind
    loadCustom()
end)

local function updateIndex(model, angle, color, file, url, id)
    local v = vehicleInfo(model) or {}
    local e = index[model] or { images = {} }
    local key = color and (color .. '_' .. angle) or angle
    e.model, e.name, e.brand = model, v.name, v.brand
    e.category, e.price, e.custom = v.category, v.price, v.custom
    e.images[key] = file
    if url then
        e.urls = e.urls or {}
        e.ids = e.ids or {}
        e.urls[key], e.ids[key] = url, id
    end
    if color then
        e.colors = e.colors or {}
        e.colors[color] = e.colors[color] or {}
        e.colors[color][angle] = url or file
    elseif angle == Config.MainAngle then
        e.image = file
        if url then e.imageUrl = url end
    end
    e.updated = os.date('!%Y-%m-%dT%H:%M:%SZ')
    index[model] = e
    saveIndex()
end

---------------------------------------------------------------------
-- Fahrzeuglisten
---------------------------------------------------------------------
local function entryFor(model, v)
    v = v or { name = model }
    return { model = model, name = v.name, brand = v.brand, category = v.category or 'unknown', price = v.price, custom = v.custom }
end

-- category: nil = Standard (Config.OnlyCustom), 'custom' = nur eigene, 'all' = alle, sonst Kategorie
local function buildList(category, skipExisting)
    local models = {}
    for m in pairs(QBCore.Shared.Vehicles) do models[m] = true end
    for m in pairs(customVehicles) do models[m] = true end

    local list = {}
    for model in pairs(models) do
        local v = vehicleInfo(model)
        local cat = v.category
        local allowed
        if category == 'custom' then
            allowed = v.custom
        elseif category == 'all' then
            allowed = not Config.ExcludeCategories[cat]
        elseif category then
            allowed = (cat == category) and (not Config.OnlyCustom or v.custom)
        else
            allowed = (not Config.OnlyCustom or v.custom) and not Config.ExcludeCategories[cat]
        end
        local exists = skipExisting and index[model] and index[model].image
        if allowed and not exists then
            list[#list + 1] = entryFor(model, v)
        end
    end
    table.sort(list, function(a, b) return a.model < b.model end)
    return list
end

---------------------------------------------------------------------
-- Sessions
---------------------------------------------------------------------
local function endSession(src)
    local s = sessions[src]
    if not s then return end
    SetPlayerRoutingBucket(src, s.oldBucket or 0)
    sessions[src] = nil
end

local function startSession(src, mode, list, startModel, extra)
    if sessions[src] then
        TriggerClientEvent('QBCore:Notify', src, 'Du bist bereits im Fotostudio.', 'error')
        return false
    end
    if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= 0 then
        TriggerClientEvent('QBCore:Notify', src, 'Steig zuerst aus dem Fahrzeug aus.', 'error')
        return false
    end
    if #list == 0 then
        local msg = (mode == 'player') and 'Keine Fahrzeuge gefunden.'
            or (Config.OnlyCustom
                and 'Keine eigenen Fahrzeuge gefunden. Config.CustomVehicles füllen oder /vpsscan ausführen (alle: /photoall all).'
                or 'Keine passenden Fahrzeuge gefunden.')
        TriggerClientEvent('QBCore:Notify', src, msg, 'error', 8000)
        return false
    end

    local bucket = Config.BucketBase + src
    local s = { oldBucket = GetPlayerRoutingBucket(src), mode = mode }
    for k, v in pairs(extra or {}) do s[k] = v end
    sessions[src] = s
    SetRoutingBucketPopulationEnabled(bucket, false)
    SetPlayerRoutingBucket(src, bucket)

    TriggerClientEvent('vps:client:open', src, mode, list, startModel, { studio = s.studio, lock = s.lockStudio })
    return true
end

-- Studio-Ort nach Name finden (Config.Studios)
local function findStudio(name)
    if type(name) ~= 'string' then return nil end
    local H = Config.HereStudio
    if H and H.enabled and name == (H.name or 'hier') then
        return { name = H.name or 'hier', label = H.label or 'Aktueller Standort', suffix = H.suffix, here = true }
    end
    for _, st in ipairs(Config.Studios or {}) do
        if st.name == name then return st end
    end
end
VPS.findStudio = findStudio
VPS.startSession = startSession
VPS.endSession = endSession

QBCore.Commands.Add('photostudio', 'Fahrzeug-Fotostudio öffnen', {
    { name = 'model', help = 'Spawn-Name oder Ort (optional)' },
    { name = 'ort',   help = 'Studio-Ort, z.B. Hangar, Garage, Tuner, himmel (optional)' },
}, false, function(source, args)
    local list = buildList(nil, false)
    local start, place = args[1], args[2]
    -- /photostudio himmel  -> nur Ort angegeben
    if start and not place and findStudio(start) and not vehicleInfo(start) then
        start, place = nil, start
    end
    if place and not findStudio(place) then
        return TriggerClientEvent('QBCore:Notify', source, 'Unbekannter Ort: ' .. place, 'error')
    end
    if start then
        local found = false
        for _, e in ipairs(list) do if e.model == start then found = true break end end
        if not found then
            table.insert(list, 1, entryFor(start, vehicleInfo(start)))
        end
    end
    startSession(source, 'single', list, start, { studio = place })
end, Config.Permission)

QBCore.Commands.Add('vpsscan', 'Eigene Fahrzeuge neu erkennen', {}, false, function(source)
    loadCustom()
    local n, list = 0, {}
    for m in pairs(customVehicles) do n = n + 1; list[#list + 1] = m end
    table.sort(list)
    print('[photostudio] Eigene Fahrzeuge: ' .. table.concat(list, ', '))
    TriggerClientEvent('QBCore:Notify', source, ('%d eigene Fahrzeuge erkannt (Liste in der Serverkonsole)'):format(n), 'success')
end, Config.Permission)

QBCore.Commands.Add('photoall', 'Alle Fahrzeuge automatisch fotografieren', {
    { name = 'kategorie', help = 'optional: custom (nur eigene), all (alle) oder Kategorie z.B. sports' },
    { name = 'ort',       help = 'optional: Studio-Ort, z.B. himmel' },
}, false, function(source, args)
    local category, place = args[1], args[2]
    -- /photoall himmel  -> nur Ort angegeben
    if category and not place and findStudio(category) then
        category, place = nil, category
    end
    if place and not findStudio(place) then
        return TriggerClientEvent('QBCore:Notify', source, 'Unbekannter Ort: ' .. place, 'error')
    end
    local list = buildList(category, Config.SkipExisting)
    TriggerClientEvent('QBCore:Notify', source, ('%d Fahrzeuge in der Warteschlange'):format(#list), 'primary')
    startSession(source, 'batch', list, nil, { studio = place })
end, Config.Permission)

QBCore.Commands.Add('vpsorte', 'Alle Studio-Orte anzeigen', {}, false, function(source)
    local names = {}
    for _, st in ipairs(Config.Studios or {}) do
        names[#names + 1] = st.name .. (st.name == Config.DefaultStudio and ' (Standard)' or '')
    end
    TriggerClientEvent('QBCore:Notify', source, 'Orte: ' .. table.concat(names, ', '), 'primary', 10000)
end, Config.Permission)

---------------------------------------------------------------------
-- Fivemanage Upload (https://docs.fivemanage.com)
---------------------------------------------------------------------
local FM_URL = 'https://api.fivemanage.com/api/v3/file/base64'

local function uploadFivemanage(dataUri, file, meta, cb, path)
    local token = GetConvar(Config.Upload.tokenConvar or 'fivemanage_token', '')
    if token == '' then
        print('[photostudio] Kein Fivemanage-Token gesetzt (set ' .. (Config.Upload.tokenConvar or 'fivemanage_token') .. ' "...")')
        return cb(nil)
    end

    PerformHttpRequest(FM_URL, function(status, body)
        local ok, res = pcall(json.decode, body or '')
        if (status ~= 200 and status ~= 201) or not ok or not res or not res.data or not res.data.url then
            print(('[photostudio] Fivemanage-Upload fehlgeschlagen (%s): %s'):format(tostring(status), tostring(body)))
            return cb(nil)
        end
        cb(res.data.url, res.data.id)
    end, 'POST', json.encode({
        base64   = dataUri,
        filename = file,
        path     = path or Config.Upload.path,
        metadata = json.encode(meta),
    }), {
        ['Content-Type']  = 'application/json',
        ['Authorization'] = token,
    })
end
VPS.uploadFivemanage = uploadFivemanage

-- Datei auf Fivemanage löschen (id oder Pfad)
function VPS.deleteFivemanage(id)
    local token = GetConvar(Config.Upload.tokenConvar or 'fivemanage_token', '')
    if token == '' or not id or id == '' then return end
    PerformHttpRequest('https://api.fivemanage.com/api/v3/file/' .. id, function(status, body)
        if status ~= 200 and status ~= 204 then
            print(('[photostudio] Löschen auf Fivemanage fehlgeschlagen (%s): %s'):format(tostring(status), tostring(body)))
        end
    end, 'DELETE', '', { ['Authorization'] = token })
end

---------------------------------------------------------------------
-- Discord-Webhook
---------------------------------------------------------------------
local function angleLabel(name)
    for _, a in ipairs(Config.Angles) do if a.name == name then return a.label end end
    return name
end
-- Farbname -> Anzeige. Bei Varianten wie "schwarz_himmel" zählt der Farbteil;
-- ist die Variante nur ein Ortsname, gibt es keine Farbe (nil).
local function colorLabel(name)
    if not name then return nil end
    for _, c in ipairs(Config.Colors) do if c.name == name then return c.label end end
    local first = name:match('^([^_]+)_')
    if first then
        for _, c in ipairs(Config.Colors) do if c.name == first then return c.label end end
    end
    return nil
end
local function inList(list, v)
    if not list then return true end
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end
local function fmtPrice(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    return (s:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', ''))
end
VPS.angleLabel = angleLabel

-- kind = 'catalog' | 'player'. Mit imageUrl wird der Link eingebettet,
-- sonst wird das Bild (dataUri) direkt als Anhang mitgeschickt.
function VPS.discord(kind, angle, embed, imageUrl, fileName, dataUri)
    local D = Config.Discord
    if not D or not D.enabled then return end
    local sub = D[kind] or {}
    if sub.enabled == false or not inList(sub.angles, angle) then return end

    local hook = GetConvar(kind == 'player' and D.playerConvar or D.catalogConvar, '')
    if hook == '' then return end

    embed.color = embed.color or D.color
    embed.timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
    embed.footer = embed.footer or { text = 'Vehicle Photo Studio' }

    local attach = false
    if imageUrl then
        embed.image = { url = imageUrl }
    elseif dataUri and fileName then
        embed.image = { url = 'attachment://' .. fileName }
        attach = true
    end

    exports[resName]:discordPost(hook, {
        username   = D.username,
        avatar_url = D.avatar,
        embeds     = { embed },
    }, attach and fileName or nil, attach and dataUri or nil)
end

local function catalogEmbed(src, model, angle, color)
    local v = vehicleInfo(model) or {}
    local fields = {
        { name = 'Modell',    value = '`' .. model .. '`',          inline = true },
        { name = 'Kategorie', value = tostring(v.category or '-'),  inline = true },
        { name = 'Winkel',    value = angleLabel(angle),            inline = true },
    }
    if v.price then fields[#fields + 1] = { name = 'Preis', value = '$' .. fmtPrice(v.price), inline = true } end
    local cl = colorLabel(color)
    if cl then fields[#fields + 1] = { name = 'Farbe', value = cl, inline = true } end
    local st = sessions[src] and sessions[src].lastStudio
    if st then fields[#fields + 1] = { name = 'Ort', value = st.label or st.name, inline = true } end
    fields[#fields + 1] = { name = 'Aufgenommen von', value = GetPlayerName(src) or '-', inline = true }
    return { title = (v.brand and (v.brand .. ' ') or '') .. (v.name or model), fields = fields }
end

---------------------------------------------------------------------
-- Screenshot
---------------------------------------------------------------------
RegisterNetEvent('vps:server:capture', function(model, angle, color, plate, studioName)
    local src = source
    local session = sessions[src]
    if not session then return end

    local st = findStudio(studioName)

    -- Persönliche Spielerfahrzeuge -> server_player.lua
    if session.mode == 'player' then
        return VPS.playerCapture(src, session, angle, plate, st)
    end

    model = (tostring(model):gsub('[^%w_%-]', ''))
    angle = (tostring(angle):gsub('[^%w_%-]', ''))
    if model == '' or angle == '' then return end
    if color then
        color = (tostring(color):gsub('[^%w_%-]', ''))
        if color == '' then color = nil end
    end
    -- Orte mit suffix = true bekommen ihren Namen in den Dateinamen
    -- (wird wie eine Farb-Variante behandelt: adder_himmel.png, adder_schwarz_himmel_side.png)
    if st and st.suffix then
        color = color and (color .. '_' .. st.name) or st.name
    end
    session.lastStudio = st

    local base = model
    if color then base = base .. '_' .. color end
    if angle ~= Config.MainAngle then base = base .. '_' .. angle end
    local file = base .. '.' .. Config.Encoding

    local mode = Config.Upload and Config.Upload.mode or 'local'
    local wantLocal  = (mode == 'local' or mode == 'both')
    local wantUpload = (mode == 'fivemanage' or mode == 'both')

    local function done(ok, label)
        TriggerClientEvent('vps:client:captureDone', src, ok, label or file)
    end

    -- screenshot-basic schreibt selbst KEINE Datei mehr (FXServer-Sandbox / fs.write).
    -- Wir holen das Bild als data-URI und speichern es mit dieser Resource selbst.
    exports['screenshot-basic']:requestClientScreenshot(src, {
        encoding = Config.Encoding,
        quality  = Config.Quality,
    }, function(err, dataUri)
        if err or not dataUri then
            print(('[photostudio] Screenshot fehlgeschlagen (%s): %s'):format(file, tostring(err)))
            return done(false, file)
        end

        if wantLocal then
            if exports[resName]:saveDataUri('images/' .. file, dataUri) then
                updateIndex(model, angle, color, file)
            else
                print(('[photostudio] Konnte %s nicht lokal speichern'):format(file))
                if not wantUpload then return done(false, file) end
            end
        end

        local postDiscord = session.mode ~= 'batch' or (Config.Discord and Config.Discord.catalog and Config.Discord.catalog.batch)

        if not wantUpload then
            if postDiscord then VPS.discord('catalog', angle, catalogEmbed(src, model, angle, color), nil, file, dataUri) end
            return done(true, file)
        end

        local v = vehicleInfo(model) or {}
        local meta = { model = model, name = v.name, brand = v.brand, angle = angle, color = color or 'standard' }
        uploadFivemanage(dataUri, file, meta, function(url, id)
            if not url then return done(false, file .. ' (Upload)') end
            updateIndex(model, angle, color, file, url, id)
            print(('[photostudio] %s -> %s'):format(file, url))
            if postDiscord then VPS.discord('catalog', angle, catalogEmbed(src, model, angle, color), url) end
            done(true, file .. ' -> Fivemanage')
        end)
    end)
end)

RegisterNetEvent('vps:server:exit', function()
    endSession(source)
end)

AddEventHandler('playerDropped', function()
    endSession(source)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= resName then return end
    SaveResourceFile(resName, 'images/index.json', json.encode(index), -1)
    for src in pairs(sessions) do endSession(src) end
end)

-- Für server_gallery.lua
VPS.getIndex    = function() return index end
VPS.saveIndex   = saveIndex
VPS.vehicleInfo = vehicleInfo
VPS.buildList   = buildList
VPS.colorLabel  = colorLabel
