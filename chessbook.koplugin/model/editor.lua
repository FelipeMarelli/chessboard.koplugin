-- Setting up a position by hand: a board to put pieces on, the piece to put and the side to move.
-- Nothing is checked until result.
local Rules = require("chess/rules")

local Editor = {}
Editor.__index = Editor

-- Each castling right, with the squares its king and rook start on.
local CASTLINGS = {
    { right = "K", king = "e1", rook = "h1" },
    { right = "Q", king = "e1", rook = "a1" },
    { right = "k", king = "e8", rook = "h8" },
    { right = "q", king = "e8", rook = "a8" },
}

-- The castling rights the pieces allow: those whose king and rook are on their start squares.
local function castling_of(board)
    local rights = {}
    for _, c in ipairs(CASTLINGS) do
        local white = c.right:match("%u") ~= nil
        if board[Rules.squareFromName(c.king)] == (white and "K" or "k")
            and board[Rules.squareFromName(c.rook)] == (white and "R" or "r") then
            rights[#rights + 1] = c.right
        end
    end
    return table.concat(rights)
end

local function copy(board)
    local new = {}
    for sq, piece in pairs(board) do
        new[sq] = piece
    end
    return new
end

-- Whether two boards have the same pieces on the same squares.
local function same_board(a, b)
    for sq = 1, 64 do
        if a[sq] ~= b[sq] then
            return false
        end
    end
    return true
end

local START_BOARD = assert(Rules.fromFen(Rules.START_FEN)).board

-- Edits the pieces of a position and its side to move; the rest of it is left behind.
function Editor.new(position)
    return setmetatable({
        board = copy(position.board),
        side = position.turn,
        entry = { board = copy(position.board), side = position.turn },
    }, Editor)
end

-- Whether the pieces or the side to move differ from the position the editor started with.
function Editor:isChanged()
    return self.side ~= self.entry.side or not same_board(self.board, self.entry.board)
end

-- Whether the board has the pieces of the usual start position.
function Editor:isStart()
    return same_board(self.board, START_BOARD)
end

-- Puts the pieces of the usual start position, White to move. Returns whether it changed.
function Editor:setStart()
    if self:isStart() and self.side == "w" then
        return false
    end
    self.board = copy(START_BOARD)
    self.side = "w"
    return true
end

-- Chooses the piece to put, a FEN letter ("K", "q", ...), or none. Returns whether it changed.
function Editor:setTool(letter)
    if self.piece == letter then
        return false
    end
    self.piece = letter
    return true
end

function Editor:tool()
    return self.piece
end

-- Puts the chosen piece on a square. Returns whether the board changed.
function Editor:tapSquare(sq)
    if not self.piece or self.board[sq] == self.piece then
        return false
    end
    self.board[sq] = self.piece
    return true
end

-- Empties the board. Returns whether it changed.
function Editor:clear()
    if next(self.board) == nil then
        return false
    end
    self.board = {}
    return true
end

-- Sets the side to move, "w" or "b". Returns whether it changed.
function Editor:setTurn(color)
    if self.side == color then
        return false
    end
    self.side = color
    return true
end

function Editor:turn()
    return self.side
end

-- The position being set up, to draw it: the castling rights and the move number are not in it.
function Editor:position()
    return { board = self.board, turn = self.side, castling = "", halfmove = 0, fullmove = 1 }
end

-- The position set up, ready to start a game from: no en passant, move 1, and every castling the
-- pieces allow. Nil and why when it cannot be played (see Rules.validate).
function Editor:result()
    local position = self:position()
    position.board = copy(self.board)
    position.castling = castling_of(self.board)
    local ok, reason = Rules.validate(position)
    if not ok then
        return nil, reason
    end
    return position
end

return Editor
