-- Known move counts of standard chess and Chess960 positions, read from spec/perft.
--
-- Taken from tests/perft_spec.lua of Ink Knight, commit 601acd2a3a3e24148e442e10fd806accd6002782,
-- https://github.com/beater-studios/ink_knight.koplugin
-- Copyright (C) 2026 Beater Studios
-- Modified for chessbook.koplugin in November 2026: runs under spec/run.lua against
-- chess/rules.lua. Licensed under the GNU General Public License, version 3 only: see
-- chessbook.koplugin/chess/LICENSE-GPL-3.0.
--
-- The positions in spec/perft come from scalachess (MIT, spec/perft/LICENSE-scalachess). Each
-- depth's count must match, so any mistake in the rules shows. Only the depths up to PERFT_LIMIT
-- sequences run (20000 by default); PERFT_LIMIT=10000000 runs them deep. The first depth listed
-- always runs, so no limit turns a file into a pass that checked nothing.
local Helper = require("helper")
local Chess = require("chess/rules")
local test = Helper.test

local LIMIT = tonumber(os.getenv("PERFT_LIMIT")) or 20000
-- The 960 positions of Chess960 are many, so by default one in CHESS960_EVERY runs, to
-- CHESS960_LIMIT sequences: only the first depth.
local CHESS960_EVERY = tonumber(os.getenv("CHESS960_EVERY")) or 4
local CHESS960_LIMIT = tonumber(os.getenv("CHESS960_LIMIT")) or 100
-- What each file must hold: a change of a file that loses a position fails here.
local EXPECTED = { ["tricky.perft"] = 18, ["chess960.perft"] = 960 }

local function read(path)
    local cases, current = {}, nil
    for line in io.lines(path) do
        local id = line:match("^id%s+(%S+)")
        local epd = line:match("^epd%s+(.+)$")
        local depth, count = line:match("^perft%s+(%d+)%s+(%d+)")
        if id then
            current = { id = id, counts = {} }
            cases[#cases + 1] = current
        elseif epd and current then
            current.epd = epd
        elseif depth and current then
            -- Some positions skip depths, so the depths are kept with their count.
            current.counts[#current.counts + 1] = {
                depth = tonumber(depth), count = tonumber(count),
            }
        end
    end
    return cases
end

local function run_file(name, limit, every)
    local cases = read(Helper.dir .. "/perft/" .. name)
    test(name .. " has its positions", function()
        if #cases ~= EXPECTED[name] then
            error(string.format("expected %d, read %d", EXPECTED[name], #cases), 0)
        end
    end)
    for index, case in ipairs(cases) do
        if (index - 1) % every == 0 then
            -- The xfen positions write the castling of Chess960 as KQkq, so they are read as
            -- Chess960.
            local position = Chess.fromFen(case.epd or "", case.id:match("^xfen") ~= nil)
            test(name .. " " .. case.id, function()
                if not position then
                    error("cannot read the position " .. tostring(case.epd), 0)
                end
                table.sort(case.counts, function(a, b) return a.depth < b.depth end)
                assert(#case.counts > 0, "no count to compare")
                for position_index, item in ipairs(case.counts) do
                    if position_index > 1 and item.count > limit then
                        break
                    end
                    local got = Chess.perft(position, item.depth)
                    if got ~= item.count then
                        error(string.format("depth %d: expected %d, got %d", item.depth,
                            item.count, got), 0)
                    end
                end
            end)
        end
    end
end

run_file("tricky.perft", LIMIT, 1)
run_file("chess960.perft", CHESS960_LIMIT, CHESS960_EVERY)
