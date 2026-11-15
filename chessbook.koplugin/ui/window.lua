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
function Window:refresh(rect)
    UIManager:setDirty(self.view.dialog, "ui", Geom:new(rect))
end

function Window:setOpen(open)
    self.layout:setOpen(open)
    self:refresh(self.layout:dirtyRect())
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
    local bar, row = rects.titlebar, rects.buttons
    bb:paintRect(bar.x, bar.y, bar.w, bar.h, gray.bar)
    bb:paintRect(row.x, row.y, row.w, row.h, gray.row)
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
