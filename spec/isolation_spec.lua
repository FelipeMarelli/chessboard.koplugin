-- The pure modules load without KOReader, and KOReader cannot be reached from the specs.
local Helper = require("helper")
local eq, test = Helper.eq, Helper.test

test("KOReader modules cannot be required from the specs", function()
    eq(pcall(require, "logger"), false)
    eq(pcall(require, "ui/widget/widget"), false)
    eq(pcall(require, "device"), false)
end)

test("chess/rules loads without KOReader", function()
    eq(type(require("chess/rules")), "table")
end)
