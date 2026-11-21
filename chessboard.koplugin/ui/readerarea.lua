-- Gives the book a part of the screen while it is split, and the whole screen back after.
--
-- The reader is fitted to its part the way KOReader fits it to a screen that turned or changed
-- size (see spikes/split-screen.md): crengine's page (EPUB and the other reflowed formats) is set
-- to the part with the steps ReaderRolling:onSetDimensions takes, which itself would set it back
-- to the whole screen; the view of a paged document (PDF, DjVu, comics) is shrunk and its zoom
-- fitted again, and its scroll states made again for the new height.
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

-- Fits the book to rect, or to the whole screen when rect is nil; nothing is done when it is
-- already fitted to it, unless forced (the screen turned, and KOReader fitted it to the whole
-- screen). True when it changed: the whole screen has to be painted again.
function ReaderArea:fit(rect, force)
    if same(rect, self.rect) and not (force and rect) then
        return false
    end
    self.rect = rect and { x = rect.x, y = rect.y, w = rect.w, h = rect.h } or nil
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
