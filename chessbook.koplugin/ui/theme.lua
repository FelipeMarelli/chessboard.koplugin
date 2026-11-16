-- Sizes, grays and the cache of bitmaps the window is drawn with.
--
-- Sizes are in millimetres and grays are values from 0 (black) to 255 (white). They are first
-- guesses, to be tuned on the Kindle.
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local RenderImage = require("ui/renderimage")

local Screen = Device.screen

local Theme = {}

-- Window geometry, for model/layout.lua.
Theme.SIZES = {
    row = 7,        -- height of the button row under the board
    button = 7,     -- button width
    border = 0.3,   -- window frame
    margin = 2,     -- gap to the screen edge
    min_square = 4.2,
    size_step = 1,  -- how much the side of a square changes with each tap on smaller or bigger
    gutter = 2.5,   -- strips for the coordinates outside the board; 0 puts them on the squares
}

Theme.ICON = 5          -- icon side, mm

-- A disabled button is drawn over with white by this share, so that its icon looks lighter.
Theme.DISABLED = 0.6

-- The border that marks a button held down, in mm: as thick as the strokes of the icons, inside
-- the button by inset, with rounded corners like theirs.
Theme.PRESSED = { width = 0.4, inset = 0.5, radius = 1.2 }

local function gray(value)
    return Blitbuffer.Color8(value)
end

Theme.GRAY = {
    frame = gray(0x00),
    row = gray(0xFF),
    light_square = gray(0xEE),
    dark_square = gray(0xAA),
    gutter = gray(0xFF),
}

-- Marks on the squares, in the manner of lichess. Sizes are shares of the square side.
-- They differ in shape: a thin gray frame on the two squares of the last move, a thick dark one
-- for the selected piece, a dot for a move to an empty square, corners for a capture and a disc
-- behind a king in check. The last move is not a tint: on e-ink a shade darker than the square
-- hardly showed. Chosen by Felipe ("E" of a comparison sheet), made a little lighter.
Theme.MARK = {
    last_move = gray(0x66),
    last_move_width = 0.04,
    selected = gray(0x33),
    selected_width = 0.08,
    target = gray(0x55),
    target_radius = 0.15,
    capture = gray(0x55),
    capture_leg = 0.28,
    check = gray(0x77),
    check_radius = 0.48,
}

-- Whose turn it is, in the corner where the coordinate strips meet: a ring when White moves,
-- a disc when Black does, and a symbol when the game is over. Sizes are shares of the corner.
Theme.STATUS = {
    color = gray(0x00),
    radius = 0.3,
    ring_width = 0.12,
    text_share = 0.8,
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

function Theme.pxPerMm()
    return Screen:getDPI() / 25.4
end

function Theme.px(mm)
    return math.max(1, math.floor(mm * Theme.pxPerMm() + 0.5))
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

-- The icon of a button, side pixels wide (Theme.ICON when not given).
function Theme.icon(name, side)
    side = side or Theme.px(Theme.ICON)
    local path = string.format("%s/assets/icons/%s.svg", plugin_dir, ICON_FILES[name] or name)
    return cached(cache.icons, name .. "@" .. side, path, side)
end

-- A piece drawn as the icon of a button.
function Theme.pieceIcon(letter, side)
    return cached(cache.icons, letter .. "@" .. side, piece_path(letter), side)
end

return Theme
