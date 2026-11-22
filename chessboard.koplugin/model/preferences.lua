-- The choices kept across books, in the plugin's own preferences file: the window split or
-- floating and its size (Layout:preferences), and the window drawn dark or light. A plain table,
-- to save and to read back.
local Preferences = {}

Preferences.VERSION = 1

-- The choices of a layout and a session, to save.
function Preferences.of(layout, session)
    return {
        version = Preferences.VERSION,
        window = layout:preferences(),
        dark = session:isDark(),
    }
end

-- Takes up on a new layout and session the choices of a table of Preferences.of; nil (nothing
-- saved yet) leaves them as they are. -> true | nil, warning when the table is not understood.
function Preferences.apply(prefs, layout, session)
    if prefs == nil then
        return true
    end
    if type(prefs) ~= "table" or prefs.version ~= Preferences.VERSION then
        return nil, "preferences not understood: " .. tostring(type(prefs) == "table"
            and prefs.version or prefs)
    end
    if type(prefs.window) == "table" then
        layout:usePreferences(prefs.window)
    end
    if type(prefs.dark) == "boolean" and prefs.dark ~= session:isDark() then
        session:toggleDark()
    end
    return true
end

return Preferences
