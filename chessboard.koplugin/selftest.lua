-- Scripted run of the window with synthetic taps, for the emulator. Only runs when the variable
-- CHESSBOARD_SELFTEST is set.
--
--   CHESSBOARD_SELFTEST=1 [CHESSBOARD_SCENARIO=h03] [CHESSBOARD_PAGE=30] ./run-emu.sh book
--
-- Each scenario taps, checks the state and saves screenshots in emu-data/chessboard/. The result
-- goes to emu-data/chessboard/selftest.txt, one PASS or FAIL line per check.
local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local dump = require("dump")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local Screen = Device.screen

local STEP_SECONDS = 0.6

local SelfTest = {}
SelfTest.__index = SelfTest

-- "h" or "v", for the names of the images.
local function orientation()
    return Screen:getWidth() > Screen:getHeight() and "h" or "v"
end

-- Saves the screen as it is now.
function SelfTest:save(name)
    self.shots = self.shots + 1
    Screen.bb:writePNG(string.format("%s/%s_%s_%02d_%s.png", self.dir, self.scenario,
        orientation(), self.shots, name))
end

function SelfTest:shot(name)
    -- Paint what is pending first: setDirty only paints on a later turn of the event loop.
    UIManager:forceRePaint()
    self:save(name)
end

local function center(rect)
    return { x = rect.x + rect.w / 2, y = rect.y + rect.h / 2 }
end

-- A point of the button row that is on no button: just right of the last button on the left.
local function between_buttons(layout)
    local last_left = layout:buttonRect("split")
    return { x = last_left.x + last_left.w + 2, y = last_left.y + last_left.h / 2 }
end

local function point(p)
    return Geom:new{ x = math.floor(p.x), y = math.floor(p.y), w = 0, h = 0 }
end

local function offset(p, dx, dy)
    return { x = p.x + dx, y = p.y + dy }
end

local function direction(from, to)
    local dx, dy = to.x - from.x, to.y - from.y
    if math.abs(dx) > math.abs(dy) then
        return dx > 0 and "east" or "west"
    end
    return dy > 0 and "south" or "north"
end

local function distance(from, to)
    return math.abs(to.x - from.x) + math.abs(to.y - from.y)
end

function SelfTest:gesture(ges)
    ges.time = 0
    UIManager:sendEvent(Event:new("Gesture", ges))
end

-- The finger goes down at p. KOReader reports it before any other gesture of the finger.
function SelfTest:touch(p)
    self:gesture({ ges = "touch", pos = point(p) })
end

function SelfTest:tap(x, y)
    local p = { x = x, y = y }
    self:touch(p)
    self:gesture({ ges = "tap", pos = point(p) })
end

function SelfTest:tapRect(rect)
    local p = center(rect)
    self:tap(p.x, p.y)
end

-- The gesture that ends a slow drag: its position is where the finger was lifted.
local function slow_lift(kind)
    return function(_, to)
        return { ges = kind, pos = point(to) }
    end
end

-- The gesture that ends a quick drag: its position is where the finger went down. turns: the
-- directions of a multiswipe.
local function quick_lift(kind, turns)
    return function(from, to)
        return { ges = kind, pos = point(from), end_pos = point(to),
            direction = direction(from, to), distance = distance(from, to),
            multiswipe_directions = turns }
    end
end

-- The gestures that end a drag, by how the finger is lifted.
local LIFTS = {
    hold = slow_lift("hold_release"),
    pan_release = slow_lift("pan_release"),
    swipe = quick_lift("swipe"),
    multiswipe = quick_lift("multiswipe", "north east"),
}

