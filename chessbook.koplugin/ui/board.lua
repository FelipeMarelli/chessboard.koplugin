-- Paints the board: squares, coordinate labels and pieces, from the session view.
local Font = require("ui/font")
local Layout = require("model/layout")
local Rules = require("chess/rules")
local Screen = require("device").screen
local TextWidget = require("ui/widget/textwidget")
local Theme = require("ui/theme")

local Board = {}

local function paint_squares(bb, layout, view)
    local gray = Theme.GRAY
    for sq = 1, 64 do
        local r = layout:squareRect(sq, view.flipped)
        local color = view.squares[sq].light and gray.light_square or gray.dark_square
        bb:paintRect(r.x, r.y, r.w, r.h, color)
    end
end

-- Font:getFace scales the size it gets with the screen; this asks for a size in pixels.
local function face_of_px(size_px)
    return Font:getFace("cfont", size_px * 100 / Screen:scaleBySize(100))
end

-- Where a text of a size goes in a corner of a square.
local CORNERS = {
    top_left = function(r, size, pad) return r.x + pad, r.y end,
    top_right = function(r, size, pad) return r.x + r.w - size.w - pad, r.y end,
    bottom_left = function(r, size, pad) return r.x + pad, r.y + r.h - size.h end,
    bottom_right = function(r, size, pad) return r.x + r.w - size.w - pad, r.y + r.h - size.h end,
}

local function paint_labels(bb, layout, view)
    local style = Theme.LABEL
    local s = layout:squareSize()
    local face = face_of_px(math.max(6, math.floor(s * style.share)))
    local pad = math.max(1, math.floor(s / 20))
    for _, label in ipairs(Layout.labelSquares(view.flipped)) do
        local r = layout:squareRect(label.square, view.flipped)
        local name = Rules.squareName(label.square)
        local is_file = label.kind == "file"
        local text = TextWidget:new{
            text = is_file and name:sub(1, 1) or name:sub(2, 2),
            face = face,
            bold = style.bold,
            fgcolor = view.squares[label.square].light and style.on_light or style.on_dark,
        }
        local corner = CORNERS[is_file and style.file_corner or style.rank_corner]
        text:paintTo(bb, corner(r, text:getSize(), pad))
        text:free()
    end
end

local function paint_pieces(bb, layout, view)
    local s = layout:squareSize()
    for sq = 1, 64 do
        local piece = view.squares[sq].piece
        if piece then
            local r = layout:squareRect(sq, view.flipped)
            local image = Theme.piece(piece, s)
            bb:alphablitFrom(image, r.x, r.y, 0, 0, image:getWidth(), image:getHeight())
        end
    end
end

function Board.paint(bb, layout, view)
    paint_squares(bb, layout, view)
    paint_labels(bb, layout, view)
    paint_pieces(bb, layout, view)
end

return Board
