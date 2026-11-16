-- Geometry of the floating window: where it is, its parts, its buttons and which part a point hits.
--
-- Rectangles are plain tables { x, y, w, h } in whole pixels. Sizes come in millimetres and are
-- turned into pixels with the screen density, so the same numbers work on any screen.
local Layout = {}
Layout.__index = Layout

local BOARD_SHARE = 0.6 -- of the short side of the screen, on first open
local FILES = 8

-- The rows of buttons under the board, by name. Each has its buttons from the left edge and from
-- the right edge, in order. The main row shows first; a button of OPENS shows another row instead
-- of acting, and the back button of any row shows the main one again. "move" is the one to drag
-- the window by; "backward" and "forward" step along the line of moves, next to close.
local MAIN_ROW = "main"
local MOVE_BUTTON = "move"
local BACK_BUTTON = "back"
local ROWS = {
    main = { left = { MOVE_BUTTON, "flip", "size", "reset", "edit" },
        right = { "close", "forward", "backward" } },
    size = { left = { BACK_BUTTON, "smaller", "bigger" }, right = {} },
    edit = { left = { BACK_BUTTON, "clear", "color", "king", "queen", "rook", "bishop", "knight",
        "pawn" }, right = {} },
}
local OPENS = { size = "size", edit = "edit" }

-- Buttons that resize the board, with how many steps each takes. Each is disabled at the limit it
-- goes towards.
local RESIZES = { smaller = -1, bigger = 1 }

local function px(mm, px_per_mm)
    return math.max(1, math.floor(mm * px_per_mm + 0.5))
end

local function inside(rect, x, y)
    return x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

-- A layout for a screen. sizes, in millimetres: row (height of the button row under the board),
-- button (width of a button), border, margin (to the screen edge), min_square, size_step (how much
-- the side of a square changes with each step of resize), and gutter (the strips left of and
-- under the board where the coordinates go; 0 or nil to put them on the squares).
function Layout.new(args)
    local self = setmetatable({}, Layout)
    local ppm = args.px_per_mm
    local sizes = args.sizes
    self.px = {
        row = px(sizes.row, ppm),
        button = px(sizes.button, ppm),
        border = px(sizes.border, ppm),
        margin = px(sizes.margin, ppm),
        min_square = px(sizes.min_square, ppm),
        size_step = px(sizes.size_step, ppm),
        gutter = (sizes.gutter or 0) > 0 and px(sizes.gutter, ppm) or 0,
    }
    self.open = false
    self.row = MAIN_ROW
    self:setScreen(args.screen_w, args.screen_h)
    return self
end

-- The biggest square size that fits the screen with the controls, and never under the minimum.
function Layout:maxSquare()
    local p = self.px
    local room_w = self.screen_w - 2 * (p.margin + p.border) - p.gutter
    local room_h = self.screen_h - 2 * (p.margin + p.border) - p.gutter - p.row
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

function Layout:windowSize()
    local p = self.px
    local side = FILES * self.square
    return side + p.gutter + 2 * p.border, side + p.gutter + p.row + 2 * p.border
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
    local g = p.gutter
    local rects = {
        window = { x = self.x, y = self.y, w = w, h = h },
        board = { x = left + g, y = top, w = side, h = side },
        buttons = { x = left, y = top + side + g, w = side + g, h = p.row },
    }
    if g > 0 then
        rects.ranks = { x = left, y = top, w = g, h = side }
        rects.files = { x = left + g, y = top + side, w = side, h = g }
        -- The corner where the two strips meet shows whose turn it is.
        rects.status = { x = left, y = top + side, w = g, h = g }
    end
    return rects
end

-- Every button of the row shown, with its id, its rect and whether it is enabled, from left to
-- right. When they do not all fit in the row at their usual width, they are narrowed until they do.
function Layout:buttons()
    local row = self:rects().buttons
    local list = {}
    local left, right = ROWS[self.row].left, ROWS[self.row].right
    local bw = math.min(self.px.button, math.floor(row.w / (#left + #right)))
    local function add(id, x)
        list[#list + 1] = { id = id, enabled = self:isEnabled(id),
            rect = { x = x, y = row.y, w = bw, h = row.h } }
    end
    for i, id in ipairs(left) do
        add(id, row.x + (i - 1) * bw)
    end
    for i = #right, 1, -1 do
        add(right[i], row.x + row.w - i * bw)
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

-- Each coordinate label with its square, its kind and the rect it is centred in: the gutter cell
-- next to the square when there are gutters, else the square itself.
function Layout:labels(flipped)
    local r = self:rects()
    local list = Layout.labelSquares(flipped)
    for _, label in ipairs(list) do
        local sq = self:squareRect(label.square, flipped)
        if not r.files then
            label.rect = sq
        elseif label.kind == "file" then
            label.rect = { x = sq.x, y = r.files.y, w = sq.w, h = r.files.h }
        else
            label.rect = { x = r.ranks.x, y = sq.y, w = r.ranks.w, h = sq.h }
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
-- without a square. A disabled button is like the row between buttons; one that shows another
-- row says which, in opens.
function Layout:hit(x, y, flipped)
    local r = self:rects()
    if not (self.open and inside(r.window, x, y)) then
        return nil
    end
    local board = r.board
    x = clamp(x, r.buttons.x, board.x + board.w - 1)
    y = clamp(y, board.y, r.buttons.y + r.buttons.h - 1)
    for _, button in ipairs(self:buttons()) do
        if inside(button.rect, x, y) and button.enabled then
            return { zone = "button", button = button.id, opens = Layout.rowOpenedBy(button.id) }
        end
    end
    if inside(board, x, y) then
        return { zone = "board", square = square_at(board, self.square, x, y, flipped) }
    elseif y < r.buttons.y then
        return { zone = "board" }
    end
    return { zone = "button" }
end

-- Drags. A drag runs from the finger down to the finger up and is the window's when it starts on
-- the window, wherever the finger goes after. Only a drag that starts on the move button moves the
-- window; from anywhere else it does nothing, and from the board above all, which is for playing.

-- Starts a drag with the finger down at x, y. False when the point is off the window: the drag is
-- the reader's. Called again with the same point, it goes on with the drag already started.
function Layout:startDrag(x, y, flipped)
    local d = self.drag
    if d and d.x == x and d.y == y then
        return true
    end
    local hit = self:hit(x, y, flipped)
    self.drag = hit and { x = x, y = y, moves = hit.button == MOVE_BUTTON } or nil
    return self.drag ~= nil
end

function Layout:isDragging()
    return self.drag ~= nil
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
