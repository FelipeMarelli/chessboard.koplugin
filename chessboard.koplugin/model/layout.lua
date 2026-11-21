-- Geometry of the floating window: where it is, its parts, its buttons and which part a point hits.
--
-- Rectangles are plain tables { x, y, w, h } in whole pixels. Sizes come in design pixels, the
-- pixels of a reference screen of 600 by 800, and are scaled to the screen (Layout.scaleFor).
--
-- The window is either floating over the page or split: on a part of the screen of its own, with
-- the book on the other part (model/split.lua).
local Split = require("model/split")

local Layout = {}
Layout.__index = Layout

-- The reference screen of the design pixels: its short side and its long side.
local REFERENCE_SHORT, REFERENCE_LONG = 600, 800

local BOARD_SHARE = 0.6 -- of the short side of the screen, on first open
local FILES = 8

-- The rows of buttons under the board, by name. Each has its buttons from the left edge and from
-- the right edge, in order. The main row shows first; a button of OPENS shows another row instead
-- of acting, and the back button of any row shows the main one again. "peek" hides the window
-- while the finger is on it; "move" is the one to drag the window by; "backward" and "forward"
-- step along the line of moves, next to close. A row with
-- upper buttons puts them after the others when they all fit there at their usual width, and the
-- window has no strip of moves while it shows; else, from the left, in the place of the strip.
local MAIN_ROW = "main"
local MOVE_BUTTON = "move"
local PEEK_BUTTON = "peek"
local BACK_BUTTON = "back"
local ROWS = {
    main = { left = { PEEK_BUTTON, MOVE_BUTTON, "flip", "size", "reset", "edit" },
        right = { "close", "forward", "backward" } },
    size = { left = { BACK_BUTTON, "smaller", "bigger", "split" }, right = {} },
    edit = { left = { BACK_BUTTON, "clear", "erase" }, right = {},
        upper = { "color", "king", "queen", "rook", "bishop", "knight", "pawn" } },
}
local OPENS = { size = "size", edit = "edit" }

-- The buttons of each row while split, in a grid beside the board, from the top left. "swap" puts
-- the book and the board the other way round, and "float" takes the window back over the page.
-- The eye has no page under the board to show, and the window is moved and sized by the divider.
local SPLIT_ROWS = {
    main = { "backward", "forward", "flip", "reset", "edit", "swap", "float", "close" },
    edit = { "color", "king", "queen", "rook", "bishop", "knight", "pawn", BACK_BUTTON, "clear",
        "erase" },
}

-- Buttons that resize the board, with how many steps each takes. Each is disabled at the limit it
-- goes towards.
local RESIZES = { smaller = -1, bigger = 1 }

local function contains_id(ids, id)
    for _, each in ipairs(ids or {}) do
        if each == id then
            return true
        end
    end
    return false
end

-- How many pixels of a screen a design pixel takes: as much as the reference screen grows to fit
-- in it, by its short and long sides, so turning the screen does not change it.
function Layout.scaleFor(screen_w, screen_h)
    local short, long = math.min(screen_w, screen_h), math.max(screen_w, screen_h)
    return math.min(short / REFERENCE_SHORT, long / REFERENCE_LONG)
end

-- A size in design pixels on a screen of a scale, in whole pixels and never under one.
function Layout.px(size, scale)
    return math.max(1, math.floor(size * scale + 0.5))
end

-- A size that may be left out: 0 when it is nil or 0.
local function optional_px(size, scale)
    return (size or 0) > 0 and Layout.px(size, scale) or 0
end

local function inside(rect, x, y)
    return x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

