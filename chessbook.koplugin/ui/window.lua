-- The floating window: paints it over the page and turns taps on it into calls to the model.
--
-- It is a view module of the reader, not a widget shown by UIManager, so that taps outside it
-- still reach the reader.
local Board = require("ui/board")
local Geom = require("ui/geometry")
local Theme = require("ui/theme")
local UIManager = require("ui/uimanager")
local logger = require("logger")

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

local ACTIONS = {
    close = function(self) self:setOpen(false) end,
    flip = function(self)
        self.session:flip()
        self:refresh(self.layout:dirtyRect())
    end,
    size = function(self)
        local before = self.layout:rects()
        self.layout:toggleSmall()
        self:refresh(self.layout:dirtyRect(before), not self.layout:isSmall())
    end,
}

-- True when the tap was on the window, so that the reader does not get it.
function Window:onTap(ges)
    local hit = self.layout:hit(ges.pos.x, ges.pos.y, self.session:flipped())
    if not hit then
        return false
    end
    local action = hit.button and ACTIONS[hit.button]
    if action then
        local ok, err = pcall(action, self)
        if not ok then
            logger.err("chessbook: button", hit.button, "failed:", err)
            self:setOpen(false)
        end
    end
    return true
end

-- Drags. KOReader splits one drag into several gestures: "hold" when the finger rests before
-- moving, then "hold_pan" and "hold_release"; else "pan" while it moves, and "swipe" (or
-- "multiswipe", if it turned) or "pan_release" when it is lifted, depending on how quick it was.
-- The window keeps every gesture of a drag that started on it, so that none reaches the reader.

-- Where the finger went down, as the name of the field of the gesture that has it, for the
-- gestures that can start a drag. A swipe reports its start as its position.
local START_FIELD = { hold = "pos", pan = "start_pos", swipe = "pos", multiswipe = "pos" }

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

-- True when the gesture belongs to a drag of the window.
function Window:onDrag(ges)
    if not self:ownsDrag(ges) then
        return false
    end
    local lift = point_of(ges, LIFT_FIELD)
    if lift then
        self:drop(lift)
    end
    return true
end

function Window:drop(pos)
    local before = self.layout:rects()
    if self.layout:endDrag(pos.x, pos.y) then
        self:refresh(self.layout:dirtyRect(before), true)
    end
end

local function paint_icon(bb, name, rect)
    local icon = Theme.icon(name)
    local w, h = icon:getWidth(), icon:getHeight()
    bb:alphablitFrom(icon, rect.x + math.floor((rect.w - w) / 2),
        rect.y + math.floor((rect.h - h) / 2), 0, 0, w, h)
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
    for _, button in ipairs(self.layout:buttons()) do
        paint_icon(bb, button.id, button.rect)
    end
    Board.paint(bb, self.layout, self.session:view())
end

return Window
