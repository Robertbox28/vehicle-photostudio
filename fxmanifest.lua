fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vehicle-photostudio'
description 'Vehicle Photo Studio für QBCore – Katalogbilder aller Fahrzeuge per Knopfdruck'
version '1.4.0'

shared_script 'config.lua'
client_scripts {
    'client.lua',
    'client_points.lua',
}
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.js',
    'server.lua',
    'server_player.lua',
    'server_gallery.lua',
}

ui_page 'html/index.html'
files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

dependencies {
    'qb-core',
    'oxmysql',
    'screenshot-basic'
}
