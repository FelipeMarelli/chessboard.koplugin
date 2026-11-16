-- What the reader does with the board and what has to be drawn for it: selecting a piece, moving
-- it with a second tap, and the marks that go with that.
local Rules = require("chess/rules")

local Session = {}
Session.__index = Session

function Session.new(game)
    return setmetatable({ game = game, is_flipped = false }, Session)
end

function Session:flip()
    self.is_flipped = not self.is_flipped
end

function Session:flipped()
    return self.is_flipped
end

local function select(self, sq, moves)
    self.selected, self.moves = sq, moves
end

local function clear_selection(self)
    select(self, nil, nil)
end

local function color_of(piece)
    return piece:match("%u") and "w" or "b"
end

-- The legal moves of the piece on a square, when it is one of the side to move and has any.
local function movable(position, sq)
    local piece = Rules.pieceAt(position, sq)
    if not piece or color_of(piece) ~= Rules.turn(position) then
        return nil
    end
    local moves = Rules.legalMovesFrom(position, sq)
    return #moves > 0 and moves or nil
end

-- The selected piece's move to a square, if it has one. A promotion has one move per piece; the
-- first stands for them all.
local function move_to(self, sq)
    for _, move in ipairs(self.moves or {}) do
        if move.to == sq then
            return move
        end
    end
end

-- What tapSquare and choosePromotion answer.
local function answer(changed, played, needs_promotion)
    return { changed = changed, played = played, needs_promotion = needs_promotion or false }
end

-- Drops the selected piece and the promotion waiting for its piece, if any.
local function forget_choice(self)
    clear_selection(self)
    self.pending = nil
end

local function play(self, move)
    forget_choice(self)
    assert(self.game:play(move))
    return answer(true, move)
end

-- Editing the start position. While it lasts a tap on a square puts the chosen piece there, in
-- the chosen color, and the game is left alone until finishEdit.

-- Puts the chosen piece on a square, if a piece is chosen.
local function place(self, sq)
    local edit = self.edit
    local piece = edit.piece and (edit.color == "w" and edit.piece:upper() or edit.piece)
    if not piece or edit.position.board[sq] == piece then
        return answer(false)
    end
    edit.position.board[sq] = piece
    return answer(true)
end

local EMPTY_FEN = "8/8/8/8/8/8/8/8 w - - 0 1"

-- A position to edit: the pieces of a FEN, a color to move, no castling and no en passant.
local function editable(fen, color)
    local position = assert(Rules.fromFen(fen))
    position.turn, position.castling, position.passant = color, "", nil
    position.halfmove, position.fullmove = 0, 1
    return position
end

function Session:isEditing()
    return self.edit ~= nil
end

-- Starts editing from the usual start position, which the game goes back to.
function Session:startEdit()
    forget_choice(self)
    assert(self.game:reset())
    self.edit = { position = editable(Rules.START_FEN, "w"), color = "w" }
    return true
end

-- Empties the board being edited.
function Session:clearBoard()
    self.edit.position = editable(EMPTY_FEN, self.edit.color)
    return answer(true)
end

-- Switches the color of the pieces to put, which is also the side to move.
function Session:toggleColor()
    local edit = self.edit
    edit.color = edit.color == "w" and "b" or "w"
    edit.position.turn = edit.color
    return answer(true)
end

-- Chooses the piece to put: "k", "q", "r", "b", "n" or "p".
function Session:choosePiece(letter)
    self.edit.piece = letter
    return answer(true)
end

-- Ends editing: the game starts from the edited position when it is valid, else from the usual
-- one. False when there was nothing being edited.
function Session:finishEdit()
    local edit = self.edit
    if not edit then
        return false
    end
    self.edit = nil
    if not self.game:reset(Rules.toFen(edit.position)) then
        assert(self.game:reset())
    end
    return true
end

