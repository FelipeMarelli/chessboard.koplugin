-- Rules tests from Ink Knight, adapted to chess/rules.lua.
--
-- Taken from tests/chess_spec.lua of Ink Knight, commit 601acd2a3a3e24148e442e10fd806accd6002782,
-- https://github.com/beater-studios/ink_knight.koplugin
-- Copyright (C) 2026 Beater Studios
-- Modified for chessbook.koplugin in November 2026: only the tests of the rules were kept, written
-- against the names of chess/rules.lua; the parts about Ink Knight's games, screens and Chess960
-- numbering were left out.
-- Licensed under the GNU General Public License, version 3 only: see
-- chessbook.koplugin/chess/LICENSE-GPL-3.0.
local Helper = require("helper")
local Chess = require("chess/rules")
local eq, test = Helper.eq, Helper.test

local function pos(fen) return assert(Chess.fromFen(fen)) end

local function move_by_uci(position, uci)
    for _, move in ipairs(Chess.legalMoves(position)) do
        if Chess.moveToUci(move, position) == uci then return move end
    end
end

local function has_move(position, uci)
    return move_by_uci(position, uci) ~= nil
end

local function apply_uci(position, uci)
    return Chess.apply(position, assert(Chess.parseUci(position, uci)))
end

-- The position after a list of moves in UCI separated by spaces, and the last move.
local function from_moves(moves)
    local position, last = pos(Chess.START_FEN), nil
    for uci in moves:gmatch("%S+") do
        position, last = assert(apply_uci(position, uci))
    end
    return position, last
end

local PERFT = {
    { "start", Chess.START_FEN, { 20, 400, 8902 } },
    { "promotions", "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
        { 6, 264, 9467 } },
}
for _, case in ipairs(PERFT) do
    test("perft " .. case[1], function()
        for depth, count in ipairs(case[3]) do
            eq(Chess.perft(pos(case[2]), depth), count)
        end
    end)
end

test("square names go both ways", function()
    eq(Chess.squareName(1), "a1"); eq(Chess.squareName(64), "h8")
    eq(Chess.squareFromName("e4"), 29); eq(Chess.squareFromName("z9"), nil)
end)

test("an invalid FEN is refused", function()
    eq(Chess.fromFen("not a fen"), nil)
    eq(Chess.fromFen("9/8/8/8/8/8/8/8/x w - -"), nil)
end)

test("castling cannot cross an attacked square", function()
    local position = pos("4k3/8/8/8/8/5r2/8/4K2R w K - 0 1")
    eq(has_move(position, "e1g1"), false)
end)

test("castling is not possible while in check", function()
    eq(has_move(pos("4k3/8/8/8/8/4r3/8/4K2R w K - 0 1"), "e1g1"), false)
end)

test("castling moves the rook too", function()
    local position = assert(apply_uci(pos("4k3/8/8/8/8/8/8/4K2R w K - 0 1"), "e1g1"))
    eq(position.board[Chess.squareFromName("f1")], "R")
    eq(position.board[Chess.squareFromName("h1")], nil)
    eq(position.board[Chess.squareFromName("g1")], "K")
end)

test("castling written as the king taking its rook is understood", function()
    local position = assert(apply_uci(pos("4k3/8/8/8/8/8/8/4K2R w K - 0 1"), "e1h1"))
    eq(position.board[Chess.squareFromName("g1")], "K")
    eq(position.board[Chess.squareFromName("f1")], "R")
end)

test("en passant removes the pawn that passed", function()
    local position = from_moves("e2e4 a7a6 e4e5 d7d5 e5d6")
    eq(position.board[Chess.squareFromName("d5")], nil)
    eq(position.board[Chess.squareFromName("d6")], "P")
end)

test("promotion gives the chosen piece", function()
    local position = assert(apply_uci(pos("8/P6k/8/8/8/8/8/K7 w - - 0 1"), "a7a8n"))
    eq(position.board[Chess.squareFromName("a8")], "N")
    local to_a8 = 0
    for _, move in ipairs(Chess.legalMovesFrom(pos("8/P6k/8/8/8/8/8/K7 w - - 0 1"),
            Chess.squareFromName("a7"))) do
        if move.to == Chess.squareFromName("a8") then to_a8 = to_a8 + 1 end
    end
    eq(to_a8, 4)
end)

