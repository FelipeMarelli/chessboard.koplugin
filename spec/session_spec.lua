-- H03, H07: what model/session.lua exposes to draw the board, flipping it, and playing moves
-- with two taps.
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

test("C2: close, flip and reset can always be used", function()
    eq(Session.new(assert(Game.new())):view().buttons, { close = true, flip = true, reset = true })
end)

-- H07

local function session_at(fen)
    return Session.new(assert(Game.new(fen)))
end

-- Taps squares by name, one after another; returns what the last tap answered.
local function tap(session, ...)
    local result
    for _, name in ipairs({ ... }) do
        result = session:tapSquare(sq(name))
    end
    return result
end

-- The names of the squares that carry a mark, in alphabetical order.
local function marked(session, name)
    local names = {}
    for square, info in pairs(session:view().squares) do
        if info.marks[name] then
            names[#names + 1] = Rules.squareName(square)
        end
    end
    table.sort(names)
    return names
end

local function piece_on(session, name)
    return session:view().squares[sq(name)].piece
end

local AFTER_E4_D5 = "rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"

test("H07 C1: tapping a piece of the side to move selects it and shows its targets", function()
    local session = session_at()
    eq(tap(session, "e2"), { changed = true, needs_promotion = false })
    eq(marked(session, "selected"), { "e2" })
    eq(marked(session, "target"), { "e3", "e4" })
    eq(marked(session, "capture"), {})
end)

test("H07 C1: captures are told apart from moves to an empty square", function()
    local session = session_at(AFTER_E4_D5)
    tap(session, "e4")
    eq(marked(session, "target"), { "e5" })
    eq(marked(session, "capture"), { "d5" })
end)

test("H07 C2: tapping a target plays the move and clears the selection", function()
    local session = session_at()
    local result = tap(session, "g1", "f3")
    eq(result.changed, true); eq(result.needs_promotion, false)
    eq(result.played, { from = sq("g1"), to = sq("f3") })
    eq(piece_on(session, "f3"), "N"); eq(piece_on(session, "g1"), nil)
    eq(session:view().turn, "b")
    eq(marked(session, "selected"), {}); eq(marked(session, "target"), {})
end)

test("H07 C3: tapping the selected piece again clears the selection", function()
    local session = session_at()
    eq(tap(session, "e2", "e2").changed, true)
    eq(marked(session, "selected"), {}); eq(marked(session, "target"), {})
end)

test("H07 C3: tapping another piece of the same side selects it instead", function()
    local session = session_at()
    tap(session, "e2", "g1")
    eq(marked(session, "selected"), { "g1" })
    eq(marked(session, "target"), { "f3", "h3" })
end)

test("H07 C3: tapping a square that is not a target clears the selection and moves nothing",
    function()
        for _, name in ipairs({ "e5", "d7", "a1" }) do
            local session = session_at()
            local result = tap(session, "e2", name)
            eq(result, { changed = true, needs_promotion = false }, name)
            eq(marked(session, "selected"), {}, name)
            eq(piece_on(session, "e2"), "P", name); eq(session:view().turn, "w", name)
        end
    end)

test("H07 C4: a piece of the other side, one with no moves, or an empty square select nothing",
    function()
        for _, name in ipairs({ "e7", "a1", "e1", "e4" }) do
            local session = session_at()
            eq(tap(session, name), { changed = false, needs_promotion = false }, name)
            eq(marked(session, "selected"), {}, name)
        end
    end)

test("H07 C5: castling is moving the king two squares; the rook follows", function()
    local session = session_at("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    tap(session, "e1")
    eq(marked(session, "target"), { "c1", "d1", "d2", "e2", "f1", "f2", "g1" })
    tap(session, "g1")
    eq(piece_on(session, "g1"), "K"); eq(piece_on(session, "f1"), "R")
    eq(piece_on(session, "h1"), nil); eq(piece_on(session, "e1"), nil)
end)

test("H07 C5: en passant is a capture, and takes the pawn off its square", function()
    local session = session_at("rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3")
    tap(session, "e5")
    eq(marked(session, "target"), { "e6" })
    eq(marked(session, "capture"), { "f6" })
    tap(session, "f6")
    eq(piece_on(session, "f6"), "P"); eq(piece_on(session, "f5"), nil)
end)

test("H07 C6: the squares of the last move stay marked", function()
    local session = session_at()
    eq(marked(session, "last_move"), {})
    tap(session, "e2", "e4")
    eq(marked(session, "last_move"), { "e2", "e4" })
    tap(session, "g8", "f6")
    eq(marked(session, "last_move"), { "f6", "g8" })
end)

test("H07 C6: after castling the last move marks where the king went from and to", function()
    local session = session_at("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    tap(session, "e1", "c1")
    eq(marked(session, "last_move"), { "c1", "e1" })
end)

test("H07 C7: the king of the side to move is marked when in check", function()
    local session = session_at("4k3/8/8/8/8/8/4r3/4K3 w - - 0 1")
    eq(marked(session, "check"), { "e1" })
    eq(session:view().status, "ongoing")
    tap(session, "e1", "e2")
    eq(marked(session, "check"), {})
end)

test("H07 C7: the view tells checkmate and stalemate", function()
    local mate = session_at("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3")
    eq(mate:view().status, "checkmate"); eq(marked(mate, "check"), { "e1" })
    local stalemate = session_at("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
    eq(stalemate:view().status, "stalemate"); eq(marked(stalemate, "check"), {})
end)

test("H07 C8: the view tells whose turn it is", function()
    local session = session_at()
    eq(session:view().turn, "w")
    tap(session, "d2", "d4")
    eq(session:view().turn, "b")
end)

local PROMOTION = "8/P7/8/8/8/8/8/k6K w - - 0 1"

test("H07: a move that promotes waits for the piece, and other taps do nothing meanwhile",
    function()
        local session = session_at(PROMOTION)
        eq(tap(session, "a7", "a8"), { changed = true, needs_promotion = true })
        eq(piece_on(session, "a7"), "P"); eq(piece_on(session, "a8"), nil)
        eq(session:view().promotion, { square = "a8", color = "w" })
        eq(marked(session, "selected"), {})
        eq(tap(session, "h1"), { changed = false, needs_promotion = false })
    end)

test("H07: choosing the piece completes the promotion", function()
    local session = session_at(PROMOTION)
    tap(session, "a7", "a8")
    local result = session:choosePromotion("q")
    eq(result.played, { from = sq("a7"), to = sq("a8"), promotion = "q" })
    eq(piece_on(session, "a8"), "Q"); eq(piece_on(session, "a7"), nil)
    eq(session:view().promotion, nil); eq(session:view().turn, "b")
end)

test("H07: choosing a piece with no promotion pending does nothing", function()
    local session = session_at()
    eq(session:choosePromotion("q"), { changed = false, needs_promotion = false })
    eq(session:view().turn, "w")
end)

-- Reset button: back to the usual start position, dropping the moves.

-- The game is the usual start position with no moves, and nothing is chosen or marked.
local function assert_start(session)
    eq(session.game:serialize(), { start = Rules.START_FEN, moves = {}, cursor = 0 })
    local view = session:view()
    eq(view.turn, "w"); eq(view.last_move, nil); eq(view.promotion, nil)
    eq(marked(session, "selected"), {}); eq(marked(session, "last_move"), {})
end

test("Reset: after some moves, back to the start position with no moves", function()
    local session = session_at()
    tap(session, "e2", "e4", "g8", "f6", "g1", "f3")
    eq(session:reset(), true)
    assert_start(session)
end)

test("Reset: a game from another position starts again from the usual one", function()
    local session = session_at(AFTER_E4_D5)
    eq(session:reset(), true)
    assert_start(session)
end)

test("Reset: moves ahead of the cursor go too", function()
    local session = session_at()
    tap(session, "e2", "e4")
    session.game:toStart()
    eq(session:reset(), true)
    eq(session.game:canForward(), false)
    assert_start(session)
end)

test("Reset: drops the selection and a pending promotion", function()
    local selected = session_at()
    tap(selected, "e2")
    eq(selected:reset(), true)
    assert_start(selected)
    local promoting = session_at(PROMOTION)
    tap(promoting, "a7", "a8")
    eq(promoting:reset(), true)
    assert_start(promoting)
end)

test("Reset: at the start position with no moves, nothing changes", function()
    local session = session_at()
    eq(session:reset(), false)
    assert_start(session)
end)
