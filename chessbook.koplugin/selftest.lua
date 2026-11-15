-- Scripted run of the window with synthetic taps, for the emulator. Only runs when the variable
-- CHESSBOOK_SELFTEST is set.
--
--   CHESSBOOK_SELFTEST=1 [CHESSBOOK_SCENARIO=h03] [CHESSBOOK_PAGE=30] ./run-emu.sh book
--
-- Each scenario taps, checks the state and saves screenshots in emu-data/chessbook/. The result
-- goes to emu-data/chessbook/selftest.txt, one PASS or FAIL line per check.
local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local Screen = Device.screen

local STEP_SECONDS = 0.6

local SelfTest = {}
SelfTest.__index = SelfTest

function SelfTest:shot(name)
    -- Paint what is pending first: setDirty only paints on a later turn of the event loop.
    UIManager:forceRePaint()
    self.shots = self.shots + 1
    local orientation = Screen:getWidth() > Screen:getHeight() and "h" or "v"
    Screen.bb:writePNG(string.format("%s/%s_%s_%02d_%s.png", self.dir, self.scenario,
        orientation, self.shots, name))
end

local function center(rect)
    return { x = rect.x + rect.w / 2, y = rect.y + rect.h / 2 }
end

-- A point of the button row that is on no button: just right of the move button.
local function between_buttons(layout)
    local move = layout:buttonRect("move")
    return { x = move.x + move.w + 2, y = move.y + move.h / 2 }
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

function SelfTest:tap(x, y)
    self:gesture({ ges = "tap", pos = point({ x = x, y = y }) })
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

-- A drag from one point to another the way KOReader reports it, through the points of via. lift:
-- "pan_release" (a slow drag), "swipe" or "multiswipe" (quick ones) or "hold" (the finger
-- rested before moving).
function SelfTest:drag(from, to, lift, via)
    local held = lift == "hold"
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
    self:gesture(LIFTS[lift](from, to))
end

