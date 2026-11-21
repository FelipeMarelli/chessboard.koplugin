-- Split screen: the book on one part of the screen and the board on the other (model/split.lua and
-- the split state of model/layout.lua).
local Helper = require("helper")
local Layout = require("model/layout")
local Rects = require("rects")
local Rules = require("chess/rules")
local Split = require("model/split")
local eq, test = Helper.eq, Helper.test
local center, contains, overlap = Rects.center, Rects.contains, Rects.overlap

-- The sizes of ui/theme.lua, in design pixels; on the emulator one is 1.05 pixels.
local SIZES = { row = 39, button = 39, border = 2, margin = 11, min_square = 29, size_step = 6,
    gutter = 14, notation = 26, spacing = 8, divider = 24, split_controls = 80 }
local SCALE = Layout.scaleFor(632, 840)
local MIN_TOUCH = 39 * SCALE
local PORTRAIT, LANDSCAPE = { 632, 840 }, { 840, 632 }
local SCREENS = { PORTRAIT, LANDSCAPE, { 1072, 1448 }, { 1448, 1072 } }

local function new(size, sizes)
    local layout = Layout.new{ screen_w = size[1], screen_h = size[2], scale = SCALE,
        sizes = sizes or SIZES }
    layout:setOpen(true)
    return layout
end

local function split(size)
    local layout = new(size)
    layout:setSplit(true)
    return layout
end

local function screen_of(size)
    return { x = 0, y = 0, w = size[1], h = size[2] }
end

