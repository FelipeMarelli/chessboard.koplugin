-- H02: acceptance criteria 2 to 7 of chess/game.lua.
local Game = require("chess/game")
local Games = require("games")
local Helper = require("helper")
local Rules = require("chess/rules")
local eq, test = Helper.eq, Helper.test
local move, play = Games.move, Games.play

local sq = Rules.squareFromName

local function fen(game)
    return Rules.toFen(game:position())
end

local AFTER_E4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
local AFTER_E4_E5 = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"

-- 1. Start position ----------------------------------------------------------------------------

test("C1: a new game starts at the usual position, or at any valid one", function()
    local game = assert(Game.new())
    eq(fen(game), Rules.START_FEN)
    eq(game:canBack(), false); eq(game:canForward(), false); eq(game:lastMove(), nil)
    local ending = "8/8/4k3/8/8/4K3/4P3/8 b - - 3 40"
    eq(fen(assert(Game.new(ending))), ending)
end)

test("C1: an invalid or unplayable start position gives nil and a message", function()
    for _, bad in ipairs({ "not a fen", "8/8/8/8/8/8/8/4K3 w - - 0 1" }) do
        local game, err = Game.new(bad)
        eq(game, nil); eq(type(err), "string")
    end
end)

-- 2. Playing at the end ------------------------------------------------------------------------

test("C2: a legal move at the end is added and the cursor moves on", function()
    local game = assert(Game.new())
    eq(game:play(move("e2e4")), true)
    eq(fen(game), AFTER_E4)
    eq(game:canBack(), true); eq(game:canForward(), false)
    play(game, "e7e5")
    eq(fen(game), AFTER_E4_E5)
end)

test("C2: an illegal move is refused and changes nothing", function()
    local game = Games.of(nil, "e2e4", "e7e5", "g1f3")
    game:back()
    local before = game:serialize()
    for _, bad in ipairs({ move("e2e4"), move("e1e3"), { from = 99, to = 1 }, "e2e4" }) do
        local ok, err = game:play(bad)
        eq(ok, nil); eq(type(err), "string")
        eq(game:serialize(), before)
    end
end)

-- 3. Playing in the middle ---------------------------------------------------------------------

test("C3: another move in the middle replaces everything that followed", function()
    local game = Games.of(nil, "e2e4", "e7e5", "g1f3", "b8c6")
    game:back(); game:back()
    play(game, "f1c4")
    eq(game:canForward(), false)
    eq(game:serialize().moves, { "e2e4", "e7e5", "f1c4" })
    game:toStart()
    eq(game:toEnd(), true)
    eq(Rules.squareName(game:lastMove().move.to), "c4")
end)

test("C3: the same move as the one already there only moves the cursor", function()
    local game = Games.of(nil, "e2e4", "e7e5", "g1f3", "b8c6")
    game:toStart()
    play(game, "e2e4")
    eq(game:canForward(), true)
    eq(game:serialize(), { start = Rules.START_FEN, moves = { "e2e4", "e7e5", "g1f3", "b8c6" },
        cursor = 1 })
end)

test("C3: the same squares with another promotion is another move", function()
    local game = Games.of("4k3/P7/8/8/8/8/8/4K3 w - - 0 1", "a7a8q", "e8d7")
    game:toStart()
    play(game, "a7a8n")
    eq(game:serialize().moves, { "a7a8n" })
end)

-- 4. Navigation --------------------------------------------------------------------------------

test("C4: back, forward, start and end", function()
    local game = Games.of(nil, "e2e4", "e7e5", "g1f3")
    eq(game:back(), true); eq(fen(game), AFTER_E4_E5)
    eq(game:back(), true); eq(fen(game), AFTER_E4)
    eq(game:forward(), true); eq(fen(game), AFTER_E4_E5)
    eq(game:toStart(), true); eq(fen(game), Rules.START_FEN)
    eq(game:toEnd(), true)
    eq(Rules.squareName(game:lastMove().move.to), "f3")
end)

