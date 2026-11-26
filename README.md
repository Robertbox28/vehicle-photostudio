# Vehicle Photo Studio (QBCore)

Erstellt einheitliche Katalogbilder deiner Fahrzeuge – einzeln mit freier Kamera oder vollautomatisch für alle Fahrzeuge aus `QBCore.Shared.Vehicles`.

## Voraussetzungen
- `qb-core`
- `screenshot-basic` (citizenfx/screenshot-basic)

## Installation
1. Ordner `vehicle-photostudio` nach `resources/[standalone]/` kopieren
2. In der `server.cfg` **nach** qb-core und screenshot-basic: `ensure vehicle-photostudio`
3. Studio-Orte prüfen: an einem freien Platz `/vpspos` eingeben und die Zeile aus der F8-Konsole in `Config.Studios` einfügen

## Befehle (Admin)
| Befehl | Funktion |
|---|---|
| `/photostudio [model]` | Studio öffnen, freie Kamera, Fahrzeuge durchblättern |
| `/photoall [kategorie]` | Serienaufnahme aller (oder einer Kategorie) – Einsatz-/Militärfahrzeuge werden standardmäßig übersprungen |
| `/vpspos` | Fertige Zeile für einen neuen Studio-Ort in der F8-Konsole ausgeben |
| `/vpsorte` | Alle Studio-Orte anzeigen |

### Steuerung im Studio
←/→ Winkel · ↑/↓ Zoom · Q/E drehen · R/F Kamerahöhe · X Reset · Bild↑/Bild↓ Fahrzeug wechseln
G Lackfarbe · H Bildfilter (SHIFT+G / SHIFT+H rückwärts) – Farben & Filter in `Config.Colors` / `Config.Filters`
ENTER Foto · LEERTASTE alle Winkel aus `Config.BatchAngles` · BACKSPACE beenden/abbrechen

## Ausgabe
Alles landet in `vehicle-photostudio/images/`:
- `adder.png` – Hauptbild (`Config.MainAngle`)
- `adder_side.png`, `adder_rear34.png` – weitere Winkel
- `index.json` – Name, Marke, Kategorie, Preis und Bilddateien pro Fahrzeug (direkt für Website/Katalog nutzbar)

Den Ordner kannst du einfach auf deinen Webspace kopieren.

## Studio-Orte
- Beliebig viele Orte in `Config.Studios`, Start-Ort `Config.DefaultStudio`
- Im Studio mit **B** wechseln (SHIFT+B rückwärts)
- Per Befehl: `/photostudio adder himmel`, `/photostudio himmel`, `/photoall sports himmel`, `/photoall himmel`
- Pro Ort eigene Uhrzeit (`time`) und eigenes Wetter (`weather`)
- `suffix = true` hängt den Ortsnamen an den Dateinamen (`adder_himmel.png`)
- Spieler: pro Eingang `studio = 'name'` in `Config.PlayerStudio.locations`, Auswahl mit `Config.PlayerStudio.studios` einschränken
- **Aktueller Standort:** Ort `hier` – Fahrzeug erscheint dort, wo du stehst, mit echter Uhrzeit und echtem Wetter (`Config.HereStudio`). `/photostudio adder hier`, `/photoall sports hier`, Spieler: `/fotostudio hier` (`allowHere`, `hereAnywhere`)

## Eigene Fahrzeuge (Addon-Cars)
- `Config.OnlyCustom = true` → Studio und `/photoall` zeigen nur eigene Fahrzeuge
- Erkennung automatisch über die `vehicles.meta` aller gestarteten Resourcen (`data_file 'VEHICLE_METADATA_FILE'`)
- Car-Packs mit Wildcard-Pfaden (`data/**/vehicles.meta`) werden in der Serverkonsole gelistet → Modelle in `Config.CustomVehicles` eintragen
- `/vpsscan` erkennt neu und listet alle eigenen Modelle in der Serverkonsole
- `/photoall custom` = nur eigene · `/photoall all` = alle · `/photoall sports` = Kategorie
- Pro Fahrzeug Kamera, Livery, Extras, Mods, Tönung und feste Farbe über `Config.VehicleOverrides`
- Name/Marke/Preis: zuerst `Config.CustomVehicles`, dann `qb-core/shared/vehicles.lua`, dann `gameName`/`vehicleMakeName` aus der vehicles.meta

## Persönliche Fahrzeuge der Spieler
Benötigt `oxmysql` und einen Fivemanage-Token.
- `/fotostudio` – Spieler fotografiert seine eigenen Autos aus `player_vehicles`, mit seinem Tuning, Lack und Kennzeichen
- `/photoplayer [id]` – Admin fotografiert die Autos eines Spielers (ohne Limits/Kosten)
- Öffnen per qb-target/Ped: `TriggerServerEvent('vehicle-photostudio:server:openPlayer')`
- Ort, Preis, erlaubte Winkel, Foto-Limit, Cooldown in `Config.PlayerStudio`
- Bilder: Fivemanage-Ordner `player-vehicles/KENNZEICHEN_winkel.webp`, Links in Tabelle `vehicle_photos` (wird automatisch angelegt). Neues Foto ersetzt das alte (auch auf Fivemanage).

