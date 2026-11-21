-- H01: acceptance criteria 1 to 8 of chess/rules.lua.
local Helper = require("helper")
local Rules = require("chess/rules")
local eq, test = Helper.eq, Helper.test

local sq = Rules.squareFromName

local function pos(fen)
    return assert(Rules.fromFen(fen))
end

local function move(uci)
    local from, to, promotion = uci:match("^(%a%d)(%a%d)(%a?)$")
    return { from = sq(from), to = sq(to), promotion = promotion ~= "" and promotion or nil }
end

local function ucis(moves)
    local list = {}
    for _, m in ipairs(moves) do
        list[#list + 1] = Rules.moveToUci(m)
    end
    table.sort(list)
    return list
end

local function has(position, uci)
    for _, m in ipairs(Rules.legalMoves(position)) do
        if Rules.moveToUci(m) == uci then
            return true
        end
    end
    return false
end

local function play(position, ...)
    for _, uci in ipairs({ ... }) do
        position = assert(Rules.apply(position, move(uci)))
    end
    return position
end

local REFERENCE = {
    { Rules.START_FEN, { 20, 400, 8902, 197281 } },
    { "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", { 48, 2039, 97862 } },
    { "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", { 14, 191, 2812, 43238 } },
    { "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", { 44, 1486, 62379 } },
}

-- Squares ------------------------------------------------------------------------------------

test("squares are numbers from a1 = 1 to h8 = 64", function()
    eq(sq("a1"), 1); eq(sq("h1"), 8); eq(sq("a2"), 9); eq(sq("e4"), 29); eq(sq("h8"), 64)
    eq(Rules.squareName(29), "e4"); eq(sq("i1"), nil); eq(sq("a9"), nil); eq(sq(nil), nil)
    eq(Rules.fileOf(29), 5); eq(Rules.rankOf(29), 4)
    eq(Rules.square(5, 4), 29); eq(Rules.square(9, 1), nil); eq(Rules.square(1, 0), nil)
end)

-- 1. A complete position -----------------------------------------------------------------------

test("C1: a position has pieces, turn, castling, en passant and both counters", function()
    local p = pos("rnbqkbnr/pp1ppppp/8/2pP4/8/8/PPP1PPPP/RNBQKBNR w Kq c6 0 3")
    eq(Rules.pieceAt(p, sq("d5")), "P"); eq(Rules.pieceAt(p, sq("e8")), "k")
    eq(Rules.pieceAt(p, sq("d2")), nil)
    eq(Rules.turn(p), "w")
    eq(p.castling, "Kq"); eq(p.passant, sq("c6")); eq(p.halfmove, 0); eq(p.fullmove, 3)
    eq(Rules.kingSquare(p, "w"), sq("e1")); eq(Rules.kingSquare(p, "b"), sq("e8"))
end)

-- 2. FEN ---------------------------------------------------------------------------------------

test("C2: reading a FEN and writing it back gives the same text", function()
    local fens = {
        "rnbqkbnr/pp1ppppp/8/2pP4/8/8/PPP1PPPP/RNBQKBNR w Kq c6 0 3",
        "8/8/8/8/4Pp2/8/8/4K2k b - e3 0 57",
        "r3k2r/8/8/8/8/8/8/R3K2R b - - 99 120",
        "4k3/8/8/8/8/8/8/4K3 w - - 0 1",
    }
    for _, case in ipairs(REFERENCE) do
        fens[#fens + 1] = case[1]
    end
    for _, fen in ipairs(fens) do
        eq(Rules.toFen(pos(fen)), fen)
    end
end)

test("C2: a FEN without counters reads them as 0 and 1", function()
    eq(Rules.toFen(pos("4k3/8/8/8/8/8/8/4K3 w - -")), "4k3/8/8/8/8/8/8/4K3 w - - 0 1")
end)

test("C2: a malformed FEN gives nil and a message, never an exception", function()
    local bad = {
        "", "not a fen", 42, {},
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP w KQkq - 0 1",           -- 7 ranks
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR/8 w KQkq - 0 1", -- 9 ranks
        "rnbqkbnr/ppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",    -- 7 squares
        "rnbqkbnr/ppppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",  -- 9 squares
        "rnbqkbnr/pppppppp/9/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",   -- digit 9
        "rnbqkbnr/pppppppp/44/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",  -- two digits
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNX w KQkq - 0 1",   -- unknown piece
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1",   -- turn
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkx - 0 1",   -- castling
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq e4 0 1",  -- en passant rank
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq z3 0 1",  -- en passant file
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - x 1",   -- half moves
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 0",   -- move number
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1 x", -- 7 fields
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq",         -- 3 fields
    }
    for _, fen in ipairs(bad) do
        local ok, position, err = pcall(Rules.fromFen, fen)
        eq(ok, true, "no exception for " .. tostring(fen))
        eq(position, nil, tostring(fen))
        eq(type(err), "string", tostring(fen))
    end
end)

-- 3. Legal moves -------------------------------------------------------------------------------

test("C3: all the legal moves, and those from one square", function()
    local start = pos(Rules.START_FEN)
    eq(#Rules.legalMoves(start), 20)
    eq(ucis(Rules.legalMovesFrom(start, sq("g1"))), { "g1f3", "g1h3" })
    eq(ucis(Rules.legalMovesFrom(start, sq("e2"))), { "e2e3", "e2e4" })
    eq(Rules.legalMovesFrom(start, sq("e4")), {})
    eq(Rules.legalMovesFrom(start, sq("e7")), {})
end)

test("C3: castling on both sides, which moves the rook too", function()
    local p = pos("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    assert(has(p, "e1g1") and has(p, "e1c1"))
    local short = play(p, "e1g1")
    eq(Rules.pieceAt(short, sq("g1")), "K"); eq(Rules.pieceAt(short, sq("f1")), "R")
    eq(Rules.pieceAt(short, sq("h1")), nil); eq(short.castling, "kq")
    local long = play(p, "e1c1")
    eq(Rules.pieceAt(long, sq("c1")), "K"); eq(Rules.pieceAt(long, sq("d1")), "R")
    eq(Rules.pieceAt(long, sq("a1")), nil)
end)

test("C3: no castling through or out of an attacked square, nor without the right", function()
    eq(has(pos("4k3/8/8/8/8/5r2/8/4K2R w K - 0 1"), "e1g1"), false) -- f1 attacked
    eq(has(pos("4k3/8/8/8/8/3r4/8/R3K3 w Q - 0 1"), "e1c1"), false) -- d1 attacked
    eq(has(pos("4k3/8/8/8/8/4r3/8/4K2R w K - 0 1"), "e1g1"), false) -- in check
    eq(has(pos("4k3/8/8/8/8/8/8/4K2R w - - 0 1"), "e1g1"), false)   -- no right
    eq(has(pos("4k3/8/8/8/8/8/8/4KN1R w K - 0 1"), "e1g1"), false)  -- blocked
    -- The b1 square may be attacked: only the king's path counts.
    assert(has(pos("4k3/8/8/8/8/1r6/8/R3K3 w Q - 0 1"), "e1c1"))
end)

test("C3: en passant captures the pawn that passed", function()
    local p = pos("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
    assert(has(p, "e5d6"))
    local after = play(p, "e5d6")
    eq(Rules.pieceAt(after, sq("d5")), nil); eq(Rules.pieceAt(after, sq("d6")), "P")
end)

test("C3: a pawn reaching the last rank has the four promotions", function()
    local p = pos("8/P6k/8/8/8/8/8/K7 w - - 0 1")
    eq(ucis(Rules.legalMovesFrom(p, sq("a7"))), { "a7a8b", "a7a8n", "a7a8q", "a7a8r" })
    eq(Rules.pieceAt(play(p, "a7a8n"), sq("a8")), "N")
    eq(Rules.pieceAt(play(pos("k7/8/8/8/8/8/p7/7K b - - 0 1"), "a2a1q"), sq("a1")), "q")
end)

test("C3: no move leaves the own king in check", function()
    eq(has(pos("4r2k/8/8/8/8/8/4N3/4K3 w - - 0 1"), "e2c3"), false) -- pinned knight
    eq(has(pos("4k3/8/8/8/8/8/8/r3K3 w - - 0 1"), "e1d1"), false)   -- into check
    -- In check, only the moves that answer it.
    eq(ucis(Rules.legalMoves(pos("4k3/8/8/8/8/8/3PPP2/r3K3 w - - 0 1"))), {})
end)

-- 4. Reference counts --------------------------------------------------------------------------

test("C4: perft matches the reference table", function()
    for _, case in ipairs(REFERENCE) do
        local p = pos(case[1])
        for depth, count in ipairs(case[2]) do
            eq(Rules.perft(p, depth), count, case[1] .. " depth " .. depth)
        end
    end
end)

-- 5. Applying a move ---------------------------------------------------------------------------

test("C5: applying a move returns a new position and leaves the old one as it was", function()
    local start = pos(Rules.START_FEN)
    local after = play(start, "e2e4")
    eq(Rules.toFen(start), Rules.START_FEN)
    eq(Rules.toFen(after), "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1")
end)

test("C5: turn, counters and move number are updated", function()
    local p = play(pos(Rules.START_FEN), "g1f3")
    eq(p.turn, "b"); eq(p.halfmove, 1); eq(p.fullmove, 1)
    p = play(p, "g8f6")
    eq(p.turn, "w"); eq(p.halfmove, 2); eq(p.fullmove, 2)
    p = play(p, "e2e4")
    eq(p.halfmove, 0)
    p = play(p, "f6e4")
    eq(p.halfmove, 0); eq(p.fullmove, 3)
end)

test("C5: castling rights go with the king, a rook that moves and a rook taken", function()
    local p = pos("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    eq(play(p, "e1e2").castling, "kq")
    eq(play(p, "h1h2").castling, "Qkq")
    eq(play(p, "a1a8").castling, "Kk")
end)

test("C5: the en passant square is kept only when a pawn can take", function()
    eq(play(pos(Rules.START_FEN), "e2e4").passant, nil)
    local p = play(pos(Rules.START_FEN), "e2e4", "a7a6", "e4e5", "d7d5")
    eq(p.passant, sq("d6"))
    eq(play(p, "e5d6").passant, nil)
end)

test("C5: an illegal or malformed move gives nil and a message", function()
    local start = pos(Rules.START_FEN)
    local cases = { move("e2e5"), move("e7e5"), move("a1a3"), { from = 99, to = 1 }, {}, "e2e4",
        move("e2e4q") }
    for _, m in ipairs(cases) do
        local ok, position, err = pcall(Rules.apply, start, m)
        eq(ok, true); eq(position, nil); eq(type(err), "string")
    end
    -- A promotion needs its piece.
    eq(Rules.apply(pos("8/P6k/8/8/8/8/8/K7 w - - 0 1"), move("a7a8")), nil)
end)

-- 6. Check, checkmate, stalemate ---------------------------------------------------------------

test("C6: check, checkmate and stalemate", function()
    local start = pos(Rules.START_FEN)
    eq(Rules.isCheck(start), false); eq(Rules.status(start), "ongoing")
    local check = pos("4k3/8/8/8/8/8/8/4RK2 b - - 0 1")
    eq(Rules.isCheck(check), true); eq(Rules.status(check), "ongoing")
    local mate = play(start, "f2f3", "e7e5", "g2g4", "d8h4")
    eq(Rules.isCheck(mate), true); eq(Rules.status(mate), "checkmate")
    local stalemate = pos("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
    eq(Rules.isCheck(stalemate), false); eq(Rules.status(stalemate), "stalemate")
end)

test("draws by insufficient material and by the fifty-move rule", function()
    eq(Rules.ending(pos(Rules.START_FEN)), nil)
    eq(Rules.ending(pos("4k3/8/8/8/8/8/8/4KB2 w - - 0 1")), "insufficient")
    eq(Rules.ending(pos("4k3/8/8/8/8/8/8/3NKB2 w - - 0 1")), nil)
    eq(Rules.ending(pos("4k3/8/8/8/8/8/8/R3K3 w - - 100 80")), "fifty")
    eq(Rules.ending(pos("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")), "stalemate")
end)

-- 7. Notation ----------------------------------------------------------------------------------

local function san(fen, uci)
    return Rules.san(pos(fen), move(uci))
end

test("C7: the piece letter comes apart from the rest", function()
    eq(san(Rules.START_FEN, "g1f3"), { piece = "N", text = "f3", suffix = "" })
    eq(san(Rules.START_FEN, "e2e4"), { text = "e4", suffix = "" })
    eq(san("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1", "b8c6"),
        { piece = "n", text = "c6", suffix = "" })
end)

test("C7: disambiguation by file, by rank and by both", function()
    local knights = "rnbqkb1r/ppp1pppp/5n2/3p4/3P4/5N2/PPP1PPPP/RNBQKB1R b KQkq - 2 3"
    eq(Rules.sanText(pos(knights), move("b8d7")), "Nbd7")
    eq(Rules.sanText(pos(knights), move("f6d7")), "Nfd7")
    local rooks = "7k/8/8/8/8/4R3/8/K3R3 w - - 0 1"
    eq(san(rooks, "e1e2"), { piece = "R", text = "1e2", suffix = "" })
    eq(Rules.sanText(pos(rooks), move("e3e2")), "R3e2")
    eq(Rules.sanText(pos("8/8/1k6/8/4Q2Q/8/8/K6Q w - - 0 1"), move("h4e1")), "Qh4e1")
    -- A pinned twin does not count.
    eq(Rules.sanText(pos("4r2k/8/8/8/8/8/N3N3/4K3 w - - 0 1"), move("a2c3")), "Nc3")
end)

test("C7: captures, castling, promotion, check and mate", function()
    eq(san("4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1", "e4d5"), { text = "exd5", suffix = "" })
    eq(san("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", "e5d6"), { text = "exd6", suffix = "" })
    eq(Rules.sanText(pos("4k3/8/8/4p3/8/5N2/8/4K3 w - - 0 1"), move("f3e5")), "Nxe5")
    eq(san("r2k4/8/8/8/8/8/8/R3K2R w KQ - 0 1", "e1g1"), { text = "O-O", suffix = "" })
    eq(san("r2k4/8/8/8/8/8/8/R3K2R w KQ - 0 1", "e1c1"), { text = "O-O-O", suffix = "+" })
    eq(san("8/4P3/8/8/8/8/k7/4K3 w - - 0 1", "e7e8q"),
        { text = "e8", promotion = "Q", suffix = "" })
    eq(san("k7/8/8/8/8/8/4p3/K7 b - - 0 1", "e2e1q"),
        { text = "e1", promotion = "q", suffix = "+" })
    eq(Rules.sanText(pos("5r1k/4P3/8/8/8/8/8/K7 w - - 0 1"), move("e7f8n")), "exf8=N")
    eq(Rules.sanText(pos("6k1/8/6K1/8/8/8/8/R7 w - - 0 1"), move("a1a8")), "Ra8#")
    eq(Rules.sanText(pos("4k3/8/8/8/8/8/8/R3K3 w - - 0 1"), move("a1a8")), "Ra8+")
end)

test("C7: notation of an illegal move gives nil and a message", function()
    local parts, err = Rules.san(pos(Rules.START_FEN), move("e2e5"))
    eq(parts, nil); eq(type(err), "string")
end)

-- 8. Validation of a position set up by hand ---------------------------------------------------

test("C8: a playable position is valid", function()
    eq(Rules.validate(pos(Rules.START_FEN)), true)
    eq(Rules.validate(pos("4k3/8/8/8/8/8/8/4RK2 b - - 0 1")), true) -- side to move in check
end)

test("C8: each invalid position says why", function()
    local cases = {
        { "8/8/8/8/8/8/8/4K3 w - - 0 1", "Place exactly one king of each color." },
        { "4k3/8/8/8/8/8/8/8 w - - 0 1", "Place exactly one king of each color." },
        { "4k3/8/8/8/8/8/8/K3K3 w - - 0 1", "Place exactly one king of each color." },
        { "4k2k/8/8/8/8/8/8/4K3 w - - 0 1", "Place exactly one king of each color." },
        { "P3k3/8/8/8/8/8/8/4K3 w - - 0 1", "Move the pawns off the first and last ranks." },
        { "4k3/8/8/8/8/8/8/p3K3 w - - 0 1", "Move the pawns off the first and last ranks." },
        { "4k3/4r3/8/8/8/8/8/4K3 b - - 0 1",
            "The side not to move is in check: change the turn or the position." },
    }
    for _, case in ipairs(cases) do
        local ok, reason = Rules.validate(pos(case[1]))
        eq(ok, nil, case[1]); eq(reason, case[2], case[1])
    end
end)

test("a piece in upper case is White's, in lower case Black's", function()
    eq(Rules.colorOf("K"), "w")
    eq(Rules.colorOf("p"), "b")
end)

test("a move captures when it takes a piece on its target, or a pawn en passant", function()
    local position = pos("4k3/8/8/3pP3/8/8/8/R3K3 w - d6 0 1")
    eq(Rules.isCapture(position, move("e5d6")), true)
    eq(Rules.isCapture(position, move("e5e6")), false)
    eq(Rules.isCapture(position, move("a1a8")), false)
    eq(Rules.isCapture(pos("r3k3/8/8/8/8/8/8/R3K3 w - - 0 1"), move("a1a8")), true)
end)