test("C4: at either end the moves do nothing and do not fail", function()
    local empty = assert(Game.new())
    eq(empty:back(), false); eq(empty:forward(), false)
    eq(empty:toStart(), false); eq(empty:toEnd(), false)
    eq(fen(empty), Rules.START_FEN)
    local game = Games.of(nil, "e2e4")
    eq(game:forward(), false); eq(game:toEnd(), false); eq(fen(game), AFTER_E4)
    game:toStart()
    eq(game:back(), false); eq(game:toStart(), false); eq(fen(game), Rules.START_FEN)
end)

-- 5. What can be asked -------------------------------------------------------------------------

test("C5: the last move, with its number, color and notation", function()
    local game = Games.of(nil, "e2e4")
    eq(game:lastMove(), {
        move = { from = sq("e2"), to = sq("e4") }, number = 1, color = "w",
        san = { text = "e4", suffix = "" },
    })
    play(game, "e7e5", "g1f3", "b8c6")
    local last = game:lastMove()
    eq(last.number, 2); eq(last.color, "b")
    eq(last.move.from, sq("b8")); eq(last.move.to, sq("c6"))
    eq(last.san, { piece = "n", text = "c6", suffix = "" })
    game:back()
    eq(game:lastMove().san, { piece = "N", text = "f3", suffix = "" })
end)

test("C5: the move number follows the start position", function()
    local game = Games.of("4k3/8/8/8/8/8/4P3/4K3 b - - 0 12", "e8d7", "e2e4")
    eq(game:lastMove().number, 13); eq(game:lastMove().color, "w")
    game:back()
    eq(game:lastMove().number, 12); eq(game:lastMove().color, "b")
end)

test("C5: castling, check and mate come in the notation", function()
    local game = Games.of(nil, "f2f3", "e7e5", "g2g4", "d8h4")
    eq(game:lastMove().san, { piece = "q", text = "h4", suffix = "#" })
    local castle = Games.of("r3k3/8/8/8/8/8/8/R3K2R w KQq - 0 1", "e1g1")
    eq(castle:lastMove().san, { text = "O-O", suffix = "" })
    eq(castle:lastMove().move.castle, sq("h1"))
end)