local function ids_of(layout)
    local ids = {}
    for _, button in ipairs(layout:buttons()) do
        ids[#ids + 1] = button.id
    end
    return ids
end

-- Drags from the middle of a rect by dx, dy, and lifts the finger there.
local function drag(layout, rect, dx, dy)
    local x, y = center(rect)
    assert(layout:startDrag(x, y, false), "the drag is not the window's")
    return layout:endDrag(x + dx, y + dy)
end

-- Grid ----------------------------------------------------------------------------------------

test("a grid takes as many columns as make its cells biggest", function()
    eq(Split.grid({ x = 0, y = 0, w = 300, h = 100 }, 3), {
        { x = 0, y = 0, w = 100, h = 100 }, { x = 100, y = 0, w = 100, h = 100 },
        { x = 200, y = 0, w = 100, h = 100 } })
    local column = Split.grid({ x = 10, y = 20, w = 100, h = 300 }, 3)
    eq(column[1], { x = 10, y = 20, w = 100, h = 100 })
    eq(column[3], { x = 10, y = 220, w = 100, h = 100 })
end)

test("the cells of a grid are apart, inside it, and the grid is centred", function()
    local rect = { x = 5, y = 7, w = 230, h = 373 }
    local cells = Split.grid(rect, 10)
    eq(#cells, 10)
    for i, cell in ipairs(cells) do
        assert(contains(rect, cell), "cell " .. i .. " out")
        for j = i + 1, #cells do
            assert(not overlap(cell, cells[j]), "cells " .. i .. " and " .. j)
        end
    end
    local right = cells[3].x + cells[3].w
    assert(math.abs((cells[1].x - rect.x) - (rect.x + rect.w - right)) <= 1, "not centred")
end)

-- Limits of the divider ----------------------------------------------------------------------

test("the axis of the split is the long side of the screen", function()
    eq(Split.axis(632, 840), "y")
    eq(Split.axis(840, 632), "x")
end)

test("the book keeps a quarter of the screen, and the board room for its smallest size",
    function()
        local px = new(PORTRAIT).px
        local least, most = Split.textLimits(632, 840, px)
        eq(least, 210)
        eq(840 - most, 8 * px.min_square + 2 * px.gutter + 2 * px.border + px.divider)
        eq(Split.fitText(632, 840, px, 10), least)
        eq(Split.fitText(632, 840, px, 2000), most)
        eq(Split.fitText(632, 840, px, 400.4), 400)
    end)

test("a drag moves the divider along the long side of the screen", function()
    eq(Split.travel(632, 840, 100, 100, 150, 130), 30)
    eq(Split.travel(840, 632, 100, 100, 150, 130), 50)
end)

-- Parts of the screen ------------------------------------------------------------------------

test("the window is not split until asked, and the book has the whole screen", function()
    local layout = new(PORTRAIT)
    eq(layout:isSplit(), false)
    eq(layout:readerRect(), nil)
    eq(layout:rects().reader, nil)
end)

test("split, the book and the window share the screen, half each at first", function()
    for _, size in ipairs(SCREENS) do
        local layout = split(size)
        eq(layout:isSplit(), true)
        local r = layout:rects()
        eq(layout:readerRect(), r.reader)
        assert(not overlap(r.reader, r.window), "they overlap")
        eq(r.reader.w * r.reader.h + r.window.w * r.window.h, size[1] * size[2])
        local long = math.max(size[1], size[2])
        assert(math.abs(layout:textLength() - long / 2) <= 1, "not half")
    end
end)

test("portrait: the book above, the board below on the left and its buttons on its right",
    function()
        local r = split(PORTRAIT):rects()
        eq(r.reader, { x = 0, y = 0, w = 632, h = 420 })
        eq(r.window, { x = 0, y = 420, w = 632, h = 420 })
        eq(r.divider.y, 420)
        assert(r.board_frame.x <= r.inner.x, "the board is not on the left")
        assert(r.buttons.x > r.board_frame.x + r.board_frame.w, "the buttons are not on its right")
        -- The board takes the whole height there is under the divider.
        assert(r.inner.h - r.board_frame.h < 8, "the board is short: " .. r.board_frame.h)
    end)

test("landscape: the book on the left, the board on the right on top and its buttons under it",
    function()
        local r = split(LANDSCAPE):rects()
        eq(r.reader, { x = 0, y = 0, w = 420, h = 632 })
        eq(r.window, { x = 420, y = 0, w = 420, h = 632 })
        eq(r.divider.x, 420)
        assert(r.buttons.y > r.board_frame.y + r.board_frame.h, "the buttons are not under it")
        assert(r.inner.w - r.board_frame.w < 8, "the board is narrow: " .. r.board_frame.w)
    end)

test("every part of the split window is inside it, and the board apart from the buttons",
    function()
        for _, size in ipairs(SCREENS) do
            local r = split(size):rects()
            for _, part in ipairs({ "divider", "inner", "board", "board_frame", "buttons",
                "notation", "status" }) do
                assert(contains(r.window, r[part]), part)
            end
            assert(not overlap(r.board_frame, r.buttons), "board and buttons")
            assert(not overlap(r.board_frame, r.notation), "board and notation")
            assert(not overlap(r.divider, r.inner), "divider and inside")
            eq(r.board.w, 8 * split(size):squareSize())
        end
    end)

test("swapped, the book goes below or on the right, next to the divider", function()
    local layout = split(PORTRAIT)
    eq(layout:swapSplit(), true)
    eq(layout:isTextFirst(), false)
    local r = layout:rects()
    eq(r.reader, { x = 0, y = 420, w = 632, h = 420 })
    eq(r.window, { x = 0, y = 0, w = 632, h = 420 })
    eq(r.divider.y + r.divider.h, 420)
    layout = split(LANDSCAPE)
    layout:swapSplit()
    r = layout:rects()
    eq(r.reader, { x = 420, y = 0, w = 420, h = 632 })
    eq(r.divider.x + r.divider.w, 420)
    layout:swapSplit()
    eq(layout:rects().reader.x, 0)
end)

test("a floating window does not swap", function()
    eq(new(PORTRAIT):swapSplit(), false)
end)

test("closed, the book has the whole screen, and opened again it is split again", function()
    local layout = split(PORTRAIT)
    layout:setOpen(false)
    eq(layout:readerRect(), nil)
    layout:setOpen(true)
    eq(layout:readerRect(), { x = 0, y = 0, w = 632, h = 420 })
end)

-- Buttons ------------------------------------------------------------------------------------

test("split, the main row has the buttons of the game, and swap and float; no eye, move or size",
    function()
        eq(ids_of(split(PORTRAIT)), { "backward", "forward", "flip", "reset", "edit", "swap",
            "float", "close" })
    end)

test("the size row of the floating window has the button that splits the screen", function()
    local layout = new(PORTRAIT)
    layout:showRow("size")
    eq(layout:button("split").enabled, true)
end)

test("splitting and floating again show the main row", function()
    local layout = new(PORTRAIT)
    layout:showRow("size")
    layout:setSplit(true)
    eq(layout:shownRow(), "main")
    layout:showRow("edit")
    layout:setSplit(false)
    eq(layout:shownRow(), "main")
end)

test("split, the buttons are big, apart and inside the room beside the board", function()
    for _, size in ipairs(SCREENS) do
        local layout = split(size)
        for _, row in ipairs({ "main", "edit" }) do
            layout:showRow(row)
            local buttons = layout:buttons()
            for i, button in ipairs(buttons) do
                assert(contains(layout:rects().buttons, button.rect), row .. " " .. button.id)
                assert(button.rect.w >= MIN_TOUCH and button.rect.h >= MIN_TOUCH,
                    row .. " " .. button.id .. " small")
                for j = i + 1, #buttons do
                    assert(not overlap(button.rect, buttons[j].rect), button.id)
                end
            end
        end
    end
end)

test("split, the edit row shows the pieces bare and its other buttons on cards", function()
    local layout = split(PORTRAIT)
    layout:showRow("edit")
    eq(layout:button("queen").upper, true)
    eq(layout:button("color").upper, true)
    eq(layout:button("clear").upper, nil)
end)

-- Taps ---------------------------------------------------------------------------------------

test("split, a tap finds the squares, the buttons, the strip and the divider", function()
    for _, size in ipairs({ PORTRAIT, LANDSCAPE }) do
        local layout = split(size)
        eq(layout:hit(center(layout:squareRect(Rules.squareFromName("e4"), false))),
            { zone = "board", square = Rules.squareFromName("e4") })
        eq(layout:hit(center(layout:buttonRect("swap"))), { zone = "button", button = "swap" })
        eq(layout:hit(center(layout:buttonRect("edit"))),
            { zone = "button", button = "edit", opens = "edit" })
        eq(layout:hit(center(layout:rects().notation)), { zone = "notation" })
        eq(layout:hit(center(layout:rects().divider)), { zone = "divider" })
        eq(layout:hit(center(layout:rects().reader)), nil)
    end
end)

test("split, the coordinate strips count as the board", function()
    local r = split(PORTRAIT):rects()
    eq(split(PORTRAIT):hit(center(r.files)), { zone = "board" })
end)

-- Divider ------------------------------------------------------------------------------------

test("dragging the divider gives the book the room up to where the finger is lifted", function()
    local layout = split(PORTRAIT)
    eq(drag(layout, layout:rects().divider, 0, -60), true)
    eq(layout:textLength(), 360)
    eq(layout:rects().window, { x = 0, y = 360, w = 632, h = 480 })
    layout = split(LANDSCAPE)
    eq(drag(layout, layout:rects().divider, 40, 0), true)
    eq(layout:rects().reader.w, 460)
end)

test("with the book second, the divider follows the finger the other way", function()
    local layout = split(PORTRAIT)
    layout:swapSplit()
    drag(layout, layout:rects().divider, 0, -60)
    eq(layout:rects().reader, { x = 0, y = 360, w = 632, h = 480 })
end)

test("the board grows with its part of the screen, and shrinks with it", function()
    local layout = split(PORTRAIT)
    local square = layout:squareSize()
    drag(layout, layout:rects().divider, 0, -60)
    assert(layout:squareSize() > square, "it did not grow")
    drag(layout, layout:rects().divider, 0, 120)
    assert(layout:squareSize() < square, "it did not shrink")
end)

test("the divider stops at its limits, and a drag across it does nothing", function()
    local layout = split(PORTRAIT)
    local least, most = Split.textLimits(632, 840, layout.px)
    drag(layout, layout:rects().divider, 0, -800)
    eq(layout:textLength(), least)
    eq(drag(layout, layout:rects().divider, 30, 0), false)
    drag(layout, layout:rects().divider, 0, 800)
    eq(layout:textLength(), most)
    assert(layout:squareSize() >= layout.px.min_square)
end)

test("while a promotion waits for its piece the divider does not move", function()
    local layout = split(PORTRAIT)
    local x, y = center(layout:rects().divider)
    layout:startDrag(x, y, false, true)
    eq(layout:endDrag(x, y - 60), false)
    eq(layout:textLength(), 420)
end)

test("a drag from the board does not move the divider", function()
    local layout = split(PORTRAIT)
    eq(drag(layout, layout:rects().board, 0, -60), false)
    eq(layout:textLength(), 420)
end)

-- Floating again and turning the screen --------------------------------------------------------

test("floating again, the window is back where it was and as big", function()
    local layout = new(PORTRAIT)
    layout:resize(2)
    layout:moveTo(40, 50)
    local before = layout:rects()
    layout:setSplit(true)
    eq(layout:setSplit(true), false)
    eq(layout:setSplit(false), true)
    eq(layout:rects(), before)
    eq(layout:readerRect(), nil)
end)

test("turning the screen keeps the split and the share of the book", function()
    local layout = split(PORTRAIT)
    drag(layout, layout:rects().divider, 0, -84)
    eq(layout:setScreen(632, 840), false)
    eq(layout:setScreen(840, 632), true)
    eq(layout:isSplit(), true)
    eq(layout:splitAxis(), "x")
    eq(layout:textLength(), 336) -- 40 % of 840
    eq(layout:rects().reader, { x = 0, y = 0, w = 336, h = 632 })
end)

test("floating again after the screen turned, the window is in its default place", function()
    local layout = split(PORTRAIT)
    layout:setScreen(840, 632)
    layout:setSplit(false)
    local fresh = new(LANDSCAPE)
    eq(layout:rects().window, fresh:rects().window)
end)

test("the split window covers the whole screen but the book's part", function()
    for _, size in ipairs(SCREENS) do
        local r = split(size):rects()
        assert(contains(screen_of(size), r.window))
        assert(contains(screen_of(size), r.reader))
    end
end)
