-- model/rect.lua: rectangles as plain tables.
local Helper = require("helper")
local Rect = require("model/rect")
local eq, test = Helper.eq, Helper.test

test("two rects are the same when every field is", function()
    local a = { x = 1, y = 2, w = 3, h = 4 }
    eq(Rect.same(a, { x = 1, y = 2, w = 3, h = 4 }), true)
    eq(Rect.same(a, { x = 1, y = 2, w = 3, h = 5 }), false)
    eq(Rect.same(nil, nil), true)
    eq(Rect.same(a, nil), false)
    eq(Rect.same(nil, a), false)
end)