-- A tap on a square of the board. It selects a piece of the side to move, plays the selected
-- one to a legal target, or clears the selection. A move that promotes waits for the piece: see
-- choosePromotion.
function Session:tapSquare(sq)
    if self.edit then
        return place(self, sq)
    end
    if self.pending then
        return answer(false)
    end
    local move = move_to(self, sq)
    if move and move.promotion then
        clear_selection(self)
        self.pending = { from = move.from, to = move.to }
        return answer(true, nil, true)
    elseif move then
        return play(self, move)
    end
    local moves = sq ~= self.selected and movable(self.game:position(), sq)
    if moves then
        select(self, sq, moves)
        return answer(true)
    elseif self.selected then
        clear_selection(self)
        return answer(true)
    end
    return answer(false)
end

-- Completes a pending promotion with a piece: "q", "r", "b" or "n".
function Session:choosePromotion(letter)
    local pending = self.pending
    if not pending then
        return answer(false)
    end
    return play(self, { from = pending.from, to = pending.to, promotion = letter })
end

-- True when a reset would change nothing: the usual start position, no moves, nothing chosen.
local function is_fresh(self)
    local saved = self.game:serialize()
    return saved.start == Rules.START_FEN and #saved.moves == 0 and not self.selected
        and not self.pending
end

-- Starts again from the usual start position, dropping every move, the selection and a pending
-- promotion. Returns whether anything changed.
function Session:reset()
    if is_fresh(self) then
        return false
    end
    forget_choice(self)
    assert(self.game:reset())
    return true
end

-- a1 is dark.
local function is_light(sq)
    return (Rules.fileOf(sq) + Rules.rankOf(sq)) % 2 == 1
end

-- En passant takes a pawn that is not on the target square.
local function is_capture(position, move)
    return Rules.pieceAt(position, move.to) ~= nil
        or (Rules.pieceAt(position, move.from):lower() == "p" and move.to == position.passant)
end

local function mark(squares, sq, name)
    squares[sq].marks[name] = true
end

local function mark_selection(squares, position, selected, moves)
    if not selected then
        return
    end
    mark(squares, selected, "selected")
    for _, move in ipairs(moves) do
        mark(squares, move.to, is_capture(position, move) and "capture" or "target")
    end
end

local function mark_last_move(squares, last)
    if last then
        mark(squares, last.move.from, "last_move")
        mark(squares, last.move.to, "last_move")
    end
end

local function mark_check(squares, position)
    if Rules.isCheck(position) then
        mark(squares, Rules.kingSquare(position, Rules.turn(position)), "check")
    end
end

local function promotion_view(pending, position)
    if pending then
        return { square = Rules.squareName(pending.to), color = Rules.turn(position) }
    end
end

-- What there is to draw: each square with its piece, its marks and whether it is a light one,
-- whose turn it is, how the game stands, its last move, and which buttons can be used.
local function squares_of(position)
    local squares = {}
    for sq = 1, 64 do
        squares[sq] = { piece = Rules.pieceAt(position, sq), marks = {}, light = is_light(sq) }
    end
    return squares
end

-- While editing: the pieces put so far, the chosen color as the side to move, and no marks.
local function edit_view(self)
    local edit = self.edit
    return {
        squares = squares_of(edit.position),
        turn = edit.color,
        status = "ongoing",
        flipped = self.is_flipped,
        edit = { color = edit.color, piece = edit.piece },
        buttons = {},
    }
end

-- What there is to draw: each square with its piece, its marks and whether it is a light one,
-- whose turn it is, how the game stands, its last move, and which buttons can be used. While
-- editing, see edit_view.
function Session:view()
    if self.edit then
        return edit_view(self)
    end
    local position = self.game:position()
    local last_move = self.game:lastMove()
    local squares = squares_of(position)
    mark_last_move(squares, last_move)
    mark_check(squares, position)
    mark_selection(squares, position, self.selected, self.moves)
    return {
        squares = squares,
        turn = Rules.turn(position),
        status = Rules.status(position),
        last_move = last_move,
        promotion = promotion_view(self.pending, position),
        flipped = self.is_flipped,
        buttons = { close = true, flip = true, reset = true },
    }
end

return Session
