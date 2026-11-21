-- E03: the game as PGN and as a lichess analysis link (model/export.lua).
local Export = require("model/export")
local Games = require("games")
local Helper = require("helper")
local eq, test = Helper.eq, Helper.test
local game_of = Games.of

local MAX = 2400

local SCHOLAR = { "e2e4", "e7e5", "d1h5", "b8c6", "f1c4", "g8f6", "h5f7" }

-- A position after 1. e4 with Black to move, set up in the editor: move 1, no en passant.
local AFTER_E4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"

test("the PGN of a game from the usual start: numbered moves with checks, no result", function()
    eq(Export.pgn(game_of(nil, unpack(SCHOLAR))),
        "1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7# *")
end)

test("the PGN of a game with no moves is only its result", function()
    eq(Export.pgn(game_of()), "*")
end)

test("the PGN is of the whole line, wherever the current position is", function()
    local game = game_of(nil, "e2e4", "e7e5")
    game:toStart()
    eq(Export.pgn(game), "1. e4 e5 *")
end)

test("the PGN of a game from a set up position carries it, and opens with Black's number",
    function()
        eq(Export.pgn(game_of(AFTER_E4, "e7e5", "g1f3")),
            '[SetUp "1"]\n[FEN "' .. AFTER_E4 .. '"]\n\n1... e5 2. Nf3 *')
    end)

test("a promotion is written with its piece", function()
    local start = "8/4P3/8/8/8/8/k7/4K3 w - - 0 50"
    eq(Export.pgn(game_of(start, "e7e8n")), '[SetUp "1"]\n[FEN "' .. start .. '"]\n\n50. e8=N *')
end)

test("the lichess link has spaces as _, no + or #, and opens at the current ply", function()
    local game = game_of(nil, unpack(SCHOLAR))
    eq(Export.lichessUrl(game, MAX),
        Export.LICHESS .. "1._e4_e5_2._Qh5_Nc6_3._Bc4_Nf6_4._Qxf7_%2A#7")
    game:back()
    game:back()
    assert(Export.lichessUrl(game, MAX):match("#5$"), "not at the current ply")
end)

test("the lichess link of a set up position encodes its headers, and counts plies from move 1",
    function()
        local game = game_of(AFTER_E4, "e7e5")
        eq(Export.lichessUrl(game, MAX), Export.LICHESS
            .. "%5BSetUp_%221%22%5D%0A%5BFEN_%22rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR"
            .. "_b_KQkq_-_0_1%22%5D%0A%0A1..._e5_%2A#2")
        game:toStart()
        assert(Export.lichessUrl(game, MAX):match("#1$"), "not at the start ply")
    end)

test("a promotion in a link keeps its =, encoded", function()
    local game = game_of("8/4P3/8/8/8/8/k7/4K3 w - - 0 50", "e7e8q")
    assert(Export.lichessUrl(game, MAX):match("50._e8%%3DQ_"), "no promotion")
end)

test("a link longer than the most a QR code holds gives nil and why", function()
    local game = game_of(nil, unpack(SCHOLAR))
    local url, err = Export.lichessUrl(game, 40)
    eq(url, nil)
    eq(err, "The game is too long for a QR code.")
end)