function SelfTest:check(name, ok, detail)
    local line = string.format("%s %s %s%s", ok and "PASS" or "FAIL", self.scenario, name,
        detail and (" (" .. tostring(detail) .. ")") or "")
    self.results[#self.results + 1] = line
    if not ok then
        self.failed = true
    end
    logger.info("chessbook selftest:", line)
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

-- Adds a first step that goes to the page in CHESSBOOK_PAGE, when it is set.
local function go_to_page(steps, plugin)
    local page = tonumber(os.getenv("CHESSBOOK_PAGE") or "")
    if page then
        steps[#steps + 1] = function() plugin.ui:handleEvent(Event:new("GotoPage", page)) end
    end
end

-- A layout whose board has squares of the minimum size: one for a screen just big enough.
function SelfTest:minimumLayout()
    local Layout = require("model/layout")
    local Theme = require("ui/theme")
    local min_px = Theme.px(Theme.SIZES.min_square)
    local side = math.ceil(8 * min_px / 0.6) + 1
    local layout = Layout.new{ screen_w = side, screen_h = side + 2 * Theme.px(Theme.SIZES.row),
        px_per_mm = Theme.pxPerMm(), sizes = Theme.SIZES }
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
    local steps = {}
    local function step(fn) steps[#steps + 1] = fn end
    go_to_page(steps, plugin)
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
            t.repaints[1] and t.repaints[1].refresh == "flashui", t.repaints[1] and t.repaints[1].refresh)
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
        t:tapRect(plugin.layout:buttonRect("size"))
    end)
    step(function()
        UIManager:forceRePaint()
        t:shot("small")
        t:check("the temporary size button makes the window minimum",
            plugin.layout:isSmall() and plugin.layout:squareSize() == plugin.layout.px.min_square,
            plugin.layout:squareSize())
        t:check("shrinking does not flash", t.repaints[1] and t.repaints[1].refresh == "ui",
            t.repaints[1] and t.repaints[1].refresh)
        t.repaints = {}
        t:tapRect(plugin.layout:buttonRect("size"))
    end)
    step(function()
        UIManager:forceRePaint()
        t:check("and again back to the default size", not plugin.layout:isSmall(),
            plugin.layout:squareSize())
        t:check("growing flashes", t.repaints[1] and t.repaints[1].refresh == "flashui",
            t.repaints[1] and t.repaints[1].refresh)
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
    "readerhighlight_hold_release", "multiswipe",
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
    local steps = {}
    local function step(fn) steps[#steps + 1] = fn end
    local function move_button()
        return center(layout:buttonRect("move"))
    end
    -- Before a gesture: remember where the window is and forget the repaints so far.
    local function mark()
        t.from = layout:rects().window
        t.repaints = {}
    end
    local function drag_by(dx, dy, lift, via)
        mark()
        local p = move_button()
        t:drag(p, offset(p, dx, dy), lift, via)
    end
    local function reader_untouched(name)
        t:check(name .. " does not reach the reader", t.reader_calls() == 0, t.reader_calls())
    end
    -- Checks that the drag since mark() moved the window by dx, dy, repainting once.
    local function moved(name, dx, dy)
        UIManager:forceRePaint()
        t:check(name .. " moves the window", window_at(layout, offset(t.from, dx, dy)),
            place_text(t.from) .. " -> " .. place_text(layout:rects().window))
        t:check(name .. " repaints once, old and new place, with a flash", #t.repaints == 1
            and same_rect(t.repaints[1], layout:dirtyRect({ window = t.from }))
            and t.repaints[1].refresh == "flashui", #t.repaints)
        reader_untouched(name)
        t:check(name .. " does not move the reading", reading_position(plugin.ui) == t.position,
            reading_position(plugin.ui))
    end
    -- Checks that what was done since mark() left the window alone.
    local function stayed(name)
        t:check(name .. " does not move the window", window_at(layout, t.from),
            place_text(layout:rects().window))
        t:check(name .. " repaints nothing", #t.repaints == 0, #t.repaints)
        reader_untouched(name)
    end
    go_to_page(steps, plugin)
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
        -- Slow drag up, with the finger leaving the window on the way.
        drag_by(-40, -150, "pan_release", { { x = 2, y = 400 }, { x = 5, y = 5 } })
    end)
    step(function()
        moved("a slow drag", -40, -150)
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
        stayed("a short tap on the move button")
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

-- Ways of drawing the coordinate labels, to compare them side by side. gutter in mm (0: on the
-- squares); grays from 0 (black) to 255 (white).
local LABEL_VARIANTS = {
    { name = "A", gutter = 0, share = 0.24, bold = false, on_light = 0x66, on_dark = 0xFF },
    { name = "G", gutter = 2.5, bold = false, ink = 0x00, paper = 0xFF },
    { name = "H (now)", gutter = 2.5, bold = true, ink = 0x00, paper = 0xFF },
    { name = "I", gutter = 2, bold = false, ink = 0x55, paper = 0xFF },
    { name = "J", gutter = 3, bold = false, ink = 0x00, paper = 0xDD },
    { name = "K", gutter = 3, bold = true, ink = 0xFF, paper = 0x00 },
}

local function layout_for(plugin, gutter)
    local Layout = require("model/layout")
    local Theme = require("ui/theme")
    local sizes = {}
    for k, v in pairs(Theme.SIZES) do sizes[k] = v end
    sizes.gutter = gutter
    local layout = Layout.new{ screen_w = Screen:getWidth(), screen_h = Screen:getHeight(),
        px_per_mm = Theme.pxPerMm(), sizes = sizes }
    layout:setOpen(true)
    return layout
end

local function copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

-- Paints the window with each label variant and puts them all in one image.
local function labels(t, plugin)
    local Blitbuffer = require("ffi/blitbuffer")
    local Font = require("ui/font")
    local TextWidget = require("ui/widget/textwidget")
    local Theme = require("ui/theme")
    local original = { label = copy(Theme.LABEL), gray = copy(Theme.GRAY),
        layout = plugin.layout }
    local layouts, cell_w, cell_h = {}, 0, 0
    local columns, caption = 3, 30
    for i, variant in ipairs(LABEL_VARIANTS) do
        layouts[i] = layout_for(plugin, variant.gutter)
        local w = layouts[i]:rects().window
        cell_w, cell_h = math.max(cell_w, w.w + 20), math.max(cell_h, w.h + caption)
    end
    local rows = math.ceil(#LABEL_VARIANTS / columns)
    local grid = Blitbuffer.new(columns * cell_w, rows * cell_h, Screen.bb:getType())
    grid:fill(Blitbuffer.COLOR_WHITE)
    local function use(label, gray, layout)
        for k, v in pairs(label) do Theme.LABEL[k] = v end
        for k, v in pairs(gray) do Theme.GRAY[k] = v end
        local before = plugin.layout:rects()
        plugin.layout, plugin.window.layout = layout, layout
        plugin.window:refresh(layout:dirtyRect(before))
    end
    local steps = {}
    for i, variant in ipairs(LABEL_VARIANTS) do
        steps[#steps + 1] = function()
            local label, gray = copy(original.label), copy(original.gray)
            label.bold = variant.bold
            label.share = variant.share or label.share
            if variant.on_light then
                label.on_light = Blitbuffer.Color8(variant.on_light)
                label.on_dark = Blitbuffer.Color8(variant.on_dark)
            end
            if variant.ink then
                label.on_gutter = Blitbuffer.Color8(variant.ink)
                gray.gutter = Blitbuffer.Color8(variant.paper)
            end
            use(label, gray, layouts[i])
            UIManager:forceRePaint()
            local w = layouts[i]:rects().window
            local x, y = ((i - 1) % columns) * cell_w, math.floor((i - 1) / columns) * cell_h
            local text = TextWidget:new{ text = variant.name, face = Font:getFace("cfont", 16),
                bold = true }
            text:paintTo(grid, x + 4, y)
            text:free()
            grid:blitFrom(Screen.bb, x, y + caption, w.x, w.y, w.w, w.h)
        end
    end
    steps[#steps + 1] = function()
        use(original.label, original.gray, original.layout)
        local orientation = Screen:getWidth() > Screen:getHeight() and "h" or "v"
        grid:writePNG(string.format("%s/labels_%s.png", t.dir, orientation))
        grid:free()
        t:check("label variants saved", true)
    end
    return steps
end

-- Square sides in mm to compare as the minimum size of the window.
local MINIMUM_SIZES = { 2.5, 3, 3.5, 4, 4.5, 5 }

-- Paints the window with each minimum square size over the same page, to compare them with the
-- text and the diagrams of the book.
local function sizes(t, plugin)
    local Blitbuffer = require("ffi/blitbuffer")
    local Font = require("ui/font")
    local Layout = require("model/layout")
    local TextWidget = require("ui/widget/textwidget")
    local Theme = require("ui/theme")
    local original = plugin.layout
    local sheet
    local x, y, row_h, gap, caption = 10, 60, 0, 10, 22
    local steps = {}
    steps[#steps + 1] = function()
        plugin.window:setOpen(false)
        UIManager:forceRePaint()
        sheet = Blitbuffer.new(Screen:getWidth(), Screen:getHeight(), Screen.bb:getType())
        sheet:blitFrom(Screen.bb, 0, 0, 0, 0, Screen:getWidth(), Screen:getHeight())
    end
    for _, mm in ipairs(MINIMUM_SIZES) do
        steps[#steps + 1] = function()
            local sizes_mm = copy(Theme.SIZES)
            sizes_mm.min_square = mm
            local min_px = Theme.px(mm)
            local side = math.ceil(8 * min_px / 0.6) + 1
            local layout = Layout.new{ screen_w = side,
                screen_h = side + 2 * Theme.px(Theme.SIZES.row),
                px_per_mm = Theme.pxPerMm(), sizes = sizes_mm }
            layout:setOpen(true)
            t:use(plugin, layout)
            local w = layout:rects().window
            if x + w.w > Screen:getWidth() then
                x, y, row_h = 10, y + row_h + gap, 0
            end
            local text = TextWidget:new{ text = string.format("%s mm (%d px)", mm,
                layout:squareSize()), face = Font:getFace("cfont", 14), bold = true }
            sheet:paintRect(x, y, text:getSize().w + 4, caption, Blitbuffer.COLOR_WHITE)
            text:paintTo(sheet, x + 2, y)
            text:free()
            sheet:blitFrom(Screen.bb, x, y + caption, w.x, w.y, w.w, w.h)
            x, row_h = x + w.w + gap, math.max(row_h, w.h + caption)
        end
    end
    steps[#steps + 1] = function()
        t:use(plugin, original)
        local orientation = Screen:getWidth() > Screen:getHeight() and "h" or "v"
        sheet:writePNG(string.format("%s/sizes_%s.png", t.dir, orientation))
        sheet:free()
        t:check("minimum sizes saved", true)
    end
    return steps
end

local SCENARIOS = { h03 = h03, h04 = h04, labels = labels, sizes = sizes }

function SelfTest.start(plugin)
    local t = setmetatable({ shots = 0, results = {}, failed = false }, SelfTest)
    t.scenario = os.getenv("CHESSBOOK_SCENARIO") or "h03"
    t.dir = DataStorage:getDataDir() .. "/chessbook"
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
        print("chessbook selftest: " .. line)
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
