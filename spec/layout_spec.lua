-- H03: geometry of the floating window (model/layout.lua).
local Helper = require("helper")
local Layout = require("model/layout")
local Rules = require("chess/rules")
local eq, test = Helper.eq, Helper.test

local sq = Rules.squareFromName

local SIZES = { row = 7, button = 9, border = 0.3, margin = 2, min_square = 5 }
local PX_PER_MM = 150 / 25.4

local function new(w, h, open)
    local layout = Layout.new{ screen_w = w, screen_h = h, px_per_mm = PX_PER_MM, sizes = SIZES }
    layout:setOpen(open ~= false)
    return layout
end

local function is_int(n)
    return type(n) == "number" and n % 1 == 0
end

local function center(rect)
    return rect.x + math.floor(rect.w / 2), rect.y + math.floor(rect.h / 2)
end

local function contains(outer, inner)
    return inner.x >= outer.x and inner.y >= outer.y and inner.x + inner.w <= outer.x + outer.w
        and inner.y + inner.h <= outer.y + outer.h
end

local SCREENS = { { 632, 840 }, { 840, 632 }, { 1072, 1448 }, { 1448, 1072 }, { 300, 220 } }

-- 3. First place ------------------------------------------------------------------------------

test("C3: the window starts centred at the bottom, the board near 60 % of the short side",
    function()
        for _, size in ipairs({ { 632, 840 }, { 840, 632 }, { 1072, 1448 }, { 1448, 1072 } }) do
            local w, h = size[1], size[2]
            local r = new(w, h):rects()
            local short = math.min(w, h)
            assert(math.abs(r.board.w - 0.6 * short) <= 8, "board " .. r.board.w)
            assert(math.abs(2 * r.window.x + r.window.w - w) <= 1, "not centred")
            local gap = h - (r.window.y + r.window.h)
            assert(gap >= 0 and gap <= 0.05 * h, "not at the bottom: " .. gap)
        end
    end)

test("C3: the exact place on the screens of the UI test", function()
    eq(new(632, 840):rects().window, { x = 126, y = 407, w = 380, h = 421 })
    eq(new(840, 632):rects().window, { x = 230, y = 199, w = 380, h = 421 })
end)

test("C3: on a small screen the window still fits, with squares of the minimum size or more",
    function()
        for _, size in ipairs(SCREENS) do
            local layout = new(size[1], size[2])
            local r = layout:rects()
            assert(layout:squareSize() >= 30, "square " .. layout:squareSize())
            if size[1] >= 300 and size[2] >= 300 then
                assert(contains({ x = 0, y = 0, w = size[1], h = size[2] }, r.window))
            end
        end
    end)

-- 2. Parts of the window ------------------------------------------------------------------------

test("C2: the board and a row of buttons under it, inside the window", function()
    local r = new(632, 840):rects()
    for _, part in ipairs({ "board", "buttons" }) do
        assert(contains(r.window, r[part]), part)
    end
    eq(r.board.y + r.board.h, r.buttons.y)
    eq(r.buttons.w, r.board.w)
    eq(r.titlebar, nil)
end)

