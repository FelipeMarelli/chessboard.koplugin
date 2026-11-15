-- What the reader does with the board and what has to be drawn for it.
--
-- For now it only shows the position of a game and turns the board round; selecting and moving
-- pieces come with later stories.
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

-- a1 is dark.
local function is_light(sq)
    return (Rules.fileOf(sq) + Rules.rankOf(sq)) % 2 == 1
end

-- What there is to draw: each square with its piece, its marks and whether it is a light one,
-- whose turn it is, how the game stands, its last move, and which buttons can be used.
function Session:view()
    local position = self.game:position()
    local squares = {}
    for sq = 1, 64 do
        squares[sq] = { piece = Rules.pieceAt(position, sq), marks = {}, light = is_light(sq) }
    end
    return {
        squares = squares,
        turn = Rules.turn(position),
        status = Rules.status(position),
        last_move = self.game:lastMove(),
        promotion = nil,
        flipped = self.is_flipped,
        buttons = { close = true, flip = true },
    }
end

return Session
