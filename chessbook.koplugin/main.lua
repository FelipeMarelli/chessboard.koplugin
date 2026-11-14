--[[--
Chess book companion: proof of concept.

Answers two questions:
 1. Can a plugin paint a panel over the book page that takes taps, while the
    rest of the page keeps working (page turns, menus)?
 2. Can a plugin read what is under a tap: pixels of a diagram (PDF/DjVu/EPUB)
    and text/markup (EPUB)?
--]]

local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")

local Screen = Device.screen

-- Reader tap zones the panel must win against.
local TAP_OVERRIDES = {
    "tap_link", "readerhighlight_tap", "readerhighlight_tap_select_mode",
    "readerfooter_tap", "readermenu_tap", "readermenu_ext_tap",
    "readerconfigmenu_tap", "readerconfigmenu_ext_tap",
    "tap_forward", "tap_backward", "inertial_scrolling_tap",
}

local ChessBook = WidgetContainer:extend{
    name = "chessbook",
    is_doc_only = true,
    visible = false,
    armed = false,       -- next tap on the page captures what is under it
    selected = nil,      -- {file=1..8, rank=1..8}
    status = {},         -- lines of text shown in the panel
    thumb = nil,         -- scaled copy of the last captured bitmap
    capture_count = 0,
}

function ChessBook:init()
    self.out_dir = DataStorage:getDataDir() .. "/chessbook"
    if lfs.attributes(self.out_dir, "mode") ~= "directory" then lfs.mkdir(self.out_dir) end
    self.status = { "Panel listo." }
    self.ui.menu:registerToMainMenu(self)
    self:computeLayout()
end

function ChessBook:addToMainMenu(menu_items)
    menu_items.chessbook = {
        text = _("Chess board panel"),
        sorting_hint = "more_tools",
        checked_func = function() return self.visible end,
        callback = function() self:toggle() end,
    }
end

function ChessBook:onReaderReady()
    self.view:registerViewModule("chessbook", self)
    self.ui:registerTouchZones({
        {
            id = "chessbook_tap",
            ges = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            overrides = TAP_OVERRIDES,
            handler = function(ges) return self:onTap(ges) end,
        },
    })
    if os.getenv("CHESSBOOK_SELFTEST") then
        UIManager:scheduleIn(1, function() self:selfTest() end)
    end
end

-- Called by ReaderView on screen rotation/resize.
function ChessBook:resetLayout()
    self:computeLayout()
end

function ChessBook:computeLayout()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local pad = math.floor(sw * 0.02)
    local sq = math.floor(sw * 0.56 / 8)
    local board = sq * 8
    local ph = board + 2 * pad
    self.panel = Geom:new{ x = 0, y = sh - ph, w = sw, h = ph }
    self.board = Geom:new{ x = pad, y = self.panel.y + pad, w = board, h = board }
    self.sq = sq
    local sx = self.board.x + board + pad
    local side_w = sw - sx - pad
    local bh = math.floor(sq * 0.9)
    self.btn_capture = Geom:new{ x = sx, y = self.board.y, w = math.floor(side_w * 0.6), h = bh }
    self.btn_close = Geom:new{ x = sx + self.btn_capture.w + pad, y = self.board.y, w = side_w - self.btn_capture.w - pad, h = bh }
    self.side = Geom:new{ x = sx, y = self.board.y + bh + pad, w = side_w, h = board - bh - pad }
    local strip_h = math.floor(sq * 0.9)
    self.strip = Geom:new{ x = 0, y = sh - strip_h, w = sw, h = strip_h }
    self.face = Font:getFace("cfont", 14)
    self.face_small = Font:getFace("cfont", 11)
end

function ChessBook:toggle()
    self.visible = not self.visible
    self.armed = false
    self:refresh()
end

function ChessBook:refresh()
    UIManager:setDirty(self.view.dialog, "ui")
end

local function inside(rect, pos)
    return pos.x >= rect.x and pos.x < rect.x + rect.w and pos.y >= rect.y and pos.y < rect.y + rect.h
end

