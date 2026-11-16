-- Rules of chess: positions, legal moves, FEN and notation. Squares are numbers, 1 (a1) to 64 (h8).
--
-- Derived from ink_knight/chess.lua of Ink Knight, commit 601acd2a3a3e24148e442e10fd806accd6002782,
-- https://github.com/beater-studios/ink_knight.koplugin
-- Copyright (C) 2026 Beater Studios
--
-- Modified for chessboard.koplugin in November 2026: names and signatures follow the contract in
-- AGENTS.md; FEN is read strictly and keeps the move number; notation hands the piece
-- letter apart so a figurine can replace it; moves are checked before they are applied; positions
-- can be validated; the helpers tied to Ink Knight's games and screens were removed.
--
-- Unlike the rest of the plugin (AGPL-3.0), this file is licensed under the GNU General Public
-- License, version 3 only: see LICENSE-GPL-3.0 in this folder. Section 13 of both licenses allows
-- combining them. As an additional term under section 7(e), the license grants no rights under
-- trademark law to the names "Ink Knight" and "Beater Studios".

local Rules = {}

Rules.START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

local KNIGHT = {
    { 1, 2 }, { 2, 1 }, { 2, -1 }, { 1, -2 }, { -1, -2 }, { -2, -1 }, { -2, 1 }, { -1, 2 },
}
local KING = {
    { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 },
}
local ROOK = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local BISHOP = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
local QUEEN = {
    { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
}
local PROMOTIONS = { "q", "r", "b", "n" }
-- Half moves without a capture or a pawn move after which the fifty-move rule applies.
local FIFTY_MOVE_HALFMOVES = 100

local function index(file, rank)
    return (rank - 1) * 8 + file
end

local function file_of(square)
    return (square - 1) % 8 + 1
end

local function rank_of(square)
    return math.floor((square - 1) / 8) + 1
end

local function on_board(file, rank)
    return file >= 1 and file <= 8 and rank >= 1 and rank <= 8
end

local function is_white(piece)
    return piece == piece:upper()
end

-- The square of a file and a rank, both from 1 to 8, or nil off the board.
function Rules.square(file, rank)
    if on_board(file, rank) then
        return index(file, rank)
    end
    return nil
end

Rules.fileOf = file_of
Rules.rankOf = rank_of

function Rules.squareName(square)
    return string.char(96 + file_of(square)) .. rank_of(square)
end

function Rules.squareFromName(name)
    local file, rank = tostring(name):match("^([a-h])([1-8])$")
    if not file then
        return nil
    end
    return index(file:byte() - 96, tonumber(rank))
end

-- The castling of a position is "KQkq" in standard chess. In Chess960 each right is the file of
-- its rook, upper case for white ("HFhf", as Shredder writes it), and the position has chess960
-- set, which every move keeps.
-- chess960: read the FEN as Chess960, where "KQkq" (X-FEN, as Lichess writes it) means the
-- outermost rook on each side of the king, and a right with no king or rook to stand for is
-- dropped. Without it only a FEN with files is Chess960, so a standard FEN written loosely keeps
-- the rights it had.
local function chess960_castling(board, castling, chess960)
    local letters = {}
    for letter in castling:gmatch(".") do
        local white = letter == letter:upper()
        local rank = white and 1 or 8
        local upper = letter:upper()
        if (upper == "K" or upper == "Q") and not chess960 then
            letters[#letters + 1] = letter
        elseif upper == "K" or upper == "Q" then
            local king_file
            for file = 1, 8 do
                if board[index(file, rank)] == (white and "K" or "k") then
                    king_file = file
                end
            end
            local rook = white and "R" or "r"
            local step = upper == "K" and -1 or 1
            for file = upper == "K" and 8 or 1, king_file or (upper == "K" and 9 or 0), step do
                if board[index(file, rank)] == rook then
                    local name = string.char(64 + file)
                    letters[#letters + 1] = white and name or name:lower()
                    break
                end
            end
        else
            letters[#letters + 1] = letter
        end
    end
    local result = table.concat(letters)
    return result, chess960 or result:find("[A-Ha-h]") ~= nil
end

-- The pieces of the first field of a FEN, or nil and why it is wrong. Every rank must have
-- exactly eight squares, and two digits in a row are refused.
local function parse_placement(placement)
    local rows = {}
    for row in (placement .. "/"):gmatch("([^/]*)/") do
        rows[#rows + 1] = row
    end
    if #rows ~= 8 then
        return nil, "invalid FEN: the board must have 8 ranks"
    end
    local board = {}
    for row_index, row in ipairs(rows) do
        local rank, file, after_digit = 9 - row_index, 1, false
        for char in row:gmatch(".") do
            if char:match("^[1-8]$") and not after_digit then
                file, after_digit = file + tonumber(char), true
            elseif char:match("^[prnbqkPRNBQK]$") and file <= 8 then
                board[index(file, rank)] = char
                file, after_digit = file + 1, false
            else
                return nil, "invalid FEN: wrong rank " .. rank
            end
        end
        if file ~= 9 then
            return nil, "invalid FEN: rank " .. rank .. " must have 8 squares"
        end
    end
    return board
end

-- Reads a FEN. The last two fields (half moves since a capture or a pawn move, and move number)
-- may be left out, as in an EPD; they then count as 0 and 1.
function Rules.fromFen(fen, chess960)
    if type(fen) ~= "string" then
        return nil, "invalid FEN: not a text"
    end
    local fields = {}
    for field in fen:gmatch("%S+") do
        fields[#fields + 1] = field
    end
    if #fields < 4 or #fields > 6 then
        return nil, "invalid FEN: it must have 4 to 6 fields"
    end
    local placement, turn, castling, passant, halfmove, fullmove = unpack(fields)
    local board, err = parse_placement(placement)
    if not board then
        return nil, err
    end
    if turn ~= "w" and turn ~= "b" then
        return nil, "invalid FEN: the side to move must be w or b"
    end
    if castling ~= "-" and not castling:match("^[KQkqA-Ha-h]+$") then
        return nil, "invalid FEN: wrong castling rights"
    end
    if passant ~= "-" and not passant:match("^[a-h][36]$") then
        return nil, "invalid FEN: wrong en passant square"
    end
    if halfmove and not halfmove:match("^%d+$") then
        return nil, "invalid FEN: wrong half move count"
    end
    if fullmove and not (fullmove:match("^%d+$") and tonumber(fullmove) >= 1) then
        return nil, "invalid FEN: wrong move number"
    end
    local rights, is_960 = chess960_castling(board, castling == "-" and "" or castling, chess960)
    return {
        board = board,
        turn = turn,
        castling = rights,
        chess960 = is_960 or nil,
        passant = passant ~= "-" and Rules.squareFromName(passant) or nil,
        halfmove = tonumber(halfmove or "0"),
        fullmove = tonumber(fullmove or "1"),
    }
end

function Rules.toFen(position)
    local rows = {}
    for rank = 8, 1, -1 do
        local row, empty = {}, 0
        for file = 1, 8 do
            local piece = position.board[index(file, rank)]
            if piece then
                if empty > 0 then
                    row[#row + 1] = tostring(empty)
                    empty = 0
                end
                row[#row + 1] = piece
            else
                empty = empty + 1
            end
        end
        if empty > 0 then
            row[#row + 1] = tostring(empty)
        end
        rows[#rows + 1] = table.concat(row)
    end
    return string.format("%s %s %s %s %d %d", table.concat(rows, "/"), position.turn,
        position.castling ~= "" and position.castling or "-",
        position.passant and Rules.squareName(position.passant) or "-",
        position.halfmove, position.fullmove)
end

function Rules.pieceAt(position, square)
    return position.board[square]
end

function Rules.turn(position)
    return position.turn
end

local function find_king(position, white)
    local king = white and "K" or "k"
    for square = 1, 64 do
        if position.board[square] == king then
            return square
        end
    end
    return nil
end

-- The square of the king of a color ("w" or "b"), or nil when it has none.
function Rules.kingSquare(position, color)
    return find_king(position, color == "w")
end

-- Whether a slider of either kind sits at the end of one of these rays. It lives out here, and
-- not inside is_attacked, because making a function on each call allocates and keeps LuaJIT from
-- compiling the hot path.
local function slides(board, file, rank, steps, first, second)
    for i = 1, #steps do
        local step = steps[i]
        local df, dr = step[1], step[2]
        local f, r = file + df, rank + dr
        while f >= 1 and f <= 8 and r >= 1 and r <= 8 do
            local piece = board[(r - 1) * 8 + f]
            if piece then
                if piece == first or piece == second then
                    return true
                end
                break
            end
            f, r = f + df, r + dr
        end
    end
    return false
end

local function jumps(board, file, rank, steps, piece)
    for i = 1, #steps do
        local step = steps[i]
        local f, r = file + step[1], rank + step[2]
        if f >= 1 and f <= 8 and r >= 1 and r <= 8 and board[(r - 1) * 8 + f] == piece then
            return true
        end
    end
    return false
end

-- Whether a side attacks a square, walking out from the square to where its pieces would be.
local function is_attacked(position, square, by_white)
    local board = position.board
    local file, rank = file_of(square), rank_of(square)
    local from_rank = rank + (by_white and -1 or 1)
    if from_rank >= 1 and from_rank <= 8 then
        local pawn = by_white and "P" or "p"
        if (file > 1 and board[index(file - 1, from_rank)] == pawn)
            or (file < 8 and board[index(file + 1, from_rank)] == pawn) then
            return true
        end
    end
    if jumps(board, file, rank, KNIGHT, by_white and "N" or "n")
        or jumps(board, file, rank, KING, by_white and "K" or "k") then
        return true
    end
    local queen = by_white and "Q" or "q"
    return slides(board, file, rank, ROOK, by_white and "R" or "r", queen)
        or slides(board, file, rank, BISHOP, by_white and "B" or "b", queen)
end

local function in_check(position, white)
    local king = find_king(position, white)
    return king ~= nil and is_attacked(position, king, not white)
end

-- Whether the side to move is in check.
function Rules.isCheck(position)
    return in_check(position, position.turn == "w")
end

local function copy(position)
    local board = {}
    for square, piece in pairs(position.board) do
        board[square] = piece
    end
    return {
        board = board,
        turn = position.turn,
        castling = position.castling,
        chess960 = position.chess960,
        passant = position.passant,
        halfmove = position.halfmove,
        fullmove = position.fullmove,
    }
end

local function drop_castling(castling, letters)
    return (castling:gsub("[" .. letters .. "]", ""))
end

-- The square of the rook a castling right is for.
local function rook_square_of(letter)
    local white = letter == letter:upper()
    local rank = white and 1 or 8
    local upper = letter:upper()
    local file = upper == "K" and 8 or (upper == "Q" and 1 or upper:byte() - 64)
    return index(file, rank)
end

-- Plays a move on a copy, without checking that it is legal.
local function play(position, move)
    local next_position = copy(position)
    local board = next_position.board
    local piece = board[move.from]
    local white = is_white(piece)
    local kind = piece:lower()
    next_position.halfmove = (kind == "p" or board[move.to]) and 0 or position.halfmove + 1
    if move.castle then
        -- The king and the rook leave, then land on their squares, which may be where the other
        -- one stood.
        local rank = rank_of(move.from)
        local rook = board[move.castle]
        board[move.from], board[move.castle] = nil, nil
        board[move.to] = piece
        board[index(file_of(move.to) == 7 and 6 or 4, rank)] = rook
        next_position.halfmove = position.halfmove + 1
    else
        board[move.from] = nil
        if kind == "p" and move.to == position.passant then
            board[index(file_of(move.to), rank_of(move.from))] = nil
        end
        board[move.to] = move.promotion
            and (white and move.promotion:upper() or move.promotion) or piece
    end
    -- The square passed over only counts when an enemy pawn stands beside the one that moved, as
    -- in a FEN from Lichess, so the same position does not look different the first time.
    next_position.passant = nil
    if kind == "p" and math.abs(rank_of(move.to) - rank_of(move.from)) == 2 then
        local file, rank = file_of(move.to), rank_of(move.to)
        local enemy = white and "p" or "P"
        if (file > 1 and board[index(file - 1, rank)] == enemy)
            or (file < 8 and board[index(file + 1, rank)] == enemy) then
            next_position.passant = index(file, (rank_of(move.from) + rank) / 2)
        end
    end
    if kind == "k" then
        next_position.castling = drop_castling(next_position.castling, white and "KQA-H" or "kqa-h")
    end
    -- A rook that moves or is taken ends the castling with it.
    for letter in next_position.castling:gmatch(".") do
        local square = rook_square_of(letter)
        if square == move.from or square == move.to then
            next_position.castling = drop_castling(next_position.castling, letter)
        end
    end
    next_position.turn = white and "b" or "w"
    next_position.fullmove = position.fullmove + (white and 0 or 1)
    return next_position
end

-- Out here rather than inside pseudo_moves, for the same reason as slides.
local function add_move(board, list, from, to)
    local piece = board[from]
    if (piece == "p" or piece == "P") and (to <= 8 or to > 56) then
        for _, promotion in ipairs(PROMOTIONS) do
            list[#list + 1] = { from = from, to = to, promotion = promotion }
        end
    else
        list[#list + 1] = { from = from, to = to }
    end
end

local function pawn_moves(position, list, square, white)
    local board = position.board
    local file, rank = file_of(square), rank_of(square)
    local forward = white and 1 or -1
    local one = rank + forward
    if on_board(file, one) and not board[index(file, one)] then
        add_move(board, list, square, index(file, one))
        local start = white and 2 or 7
        if rank == start and not board[index(file, one + forward)] then
            add_move(board, list, square, index(file, one + forward))
        end
    end
    for df = -1, 1, 2 do
        if on_board(file + df, one) then
            local target = index(file + df, one)
            local other = board[target]
            if (other and is_white(other) ~= white) or target == position.passant then
                add_move(board, list, square, target)
            end
        end
    end
end

local function step_moves(board, list, square, white, steps)
    local file, rank = file_of(square), rank_of(square)
    for _, step in ipairs(steps) do
        if on_board(file + step[1], rank + step[2]) then
            local target = index(file + step[1], rank + step[2])
            local other = board[target]
            if not other or is_white(other) ~= white then
                add_move(board, list, square, target)
            end
        end
    end
end

local function slide_moves(board, list, square, white, steps)
    local file, rank = file_of(square), rank_of(square)
    for _, step in ipairs(steps) do
        local f, r = file + step[1], rank + step[2]
        while on_board(f, r) do
            local target = index(f, r)
            local other = board[target]
            if not other then
                add_move(board, list, square, target)
            else
                if is_white(other) ~= white then
                    add_move(board, list, square, target)
                end
                break
            end
            f, r = f + step[1], r + step[2]
        end
    end
end

-- Castling, from wherever king and rook stand, as Chess960 has it: the king lands on g or c and
-- the rook on f or d, every square they cross or land on is empty but for the two of them, and the
-- king does not start or cross under attack (landing is checked with the other moves). Standard
-- chess is the case of e, a and h.
local function castling_moves(position, list, white)
    local board = position.board
    local rank = white and 1 or 8
    local king, rook = white and "K" or "k", white and "R" or "r"
    local king_square
    for file = 1, 8 do
        if board[index(file, rank)] == king then
            king_square = index(file, rank)
        end
    end
    if not king_square or position.castling == ""
        or is_attacked(position, king_square, not white) then
        return
    end
    for letter in position.castling:gmatch(".") do
        local rook_square = rook_square_of(letter)
        if (letter == letter:upper()) == white and board[rook_square] == rook then
            local king_side = file_of(rook_square) > file_of(king_square)
            local king_to = index(king_side and 7 or 3, rank)
            local rook_to = index(king_side and 6 or 4, rank)
            local low = math.min(file_of(king_square), file_of(rook_square),
                file_of(king_to), file_of(rook_to))
            local high = math.max(file_of(king_square), file_of(rook_square),
                file_of(king_to), file_of(rook_to))
            local free = true
            for file = low, high do
                local square = index(file, rank)
                if board[square] and square ~= king_square and square ~= rook_square then
                    free = false
                end
            end
            local step = file_of(king_to) >= file_of(king_square) and 1 or -1
            for file = file_of(king_square) + step, file_of(king_to) - step, step do
                if free and is_attacked(position, index(file, rank), not white) then
                    free = false
                end
            end
            if free then
                list[#list + 1] = { from = king_square, to = king_to, castle = rook_square }
            end
        end
    end
end

local function pseudo_moves(position, list)
    local board = position.board
    local white = position.turn == "w"
    for square = 1, 64 do
        local piece = board[square]
        if piece and is_white(piece) == white then
            local kind = piece:lower()
            if kind == "p" then
                pawn_moves(position, list, square, white)
            elseif kind == "n" then
                step_moves(board, list, square, white, KNIGHT)
            elseif kind == "k" then
                step_moves(board, list, square, white, KING)
            else
                local steps = kind == "q" and QUEEN or (kind == "r" and ROOK or BISHOP)
                slide_moves(board, list, square, white, steps)
            end
        end
    end
    castling_moves(position, list, white)
    return list
end

-- Every legal move of the side to move. A castling carries `castle`, the square of its rook.
function Rules.legalMoves(position)
    local legal = {}
    local white = position.turn == "w"
    for _, move in ipairs(pseudo_moves(position, {})) do
        if not in_check(play(position, move), white) then
            legal[#legal + 1] = move
        end
    end
    return legal
end

function Rules.legalMovesFrom(position, square)
    local moves = {}
    for _, move in ipairs(Rules.legalMoves(position)) do
        if move.from == square then
            moves[#moves + 1] = move
        end
    end
    return moves
end

-- The legal move that a move given as { from, to, promotion } stands for, or nil and why.
-- In Chess960 a castling and a plain king move may share both squares, so there `castle` decides.
local function find_legal(position, move)
    if type(move) ~= "table" or type(move.from) ~= "number" or type(move.to) ~= "number" then
        return nil, "invalid move"
    end
    for _, legal in ipairs(Rules.legalMoves(position)) do
        if legal.from == move.from and legal.to == move.to and legal.promotion == move.promotion
            and (not position.chess960 or (legal.castle ~= nil) == (move.castle ~= nil)) then
            return legal
        end
    end
    return nil, "illegal move"
end

-- The position after a legal move, and the move as the rules know it (with `castle` when it is
-- a castling). The position given is not changed.
function Rules.apply(position, move)
    local legal, err = find_legal(position, move)
    if not legal then
        return nil, err
    end
    return play(position, legal), legal
end

-- "ongoing", "checkmate" or "stalemate".
function Rules.status(position)
    if #Rules.legalMoves(position) > 0 then
        return "ongoing"
    end
    return Rules.isCheck(position) and "checkmate" or "stalemate"
end

-- No side can give mate: kings alone, or kings and a single bishop or knight.
local function insufficient_material(position)
    local minors = 0
    for _, piece in pairs(position.board) do
        local kind = piece:lower()
        if kind == "b" or kind == "n" then
            minors = minors + 1
        elseif kind ~= "k" then
            return false
        end
    end
    return minors <= 1
end

-- What the rules say about a position: nil while it goes on, otherwise "checkmate", "stalemate",
-- "insufficient" (material) or "fifty" (the fifty-move rule).
function Rules.ending(position)
    local status = Rules.status(position)
    if status ~= "ongoing" then
        return status
    end
    if insufficient_material(position) then
        return "insufficient"
    end
    if position.halfmove >= FIFTY_MOVE_HALFMOVES then
        return "fifty"
    end
    return nil
end

-- A legal move in the usual notation, in parts: `piece` is the FEN letter of the piece that moves
-- (nil for a pawn or a castling), so the screen can draw a figurine in its place; `text` is the
-- rest ("bd7", "exd5", "O-O"); `promotion` is the FEN letter of the new piece, written after "=";
-- `suffix` is "+", "#" or "". Returns nil and why for a move that is not legal.
function Rules.san(position, move)
    local legal, err = find_legal(position, move)
    if not legal then
        return nil, err
    end
    move = legal
    local piece = position.board[move.from]
    local kind = piece:lower()
    local parts = { suffix = "" }
    if move.castle then
        parts.text = file_of(move.to) == 7 and "O-O" or "O-O-O"
    else
        local to = Rules.squareName(move.to)
        local takes = position.board[move.to] ~= nil
            or (kind == "p" and move.to == position.passant)
        if kind == "p" then
            parts.text = (takes and (Rules.squareName(move.from):sub(1, 1) .. "x") or "") .. to
            if move.promotion then
                parts.promotion = is_white(piece) and move.promotion:upper() or move.promotion
            end
        else
            local same_file, same_rank, other = false, false, false
            for _, candidate in ipairs(Rules.legalMoves(position)) do
                if candidate.to == move.to and candidate.from ~= move.from
                    and position.board[candidate.from] == piece and not candidate.castle then
                    other = true
                    same_file = same_file or file_of(candidate.from) == file_of(move.from)
                    same_rank = same_rank or rank_of(candidate.from) == rank_of(move.from)
                end
            end
            local origin = Rules.squareName(move.from)
            local hint = ""
            if other then
                if not same_file then
                    hint = origin:sub(1, 1)
                elseif not same_rank then
                    hint = origin:sub(2, 2)
                else
                    hint = origin
                end
            end
            parts.piece = piece
            parts.text = hint .. (takes and "x" or "") .. to
        end
    end
    local after = play(position, move)
    if Rules.isCheck(after) then
        parts.suffix = Rules.status(after) == "checkmate" and "#" or "+"
    end
    return parts
end

-- The usual notation in one English text, such as "Nbd7", "exd5", "O-O" or "e8=Q+".
function Rules.sanText(position, move)
    local parts, err = Rules.san(position, move)
    if not parts then
        return nil, err
    end
    return (parts.piece and parts.piece:upper() or "") .. parts.text
        .. (parts.promotion and ("=" .. parts.promotion:upper()) or "") .. parts.suffix
end

-- A move in UCI notation ("e2e4", "e7e8q"). A castling of Chess960 goes as the king taking its
-- own rook, the only way Lichess reads it there.
function Rules.moveToUci(move, position)
    local chess960 = position and position.chess960
    local to = (move.castle and chess960) and move.castle or move.to
    return Rules.squareName(move.from) .. Rules.squareName(to) .. (move.promotion or "")
end

-- Reads a move in UCI notation, without checking it against the rules, or nil. Castling may be
-- written as the king going two squares or as the king taking its own rook.
function Rules.parseUci(position, uci)
    local from, to, promotion = tostring(uci):match("^([a-h][1-8])([a-h][1-8])([qrbn]?)$")
    if not from then
        return nil
    end
    from, to = Rules.squareFromName(from), Rules.squareFromName(to)
    local piece = position.board[from]
    local is_king = piece and piece:lower() == "k"
    if is_king and position.board[to] and is_white(position.board[to]) == is_white(piece) then
        local king_to = index(file_of(to) > file_of(from) and 7 or 3, rank_of(from))
        return { from = from, to = king_to, castle = to }
    end
    if is_king and not position.chess960 and rank_of(to) == rank_of(from)
        and math.abs(file_of(to) - file_of(from)) == 2 then
        local rook = index(file_of(to) > file_of(from) and 8 or 1, rank_of(from))
        return { from = from, to = to, castle = rook }
    end
    return { from = from, to = to, promotion = promotion ~= "" and promotion or nil }
end

-- Whether a position set up by hand can be played: true, or nil and the reason, in English for
-- the translation catalogue.
function Rules.validate(position)
    local kings = { K = 0, k = 0 }
    for square = 1, 64 do
        local piece = position.board[square]
        if piece == "K" or piece == "k" then
            kings[piece] = kings[piece] + 1
        end
    end
    if kings.K ~= 1 or kings.k ~= 1 then
        return nil, "Place exactly one king of each color."
    end
    for square = 1, 64 do
        local piece = position.board[square]
        local rank = rank_of(square)
        if (piece == "P" or piece == "p") and (rank == 1 or rank == 8) then
            return nil, "Move the pawns off the first and last ranks."
        end
    end
    if in_check(position, position.turn ~= "w") then
        return nil, "The side not to move is in check: change the turn or the position."
    end
    return true
end

-- The number of move sequences of a given length, to compare with known counts.
function Rules.perft(position, depth)
    if depth == 0 then
        return 1
    end
    local moves = Rules.legalMoves(position)
    if depth == 1 then
        return #moves
    end
    local total = 0
    for _, move in ipairs(moves) do
        total = total + Rules.perft(play(position, move), depth - 1)
    end
    return total
end

return Rules
