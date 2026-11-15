-- Plugin entry point: menu entry, life cycle and the link between the reader and the window.
local Device = require("device")
local Game = require("chess/game")
local I18n = require("i18n")
local Layout = require("model/layout")
local Session = require("model/session")
local Theme = require("ui/theme")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Window = require("ui/window")
local logger = require("logger")

local Screen = Device.screen

-- Reader tap zones that the window has to come before.
local TAP_OVERRIDES = {
    "tap_link", "readerhighlight_tap", "readerhighlight_tap_select_mode",
    "readerfooter_tap", "readermenu_tap", "readermenu_ext_tap",
    "readerconfigmenu_tap", "readerconfigmenu_ext_tap",
    "tap_forward", "tap_backward", "inertial_scrolling_tap",
}

local ChessBook = WidgetContainer:extend{
    name = "chessbook",
    is_doc_only = true,
}

function ChessBook:init()
    Theme.setPluginDir(self.path)
    self.layout = Layout.new{
        screen_w = Screen:getWidth(),
        screen_h = Screen:getHeight(),
        px_per_mm = Theme.pxPerMm(),
        sizes = Theme.SIZES,
    }
    self.session = Session.new(assert(Game.new()))
    self.ui.menu:registerToMainMenu(self)
end

function ChessBook:addToMainMenu(menu_items)
    menu_items.chessbook = {
        text = I18n.t("Chess board"),
        sorting_hint = "more_tools",
        checked_func = function() return self.layout:isOpen() end,
        callback = function() self:toggle() end,
    }
end

function ChessBook:onReaderReady()
    self.window = Window.new(self.view, self.layout, self.session)
    self.view:registerViewModule("chessbook", self)
    self.ui:registerTouchZones({
        {
            id = "chessbook_tap",
            ges = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            overrides = TAP_OVERRIDES,
            handler = function(ges) return self:onTap(ges) end,
        },
    })
    if os.getenv("CHESSBOOK_SELFTEST") then
        self.selftest = require("selftest").start(self)
    end
end

function ChessBook:toggle()
    if self.window then
        self.window:toggle()
    end
end

-- A failure of the plugin must not stop the reading: log it and close the window.
function ChessBook:guard(what, fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    logger.err("chessbook:", what, "failed:", result)
    pcall(self.layout.setOpen, self.layout, false)
    return false
end

function ChessBook:onTap(ges)
    return self:guard("tap", self.window.onTap, self.window, ges)
end

-- Called by ReaderView after it paints the page.
function ChessBook:paintTo(bb)
    self:guard("paint", self.window.paintTo, self.window, bb)
end

-- Called by ReaderView when the screen turns or changes size.
function ChessBook:resetLayout()
    self.layout:setScreen(Screen:getWidth(), Screen:getHeight())
end

function ChessBook:onCloseDocument()
    if self.selftest then
        self.selftest:stop()
    end
    Theme.free()
end

return ChessBook
