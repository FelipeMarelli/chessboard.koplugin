-- Sizes, grays and the cache of bitmaps the window is drawn with.
--
-- Sizes are in design pixels, those of a screen of 600 by 800 scaled to the real one
-- (Layout.scaleFor): on a 6-inch screen one is about 0.18 mm. Grays are values from 0 (black) to
-- 255 (white). They are first guesses, to be tuned on the Kindle.
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Layout = require("model/layout")
local RenderImage = require("ui/renderimage")
local TextWidget = require("ui/widget/textwidget")

local Screen = Device.screen

local Theme = {}

-- Window geometry, for model/layout.lua.
Theme.SIZES = {
    row = 39,       -- height of the button row under the board
    button = 39,    -- button width
    border = 2,     -- window frame
    margin = 11,    -- gap to the screen edge
    min_square = 29, -- leaves room in the buttons for the square of a held one (ui/kit.lua)
    size_step = 6,  -- how much the side of a square changes with each tap on smaller or bigger
    gutter = 14,    -- strips for the coordinates outside the board; 0 puts them on the squares
    notation = 26,  -- strip with the last moves, between the board and the buttons (H16)
    spacing = 8,    -- gap between the board and a row of buttons right under it, so that their
                    -- white cards do not run into the white border of the board
    divider = 24,   -- the strip dragged to move the edge of the split screen (H18)
    split_controls = 80, -- the least room beside the board for its buttons, split
    split_button = 80, -- the biggest a button gets, split; the room left is between the board
                       -- and the buttons
}

local function gray(value)
    return Blitbuffer.Color8(value)
end

-- surface: the ground of the window under the board (the button rows and the strip of moves). The
-- coordinates go on white, a border that sets the board apart from it.
Theme.GRAY = {
    frame = gray(0x00),
    surface = gray(0xEE),
    light_square = gray(0xEE),
    dark_square = gray(0xAA),
    gutter = gray(0xFF),
}
Theme.GRAY.row = Theme.GRAY.surface

-- Buttons (ui/kit.lua): a card on the ground of the row, a square in the face gray with no border,
-- as big as fits in the button leaving gap on each side, with corners rounded by the share round of
-- its side. Its icon, in ink, takes the share icon of the card, so a big button looks like a small
-- one, only bigger. A button held down has its card in down and its icon in down_ink. stroke:
-- lines drawn by hand in a button, as thick as those of the icons. The icon of a button that would
-- do nothing is lightened by the share disabled; those of the tools of the editor not chosen by
-- unchosen, so that the chosen one stands out.
Theme.BUTTON = {
    gap = 2,
    round = 0.22,
    icon = 0.66,
    stroke = 2,
    ground = Theme.GRAY.surface,
    face = gray(0xFF),
    ink = gray(0x00),
    down = gray(0xBB),
    down_ink = gray(0x00),
    disabled = 0.6,
    unchosen = 0.6,
}

-- The divider of the split screen: a strip in ground (held while the finger is on it), with a grip
-- in the middle, grip_length long along it and grip_width thick, in design pixels.
Theme.DIVIDER = {
    ground = gray(0xCC),
    held = gray(0x99),
    grip = gray(0x44),
    grip_length = 60,
    grip_width = 6,
}

-- Marks on the squares, in the manner of lichess. Sizes are shares of the square side.
-- They differ in shape: a frame for the selected piece, a dot for a move to an empty square,
-- corners for a capture and a disc behind a king in check. The last move is not marked on the
-- board, as chosen after trying a tint, a frame and a sheet of other ways: the strip of
-- moves shows it in bold.
Theme.MARK = {
    selected = gray(0x33),
    selected_width = 0.08,
    target = gray(0x55),
    target_radius = 0.15,
    capture = gray(0x55),
    capture_leg = 0.28,
    check = gray(0x77),
    check_radius = 0.48,
}

-- The promotion selector, as on lichess: the board lightened by dim, and the pieces to choose on
-- white squares with a frame, frame_width a share of the square side.
Theme.PROMOTION = {
    dim = 0.6,
    background = gray(0xFF),
    frame = gray(0x00),
    frame_width = 0.04,
}

