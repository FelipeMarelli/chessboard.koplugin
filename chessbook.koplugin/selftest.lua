-- Scripted run of the window with synthetic taps, for the emulator. Only runs when the variable
-- CHESSBOOK_SELFTEST is set.
--
--   CHESSBOOK_SELFTEST=1 [CHESSBOOK_SCENARIO=h03] [CHESSBOOK_PAGE=30] ./run-emu.sh book
--
-- Each scenario taps, checks the state and saves screenshots in emu-data/chessbook/. The result
-- goes to emu-data/chessbook/selftest.txt, one PASS or FAIL line per check.
local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local Screen = Device.screen

local STEP_SECONDS = 0.6

local SelfTest = {}
SelfTest.__index = SelfTest

function SelfTest:shot(name)
    -- Paint what is pending first: setDirty only paints on a later turn of the event loop.
    UIManager:forceRePaint()
    self.shots = self.shots + 1
    local orientation = Screen:getWidth() > Screen:getHeight() and "h" or "v"
    Screen.bb:writePNG(string.format("%s/%s_%s_%02d_%s.png", self.dir, self.scenario,
        orientation, self.shots, name))
end

function SelfTest:tap(x, y)
    UIManager:sendEvent(Event:new("Gesture", {
        ges = "tap", pos = Geom:new{ x = math.floor(x), y = math.floor(y), w = 0, h = 0 },
        time = 0,
    }))
end

function SelfTest:tapRect(rect)
    self:tap(rect.x + rect.w / 2, rect.y + rect.h / 2)
end

function SelfTest:check(name, ok, detail)
    local line = string.format("%s %s %s%s", ok and "PASS" or "FAIL", self.scenario, name,
        detail and (" (" .. tostring(detail) .. ")") or "")
    self.results[#self.results + 1] = line
    if not ok then
        self.failed = true
    end
    logger.info("chessbook selftest:", line)
end

-- Records the regions asked to be repainted, to check that only the window is.
function SelfTest:watchRepaints()
    self.repaints = {}
    local original = UIManager.setDirty
    self.restore_set_dirty = function() UIManager.setDirty = original end
    UIManager.setDirty = function(manager, widget, refresh, region, ...)
        if region then
            self.repaints[#self.repaints + 1] = { x = region.x, y = region.y, w = region.w,
                h = region.h }
        else
            self.repaints[#self.repaints + 1] = { full = true }
        end
        return original(manager, widget, refresh, region, ...)
    end
end

-- The page pixels inside a rect, to compare the page before opening and after closing.
local function grab(rect)
    local copy = {}
    local bb = Screen.bb
    for y = rect.y, rect.y + rect.h - 1 do
        for x = rect.x, rect.x + rect.w - 1 do
            copy[#copy + 1] = bb:getPixel(x, y):getColor8().a
        end
    end
    return copy
end

local function differences(a, b)
    local count = 0
    for i = 1, math.max(#a, #b) do
        if a[i] ~= b[i] then
            count = count + 1
        end
    end
    return count
end

local function same_rect(a, b)
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

-- H03: open, flip, tap inside and outside, close.
local function h03(t, plugin)
    local layout, session = plugin.layout, plugin.session
    local steps = {}
    local function step(fn) steps[#steps + 1] = fn end
    local page = tonumber(os.getenv("CHESSBOOK_PAGE") or "")
    if page then
        step(function() plugin.ui:handleEvent(Event:new("GotoPage", page)) end)
    end
    step(function()
        t:shot("page")
        t.page_pixels = grab(layout:rects().window)
        t:watchRepaints()
        plugin:toggle()
    end)
    step(function()
        t:shot("open")
        t:check("opens", layout:isOpen())
        local window = layout:rects().window
        t:check("open repaints only the window", #t.repaints == 1
            and same_rect(t.repaints[1], window))
        t.repaints = {}
        t:tapRect(layout:buttonRect("flip"))
    end)
    step(function()
        t:shot("flipped")
        t:check("flip turns the board", session:flipped())
        t:check("flip repaints only the window", #t.repaints == 1
            and same_rect(t.repaints[1], layout:rects().window))
        t:tapRect(layout:buttonRect("flip"))
    end)
    step(function()
        t:check("flip again turns it back", not session:flipped())
        t.page_before = plugin.ui:getCurrentPage()
        t:tapRect(layout:squareRect(29, false))
        t:tapRect(layout:rects().titlebar)
    end)
    step(function()
        t:check("taps inside do not turn the page",
            plugin.ui:getCurrentPage() == t.page_before, plugin.ui:getCurrentPage())
        -- Right of the page, below the top band that opens the reader menu.
        t:tap(Screen:getWidth() * 0.9, Screen:getHeight() * 0.25)
    end)
    step(function()
        local now = plugin.ui:getCurrentPage()
        t:check("a tap outside turns the page", now ~= t.page_before,
            t.page_before .. " -> " .. now)
        plugin.ui:handleEvent(Event:new("GotoPage", t.page_before))
    end)
    step(function()
        t.repaints = {}
        t:tapRect(layout:buttonRect("close"))
    end)
    step(function()
        t:shot("closed")
        local window = layout:rects().window
        t:check("close closes", not layout:isOpen())
        t:check("close repaints only the window", #t.repaints == 1
            and same_rect(t.repaints[1], window))
        local diff = differences(t.page_pixels, grab(window))
        t:check("the page is clean after closing", diff == 0, diff .. " pixels differ")
    end)
    return steps
end

local SCENARIOS = { h03 = h03 }

function SelfTest.start(plugin)
    local t = setmetatable({ shots = 0, results = {}, failed = false }, SelfTest)
    t.scenario = os.getenv("CHESSBOOK_SCENARIO") or "h03"
    t.dir = DataStorage:getDataDir() .. "/chessbook"
    if lfs.attributes(t.dir, "mode") ~= "directory" then
        lfs.mkdir(t.dir)
    end
    local steps = assert(SCENARIOS[t.scenario], "no scenario " .. t.scenario)(t, plugin)
    steps[#steps + 1] = function() t:finish(plugin) end
    local i = 0
    t.run = function()
        i = i + 1
        if not steps[i] then
            return
        end
        local ok, err = pcall(steps[i])
        if not ok then
            t:check("step " .. i, false, err)
        end
        if t.run then -- nil once stopped
            UIManager:scheduleIn(STEP_SECONDS, t.run)
        end
    end
    UIManager:scheduleIn(1, t.run)
    return t
end

function SelfTest:finish(plugin)
    if self.restore_set_dirty then
        self.restore_set_dirty()
    end
    local file = io.open(self.dir .. "/selftest.txt", "a")
    if file then
        file:write(table.concat(self.results, "\n"), "\n")
        file:close()
    end
    for _, line in ipairs(self.results) do
        print("chessbook selftest: " .. line)
    end
    self:stop()
    plugin.ui:onClose()
    UIManager:quit(self.failed and 1 or 0)
end

-- Steps scheduled for later must not run once the book is closed.
function SelfTest:stop()
    if self.run then
        UIManager:unschedule(self.run)
        self.run = nil
    end
    if self.restore_set_dirty then
        self.restore_set_dirty()
        self.restore_set_dirty = nil
    end
end

return SelfTest
