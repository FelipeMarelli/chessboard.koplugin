-- What the reader does with the board and what has to be drawn for it: selecting a piece, moving
-- it with a second tap, and the marks that go with that.
local Editor = require("model/editor")
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

-- A piece letter ("k", "q", ...) in a color.
local function colored(letter, color)
    return color == "w" and letter:upper() or letter:lower()
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

-- The pieces a pawn can become, in the order lichess offers them.
local PROMOTION_PIECES = { "q", "n", "r", "b" }

-- A promotion waiting for its piece: the move, and the pieces to choose from in a column of
-- squares, from the one the pawn goes to towards the middle of the board.
local function pending_promotion(move, color)
    local file, rank = Rules.fileOf(move.to), Rules.rankOf(move.to)
    local toward_middle = rank == 8 and -1 or 1
    local choices = {}
    for i, letter in ipairs(PROMOTION_PIECES) do
        choices[i] = { square = Rules.square(file, rank + (i - 1) * toward_middle),
            piece = colored(letter, color) }
    end
    return { from = move.from, to = move.to, choices = choices }
end

-- The piece of the promotion offered on a square, if any.
local function choice_on(pending, sq)
    for _, choice in ipairs(pending.choices) do
        if choice.square == sq then
            return choice.piece:lower()
        end
    end
end

-- Editing the start position (see model/editor.lua). The color button chooses at once the color
-- of the pieces to put and the side to move, so the editor's turn is that color.

function Session:isEditing()
    return self.editor ~= nil
end

-- Starts editing from the position shown; the game is left as it is until editing ends.
function Session:startEdit()
    forget_choice(self)
    self.editor = Editor.new(self.game:position())
    return true
end

-- The trash of the editor: puts the usual start position, and on it, empties the board.
-- Returns whether it changed.
function Session:clearBoard()
    local editor = self.editor
    if editor:isStart() then
        return editor:clear()
    end
    return editor:setStart()
end

-- Switches the color of the pieces to put, which is also the side to move.
function Session:toggleColor()
    local editor = self.editor
    local color = editor:turn() == "w" and "b" or "w"
    editor:setTurn(color)
    local piece = editor:tool()
    if piece then
        editor:setTool(colored(piece, color))
    end
    return true
end

-- Chooses the piece to put: "k", "q", "r", "b", "n" or "p". Returns whether it changed.
function Session:choosePiece(letter)
    return self.editor:setTool(colored(letter, self.editor:turn()))
end

-- Ends editing: when the position was changed and is valid, the game starts from it; else the
-- game and its line stay as they were. False when there was nothing being edited.
function Session:finishEdit()
    local editor = self.editor
    if not editor then
        return false
    end
    self.editor = nil
    local position = editor:isChanged() and editor:result()
    if position then
        assert(self.game:reset(Rules.toFen(position)))
    end
    return true
end

-- A tap on a square of the board. It selects a piece of the side to move, plays the selected
-- one to a legal target, or clears the selection. A move that promotes waits for the piece:
-- meanwhile a tap on a piece offered completes it, and a tap anywhere else cancels it.
function Session:tapSquare(sq)
    if self.editor then
        return answer(self.editor:tapSquare(sq))
    end
    if self.pending then
        local letter = choice_on(self.pending, sq)
        if letter then
            return self:choosePromotion(letter)
        end
        return answer(self:cancelPromotion())
    end
    local move = move_to(self, sq)
    if move and move.promotion then
        clear_selection(self)
        self.pending = pending_promotion(move, Rules.turn(self.game:position()))
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

-- Drops a pending promotion: the pawn stays where it was and no move is played. Returns whether
-- there was one.
function Session:cancelPromotion()
    if not self.pending then
        return false
    end
    self.pending = nil
    return true
end

function Session:isPromoting()
    return self.pending ~= nil
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

-- The game's step for each way to go along the line.
local STEPS = { back = "back", forward = "forward", start = "toStart", ["end"] = "toEnd" }

-- Goes along the line: "back", "forward", "start" or "end". It drops the selection and a
-- pending promotion. Returns whether the position changed; at the end it goes towards, nothing
-- changes.
function Session:navigate(direction)
    local step = assert(STEPS[direction], "no such direction")
    if not self.game[step](self.game) then
        return false
    end
    forget_choice(self)
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
        return { square = Rules.squareName(pending.to), color = Rules.turn(position),
            choices = pending.choices }
    end
end

-- Each square of a position with its piece, whether it is a light one and no marks yet.
local function squares_of(position)
    local squares = {}
    for sq = 1, 64 do
        squares[sq] = { piece = Rules.pieceAt(position, sq), marks = {}, light = is_light(sq) }
    end
    return squares
end

-- The most moves the strip under the board can show: more than fit in the widest window.
local NOTATION_MOVES = 16

-- The last moves up to the position shown, for the strip under the board (see model/notation.lua),
-- with move numbers only when the game started from the usual position.
local function notation_of(game)
    return { moves = game:recentMoves(NOTATION_MOVES),
        numbered = game:startFen() == Rules.START_FEN }
end

-- While editing: the pieces put so far, the chosen color as the side to move, no marks and no
-- moves.
local function edit_view(self)
    local editor = self.editor
    local piece = editor:tool()
    return {
        squares = squares_of(editor:position()),
        turn = editor:turn(),
        status = "ongoing",
        flipped = self.is_flipped,
        edit = { color = editor:turn(), piece = piece and piece:lower() },
        notation = { moves = {}, numbered = false },
        buttons = {},
    }
end

-- What there is to draw: each square with its piece, its marks and whether it is a light one,
-- whose turn it is, how the game stands, its last move and the ones before it, and which buttons
-- can be used. While editing, see edit_view.
function Session:view()
    if self.editor then
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
        notation = notation_of(self.game),
        promotion = promotion_view(self.pending, position),
        flipped = self.is_flipped,
        buttons = { close = true, flip = true, reset = true,
            backward = self.game:canBack(), forward = self.game:canForward() },
    }
end

return Session
