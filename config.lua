Config = {}

-- Wer darf das Studio benutzen (QBCore-Permission: 'god', 'admin', ...)
Config.Permission = 'admin'

-- Jede Session läuft in einer eigenen Routing-Bucket (keine anderen Spieler/NPCs im Bild)
Config.BucketBase = 7000

---------------------------------------------------------------------
-- Studio-Orte
---------------------------------------------------------------------
-- Im Studio mit B (SHIFT+B rückwärts) umschalten, oder direkt per Befehl:
--   /photostudio adder himmel      /photoall sports Hangar
-- Neuen Ort anlegen: hinstellen, /vpspos eingeben, die Zeile aus der
-- F8-Konsole hier einfügen und name/label anpassen.
--
--   name     = interner Name (für Befehle, Spieler-Eingänge, Dateinamen)
--   label    = Anzeige im Studio und auf Discord
--   coords   = Position des Fahrzeugs        heading = Blickrichtung des Fahrzeugs
--   onGround = true: Fahrzeug auf den Boden setzen / false: schwebt (z.B. Himmel)
--   pitch    = feste Kamerahöhe in Grad (nil = aus den Winkeln unten)
--   time     = eigene Uhrzeit für diesen Ort, z.B. { hour = 19, minute = 30 }
--   weather  = eigenes Wetter für diesen Ort, z.B. 'CLEAR'
--   suffix   = true: Ortsname kommt in den Dateinamen (adder_himmel.png),
--              damit Bilder von verschiedenen Orten sich nicht überschreiben
Config.Studios = {
    {
        name = 'Garage', label = 'Garage',
        coords = vector3(-1507.71, -2992.78, -82.58), heading = 269.68,
        onGround = true,
    },
    {
        name = 'Hangar', label = 'Hangar (LSIA)',
        coords = vector3(-1266.93, -3010.64, -48.86), heading = 0.49,
        onGround = true,
    },
    {
        name = 'Tuner', label = 'Tuner Garage',
        coords = vector3(-1333.46, 147.95, -99.57), heading = 42.68,
        onGround = true,
    },
    {
        name = 'himmel', label = 'Himmel (zum Freistellen)',
        coords = vector3(-3200.0, -3200.0, 900.0), heading = 0.0,
        onGround = false, pitch = -10.0,
        suffix = true,
    },
    -- Beispiele – Koordinaten mit /vpspos ermitteln:
    -- { name = 'showroom', label = 'Weigelt\'s Showroom', coords = vector3(0.0, 0.0, 0.0), heading = 0.0, onGround = true },
    -- { name = 'hafen',    label = 'Hafen am Abend',     coords = vector3(0.0, 0.0, 0.0), heading = 0.0, onGround = true,
    --   time = { hour = 19, minute = 30 }, weather = 'CLEAR', suffix = true },
}

-- Aktueller Standort als zusätzlicher Ort: das Fahrzeug erscheint dort,
-- wo du beim Öffnen stehst, und schaut in deine Blickrichtung.
--   /photostudio adder hier    /photoall sports hier    oder im Studio mit B
-- Andere Spieler und NPCs sind trotzdem ausgeblendet (eigene Routing-Bucket).
Config.HereStudio = {
    enabled       = true,
    name          = 'hier',
    label         = 'Aktueller Standort',
    forward       = 0.0,    -- Fahrzeug so viele Meter vor dich stellen (0 = genau wo du stehst)
    headingOffset = 0.0,    -- Fahrzeug zusätzlich drehen (180 = schaut zu dir)
    keepTime      = true,   -- echte Uhrzeit behalten (false = Config.Time)
    keepWeather   = true,   -- echtes Wetter behalten (false = Config.Weather)
    suffix        = false,  -- true = adder_hier.png
}

-- Ort beim Öffnen (name aus Config.Studios, oder 'hier')
Config.DefaultStudio = 'Hangar'

-- Standard-Licht & -Wetter (wenn der Ort nichts eigenes hat)
Config.Time    = { hour = 12, minute = 0 }
Config.Weather = 'EXTRASUNNY'

