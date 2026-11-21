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

-- The parts of each move, and the gap before each one but the first.
local function by_move(parts)
    local groups, gaps = { {} }, {}
    for _, part in ipairs(parts) do
        if part.kind == "gap" then
            groups[#groups + 1] = {}
            gaps[#groups] = part
        else
            table.insert(groups[#groups], part)
        end
    end
    return groups, gaps
end

-- Parts cut into lines no wider than room, between moves: a move goes on the line before when it
-- fits there after its gap, and else starts a line, alone if it is wider than room.
local function wrap(parts, width_of, room)
    local groups, gaps = by_move(parts)
    local lines, used = {}, 0
    for i, group in ipairs(groups) do
        local w, line = width(group, width_of), lines[#lines]
        local gap = gaps[i]
        if line and used + width_of(gap) + w <= room then
            line[#line + 1] = gap
            used = used + width_of(gap) + w
        else
            line = {}
            lines[#lines + 1] = line
            used = w
        end
        for _, part in ipairs(group) do
            line[#line + 1] = part
        end
    end
    return lines
end

-- Whether the moves from first to last take no more than rows lines of room.
local function fits(moves, numbered, current, width_of, room, rows, first, last)
    local parts = parts_between(moves, numbered, current, first, last)
    return #wrap(parts, width_of, room) <= rows
end

-- The earliest move from which the moves up to last fit in rows lines of room; last itself when
-- not even it fits.
local function first_fitting(moves, numbered, current, width_of, room, rows, last)
    local first = last
    while first > 1 and fits(moves, numbered, current, width_of, room, rows, first - 1, last) do
        first = first - 1
    end
    return first
end

-- The parts of the moves of a line that fit in rows lines of room, a list of parts for each line,
-- cut between moves. As wide as width_of says each part is. current is the index of the move that
-- led to the position shown (0 at the start of the line; the last one when nil): it is marked, and
-- always there, even when it does not fit whole. The moves shown end with the line when they can;
-- else they start with the current one (with the first one, at the start).
function Notation.lines(moves, numbered, width_of, room, rows, current)
    current = current or #moves
    local anchor = math.max(current, 1)
    for last = #moves, anchor, -1 do
        local first = first_fitting(moves, numbered, current, width_of, room, rows, last)
        if first <= anchor or last == anchor then
            return wrap(parts_between(moves, numbered, current, first, last), width_of, room)
        end
    end
    return {}
end

-- The parts of the moves of a line that fit in one line of room (see Notation.lines).
function Notation.fit(moves, numbered, width_of, room, current)
    return Notation.lines(moves, numbered, width_of, room, 1, current)[1] or {}
end

return Notation
