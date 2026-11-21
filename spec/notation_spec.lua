-- H16: the moves under the board written as in a book (model/notation.lua).
local Games = require("games")
local Helper = require("helper")
local Notation = require("model/notation")
local eq, test = Helper.eq, Helper.test

-- The last moves of a game played from a FEN (the usual start when nil), in coordinate notation.
local function moves_of(fen, ...)
    return Games.of(fen, ...):recentMoves(100)
end

-- Parts as one text: a figurine as its letter in brackets, a gap as a space.
local function show(parts)
    local out = {}
    for _, part in ipairs(parts) do
        out[#out + 1] = part.kind == "text" and part.text
            or part.kind == "figurine" and "[" .. part.piece .. "]" or " "
    end
    return table.concat(out)
end

local function written(numbered, fen, ...)
    return show(Notation.parts(moves_of(fen, ...), numbered))
end

test("C1, C2: White's moves carry their number, Black's go after them", function()
    eq(written(true, nil, "e2e4", "e7e5", "g1f3"), "1.e4 e5 2.[N]f3")
end)

test("C2: a move of Black that comes first carries its number and an ellipsis", function()
    local moves = moves_of(nil, "e2e4", "e7e5", "g1f3", "b8c6")
    eq(show(Notation.parts({ moves[2], moves[3], moves[4] }, true)), "1…e5 2.[N]f3 [N]c6")
    eq(show(Notation.parts({ moves[4] }, true)), "2…[N]c6")
end)

test("C3: without numbers, the moves alone", function()
    local fen = "4k3/8/8/8/8/8/4P3/4K3 b - - 0 1"
    eq(written(false, fen, "e8d7", "e2e4"), "[K]d7 e4")
end)

test("C1, C4: a figurine for each piece, White's for both sides, and parts merged", function()
    local parts = Notation.parts(moves_of(nil, "g1f3", "g8f6"), true)
    eq(parts, { { kind = "text", text = "1." }, { kind = "figurine", piece = "N" },
        { kind = "text", text = "f3" }, { kind = "gap" }, { kind = "figurine", piece = "N" },
        { kind = "text", text = "f6" } })
end)

test("C4: pawns, captures, promotion, castling, check and mate", function()
    eq(written(true, nil, "e2e4", "d7d5", "e4d5"), "1.e4 d5 2.exd5")
    eq(written(true, "4k3/1P6/8/8/8/8/8/4K3 w - - 0 1", "b7b8q"), "1.b8=[Q]+")
    eq(written(true, "r3k3/8/8/8/8/8/8/R3K2R w KQq - 0 1", "e1g1", "e8c8"), "1.O-O O-O-O")
    eq(written(true, nil, "f2f3", "e7e5", "g2g4", "d8h4"), "1.f3 e5 2.g4 [Q]h4#")
end)

test("C5: no moves, no parts", function()
    eq(Notation.parts({}, true), {})
    eq(Notation.fit({}, true, function() return 1 end, 100), {})
end)

-- Each character of a text 1 wide, a figurine 2 and a gap 1.
local function width_of(part)
    if part.kind == "text" then
        return #part.text:gsub("[\128-\191]", "") -- UTF-8 continuation bytes are no character
    end
    return part.kind == "figurine" and 2 or 1
end

test("C1: only the most recent moves that fit", function()
    local moves = moves_of(nil, "e2e4", "e7e5", "g1f3", "b8c6")
    -- "1.e4 e5 2.[N]f3 [N]c6" is 4 + 1 + 2 + 1 + 2 + 2 + 2 + 1 + 2 + 2 = 19 wide.
    eq(show(Notation.fit(moves, true, width_of, 19)), "1.e4 e5 2.[N]f3 [N]c6")
    -- Without the first move, e5 carries "1…": "1…e5 2.[N]f3 [N]c6" is 16 wide.
    eq(show(Notation.fit(moves, true, width_of, 18)), "1…e5 2.[N]f3 [N]c6")
    eq(show(Notation.fit(moves, true, width_of, 16)), "1…e5 2.[N]f3 [N]c6")
    eq(show(Notation.fit(moves, true, width_of, 15)), "2.[N]f3 [N]c6")
end)

-- The parts of the current move, as one text.
local function current_of(parts)
    local marked = {}
    for _, part in ipairs(parts) do
        if part.current then
            marked[#marked + 1] = part
        end
    end
    return show(marked)
end

test("C1: the move that led to the position shown is marked", function()
    local moves = moves_of(nil, "e2e4", "e7e5", "g1f3")
    eq(current_of(Notation.parts(moves, true, 3)), "2.[N]f3")
    eq(current_of(Notation.parts(moves, true, 2)), "e5")
    eq(current_of(Notation.parts(moves, true, 0)), "")
end)

-- Decided on 16 November 2026: going back keeps the line in the strip.
test("C1: the line ends the strip while the current move fits; else the strip starts with it",
    function()
        local moves = moves_of(nil, "e2e4", "e7e5", "g1f3", "b8c6")
        -- "1…e5 2.[N]f3 [N]c6" is 16 wide; "1.e4 e5" 7.
        eq(show(Notation.fit(moves, true, width_of, 16, 2)), "1…e5 2.[N]f3 [N]c6")
        eq(show(Notation.fit(moves, true, width_of, 16, 1)), "1.e4 e5 2.[N]f3")
        eq(current_of(Notation.fit(moves, true, width_of, 16, 1)), "1.e4")
        eq(show(Notation.fit(moves, true, width_of, 16, 0)), "1.e4 e5 2.[N]f3")
        eq(current_of(Notation.fit(moves, true, width_of, 16, 0)), "")
        eq(show(Notation.fit(moves, true, width_of, 1, 2)), "1…e5")
    end)

test("C7: the last move is there even when it does not fit whole", function()
    local moves = moves_of(nil, "e2e4", "e7e5", "g1f3")
    eq(show(Notation.fit(moves, true, width_of, 1)), "2.[N]f3")
end)

-- Each line of some lines of parts as one text.
local function shown_lines(lines)
    local out = {}
    for i, line in ipairs(lines) do
        out[i] = show(line)
    end
    return out
end

test("over several lines, the moves are cut between moves, without the gap at the cut",
    function()
        local moves = moves_of(nil, "e2e4", "e7e5", "g1f3", "b8c6")
        eq(shown_lines(Notation.lines(moves, true, width_of, 8, 3)),
            { "1.e4 e5", "2.[N]f3", "[N]c6" })
        eq(shown_lines(Notation.lines(moves, true, width_of, 19, 3)),
            { "1.e4 e5 2.[N]f3 [N]c6" })
    end)

test("over fewer lines than the line needs, the most recent moves that fit", function()
    local moves = moves_of(nil, "e2e4", "e7e5", "g1f3", "b8c6")
    eq(shown_lines(Notation.lines(moves, true, width_of, 8, 2)), { "2.[N]f3", "[N]c6" })
    eq(shown_lines(Notation.lines(moves, true, width_of, 8, 2, 1)), { "1.e4 e5", "2.[N]f3" })
end)

test("one line of lines is what fit gives", function()
    local moves = moves_of(nil, "e2e4", "e7e5", "g1f3", "b8c6")
    for room = 1, 20 do
        eq(Notation.lines(moves, true, width_of, room, 1)[1], Notation.fit(moves, true, width_of,
            room), "room " .. room)
    end
    eq(Notation.lines({}, true, width_of, 10, 3), {})
end)
