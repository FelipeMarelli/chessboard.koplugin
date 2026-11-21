-- Moves and games written short, shared by the specs.
local Game = require("chess/game")
local Rules = require("chess/rules")

local Games = {}

-- A move in coordinate notation ("e2e4", "a7a8q") as a move table, legal or not.
function Games.move(uci)
    local from, to, promotion = uci:match("^(%a%d)(%a%d)(%a?)$")
    return { from = Rules.squareFromName(from), to = Rules.squareFromName(to),
        promotion = promotion ~= "" and promotion or nil }
end

-- Plays moves in coordinate notation on a game, each one legal; returns the game.
function Games.play(game, ...)
    for _, uci in ipairs({ ... }) do
        assert(game:play(Games.move(uci)))
    end
    return game
end

-- A game from a FEN (the usual start when nil) with moves in coordinate notation played.
function Games.of(fen, ...)
    return Games.play(assert(Game.new(fen)), ...)
end

return Games
