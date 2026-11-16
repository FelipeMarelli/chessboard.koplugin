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

test("C2: close, flip and reset can always be used; at the start there is nowhere to go", function()
    eq(Session.new(assert(Game.new())):view().buttons, { close = true, flip = true, reset = true,
        backward = false, forward = false })
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

-- The pieces offered for a promotion, by square name.
local function offered(session)
    local list = {}
    for _, choice in ipairs(session:view().promotion.choices) do
        list[#list + 1] = Rules.squareName(choice.square) .. "=" .. choice.piece
    end
    return table.concat(list, " ")
end

test("H08 C1: a move that promotes waits for the piece, offered in a column from that square",
    function()
        local session = session_at(PROMOTION)
        eq(tap(session, "a7", "a8"), { changed = true, needs_promotion = true })
        eq(piece_on(session, "a7"), "P"); eq(piece_on(session, "a8"), nil)
        eq(session:isPromoting(), true)
        local view = session:view()
        eq({ view.promotion.square, view.promotion.color }, { "a8", "w" })
        eq(offered(session), "a8=Q a7=N a6=R a5=B")
        eq(marked(session, "selected"), {})
    end)

test("H08 C1: Black's pieces for Black, up from the first rank", function()
    local session = session_at("K7/8/8/8/8/8/3p4/7k b - - 0 1")
    tap(session, "d2", "d1")
    eq(offered(session), "d1=q d2=n d3=r d4=b")
end)

test("H08 C2, C5: tapping a piece offered plays the move with it", function()
    local session = session_at(PROMOTION)
    tap(session, "a7", "a8")
    local result = tap(session, "a6")
    eq(result.played, { from = sq("a7"), to = sq("a8"), promotion = "r" })
    eq(piece_on(session, "a8"), "R")
    eq(session:isPromoting(), false); eq(session:view().promotion, nil)
    eq(session:view().last_move.san, { text = "a8", promotion = "R", suffix = "+" })
end)

test("H08 C3: a tap anywhere else cancels: the pawn stays and no move is played", function()
    local session = session_at(PROMOTION)
    tap(session, "a7", "a8")
    eq(tap(session, "h1"), { changed = true, needs_promotion = false })
    eq(session:isPromoting(), false)
    eq(piece_on(session, "a7"), "P"); eq(session.game:serialize().moves, {})
    eq(session:cancelPromotion(), false)
end)

test("H08 C3: cancelling, from outside the board, says whether there was a promotion", function()
    local session = session_at(PROMOTION)
    eq(session:cancelPromotion(), false)
    tap(session, "a7", "a8")
    eq(session:cancelPromotion(), true)
    eq(piece_on(session, "a7"), "P")
end)

test("H08 C2: choosing the piece completes the promotion", function()
    local session = session_at(PROMOTION)
    tap(session, "a7", "a8")
    local result = session:choosePromotion("q")
    eq(result.played, { from = sq("a7"), to = sq("a8"), promotion = "q" })
    eq(piece_on(session, "a8"), "Q"); eq(piece_on(session, "a7"), nil)
    eq(session:view().promotion, nil); eq(session:view().turn, "b")
end)

test("H08: choosing a piece with no promotion pending does nothing", function()
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

-- Editing the start position

-- Chooses a piece and puts it on squares, by name.
local function put(session, letter, ...)
    session:choosePiece(letter)
    return tap(session, ...)
end

-- A session editing an empty board: on the start position, the trash empties it.
local function editing_empty()
    local session = session_at()
    session:startEdit()
    session:clearBoard()
    return session
end

-- A session with 1.e4 d5 played, gone back to the position after 1.e4.
local function back_after_e4()
    local session = session_at()
    tap(session, "e2", "e4", "d7", "d5")
    session:navigate("back")
    return session
end

-- Felipe, 16 November 2026: editing starts from the position shown, and the line is kept until
-- an edited position replaces it. Before, the editor started from the usual start position.
test("Edit: starts from the position shown, and the game is left as it is", function()
    local session = back_after_e4()
    eq(session:isEditing(), false)
    eq(session:startEdit(), true)
    eq(session:isEditing(), true)
    local view = session:view()
    eq(view.squares[sq("e4")].piece, "P"); eq(view.turn, "b")
    eq(view.edit, { color = "b" })
    eq(session.game:serialize().moves, { "e2e4", "d7d5" })
end)

test("Edit: unchanged, back keeps the line and the position shown", function()
    local session = back_after_e4()
    session:startEdit()
    session:toggleColor(); session:toggleColor()
    eq(session:finishEdit(), true)
    eq(session.game:serialize().moves, { "e2e4", "d7d5" })
    eq(session:view().squares[sq("d5")].piece, nil)
    eq(session:view().buttons.forward, true)
end)

test("Edit: the trash puts the start position, and on it empties the board", function()
    local session = back_after_e4()
    session:startEdit()
    eq(session:clearBoard(), true)
    eq(piece_on(session, "e2"), "P"); eq(session:view().turn, "w")
    eq(session:clearBoard(), true)
    eq(piece_on(session, "e1"), nil)
    eq(session:clearBoard(), true)
    eq(piece_on(session, "e1"), "K")
end)

test("Edit: the start position put with the trash starts a new game from it", function()
    local session = back_after_e4()
    session:startEdit()
    session:clearBoard()
    session:finishEdit()
    eq(session.game:serialize(), { start = Rules.START_FEN, moves = {}, cursor = 0 })
end)

test("Edit: clearing leaves the board empty", function()
    local view = editing_empty():view()
    for square = 1, 64 do
        eq(view.squares[square].piece, nil)
    end
end)

test("Edit: a tap puts the chosen piece in the chosen color, and without one does nothing",
    function()
        local session = editing_empty()
        eq(tap(session, "e1").changed, false)
        eq(put(session, "k", "e1").changed, true)
        eq(put(session, "k", "e1").changed, false)
        eq(session:view().edit, { color = "w", piece = "k" })
        session:toggleColor()
        put(session, "q", "e1")
        eq(piece_on(session, "e1"), "q")
        eq(session:view().edit, { color = "b", piece = "q" })
    end)

test("Edit: the color chosen when it ends is the side to move", function()
    local session = editing_empty()
    put(session, "k", "e1"); put(session, "p", "e2")
    session:toggleColor()
    put(session, "k", "e8")
    eq(session:view().turn, "b")
    session:toggleColor(); session:toggleColor()
    eq(session:finishEdit(), true)
    eq(session:isEditing(), false)
    eq(session.game:serialize().start, "4k3/8/8/8/8/8/4P3/4K3 b - - 0 1")
    eq(session:finishEdit(), false)
end)

test("Edit: the eraser empties squares, and switching the color keeps it", function()
    local session = session_at()
    session:startEdit()
    eq(session:chooseEraser(), true)
    eq(tap(session, "e2").changed, true)
    eq(piece_on(session, "e2"), nil)
    session:toggleColor()
    eq(session:view().edit, { color = "b", piece = "erase" })
    eq(tap(session, "e7").changed, true)
    eq(session:chooseEraser(), false)
end)

test("Edit: emptying the board keeps the chosen color", function()
    local session = session_at()
    session:startEdit()
    session:toggleColor()
    session:clearBoard()
    eq(piece_on(session, "e1"), nil)
    eq(session:view().turn, "b")
end)

test("Edit: an invalid position keeps the line it came from", function()
    local session = back_after_e4()
    session:startEdit()
    session:clearBoard(); session:clearBoard()
    put(session, "k", "e1")
    session:finishEdit()
    eq(session.game:serialize().moves, { "e2e4", "d7d5" })
end)

-- Felipe, 16 November 2026: castling is there when the king and the rook are on their start
-- squares. Before, an edit dropped every castling.
test("Edit: unchanged, the usual start position stays, castling included", function()
    local session = session_at()
    session:startEdit()
    session:finishEdit()
    eq(session.game:serialize().start, Rules.START_FEN)
end)

test("Edit: choosing a piece again changes nothing", function()
    local session = editing_empty()
    eq(session:choosePiece("q"), true)
    eq(session:choosePiece("q"), false)
end)

test("Edit: reset goes back to the usual start position after an edit", function()
    local session = editing_empty()
    put(session, "k", "a1")
    session:toggleColor()
    put(session, "k", "h8")
    session:finishEdit()
    eq(session.game:serialize().start, "7k/8/8/8/8/8/8/K7 b - - 0 1")
    eq(session:reset(), true)
    eq(session.game:serialize().start, Rules.START_FEN)
end)

-- Going along the line

local function can_go(session)
    local buttons = session:view().buttons
    return { backward = buttons.backward, forward = buttons.forward }
end

test("Line: back and forward step along the line, with the last move marked", function()
    local session = session_at()
    tap(session, "e2", "e4", "e7", "e5")
    eq(can_go(session), { backward = true, forward = false })
    eq(session:navigate("back"), true)
    eq(session:view().last_move.san.text, "e4")
    eq(marked(session, "last_move"), { "e2", "e4" })
    eq(can_go(session), { backward = true, forward = true })
    eq(session:navigate("back"), true)
    eq(session:view().last_move, nil)
    eq(can_go(session), { backward = false, forward = true })
    eq(session:navigate("forward"), true)
    eq(session:navigate("end"), true)
    eq(session:view().last_move.san.text, "e5")
    eq(session:navigate("start"), true)
    eq(session:view().last_move, nil)
end)

test("Line: at either end, going further changes nothing", function()
    local session = session_at()
    eq(session:navigate("back"), false)
    eq(session:navigate("forward"), false)
    tap(session, "e2", "e4")
    eq(session:navigate("forward"), false)
    eq(session:navigate("end"), false)
end)

test("Line: going drops the selection and a pending promotion", function()
    local session = session_at()
    tap(session, "e2", "e4", "d7")
    eq(session:navigate("back"), true)
    eq(marked(session, "selected"), {})
    local promoting = session_at(PROMOTION)
    tap(promoting, "h1", "h2", "a1", "b1", "a7", "a8")
    eq(promoting:navigate("back"), true)
    eq(promoting:view().promotion, nil)
end)

test("Line: a different move after going back replaces the rest of the line", function()
    local session = session_at()
    tap(session, "e2", "e4", "e7", "e5")
    session:navigate("back")
    tap(session, "c7", "c5")
    eq(can_go(session), { backward = true, forward = false })
    eq(session.game:serialize().moves, { "e2e4", "c7c5" })
end)

test("Line: the same move after going back keeps the rest of the line", function()
    local session = session_at()
    tap(session, "e2", "e4", "e7", "e5")
    session:navigate("start")
    tap(session, "e2", "e4")
    eq(can_go(session), { backward = true, forward = true })
    eq(session.game:serialize().moves, { "e2e4", "e7e5" })
end)

-- The moves for the strip under the board (H16)

-- The notation of the moves the view gives for the strip, as plain text.
local function strip_of(session)
    local list = {}
    for _, m in ipairs(session:view().notation.moves) do
        list[#list + 1] = (m.san.piece or "") .. m.san.text
    end
    return table.concat(list, " ")
end

-- Felipe, 16 November 2026: the strip keeps the whole line while going along it, the move on the
-- board marked. Before, it ended at the position shown.
test("H16 C1, C6: the strip has the line, and which move led to the position shown", function()
    local session = session_at()
    eq(strip_of(session), "")
    tap(session, "e2", "e4", "e7", "e5", "g1", "f3")
    eq(strip_of(session), "e4 e5 Nf3")
    eq(session:view().notation.current, 3)
    eq(session:view().notation.numbered, true)
    session:navigate("back")
    eq(strip_of(session), "e4 e5 Nf3")
    eq(session:view().notation.current, 2)
    session:navigate("start")
    eq(strip_of(session), "e4 e5 Nf3")
    eq(session:view().notation.current, 0)
    session:reset()
    eq(strip_of(session), "")
end)

test("H16 C1: a new move after going back drops the rest of the line from the strip", function()
    local session = session_at()
    tap(session, "e2", "e4", "e7", "e5", "g1", "f3")
    session:navigate("back")
    tap(session, "f1", "c4")
    eq(strip_of(session), "e4 e5 Bc4")
    eq(session:view().notation.current, 3)
end)

test("H16 C3: no move numbers in a game from an edited position", function()
    local session = editing_empty()
    put(session, "k", "e1")
    session:toggleColor()
    put(session, "k", "e8")
    session:toggleColor()
    session:finishEdit()
    tap(session, "e1", "e2")
    eq(strip_of(session), "Ke2")
    eq(session:view().notation.numbered, false)
end)

test("H16 C5: while editing the strip is empty", function()
    local session = session_at()
    tap(session, "e2", "e4")
    session:startEdit()
    eq(session:view().notation, { moves = {}, current = 0, numbered = false })
end)
