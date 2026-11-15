-- Paints the board: squares, coordinate labels and pieces, from the session view.
local Font = require("ui/font")
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

local function centred(r, size)
    return r.x + math.floor((r.w - size.w) / 2), r.y + math.floor((r.h - size.h) / 2)
end

-- Labels go in a corner of their square, or centred in the gutters when the layout has them.
local function paint_labels(bb, layout, view)
    local style = Theme.LABEL
    local gutters = layout:rects().files ~= nil
    local s = gutters and layout:rects().files.h or layout:squareSize()
    local share = gutters and style.gutter_share or style.share
    local face = face_of_px(math.max(6, math.floor(s * share)))
    local pad = math.max(1, math.floor(s / 20))
    for _, label in ipairs(layout:labels(view.flipped)) do
        local name = Rules.squareName(label.square)
        local is_file = label.kind == "file"
        local color = view.squares[label.square].light and style.on_light or style.on_dark
        local text = TextWidget:new{
            text = is_file and name:sub(1, 1) or name:sub(2, 2),
            face = face,
            bold = style.bold,
            fgcolor = gutters and style.on_gutter or color,
        }
        if gutters then
            text:paintTo(bb, centred(label.rect, text:getSize()))
        else
            local corner = CORNERS[is_file and style.file_corner or style.rank_corner]
            text:paintTo(bb, corner(label.rect, text:getSize(), pad))
        end
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