-- Returns true only when the panel consumed the tap; anything else falls
-- through to the reader's own zones (page turn, menu, links...).
function ChessBook:onTap(ges)
    if not self.visible then return false end
    local pos = ges.pos
    if self.armed then
        self.armed = false
        if inside(self.strip, pos) then
            self.status = { "Captura cancelada." }
        else
            self:capture(pos)
        end
        self:refresh()
        return true
    end
    if inside(self.panel, pos) then
        if inside(self.board, pos) then
            local file = math.floor((pos.x - self.board.x) / self.sq) + 1
            local rank = 8 - math.floor((pos.y - self.board.y) / self.sq)
            self.selected = { file = file, rank = rank }
            self.status = { "Casilla: " .. string.char(96 + file) .. rank }
        elseif inside(self.btn_capture, pos) then
            self.armed = true
        elseif inside(self.btn_close, pos) then
            self.visible = false
        end
        self:refresh()
        return true
    end
    return false
end

function ChessBook:setThumb(bb)
    if self.thumb then self.thumb:free() self.thumb = nil end
    if not bb then return end
    local max_w, max_h = self.side.w, math.floor(self.side.h * 0.55)
    local scale = math.min(max_w / bb:getWidth(), max_h / bb:getHeight())
    self.thumb = bb:scale(math.max(1, math.floor(bb:getWidth() * scale)), math.max(1, math.floor(bb:getHeight() * scale)))
end

function ChessBook:savePNG(bb, tag)
    self.capture_count = self.capture_count + 1
    local path = string.format("%s/%s_%02d.png", self.out_dir, tag, self.capture_count)
    bb:writePNG(path)
    return path
end

function ChessBook:log(lines)
    self.status = lines
    local f = io.open(self.out_dir .. "/log.txt", "a")
    if f then
        f:write("---- ", self.ui.document.file:match("[^/]+$"), "\n")
        for _, l in ipairs(lines) do f:write(l, "\n") end
        f:close()
    end
    logger.info("chessbook:", table.concat(lines, " | "))
end

-- Renders a rectangle of a page (native page coordinates) to a bitmap.
-- Returns bb, owned: when owned is true the caller must free it.
function ChessBook:renderPagePart(pageno, rect)
    local doc = self.ui.document
    if not doc.is_djvu then
        return doc:drawPagePart(pageno, rect, 0), false -- TileCache item
    end
    -- Document:drawPagePart is wrong for DjVu: the native draw ignores the
    -- x/y it is given and only honours the draw context offset, so the result
    -- is always the top-left corner of the page. Render it ourselves.
    local DrawContext = require("ffi/drawcontext")
    local zoom = math.min(Screen:getWidth() / rect.w, Screen:getHeight() / rect.h)
    local w, h = math.floor(rect.w * zoom), math.floor(rect.h * zoom)
    local bb = Blitbuffer.new(w, h, doc.render_color and doc.color_bb_type or nil)
    local dc = DrawContext.new()
    dc:setRotate(0)
    dc:setZoom(zoom)
    dc:setOffset(-math.floor(rect.x * zoom), -math.floor(rect.y * zoom))
    local page = doc._document:openPage(pageno)
    page:draw(dc, bb, 0, 0, doc.render_mode)
    page:close()
    return bb, true
end

