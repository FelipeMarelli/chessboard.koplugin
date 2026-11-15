-- H03: what model/session.lua exposes to draw the board, and flipping it.
local Game = require("chess/game")
local Helper = require("helper")
local Rules = require("chess/rules")
local Session = require("model/session")
local eq, test = Helper.eq, Helper.test

local sq = Rules.squareFromName

test("C4: the view of a new game is the start position, square by square", function()
    local view = Session.new(assert(Game.new())):view()
    eq(view.squares[sq("e1")], { piece = "K", marks = {}, light = false })
    eq(view.squares[sq("d1")], { piece = "Q", marks = {}, light = true })
    eq(view.squares[sq("d8")], { piece = "q", marks = {}, light = false })
    eq(view.squares[sq("e4")], { marks = {}, light = true })
    eq(view.squares[sq("a1")].light, false); eq(view.squares[sq("h8")].light, false)
    eq(view.squares[sq("h1")].light, true); eq(view.squares[sq("e5")].light, false)
    local pieces = 0
    for square = 1, 64 do
        assert(view.squares[square], "missing square " .. square)
        if view.squares[square].piece then
            pieces = pieces + 1
        end
    end
    eq(pieces, 32)
    eq(view.turn, "w"); eq(view.status, "ongoing"); eq(view.last_move, nil)
    eq(view.promotion, nil)
end)

test("C4: the view follows the game", function()
    local game = assert(Game.new())
    local session = Session.new(game)
    assert(game:play({ from = sq("e2"), to = sq("e4") }))
    local view = session:view()
    eq(view.squares[sq("e4")].piece, "P"); eq(view.squares[sq("e2")].piece, nil)
    eq(view.turn, "b"); eq(view.last_move.san.text, "e4")
end)

test("C9: flipping turns the board round, and again turns it back", function()
    local session = Session.new(assert(Game.new()))
    eq(session:flipped(), false); eq(session:view().flipped, false)
    session:flip()
    eq(session:flipped(), true); eq(session:view().flipped, true)
    session:flip()
    eq(session:flipped(), false)
end)

test("C2: close and flip can always be used", function()
    eq(Session.new(assert(Game.new())):view().buttons, { close = true, flip = true })
end)
