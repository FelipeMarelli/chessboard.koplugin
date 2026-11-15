-- The floating window: paints it over the page and turns taps on it into calls to the model.
--
-- It is a view module of the reader, not a widget shown by UIManager, so that taps outside it
-- still reach the reader.
local Board = require("ui/board")
local Device = require("device")
local Geom = require("ui/geometry")
local Theme = require("ui/theme")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local Screen = Device.screen

local Window = {}
Window.__index = Window

-- view: the ReaderView; layout and session: the models it shows.
function Window.new(view, layout, session)
    return setmetatable({ view = view, layout = layout, session = session }, Window)
end

-- Asks for one repaint of a region of the screen; the page under it is painted again first.
--
-- A plain "ui" refresh does not flash, but on e-ink it leaves a ghost of the text the window
-- covers, most visible on the gray squares. When the window covers new text (opening, growing) it
-- uses "flashui": the region flashes once and the ghost goes. Uncovering text is clean without it.
function Window:refresh(rect, covers_text)
    UIManager:setDirty(self.view.dialog, covers_text and "flashui" or "ui", Geom:new(rect))
end

function Window:setOpen(open)
    self.layout:setOpen(open)
    self:refresh(self.layout:dirtyRect(), open)
end

function Window:toggle()
    self:setOpen(not self.layout:isOpen())
end

-- Grows (steps > 0) or shrinks the board. The window is repainted where it was and where it is,
-- with a flash when it grows over the page.
local function resize(self, steps)
    local before = self.layout:rects()
    if self.layout:resize(steps) then
        self:refresh(self.layout:dirtyRect(before), steps > 0)
    end
end

-- Repaints the window when a tap changed what it shows.
local function repaint_if(self, changed)
    if changed then
        self:refresh(self.layout:dirtyRect())
    end
end

local ACTIONS = {
    close = function(self) self:setOpen(false) end,
    flip = function(self)
        self.session:flip()
        self:refresh(self.layout:dirtyRect())
    end,
    reset = function(self) repaint_if(self, self.session:reset()) end,
    smaller = function(self) resize(self, -1) end,
    bigger = function(self) resize(self, 1) end,
}

-- Shows another row of buttons in place of the one shown; only the row is repainted.
local function show_row(self, name)
    self.layout:showRow(name)
    self:refresh(self.layout:rects().buttons)
end

-- A tap on a square of the board. Until the promotion picker comes (H08), a pawn that reaches
-- the last rank becomes a queen.
local function tap_square(self, sq)
    local result = self.session:tapSquare(sq)
    if result.needs_promotion then
        result = self.session:choosePromotion("q")
    end
    repaint_if(self, result.changed)
end

-- Runs what a tap does; a failure closes the window, so that the reader can go on.
function Window:run(name, action, ...)
    local ok, err = pcall(action, self, ...)
    if not ok then
        logger.err("chessbook:", name, "failed:", err)
        self:setOpen(false)
    end
end

-- True when the tap was on the window, so that the reader does not get it.
function Window:onTap(ges)
    -- A tap is a finger lifted where it went down: it ends the touch that started it.
    self:drop(ges.pos, self.layout:pressedButton())
    local hit = self.layout:hit(ges.pos.x, ges.pos.y, self.session:flipped())
    if not hit then
        return false
    end
    if hit.square then
        self:run("square", tap_square, hit.square)
    elseif hit.opens then
        self:run(hit.button, show_row, hit.opens)
    elseif ACTIONS[hit.button] then
        self:run(hit.button, ACTIONS[hit.button])
    end
    return true
end

-- Drags. KOReader splits one drag into several gestures: "touch" as soon as the finger goes down;
-- "hold" when it rests before moving, then "hold_pan" and "hold_release"; else "pan" while it
-- moves, and "swipe" (or "multiswipe", if it turned) or "pan_release" when it is lifted, depending
-- on how quick it was. A finger lifted without moving makes a "tap" instead.
-- The window keeps every gesture of a drag that started on it, so that none reaches the reader.
-- The drag starts at the touch, and not at the first "pan", which only comes after the finger has
-- moved some millimetres: so the move button is marked as soon as the finger is on it.

-- Where the finger went down, as the name of the field of the gesture that has it, for the
-- gestures that can start a drag. A swipe reports its start as its position.
local START_FIELD = {
    touch = "pos", hold = "pos", pan = "start_pos", swipe = "pos", multiswipe = "pos",
}

