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

-- The face of a button in a cell of its row: the box, inside the gap that parts it from the next.
local function box_of(cell)
    return Kit.inset(cell, math.floor(Theme.px(Theme.BUTTON.gap) / 2))
end

-- Where the content of a button goes (its icon), inside the box and its padding.
function Kit.buttonFace(cell)
    return Kit.inset(box_of(cell), Theme.px(Theme.BUTTON.pad))
end

-- The side of a square icon that fits the face of a button: Theme.BUTTON.icon, or less in a
-- button narrowed to fit its row.
function Kit.iconSide(cell)
    local face = Kit.buttonFace(cell)
    return math.min(Theme.px(Theme.BUTTON.icon), face.w, face.h)
end

-- A button in the cell its row gives it: a box with rounded corners and a thin border, with its
-- content painted by paint_face(bb, face). look.down: held down or chosen, on a gray ground.
-- look.dim: a share to lighten it by, when it does nothing now or is a tool not chosen.
function Kit.button(bb, cell, look, paint_face)
    local style = Theme.BUTTON
    local box = box_of(cell)
    local radius = Theme.px(style.radius)
    Kit.fill(bb, cell, style.ground)
    bb:paintRoundedRect(box.x, box.y, box.w, box.h, look.down and style.down or style.face,
        radius)
    bb:paintBorder(box.x, box.y, box.w, box.h, Theme.px(style.border), style.edge, radius,
        G_reader_settings:nilOrTrue("anti_alias_ui"))
    paint_face(bb, Kit.buttonFace(cell))
    if look.dim then
        bb:lightenRect(cell.x, cell.y, cell.w, cell.h, look.dim)
    end
end

return Kit