Für andere Resourcen (Auktionshaus, Garage, Handy):
```lua
-- Server
local url    = exports['vehicle-photostudio']:GetVehiclePhoto(plate)          -- Hauptbild
local side   = exports['vehicle-photostudio']:GetVehiclePhoto(plate, 'side')
local photos = exports['vehicle-photostudio']:GetVehiclePhotos(plate)         -- { front34 = url, ... }

AddEventHandler('vehicle-photostudio:server:photoTaken', function(src, data)
    -- data.citizenid, data.plate, data.model, data.angle, data.url
end)

-- Client
QBCore.Functions.TriggerCallback('vehicle-photostudio:server:getPhotos', function(photos) end, plate)
```

## Feste Orte (Studio / Galerie per Menü)
- Einträge in `Config.PlayerStudio.locations` mit Kartensymbol (`blip`), NPC (`ped`) oder Marker
- Menü: Fahrzeug fotografieren, Meine Fotos, (Admin) Katalog-Studio, Fahrzeugkatalog – pro Ort mit `menu` ein-/ausblendbar
- qb-target wird genutzt, wenn gestartet (`Config.Points`), sonst Marker + E
- Ein Beispiel-Ort beim Autohaus ist eingetragen (Koordinaten ungetestet). Solange ein Ort eingetragen ist, geht `/fotostudio` nur dort; `locations = {}` macht es wieder überall möglich.

## Galerie
- `/meinefotos` – Spieler sehen ihre Fahrzeuge mit allen Fotos (auch ohne Foto), überall
- `/fotokatalog` – Admins sehen alle Katalogbilder, inkl. Fahrzeuge ohne Foto, mit „Jetzt fotografieren“
- **TAB** im Studio öffnet die passende Galerie
- Suchen, Filter (mit/ohne Foto, Kategorie), große Ansicht aller Winkel, Link kopieren, Löschen
- Einstellungen in `Config.Gallery`. Lokal gespeicherte Bilder werden einzeln nachgeladen – mit Fivemanage ist die Galerie schneller.

## Discord-Webhook
In die `server.cfg` (mit `set`, URL geheim halten):
```
set vps_webhook_catalog "https://discord.com/api/webhooks/..."
set vps_webhook_player  "https://discord.com/api/webhooks/..."
```
Jedes Foto wird als Embed mit Bild gepostet. Einstellungen in `Config.Discord`: welche Winkel, ob auch bei `/photoall`, Besitzername anzeigen. Ohne Fivemanage wird das Bild direkt als Anhang an Discord geschickt.

## Fivemanage
1. Auf fivemanage.com einen API-Token erstellen
2. In die `server.cfg` (mit `set`, nicht `setr`!):
   ```
   set fivemanage_token "DEIN_TOKEN"
   ```
3. `Config.Upload.mode` auf `'fivemanage'` oder `'both'` stellen
4. Die URLs stehen danach in `images/index.json` (`imageUrl`, `urls`, `ids`) und in der Serverkonsole.

Tipp: `Config.Encoding = 'webp'` spart viel Speicherplatz auf Fivemanage.

## Beste Bildqualität
- `Config.HighQuality` ist standardmäßig an: Brennweite 30, höhere Detailstufe, volle Fahrzeug-Details, extra Wartezeit für Texturen, Fahrzeug repariert und sauber, GTA-Benachrichtigungen aus
- `Config.Encoding = 'png'` (verlustfrei) und `Config.Quality = 1.0`
- Optional `dof = true` für einen leicht unscharfen Hintergrund (vorher testen)
- Im Spiel: höchste Auflösung im Vollbild, Texturen/Shader/Reflexionen auf Maximum, Kantenglättung an, Bewegungsunschärfe aus – das Foto ist so groß wie dein Spielbild

## Tipps für saubere Bilder
- Bildgröße = deine Spielauflösung. Für Katalogbilder 1920×1080 oder höher, Grafik auf Ultra.
- Alles, was als NUI auf dem Bildschirm liegt (HUD, Chat, Notifys), ist im Foto. HUD über `Config.OnEnter/OnExit` ausblenden, Chat vorher ausblenden lassen.
- Der Ort `himmel` ergibt fast reinen Himmel als Hintergrund – ideal, wenn du die Autos später freistellen willst.
- Erneut fotografieren: `Config.SkipExisting = false` oder den Eintrag aus `index.json` löschen.

---
Autor: Robertbox28 · robertbox28.ch · Für Culture City