function ChessBook:capture(pos)
    local doc = self.ui.document
    local lines = {}
    if self.ui.paging then
        -- PDF / DjVu: find the box around the tap, render it from the page.
        local ppos = self.view:screenToPageTransform(pos)
        if not ppos then return self:log({ "Fuera de la pagina." }) end
        local rect = doc:getPanelFromPage(ppos.page, ppos)
        local how = "recuadro detectado"
        if not rect then
            local psize = doc:getNativePageDimensions(ppos.page)
            local side = math.floor(psize.w * 0.3)
            local rx = math.max(0, math.min(psize.w - side, math.floor(ppos.x - side / 2)))
            local ry = math.max(0, math.min(psize.h - side, math.floor(ppos.y - side / 2)))
            rect = Geom:new{ x = rx, y = ry, w = side, h = side }
            how = "sin recuadro: cuadrado alrededor del toque"
        end
        local bb, owned = self:renderPagePart(ppos.page, rect)
        local path = self:savePNG(bb, "page" .. ppos.page)
        self:setThumb(bb)
        lines = {
            how,
            string.format("Pagina %d, %dx%d en (%d,%d)", ppos.page, rect.w, rect.h, rect.x, rect.y),
            string.format("Bitmap %dx%d", bb:getWidth(), bb:getHeight()),
            path:match("[^/]+$"),
        }
        if owned then bb:free() end
    else
        -- EPUB: image under the tap, else the word under the tap and its markup.
        local link = doc:getLinkFromPosition(pos)
        local image = doc:getImageFromPosition(pos, false, false)
        if image then
            local path = self:savePNG(image, "img")
            self:setThumb(image)
            lines = { string.format("Imagen %dx%d", image:getWidth(), image:getHeight()), path:match("[^/]+$") }
            image:free()
        else
            self:setThumb(nil)
            local word = doc:getWordFromPosition(pos, true)
            if word and word.word then
                lines = { "Palabra: " .. word.word, "xpointer: " .. tostring(word.pos0) }
                local html = word.pos0 and doc:getHTMLFromXPointer(word.pos0, 0x1001, true)
                if html then
                    -- keep the neighbourhood of the tapped word, markup included
                    local i = html:find(word.word, 1, true) or 1
                    table.insert(lines, "HTML: " .. html:sub(math.max(1, i - 160), i + 60):gsub("%s+", " "))
                end
            else
                lines = { "Nada bajo el toque." }
            end
        end
        if link then table.insert(lines, "Link: " .. tostring(link)) end
    end
    self:log(lines)
end

function ChessBook:drawText(bb, text, x, y, max_w, face)
    local tw = TextWidget:new{ text = text, face = face or self.face, max_width = max_w }
    tw:paintTo(bb, x, y)
    local h = tw:getSize().h
    tw:free()
    return h
end

function ChessBook:drawButton(bb, rect, label, active)
    bb:paintRect(rect.x, rect.y, rect.w, rect.h, active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE)
    bb:paintBorder(rect.x, rect.y, rect.w, rect.h, 2, Blitbuffer.COLOR_BLACK)
    local tw = TextWidget:new{ text = label, face = self.face, fgcolor = active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK }
    local sz = tw:getSize()
    tw:paintTo(bb, rect.x + math.floor((rect.w - sz.w) / 2), rect.y + math.floor((rect.h - sz.h) / 2))
    tw:free()
end

-- Painted by ReaderView after the page, as a view module.
function ChessBook:paintTo(bb, x, y)
    if not self.visible then return end
    if self.armed then
        local s = self.strip
        bb:paintRect(s.x, s.y, s.w, s.h, Blitbuffer.COLOR_BLACK)
        local tw = TextWidget:new{
            text = "Toca un diagrama o una jugada  -  toca aca para cancelar",
            face = self.face_small, fgcolor = Blitbuffer.COLOR_WHITE, max_width = s.w - 20,
        }
        local sz = tw:getSize()
        tw:paintTo(bb, s.x + math.floor((s.w - sz.w) / 2), s.y + math.floor((s.h - sz.h) / 2))
        tw:free()
        return
    end
    local p, b, sq = self.panel, self.board, self.sq
    bb:paintRect(p.x, p.y, p.w, p.h, Blitbuffer.COLOR_WHITE)
    bb:paintRect(p.x, p.y, p.w, 3, Blitbuffer.COLOR_BLACK)
    for r = 0, 7 do
        for f = 0, 7 do
            if (r + f) % 2 == 1 then
                bb:paintRect(b.x + f * sq, b.y + r * sq, sq, sq, Blitbuffer.COLOR_GRAY_B)
            end
        end
    end
    bb:paintBorder(b.x, b.y, b.w, b.h, 2, Blitbuffer.COLOR_BLACK)
    if self.selected then
        local sx = b.x + (self.selected.file - 1) * sq
        local sy = b.y + (8 - self.selected.rank) * sq
        bb:paintRect(sx, sy, sq, sq, Blitbuffer.COLOR_BLACK)
        local tw = TextWidget:new{
            text = string.char(96 + self.selected.file) .. self.selected.rank,
            face = self.face, fgcolor = Blitbuffer.COLOR_WHITE,
        }
        local sz = tw:getSize()
        tw:paintTo(bb, sx + math.floor((sq - sz.w) / 2), sy + math.floor((sq - sz.h) / 2))
        tw:free()
    end
    self:drawButton(bb, self.btn_capture, "Capturar", self.armed)
    self:drawButton(bb, self.btn_close, "X", false)
    local ty = self.side.y
    if self.thumb then
        bb:blitFrom(self.thumb, self.side.x, ty, 0, 0, self.thumb:getWidth(), self.thumb:getHeight())
        bb:paintBorder(self.side.x, ty, self.thumb:getWidth(), self.thumb:getHeight(), 1, Blitbuffer.COLOR_BLACK)
        ty = ty + self.thumb:getHeight() + 6
    end
    for _, line in ipairs(self.status) do
        if ty > self.side.y + self.side.h - 10 then break end
        ty = ty + self:drawText(bb, line, self.side.x, ty, self.side.w, self.face_small) + 2
    end
