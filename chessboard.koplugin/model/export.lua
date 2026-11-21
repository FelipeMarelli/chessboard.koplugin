-- The game as PGN, and as a link that opens it on the lichess analysis board.
--
-- lichess takes a game in the path of /analysis/pgn/ (lila's UserAnalysis.pgn): it decodes the
-- path, turns "_" and "+" into spaces, and reads the PGN in the browser, start position from the
-- FEN header included. A "#ply" after it opens the board at that ply, counted from the usual start
-- position, and without it at the end of the game.
local Rules = require("chess/rules")

local Export = {}

Export.LICHESS = "https://lichess.org/analysis/pgn/"

-- PGN's mark for a game with no result yet.
local NO_RESULT = "*"

-- Characters a path takes as they are; every other one but the space is percent encoded.
local PLAIN = "[%w%-%./~]"

-- The moves of the line from its start position, each with the position it was played in, and
-- the game as serialize gives it.
local function line(game)
    local data = game:serialize()
    local position = assert(Rules.fromFen(data.start))
    local moves = {}
    for _, uci in ipairs(data.moves) do
        local move = assert(Rules.parseUci(position, uci))
        moves[#moves + 1] = { position = position, move = move }
        position = assert(Rules.apply(position, move))
    end
    return moves, data
end

-- The moves in SAN, numbered as in a book: White's with "12.", Black's with "12..." when it
-- opens the line. Without checks, "+" and "#" are left out.
local function movetext(moves, checks)
    local words = {}
    for index, played in ipairs(moves) do
        local position = played.position
        if position.turn == "w" then
            words[#words + 1] = position.fullmove .. "."
        elseif index == 1 then
            words[#words + 1] = position.fullmove .. "..."
        end
        local san = assert(Rules.sanText(position, played.move))
        words[#words + 1] = checks and san or san:gsub("[+#]$", "")
    end
    words[#words + 1] = NO_RESULT
    return table.concat(words, " ")
end

-- The PGN of a line: the headers of its start position when it is not the usual one, then the
-- moves.
local function pgn_of(start, moves, checks)
    local text = movetext(moves, checks)
    if start == Rules.START_FEN then
        return text
    end
    return '[SetUp "1"]\n[FEN "' .. start .. '"]\n\n' .. text
end

-- The PGN of the whole line of a game, with no result.
function Export.pgn(game)
    local moves, data = line(game)
    return pgn_of(data.start, moves, true)
end

-- Text as a path: spaces as "_", the rest that a path cannot hold percent encoded.
local function as_path(text)
    return (text:gsub(" ", "_"):gsub("[^_]", function(char)
        if char:match(PLAIN) then
            return char
        end
        return string.format("%%%02X", char:byte())
    end))
end

-- The ply of the current position counted from the usual start position, as lichess counts it.
local function ply(start, cursor)
    local position = assert(Rules.fromFen(start))
    return (position.fullmove - 1) * 2 + (position.turn == "b" and 1 or 0) + cursor
end

-- The link that opens the whole line of a game on the lichess analysis board, at the current
-- position; nil and why when it is longer than max characters.
function Export.lichessUrl(game, max)
    local moves, data = line(game)
    local url = Export.LICHESS .. as_path(pgn_of(data.start, moves, false))
        .. "#" .. ply(data.start, data.cursor)
    if #url > max then
        return nil, "The game is too long for a QR code."
    end
    return url
end

return Export
