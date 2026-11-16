-- Translatable texts: our own translations first, then KOReader's, then the English text.
local GetText = require("gettext")

local I18n = {}

local loaded = {}

-- The table of a language, "es" for "es_AR" too; an empty one when there is none.
local function table_for(lang)
    local short = (lang or "C"):match("^(%a%a)") or "C"
    if loaded[short] == nil then
        local ok, texts = pcall(require, "l10n/" .. short)
        loaded[short] = ok and type(texts) == "table" and texts or false
    end
    return loaded[short] or {}
end

function I18n.t(text)
    local own = table_for(GetText.current_lang)[text]
    if own then
        return own
    end
    return GetText(text)
end

return I18n
