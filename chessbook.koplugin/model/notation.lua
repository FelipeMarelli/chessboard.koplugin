-- The moves shown under the board, written as in a book, as parts to draw one after another:
-- texts, figurines in place of the piece letters, and gaps between moves. Figurines are always
-- White's pieces, whichever side moved, as in most books.
--
-- A move is what game:lastMove() gives. numbered: whether to write move numbers, which only mean
-- something when the game started from the usual position.
local Notation = {}

local ELLIPSIS = "…"

-- The parts of one move. A move of White carries its number; one of Black only when it is the
-- first one shown.
local function parts_of(move, numbered, first)
    local list = {}
    local function text(t)
        local last = list[#list]
        if last and last.kind == "text" then
            last.text = last.text .. t
        else
            list[#list + 1] = { kind = "text", text = t }
        end
    end
    local function figurine(piece)
        list[#list + 1] = { kind = "figurine", piece = piece:upper() }
    end
    local san = move.san
    if numbered and move.color == "w" then
        text(move.number .. ".")
    elseif numbered and first then
        text(move.number .. ELLIPSIS)
    end
    if san.piece then
        figurine(san.piece)
    end
    text(san.text)
    if san.promotion then
        text("=")
        figurine(san.promotion)
    end
    if san.suffix ~= "" then
        text(san.suffix)
    end
    return list
end

-- The parts of some moves, in order, with a gap between one move and the next:
-- { { kind = "text", text = "30." }, { kind = "figurine", piece = "B" }, { kind = "gap" }, ... }
function Notation.parts(moves, numbered)
    local list = {}
    for i, move in ipairs(moves) do
        if i > 1 then
            list[#list + 1] = { kind = "gap" }
        end
        for _, part in ipairs(parts_of(move, numbered, i == 1)) do
            list[#list + 1] = part
        end
    end
    return list
end

local function width(parts, width_of)
    local total = 0
    for _, part in ipairs(parts) do
        total = total + width_of(part)
    end
    return total
end

-- The parts of the most recent moves that fit in room, as wide as width_of says each part is. The
-- last move is always there, even when it does not fit whole.
function Notation.fit(moves, numbered, width_of, room)
    local best = {}
    for first = #moves, 1, -1 do
        local parts = Notation.parts({ unpack(moves, first) }, numbered)
        if first < #moves and width(parts, width_of) > room then
            break
        end
        best = parts
    end
    return best
end

return Notation
