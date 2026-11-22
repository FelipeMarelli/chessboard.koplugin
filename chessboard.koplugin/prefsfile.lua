-- The plugin's own preferences file, in KOReader's settings folder: the choices kept across books
-- (model/preferences.lua). Not KOReader's global settings, nor a book's.
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local PrefsFile = {}

local FILE = "chessboard.lua"
local KEY = "preferences"

local function open()
    return LuaSettings:open(DataStorage:getSettingsDir() .. "/" .. FILE)
end

-- The table saved last, or nil when there is none.
function PrefsFile.read()
    return open():readSetting(KEY)
end

function PrefsFile.write(preferences)
    local settings = open()
    settings:saveSetting(KEY, preferences)
    settings:flush()
end

return PrefsFile
