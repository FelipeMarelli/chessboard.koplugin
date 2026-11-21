-- Geometry of the floating window: where it is, its parts, its buttons and which part a point hits.
--
-- Rectangles are plain tables { x, y, w, h } in whole pixels. Sizes come in design pixels, the
-- pixels of a reference screen of 600 by 800, and are scaled to the screen (Layout.scaleFor).
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
-- upper buttons puts them, from the left, in the place of the strip of moves (after the others,
-- when there is no strip).
local MAIN_ROW = "main"
local MOVE_BUTTON = "move"
local PEEK_BUTTON = "peek"
local BACK_BUTTON = "back"
local ROWS = {
    main = { left = { PEEK_BUTTON, MOVE_BUTTON, "flip", "size", "reset", "edit" },
        right = { "close", "forward", "backward" } },
    size = { left = { BACK_BUTTON, "smaller", "bigger" }, right = {} },
    edit = { left = { BACK_BUTTON, "clear", "erase" }, right = {},
        upper = { "color", "king", "queen", "rook", "bishop", "knight", "pawn" } },
}
local OPENS = { size = "size", edit = "edit" }

-- Buttons that resize the board, with how many steps each takes. Each is disabled at the limit it
-- goes towards.
local RESIZES = { smaller = -1, bigger = 1 }

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
-- squares) and notation (height of the strip with the last moves, between the board and
-- the buttons; 0 or nil for none).
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
    }
    self.open = false
    self.row = MAIN_ROW
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
-- (H14).
function Layout:setScreen(screen_w, screen_h)
    local same = screen_w == self.screen_w and screen_h == self.screen_h
    self.screen_w, self.screen_h = screen_w, screen_h
    if same then
        self.square = self:fittedSquare(self.square)
        self:moveTo(self.x, self.y)
    else
        self.square = self:defaultSquare()
        self:placeDefault()
        self.drag = nil
    end
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

function Layout:windowSize()
    local p = self.px
    local framed = self:framedSide()
    return framed + 2 * p.border, framed + p.notation + p.row + 2 * p.border
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

-- The name of the row of buttons shown.
function Layout:shownRow()
    return self.row
end

-- Shows a row of buttons by its name.
function Layout:showRow(name)
    assert(ROWS[name], "no such row")
    self.row = name
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

function Layout:rects()
    local p = self.px
    local w, h = self:windowSize()
    local side = FILES * self.square
    local left, top = self.x + p.border, self.y + p.border
    local g, n = p.gutter, p.notation
    local framed = self:framedSide()
    local rects = {
        window = { x = self.x, y = self.y, w = w, h = h },
        board = { x = left + g, y = top + g, w = side, h = side },
        buttons = { x = left, y = top + framed + n, w = framed, h = p.row },
    }
    if n > 0 then
        rects.notation = { x = left, y = top + framed, w = framed, h = n }
    end
    if g > 0 then
        -- The board with the strips of coordinates around it: ranks left and right, files under
        -- and over it.
        rects.board_frame = { x = left, y = top, w = framed, h = framed }
        rects.ranks = { x = left, y = top + g, w = g, h = side }
        rects.ranks_right = { x = left + g + side, y = top + g, w = g, h = side }
        rects.files = { x = left + g, y = top + g + side, w = side, h = g }
        rects.files_top = { x = left + g, y = top, w = side, h = g }
        -- The corner where the left and the bottom strips meet shows whose turn it is.
        rects.status = { x = left, y = top + g + side, w = g, h = g }
    end
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
-- row under the board from left to right, then the upper ones (see ROWS).
function Layout:buttons()
    local rects = self:rects()
    local row = ROWS[self.row]
    local left, upper = row.left, row.upper
    if upper and not rects.notation then
        left, upper = concat(left, upper), nil
    end
    local list = {}
    add_buttons(self, list, rects.buttons, left, row.right)
    if upper then
        add_buttons(self, list, rects.notation, upper, {})
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
    end
    local board, inner = r.board, r.buttons
    x = clamp(x, inner.x, inner.x + inner.w - 1)
    y = clamp(y, r.window.y + self.px.border, inner.y + inner.h - 1)
    for _, button in ipairs(self:buttons()) do
        if inside(button.rect, x, y) and button.enabled then
            return { zone = "button", button = button.id, opens = Layout.rowOpenedBy(button.id) }
        end
    end
    if inside(board, x, y) then
        return { zone = "board", square = square_at(board, self.square, x, y, flipped) }
    elseif r.notation and inside(r.notation, x, y) then
        return { zone = "notation" }
    elseif y < r.buttons.y then
        return { zone = "board" }
    end
    return { zone = "button" }
end

-- Drags. A drag runs from the finger down to the finger up and is the window's when it starts on
-- the window, wherever the finger goes after. Only a drag that starts on the move button moves the
-- window; one that starts on the eye hides it until the finger is lifted; from anywhere else it
-- does nothing, and from the board above all, which is for playing.

-- Starts a drag with the finger down at x, y. False when the point is off the window: the drag is
-- the reader's. Called again with the same point, it goes on with the drag already started. With
-- locked, not even the move button moves the window, as while a promotion waits for its piece.
function Layout:startDrag(x, y, flipped, locked)
    local d = self.drag
    if d and d.x == x and d.y == y then
        return true
    end
    local hit = self:hit(x, y, flipped)
    self.drag = hit and { x = x, y = y, moves = not locked and hit.button == MOVE_BUTTON,
        hides = hit.button == PEEK_BUTTON } or nil
    return self.drag ~= nil
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

-- Ends the drag with the finger lifted at x, y, and leaves the window there. True when it moved.
function Layout:endDrag(x, y)
    local target = self:dragRect(x, y)
    self.drag = nil
    if not target or (target.x == self.x and target.y == self.y) then
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