-- A layout for a screen. scale: Layout.scaleFor the screen. sizes, in design pixels: row (height
-- of the button row under the board), button (width of a button), border, margin (to the screen
-- edge), min_square, size_step (how much the side of a square changes with each step of resize),
-- gutter (the strips around the board where the coordinates go; 0 or nil to put them on the
-- squares), notation (height of the strip with the last moves, between the board and
-- the buttons; 0 or nil for none), spacing (the gap left in place of the strip when a row
-- takes it, and between the board and its buttons while split; 0 or nil for none), divider (how
-- thick the divider of the split is) and split_controls (the least room beside the board for its
-- buttons while split).
function Layout.new(args)
    local self = setmetatable({}, Layout)
    local scale = args.scale
    local sizes = args.sizes
    local px = Layout.px
    self.px = {
        row = px(sizes.row, scale),
        button = px(sizes.button, scale),
        border = px(sizes.border, scale),
        margin = px(sizes.margin, scale),
        min_square = px(sizes.min_square, scale),
        size_step = px(sizes.size_step, scale),
        gutter = optional_px(sizes.gutter, scale),
        notation = optional_px(sizes.notation, scale),
        spacing = optional_px(sizes.spacing, scale),
        divider = optional_px(sizes.divider, scale),
        split_controls = optional_px(sizes.split_controls, scale),
    }
    self.open = false
    self.row = MAIN_ROW
    self.split = false
    self.text_first = true
    self.text_share = Split.TEXT_SHARE
    self:setScreen(args.screen_w, args.screen_h)
    return self
end

-- The biggest square size that fits the screen with the controls, and never under the minimum.
function Layout:maxSquare()
    local p = self.px
    local room_w = self.screen_w - 2 * (p.margin + p.border + p.gutter)
    local room_h = self.screen_h - 2 * (p.margin + p.border + p.gutter) - p.notation - p.row
    return math.max(p.min_square, math.floor(math.min(room_w, room_h) / FILES))
end

-- A square size within the limits: the minimum and the biggest that fits.
function Layout:fittedSquare(size)
    return clamp(size, self.px.min_square, self:maxSquare())
end

-- The square size the window opens with: near the share of the short side asked for.
function Layout:defaultSquare()
    return self:fittedSquare(
        math.floor(BOARD_SHARE * math.min(self.screen_w, self.screen_h) / FILES))
end

-- Sets the screen size. The same size keeps the window where it is, and its size; a new one (the
-- screen turned) puts it back in the default place and size, until each orientation keeps its own
-- (H14). Split, it stays split. True when the size is new.
function Layout:setScreen(screen_w, screen_h)
    local same = screen_w == self.screen_w and screen_h == self.screen_h
    self.screen_w, self.screen_h = screen_w, screen_h
    if self.split then
        -- The floating window goes back to the default place on a turned screen.
        self.floating = same and self.floating or nil
        self.drag = same and self.drag or nil
        self:fitSplit()
        return not same
    elseif same then
        self.square = self:fittedSquare(self.square)
        self:moveTo(self.x, self.y)
    else
        self.square = self:defaultSquare()
        self:placeDefault()
        self.drag = nil
    end
    return not same
end

-- Centred, at the bottom.
function Layout:placeDefault()
    local w, h = self:windowSize()
    self.x = math.floor((self.screen_w - w) / 2)
    self.y = math.max(0, self.screen_h - self.px.margin - h)
end

-- One coordinate of the window, kept on the screen and off its edge by the margin when there is
-- room for it.
local function fit(pos, size, screen, margin)
    if size + 2 * margin > screen then
        margin = 0
    end
    return clamp(math.floor(pos + 0.5), margin, math.max(margin, screen - margin - size))
end

-- The window rect with its top left corner at x, y, or at the nearest place that keeps it on the
-- screen.
function Layout:fittedRect(x, y)
    local w, h = self:windowSize()
    local margin = self.px.margin
    return { x = fit(x, w, self.screen_w, margin), y = fit(y, h, self.screen_h, margin),
        w = w, h = h }
end

function Layout:moveTo(x, y)
    local rect = self:fittedRect(x, y)
    self.x, self.y = rect.x, rect.y
end

-- The side of the board with the strips of coordinates around it, as wide as the rows below it.
function Layout:framedSide()
    return FILES * self.square + 2 * self.px.gutter
end

