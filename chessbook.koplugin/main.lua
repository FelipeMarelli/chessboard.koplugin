-- Plugin entry point. It only registers the plugin for now; the floating board arrives with H03.
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local ChessBook = WidgetContainer:extend{
    name = "chessbook",
    is_doc_only = true,
}

return ChessBook
