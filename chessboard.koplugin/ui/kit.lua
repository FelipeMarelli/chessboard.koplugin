-- The pieces the window is drawn with: buttons, discs and rings, centred bitmaps and texts. Each
-- one paints in a rect it is given, with the style of ui/theme.lua, and decides nothing.
local Blitbuffer = require("ffi/blitbuffer")
local Theme = require("ui/theme")

local Kit = {}

function Kit.fill(bb, rect, color)
    bb:paintRect(rect.x, rect.y, rect.w, rect.h, color)
end

-- A rect made smaller by by pixels on every side.
-- A frame of the given width inside rect.
function Kit.frame(bb, rect, width, color)
    Kit.fill(bb, { x = rect.x, y = rect.y, w = rect.w, h = width }, color)
    Kit.fill(bb, { x = rect.x, y = rect.y + rect.h - width, w = rect.w, h = width }, color)
    Kit.fill(bb, { x = rect.x, y = rect.y, w = width, h = rect.h }, color)
    Kit.fill(bb, { x = rect.x + rect.w - width, y = rect.y, w = width, h = rect.h }, color)
end

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

-- Fades what is painted in a square towards a gray, by a share from 0 to 1. lightenRect fades
-- towards white only, which would light up a gray ground around an icon.
function Kit.fade(bb, x, y, side, gray, by)
    local value = gray:getColor8().a
    bb:paintRect(x, y, side, side, Blitbuffer.Color8A(value, math.floor(0xFF * by)),
        bb.setPixelBlend)
end

-- A square filled with rounded corners. paintRoundedRect leaves them jagged: a thin
-- anti-aliased border of the same gray goes over its edge.
function Kit.roundedSquare(bb, x, y, side, radius, color)
    bb:paintRoundedRect(x, y, side, side, color, radius)
    bb:paintBorder(x, y, side, side, Theme.px(Theme.BUTTON.stroke), color, radius, true)
end

-- The card of a button: a square as big as fits in its cell leaving Theme.BUTTON.gap around it.
local function card_of(cell)
    local side = math.min(cell.w, cell.h) - 2 * Theme.px(Theme.BUTTON.gap)
    local x, y = Kit.centred(cell, side, side)
    return { x = x, y = y, w = side, h = side }
end

-- The side of the icon of a button: its share of the card, or, bare, as high as the button.
function Kit.iconSide(cell, bare)
    if bare then
        return math.min(cell.h, cell.w - 2 * Theme.px(Theme.BUTTON.gap))
    end
    return math.floor(card_of(cell).w * Theme.BUTTON.icon + 0.5)
end

-- A button in the cell its row gives it: a card on the ground of the row, with its content painted
-- by paint_face(bb, cell, ink), ink the gray of its icon. look.down: held down, the card darker.
-- look.dim: a share to lighten the icon by, when it does nothing now or is a tool not chosen.
-- look.bare: no card, the icon as big as the button.
function Kit.button(bb, cell, look, paint_face)
    local style = Theme.BUTTON
    -- What is under the icon: the ground of the row for a bare button, else the card.
    local under = look.bare and style.ground or (look.down and style.down or style.face)
    Kit.fill(bb, cell, style.ground)
    if not look.bare then
        local card = card_of(cell)
        Kit.roundedSquare(bb, card.x, card.y, card.w, math.floor(card.w * style.round + 0.5),
            under)
    end
    paint_face(bb, cell, look.down and style.down_ink or style.ink)
    if look.dim then
        local side = Kit.iconSide(cell, look.bare)
        local x, y = Kit.centred(cell, side, side)
        Kit.fade(bb, x, y, side, under, look.dim)
    end
end

return Kit