-- True when the row shown has upper buttons and there is room for all of them in the row under
-- the board, at their usual width.
function Layout:isOneRow()
    local row = ROWS[self.row]
    local count = #row.left + #row.right + #(row.upper or {})
    return row.upper ~= nil and count * self.px.button <= self:framedSide()
end

-- The height of the strip of moves, or, while the row shown takes all its buttons in one row, of
-- the gap that sets them apart from the board in its place.
function Layout:stripHeight()
    return self:isOneRow() and self.px.spacing or self.px.notation
end

function Layout:windowSize()
    local p = self.px
    local framed = self:framedSide()
    return framed + 2 * p.border, framed + self:stripHeight() + p.row + 2 * p.border
end

-- Opening or closing the window drops the drag and shows the main row.
function Layout:setOpen(open)
    self.open = open and true or false
    self.drag = nil
    self.row = MAIN_ROW
end

function Layout:isOpen()
    return self.open
end

function Layout:squareSize()
    return self.square
end

-- The square size after some steps of resize (negative to shrink), within the limits.
function Layout:resizedSquare(steps)
    return self:fittedSquare(self.square + steps * self.px.size_step)
end

-- True when some steps of resize would change the size: false at the limit they go towards.
function Layout:canResize(steps)
    return self:resizedSquare(steps) ~= self.square
end

-- Grows (steps > 0) or shrinks the board by some steps, up to its limits. The top left corner
-- stays, unless the window would go off the screen. True when the size changed.
function Layout:resize(steps)
    if not self:canResize(steps) then
        return false
    end
    self.square = self:resizedSquare(steps)
    self:moveTo(self.x, self.y)
    return true
end

-- Split ----------------------------------------------------------------------------------------

function Layout:isSplit()
    return self.split
end

-- True when the book is above the board (portrait) or on its left (landscape).
function Layout:isTextFirst()
    return self.text_first
end

-- The axis the screen is split along: "y" in portrait, "x" in landscape.
function Layout:splitAxis()
    return Split.axis(self.screen_w, self.screen_h)
end

-- The room the book takes along the split.
function Layout:textLength()
    return Split.textLength(self.screen_w, self.screen_h, self.px, self.text_share)
end

function Layout:splitRects()
    return Split.rects{ screen_w = self.screen_w, screen_h = self.screen_h, px = self.px,
        text_first = self.text_first, text = self:textLength() }
end

-- The board takes the biggest square that fits its part of the screen.
function Layout:fitSplit()
    local _, square = self:splitRects()
    self.square = square
end

-- Splits the screen (true) or takes the window back over the page (false), with the main row.
-- The floating window comes back where it was and as big, unless the screen turned meanwhile.
-- True when it changed.
function Layout:setSplit(split)
    split = split and true or false
    if split == self.split then
        return false
    end
    self.drag = nil
    self.row = MAIN_ROW
    self.split = split
    if split then
        self.floating = { square = self.square, x = self.x, y = self.y }
        self:fitSplit()
        return true
    end
    local floating = self.floating
    self.floating = nil
    if floating then
        self.square = self:fittedSquare(floating.square)
        self:moveTo(floating.x, floating.y)
    else
        self.square = self:defaultSquare()
        self:placeDefault()
    end
    return true
end

-- Puts the book and the board the other way round. True when split.
function Layout:swapSplit()
    if not self.split then
        return false
    end
    self.text_first = not self.text_first
    return true
end

-- Gives the book a room along the split, within its limits. True when the divider moved.
function Layout:setTextLength(text)
    local before = self:textLength()
    local fitted = Split.fitText(self.screen_w, self.screen_h, self.px, text)
    self.text_share = Split.shareOf(self.screen_w, self.screen_h, fitted)
    self:fitSplit()
    return self:textLength() ~= before
end

-- Moves the divider by some pixels along the split, towards the board when positive.
function Layout:moveDivider(travel)
    local text = self:textLength()
    return self:setTextLength(self.text_first and text + travel or text - travel)
end

