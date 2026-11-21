-- Paints the strip under the board with the moves of the line, as model/notation.lua writes them,
-- the one that led to the position shown in bold, with the chess characters of the font as
-- figurines (KOReader finds them in FreeSerif, one of its fallback fonts).
local Kit = require("ui/kit")
local Notation = require("model/notation")
local Theme = require("ui/theme")

local Strip = {}

-- White's pieces, whichever side moved.
local FIGURINE = { K = "\u{2654}", Q = "\u{2655}", R = "\u{2656}", B = "\u{2657}", N = "\u{2658}" }

-- A figurine as the text of its character; other parts as they are.
local function as_text(part)
    if part.kind == "figurine" then
        return { kind = "text", text = FIGURINE[part.piece], current = part.current }
    end
    return part
end

-- The widget of a text part, bold when it is of the current move. The caller frees it.
local function text_widget(part, sizes)
    return Theme.text(part.text, sizes.text, Theme.NOTATION.color, part.current)
end

-- The sizes of the parts on a strip of a height, in pixels.
local function sizes_of(height)
    local style = Theme.NOTATION
    return {
        text = math.floor(height * style.text_share),
        gap = Theme.px(style.gap),
        pad = Theme.px(style.pad),
    }
end

-- The width of each part, measuring each text once.
local function measurer(sizes)
    local widths = {}
    return function(part)
        part = as_text(part)
        if part.kind == "gap" then
            return sizes.gap
        end
        local key = (part.current and "b:" or "r:") .. part.text
        if not widths[key] then
            local text = text_widget(part, sizes)
            widths[key] = text:getSize().w
            text:free()
        end
        return widths[key]
    end
end

local function middle(rect, h)
    return rect.y + math.floor((rect.h - h) / 2)
end

-- How each kind of part is painted at x on the strip; a gap is only room.
local PAINT = {
    text = function(bb, part, x, rect, sizes)
        local text = text_widget(part, sizes)
        text:paintTo(bb, x, middle(rect, text:getSize().h))
        text:free()
    end,
    gap = function() end,
}

-- Paints the parts of one line on the strip, from its left; the parts that do not fit whole are
-- left out.
local function paint_line(bb, rect, parts, sizes, width_of)
    local x, right = rect.x + sizes.pad, rect.x + rect.w - sizes.pad
    for _, part in ipairs(parts) do
        local w = width_of(part)
        if x + w > right then
            return
        end
        local shown = as_text(part)
        PAINT[shown.kind](bb, shown, x, rect, sizes)
        x = x + w
    end
end

-- Paints the strip in rect with the moves of the session view (view.notation), in as many lines
-- of the height of the strip under the board as fit in it.
function Strip.paint(bb, rect, notation)
    Kit.fill(bb, rect, Theme.NOTATION.background)
    local line_h = math.min(rect.h, Theme.px(Theme.SIZES.notation))
    local sizes = sizes_of(line_h)
    local width_of = measurer(sizes)
    local lines = Notation.lines(notation.moves, notation.numbered, width_of,
        rect.w - 2 * sizes.pad, math.floor(rect.h / line_h), notation.current)
    for i, parts in ipairs(lines) do
        local line = { x = rect.x, y = rect.y + (i - 1) * line_h, w = rect.w, h = line_h }
        paint_line(bb, line, parts, sizes, width_of)
    end
end

return Strip