test("a pinned piece cannot leave the line", function()
    eq(has_move(pos("4r2k/8/8/8/8/8/4N3/4K3 w - - 0 1"), "e2c3"), false)
end)

test("a checkmate has no moves", function()
    local position = from_moves("f2f3 e7e5 g2g4 d8h4")
    eq(#Chess.legalMoves(position), 0)
    eq(Chess.isCheck(position), true)
end)

test("the last move comes with the position", function()
    local _, last = from_moves("e2e4 e7e5")
    eq(Chess.squareName(last.to), "e5")
end)

test("a pawn that moved two squares leaves no mark when nothing can take it", function()
    local position = from_moves("e2e4")
    eq(position.passant, nil)
    position = from_moves("e2e4 d7d5 e4e5 f7f5")
    eq(Chess.squareName(position.passant), "f6")
    assert(has_move(position, "e5f6"))
end)

test("a capture in passing that a pin forbids is not a move", function()
    -- The white king on a5 and the black rook on h5 pin the pawn on e5, so it cannot take on d6.
    local before = pos("4k3/3p4/8/K3P2r/8/8/8/8 b - - 0 1")
    local after = assert(apply_uci(before, "d7d5"))
    eq(Chess.squareName(after.passant), "d6")
    eq(has_move(after, "e5d6"), false)
end)

test("a position becomes a FEN and back", function()
    local fen = "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 1"
    eq(Chess.toFen(Chess.fromFen(fen)), fen)
    eq(Chess.toFen(Chess.fromFen("8/8/8/8/4Pp2/8/8/4K2k b - e3 0 1")),
        "8/8/8/8/4Pp2/8/8/4K2k b - e3 0 1")
end)

test("moves are written in the usual notation", function()
    local function san(fen, uci)
        local position = Chess.fromFen(fen)
        return Chess.sanText(position, Chess.parseUci(position, uci))
    end
    eq(san(Chess.START_FEN, "g1f3"), "Nf3")
    eq(san(Chess.START_FEN, "e2e4"), "e4")
    eq(san("4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1", "e4d5"), "exd5")
    eq(san("r3k3/8/8/8/8/8/8/4K2R w K - 0 1", "e1g1"), "O-O")
    eq(san("4k3/P7/8/8/8/8/8/4K3 w - - 0 1", "a7a8q"), "a8=Q+")
    eq(san("6k1/8/6K1/8/8/8/8/R7 w - - 0 1", "a1a8"), "Ra8#")
    eq(san("6k1/8/8/8/8/8/4K3/R6R w - - 0 1", "a1d1"), "Rad1")
    eq(san("4k3/8/R7/8/8/8/8/R3K3 w - - 0 1", "a1a3"), "R1a3")
end)

test("a position of Chess960 that stands as standard chess counts the same", function()
    local standard_looking = pos("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w HAha - 0 1")
    assert(standard_looking.chess960 and standard_looking.castling == "HAha")
    eq(Chess.perft(standard_looking, 2), 400)
end)

test("X-FEN is read as Chess960 only when asked, and standard chess stays as it was", function()
    local start = pos(Chess.START_FEN)
    assert(not start.chess960 and start.castling == "KQkq", "standard chess keeps KQkq")
    -- KQkq is X-FEN only for a game said to be Chess960; the files of the rooks are Chess960
    -- anyway.
    local fen = "bbnrkqrn/pppppppp/8/8/8/8/PPPPPPPP/BBNRKQRN w KQkq - 0 1"
    local xfen = assert(Chess.fromFen(fen, true))
    eq(xfen.castling, "GDgd"); assert(xfen.chess960)
    assert(pos("bbnrkqrn/pppppppp/8/8/8/8/PPPPPPPP/BBNRKQRN w GDgd - 0 1").chess960)
    -- A right with no king or rook to stand for is dropped in Chess960.
    eq(assert(Chess.fromFen("r3k3/8/8/8/8/8/8/8 w KQq - 0 1", true)).castling, "a")
end)

test("a standard FEN written loosely keeps its rights, and does not become Chess960", function()
    -- A castling letter with no king or rook behind it: no castling at all.
    local loose = pos("8/8/8/8/8/5pk1/1r6/2R3K1 b Q - 0 1")
    assert(not loose.chess960 and loose.castling == "Q")
    loose.turn = "w"
    assert(not move_by_uci(loose, "g1c1") and not move_by_uci(loose, "g1e1"),
        "no castling for a king on g1")
    -- The black king already castled keeps white's castle on g1.
    local lesson = pos("rnb2rk1/pppp1ppp/5n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNB1K2R w KQkq - 0 1")
    assert(not lesson.chess960)
    local castle = move_by_uci(lesson, "e1g1")
    assert(castle and castle.castle, "castling to g1")
end)

test("in Chess960 a castling and a plain king move to the same square stay two moves", function()
    local position = pos("1k6/8/8/8/8/8/8/5K1R w H - 0 1")
    local castle = move_by_uci(position, "f1h1")
    local step = move_by_uci(position, "f1g1")
    assert(castle and step and castle.to == step.to, "both go to g1")
    assert(castle.castle and not step.castle)
    local castled = assert(Chess.apply(position, castle))
    eq(castled.board[Chess.squareFromName("f1")], "R")
    local stepped = assert(Chess.apply(position, step))
    eq(stepped.board[Chess.squareFromName("h1")], "R")
    eq(Chess.sanText(position, castle), "O-O")
end)

test("castling in Chess960 from wherever king and rook stand", function()
    -- King on b1, rook on a1: queen side castling takes the king to c1 and the rook to d1.
    local position = pos("rk6/8/8/8/8/8/8/RK5R w AHah - 0 1")
    local long = move_by_uci(position, "b1a1")
    assert(long and long.castle == Chess.squareFromName("a1"), "the king takes its rook to castle")
    local after = assert(Chess.apply(position, long))
    eq(after.board[Chess.squareFromName("c1")], "K")
    eq(after.board[Chess.squareFromName("d1")], "R")
    eq(after.board[Chess.squareFromName("a1")], nil)
    eq(after.board[Chess.squareFromName("b1")], nil)
    eq(after.castling, "ah")
    eq(Chess.sanText(position, long), "O-O-O")
    -- King side, the king going to g1 and the rook to f1.
    local short = move_by_uci(position, "b1h1")
    eq(Chess.sanText(position, short), "O-O")
    after = assert(Chess.apply(position, short))
    eq(after.board[Chess.squareFromName("g1")], "K")
    eq(after.board[Chess.squareFromName("f1")], "R")
end)

test("a king already on g castles by the rook alone, and a piece in the way stops it", function()
    local position = pos("6k1/8/8/8/8/8/8/6KR w H - 0 1")
    local castle = move_by_uci(position, "g1h1")
    assert(castle, "the king stays and the rook comes to f1")
    local after = assert(Chess.apply(position, castle))
    eq(after.board[Chess.squareFromName("g1")], "K")
    eq(after.board[Chess.squareFromName("f1")], "R")
    local blocked = pos("6k1/8/8/8/8/8/8/1N2K2R w H - 0 1")
    assert(move_by_uci(blocked, "e1h1"), "nothing between king, rook and their squares")
    blocked = pos("6k1/8/8/8/8/8/8/4KN1R w H - 0 1")
    assert(not move_by_uci(blocked, "e1h1"), "the knight on f1 is in the way")
    -- A square the king crosses under attack stops it, though the rook's path may be attacked.
    local attacked = pos("5r1k/8/8/8/8/8/8/4K2R w H - 0 1")
    assert(not move_by_uci(attacked, "e1h1"), "f1 is attacked")
end)

test("castling of standard chess keeps its notation", function()
    local position = pos("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    local move = move_by_uci(position, "e1g1")
    assert(move, "standard castling is e1g1 in UCI")
    eq(Chess.sanText(position, move), "O-O")
    eq(Chess.moveToUci(Chess.parseUci(position, "e1h1"), position), "e1g1")
    local after = apply_uci(position, "e1g1")
    eq(after.board[Chess.squareFromName("f1")], "R")
end)
