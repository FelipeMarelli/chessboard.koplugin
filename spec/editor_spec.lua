-- Setting up a position by hand (model/editor.lua).
local Editor = require("model/editor")
local Helper = require("helper")
local Rules = require("chess/rules")
local eq, test = Helper.eq, Helper.test

local sq = Rules.squareFromName

local function editor_of(fen)
    return Editor.new(assert(Rules.fromFen(fen or Rules.START_FEN)))
end

-- The FEN of what the editor sets up, or nil and why.
local function result_fen(editor)
    local position, reason = editor:result()
    return position and Rules.toFen(position), reason
end

-- Chooses a piece and puts it on squares, by name: put(editor, "K", "e1").
local function put(editor, letter, ...)
    editor:setTool(letter)
    for _, name in ipairs({ ... }) do
        editor:tapSquare(sq(name))
    end
end

test("Editor: starts with the pieces and the side to move of a position", function()
    local editor = editor_of("4k3/8/8/8/8/8/4P3/4K3 b - - 0 7")
    eq(editor:turn(), "b")
    eq(editor:position().board[sq("e2")], "P")
    eq(editor:tool(), nil)
end)

test("Editor: does not change the position it started from", function()
    local position = assert(Rules.fromFen(Rules.START_FEN))
    local editor = Editor.new(position)
    editor:clear()
    eq(position.board[sq("e1")], "K")
end)

test("Editor: a tap puts the chosen piece, and without one, or on the same piece, does nothing",
    function()
        local editor = editor_of()
        eq(editor:tapSquare(sq("e4")), false)
        eq(editor:setTool("q"), true)
        eq(editor:setTool("q"), false)
        eq(editor:tool(), "q")
        eq(editor:tapSquare(sq("e1")), true)
        eq(editor:position().board[sq("e1")], "q")
        eq(editor:tapSquare(sq("e1")), false)
    end)

test("Editor: clearing empties the board, and an empty one does not change", function()
    local editor = editor_of()
    eq(editor:clear(), true)
    eq(next(editor:position().board), nil)
    eq(editor:clear(), false)
end)

test("Editor: the side to move", function()
    local editor = editor_of()
    eq(editor:setTurn("w"), false)
    eq(editor:setTurn("b"), true)
    eq(editor:turn(), "b")
    eq(editor:position().turn, "b")
end)

test("Editor: the result has no en passant and starts at move 1", function()
    local editor = editor_of("rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3")
    eq(result_fen(editor), "rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1")
end)

test("Editor: castling is there when the king and the rook are on their start squares",
    function()
        local editor = editor_of()
        editor:clear()
        put(editor, "K", "e1"); put(editor, "R", "a1", "h1")
        put(editor, "k", "e8"); put(editor, "r", "h8")
        eq(result_fen(editor), "4k2r/8/8/8/8/8/8/R3K2R w KQk - 0 1")
        put(editor, "K", "f1"); put(editor, "N", "e1")
        put(editor, "r", "a8")
        eq(result_fen(editor), "r3k2r/8/8/8/8/8/8/R3NK1R w kq - 0 1")
    end)

test("Editor: a rook of the other color on the corner gives no castling", function()
    local editor = editor_of()
    editor:clear()
    put(editor, "K", "e1"); put(editor, "r", "h1"); put(editor, "k", "e8")
    eq(result_fen(editor), "4k3/8/8/8/8/8/8/4K2r w - - 0 1")
end)

test("Editor: a position that cannot be played gives no result, and why", function()
    local editor = editor_of()
    editor:clear()
    put(editor, "K", "e1")
    local fen, reason = result_fen(editor)
    eq(fen, nil)
    eq(reason, "Place exactly one king of each color.")
end)
