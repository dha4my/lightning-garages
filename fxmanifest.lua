fx_version 'cerulean'
game 'gta5'

description 'lightning-garages'
version '1.0.0'
author 'JDev & Lightning Development'

shared_scripts {
    'config.lua',
    '@qb-core/shared/locale.lua',
    'locales/en.lua',
    'locales/*.lua'
}

client_scripts {
    '@PolyZone/client.lua',
    '@PolyZone/BoxZone.lua',
    '@PolyZone/EntityZone.lua',
    '@PolyZone/CircleZone.lua',
    '@PolyZone/ComboZone.lua',
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

ui_page {
	'web/index.html',
}

files {
    'web/index.html',
    'web/style.css',
    'web/script.js',
    'web/bg.png',
    'web/car.png'
}


dependencies {
    'lightning-interaction'
}

lua54 'yes'