---------------------------------------------------------------------
-- Kamera
---------------------------------------------------------------------
Config.FOV          = 40.0   -- kleiner = weniger Verzerrung, Fahrzeug wird automatisch eingepasst
Config.Padding      = 1.05   -- Rand um das Fahrzeug (1.0 = knapp)
Config.CaptureDelay = 800    -- ms warten, bis Texturen/LODs geladen sind

---------------------------------------------------------------------
-- Beste Bildqualität
---------------------------------------------------------------------
-- Die Bildgröße ist immer deine Spielauflösung. Für die besten Fotos:
-- Vollbild in der höchsten Auflösung, Grafik auf Maximum (siehe Anleitung).
Config.HighQuality = {
    enabled       = true,
    fov           = 30.0,   -- engere Brennweite wie bei Profi-Autofotos (ersetzt Config.FOV)
    lodScale      = 2.0,    -- höhere Detailstufe der Umgebung und Modelle während der Aufnahme
    lodMultiplier = 3.0,    -- Fahrzeug immer in voller Detailstufe
    textureWait   = 1500,   -- ms extra vor dem ersten Foto jedes Fahrzeugs (Texturen laden)
    perfectCar    = true,   -- Fahrzeug repariert, ohne Dellen, sauber
    hideFeed      = true,   -- GTA-Benachrichtigungen während der Aufnahme ausblenden
    dof           = false,  -- Hintergrund leicht unscharf (Tiefenschärfe), Fahrzeug bleibt scharf
    dofStrength   = 0.6,    -- 0.0 – 1.0
}

-- yaw: 0 = von vorne, -90 = linke Seite (Fahrerseite), 180 = von hinten
-- pitch: Kamerahöhe in Grad, zoom: individueller Zoomfaktor
Config.Angles = {
    { name = 'front34', label = 'Vorne 3/4',  yaw = -35.0,  pitch = 8.0, zoom = 1.0 },
    { name = 'side',    label = 'Seite',      yaw = -90.0,  pitch = 4.0, zoom = 1.0 },
    { name = 'rear34',  label = 'Hinten 3/4', yaw = -145.0, pitch = 8.0, zoom = 1.0 },
    { name = 'front',   label = 'Vorne',      yaw = 0.0,    pitch = 5.0, zoom = 0.8 },
    { name = 'rear',    label = 'Hinten',     yaw = 180.0,  pitch = 5.0, zoom = 0.8 },
}

-- Hauptbild wird als <model>.png gespeichert, alle anderen als <model>_<winkel>.png
Config.MainAngle   = 'front34'
-- Welche Winkel /photoall bzw. LEERTASTE pro Fahrzeug aufnimmt
Config.BatchAngles = { 'front34', 'side', 'rear34' }

---------------------------------------------------------------------
-- Fahrzeug-Look
---------------------------------------------------------------------
Config.Plate = 'STUDIO'

-- Lackfarben (im Studio mit G / SHIFT+G wechseln)
-- Der ERSTE Eintrag ist die Katalogfarbe -> Dateiname ohne Farbzusatz (adder.png)
-- Alle anderen bekommen den Namen angehängt (adder_schwarz.png, adder_schwarz_side.png)
-- paint: 0 normal, 1 metallic, 2 perl, 3 matt, 4 metall, 5 chrom
-- original = true -> Werksfarbe des Modells
Config.Colors = {
    { name = 'weiss',    label = 'Weiß',          r = 235, g = 235, b = 235, paint = 1 },
    { name = 'original', label = 'Werksfarbe',    original = true },
    { name = 'schwarz',  label = 'Schwarz',       r = 12,  g = 12,  b = 14,  paint = 1 },
    { name = 'silber',   label = 'Silber',        r = 165, g = 168, b = 172, paint = 1 },
    { name = 'rot',      label = 'Rot',           r = 170, g = 12,  b = 16,  paint = 1 },
    { name = 'blau',     label = 'Blau',          r = 18,  g = 52,  b = 140, paint = 1 },
    { name = 'gelb',     label = 'Gelb',          r = 235, g = 185, b = 10,  paint = 0 },
    { name = 'gruen',    label = 'British Green', r = 18,  g = 60,  b = 38,  paint = 1 },
    { name = 'mattgrau', label = 'Matt Grau',     r = 70,  g = 72,  b = 76,  paint = 3 },
    { name = 'chrom',    label = 'Chrom',         r = 200, g = 200, b = 200, paint = 5 },
    -- zweifarbig: r2/g2/b2 = Sekundärfarbe
    -- { name = 'weissblau', label = 'Weiß/Blau', r = 235, g = 235, b = 235, r2 = 18, g2 = 52, b2 = 140, paint = 1 },
}

