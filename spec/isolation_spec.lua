-- The pure modules load without KOReader, and KOReader cannot be reached from the specs.
local Helper = require("helper")
local eq, test = Helper.eq, Helper.test

test("KOReader modules cannot be required from the specs", function()
    eq(pcall(require, "logger"), false)
    eq(pcall(require, "ui/widget/widget"), false)
    eq(pcall(require, "device"), false)
end)

test("every module of chess/ and model/ loads without KOReader", function()
    local plugin = Helper.dir .. "/../chessboard.koplugin"
    local count = 0
    for _, folder in ipairs({ "chess", "model" }) do
        local list = assert(io.popen('ls -1 "' .. plugin .. "/" .. folder .. '"'))
        for name in list:lines() do
            local module = name:match("^(.+)%.lua$")
            if module then
                eq(type(require(folder .. "/" .. module)), "table")
                count = count + 1
            end
        end
        list:close()
    end
    assert(count >= 3, "found only " .. count .. " modules")
end)