-- The middle of a drag, the way KOReader reports it: the finger, already down at from (see
-- SelfTest:touch), moves through the points of via to to, without being lifted. held: it rested
-- before moving.
function SelfTest:press(from, to, held, via)
    if held then
        self:gesture({ ges = "hold", pos = point(from) })
    end
    local path = { unpack(via or {}) }
    path[#path + 1] = to
    for _, p in ipairs(path) do
        self:gesture({ ges = held and "hold_pan" or "pan", start_pos = point(from), pos = point(p),
            relative = { x = p.x - from.x, y = p.y - from.y }, direction = direction(from, p),
            distance = distance(from, p) })
    end
end

-- A finger resting in the middle of rect and lifted there, without moving.
function SelfTest:holdRect(rect)
    local p = center(rect)
    self:touch(p)
    self:gesture({ ges = "hold", pos = point(p) })
    self:lift(p, p, "hold")
end

-- The end of a drag from one point to another: the finger is lifted at to. lift: "pan_release"
-- (a slow drag), "swipe" or "multiswipe" (quick ones) or "hold" (the finger rested before moving).
function SelfTest:lift(from, to, lift)
    self:gesture(LIFTS[lift](from, to))
end

-- A whole drag from one point to another, through the points of via. lift: as for SelfTest:lift.
function SelfTest:drag(from, to, lift, via)
    self:touch(from)
    self:press(from, to, lift == "hold", via)
    self:lift(from, to, lift)
end

function SelfTest:check(name, ok, detail)
    local line = string.format("%s %s %s%s", ok and "PASS" or "FAIL", self.scenario, name,
        detail and (" (" .. tostring(detail) .. ")") or "")
    self.results[#self.results + 1] = line
    if not ok then
        self.failed = true
    end
    logger.info("chessboard selftest:", line)
end

-- Records the regions asked to be repainted, to check that only the window is.
function SelfTest:watchRepaints()
    self.repaints = {}
    local original = UIManager.setDirty
    self.restore_set_dirty = function() UIManager.setDirty = original end
    UIManager.setDirty = function(manager, widget, refresh, region, ...)
        if region then
            self.repaints[#self.repaints + 1] = { x = region.x, y = region.y, w = region.w,
                h = region.h, refresh = refresh }
        else
            self.repaints[#self.repaints + 1] = { full = true, refresh = refresh }
        end
        return original(manager, widget, refresh, region, ...)
    end
end

-- Counts the calls to the handler of a reader touch zone from now on; returns a function that
-- tells how many there were.
function SelfTest:countCalls(ui, zone_id)
    return self:countAllCalls(ui, { zone_id })
end

-- The same, for the calls to the handlers of several zones together.
function SelfTest:countAllCalls(ui, zone_ids)
    local calls = 0
    local wanted = {}
    for _, id in ipairs(zone_ids) do wanted[id] = true end
    for _, zone in ipairs(ui._ordered_touch_zones) do
        if wanted[zone.def.id] then
            local handler = zone.handler
            zone.handler = function(...)
                calls = calls + 1
                return handler(...)
            end
        end
    end
    return function() return calls end
end

-- The steps of a scenario and the function that adds one. The first one goes to the page in
-- CHESSBOARD_PAGE, when it is set.
local function new_steps(plugin)
    local steps = {}
    local function step(fn) steps[#steps + 1] = fn end
    local page = tonumber(os.getenv("CHESSBOARD_PAGE") or "")
    if page then
        step(function() plugin.ui:handleEvent(Event:new("GotoPage", page)) end)
    end
    return steps, step
end

-- A layout whose board has squares of the minimum size: one for a screen just big enough.
function SelfTest:minimumLayout()
    local Layout = require("model/layout")
    local Theme = require("ui/theme")
    local min_px = Theme.px(Theme.SIZES.min_square)
    local side = math.ceil(8 * min_px / 0.6) + 1
    local layout = Layout.new{ screen_w = side, screen_h = side + 2 * Theme.px(Theme.SIZES.row),
        scale = Theme.scale(), sizes = Theme.SIZES }
    layout:setOpen(true)
    return layout
end

-- Shows another layout in the window and paints it at once.
function SelfTest:use(plugin, layout)
    local before = plugin.layout:rects()
    plugin.layout, plugin.window.layout = layout, layout
    plugin.window:refresh(layout:dirtyRect(before))
    UIManager:forceRePaint()
end

-- The page pixels inside a rect, to compare the page before opening and after closing.
local function grab(rect)
    local copy = {}
    local bb = Screen.bb
    for y = rect.y, rect.y + rect.h - 1 do
        for x = rect.x, rect.x + rect.w - 1 do
            copy[#copy + 1] = bb:getPixel(x, y):getColor8().a
        end
    end
    return copy
end

-- How many pixels of a rect, leaving out those inside hole, differ between a copy of the screen
-- and the screen now.
local function changed_outside(copy, rect, hole)
    local count = 0
    for y = rect.y, rect.y + rect.h - 1 do
        for x = rect.x, rect.x + rect.w - 1 do
            local in_hole = x >= hole.x and x < hole.x + hole.w and y >= hole.y
                and y < hole.y + hole.h
            if not in_hole and copy:getPixel(x, y):getColor8().a
                    ~= Screen.bb:getPixel(x, y):getColor8().a then
                count = count + 1
            end
        end
    end
    return count
end

local function differences(a, b)
    local count = 0
    for i = 1, math.max(#a, #b) do
        if a[i] ~= b[i] then
            count = count + 1
        end
    end
    return count
end

local function same_rect(a, b)
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

-- Checks that what was done since the repaints were last forgotten repainted rect once, with
-- that kind of refresh, and nothing else.
function SelfTest:repaintedOnce(name, rect, refresh)
    local r = self.repaints[1]
    self:check(name, #self.repaints == 1 and same_rect(r, rect) and r.refresh == refresh,
        r and string.format("%d repaints, the first %s", #self.repaints, r.refresh) or "none")
end

-- Where the reader is. For EPUB, the position in the text. For PDF and DjVu, the top page and
-- the part of it on screen: in continuous scroll mode (the emulator uses it in landscape) a
-- forward tap scrolls the view, and the page number may stay the same.
local function reading_position(ui)
    if ui.rolling then
        return "pos " .. tostring(ui.document:getCurrentPos())
    end
    local view = ui.view
    local state = view.page_scroll and view.page_states[1]
    if state then
        return string.format("page %d y %d", state.page, state.visible_area.y)
    end
    return string.format("page %d y %d", ui:getCurrentPage(), view.visible_area.y)
end

-- H03: open, flip, tap inside and outside, close.
local function h03(t, plugin)
    local layout, session = plugin.layout, plugin.session
    local steps, step = new_steps(plugin)
    step(function()
        t:shot("page")
        t.page_pixels = grab(layout:rects().window)
        t:watchRepaints()
        plugin:toggle()
    end)
    step(function()
        t:shot("open")
        t:check("opens", layout:isOpen())
        local window = layout:rects().window
        t:check("open repaints only the window", #t.repaints == 1
            and same_rect(t.repaints[1], window))
        t:check("open flashes, to clear the ghost of the text under it",
            t.repaints[1] and t.repaints[1].refresh == "flashui",
            t.repaints[1] and t.repaints[1].refresh)
        t.repaints = {}
        t:tapRect(layout:buttonRect("flip"))
    end)
    step(function()
        t:shot("flipped")
        t:check("flip turns the board", session:flipped())
        t:check("flip repaints only the window", #t.repaints == 1
            and same_rect(t.repaints[1], layout:rects().window))
        t:check("flip does not flash", t.repaints[1] and t.repaints[1].refresh == "ui",
            t.repaints[1] and t.repaints[1].refresh)
        t:tapRect(layout:buttonRect("flip"))
    end)
    step(function()
        t:check("flip again turns it back", not session:flipped())
        t.page_before = plugin.ui:getCurrentPage()
        t.position_before = reading_position(plugin.ui)
        t:tapRect(layout:squareRect(29, false))
        local between = between_buttons(layout)
        t:tap(between.x, between.y)
    end)
    step(function()
        local now = reading_position(plugin.ui)
        t:check("taps inside do not move the reading", now == t.position_before, now)
        t.link_calls = t:countCalls(plugin.ui, "tap_link")
        -- Right of the page, below the top band that opens the reader menu.
        t:tap(Screen:getWidth() * 0.9, Screen:getHeight() * 0.25)
    end)
    step(function()
        t:shot("outside")
        local now = reading_position(plugin.ui)
        t:check("a tap outside moves the reading forward", now ~= t.position_before,
            t.position_before .. " -> " .. now)
        t:check("a tap outside reaches the reader's links", t.link_calls() == 1, t.link_calls())
        plugin.ui:handleEvent(Event:new("GotoPage", t.page_before))
    end)
    step(function()
        t:tap(Screen:getWidth() / 2, 5) -- top band of the reader
    end)
    step(function()
        t:shot("menu")
        t:check("a tap on the top band opens the reader menu", plugin.ui.menu.menu_container ~= nil)
        -- The top band opens the bottom settings panel along with the menu; close both.
        plugin.ui.menu:onCloseReaderMenu()
        if plugin.ui.config then
            plugin.ui.config:onCloseConfigMenu()
        end
    end)
    step(function()
        t.full_layout = plugin.layout
        local small = t:minimumLayout()
        t:use(plugin, small)
        t:shot("minimum")
        t:check("the board can be drawn with squares of the minimum size",
            small:squareSize() == small.px.min_square, small:squareSize())
        t:use(plugin, t.full_layout)
    end)
    step(function()
        t.repaints = {}
        t:tapRect(layout:buttonRect("close"))
    end)
    step(function()
        t:shot("closed")
        local window = layout:rects().window
        t:check("close closes", not layout:isOpen())
        t:check("close repaints only the window", #t.repaints == 1
            and same_rect(t.repaints[1], window))
        t:check("close does not flash", t.repaints[1] and t.repaints[1].refresh == "ui",
            t.repaints[1] and t.repaints[1].refresh)
        local diff = differences(t.page_pixels, grab(window))
        t:check("the page is clean after closing", diff == 0, diff .. " pixels differ")
    end)
    return steps
end

-- Reader zones a drag on the window must not reach.
local READER_DRAG_ZONES = {
    "paging_pan", "paging_pan_release", "paging_swipe", "rolling_pan", "rolling_pan_release",
    "rolling_swipe", "readerhighlight_hold", "readerhighlight_hold_pan",
    "readerhighlight_hold_release", "multiswipe", "inertial_scrolling_touch",
}

local function window_at(layout, place)
    local w = layout:rects().window
    return w.x == place.x and w.y == place.y
end

local function place_text(rect)
    return rect.x .. "," .. rect.y
end

-- H04: drag the window around, in the ways KOReader reports a drag.
local function h04(t, plugin)
    local layout = plugin.layout
    local steps, step = new_steps(plugin)
    local function move_button()
        return center(layout:buttonRect("move"))
    end
    -- Before a gesture: remember where the window and its move button are and how the button
    -- looks, and forget the repaints so far.
    local function mark()
        t.from = layout:rects().window
        t.button = layout:buttonRect("move")
        t.unpressed = grab(t.button)
        t.repaints = {}
    end
    local function repainted(i, rect, refresh)
        local r = t.repaints[i]
        return r ~= nil and same_rect(r, rect) and r.refresh == refresh
    end
    -- The i-th repaint was the quick one of the move button alone, to mark it or clear it.
    local function button_repainted(i)
        return repainted(i, t.button, "fast")
    end
    local function button_changed()
        return differences(grab(t.button), t.unpressed)
    end
    local function drag_by(dx, dy, lift, via)
        mark()
        local p = move_button()
        t:drag(p, offset(p, dx, dy), lift, via)
    end
    local function reader_untouched(name)
        t:check(name .. " does not reach the reader", t.reader_calls() == 0, t.reader_calls())
    end
    -- Checks that the drag since mark() moved the window by dx, dy: the move button marked when
    -- it started, and the window repainted once when it ended.
    local function moved(name, dx, dy)
        UIManager:forceRePaint()
        t:check(name .. " moves the window", window_at(layout, offset(t.from, dx, dy)),
            place_text(t.from) .. " -> " .. place_text(layout:rects().window))
        t:check(name .. " marks the move button, then repaints the old and new place with a flash",
            #t.repaints == 2 and button_repainted(1)
            and repainted(2, layout:dirtyRect({ window = t.from }), "flashui"), #t.repaints)
        reader_untouched(name)
        t:check(name .. " does not move the reading", reading_position(plugin.ui) == t.position,
            reading_position(plugin.ui))
    end
    -- Checks that the finger, down on the move button since mark() and lifted where it went
    -- down, marked the button and cleared it again without moving the window.
    local function pressed_in_place(name)
        t:check(name .. " does not move the window", window_at(layout, t.from),
            place_text(layout:rects().window))
        t:check(name .. " marks the move button and clears it, repainting only the button",
            #t.repaints == 2 and button_repainted(1) and button_repainted(2), #t.repaints)
        t:check(name .. " leaves the move button as before", button_changed() == 0,
            button_changed() .. " pixels differ")
        reader_untouched(name)
    end
    -- Checks that what was done since mark() left the window alone.
    local function stayed(name)
        t:check(name .. " does not move the window", window_at(layout, t.from),
            place_text(layout:rects().window))
        t:check(name .. " repaints nothing", #t.repaints == 0, #t.repaints)
        reader_untouched(name)
    end
    step(function()
        UIManager:forceRePaint()
        t.page = Screen.bb:copy()
        t.position = reading_position(plugin.ui)
        t.reader_calls = t:countAllCalls(plugin.ui, READER_DRAG_ZONES)
        t:watchRepaints()
        plugin:toggle()
    end)
    step(function()
        t:shot("open")
        -- The finger goes down on the move button, before KOReader knows whether it is a drag.
        mark()
        t.held_at = move_button()
        t:touch(t.held_at)
        -- No forceRePaint from here on: the mark must be on the screen without a whole repaint.
        t:check("touching the move button marks it at once, repainting only the button",
            #t.repaints == 1 and button_repainted(1), #t.repaints)
        t:check("the mark is drawn on the move button", button_changed() > 0,
            button_changed() .. " pixels differ")
        -- Then it rests and moves a little, without being lifted.
        t:press(t.held_at, offset(t.held_at, 0, -20), true)
    end)
    step(function()
        t:shot("pressed")
        t:check("the mark is not repainted while the finger rests and moves",
            #t.repaints == 1, #t.repaints)
        t:check("the window does not move before the finger is lifted", window_at(layout, t.from))
        t:lift(t.held_at, t.held_at, "hold")
    end)
    step(function()
        pressed_in_place("holding the move button and lifting it there")
        -- Slow drag up, with the finger leaving the window on the way.
        drag_by(-40, -120, "pan_release", { { x = 2, y = 400 }, { x = 5, y = 5 } })
    end)
    step(function()
        moved("a slow drag", -40, -120)
        t:shot("moved")
        local diff = changed_outside(t.page, t.from, layout:rects().window)
        t:check("the page where the window was is clean", diff == 0, diff .. " pixels differ")
        drag_by(30, 60, "swipe")
    end)
    step(function()
        moved("a quick drag", 30, 60)
        drag_by(-20, 40, "multiswipe", { { x = 300, y = 10 } })
    end)
    step(function()
        moved("a quick drag that turns", -20, 40)
        drag_by(25, -60, "hold")
    end)
    step(function()
        moved("a drag after resting the finger", 25, -60)
        mark()
        local starts = {
            { center(layout:squareRect(29, false)), "pan_release" },
            { center(layout:buttonRect("close")), "swipe" },
            { between_buttons(layout), "hold" },
        }
        for _, start in ipairs(starts) do
            t:drag(start[1], offset(start[1], -150, -150), start[2])
        end
    end)
    step(function()
        stayed("drags from the board, another button or between them")
        t:check("the window is still open", layout:isOpen())
        -- To the corner of the screen: the window would go past the right and bottom edges.
        local p = move_button()
        drag_by(Screen:getWidth() - 1 - p.x, Screen:getHeight() - 1 - p.y, "pan_release")
    end)
    step(function()
        UIManager:forceRePaint()
        t:shot("edge")
        local w = layout:rects().window
        local margin = layout.px.margin
        t:check("dropped off the screen, the window rests against the edge",
            w.x + w.w == Screen:getWidth() - margin and w.y + w.h == Screen:getHeight() - margin,
            place_text(w))
        mark()
        t:tapRect(layout:buttonRect("move"))
    end)
    step(function()
        pressed_in_place("a short tap on the move button")
        -- A quick drag off the window is the reader's: it turns the page.
        local y = layout:rects().window.y / 2
        t:drag({ x = Screen:getWidth() * 0.8, y = y }, { x = Screen:getWidth() * 0.2, y = y },
            "swipe")
    end)
    step(function()
        local now = reading_position(plugin.ui)
        t:check("a drag off the window still turns the page", now ~= t.position,
            t.position .. " -> " .. now)
        t.page:free()
        plugin.window:setOpen(false)
    end)
    return steps
end

-- Taps squares of the board by name, one after another, forgetting the repaints so far.
local function tap_squares(t, plugin, ...)
    local Rules = require("chess/rules")
    t.repaints = {}
    for _, name in ipairs({ ... }) do
        t:tapRect(plugin.layout:squareRect(Rules.squareFromName(name), plugin.session:flipped()))
    end
end

-- Taps buttons of the row shown, by id, one after another, forgetting the repaints so far.
local function tap_buttons(t, plugin, ...)
    t.repaints = {}
    for _, id in ipairs({ ... }) do
        t:tapRect(plugin.layout:buttonRect(id))
    end
end

-- What the session view shows on a square, by name: its piece and its marks.
local function square_view(plugin, name)
    local Rules = require("chess/rules")
    return plugin.session:view().squares[Rules.squareFromName(name)]
end

-- Starts the game again from a FEN (the usual start when nil) and repaints the window.
local function load_position(plugin, fen)
    assert(plugin.session.game:reset(fen))
    plugin.window:refresh(plugin.layout:dirtyRect())
end

-- H07: play moves with two taps, and the marks that go with them.
local function h07(t, plugin)
    local Rules = require("chess/rules")
    local layout, session = plugin.layout, plugin.session
    local steps, step = new_steps(plugin)
    local function info(name)
        return square_view(plugin, name)
    end
    local function has(name, mark)
        return info(name).marks[mark] == true
    end
    -- Checks that each of n taps repainted the window once, without a flash.
    local function repainted(name, n)
        local ok = #t.repaints == n
        for _, repaint in ipairs(t.repaints) do
            ok = ok and same_rect(repaint, layout:rects().window) and repaint.refresh == "ui"
        end
        t:check(name .. " repaints the window once per tap, without a flash", ok, #t.repaints)
    end
    local function played(name, square, piece, ...)
        tap_squares(t, plugin, ...)
        t:check(name, info(square).piece == piece, info(square).piece)
        repainted(name, select("#", ...))
    end
    step(function()
        t:watchRepaints()
        plugin:toggle()
    end)
    step(function()
        t:shot("open")
        tap_squares(t, plugin, "e2")
        t:shot("selected")
        t:check("a tap on a piece selects it", has("e2", "selected"))
        t:check("and shows its targets", has("e3", "target") and has("e4", "target"))
        repainted("selecting", 1)
    end)
    step(function()
        played("a tap on a target plays the move", "e4", "P", "e4")
        t:shot("played")
        t:check("the last move is not marked", not has("e2", "last_move")
            and not has("e4", "last_move"))
        t:check("and it is Black's turn", session:view().turn == "b")
        tap_squares(t, plugin, "e5", "e2")
        t:check("taps that change nothing repaint nothing", #t.repaints == 0, #t.repaints)
    end)
    step(function()
        session:flip()
        played("with the board flipped, taps find their squares", "a6", "p", "a7", "a6")
        t:shot("flipped")
        session:flip()
    end)
    step(function()
        played("e4-e5", "e5", "P", "e4", "e5")
        played("d7-d5, next to the pawn", "d5", "p", "d7", "d5")
        tap_squares(t, plugin, "e5")
        t:shot("en_passant")
        t:check("en passant shows as a capture", has("d6", "capture") and has("e6", "target"))
    end)
    step(function()
        played("en passant", "d6", "P", "d6")
        t:check("en passant takes the pawn", info("d5").piece == nil)
        played("a knight", "f6", "n", "g8", "f6")
        played("a knight", "f3", "N", "g1", "f3")
        played("a knight", "c6", "n", "b8", "c6")
        played("a bishop", "c4", "B", "f1", "c4")
        tap_squares(t, plugin, "e7")
        t:shot("capture")
        t:check("a capture is told apart from a move to an empty square",
            has("d6", "capture") and has("e6", "target") and has("e5", "target"))
    end)
    step(function()
        played("a capture", "d6", "p", "d6")
        tap_squares(t, plugin, "e1")
        t:shot("castling")
        t:check("the king can go two squares to castle", has("g1", "target"))
    end)
    step(function()
        played("castling", "g1", "K", "g1")
        t:check("castling moves the rook", info("f1").piece == "R" and info("h1").piece == nil)
        t:shot("castled")
        load_position(plugin)
        played("f2-f3", "f3", "P", "f2", "f3")
        played("e7-e5", "e5", "p", "e7", "e5")
        played("g2-g4", "g4", "P", "g2", "g4")
        played("the queen mates", "h4", "q", "d8", "h4")
        t:shot("mate")
        t:check("checkmate", session:view().status == "checkmate")
        t:check("the king in check is marked", has("e1", "check"))
    end)
    step(function()
        load_position(plugin, "7k/8/6K1/8/8/8/8/5Q2 w - - 0 1")
        played("the queen stalemates", "f7", "Q", "f1", "f7")
        t:shot("stalemate")
        t:check("stalemate", session:view().status == "stalemate")
        load_position(plugin, "4k3/8/8/8/8/8/8/R6K w - - 0 1")
        played("the rook checks", "a8", "R", "a1", "a8")
        t:shot("check")
        t:check("the black king in check is marked", has("e8", "check"))
        plugin.window:setOpen(false)
    end)
    return steps
end

-- H05: the size row, shrinking and growing to the limits, and back to the main row.
local function h05(t, plugin)
    local layout = plugin.layout
    local steps, step = new_steps(plugin)
    -- Taps a button of the row shown, forgetting the repaints so far and remembering the window.
    local function tap(id)
        t.before = layout:rects()
        tap_buttons(t, plugin, id)
    end
    local function corner_kept(name)
        local now = layout:rects().window
        t:check(name .. " keeps the top left corner", now.x == t.before.window.x
            and now.y == t.before.window.y, place_text(now))
    end
    -- Taps a resize button and checks that the board changed by one step and the window was
    -- repainted once, where it was and where it is.
    local function resized(id, steps_taken, refresh)
        local square = layout:squareSize()
        tap(id)
        local now = layout:squareSize()
        t:check(id .. " changes the squares by one step",
            now == square + steps_taken * layout.px.size_step, square .. " -> " .. now)
        t:repaintedOnce(id .. " repaints the window once, " .. refresh, layout:dirtyRect(t.before),
            refresh)
    end
    -- Taps a resize button until it is disabled, and checks that a tap then does nothing.
    local function to_limit(id)
        while layout:button(id).enabled do
            tap(id)
        end
        local square = layout:squareSize()
        tap(id)
        t:check("at its limit " .. id .. " does nothing", layout:squareSize() == square
            and #t.repaints == 0, #t.repaints)
    end
    local function row_shown(name, row)
        t:check(name .. " shows the " .. row .. " row", layout:shownRow() == row,
            layout:shownRow())
        t:repaintedOnce(name .. " repaints only the row", layout:rects().buttons, "ui")
    end
    step(function()
        t:watchRepaints()
        plugin:toggle()
    end)
    step(function()
        t:shot("open")
        tap("size")
        row_shown("size", "size")
        UIManager:forceRePaint()
        t:shot("size_row")
    end)
    step(function()
        resized("smaller", -1, "ui")
        corner_kept("smaller")
        resized("bigger", 1, "flashui")
        corner_kept("bigger")
        to_limit("smaller")
        t:check("the smallest board has squares of the minimum size",
            layout:squareSize() == layout.px.min_square, layout:squareSize())
        UIManager:forceRePaint()
        t:shot("minimum")
    end)
    step(function()
        to_limit("bigger")
        local screen = { x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
        local window = layout:rects().window
        t:check("the biggest board fits the screen", window.x >= screen.x
            and window.y >= screen.y and window.x + window.w <= screen.w
            and window.y + window.h <= screen.h, place_text(window))
        UIManager:forceRePaint()
        t:shot("maximum")
    end)
    step(function()
        tap("back")
        row_shown("back", "main")
        UIManager:forceRePaint()
        t:shot("back")
        layout:showRow("size")
        plugin:toggle()
        plugin:toggle()
        t:check("closing and opening shows the main row", layout:shownRow() == "main",
            layout:shownRow())
        plugin:toggle()
    end)
    return steps
end

-- The reset button: back to the start position, dropping the moves and the selection.
local function reset(t, plugin)
    local Rules = require("chess/rules")
    local layout, session = plugin.layout, plugin.session
    local steps, step = new_steps(plugin)
    step(function()
        t:watchRepaints()
        plugin:toggle()
    end)
    step(function()
        tap_squares(t, plugin, "e2", "e4", "e7", "e5", "g1")
        t:shot("played")
        tap_buttons(t, plugin, "reset")
        t:shot("reset")
        local saved = session.game:serialize()
        t:check("reset goes back to the start position, with no moves",
            saved.start == Rules.START_FEN and #saved.moves == 0, #saved.moves)
        t:check("and drops the selection",
            next(square_view(plugin, "g1").marks) == nil)
        t:repaintedOnce("reset repaints the window once, without a flash", layout:rects().window,
            "ui")
        tap_buttons(t, plugin, "reset")
        t:check("at the start position reset repaints nothing", #t.repaints == 0, #t.repaints)
        plugin:toggle()
    end)
    return steps
end

-- Editing the start position: unchanged it keeps the line, then the flow the story describes, then
-- an invalid position.
local function edit(t, plugin)
    local Rules = require("chess/rules")
    local layout, session = plugin.layout, plugin.session
    local steps, step = new_steps(plugin)
    local function start()
        return session.game:serialize().start
    end
    local function moves()
        return #session.game:serialize().moves
    end
    step(function()
        plugin:toggle()
        tap_squares(t, plugin, "e2", "e4")
        tap_buttons(t, plugin, "edit")
        t:shot("edit-row")
        t:check("the pencil shows the edit row", layout:shownRow() == "edit", layout:shownRow())
        t:check("with the position shown", square_view(plugin, "e4").piece == "P")
        tap_buttons(t, plugin, "back")
        t:check("back without changes keeps the line", moves() == 1, moves())
    end)
    step(function()
        tap_buttons(t, plugin, "edit", "clear")
        t:shot("trash-start")
        t:check("the trash puts the start position", square_view(plugin, "e2").piece == "P")
        tap_buttons(t, plugin, "erase")
        tap_squares(t, plugin, "d2")
        t:shot("erased")
        t:check("the eraser empties a square", square_view(plugin, "d2").piece == nil)
        tap_buttons(t, plugin, "clear", "clear", "king")
        tap_squares(t, plugin, "e1")
        tap_buttons(t, plugin, "pawn")
        tap_squares(t, plugin, "e2")
        tap_buttons(t, plugin, "color", "king")
        tap_squares(t, plugin, "e8")
        t:shot("black-king")
        tap_buttons(t, plugin, "color")
        t:shot("placed")
        tap_buttons(t, plugin, "back")
        t:shot("saved")
        t:check("back shows the main row", layout:shownRow() == "main", layout:shownRow())
        t:check("and the game starts from the edited position, White to move",
            start() == "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1", start())
    end)
    step(function()
        tap_buttons(t, plugin, "edit", "clear", "clear", "back")
        t:check("an invalid position keeps the game it came from",
            start() == "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1", start())
        plugin:toggle()
    end)
    return steps
end

-- The arrows: step back and forward along the line, and a new move after going back replaces
-- the rest of it.
local function line(t, plugin)
    local session = plugin.session
    local steps, step = new_steps(plugin)
    local function moves()
        return table.concat(session.game:serialize().moves, " ")
    end
    local function can_go()
        local buttons = session:view().buttons
        return buttons.backward, buttons.forward
    end
    step(function()
        t:watchRepaints()
        plugin:toggle()
        tap_squares(t, plugin, "e2", "e4", "e7", "e5")
        local backward, forward = can_go()
        t:check("at the end of the line only backward can be used", backward and not forward)
        t:shot("end")
        tap_buttons(t, plugin, "backward", "backward")
        t:shot("start")
        backward, forward = can_go()
        t:check("two steps back is the start, where only forward can be used",
            not backward and forward)
        tap_buttons(t, plugin, "backward")
        t:check("backward at the start does nothing", session.game:serialize().cursor == 0)
        tap_buttons(t, plugin, "forward")
        t:shot("forward")
        t:check("forward plays e4 again", session:view().last_move.san.text == "e4")
        tap_squares(t, plugin, "c7", "c5")
        t:shot("replaced")
        t:check("a new move replaces the rest of the line", moves() == "e2e4 c7c5", moves())
        tap_squares(t, plugin, "g1", "f3")
        t.repaints = {}
        local reader_calls = t:countAllCalls(plugin.ui, READER_DRAG_ZONES)
        t:holdRect(plugin.layout:buttonRect("backward"))
        t:shot("held_backward")
        t:check("holding backward goes to the start", session.game:serialize().cursor == 0)
        t:repaintedOnce("and repaints the window once, without a flash",
            plugin.layout:rects().window, "ui")
        t:holdRect(plugin.layout:buttonRect("forward"))
        t:shot("held_forward")
        t:check("holding forward goes to the end", session:view().last_move.san.text == "f3")
        t:check("holding an arrow does not reach the reader", reader_calls() == 0, reader_calls())
        plugin:toggle()
    end)
    return steps
end

-- H16: the strip under the board with the last moves that fit.
local function h16(t, plugin)
    local layout, session = plugin.layout, plugin.session
    local steps, step = new_steps(plugin)
    -- How many pixels of the strip are darker than its ground: none when it is empty.
    local function inked()
        local ground = require("ui/theme").NOTATION.background:getColor8().a
        local count = 0
        for _, value in ipairs(grab(layout:rects().notation)) do
            count = count + (value < ground and 1 or 0)
        end
        return count
    end
    local function shown()
        return #session:view().notation.moves
    end
    step(function()
        plugin:toggle()
    end)
    step(function()
        t:check("at the start the strip is empty", inked() == 0, inked())
        tap_squares(t, plugin, "e2", "e4", "e7", "e5", "g1", "f3", "b8", "c6", "f1", "b5",
            "a7", "a6", "b5", "a4", "g8", "f6", "e1", "g1", "f8", "e7")
    end)
    step(function()
        t:shot("line")
        t:check("after moves the strip shows them", inked() > 0 and shown() == 10, shown())
        tap_buttons(t, plugin, "backward", "backward")
    end)
    step(function()
        t:shot("back")
        local current = session:view().notation.current
        t:check("going back the strip keeps the line and marks the move on the board",
            shown() == 10 and current == 8, shown() .. " " .. current)
        tap_buttons(t, plugin, "size")
        while layout:canResize(-1) do
            tap_buttons(t, plugin, "smaller")
        end
        tap_buttons(t, plugin, "back")
    end)
    step(function()
        t:shot("minimum")
        tap_buttons(t, plugin, "edit", "clear", "clear", "king")
        tap_squares(t, plugin, "e1")
        tap_buttons(t, plugin, "color")
        tap_squares(t, plugin, "e8")
        tap_buttons(t, plugin, "color")
    end)
    step(function()
        t:shot("editing-minimum")
        t:check("while editing the strip shows no moves, only the pieces to put",
            shown() == 0 and layout:button("color") ~= nil, shown())
        tap_buttons(t, plugin, "back")
        tap_squares(t, plugin, "e1", "d2", "e8", "d7")
    end)
    step(function()
        t:shot("edited")
        t:check("a game from an edited position has no numbers",
            session:view().notation.numbered == false and shown() == 2)
        plugin:toggle()
    end)
    return steps
end

-- H08: choosing the piece of a promotion, and cancelling it.
local function h08(t, plugin)
    local layout, session = plugin.layout, plugin.session
    local steps, step = new_steps(plugin)
    local PROMOTION = "8/P7/8/8/8/8/8/k6K w - - 0 1"
    local function piece_on(name)
        return square_view(plugin, name).piece
    end
    local function promote()
        load_position(plugin, PROMOTION)
        tap_squares(t, plugin, "a7", "a8")
    end
    step(function()
        plugin:toggle()
        promote()
    end)
    step(function()
        t:shot("selector")
        t:check("a pawn on the last rank shows the pieces to choose", session:isPromoting())
        tap_squares(t, plugin, "a6")
    end)
    step(function()
        t:shot("rook")
        t:check("tapping the rook promotes to a rook", piece_on("a8") == "R", piece_on("a8"))
        t:check("and the strip writes it", session:view().last_move.san.promotion == "R")
        promote()
        tap_buttons(t, plugin, "flip")
        t:check("a button while choosing only cancels", not session:isPromoting()
            and not session:flipped() and piece_on("a7") == "P")
        promote()
        local before = layout:rects().window
        local from = center(layout:buttonRect("move"))
        t:drag(from, offset(from, -40, -120), "pan_release")
        t:check("the window does not move while choosing", same_rect(before,
            layout:rects().window) and session:isPromoting())
        tap_squares(t, plugin, "h1")
    end)
    step(function()
        t:shot("cancelled")
        t:check("a tap on another square cancels: the pawn stays",
            not session:isPromoting() and piece_on("a7") == "P" and piece_on("a8") == nil)
        plugin:toggle()
    end)
    return steps
end

-- Screenshots for the README: a board nearly as big as it gets, in the middle of the screen, with
-- the Marshall Attack (Capablanca-Marshall, New York 1918); a selected pawn; the editor; and the
-- smallest board in a corner, to read beside it. Run it on a book in the public domain.
local README_SHRINK_STEPS = 2

local function readme(t, plugin)
    local layout = plugin.layout
    local steps, step = new_steps(plugin)
    -- Moves the window to x, y (kept inside the screen) and repaints it.
    local function move_window(x, y)
        local before = layout:rects()
        layout:moveTo(x, y)
        plugin.window:refresh(layout:dirtyRect(before))
    end
    -- Taps a size button until it is disabled.
    local function resize_fully(button, steps_back)
        while layout:canResize(steps_back) do
            tap_buttons(t, plugin, button)
        end
    end
    step(function()
        plugin:toggle()
        tap_buttons(t, plugin, "size")
        resize_fully("bigger", 1)
        for _ = 1, README_SHRINK_STEPS do
            tap_buttons(t, plugin, "smaller")
        end
        tap_buttons(t, plugin, "back")
        local w, h = layout:windowSize()
        move_window(math.floor((layout.screen_w - w) / 2), math.floor((layout.screen_h - h) / 2))
    end)
    step(function()
        tap_squares(t, plugin, "e2", "e4", "e7", "e5", "g1", "f3", "b8", "c6", "f1", "b5",
            "a7", "a6", "b5", "a4", "g8", "f6", "e1", "g1", "f8", "e7", "f1", "e1", "b7", "b5",
            "a4", "b3", "e8", "g8", "c2", "c3", "d7", "d5")
    end)
    step(function()
        t:shot("game")
        tap_squares(t, plugin, "e4")
    end)
    step(function()
        t:shot("play")
        tap_squares(t, plugin, "e4")
        tap_buttons(t, plugin, "edit")
    end)
    step(function()
        t:shot("editor")
        tap_buttons(t, plugin, "back", "size")
        resize_fully("smaller", -1)
        tap_buttons(t, plugin, "back")
        move_window(layout.screen_w, layout.screen_h)
    end)
    step(function()
        t:shot("reading")
        plugin:toggle()
    end)
    return steps
end

-- H17: holding the eye shows the page under the window, and lifting the finger brings it back.
local function h17(t, plugin)
    local layout, session = plugin.layout, plugin.session
    local steps, step = new_steps(plugin)
    local eye
    step(function()
        t.page_pixels = grab(layout:rects().window)
        t.place = reading_position(plugin.ui)
        plugin:toggle()
        tap_squares(t, plugin, "e2", "e4", "g8")
    end)
    step(function()
        t.before = layout:rects()
        t.view = session:view()
        eye = center(layout:buttonRect("peek"))
        t:watchRepaints()
        t:touch(eye)
    end)
    step(function()
        t:shot("hidden")
        t:check("the finger on the eye hides the window", layout:isHidden())
        t:repaintedOnce("hiding repaints the window once", t.before.window, "ui")
        local diff = differences(t.page_pixels, grab(t.before.window))
        t:check("the page under it is seen whole", diff == 0, diff .. " pixels differ")
        t:press(eye, offset(eye, -80, -250), false)
    end)
    step(function()
        t:check("moving the finger does not bring the window back", layout:isHidden())
        t.repaints = {}
        t:lift(eye, offset(eye, -80, -250), "pan_release")
    end)
    step(function()
        t:shot("back")
        t:check("lifting the finger brings the window back", not layout:isHidden())
        t:repaintedOnce("showing repaints the window once, with a flash", t.before.window,
            "flashui")
        t:check("in the same place and size", same_rect(layout:rects().window, t.before.window))
        t:check("with the same position, selection and row",
            dump(session:view()) == dump(t.view) and layout:shownRow() == "main")
        t:check("the reader did not turn the page", reading_position(plugin.ui) == t.place)
        plugin:toggle()
    end)
    return steps
end

-- H18: the split screen. Splits it from the main row, plays a move, turns the page of the book in
-- its part, drags the divider, swaps the book and the board, and takes the window back over the
-- page. It works with any book: BOOK=petroff for a PDF.
local function view_fits(ui, rect)
    local dimen = ui.view.dimen
    return dimen.w == rect.w and dimen.h == rect.h, string.format("view %dx%d, part %dx%d",
        dimen.w, dimen.h, rect.w, rect.h)
end

-- Taps the right of the book's part, half way down, after noting where the reader is.
local function turn_page(t, plugin)
    local reader = plugin.layout:readerRect()
    t.place = reading_position(plugin.ui)
    t:tap(reader.x + reader.w * 0.9, reader.y + reader.h / 2)
end

-- Shows the status bar with the page progress, or the mode it had back (mode), without saving the
-- setting, and lays the book out again for it.
local function show_footer(ui, mode)
    local footer = ui.view.footer
    footer:applyFooterMode(mode or footer.mode_list.page_progress)
    footer:refreshFooter(true, true)
end

local function h18(t, plugin)
    local ui, layout = plugin.ui, plugin.layout
    local steps, step = new_steps(plugin)
    local footer_mode = ui.view.footer.mode
    step(function()
        show_footer(ui)
    end)
    step(function()
        plugin:toggle()
        tap_buttons(t, plugin, "split")
    end)
    step(function()
        t:shot("split")
        t:check("the split button splits the screen", layout:isSplit())
        t:check("the book is fitted to its part", view_fits(ui, layout:readerRect()))
        local footer = ui.view.footer
        t:check("the status bar is as wide as the book's part",
            footer.dimen.w == layout:readerRect().w, footer.dimen.w)
        tap_squares(t, plugin, "e2", "e4")
    end)
    step(function()
        t:check("the board plays", square_view(plugin, "e4").piece == "P")
        turn_page(t, plugin)
    end)
    step(function()
        t:shot("turned")
        t:check("a tap on the book turns its page", reading_position(ui) ~= t.place)
        t.text = layout:textLength()
        t.divider_from = center(layout:rects().divider)
        t:touch(t.divider_from)
    end)
    step(function()
        t:shot("divider_held")
        t:check("the divider is held while the finger is on it", layout:isDividing())
        local from = t.divider_from
        local to = layout:splitAxis() == "y" and offset(from, 0, -100) or offset(from, 100, 0)
        t:press(from, to, false)
        t:lift(from, to, "pan_release")
    end)
    step(function()
        t:shot("divider")
        t:check("dragging the divider gives the book another room", layout:textLength() ~= t.text,
            t.text .. " to " .. layout:textLength())
        t:check("and the book is fitted to it", view_fits(ui, layout:readerRect()))
        tap_buttons(t, plugin, "swap")
    end)
    step(function()
        t:shot("swapped")
        t:check("swap puts the book second", not layout:isTextFirst())
        t:check("the book is fitted to its new part", view_fits(ui, layout:readerRect()))
        turn_page(t, plugin)
    end)
    step(function()
        t:shot("swapped_turned")
        t:check("a tap on the book second turns its page", reading_position(ui) ~= t.place)
        tap_buttons(t, plugin, "swap")
    end)
    step(function()
        t:shot("swapped_back")
        t:check("swap again puts the book first", layout:isTextFirst()
            and view_fits(ui, layout:readerRect()))
        tap_buttons(t, plugin, "float")
    end)
    step(function()
        t:shot("floating")
        t:check("float takes the window back over the page", not layout:isSplit())
        t:check("and the book has the whole screen again", view_fits(ui, Screen:getSize()))
        tap_buttons(t, plugin, "split", "close")
    end)
    step(function()
        t:shot("closed")
        t:check("closed split, the book has the whole screen", view_fits(ui, Screen:getSize()))
        plugin:toggle()
    end)
    step(function()
        t:check("opened again, it is split again", layout:isSplit()
            and view_fits(ui, layout:readerRect()))
        t.rotation = Screen:getRotationMode()
        ui:handleEvent(Event:new("SetRotationMode", (t.rotation + 1) % 4))
    end)
    step(function()
        t:shot("turned_screen")
        t:check("the screen turned split, the book is fitted to its new part",
            layout:isSplit() and view_fits(ui, layout:readerRect()))
        ui:handleEvent(Event:new("SetRotationMode", t.rotation))
    end)
    step(function()
        t:check("and turned back, to its first part", view_fits(ui, layout:readerRect()))
        tap_buttons(t, plugin, "float")
        show_footer(ui, footer_mode)
    end)
    return steps
end

-- The kit: the main row of buttons inside the window frame, at the narrowest width a button of the
-- main row gets, at the width it has with room and as big buttons, with move held down and forward
-- disabled. It paints straight on the screen, for a screenshot to judge the style by; it checks
-- nothing.
local KIT_ROW = { "peek", "move", "flip", "size", "reset", "edit", "split", "backward", "forward",
    "close" }
local KIT_LOOKS = { move = { down = true }, forward = { dim = true } }
local KIT_SIZES = { { w = 27, h = 39 }, { w = 39, h = 39 }, { w = 54, h = 54 } }
-- The main row with buttons of a size in design pixels, its top left corner at x, y, framed as in
-- the window.
local function paint_kit_row(Kit, Theme, x, y, size)
    local w, h, border = Theme.px(size.w), Theme.px(size.h), Theme.px(Theme.SIZES.border)
    Kit.fill(Screen.bb, { x = x - border, y = y - border, w = #KIT_ROW * w + 2 * border,
        h = h + 2 * border }, Theme.GRAY.frame)
    local side = Kit.iconSide({ x = 0, y = 0, w = w, h = h })
    for i, id in ipairs(KIT_ROW) do
        local look = KIT_LOOKS[id] or {}
        local shown = { down = look.down, dim = look.dim and Theme.BUTTON.disabled or nil }
        Kit.button(Screen.bb, { x = x + (i - 1) * w, y = y, w = w, h = h }, shown,
            function(bb, face, ink) Kit.mask(bb, Theme.iconMask(id, side), face, ink) end)
    end
    return y + h + 2 * border
end

local function kit(t, plugin)
    local steps, step = new_steps(plugin)
    step(function() UIManager:forceRePaint() end)
    step(function()
        local Kit, Theme = require("ui/kit"), require("ui/theme")
        local gap = Theme.px(Theme.SIZES.margin)
        Kit.fill(Screen.bb, { x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() },
            Theme.GRAY.light_square)
        local y = gap
        for _, size in ipairs(KIT_SIZES) do
            y = paint_kit_row(Kit, Theme, gap, y, size) + gap
        end
        t:save("gallery")
    end)
    return steps
end

local SCENARIOS = { h03 = h03, h04 = h04, h05 = h05, h07 = h07, h08 = h08, reset = reset,
    edit = edit, line = line, h16 = h16, h17 = h17, h18 = h18, readme = readme, kit = kit }

function SelfTest.start(plugin)
    local t = setmetatable({ shots = 0, results = {}, failed = false }, SelfTest)
    t.scenario = os.getenv("CHESSBOARD_SCENARIO") or "h03"
    t.dir = DataStorage:getDataDir() .. "/chessboard"
    if lfs.attributes(t.dir, "mode") ~= "directory" then
        lfs.mkdir(t.dir)
    end
    local steps = assert(SCENARIOS[t.scenario], "no scenario " .. t.scenario)(t, plugin)
    steps[#steps + 1] = function() t:finish(plugin) end
    local i = 0
    t.run = function()
        i = i + 1
        if not steps[i] then
            return
        end
        local ok, err = pcall(steps[i])
        if not ok then
            t:check("step " .. i, false, err)
        end
        if t.run then -- nil once stopped
            UIManager:scheduleIn(STEP_SECONDS, t.run)
        end
    end
    UIManager:scheduleIn(1, t.run)
    return t
end

function SelfTest:finish(plugin)
    if self.restore_set_dirty then
        self.restore_set_dirty()
    end
    local file = io.open(self.dir .. "/selftest.txt", "a")
    if file then
        file:write(table.concat(self.results, "\n"), "\n")
        file:close()
    end
    for _, line in ipairs(self.results) do
        print("chessboard selftest: " .. line)
    end
    self:stop()
    plugin.ui:onClose()
    UIManager:quit(self.failed and 1 or 0)
end

-- Steps scheduled for later must not run once the book is closed.
function SelfTest:stop()
    if self.run then
        UIManager:unschedule(self.run)
        self.run = nil
    end
    if self.restore_set_dirty then
        self.restore_set_dirty()
        self.restore_set_dirty = nil
    end
end

return SelfTest
