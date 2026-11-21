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

local RECT = { x = 10, y = 20, w = 30, h = 40 }

test("a rect has the pixels from its corner up to its width and height, not beyond", function()
    eq(Rect.hasPoint(RECT, 10, 20), true)
    eq(Rect.hasPoint(RECT, 39, 59), true)
    eq(Rect.hasPoint(RECT, 40, 30), false)
    eq(Rect.hasPoint(RECT, 20, 60), false)
    eq(Rect.hasPoint(RECT, 9, 30), false)
end)

test("the union of two rects covers both", function()
    eq(Rect.union(RECT, { x = 0, y = 50, w = 5, h = 30 }), { x = 0, y = 20, w = 40, h = 60 })
    eq(Rect.union(RECT, RECT), RECT)
end)

test("an inset rect is smaller by as much on every side", function()
    eq(Rect.inset(RECT, 2), { x = 12, y = 22, w = 26, h = 36 })
end)

test("a band of a rect keeps its width between two heights", function()
    eq(Rect.band(RECT, 30, 45), { x = 10, y = 30, w = 30, h = 15 })
end)

test("something centred in a rect leaves as much room on each side, rounding down", function()
    eq({ Rect.centred(RECT, 10, 10) }, { 20, 35 })
    eq({ Rect.centred(RECT, 11, 11) }, { 19, 34 })
end)
