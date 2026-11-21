-- The pieces the window is drawn with: buttons, discs and rings, centred bitmaps and texts. Each
-- one paints in a rect it is given, with the style of ui/theme.lua, and decides nothing.
local Theme = require("ui/theme")

local Kit = {}

function Kit.fill(bb, rect, color)
    bb:paintRect(rect.x, rect.y, rect.w, rect.h, color)
end

-- A rect made smaller by by pixels on every side.
function Kit.inset(rect, by)
    return { x = rect.x + by, y = rect.y + by, w = rect.w - 2 * by, h = rect.h - 2 * by }
end

-- The top left corner of something w by h centred in rect.
function Kit.centred(rect, w, h)
    return rect.x + math.floor((rect.w - w) / 2), rect.y + math.floor((rect.h - h) / 2)
end

-- A bitmap with straight alpha (pieces, icons), centred in rect.
function Kit.bitmap(bb, image, rect)
    local w, h = image:getWidth(), image:getHeight()
    local x, y = Kit.centred(rect, w, h)
    bb:alphablitFrom(image, x, y, 0, 0, w, h)
end

-- A disc centred in rect, or a ring when a line width is given.
function Kit.disc(bb, rect, radius, color, width)
    bb:paintCircle(rect.x + math.floor(rect.w / 2), rect.y + math.floor(rect.h / 2), radius,
        color, width)
end

-- A text size_px high in the interface font, centred in rect.
function Kit.text(bb, rect, text, size_px, color, bold)
    local widget = Theme.text(text, size_px, color, bold)
    local size = widget:getSize()
    widget:paintTo(bb, Kit.centred(rect, size.w, size.h))
    widget:free()
end

-- The side of a square icon in a button: Theme.BUTTON.icon, or less in a button narrowed to fit
-- its row.
function Kit.iconSide(cell)
    return math.min(Theme.px(Theme.BUTTON.icon), cell.w - 2 * Theme.px(Theme.BUTTON.inset))
end

-- The frame of a button held down: rounded, inside it.
local function paint_down(bb, cell)
    local style = Theme.BUTTON
    local frame = Kit.inset(cell, Theme.px(style.inset))
    bb:paintBorder(frame.x, frame.y, frame.w, frame.h, Theme.px(style.stroke), style.ink,
        Theme.px(style.radius), G_reader_settings:nilOrTrue("anti_alias_ui"))
end

-- A button in the cell its row gives it: its content, painted by paint_face(bb, cell) on the
-- ground of the row. look.dim: a share to lighten it by, when it does nothing now or is a tool not
-- chosen. look.down: held down, framed.
function Kit.button(bb, cell, look, paint_face)
    Kit.fill(bb, cell, Theme.BUTTON.ground)
    paint_face(bb, cell)
    if look.dim then
        bb:lightenRect(cell.x, cell.y, cell.w, cell.h, look.dim)
    end
    if look.down then
        paint_down(bb, cell)
    end
end

return Kit
