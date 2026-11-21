-- The floating window: paints it over the page and turns taps on it into calls to the model.
--
-- It is a view module of the reader, not a widget shown by UIManager, so that taps outside it
-- still reach the reader.
local Board = require("ui/board")
local Device = require("device")
local Geom = require("ui/geometry")
local Kit = require("ui/kit")
local Strip = require("ui/notation")
local Theme = require("ui/theme")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local Screen = Device.screen

local Window = {}
Window.__index = Window

-- view: the ReaderView; layout and session: the models it shows; area: the ReaderArea that gives
-- the book its part of the screen while split.
function Window.new(view, layout, session, area)
    return setmetatable({ view = view, layout = layout, session = session, area = area }, Window)
end

-- Gives the book the part of the screen the layout leaves it: all of it, unless split and open.
-- The screen is painted again whole when that changed. forced: the screen turned, and KOReader
-- gave the book the whole of it.
function Window:fitReader(forced)
    self.area:fit(self.layout:readerRect(), forced)
end

-- Asks for one repaint of a region of the screen; the page under it is painted again first.
--
-- A plain "ui" refresh does not flash, but on e-ink it leaves a ghost of the text the window
-- covers, most visible on the gray squares. When the window covers new text (opening, growing) it
-- uses "flashui": the region flashes once and the ghost goes. Uncovering text is clean without it.
function Window:refresh(rect, covers_text)
    UIManager:setDirty(self.view.dialog, covers_text and "flashui" or "ui", Geom:new(rect))
end

-- KOReader's double tap holds every tap back for a while, and makes one gesture of two quick taps
-- close together: squares tapped in a row would be slow and some lost. It is a setting of the
-- whole reader, read by UIManager from the ReaderUI each time a dialog closes, so it is turned off
-- there while the window is open, and given back as it was when it closes.
function Window:holdDoubleTap(open)
    local ui = self.view.ui
    if open then
        self.reader_double_tap_off = ui.disable_double_tap
        ui.disable_double_tap = true
    else
        ui.disable_double_tap = self.reader_double_tap_off
    end
    Device.input.disable_double_tap = ui.disable_double_tap
end

-- Opening or closing ends an edit of the start position, as the main row shows again, and drops
-- a promotion waiting for its piece.
function Window:setOpen(open)
    self.session:finishEdit()
    self.session:cancelPromotion()
    if open ~= self.layout:isOpen() then
        self:holdDoubleTap(open)
    end
    self.layout:setOpen(open)
    self:refresh(self.layout:dirtyRect(), open)
    self:fitReader()
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

-- Splits the screen between the book and the board, or takes the window back over the page.
local function split(self, on)
    self.session:finishEdit()
    local before = self.layout:rects()
    if self.layout:setSplit(on) then
        self:refresh(self.layout:dirtyRect(before), true)
    end
end

-- Repaints the window when a tap changed what it shows.
local function repaint_if(self, changed)
    if changed then
        self:refresh(self.layout:dirtyRect())
    end
end

-- The piece each button of the edit row puts.
local PIECE_BUTTONS = {
    king = "k", queen = "q", rook = "r", bishop = "b", knight = "n", pawn = "p",
}

local ACTIONS = {
    close = function(self) self:setOpen(false) end,
    flip = function(self)
        self.session:flip()
        self:refresh(self.layout:dirtyRect())
    end,
    reset = function(self) repaint_if(self, self.session:reset()) end,
    backward = function(self) repaint_if(self, self.session:navigate("back")) end,
    forward = function(self) repaint_if(self, self.session:navigate("forward")) end,
    smaller = function(self) resize(self, -1) end,
    bigger = function(self) resize(self, 1) end,
    split = function(self) split(self, true) end,
    float = function(self) split(self, false) end,
    swap = function(self) repaint_if(self, self.layout:swapSplit()) end,
    clear = function(self) repaint_if(self, self.session:clearBoard()) end,
    color = function(self) repaint_if(self, self.session:toggleColor()) end,
    erase = function(self) repaint_if(self, self.session:chooseEraser()) end,
}
for id, letter in pairs(PIECE_BUTTONS) do
    ACTIONS[id] = function(self) repaint_if(self, self.session:choosePiece(letter)) end
end

-- What holding a button down does, for the buttons that do something else when held: the arrows
-- go to the start or the end of the line.
local HOLD_ACTIONS = {
    backward = function(self) repaint_if(self, self.session:navigate("start")) end,
    forward = function(self) repaint_if(self, self.session:navigate("end")) end,
}

-- What showing a row does to the session: the edit row starts editing the start position, and
-- the main one ends it. Each says whether the board changed.
local ROW_ENTERED = {
    edit = function(session) return session:startEdit() end,
    main = function(session) return session:finishEdit() end,
}