end

-- ---------------------------------------------------------------------------
-- Scripted run, for checking the plugin without hands on the window.
--   CHESSBOOK_SELFTEST=1 CHESSBOOK_PAGE=30 CHESSBOOK_TAPS="0.30,0.25;0.70,0.40"
-- Taps are screen ratios; each one is sent as a capture tap.
-- ---------------------------------------------------------------------------
function ChessBook:selfTest()
    local shots = 0
    local function shot(name)
        shots = shots + 1
        UIManager:forceRePaint()
        Screen.bb:writePNG(string.format("%s/shot_%02d_%s.png", self.out_dir, shots, name))
    end
    local function tap(x, y)
        UIManager:sendEvent(Event:new("Gesture", {
            ges = "tap", pos = Geom:new{ x = math.floor(x), y = math.floor(y), w = 0, h = 0 }, time = 0,
        }))
    end
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local steps = {}
    local page = tonumber(os.getenv("CHESSBOOK_PAGE") or "")
    if page then
        table.insert(steps, function() self.ui:handleEvent(Event:new("GotoPage", page)) end)
    end
    table.insert(steps, function() shot("page") end)
    table.insert(steps, function() self:toggle() end)
    table.insert(steps, function() shot("panel") end)
    -- tap square e4 on the panel board
    table.insert(steps, function() tap(self.board.x + 4.5 * self.sq, self.board.y + 4.5 * self.sq) end)
    table.insert(steps, function() shot("square_e4") end)
    -- tap on the page with the panel open and capture NOT armed: must turn the page
    table.insert(steps, function()
        self.before_page = self.ui:getCurrentPage()
        tap(sw * 0.9, sh * 0.2)
    end)
    table.insert(steps, function()
        self:log({ string.format("Toque fuera del panel: pagina %d -> %d", self.before_page, self.ui:getCurrentPage()) })
        if page then self.ui:handleEvent(Event:new("GotoPage", page)) end
    end)
    for xs, ys in (os.getenv("CHESSBOOK_TAPS") or ""):gmatch("([%d.]+),([%d.]+)") do
        table.insert(steps, function() tap(self.btn_capture.x + 5, self.btn_capture.y + 5) end)
        table.insert(steps, function() tap(sw * tonumber(xs), sh * tonumber(ys)) end)
        table.insert(steps, function() shot("capture") end)
    end
    table.insert(steps, function() self.ui:onClose() UIManager:quit(0) end)
    local i = 0
    local function run()
        i = i + 1
        if not steps[i] then return end
        local ok, err = pcall(steps[i])
        if not ok then logger.err("chessbook: selftest paso", i, "fallo:", err) end
        UIManager:scheduleIn(0.6, run)
    end
    run()
end

return ChessBook