-- Welche Farben /photoall pro Fahrzeug fotografiert (leer = nur die aktuell gewählte)
Config.BatchColors = { 'weiss' }

-- Bildfilter (im Studio mit H / SHIFT+H wechseln) – Timecycle-Modifier von GTA
-- Wirkt sich direkt auf den Screenshot aus. Falls einer nichts tut: Namen tauschen.
Config.Filters = {
    { label = 'Kein Filter' },
    { label = 'Kino',          modifier = 'cinema',             strength = 0.6 },
    { label = 'Film warm',     modifier = 'NG_filmic04',        strength = 0.8 },
    { label = 'Film kühl',     modifier = 'NG_filmic07',        strength = 0.8 },
    { label = 'Film kontrast', modifier = 'NG_filmic11',        strength = 0.8 },
    { label = 'Film soft',     modifier = 'NG_filmic20',        strength = 0.8 },
    { label = 'Schwarz-Weiß',  modifier = 'MP_corona_heist_BW', strength = 1.0 },
}
Config.DefaultFilter = 1

---------------------------------------------------------------------
-- Ausgabe
---------------------------------------------------------------------
Config.Encoding = 'png'      -- 'png' = verlustfrei (beste Qualität) | 'webp' | 'jpg'
Config.Quality  = 1.0        -- nur für jpg/webp: 1.0 = beste Qualität, 0.92 = kleinere Dateien

-- Speicherort der Bilder
-- 'local'      = nur in vehicle-photostudio/images/
-- 'fivemanage' = nur auf Fivemanage hochladen
-- 'both'       = beides
-- Den API-Token NICHT hier eintragen, sondern in der server.cfg:
--   set fivemanage_token "DEIN_TOKEN"
-- ('set' statt 'setr', damit er nicht an Clients geht)
Config.Upload = {
    mode        = 'both',
    tokenConvar = 'fivemanage_token',
    path        = 'vehicles',   -- Ordner auf Fivemanage (wird automatisch angelegt)
}

---------------------------------------------------------------------
-- Discord-Webhook (Bilder als Embed in einen Kanal posten)
---------------------------------------------------------------------
-- Die Webhook-URLs gehören in die server.cfg, NICHT hierher:
--   set vps_webhook_catalog "https://discord.com/api/webhooks/..."
--   set vps_webhook_player  "https://discord.com/api/webhooks/..."
-- Willst du alles in einen Kanal: beide auf dieselbe URL setzen.
-- Ist eine Convar leer, wird für diesen Bereich nichts gepostet.
Config.Discord = {
    enabled       = true,
    catalogConvar = 'vps_webhook_catalog',
    playerConvar  = 'vps_webhook_player',
    username      = 'Vehicle Photo Studio',
    -- Avatar: assets/avatar.png liegt bei. Discord braucht eine öffentliche Bild-URL,
    -- z.B. nach Upload auf Fivemanage oder deinen Webspace. Bei nil wird das Bild
    -- genommen, das du in Discord beim Webhook selbst hochgeladen hast.
    avatar        = nil,
    color         = 2055128,      -- Embed-Farbe als Zahl (0x1F5BD8)

    catalog = {
        enabled = true,
        angles  = { 'front34' },  -- nur diese Winkel posten (nil = alle)
        batch   = false,          -- auch bei /photoall posten? (viele Fahrzeuge = viele Posts)
    },
    player = {
        enabled   = true,
        angles    = nil,          -- nil = alle Winkel
        showOwner = true,         -- Name des Besitzers anzeigen
    },
}

-- /photoall überspringt Fahrzeuge, die schon ein Hauptbild haben
Config.SkipExisting = true