-- Shows another row of buttons in place of the one shown; only the row is repainted, unless the
-- board or the size of the window changed too. Grown, the window flashes over the page.
local function show_row(self, name)
    local before = self.layout:rects()
    local resized, grew = self.layout:showRow(name)
    local entered = ROW_ENTERED[name]
    local board_changed = entered and entered(self.session)
    local whole = board_changed or resized
    self:refresh(whole and self.layout:dirtyRect(before) or self.layout:rects().buttons, grew)
end

local function tap_square(self, sq)
    repaint_if(self, self.session:tapSquare(sq).changed)
end

-- A tap off the squares while a promotion waits for its piece cancels it, and does nothing else.
local function cancel_promotion(self)
    repaint_if(self, self.session:cancelPromotion())
end

-- Runs what a tap does, and gives the book the part of the screen left to it after; a failure
-- closes the window, so that the reader can go on.
function Window:run(name, action, ...)
    local ok, err = pcall(action, self, ...)
    if ok then
        self:fitReader()
    else
        logger.err("chessboard:", name, "failed:", err)
        self:setOpen(false)
    end
end

-- Runs what pressing a button does, from actions; while a promotion waits for its piece, any
-- button only cancels it.
function Window:pressButton(hit, actions)
    if self.session:isPromoting() then
        self:run("promotion", cancel_promotion)
    elseif actions[hit.button] then
        self:run(hit.button, actions[hit.button])
    end
end

-- True when the tap was on the window, so that the reader does not get it.
function Window:onTap(ges)
    -- A tap is a finger lifted where it went down: it ends the touch that started it.
    self:drop(ges.pos, self.layout:pressedButton())
    local hit = self.layout:hit(ges.pos.x, ges.pos.y, self.session:flipped())
    if not hit then
        self.area:toReader(ges)
        return false
    end
    if hit.square then
        self:run("square", tap_square, hit.square)
    elseif hit.opens and not self.session:isPromoting() then
        self:run(hit.button, show_row, hit.opens)
    else
        self:pressButton(hit, ACTIONS)
    end
    return true
end

-- A finger resting on the window: on a button with a hold action, it does it at once, without
-- waiting for the finger to be lifted.
function Window:hold(pos)
    local hit = self.layout:hit(pos.x, pos.y, self.session:flipped())
    if hit and HOLD_ACTIONS[hit.button] then
        self:pressButton(hit, HOLD_ACTIONS)
    end
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
-- on. While a promotion waits for its piece the window does not move.
function Window:ownsDrag(ges)
    local start = point_of(ges, START_FIELD)
    if start then
        return self.layout:startDrag(start.x, start.y, self.session:flipped(),
            self.session:isPromoting())
    end
    return self.layout:isDragging()
end

-- True when the gesture belongs to a drag of the window. The button held down to drag it is
-- marked once, when the drag starts, and not repainted again until the finger is lifted. A drag
-- that starts on the eye takes the window off the page until the finger is lifted.
function Window:onDrag(ges)
    local marked = self.layout:pressedButton()
    local hidden = self.layout:isHidden()
    local dividing = self.layout:isDividing()
    if not self:ownsDrag(ges) then
        self.area:toReader(ges)
        return false
    end
    if self.layout:isDividing() and not dividing then
        self:repaintDivider()
    end
    if self.layout:isHidden() and not hidden then
        self:refresh(self.layout:dirtyRect())
    end
    if ges.ges == "hold" then
        self:hold(ges.pos)
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
-- whole, in the old place and the new one, and so is one that was hidden; one that did not move
-- only loses the mark of the button it was held by.
function Window:drop(pos, marked)
    local before = self.layout:rects()
    local hidden = self.layout:isHidden()
    local dividing = self.layout:isDividing()
    if self.layout:endDrag(pos.x, pos.y) or hidden then
        self:refresh(self.layout:dirtyRect(before), true)
        self:fitReader()
    elseif marked then
        self:repaintButton(marked)
    elseif dividing then
        self:repaintDivider()
    end
end

-- The color button: a white disc with a ring when White's pieces are put, a black disc when
-- Black's are, like the turn in the corner of the board.
local function paint_color(bb, face, side, color, ink)
    local radius = math.floor(side * 0.4)
    if color == "w" then
        Kit.disc(bb, face, radius, Theme.BUTTON.face)
        Kit.disc(bb, face, radius, ink, Theme.px(Theme.BUTTON.stroke))
    else
        Kit.disc(bb, face, radius, ink)
    end
end

-- The file of the icon of a button: the one that swaps the book and the board points the way the
-- screen is split.
local function icon_name(id, axis)
    return (id == "swap" and axis == "x") and "swap-x" or id
end

-- The icon of a button, in ink; in the edit row, the pieces show in the color they are put in.
-- axis: the one the screen is split along.
local function paint_icon(bb, id, face, side, edit, ink, axis)
    local letter = PIECE_BUTTONS[id]
    if id == "color" then
        paint_color(bb, face, side, edit.color, ink)
    elseif letter then
        local piece = edit.color == "w" and letter:upper() or letter
        Kit.bitmap(bb, Theme.pieceIcon(piece, side), face)
    else
        Kit.mask(bb, Theme.iconMask(icon_name(id, axis), side), face, ink)
    end
