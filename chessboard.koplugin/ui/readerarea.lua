-- Gives the book a part of the screen while it is split, and the whole screen back after.
--
-- The reader is fitted to its part the way KOReader fits it to a screen that turned or changed
-- size (see spikes/split-screen.md): crengine's page (EPUB and the other reflowed formats) is set
-- to the part with the steps ReaderRolling:onSetDimensions takes, which itself would set it back
-- to the whole screen; the view of a paged document (PDF, DjVu, comics) is shrunk and its zoom
-- fitted again, and its scroll states made again for the new height.
--
-- KOReader lays the book out from the top left corner of the screen. When its part is elsewhere
-- (below the board, or on its right), the book is painted shifted to its part, and the gestures on
-- it are shifted back before the reader gets them. Refreshes the reader asks for a region of are
-- not shifted.
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")

local Screen = Device.screen

local ReaderArea = {}
ReaderArea.__index = ReaderArea

-- ui: the ReaderUI.
function ReaderArea.new(ui)
    return setmetatable({ ui = ui, rect = nil }, ReaderArea)
end

local function same(a, b)
    if a == nil or b == nil then
        return a == b
    end
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

local function fit_rolling(ui, dimen)
    local document = ui.document
    -- crengine keeps the reading position across the new layout with its own history.
    document:enableInternalHistory(true)
    document:setViewDimen(dimen)
    ui.view:onSetDimensions(dimen)
    ui.rolling:onUpdatePos()
    document:enableInternalHistory(false)
    ui.rolling:onRedrawCurrentView()
end

local function fit_paging(ui, dimen)
    ui.view:onSetDimensions(dimen)
    ui.zooming:onSetDimensions(dimen)
    ui:handleEvent(Event:new("InitScrollPageStates"))
end

-- The status bar lays itself out for the whole screen whenever it is laid out again, so its
-- layout is wrapped: after KOReader's own, it is narrowed to the book's part and put at its foot.
function ReaderArea:fitFooter()
    local footer = self.ui.view.footer
    if not self.footer_layout then
        self.footer_layout = footer.resetLayout
        local area = self
        footer.resetLayout = function(f, force_reset)
            area.footer_layout(f, force_reset)
            area:narrowFooter(f)
        end
    end
    footer:resetLayout(true)
    footer:onUpdateFooter()
end

-- The sizes of the status bar KOReader takes from the screen, set to the book's part: the width
-- its text and progress bar are laid out for, and the box it sits at the foot of.
function ReaderArea:narrowFooter(footer)
    local rect = self.rect
    if not rect then
        return
    end
    footer._saved_screen_width, footer._saved_screen_height = rect.w, rect.h
    footer.footer_positioner.dimen.w, footer.footer_positioner.dimen.h = rect.w, rect.h
    footer.footer_container.dimen.w = rect.w
    footer.dimen = footer.footer_positioner:getSize()
end

-- Where the top left corner of the book's part is: 0, 0 for the whole screen.
function ReaderArea:shift()
    local rect = self.rect
    if not rect then
        return 0, 0
    end
    return rect.x, rect.y
end

-- The view is painted at the corner of the book's part. Painting can go on into a second paint of
-- the view (ReaderRolling repositions and paints again), which is already shifted.
function ReaderArea:shiftPaint()
    if self.view_paint then
        return
    end
    local view, area = self.ui.view, self
    self.view_paint = view.paintTo
    view.paintTo = function(v, bb, x, y)
        if area.painting then
            return area.view_paint(v, bb, x, y)
        end
        local dx, dy = area:shift()
        area.painting = true
        local ok, err = pcall(area.view_paint, v, bb, x + dx, y + dy)
        area.painting = false
        if not ok then
            error(err, 0)
        end
    end
end

-- The points of a gesture that KOReader's gesture detector gives.
local GESTURE_POINTS = { "pos", "start_pos", "end_pos" }

-- Shifts a gesture on the book from the screen to the book's own layout, from its top left corner.
function ReaderArea:toReader(ges)
    local dx, dy = self:shift()
    if dx == 0 and dy == 0 then
        return
    end
    for _, field in ipairs(GESTURE_POINTS) do
        local p = ges[field]
        if p then
            ges[field] = Geom:new{ x = p.x - dx, y = p.y - dy, w = p.w, h = p.h }
        end
    end
end

-- Fits the book to rect, or to the whole screen when rect is nil; nothing is done when it is
-- already fitted to it, unless forced (the screen turned, and KOReader fitted it to the whole
-- screen). True when it changed: the whole screen has to be painted again.
function ReaderArea:fit(rect, force)
    if same(rect, self.rect) and not (force and rect) then
        return false
    end
    self.rect = rect and { x = rect.x, y = rect.y, w = rect.w, h = rect.h } or nil
    self:shiftPaint()
    local dimen = rect and Geom:new{ x = 0, y = 0, w = rect.w, h = rect.h } or Screen:getSize()
    if self.ui.rolling then
        fit_rolling(self.ui, dimen)
    else
        fit_paging(self.ui, dimen)
    end
    self:fitFooter()
    UIManager:setDirty(self.ui.dialog, "full")
    return true
end

return ReaderArea