-- The part of the screen the book is to be shown in while split and open; nil when it has the
-- whole screen.
function Layout:readerRect()
    if self.open and self.split then
        return self:splitRects().reader
    end
end

-- The name of the row of buttons shown.
function Layout:shownRow()
    return self.row
end

-- Shows a row of buttons by its name. The window is shorter while a row fits in one line (see
-- ROWS), and is kept on the screen when it grows back. Returns whether the window changed size
-- and whether it grew.
function Layout:showRow(name)
    assert(ROWS[name] and (SPLIT_ROWS[name] or not self.split), "no such row")
    local _, before = self:windowSize()
    self.row = name
    self:moveTo(self.x, self.y)
    local _, after = self:windowSize()
    return after ~= before, after > before
end

-- The name of the row a button shows when tapped, or nil when the button acts instead.
function Layout.rowOpenedBy(id)
    return OPENS[id] or (id == BACK_BUTTON and MAIN_ROW or nil)
end

-- False for a button that would do nothing now, such as shrinking a board at its minimum.
function Layout:isEnabled(id)
    local steps = RESIZES[id]
    return steps == nil or self:canResize(steps)
end

-- Adds to rects the board with the strips of coordinates around it, in frame: ranks left and
-- right, files under and over it. g: the width of a strip.
local function add_gutters(rects, frame, g)
    if g <= 0 then
        return
    end
    local left, top, side = frame.x, frame.y, frame.w - 2 * g
    rects.board_frame = frame
    rects.ranks = { x = left, y = top + g, w = g, h = side }
    rects.ranks_right = { x = left + g + side, y = top + g, w = g, h = side }
    rects.files = { x = left + g, y = top + g + side, w = side, h = g }
    rects.files_top = { x = left + g, y = top, w = side, h = g }
    -- The corner where the left and the bottom strips meet shows whose turn it is.
    rects.status = { x = left, y = top + g + side, w = g, h = g }
end