end

-- The tool of the editor a button chooses, as the session view names it: a piece letter or
-- "erase"; nil for the other buttons.
local function tool_of(id)
    return PIECE_BUTTONS[id] or (id == "erase" and id or nil)
end

-- True when the button is a tool of the editor and another one is chosen: it is drawn lighter, so
-- that the chosen one stands out.
local function is_unchosen(button, edit)
    local chosen = edit and edit.piece
    local tool = tool_of(button.id)
    return chosen ~= nil and tool ~= nil and tool ~= chosen
end

-- Disabled by the layout (a size at its limit) or by the session (an arrow at the end of the line).
local function is_disabled(button, view)
    return not button.enabled or view.buttons[button.id] == false
end

-- How much lighter a button is drawn: when disabled, or when it is a tool not chosen; nil if not.
local function lightening(button, view)
    if is_disabled(button, view) then
        return Theme.BUTTON.disabled
    elseif is_unchosen(button, view.edit) then
        return Theme.BUTTON.unchosen
    end
end

-- How a button looks: its card darker while it is held, lighter as lightening says, and bare, with
-- no card, for the upper ones (the color and the pieces of the editor).
local function look_of(button, pressed, view)
    return { down = button.id == pressed, dim = lightening(button, view), bare = button.upper }
end

-- One button of the row, whole. view is the session view.
local function paint_button(bb, button, pressed, view, axis)
    local side = Kit.iconSide(button.rect, button.upper)
    Kit.button(bb, button.rect, look_of(button, pressed, view), function(target, face, ink)
        paint_icon(target, button.id, face, side, view.edit, ink, axis)
    end)
end

-- The inside of the window, within its thin frame.
local function inside_frame(rects)
    return Kit.inset(rects.window, Theme.px(Theme.SIZES.border))
end

-- The divider of the split screen: the ground of the window with a short grip in the middle, laid
-- along it; gray while held. The thin frame of the window is left as the line next to the book.
local function paint_divider(bb, rects, held)
    local style = Theme.DIVIDER
    local rect = Geom:new(rects.divider):intersect(Geom:new(inside_frame(rects)))
    Kit.fill(bb, rect, held and style.held or Theme.GRAY.row)
    local long, thick = Theme.px(style.grip_length), Theme.px(style.grip_width)
    local w, h = long, thick
    if rect.h > rect.w then
        w, h = thick, long
    end
    local x, y = Kit.centred(rect, w, h)
    Kit.fill(bb, { x = x, y = y, w = w, h = h }, style.grip)
end

-- Shows a part of the window just painted straight on the screen at once, without painting the
-- page again: the way KOReader's own buttons show a press (Button:_doFeedbackHighlight). A whole
-- repaint would make the mark wait for the page. The part lies on the window, so nothing of the
-- page is in it.
local function show_now(rect)
    UIManager:setDirty(nil, "fast", Geom:new(rect))
    UIManager:forceRePaint()
end

-- Paints one button straight on the screen and shows it at once.
function Window:repaintButton(id)
    local button = self.layout:button(id)
    paint_button(Screen.bb, button, self.layout:pressedButton(), self.session:view(),
        self.layout:splitAxis())
    show_now(button.rect)
end

-- The divider, marked while held, the same way.
function Window:repaintDivider()
    local rects = self.layout:rects()
    paint_divider(Screen.bb, rects, self.layout:isDividing())
    show_now(rects.divider)
end

local function paint_frame(bb, rects)
    local gray = Theme.GRAY
    Kit.fill(bb, rects.window, gray.frame)
    -- The whole inside, so the gap between the board and the buttons too, when there is one.
    Kit.fill(bb, inside_frame(rects), gray.row)
    if rects.board_frame then
        Kit.fill(bb, rects.board_frame, gray.gutter)
    end
end

-- Called by ReaderView after it paints the page.
function Window:paintTo(bb)
    if not self.layout:isOpen() or self.layout:isHidden() then
        return
    end
    local rects = self.layout:rects()
    paint_frame(bb, rects)
    if rects.divider then
        paint_divider(bb, rects, self.layout:isDividing())
    end
    local view = self.session:view()
    local strip = rects.notation
    if strip and view.edit then
        -- While editing, the strip holds the upper buttons of the edit row.
        Kit.fill(bb, strip, Theme.GRAY.row)
    elseif strip then
        Strip.paint(bb, strip, view.notation)
    end
    local pressed = self.layout:pressedButton()
    local axis = self.layout:splitAxis()
    for _, button in ipairs(self.layout:buttons()) do
        paint_button(bb, button, pressed, view, axis)
    end
    Board.paint(bb, self.layout, view)
end

return Window
