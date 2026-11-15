-- Geometry of the floating window: where it is, its parts, its buttons and which part a point hits.
--
-- Rectangles are plain tables { x, y, w, h } in whole pixels. Sizes come in millimetres and are
-- turned into pixels with the screen density, so the same numbers work on any screen.
local Layout = {}
Layout.__index = Layout

local BOARD_SHARE = 0.6 -- of the short side of the screen, on first open
local FILES = 8

-- Buttons of the top bar (right aligned) and of the bottom row (left aligned), in order.
local BAR_BUTTONS = { "close" }
local ROW_BUTTONS = { "flip" }

local function px(mm, px_per_mm)
    return math.max(1, math.floor(mm * px_per_mm + 0.5))
end

local function inside(rect, x, y)
    return x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

-- A layout for a screen. sizes, in millimetres: bar (height of the top bar), row (height of the
-- button row), button (width of a button), border, margin (to the screen edge), min_square.
function Layout.new(args)
    local self = setmetatable({}, Layout)
    local ppm = args.px_per_mm
    local sizes = args.sizes
    self.px = {
        bar = px(sizes.bar, ppm),
        row = px(sizes.row, ppm),
        button = px(sizes.button, ppm),
        border = px(sizes.border, ppm),
        margin = px(sizes.margin, ppm),
        min_square = px(sizes.min_square, ppm),
    }
    self.open = false
    self:setScreen(args.screen_w, args.screen_h)
    return self
end

-- The biggest square size that fits the screen, near the share of the short side asked for.
function Layout:defaultSquare()
    local p = self.px
    local wanted = math.floor(BOARD_SHARE * math.min(self.screen_w, self.screen_h) / FILES)
    local room_w = self.screen_w - 2 * (p.margin + p.border)
    local room_h = self.screen_h - 2 * (p.margin + p.border) - p.bar - p.row
    local fits = math.floor(math.min(room_w, room_h) / FILES)
    return math.max(p.min_square, math.min(wanted, fits))
end

-- Places the window for a screen size: centred, at the bottom. Later stories keep the place the
-- reader chose; for now there is only the default one.
function Layout:setScreen(screen_w, screen_h)
    self.screen_w, self.screen_h = screen_w, screen_h
    self.square = self:defaultSquare()
    local w, h = self:windowSize()
    self.x = math.floor((screen_w - w) / 2)
    self.y = math.max(0, screen_h - self.px.margin - h)
end

function Layout:windowSize()
    local p = self.px
    local side = FILES * self.square
    return side + 2 * p.border, side + p.bar + p.row + 2 * p.border
end

function Layout:setOpen(open)
    self.open = open and true or false
end

function Layout:isOpen()
    return self.open
end

function Layout:squareSize()
    return self.square
end

function Layout:rects()
    local p = self.px
    local w, h = self:windowSize()
    local side = FILES * self.square
    local left, top = self.x + p.border, self.y + p.border
    return {
        window = { x = self.x, y = self.y, w = w, h = h },
        titlebar = { x = left, y = top, w = side, h = p.bar },
        board = { x = left, y = top + p.bar, w = side, h = side },
        buttons = { x = left, y = top + p.bar + side, w = side, h = p.row },
    }
end

-- Every button with its id, its rect and whether it sits on the top bar or on the bottom row.
function Layout:buttons()
    local r = self:rects()
    local list = {}
    local bw = self.px.button
    for i, id in ipairs(BAR_BUTTONS) do
        local bar = r.titlebar
        list[#list + 1] = { id = id, place = "titlebar",
            rect = { x = bar.x + bar.w - i * bw, y = bar.y, w = bw, h = bar.h } }
    end
    for i, id in ipairs(ROW_BUTTONS) do
        local row = r.buttons
        list[#list + 1] = { id = id, place = "buttons",
            rect = { x = row.x + (i - 1) * bw, y = row.y, w = bw, h = row.h } }
    end
    return list
end

function Layout:buttonRect(id)
    for _, button in ipairs(self:buttons()) do
        if button.id == id then
            return button.rect
        end
    end
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

local function square_at(board, square, x, y, flipped)
    local col, row = math.floor((x - board.x) / square), math.floor((y - board.y) / square)
    if flipped then
        return row * FILES + (FILES - 1 - col) + 1
    end
    return (FILES - 1 - row) * FILES + col + 1
end

-- Which part of the window a point falls on, or nil when the window is closed or the point is
-- outside it. The thin border counts as the part next to it.
function Layout:hit(x, y, flipped)
    local r = self:rects()
    if not (self.open and inside(r.window, x, y)) then
        return nil
    end
    local board = r.board
    x = clamp(x, board.x, board.x + board.w - 1)
    y = clamp(y, r.titlebar.y, r.buttons.y + r.buttons.h - 1)
    for _, button in ipairs(self:buttons()) do
        if inside(button.rect, x, y) then
            return { zone = "button", button = button.id }
        end
    end
    if inside(r.titlebar, x, y) then
        return { zone = "titlebar" }
    elseif inside(board, x, y) then
        return { zone = "board", square = square_at(board, self.square, x, y, flipped) }
    end
    return { zone = "button" }
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
