-- Galerie: Daten für die NUI liefern, Bilder nachladen, Fotos löschen
local QBCore = exports['qb-core']:GetCoreObject()
local G = Config.Gallery or {}
local resName = GetCurrentResourceName()

local function isAdmin(src)
    return QBCore.Functions.HasPermission(src, Config.Permission) or QBCore.Functions.HasPermission(src, 'god')
end

local function trimPlate(p)
    return (tostring(p or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

-- "schwarz_himmel_side" -> Variante "schwarz_himmel", Winkel "side"
local function splitKey(key)
    local variant, angle = key:match('^(.*)_([^_]+)$')
    if not variant then return nil, key end
    return variant, angle
end

local function variantLabel(variant)
    if not variant then return nil end
    local parts = {}
    local cl = VPS.colorLabel(variant)
    if cl then parts[#parts + 1] = cl end
    for piece in variant:gmatch('[^_]+') do
        local st = VPS.findStudio(piece)
        if st then parts[#parts + 1] = st.label or st.name end
    end
    if #parts == 0 then parts[1] = variant end
    return table.concat(parts, ' · ')
end

---------------------------------------------------------------------
-- Katalog (Admin)
---------------------------------------------------------------------
local function catalogData()
    local index = VPS.getIndex()
    local models = {}
    for _, e in ipairs(VPS.buildList(nil, false)) do models[e.model] = true end
    for m in pairs(index) do models[m] = true end

    local items = {}
    for model in pairs(models) do
        local v = VPS.vehicleInfo(model) or { name = model }
        local e = index[model]
        local images = {}
        if e and e.images then
            for key, file in pairs(e.images) do
                local variant, angle = splitKey(key)
                local url = e.urls and e.urls[key]
                images[#images + 1] = {
                    key     = key,
                    angle   = angle,
                    label   = VPS.angleLabel(angle),
                    variant = variantLabel(variant),
                    src     = url or ('local:' .. file),
                    url     = url,
                    main    = (variant == nil and angle == Config.MainAngle) or nil,
                }
            end
            table.sort(images, function(a, b)
                if (a.main and 1 or 0) ~= (b.main and 1 or 0) then return a.main ~= nil end
                return a.key < b.key
            end)
        end
        items[#items + 1] = {
            id       = model,
            model    = model,
            name     = v.name or model,
            brand    = v.brand,
            category = v.category,
            price    = v.price,
            custom   = v.custom,
            updated  = e and e.updated,
            images   = images,
        }
    end
    table.sort(items, function(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end)
    return items
end

---------------------------------------------------------------------
-- Spielerfotos
---------------------------------------------------------------------
local function playerData(citizenid)
    local vehicles = MySQL.query.await('SELECT vehicle, plate FROM player_vehicles WHERE citizenid = ?', { citizenid }) or {}
    local photos = MySQL.query.await(
        'SELECT plate, model, angle, url, UNIX_TIMESTAMP(created_at) AS ts FROM vehicle_photos WHERE citizenid = ?',
        { citizenid }) or {}

    local byPlate, items = {}, {}
    local function item(plate, model)
        plate = trimPlate(plate)
        if not byPlate[plate] then
            local v = QBCore.Shared.Vehicles[model] or {}
            byPlate[plate] = { id = plate, plate = plate, model = model, name = v.name or model, brand = v.brand, images = {} }
            items[#items + 1] = byPlate[plate]
        end
        return byPlate[plate]
    end

    for _, r in ipairs(vehicles) do item(r.plate, r.vehicle) end
    for _, r in ipairs(photos) do
        local it = item(r.plate, r.model)
        it.images[#it.images + 1] = {
            key   = r.angle,
            angle = r.angle,
            label = VPS.angleLabel(r.angle),
            src   = r.url,
            url   = r.url,
            main  = (r.angle == Config.MainAngle) or nil,
            ts    = r.ts,
        }
        it.updated = math.max(it.updated or 0, tonumber(r.ts) or 0)
    end
    for _, it in ipairs(items) do
        table.sort(it.images, function(a, b)
            if (a.main and 1 or 0) ~= (b.main and 1 or 0) then return a.main ~= nil end
            return a.key < b.key
        end)
    end
    table.sort(items, function(a, b) return a.plate < b.plate end)
    return items
end

local function citizenFor(src)
    -- Im Spieler-Studio (auch /photoplayer): Fahrzeuge dieser Sitzung
    local s = VPS.sessions[src]
    if s and s.mode == 'player' and s.citizenid then return s.citizenid end
    local Player = QBCore.Functions.GetPlayer(src)
    return Player and Player.PlayerData.citizenid
end

---------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------
QBCore.Functions.CreateCallback('vps:gallery:get', function(src, cb, kind)
    if not G.enabled then return cb(nil) end
    if kind == 'catalog' then
        if not isAdmin(src) then return cb(nil) end
        return cb({ kind = 'catalog', items = catalogData(), canDelete = G.adminDelete ~= false })
    end
    local cid = citizenFor(src)
    if not cid then return cb(nil) end
    cb({ kind = 'player', items = playerData(cid), canDelete = G.playerDelete ~= false })
end)

-- Lokale Bilder (nur Katalog, nur Admins) – als latent Event, da groß
RegisterNetEvent('vps:gallery:reqImage', function(reqId, file)
    local src = source
    if not isAdmin(src) then return end
    local dataUri = exports[resName]:readImageDataUri(tostring(file or ''))
    TriggerLatentClientEvent('vps:gallery:image', src, 2000000, reqId, dataUri or false)
end)

QBCore.Functions.CreateCallback('vps:gallery:delete', function(src, cb, data)
    if type(data) ~= 'table' then return cb(false) end

    if data.kind == 'catalog' then
        if not (G.adminDelete ~= false and isAdmin(src)) then return cb(false) end
        local index = VPS.getIndex()
        local e = index[tostring(data.id)]
        local key = tostring(data.key or '')
        if not e or not e.images or not e.images[key] then return cb(false) end

        exports[resName]:deleteImage(e.images[key])
        if e.ids and e.ids[key] then VPS.deleteFivemanage(e.ids[key]) end

        local variant, angle = splitKey(key)
        e.images[key] = nil
        if e.urls then e.urls[key] = nil end
        if e.ids then e.ids[key] = nil end
        if variant and e.colors and e.colors[variant] then
            e.colors[variant][angle] = nil
            if next(e.colors[variant]) == nil then e.colors[variant] = nil end
        elseif not variant and angle == Config.MainAngle then
            e.image, e.imageUrl = nil, nil
        end
        if next(e.images) == nil then index[tostring(data.id)] = nil end
        VPS.saveIndex()
        return cb(true)
    end

    if not (G.playerDelete ~= false) then return cb(false) end
    local cid = citizenFor(src)
    local plate = trimPlate(data.id)
    local angle = tostring(data.key or '')
    local row = MySQL.single.await('SELECT id, file_id FROM vehicle_photos WHERE citizenid = ? AND plate = ? AND angle = ?',
        { cid, plate, angle })
    if not row then return cb(false) end
    MySQL.query.await('DELETE FROM vehicle_photos WHERE id = ?', { row.id })
    if row.file_id then VPS.deleteFivemanage(row.file_id) end
    cb(true)
end)