-- Where the finger was lifted, for the gestures that end a drag.
local LIFT_FIELD = {
    swipe = "end_pos", multiswipe = "end_pos", pan_release = "pos", hold_release = "pos",
}

local function point_of(ges, fields)
    local field = fields[ges.ges]
    return field and ges[field]
end

-- True when the gesture is part of a drag that started on the window: one it starts, or one going
-- on.
function Window:ownsDrag(ges)
    local start = point_of(ges, START_FIELD)
    if start then
        return self.layout:startDrag(start.x, start.y, self.session:flipped())
    end
    return self.layout:isDragging()
end

-- True when the gesture belongs to a drag of the window. The button held down to drag it is
-- marked once, when the drag starts, and not repainted again until the finger is lifted.
function Window:onDrag(ges)
    local marked = self.layout:pressedButton()
    if not self:ownsDrag(ges) then
        return false
    end
    local lift = point_of(ges, LIFT_FIELD)
    local pressed = self.layout:pressedButton()
    if lift then
        self:drop(lift, marked)
    elseif pressed ~= marked then
        self:repaintButton(pressed or marked)
    end
    return true
end

-- Ends the drag with the finger lifted at pos, if there is one. A window that moved is repainted
-- whole, in the old place and the new one; one that did not only loses the mark of the button it
-- was held by.
function Window:drop(pos, marked)
    local before = self.layout:rects()
    if self.layout:endDrag(pos.x, pos.y) then
        self:refresh(self.layout:dirtyRect(before), true)
    elseif marked then
        self:repaintButton(marked)
    end
end

local function paint_icon(bb, name, rect)
    local icon = Theme.icon(name)
    local w, h = icon:getWidth(), icon:getHeight()
    bb:alphablitFrom(icon, rect.x + math.floor((rect.w - w) / 2),
        rect.y + math.floor((rect.h - h) / 2), 0, 0, w, h)
end

-- A rounded border inside a button, to show that it is held down.
local function paint_pressed(bb, rect)
    local p = Theme.PRESSED
    local inset = Theme.px(p.inset)
    bb:paintBorder(rect.x + inset, rect.y + inset, rect.w - 2 * inset, rect.h - 2 * inset,
        Theme.px(p.width), Theme.GRAY.frame, Theme.px(p.radius),
        G_reader_settings:nilOrTrue("anti_alias_ui"))
end

-- One button of the row, whole: its background, its icon, lighter if it is disabled, and, if it
-- is held down, its mark.
local function paint_button(bb, button, pressed)
    local rect = button.rect
    bb:paintRect(rect.x, rect.y, rect.w, rect.h, Theme.GRAY.row)
    paint_icon(bb, button.id, rect)
    if not button.enabled then
        bb:lightenRect(rect.x, rect.y, rect.w, rect.h, Theme.DISABLED)
    end
    if pressed then
        paint_pressed(bb, rect)
    end
end

-- Paints one button straight on the screen and shows it at once, without painting the page again:
-- the way KOReader's own buttons show a press (Button:_doFeedbackHighlight). A whole repaint would
-- make the mark wait for the page. The button lies on the window, so nothing of the page is in it.
function Window:repaintButton(id)
    local button = self.layout:button(id)
    paint_button(Screen.bb, button, self.layout:pressedButton() == id)
    UIManager:setDirty(nil, "fast", Geom:new(button.rect))
    UIManager:forceRePaint()
end

local function paint_frame(bb, rects)
    local gray = Theme.GRAY
    local w = rects.window
    bb:paintRect(w.x, w.y, w.w, w.h, gray.frame)
    local row = rects.buttons
    bb:paintRect(row.x, row.y, row.w, row.h, gray.row)
    local ranks, files = rects.ranks, rects.files
    if ranks then
        -- From the top of the ranks strip to the bottom of the files one, corner included.
        bb:paintRect(ranks.x, ranks.y, ranks.w + files.w, ranks.h + files.h, gray.gutter)
    end
end

-- Called by ReaderView after it paints the page.
function Window:paintTo(bb)
    if not self.layout:isOpen() then
        return
    end
    local rects = self.layout:rects()
    paint_frame(bb, rects)
    local pressed = self.layout:pressedButton()
    for _, button in ipairs(self.layout:buttons()) do
        paint_button(bb, button, button.id == pressed)
    end
    Board.paint(bb, self.layout, self.session:view())
end

return Window
