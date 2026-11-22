-- The choices kept across books (model/preferences.lua, Layout:preferences): split or floating,
-- the size of the window, and dark or light.
local Game = require("chess/game")
local Helper = require("helper")
local Layout = require("model/layout")
local Preferences = require("model/preferences")
local Session = require("model/session")
local eq, test = Helper.eq, Helper.test

local SIZES = { row = 39, button = 39, border = 2, margin = 11, min_square = 29, size_step = 6,
    gutter = 14, notation = 26, spacing = 8, divider = 24, split_controls = 80, split_button = 80 }
local PORTRAIT, BIG = { 632, 840 }, { 1072, 1448 }

local function new_layout(size)
    return Layout.new{ screen_w = size[1], screen_h = size[2],
        scale = Layout.scaleFor(size[1], size[2]), sizes = SIZES }
end

local function new_session()
    return Session.new(assert(Game.new()))
end

-- A layout and a session with every choice away from its default: split, the book second and
-- given more room, the floating board bigger, and dark.
local function chosen()
    local layout, session = new_layout(PORTRAIT), new_session()
    layout:resize(2)
    layout:setSplit(true)
    layout:swapSplit()
    layout:moveDivider(-60)
    session:toggleDark()
    return layout, session
end

-- The choices of a table taken up by a new layout and session.
local function applied(prefs, size)
    local layout, session = new_layout(size or PORTRAIT), new_session()
    eq(Preferences.apply(prefs, layout, session), true)
    return layout, session
end

test("the preferences of a new window: floating, the book first, light", function()
    local layout = new_layout(PORTRAIT)
    eq(Preferences.of(layout, new_session()), {
        version = Preferences.VERSION,
        window = { split = false, text_first = true, text_share = 0.5,
            square_share = layout:squareSize() / PORTRAIT[1] },
        dark = false,
    })
end)

test("the choices saved are taken up again, by a new layout and session", function()
    local layout, session = chosen()
    local prefs = Preferences.of(layout, session)
    local again, dark = applied(prefs)
    eq(Preferences.of(again, dark), prefs)
    eq(again:isSplit(), true)
    eq(again:isTextFirst(), false)
    eq(again:textLength(), layout:textLength())
    eq(dark:isDark(), true)
end)

test("split, the size saved is the floating window's, and it comes back when it floats", function()
    local layout, session = chosen()
    local floating = new_layout(PORTRAIT)
    floating:resize(2)
    local again = applied(Preferences.of(layout, session))
    again:setSplit(false)
    eq(again:squareSize(), floating:squareSize())
end)

test("the size is a share of the short side, so it fits another screen", function()
    local layout = new_layout(PORTRAIT)
    layout:resize(2)
    local share = layout:squareSize() / PORTRAIT[1]
    local big = applied(Preferences.of(layout, new_session()), BIG)
    eq(big:squareSize(), math.floor(share * BIG[1] + 0.5))
end)

test("split on a turned screen, no size of the floating window is saved", function()
    local layout = new_layout(PORTRAIT)
    layout:setSplit(true)
    layout:setScreen(PORTRAIT[2], PORTRAIT[1])
    eq(layout:preferences().square_share, nil)
end)

test("nothing saved yet, the defaults stay", function()
    local layout, session = applied(nil)
    eq(Preferences.of(layout, session), Preferences.of(new_layout(PORTRAIT), new_session()))
end)

test("preferences of another version are not understood, and change nothing", function()
    local layout, session = chosen()
    local prefs = Preferences.of(layout, session)
    prefs.version = Preferences.VERSION + 1
    local fresh, light = new_layout(PORTRAIT), new_session()
    local ok, warning = Preferences.apply(prefs, fresh, light)
    eq(ok, nil)
    assert(warning:match("not understood"), warning)
    eq(Preferences.apply("broken", fresh, light), nil)
    eq(Preferences.of(fresh, light), Preferences.of(new_layout(PORTRAIT), new_session()))
end)

test("choices not understood are left as they are", function()
    local layout, session = applied({ version = Preferences.VERSION, dark = "yes",
        window = { split = 1, text_first = "no", text_share = 3, square_share = -1 } })
    eq(Preferences.of(layout, session), Preferences.of(new_layout(PORTRAIT), new_session()))
end)

test("the book's share is kept within its limits", function()
    local layout = applied({ version = Preferences.VERSION,
        window = { split = true, text_share = 0.01 } })
    local least = new_layout(PORTRAIT)
    least:setSplit(true)
    least:moveDivider(-10000)
    eq(layout:textLength(), least:textLength())
end)