---------------------------------------------------------------------
-- Eigene Fahrzeuge (Addon-Cars)
---------------------------------------------------------------------
-- true  = /photostudio und /photoall zeigen NUR eigene Fahrzeuge
--         (/photoall all = trotzdem alle, /photoall sports = nur eigene der Kategorie)
-- false = alle Fahrzeuge aus qb-core/shared/vehicles.lua + eigene
Config.OnlyCustom = true

-- Automatische Erkennung: liest die vehicles.meta aller gestarteten Resourcen
-- (über 'data_file VEHICLE_METADATA_FILE' im fxmanifest). Neu scannen: /vpsscan
Config.AutoDetect = {
    enabled   = true,
    resources = {},   -- leer = alle Resourcen, sonst z.B. { 'meine-autos', 'carpack1' }
    ignore    = {},   -- Resourcen, die NICHT als eigene Fahrzeuge zählen
}

-- Manuell eintragen: für Car-Packs mit Wildcard-Pfaden ('data/**/vehicles.meta'),
-- oder für Autos, die nicht in qb-core/shared/vehicles.lua stehen.
-- Einfach den Spawn-Namen oder eine Tabelle mit Infos (überschreibt alles andere):
Config.CustomVehicles = {
    -- 'meinauto',
    -- { model = 'wdm_gt', name = 'GT Coupé', brand = 'Weigelt', category = 'sports', price = 250000 },
}

-- Einstellungen pro Fahrzeug (Spawn-Name klein geschrieben)
--   zoom     = Kamera-Abstand (1.0 normal, 1.2 = weiter weg)
--   yaw      = Kamerawinkel zusätzlich drehen (Grad)
--   pitch    = Kamerahöhe zusätzlich (Grad)
--   height   = Blickpunkt höher/tiefer (Meter)
--   delay    = zusätzliche Wartezeit vor dem Foto (ms), z.B. bei 4K-Texturen
--   livery   = Livery-Index        roofLivery = Dach-Livery
--   extras   = { [1] = true, [2] = false }  (an/aus)
--   mods     = { [0] = 1, [48] = 2 }        (Modtyp = Index, z.B. Spoiler, Livery-Mod)
--   tint     = Scheibentönung 0-6
--   color    = fest eine Farbe aus Config.Colors (z.B. 'schwarz'), überschreibt G
Config.VehicleOverrides = {
    -- wdm_gt   = { zoom = 1.1, livery = 2, extras = { [1] = true, [2] = false } },
    -- bigtruck = { zoom = 1.3, pitch = 5.0, delay = 1500 },
}

-- Addon-Fahrzeuge laden länger
Config.ModelLoadTimeout  = 20000 -- ms
Config.CustomExtraDelay  = 1000  -- ms extra vor dem ersten Foto eines eigenen Fahrzeugs

