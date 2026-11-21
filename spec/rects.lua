-- Checks on plain rects { x, y, w, h } shared by the specs of the window geometry, and the
-- buttons a layout shows.
local Rects = {}

-- The ids of the buttons of the row shown, in order.
function Rects.buttonIds(layout)
    local ids = {}
    for _, button in ipairs(layout:buttons()) do
        ids[#ids + 1] = button.id
    end
    return ids
end

-- The point at the middle of a rect, as two numbers.
function Rects.center(rect)
    return rect.x + math.floor(rect.w / 2), rect.y + math.floor(rect.h / 2)
end

function Rects.contains(outer, inner)
    return inner.x >= outer.x and inner.y >= outer.y and inner.x + inner.w <= outer.x + outer.w
        and inner.y + inner.h <= outer.y + outer.h
end

function Rects.overlap(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

return Rects
