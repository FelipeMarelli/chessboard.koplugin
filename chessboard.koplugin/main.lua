-- Plugin entry point: menu entry, life cycle and the link between the reader and the window.
--
-- Copyright (C) 2026 Felipe Marelli
-- Licensed under the GNU Affero General Public License, version 3: see LICENSE.
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

-- Edge swipes of the Gestures plugin; each comes with a "_pan" and a "_pan_release" zone.
local EDGE_SWIPES = {
    "left_edge_down", "left_edge_up", "right_edge_down", "right_edge_up",
    "top_edge_right", "top_edge_left", "bottom_edge_right", "bottom_edge_left",
}

local function edge_zones(suffix)
    local ids = {}
    for _, edge in ipairs(EDGE_SWIPES) do
        ids[#ids + 1] = "one_finger_swipe_" .. edge .. suffix
    end
    return ids
end

local function join(...)
    local all = {}
    for _, list in ipairs({ ... }) do
        for _, id in ipairs(list) do
            all[#all + 1] = id
        end
    end
    return all
end

-- The gestures a drag is made of, with the reader and Gestures plugin zones that the window has
-- to come before, so that a drag that starts on the window does not turn the page or select text.
local DRAG_OVERRIDES = {
    touch = { "inertial_scrolling_touch" },
    hold ={ "readerhighlight_hold", "readerfooter_hold", "hold_top_left_corner",
        "hold_top_right_corner", "hold_bottom_left_corner", "hold_bottom_right_corner" },
    hold_pan = { "readerhighlight_hold_pan" },
    hold_release = { "readerhighlight_hold_release" },
    pan = join({ "paging_pan", "rolling_pan", "readermenu_pan", "readermenu_ext_pan",
        "readerconfigmenu_pan", "readerconfigmenu_ext_pan" }, edge_zones("_pan")),
    pan_release = join({ "paging_pan_release", "rolling_pan_release" },
        edge_zones("_pan_release")),
    swipe = join({ "paging_swipe", "rolling_swipe", "swipe_link", "readermenu_swipe",
        "readermenu_ext_swipe", "readerconfigmenu_swipe", "readerconfigmenu_ext_swipe",
        "short_diagonal_swipe" }, edge_zones("")),
    multiswipe = { "multiswipe" },
}

-- A reader touch zone over the whole screen for one gesture, that comes before the given zones.
-- The window lets through what is not on it.
local function touch_zone(ges, overrides, handler)
    return {
        id = "chessboard_" .. ges,
        ges = ges,
        screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
        overrides = overrides,
        handler = handler,
    }
end

local ChessBoard = WidgetContainer:extend{
    name = "chessboard",
    is_doc_only = true,
}

function ChessBoard:init()
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

function ChessBoard:addToMainMenu(menu_items)
    menu_items.chessboard = {
        text = I18n.t("Chess board"),
        sorting_hint = "tools",
        checked_func = function() return self.layout:isOpen() end,
        callback = function() self:toggle() end,
    }
end

function ChessBoard:onReaderReady()
    self.window = Window.new(self.view, self.layout, self.session)
    self.view:registerViewModule("chessboard", self)
    local zones = { touch_zone("tap", TAP_OVERRIDES, function(ges) return self:onTap(ges) end) }
    for ges, overrides in pairs(DRAG_OVERRIDES) do
        zones[#zones + 1] = touch_zone(ges, overrides, function(g) return self:onDrag(g) end)
    end
    self.ui:registerTouchZones(zones)
    if os.getenv("CHESSBOARD_SELFTEST") then
        self.selftest = require("selftest").start(self)
    end
end

function ChessBoard:toggle()
    if self.window then
        self.window:toggle()
    end
end

-- A failure of the plugin must not stop the reading: log it and close the window.
function ChessBoard:guard(what, fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    logger.err("chessboard:", what, "failed:", result)
    pcall(self.layout.setOpen, self.layout, false)
    return false
end

function ChessBoard:onTap(ges)
    return self:guard("tap", self.window.onTap, self.window, ges)
end

function ChessBoard:onDrag(ges)
    return self:guard("drag", self.window.onDrag, self.window, ges)
end

-- Called by ReaderView after it paints the page.
function ChessBoard:paintTo(bb)
    self:guard("paint", self.window.paintTo, self.window, bb)
end

-- Called by ReaderView when the screen turns or changes size.
function ChessBoard:resetLayout()
    self.layout:setScreen(Screen:getWidth(), Screen:getHeight())
end

function ChessBoard:onCloseDocument()
    if self.selftest then
        self.selftest:stop()
    end
    Theme.free()
end

return ChessBoard