---------------------------------------------------------------------
-- Persönliche Fahrzeuge der Spieler (aus player_vehicles, mit Tuning)
---------------------------------------------------------------------
-- Bilder gehen IMMER zu Fivemanage (Token muss gesetzt sein) und werden
-- in der Tabelle 'vehicle_photos' gespeichert (wird automatisch angelegt).
-- Abrufbar per Export, z.B. fürs Auktionshaus:
--   exports['vehicle-photostudio']:GetVehiclePhoto(plate)          -> URL Hauptbild
--   exports['vehicle-photostudio']:GetVehiclePhotos(plate)         -> { front34 = url, side = url, ... }
Config.PlayerStudio = {
    enabled    = true,
    command    = 'fotostudio',         -- Spieler: eigene Fahrzeuge fotografieren
    adminCommand = 'photoplayer',      -- Admin: /photoplayer [id] Fahrzeuge eines Spielers fotografieren
    permission = nil,                  -- nil = jeder Spieler, sonst z.B. 'admin'

    -- Nur an bestimmten Eingängen nutzbar (leer = überall)
    -- studio = an welchem Studio-Ort fotografiert wird (name aus Config.Studios)
    -- Feste Orte (Eingänge). Hier steht ein Marker oder NPC mit Menü:
    -- Fahrzeug fotografieren / Meine Fotos / (Admin) Katalog-Studio / Fahrzeugkatalog.
    -- Steht hier mindestens ein Ort, geht /fotostudio nur noch dort (ausser "hier", siehe unten).
    --   coords  = Punkt zum Interagieren      radius = Bereich, in dem /fotostudio erlaubt ist
    --   studio  = an welchem Studio-Ort fotografiert wird (name aus Config.Studios)
    --   blip    = Kartensymbol (false = keins)
    --   ped     = NPC-Modell am Punkt (nil = nur Marker)   heading = Blickrichtung des NPC
    --   menu    = welche Einträge das Menü zeigt
    locations = {
        {
            label   = 'Fotostudio',
            coords  = vector3(-56.5, -1096.8, 26.4),   -- Beispiel beim Autohaus – mit /vpspos anpassen
            radius  = 15.0,
            studio  = nil,                            -- nil = Config.DefaultStudio
            blip    = { sprite = 225, color = 3, scale = 0.7 },
            ped     = 'a_m_y_business_02',
            heading = 70.0,
            menu    = { studio = true, gallery = true, admin = true },
        },
    },
    -- Welche Studio-Orte Spieler mit B wechseln dürfen
    -- nil = alle, {} = keiner (bleibt am Ort des Eingangs), oder z.B. { 'Garage', 'Hangar' }
    studios    = nil,
    -- Spieler dürfen am aktuellen Standort fotografieren (/fotostudio hier oder B)
    allowHere  = true,
    -- true = /fotostudio hier geht überall, auch weit weg von einem Eingang
    -- false = auch "hier" nur an den Eingängen aus locations
    hereAnywhere = true,

    price      = 0,                    -- Kosten pro Studio-Besuch
    account    = 'bank',               -- 'cash' | 'bank'

    angles     = { 'front34', 'side', 'rear34' }, -- erlaubte Winkel (LEERTASTE = alle)
    maxPhotos  = 12,                   -- Fotos pro Besuch
    cooldown   = 3,                    -- Sekunden zwischen zwei Fotos
    onlyInGarage = false,              -- true = nur Fahrzeuge, die eingeparkt sind (state = 1)
    filters    = true,                 -- Spieler dürfen Filter (H) nutzen
    path       = 'player-vehicles',    -- Ordner auf Fivemanage
    deleteOld  = true,                 -- altes Bild auf Fivemanage löschen, wenn neu fotografiert
}

---------------------------------------------------------------------
-- Interaktion an den festen Orten (Config.PlayerStudio.locations)
---------------------------------------------------------------------
Config.Points = {
    useTarget   = true,     -- qb-target nutzen, wenn gestartet (sonst Marker + E)
    targetName  = 'qb-target',
    distance    = 2.0,      -- Abstand für E bzw. qb-target
    drawMarker  = true,     -- Marker am Boden zeigen (nur ohne qb-target)
    markerColor = { r = 110, g = 155, b = 255, a = 150 },
}

---------------------------------------------------------------------
-- Galerie (Bilder ansehen)
---------------------------------------------------------------------
-- /meinefotos  -> Spieler: eigene Fahrzeuge mit allen Fotos (überall nutzbar)
-- /fotokatalog -> Admin: alle Katalogbilder, inkl. Fahrzeuge ohne Foto
-- Im Studio: TAB öffnet die passende Galerie
Config.Gallery = {
    enabled       = true,
    playerCommand = 'meinefotos',
    adminCommand  = 'fotokatalog',
    studioKey     = true,   -- TAB im Studio
    playerDelete  = true,   -- Spieler dürfen eigene Fotos löschen
    adminDelete   = true,   -- Admins dürfen Katalogbilder löschen
}

-- Kategorien, die /photoall ohne Argument ignoriert
Config.ExcludeCategories = {
    emergency = true,
    military  = true,
    service   = true,
    trains    = true,
}

---------------------------------------------------------------------
-- Hooks (Client) – z.B. eigenes HUD / andere NUI ausblenden,
-- denn alles was als NUI auf dem Bildschirm ist, landet im Foto!
---------------------------------------------------------------------
Config.OnEnter = function()
    -- TriggerEvent('dein-hud:toggle', false)
end

Config.OnExit = function()
    -- TriggerEvent('dein-hud:toggle', true)
end
