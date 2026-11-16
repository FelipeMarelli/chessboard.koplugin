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
-- The parts of the move at index current, if any, carry current = true.
function Notation.parts(moves, numbered, current)
    local list = {}
    for i, move in ipairs(moves) do
        if i > 1 then
            list[#list + 1] = { kind = "gap" }
        end
        for _, part in ipairs(parts_of(move, numbered, i == 1)) do
            part.current = i == current or nil
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

-- The parts of the moves from first to last, the one at index current of all of them marked.
local function parts_between(moves, numbered, current, first, last)
    return Notation.parts({ unpack(moves, first, last) }, numbered, current - first + 1)
end

-- The earliest move from which the moves up to last fit in room; last itself when not even it fits.
local function first_fitting(moves, numbered, current, width_of, room, last)
    local first = last
    while first > 1
        and width(parts_between(moves, numbered, current, first - 1, last), width_of) <= room do
        first = first - 1
    end
    return first
end

-- The parts of the moves of a line that fit in room, as wide as width_of says each part is.
-- current is the index of the move that led to the position shown (0 at the start of the line;
-- the last one when nil): it is marked, and always there, even when it does not fit whole. The
-- moves shown end with the line when they can; else they start with the current one (with the
-- first one, at the start).
function Notation.fit(moves, numbered, width_of, room, current)
    current = current or #moves
    local anchor = math.max(current, 1)
    for last = #moves, anchor, -1 do
        local first = first_fitting(moves, numbered, current, width_of, room, last)
        if first <= anchor or last == anchor then
            return parts_between(moves, numbered, current, first, last)
        end
    end
    return {}
end

return Notation
