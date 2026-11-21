-- Geometry of the split screen: the book on one part of the screen and the board on the other.
--
-- The screen is split across its long side: in portrait the book is above or below the board, in
-- landscape on its left or its right. The board takes the whole of its part across the split, and
-- its buttons go beside it, on the far side from the book: to its right in portrait, under it in
-- landscape. A divider on the edge of the board's part, next to the book, is dragged to give
-- the book more or less room. Rectangles are plain tables { x, y, w, h } in whole pixels.
local Split = {}

local FILES = 8

-- The share of the screen, along the split, the book takes on first split.
Split.TEXT_SHARE = 0.5
-- The least share of the screen, along the split, kept for the book.
Split.MIN_TEXT_SHARE = 0.25

-- The axis the screen is split along: "y" when it is taller than wide, else "x".
function Split.axis(screen_w, screen_h)
    return screen_h >= screen_w and "y" or "x"
end

-- A rect from where it starts and how long it is along the axis of the split (a, len) and across
-- it (b, cross).
local function along(axis, a, len, b, cross)
    if axis == "y" then
        return { x = b, y = a, w = cross, h = len }
    end
    return { x = a, y = b, w = len, h = cross }
end

-- The length of the screen along the axis of the split, and across it.
local function lengths(axis, screen_w, screen_h)
    if axis == "y" then
        return screen_h, screen_w
    end
    return screen_w, screen_h
end

-- The side of the smallest board, with its coordinates, that the board's part has to hold.
local function min_framed(px)
    return FILES * px.min_square + 2 * px.gutter
end

-- The least and the most room, along the split, the book can take on a screen: the board's part
-- keeps room for the smallest board, and the book keeps its least share.
function Split.textLimits(screen_w, screen_h, px)
    local long = lengths(Split.axis(screen_w, screen_h), screen_w, screen_h)
    local panel = min_framed(px) + 2 * px.border + px.divider
    local least = math.floor(Split.MIN_TEXT_SHARE * long + 0.5)
    return least, math.max(least, long - panel)
end

-- A room for the book along the split, kept within its limits.
function Split.fitText(screen_w, screen_h, px, text)
    local least, most = Split.textLimits(screen_w, screen_h, px)
    return math.max(least, math.min(most, math.floor(text + 0.5)))
end

-- The room, along the split, the book takes with a share of the screen, within its limits.
function Split.textLength(screen_w, screen_h, px, share)
    local long = lengths(Split.axis(screen_w, screen_h), screen_w, screen_h)
    return Split.fitText(screen_w, screen_h, px, share * long)
end

-- The share of the screen, along the split, that a room for the book is.
function Split.shareOf(screen_w, screen_h, text)
    local long = lengths(Split.axis(screen_w, screen_h), screen_w, screen_h)
    return text / long
end

-- The book's part, the board's part with the divider at its edge next to the book, and the room
-- inside the board's part for the board and its buttons, along and across the split.
local function parts(axis, long, cross, px, text_first, text)
    local panel = long - text
    local book_at = text_first and 0 or panel
    local panel_at = text_first and text or 0
    local divider_at = text_first and panel_at or panel - px.divider
    local inner_at = panel_at + (text_first and px.divider or 0) + px.border
    return {
        reader = along(axis, book_at, text, 0, cross),
        window = along(axis, panel_at, panel, 0, cross),
        divider = along(axis, divider_at, px.divider, 0, cross),
        inner = along(axis, inner_at, panel - px.divider - 2 * px.border, px.border,
            cross - 2 * px.border),
    }
end

-- The board with its coordinate strips at the start of inner across the split, centred along it,
-- as big as fits while leaving the buttons their least room beside it.
local function place_board(axis, inner, px)
    local inner_along, inner_cross = lengths(axis, inner.w, inner.h)
    local inner_a, inner_b = lengths(axis, inner.x, inner.y)
    local room = math.min(inner_along, inner_cross - px.split_controls - px.spacing)
    local square = math.max(px.min_square, math.floor((room - 2 * px.gutter) / FILES))
    local framed = FILES * square + 2 * px.gutter
    local frame = along(axis, inner_a + math.floor((inner_along - framed) / 2), framed, inner_b,
        framed)
    local controls_b = inner_b + framed + px.spacing
    local controls = along(axis, inner_a, inner_along, controls_b,
        inner_b + inner_cross - controls_b)
    return square, frame, controls
end

-- Every rect of the split, as Layout:rects names them, and the side of a square. args: screen_w,
-- screen_h, px (the sizes in pixels, as Layout keeps them), text_first (the book above or on the
-- left) and text (its room along the split, from Split.textLength).
function Split.rects(args)
    local px = args.px
    local axis = Split.axis(args.screen_w, args.screen_h)
    local long, cross = lengths(axis, args.screen_w, args.screen_h)
    local rects = parts(axis, long, cross, px, args.text_first, args.text)
    local square, frame, controls = place_board(axis, rects.inner, px)
    local g, side = px.gutter, FILES * square
    rects.board = { x = frame.x + g, y = frame.y + g, w = side, h = side }
    if px.notation > 0 then
        rects.notation = { x = controls.x, y = controls.y, w = controls.w, h = px.notation }
    end
    rects.buttons = { x = controls.x, y = controls.y + px.notation, w = controls.w,
        h = controls.h - px.notation }
    return rects, square, frame
end

-- The cells of a grid of count buttons in rect, from the top left, row by row: as many columns as
-- make the smaller side of a cell the biggest, all the same size, the grid centred in rect.
function Split.grid(rect, count)
    local best
    for columns = 1, count do
        local rows = math.ceil(count / columns)
        local w, h = math.floor(rect.w / columns), math.floor(rect.h / rows)
        if not best or math.min(w, h) > math.min(best.w, best.h) then
            best = { columns = columns, rows = rows, w = w, h = h }
        end
    end
    local x0 = rect.x + math.floor((rect.w - best.columns * best.w) / 2)
    local y0 = rect.y + math.floor((rect.h - best.rows * best.h) / 2)
    local cells = {}
    for i = 1, count do
        local col, row = (i - 1) % best.columns, math.floor((i - 1) / best.columns)
        cells[i] = { x = x0 + col * best.w, y = y0 + row * best.h, w = best.w, h = best.h }
    end
    return cells
end

-- How far the divider moved along the split when a finger went from one point to another.
function Split.travel(screen_w, screen_h, from_x, from_y, to_x, to_y)
    if Split.axis(screen_w, screen_h) == "y" then
        return to_y - from_y
    end
    return to_x - from_x
end

return Split