-- The rects of the window: window, board, buttons (the row or the grid of buttons), inner (inside
-- the border, where a point is taken to the nearest part), and notation, board_frame and the
-- strips of coordinates when there are. While split, also reader (the book's part of the screen)
-- and divider.
function Layout:rects()
    if self.split then
        local rects, _, frame = self:splitRects()
        add_gutters(rects, frame, self.px.gutter)
        return rects
    end
    local p = self.px
    local w, h = self:windowSize()
    local side = FILES * self.square
    local left, top = self.x + p.border, self.y + p.border
    local g, n = p.gutter, self:stripHeight()
    local framed = self:framedSide()
    local rects = {
        window = { x = self.x, y = self.y, w = w, h = h },
        inner = { x = left, y = top, w = w - 2 * p.border, h = h - 2 * p.border },
        board = { x = left + g, y = top + g, w = side, h = side },
        buttons = { x = left, y = top + framed + n, w = framed, h = p.row },
    }
    if n > 0 and not self:isOneRow() then
        rects.notation = { x = left, y = top + framed, w = framed, h = n }
    end
    add_gutters(rects, { x = left, y = top, w = framed, h = framed }, g)
    return rects
end

local function concat(a, b)
    local all = { unpack(a) }
    for _, id in ipairs(b) do
        all[#all + 1] = id
    end
    return all
end

-- Adds to list the buttons side by side in rect: left ones from its left edge, right ones from
-- its right edge. When they do not all fit at their usual width, they are narrowed until they do.
local function add_buttons(self, list, rect, left, right)
    local bw = math.min(self.px.button, math.floor(rect.w / (#left + #right)))
    local function add(id, x)
        list[#list + 1] = { id = id, enabled = self:isEnabled(id),
            rect = { x = x, y = rect.y, w = bw, h = rect.h } }
    end
    for i, id in ipairs(left) do
        add(id, rect.x + (i - 1) * bw)
    end
    for i = #right, 1, -1 do
        add(right[i], rect.x + rect.w - i * bw)
    end
end

-- Every button of the row shown, with its id, its rect and whether it is enabled: those of the
-- row under the board from left to right, then the upper ones (see ROWS), marked upper wherever
-- they go.
function Layout:buttons()
    local rects = self:rects()
    local row = ROWS[self.row]
    if self.split then
        local ids = SPLIT_ROWS[self.row]
        local list = {}
        for i, cell in ipairs(Split.grid(rects.buttons, #ids)) do
            local id = ids[i]
            list[i] = { id = id, enabled = self:isEnabled(id), rect = cell,
                upper = contains_id(row.upper, id) or nil }
        end
        return list
    end
    local left, upper = row.left, row.upper
    if upper and not rects.notation then
        left, upper = concat(left, upper), nil
    end
    local list = {}
    add_buttons(self, list, rects.buttons, left, row.right)
    if upper then
        add_buttons(self, list, rects.notation, upper, {})
    end
    for _, button in ipairs(list) do
        button.upper = contains_id(row.upper, button.id) or nil
    end
    return list
end

-- One button of the row shown, as buttons() gives it, or nil when the row has no such button.
function Layout:button(id)
    for _, button in ipairs(self:buttons()) do
        if button.id == id then
            return button
        end
    end
end

function Layout:buttonRect(id)
    local button = self:button(id)
    return button and button.rect
end

-- The column and row on screen (0 to 7, from the top left) of a square.
local function cell(sq, flipped)
    local file, rank = (sq - 1) % FILES, math.floor((sq - 1) / FILES)
    if flipped then
        return FILES - 1 - file, rank
    end
    return file, FILES - 1 - rank
end

function Layout:squareRect(sq, flipped)
    local board = self:rects().board
    local col, row = cell(sq, flipped)
    local s = self.square
    return { x = board.x + col * s, y = board.y + row * s, w = s, h = s }
end

-- The squares that carry the coordinate labels: the bottom row shows its file and the left column
-- its rank, whichever way round the board is.
function Layout.labelSquares(flipped)
    local list = {}
    for i = 1, FILES do
        local bottom = flipped and (FILES * FILES + 1 - i) or i
        local left = flipped and (FILES * FILES - (i - 1) * FILES) or ((i - 1) * FILES + 1)
        list[#list + 1] = { square = bottom, kind = "file" }
        list[#list + 1] = { square = left, kind = "rank" }
    end
    return list
end

-- The cell of a gutter strip next to a square: in line with its column for a strip of files, with
-- its row for one of ranks.
local function gutter_cell(strip, sq, kind)
    if kind == "file" then
        return { x = sq.x, y = strip.y, w = sq.w, h = strip.h }
    end
    return { x = strip.x, y = sq.y, w = strip.w, h = sq.h }
end

-- The strips each kind of label goes in when there are gutters: both sides of the board.
local STRIPS = { file = { "files", "files_top" }, rank = { "ranks", "ranks_right" } }

-- Each coordinate label with its square, its kind and the rect it is centred in: without gutters
-- the square itself; with them, the cell next to the square in each strip of its kind, so every
-- file shows over and under the board and every rank on its left and its right.
function Layout:labels(flipped)
    local r = self:rects()
    local list = {}
    for _, label in ipairs(Layout.labelSquares(flipped)) do
        local sq = self:squareRect(label.square, flipped)
        if not r.files then
            list[#list + 1] = { square = label.square, kind = label.kind, rect = sq }
        else
            for _, strip in ipairs(STRIPS[label.kind]) do
                list[#list + 1] = { square = label.square, kind = label.kind,
                    rect = gutter_cell(r[strip], sq, label.kind) }
            end
        end
    end
    return list
end

local function square_at(board, square, x, y, flipped)
    local col, row = math.floor((x - board.x) / square), math.floor((y - board.y) / square)
    if flipped then
        return row * FILES + (FILES - 1 - col) + 1
    end
    return (FILES - 1 - row) * FILES + col + 1
end

-- Which part of the window a point falls on, or nil when the window is closed or the point is
-- outside it. The thin border counts as the part next to it, and the gutters as the board,
-- without a square; the strip of moves is its own zone, which does nothing. A disabled button is
-- like the row between buttons; one that shows another row says which, in opens.
function Layout:hit(x, y, flipped)
    local r = self:rects()
    if not (self.open and inside(r.window, x, y)) then
        return nil
    elseif r.divider and inside(r.divider, x, y) then
        return { zone = "divider" }
    end
    local board, inner = r.board, r.inner
    x = clamp(x, inner.x, inner.x + inner.w - 1)
    y = clamp(y, inner.y, inner.y + inner.h - 1)
    for _, button in ipairs(self:buttons()) do
        if inside(button.rect, x, y) and button.enabled then
            return { zone = "button", button = button.id, opens = Layout.rowOpenedBy(button.id) }
        end
    end
    if inside(board, x, y) then
        return { zone = "board", square = square_at(board, self.square, x, y, flipped) }
    elseif r.notation and inside(r.notation, x, y) then
        return { zone = "notation" }
    elseif not inside(r.buttons, x, y) then
        return { zone = "board" }
    end
    return { zone = "button" }
end

-- Drags. A drag runs from the finger down to the finger up and is the window's when it starts on
-- the window, wherever the finger goes after. Only a drag that starts on the move button moves the
-- window, and one that starts on the divider of the split screen moves the divider; one that
-- starts on the eye hides the window until the finger is lifted; from anywhere else it does
-- nothing, and from the board above all, which is for playing.

-- Starts a drag with the finger down at x, y. False when the point is off the window: the drag is
-- the reader's. Called again with the same point, it goes on with the drag already started. With
-- locked, not even the move button moves the window, as while a promotion waits for its piece.
function Layout:startDrag(x, y, flipped, locked)
    local d = self.drag
    if d and d.x == x and d.y == y then
        return true
    end
    local hit = self:hit(x, y, flipped)
    if not hit then
        self.drag = nil
        return false
    end
    local moves = not locked and hit.button == MOVE_BUTTON
    self.drag = { x = x, y = y, moves = moves, divides = not locked and hit.zone == "divider",
        hides = hit.button == PEEK_BUTTON }
    return true
end

function Layout:isDragging()
    return self.drag ~= nil
end

-- True while the finger that went down on the eye is still down: the window is not shown.
function Layout:isHidden()
    local d = self.drag
    return d ~= nil and d.hides
end

-- The id of the button held down to drag the window, so that it can be marked while the finger is
-- on it; nil when no drag that moves the window is going on.
function Layout:pressedButton()
    local d = self.drag
    return d and d.moves and MOVE_BUTTON or nil
end

-- Where the window would be if the finger, now at x, y, were lifted: a window rect, kept on the
-- screen. Nil when no drag that moves the window is going on.
function Layout:dragRect(x, y)
    local d = self.drag
    if not (d and d.moves) then
        return nil
    end
    return self:fittedRect(self.x + x - d.x, self.y + y - d.y)
end

-- Ends the drag with the finger lifted at x, y, and leaves the window, or the divider, there. True
-- when it moved.
function Layout:endDrag(x, y)
    local d = self.drag
    local target = self:dragRect(x, y)
    self.drag = nil
    if d and d.divides then
        return self:moveDivider(Split.travel(self.screen_w, self.screen_h, d.x, d.y, x, y))
    elseif not target or (target.x == self.x and target.y == self.y) then
        return false
    end
    self:moveTo(target.x, target.y)
    return true
end

-- The smallest rect that covers both the window as it was (rects taken before a change) and as
-- it is now. Without previous rects, the window as it is.
function Layout:dirtyRect(previous)
    local now = self:rects().window
    local before = previous and previous.window
    if not before then
        return { x = now.x, y = now.y, w = now.w, h = now.h }
    end
    local x, y = math.min(now.x, before.x), math.min(now.y, before.y)
    local right = math.max(now.x + now.w, before.x + before.w)
    local bottom = math.max(now.y + now.h, before.y + before.h)
    return { x = x, y = y, w = right - x, h = bottom - y }
end

return Layout