-- The notation of each move in a list, as plain text.
local function texts(moves)
    local list = {}
    for _, m in ipairs(moves) do
        list[#list + 1] = m.number .. m.color .. ":" .. (m.san.piece or "") .. m.san.text
    end
    return list
end

test("H16: the last moves up to the cursor, oldest first", function()
    local game = assert(Game.new())
    eq(game:recentMoves(3), {})
    play(game, "e2e4", "e7e5", "g1f3", "b8c6")
    eq(texts(game:recentMoves(3)), { "1b:e5", "2w:Nf3", "2b:nc6" })
    eq(texts(game:recentMoves(10)), { "1w:e4", "1b:e5", "2w:Nf3", "2b:nc6" })
    game:back()
    eq(texts(game:recentMoves(2)), { "1b:e5", "2w:Nf3" })
    eq(game:recentMoves(1)[1], game:lastMove())
end)

test("H16: the next moves of the line after the cursor, in order", function()
    local game = assert(Game.new())
    play(game, "e2e4", "e7e5", "g1f3", "b8c6")
    eq(game:nextMoves(3), {})
    game:toStart()
    eq(texts(game:nextMoves(3)), { "1w:e4", "1b:e5", "2w:Nf3" })
    game:forward()
    eq(texts(game:nextMoves(10)), { "1b:e5", "2w:Nf3", "2b:nc6" })
end)

test("H16: the FEN the game started from, wherever the cursor is", function()
    local game = Games.of(nil, "e2e4")
    eq(game:startFen(), Rules.START_FEN)
    assert(game:reset("4k3/8/8/8/8/8/4P3/4K3 b - - 0 12"))
    eq(game:startFen(), "4k3/8/8/8/8/8/4P3/4K3 b - - 0 12")
end)

-- 6. A new game --------------------------------------------------------------------------------

test("C6: starting again from a position replaces the line", function()
    local game = Games.of(nil, "e2e4", "e7e5")
    local ending = "8/8/4k3/8/8/4K3/4P3/8 w - - 0 1"
    eq(game:reset(ending), true)
    eq(fen(game), ending)
    eq(game:canBack(), false); eq(game:canForward(), false)
    eq(game:serialize(), { start = ending, moves = {}, cursor = 0 })
    eq(game:reset(), true)
    eq(fen(game), Rules.START_FEN)
end)

test("C6: starting again from an invalid position changes nothing", function()
    local game = Games.of(nil, "e2e4", "e7e5")
    local before = game:serialize()
    local ok, err = game:reset("8/8/8/8/8/8/8/8 w - - 0 1")
    eq(ok, nil); eq(type(err), "string")
    eq(game:serialize(), before)
end)

-- 7. Saving and reading back -------------------------------------------------------------------

test("C7: a game becomes a plain table and comes back without loss", function()
    local game = Games.of(nil, "e2e4", "e7e5", "g1f3", "b8c6", "f1b5")
    game:back(); game:back()
    local data = game:serialize()
    eq(data, { start = Rules.START_FEN, moves = { "e2e4", "e7e5", "g1f3", "b8c6", "f1b5" },
        cursor = 3 })
    local copy = assert(Game.deserialize(data))
    eq(copy:serialize(), data)
    eq(fen(copy), fen(game))
    eq(copy:lastMove(), game:lastMove())
    eq(copy:toEnd(), true)
    eq(Rules.squareName(copy:lastMove().move.to), "b5")
end)

test("C7: castling, en passant and promotion survive the round trip", function()
    local start = "r3k2r/6P1/8/3pP3/8/8/8/R3K2R w KQkq d6 0 30"
    local game = Games.of(start, "e5d6", "e8c8", "g7g8r", "c8b8", "e1g1")
    local data = game:serialize()
    eq(data.moves, { "e5d6", "e8c8", "g7g8r", "c8b8", "e1g1" })
    local copy = assert(Game.deserialize(data))
    eq(fen(copy), fen(game))
end)

test("C7: a Chess960 game keeps its castling as the king taking its rook", function()
    local game = Games.of("1k6/8/8/8/8/8/8/5K1R w H - 0 1", "f1g1")
    local castle = assert(Game.new("1k6/8/8/8/8/8/8/5K1R w H - 0 1"))
    for _, m in ipairs(Rules.legalMoves(castle:position())) do
        if m.castle then assert(castle:play(m)) end
    end
    eq(game:serialize().moves, { "f1g1" })
    eq(castle:serialize().moves, { "f1h1" })
    eq(fen(assert(Game.deserialize(castle:serialize()))), fen(castle))
    eq(fen(assert(Game.deserialize(game:serialize()))), fen(game))
end)

test("C7: data that cannot be read gives nil and a message", function()
    local good = { start = Rules.START_FEN, moves = { "e2e4" }, cursor = 1 }
    local bad = {
        "text", 42, {},
        { start = "not a fen", moves = {}, cursor = 0 },
        { start = Rules.START_FEN, moves = "e2e4", cursor = 0 },
        { start = Rules.START_FEN, moves = { "e2e5" }, cursor = 0 },
        { start = Rules.START_FEN, moves = { "zz" }, cursor = 0 },
        { start = Rules.START_FEN, moves = { "e2e4" }, cursor = 2 },
        { start = Rules.START_FEN, moves = { "e2e4" }, cursor = -1 },
        { start = Rules.START_FEN, moves = { "e2e4" }, cursor = 0.5 },
        { start = Rules.START_FEN, moves = { "e2e4" } },
    }
    assert(Game.deserialize(good))
    for _, data in ipairs(bad) do
        local ok, game, err = pcall(Game.deserialize, data)
        eq(ok, true); eq(game, nil); eq(type(err), "string")
    end
end)