test("C2: move, flip and size from the left of the row, and close at the right", function()
    local layout = new(632, 840)
    local row = layout:rects().buttons
    local ids = {}
    for _, button in ipairs(layout:buttons()) do
        ids[#ids + 1] = button.id
        assert(contains(row, button.rect), button.id)
        assert(button.rect.w >= 7 * PX_PER_MM - 1 and button.rect.h >= 7 * PX_PER_MM - 1,
            "button smaller than 7 mm: " .. button.id)
    end
    eq(ids, { "move", "flip", "size", "close" })
    eq(layout:buttonRect("move").x, row.x)
    eq(layout:buttonRect("close").x + layout:buttonRect("close").w, row.x + row.w)
    eq(layout:buttonRect("move"), layout:buttons()[1].rect)
    eq(layout:buttonRect("nothing"), nil)
end)

test("temporary size button: switches to the minimum square and back, centred at the bottom",
    function()
        for _, size in ipairs({ { 632, 840 }, { 840, 632 } }) do
            local w, h = size[1], size[2]
            local layout = new(w, h)
            local default = layout:rects().window
            eq(layout:isSmall(), false)
            layout:toggleSmall()
            eq(layout:isSmall(), true)
            eq(layout:squareSize(), layout.px.min_square)
            local small = layout:rects().window
            assert(math.abs(2 * small.x + small.w - w) <= 1, "not centred")
            eq(small.y + small.h, default.y + default.h)
            layout:toggleSmall()
            eq(layout:rects().window, default)
        end
    end)

-- 6. Square board, equal squares ----------------------------------------------------------------

test("C6: the board is square and its 64 squares tile it in equal whole pixels", function()
    for _, size in ipairs(SCREENS) do
        local layout = new(size[1], size[2])
        local board = layout:rects().board
        local s = layout:squareSize()
        eq(board.w, board.h); eq(board.w, 8 * s)
        for _, flipped in ipairs({ false, true }) do
            local seen = {}
            for square = 1, 64 do
                local rect = layout:squareRect(square, flipped)
                assert(is_int(rect.x) and is_int(rect.y) and rect.w == s and rect.h == s)
                assert(contains(board, rect))
                local key = rect.x .. "," .. rect.y
                assert(not seen[key], "two squares at " .. key)
                seen[key] = true
            end
        end
    end
end)

test("C6: every rect of the window is in whole pixels", function()
    for _, size in ipairs(SCREENS) do
        local layout = new(size[1], size[2])
        local rects = layout:rects()
        for name, rect in pairs(rects) do
            for _, k in ipairs({ "x", "y", "w", "h" }) do
                assert(is_int(rect[k]), name .. "." .. k)
            end
        end
    end
end)

-- 9. Flipping ----------------------------------------------------------------------------------

test("C9: a1 is at the bottom left, and at the top right when the board is flipped", function()
    local layout = new(632, 840)
    local board = layout:rects().board
    local s = layout:squareSize()
    local bottom, right = board.y + board.h - s, board.x + board.w - s
    eq(layout:squareRect(sq("a1"), false), { x = board.x, y = bottom, w = s, h = s })
    eq(layout:squareRect(sq("h8"), false), { x = right, y = board.y, w = s, h = s })
    eq(layout:squareRect(sq("a1"), true), { x = right, y = board.y, w = s, h = s })
    eq(layout:squareRect(sq("h8"), true), { x = board.x, y = bottom, w = s, h = s })
    eq(layout:squareRect(sq("e4"), true), layout:squareRect(sq("d5"), false))
end)

-- 7. Coordinate labels -------------------------------------------------------------------------

local function labels(flipped)
    local names = { file = {}, rank = {} }
    for _, label in ipairs(Layout.labelSquares(flipped)) do
        names[label.kind][#names[label.kind] + 1] = Rules.squareName(label.square)
    end
    table.sort(names.file); table.sort(names.rank)
    return names
end

test("C7: files go on the bottom row and ranks on the left column, and follow the flip",
    function()
        eq(labels(false), { file = { "a1", "b1", "c1", "d1", "e1", "f1", "g1", "h1" },
            rank = { "a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8" } })
        eq(labels(true), { file = { "a8", "b8", "c8", "d8", "e8", "f8", "g8", "h8" },
            rank = { "h1", "h2", "h3", "h4", "h5", "h6", "h7", "h8" } })
        local layout = new(632, 840)
        local board = layout:rects().board
        for _, flipped in ipairs({ false, true }) do
            for _, label in ipairs(Layout.labelSquares(flipped)) do
                local rect = layout:squareRect(label.square, flipped)
                if label.kind == "file" then
                    eq(rect.y + rect.h, board.y + board.h)
                else
                    eq(rect.x, board.x)
                end
            end
        end
    end)

-- 10. Taps -------------------------------------------------------------------------------------

test("C10: a tap on a square gives that square, with the board either way round", function()
    local layout = new(632, 840)
    for _, flipped in ipairs({ false, true }) do
        for square = 1, 64 do
            local x, y = center(layout:squareRect(square, flipped))
            eq(layout:hit(x, y, flipped), { zone = "board", square = square })
            local rect = layout:squareRect(square, flipped)
            eq(layout:hit(rect.x, rect.y, flipped).square, square)
            eq(layout:hit(rect.x + rect.w - 1, rect.y + rect.h - 1, flipped).square, square)
        end
    end
end)

test("C10: taps on the buttons and between them", function()
    local layout = new(632, 840)
    eq(layout:hit(center(layout:buttonRect("close"))), { zone = "button", button = "close" })
    eq(layout:hit(center(layout:buttonRect("flip"))), { zone = "button", button = "flip" })
    local size = layout:buttonRect("size")
    eq(layout:hit(size.x + size.w + 1, size.y + 1), { zone = "button" })
end)

test("C10: a tap outside the window, or with the window closed, is not the window's", function()
    local layout = new(632, 840)
    local w = layout:rects().window
    for _, point in ipairs({ { 0, 0 }, { w.x - 1, w.y + 10 }, { w.x + w.w, w.y + 10 },
        { w.x + 10, w.y - 1 }, { w.x + 10, w.y + w.h } }) do
        eq(layout:hit(point[1], point[2], false), nil)
    end
    local x, y = center(w)
    assert(layout:hit(x, y, false))
    layout:setOpen(false)
    eq(layout:isOpen(), false)
    eq(layout:hit(x, y, false), nil)
end)

test("C10: every point inside the window, border included, belongs to some part", function()
    local layout = new(840, 632)
    local w = layout:rects().window
    for y = w.y, w.y + w.h - 1 do
        for x = w.x, w.x + w.w - 1, 7 do
            assert(layout:hit(x, y, true), "nothing at " .. x .. "," .. y)
        end
        assert(layout:hit(w.x + w.w - 1, y, false))
    end
    eq(layout:hit(w.x, w.y + w.h - 1, false), { zone = "button", button = "move" })
    eq(layout:hit(w.x + w.w - 1, w.y + w.h - 1, false), { zone = "button", button = "close" })
    eq(layout:hit(w.x + w.w - 1, w.y, false), { zone = "board", square = 64 })
end)

-- 11. Repainting -------------------------------------------------------------------------------

test("C11: the region to repaint is the window, or what covers the old and the new one",
    function()
        local layout = new(632, 840)
        local before = layout:rects()
        eq(layout:dirtyRect(), before.window)
        eq(layout:dirtyRect(before), before.window)
        layout:setScreen(840, 632)
        local now = layout:rects().window
        local dirty = layout:dirtyRect(before)
        assert(contains(dirty, now) and contains(dirty, before.window))
        eq(dirty, { x = 126, y = 199, w = 484, h = 629 })
    end)

-- Rotation -------------------------------------------------------------------------------------

test("a new screen size places the window again, inside the screen", function()
    local layout = new(632, 840)
    layout:setScreen(840, 632)
    eq(layout:rects().window, new(840, 632):rects().window)
    eq(layout:isOpen(), true)
end)

test("the same screen size keeps the window where it is", function()
    local layout = new(632, 840)
    layout:moveTo(20, 30)
    layout:setScreen(632, 840)
    eq(layout:rects().window.x, 20); eq(layout:rects().window.y, 30)
end)

-- H04. Moving the window -----------------------------------------------------------------------

local function overlap(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

test("H04 C1: the move button is the first of the row, on the same grid as the others", function()
    for _, size in ipairs(SCREENS) do
        local layout = new(size[1], size[2])
        local move, after = layout:buttonRect("move"), layout:buttonRect("flip")
        eq(move, { x = layout:rects().buttons.x, y = after.y, w = after.w, h = after.h })
        eq(after.x, move.x + move.w)
        eq(layout:hit(center(move)), { zone = "button", button = "move" })
    end
end)

test("H04 C1: with the window at its minimum size the buttons do not overlap", function()
    -- The sizes of ui/theme.lua.
    local sizes = { row = 7, button = 8, border = 0.3, margin = 2, min_square = 4, gutter = 2.5 }
    for _, size in ipairs({ { 632, 840 }, { 1272, 1696 } }) do
        local layout = Layout.new{ screen_w = size[1], screen_h = size[2],
            px_per_mm = size[1] / 632 * PX_PER_MM, sizes = sizes }
        layout:toggleSmall()
        local list = layout:buttons()
        for i = 1, #list do
            for j = i + 1, #list do
                assert(not overlap(list[i].rect, list[j].rect), list[i].id .. " " .. list[j].id)
            end
        end
    end
end)

local MARGIN = 12 -- 2 mm at 150 dpi

test("H04: moveTo puts the top left corner of the window at a point", function()
    local layout = new(632, 840)
    local before = layout:rects()
    layout:moveTo(40, 50)
    local now = layout:rects()
    eq(now.window, { x = 40, y = 50, w = before.window.w, h = before.window.h })
    eq(now.board.x - now.window.x, before.board.x - before.window.x)
    eq(now.board.y - now.window.y, before.board.y - before.window.y)
    eq(layout:buttonRect("close").y, now.buttons.y)
end)

test("H04 C3: moved past an edge, the window rests against that edge, at the margin", function()
    for _, size in ipairs({ { 632, 840 }, { 840, 632 } }) do
        local w, h = size[1], size[2]
        local layout = new(w, h)
        local win = layout:rects().window
        layout:moveTo(-500, -500)
        eq(layout:rects().window.x, MARGIN); eq(layout:rects().window.y, MARGIN)
        layout:moveTo(5000, 5000)
        eq(layout:rects().window.x, w - MARGIN - win.w)
        eq(layout:rects().window.y, h - MARGIN - win.h)
        layout:moveTo(-1, 100)
        eq(layout:rects().window.x, MARGIN); eq(layout:rects().window.y, 100)
        assert(contains({ x = 0, y = 0, w = w, h = h }, layout:rects().window))
    end
end)

test("H04 C3: when the margins do not fit, the window rests against the screen edge", function()
    local layout = new(300, 220)
    local win = layout:rects().window
    assert(win.h + 2 * MARGIN > 220, "the window should not fit with margins here")
    layout:moveTo(5000, 5000)
    eq(layout:rects().window.y, math.max(0, 220 - win.h))
    layout:moveTo(-5000, -5000)
    eq(layout:rects().window.y, 0)
end)

test("H04: moveTo keeps whole pixels", function()
    local layout = new(632, 840)
    layout:moveTo(40.4, 50.6)
    eq(layout:rects().window.x, 40); eq(layout:rects().window.y, 51)
end)

local function row_point(layout)
    return center(layout:buttonRect("move"))
end

test("H04 C1: dragging the move button moves the window as far as the finger went", function()
    local layout = new(632, 840)
    local before = layout:rects().window
    local x, y = row_point(layout)
    eq(layout:startDrag(x, y, false), true)
    eq(layout:isDragging(), true)
    eq(layout:dragRect(x - 30, y - 200), { x = before.x - 30, y = before.y - 200,
        w = before.w, h = before.h })
    eq(layout:rects().window, before, "the window stays until the finger is lifted")
    eq(layout:endDrag(x - 40, y - 300), true)
    eq(layout:isDragging(), false)
    eq(layout:rects().window, { x = before.x - 40, y = before.y - 300, w = before.w, h = before.h })
end)

test("H04 C1: a drag that starts on a square is the window's but does not move it", function()
    local layout = new(632, 840)
    local before = layout:rects().window
    for _, flipped in ipairs({ false, true }) do
        local x, y = center(layout:squareRect(sq("e2"), flipped))
        eq(layout:startDrag(x, y, flipped), true)
        eq(layout:dragRect(x - 100, y - 100), nil)
        eq(layout:endDrag(x - 100, y - 100), false)
        eq(layout:isDragging(), false)
        eq(layout:rects().window, before)
    end
end)

test("H04 C2: the move button is pressed while it drags the window, and only then", function()
    local layout = new(632, 840)
    eq(layout:pressedButton(), nil)
    local x, y = row_point(layout)
    layout:startDrag(x, y, false)
    eq(layout:pressedButton(), "move")
    layout:endDrag(x - 30, y - 30)
    eq(layout:pressedButton(), nil, "lifted")
    local square_x, square_y = center(layout:squareRect(sq("e2"), false))
    layout:startDrag(square_x, square_y, false)
    eq(layout:pressedButton(), nil, "a drag from the board")
    layout:startDrag(x, y, false)
    layout:setOpen(false)
    eq(layout:pressedButton(), nil, "closed while dragging")
end)

test("H04: a drag that starts off the window, or with it closed, is not the window's", function()
    local layout = new(632, 840)
    local w = layout:rects().window
    eq(layout:startDrag(w.x - 1, w.y + 10, false), false)
    eq(layout:isDragging(), false)
    eq(layout:dragRect(10, 10), nil)
    eq(layout:endDrag(10, 10), false)
    eq(layout:rects().window, w)
    local x, y = row_point(layout)
    layout:setOpen(false)
    eq(layout:startDrag(x, y, false), false)
end)

test("H04 C5: the drag goes on wherever the finger goes, also off the window", function()
    local layout = new(632, 840)
    local w = layout:rects().window
    local x, y = row_point(layout)
    layout:startDrag(x, y, false)
    eq(layout:startDrag(x, y, false), true, "the same start goes on with the drag")
    assert(layout:dragRect(5, 5), "the finger left the window")
    eq(layout:endDrag(x, 5), true)
    eq(layout:rects().window.y, MARGIN)
    eq(layout:rects().window.x, w.x)
end)

test("H04: a new start point starts a new drag", function()
    local layout = new(632, 840)
    local x, y = row_point(layout)
    layout:startDrag(x, y, false)
    local square_x, square_y = center(layout:squareRect(sq("e4"), false))
    eq(layout:startDrag(square_x, square_y, false), true)
    eq(layout:dragRect(0, 0), nil, "this one started on the board")
end)

test("H04 C3: dropped past an edge, the window rests against the nearest edge", function()
    local layout = new(632, 840)
    local w = layout:rects().window
    local x, y = row_point(layout)
    layout:startDrag(x, y, false)
    local target = layout:dragRect(x + 2000, y + 15)
    eq(target.x, 632 - MARGIN - w.w, "the rect shown while dragging is kept on the screen too")
    layout:endDrag(x + 2000, y + 15)
    eq(layout:rects().window, { x = 632 - MARGIN - w.w, y = 840 - MARGIN - w.h, w = w.w, h = w.h })
end)

test("H04 C6: lifting the finger where it went down does not move the window", function()
    local layout = new(632, 840)
    local w = layout:rects().window
    local x, y = row_point(layout)
    layout:startDrag(x, y, false)
    eq(layout:endDrag(x, y), false)
    eq(layout:rects().window, w)
    eq(layout:isDragging(), false)
end)

test("H04 C4: the region to repaint after a drop covers where the window was and is", function()
    local layout = new(632, 840)
    local before = layout:rects()
    local x, y = row_point(layout)
    layout:startDrag(x, y, false)
    layout:endDrag(x - 100, y - 300)
    local dirty = layout:dirtyRect(before)
    assert(contains(dirty, before.window) and contains(dirty, layout:rects().window))
end)

test("H04: closing the window or turning the screen drops the drag", function()
    local layout = new(632, 840)
    local x, y = row_point(layout)
    layout:startDrag(x, y, false)
    layout:setOpen(false)
    eq(layout:isDragging(), false)
    layout:setOpen(true)
    layout:startDrag(x, y, false)
    layout:setScreen(840, 632)
    eq(layout:isDragging(), false)
end)

-- Coordinates outside the board ---------------------------------------------------------------

local function with_gutter(w, h)
    local sizes = {}
    for k, v in pairs(SIZES) do sizes[k] = v end
    sizes.gutter = 2.5
    local layout = Layout.new{ screen_w = w, screen_h = h, px_per_mm = PX_PER_MM, sizes = sizes }
    layout:setOpen(true)
    return layout
end

test("C7: without gutters each label is centred in its own square", function()
    local layout = new(632, 840)
    eq(layout:rects().files, nil); eq(layout:rects().ranks, nil)
    for _, flipped in ipairs({ false, true }) do
        for _, label in ipairs(layout:labels(flipped)) do
            eq(label.rect, layout:squareRect(label.square, flipped))
        end
    end
end)

test("C7: with gutters, ranks go in a strip left of the board and files in one under it",
    function()
        for _, size in ipairs(SCREENS) do
            local layout = with_gutter(size[1], size[2])
            local r = layout:rects()
            local g = 15 -- 2.5 mm at 150 dpi
            eq(r.ranks, { x = r.board.x - g, y = r.board.y, w = g, h = r.board.h })
            eq(r.files, { x = r.board.x, y = r.board.y + r.board.h, w = r.board.w, h = g })
            eq(r.buttons.y, r.files.y + g)
            eq(r.buttons.x, r.ranks.x); eq(r.buttons.w, r.board.w + g)
            for _, part in ipairs({ "ranks", "files", "board", "buttons" }) do
                assert(contains(r.window, r[part]), part)
            end
            for _, flipped in ipairs({ false, true }) do
                for _, label in ipairs(layout:labels(flipped)) do
                    local sq = layout:squareRect(label.square, flipped)
                    local strip = label.kind == "file" and r.files or r.ranks
                    assert(contains(strip, label.rect))
                    if label.kind == "file" then
                        eq(label.rect.x, sq.x); eq(label.rect.w, sq.w)
                    else
                        eq(label.rect.y, sq.y); eq(label.rect.h, sq.h)
                    end
                end
            end
        end
    end)

test("C7: the board keeps its size near 60 % when the gutters are added", function()
    eq(with_gutter(632, 840):squareSize(), new(632, 840):squareSize())
end)

test("C10: a tap on a gutter is the window's but not a square", function()
    local layout = with_gutter(632, 840)
    local r = layout:rects()
    eq(layout:hit(r.ranks.x + 2, r.ranks.y + 50, false), { zone = "board" })
    eq(layout:hit(r.files.x + 50, r.files.y + 2, false), { zone = "board" })
    for square = 1, 64 do
        local x, y = center(layout:squareRect(square, true))
        eq(layout:hit(x, y, true), { zone = "board", square = square })
    end
    local w = r.window
    for y = w.y, w.y + w.h - 1, 3 do
        for x = w.x, w.x + w.w - 1, 3 do
            assert(layout:hit(x, y, false), "nothing at " .. x .. "," .. y)
        end
    end
    eq(layout:hit(w.x, w.y + w.h - 1, false), { zone = "button", button = "move" })
end)

test("H04 C1: a drag from anywhere on the window but the move button is the window's and does "
    .. "not move it", function()
    local layout = with_gutter(632, 840)
    local r = layout:rects()
    local move, size = layout:buttonRect("move"), layout:buttonRect("size")
    local points = {
        { center(layout:buttonRect("close")) }, { center(layout:buttonRect("flip")) },
        { r.window.x, r.window.y }, { r.ranks.x + 2, r.ranks.y + 50 },
        { r.files.x + 50, r.files.y + 2 }, { move.x + move.w, move.y + 2 },
        { size.x + size.w, size.y + 2 },
    }
    for i, p in ipairs(points) do
        eq(layout:startDrag(p[1], p[2], false), true, "point " .. i)
        eq(layout:dragRect(p[1] - 10, p[2] - 20), nil, "point " .. i)
        eq(layout:endDrag(p[1] - 10, p[2] - 20), false, "point " .. i)
        eq(layout:rects().window, r.window, "point " .. i)
    end
end)

-- H07: where the turn is shown --------------------------------------------------------------

test("H07 C8: the corner where the coordinate strips meet is left for whose turn it is",
    function()
        for _, size in ipairs(SCREENS) do
            local r = with_gutter(size[1], size[2]):rects()
            eq(r.status, { x = r.ranks.x, y = r.files.y, w = r.ranks.w, h = r.files.h })
            assert(contains(r.window, r.status))
        end
        eq(new(632, 840):rects().status, nil)
    end)
