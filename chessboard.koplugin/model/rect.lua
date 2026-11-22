-- Rectangles as plain tables { x, y, w, h } in whole pixels.
local Rect = {}

-- Whether two rects are the same; two nils are, a nil and a rect are not.
function Rect.same(a, b)
    if a == nil or b == nil then
        return a == b
    end
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

-- Whether the pixel at x, y is in rect.
function Rect.hasPoint(rect, x, y)
    return x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h
end

-- The smallest rect that covers both.
function Rect.union(a, b)
    local x, y = math.min(a.x, b.x), math.min(a.y, b.y)
    local right = math.max(a.x + a.w, b.x + b.w)
    local bottom = math.max(a.y + a.h, b.y + b.h)
    return { x = x, y = y, w = right - x, h = bottom - y }
end

-- The rect within rect, by pixels from each side.
function Rect.inset(rect, by)
    return { x = rect.x + by, y = rect.y + by, w = rect.w - 2 * by, h = rect.h - 2 * by }
end

-- The part of rect from the height top down to bottom (both from the top of the screen).
function Rect.band(rect, top, bottom)
    return { x = rect.x, y = top, w = rect.w, h = bottom - top }
end

-- The top left corner of something w by h centred in rect.
function Rect.centred(rect, w, h)
    return rect.x + math.floor((rect.w - w) / 2), rect.y + math.floor((rect.h - h) / 2)
end

-- The same place in something longer or shorter: offset from its start, out of length, is moved to
-- as far through new_length, rounded. Nothing to keep in something empty: its start.
function Rect.samePlace(offset, length, new_length)
    if length <= 0 then
        return 0
    end
    return math.floor(offset * new_length / length + 0.5)
end

return Rect
