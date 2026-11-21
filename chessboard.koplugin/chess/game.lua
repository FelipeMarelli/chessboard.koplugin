-- A game: a start position, a tree of moves and a cursor on the current position.
--
-- Each node holds the move that leads to it and the position after it. For now every node has at
-- most one continuation (playing something else replaces it), but the tree lets variations come
-- later without changing the saved data.
local Rules = require("chess/rules")

local Game = {}
Game.__index = Game

local function new_node(parent, move, position)
    return { parent = parent, move = move, position = position, children = {} }
end

local function same_move(a, b)
    return a.from == b.from and a.to == b.to and a.promotion == b.promotion
        and a.castle == b.castle
end

-- The start position of a FEN, or nil and why it cannot start a game.
local function start_position(start_fen)
    local position, err = Rules.fromFen(start_fen or Rules.START_FEN)
    if not position then
        return nil, err
    end
    local ok, reason = Rules.validate(position)
    if not ok then
        return nil, reason
    end
    return position
end

-- A game from a FEN, the usual start position when there is none.
function Game.new(start_fen)
    local game = setmetatable({}, Game)
    local ok, err = game:reset(start_fen)
    if not ok then
        return nil, err
    end
    return game
end

-- Starts again from a position, dropping every move. An invalid FEN changes nothing.
function Game:reset(start_fen)
    local position, err = start_position(start_fen)
    if not position then
        return nil, err
    end
    self.root = new_node(nil, nil, position)
    self.cursor = self.root
    return true
end

function Game:position()
    return self.cursor.position
end

-- Plays a legal move from the current position. The same move as the one already there only
-- moves the cursor forward; another one replaces everything that followed.
function Game:play(move)
    local position, legal = Rules.apply(self.cursor.position, move)
    if not position then
        return nil, legal
    end
    local next_node = self.cursor.children[1]
    if not (next_node and same_move(next_node.move, legal)) then
        next_node = new_node(self.cursor, legal, position)
        self.cursor.children = { next_node }
    end
    self.cursor = next_node
    return true
end

function Game:canBack()
    return self.cursor.parent ~= nil
end

function Game:canForward()
    return self.cursor.children[1] ~= nil
end

function Game:back()
    if not self:canBack() then
        return false
    end
    self.cursor = self.cursor.parent
    return true
end

function Game:forward()
    if not self:canForward() then
        return false
    end
    self.cursor = self.cursor.children[1]
    return true
end

function Game:toStart()
    local moved = self:canBack()
    self.cursor = self.root
    return moved
end

function Game:toEnd()
    local moved = false
    while self:forward() do
        moved = true
    end
    return moved
end

-- The move that led to a node, with its move number, the color that played it and its notation
-- (see rules.san), worked out the first time it is asked for. Nil for the root.
local function move_of(node)
    if not node.parent then
        return nil
    end
    local before = node.parent.position
    if not node.san then
        node.san = Rules.san(before, node.move)
    end
    return { move = node.move, number = before.fullmove, color = before.turn, san = node.san }
end

-- The move that led to the current position (see move_of), or nil at the start.
function Game:lastMove()
    return move_of(self.cursor)
end

-- The last moves, up to count, that led to the current position, oldest first, each as lastMove
-- gives it. Empty at the start.
function Game:recentMoves(count)
    local list = {}
    local node = self.cursor
    while node.parent and #list < count do
        list[#list + 1] = move_of(node)
        node = node.parent
    end
    for i = 1, math.floor(#list / 2) do
        list[i], list[#list + 1 - i] = list[#list + 1 - i], list[i]
    end
    return list
end

-- The moves of the line after the current position, up to count, in order, each as lastMove
-- gives it. Empty at the end of the line.
function Game:nextMoves(count)
    local list = {}
    local node = self.cursor.children[1]
    while node and #list < count do
        list[#list + 1] = move_of(node)
        node = node.children[1]
    end
    return list
end

-- The FEN of the position the game started from.
function Game:startFen()
    return Rules.toFen(self.root.position)
end

-- A plain table to save: the start FEN, the moves of the line in coordinate notation, and the
-- cursor as the number of moves played from the start.
function Game:serialize()
    local moves, cursor = {}, 0
    local node = self.root
    while node.children[1] do
        local child = node.children[1]
        moves[#moves + 1] = Rules.moveToUci(child.move, node.position)
        node = child
        if node == self.cursor then
            cursor = #moves
        end
    end
    return { start = Rules.toFen(self.root.position), moves = moves, cursor = cursor }
end

-- The game a table from serialize stands for, or nil and why it cannot be read.
function Game.deserialize(data)
    if type(data) ~= "table" or type(data.start) ~= "string" or type(data.moves) ~= "table" then
        return nil, "invalid game data"
    end
    local game, err = Game.new(data.start)
    if not game then
        return nil, err
    end
    for index, uci in ipairs(data.moves) do
        local move = Rules.parseUci(game:position(), uci)
        if not (move and game:play(move)) then
            return nil, "invalid move " .. index .. ": " .. tostring(uci)
        end
    end
    local cursor = data.cursor
    if type(cursor) ~= "number" or cursor % 1 ~= 0 or cursor < 0 or cursor > #data.moves then
        return nil, "invalid cursor"
    end
    game:toStart()
    for _ = 1, cursor do
        game:forward()
    end
    return game
end

return Game
