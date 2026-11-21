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

-- An icon mask (Theme.iconMask) centred in rect, painted in a gray.
function Kit.mask(bb, mask, rect, color)
    local w, h = mask:getWidth(), mask:getHeight()
    local x, y = Kit.centred(rect, w, h)
    bb:colorblitFrom(mask, x, y, 0, 0, w, h, color)
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

-- A square filled with rounded corners. paintRoundedRect leaves them jagged: a thin
-- anti-aliased border of the same gray goes over its edge.
function Kit.roundedSquare(bb, x, y, side, radius, color)
    bb:paintRoundedRect(x, y, side, side, color, radius)
    bb:paintBorder(x, y, side, side, Theme.px(Theme.BUTTON.stroke), color, radius, true)
end

-- The side of the square of a button as wide as w: Theme.BUTTON.square, or less in a narrow one.
-- The smallest window (Theme.SIZES.min_square) leaves room in it for an icon and its pad.
local function square_side(w)
    return math.min(Theme.px(Theme.BUTTON.square), w - 2 * Theme.px(Theme.BUTTON.gap))
end

-- The side of the icon of a button: Theme.BUTTON.icon, or less to keep its pad in the square. It
-- goes by the width alone, so the pieces of the editor keep their size in the low row above.
function Kit.iconSide(cell)
    local style = Theme.BUTTON
    return math.min(Theme.px(style.icon), square_side(cell.w) - 2 * Theme.px(style.pad))
end

-- The ground of a button held down: its square, gray with rounded corners.
local function paint_down(bb, cell)
    local style = Theme.BUTTON
    local side = math.min(square_side(cell.w), cell.h - 2 * Theme.px(style.gap))
    local x, y = Kit.centred(cell, side, side)
    Kit.roundedSquare(bb, x, y, side, math.floor(side * style.round + 0.5), style.down)
end

-- A button in the cell its row gives it: its content, painted by paint_face(bb, cell, ink) on the
-- ground of the row, ink the gray of its icon. look.down: held down, on a gray square. look.dim: a
-- share to lighten it by, when it does nothing now or is a tool not chosen.
function Kit.button(bb, cell, look, paint_face)
    local style = Theme.BUTTON
    Kit.fill(bb, cell, style.ground)
    if look.down then
        paint_down(bb, cell)
    end
    paint_face(bb, cell, look.down and style.down_ink or style.ink)
    if look.dim then
        bb:lightenRect(cell.x, cell.y, cell.w, cell.h, look.dim)
    end
end

return Kit
