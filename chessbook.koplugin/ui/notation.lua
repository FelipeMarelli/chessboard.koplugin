-- Paints the strip under the board with the last moves, as model/notation.lua writes them, with
-- the Merida pieces as figurines.
local Notation = require("model/notation")
local Theme = require("ui/theme")

local Strip = {}

-- The sizes of the parts on a strip of a height, in pixels.
local function sizes_of(height)
    local style = Theme.NOTATION
    return {
        text = math.floor(height * style.text_share),
        figurine = math.floor(height * style.figurine_share),
        gap = Theme.px(style.gap),
        pad = Theme.px(style.pad),
    }
end

-- The width of each part, measuring each text once.
local function measurer(sizes)
    local widths = {}
    return function(part)
        if part.kind == "gap" then
            return sizes.gap
        elseif part.kind == "figurine" then
            return sizes.figurine
        end
        if not widths[part.text] then
            local text = Theme.text(part.text, sizes.text, Theme.NOTATION.color)
            widths[part.text] = text:getSize().w
            text:free()
        end
        return widths[part.text]
    end
end

local function middle(rect, h)
    return rect.y + math.floor((rect.h - h) / 2)
end

-- How each kind of part is painted at x on the strip; a gap is only room.
local PAINT = {
    text = function(bb, part, x, rect, sizes)
        local text = Theme.text(part.text, sizes.text, Theme.NOTATION.color)
        text:paintTo(bb, x, middle(rect, text:getSize().h))
        text:free()
    end,
    figurine = function(bb, part, x, rect, sizes)
        local image = Theme.pieceIcon(part.piece, sizes.figurine)
        local w, h = image:getWidth(), image:getHeight()
        bb:alphablitFrom(image, x, middle(rect, h), 0, 0, w, h)
    end,
    gap = function() end,
}

-- Paints the strip in rect with the moves of the session view (view.notation). The parts that do
-- not fit whole are left out.
function Strip.paint(bb, rect, notation)
    local style = Theme.NOTATION
    bb:paintRect(rect.x, rect.y, rect.w, rect.h, style.background)
    local sizes = sizes_of(rect.h)
    local width_of = measurer(sizes)
    local x, right = rect.x + sizes.pad, rect.x + rect.w - sizes.pad
    local parts = Notation.fit(notation.moves, notation.numbered, width_of, right - x)
    for _, part in ipairs(parts) do
        local w = width_of(part)
        if x + w > right then
            return
        end
        PAINT[part.kind](bb, part, x, rect, sizes)
        x = x + w
    end
end

return Strip
