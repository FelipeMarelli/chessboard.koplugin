-- Rectangles as plain tables { x, y, w, h } in whole pixels.
local Rect = {}

-- Whether two rects are the same; two nils are, a nil and a rect are not.
function Rect.same(a, b)
    if a == nil or b == nil then
        return a == b
    end
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

return Rect