-- Whose turn it is, in the corner where the coordinate strips meet: a ring when White moves,
-- a disc when Black does, and a symbol when the game is over. Sizes are shares of the corner.
Theme.STATUS = {
    color = gray(0x00),
    radius = 0.3,
    ring_width = 0.12,
    text_share = 0.8,
}

-- The strip with the last moves. text_share: text height as a share of the strip;
-- gap (between moves) and pad (at the ends).
Theme.NOTATION = {
    background = Theme.GRAY.surface,
    color = gray(0x00),
    text_share = 0.6,
    gap = 9,
    pad = 6,
}

-- Coordinate labels. share: text height as a share of the square; gutter_share: as a share of
-- the gutter, when there is one. file_corner and rank_corner: "top_left", "top_right",
-- "bottom_left" or "bottom_right" of their square.
Theme.LABEL = {
    share = 0.24,
    gutter_share = 0.8,
    on_gutter = gray(0x00),
    bold = true,
    on_light = gray(0x66),
    on_dark = gray(0xFF),
    file_corner = "bottom_right",
    rank_corner = "top_left",
}

-- How many pixels of this screen a design pixel takes.
function Theme.scale()
    return Layout.scaleFor(Screen:getWidth(), Screen:getHeight())
end

-- A size in design pixels, in pixels of this screen.
function Theme.px(size)
    return Layout.px(size, Theme.scale())
end

-- Font:getFace scales the size it gets with the screen; this asks for a size in pixels.
local function face_of_px(size_px)
    return Font:getFace("cfont", size_px * 100 / Screen:scaleBySize(100))
end

-- A text of a height in pixels, in the interface font. The caller frees it.
function Theme.text(text, size_px, color, bold)
    return TextWidget:new{
        text = text,
        face = face_of_px(math.max(6, size_px)),
        bold = bold,
        fgcolor = color,
    }
end

local plugin_dir

function Theme.setPluginDir(dir)
    plugin_dir = dir
end

-- Bitmaps for one square size. Changing the size frees the old ones.
local cache = { size = nil, pieces = {}, icons = {} }

function Theme.free()
    for _, group in ipairs({ cache.pieces, cache.icons }) do
        for key, bb in pairs(group) do
            bb:free()
            group[key] = nil
        end
    end
    cache.size = nil
end

local function use_size(size)
    if cache.size ~= size then
        Theme.free()
        cache.size = size
    end
end

-- The file of a piece, by its FEN letter.
local function piece_path(letter)
    local color = letter:match("%u") and "w" or "b"
    return string.format("%s/assets/pieces/merida/%s%s.svg", plugin_dir, color, letter:upper())
end

-- A bitmap from a group of the cache, rendered the first time it is asked for.
local function cached(group, key, path, side)
    local bb = group[key]
    if not bb then
        bb = RenderImage:renderSVGImageFile(path, side, side)
        group[key] = bb
    end
    return bb
end

-- The bitmap of a piece (a FEN letter) at a square size. NanoSVG gives straight alpha: blit it
-- with alphablitFrom.
function Theme.piece(letter, size)
    use_size(size)
    return cached(cache.pieces, letter, piece_path(letter), size)
end

-- Buttons whose icon is the file of another one.
local ICON_FILES = { clear = "reset" }

-- The icon of a button, side pixels wide.
function Theme.icon(name, side)
    local path = string.format("%s/assets/icons/%s.svg", plugin_dir, ICON_FILES[name] or name)
    return cached(cache.icons, name .. "@" .. side, path, side)
end

-- The alpha of a bitmap as an 8-bit mask, for colorblitFrom to paint it in any gray.
local function alpha_mask(image)
    local w, h = image:getWidth(), image:getHeight()
    local mask = Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8)
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            mask:setPixel(x, y, Blitbuffer.Color8(image:getPixel(x, y):getColor8A().alpha))
        end
    end
    return mask
end

-- The icon of a button as a mask, side pixels wide, to paint it in a gray of choice.
function Theme.iconMask(name, side)
    local key = "mask:" .. name .. "@" .. side
    if not cache.icons[key] then
        cache.icons[key] = alpha_mask(Theme.icon(name, side))
    end
    return cache.icons[key]
end

-- A piece drawn as the icon of a button.
function Theme.pieceIcon(letter, side)
    return cached(cache.icons, letter .. "@" .. side, piece_path(letter), side)
end

return Theme
