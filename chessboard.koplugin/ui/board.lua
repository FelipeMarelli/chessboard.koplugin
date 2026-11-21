-- Paints the board: squares, marks, coordinate labels, pieces, whose turn it is and the promotion
-- selector, from the session view.
local Kit = require("ui/kit")
local Rect = require("model/rect")
local Rules = require("chess/rules")
local Theme = require("ui/theme")

local Board = {}

local function square_color(info)
    local gray = Theme.GRAY
    return info.light and gray.light_square or gray.dark_square
end

local function paint_squares(bb, layout, view)
    for sq = 1, 64 do
        local r = layout:squareRect(sq, view.flipped)
        Kit.fill(bb, r, square_color(view.squares[sq]))
    end
end

-- A part of a length in pixels, at least one.
local function share(length, part)
    return math.max(1, math.floor(length * part + 0.5))
end

-- A right triangle in each corner of a square, legs along its sides.
local function paint_corners(bb, r, leg, color)
    for i = 0, leg - 1 do
        local w = leg - i
        local top, bottom = r.y + i, r.y + r.h - 1 - i
        bb:paintRect(r.x, top, w, 1, color)
        bb:paintRect(r.x + r.w - w, top, w, 1, color)
        bb:paintRect(r.x, bottom, w, 1, color)
        bb:paintRect(r.x + r.w - w, bottom, w, 1, color)
    end
end

-- How each mark is drawn on a square of side s, in the order they are drawn.
local MARKS = {
    { name = "check", paint = function(bb, r, s, m)
        Kit.disc(bb, r, share(s, m.check_radius), m.check)
    end },
    { name = "selected", paint = function(bb, r, s, m)
        bb:paintInnerBorder(r.x, r.y, r.w, r.h, share(s, m.selected_width), m.selected)
    end },
    { name = "target", paint = function(bb, r, s, m)
        Kit.disc(bb, r, share(s, m.target_radius), m.target)
    end },
    { name = "capture", paint = function(bb, r, s, m)
        paint_corners(bb, r, share(s, m.capture_leg), m.capture)
    end },
}

local function paint_marks(bb, layout, view)
    local s = layout:squareSize()
    for sq = 1, 64 do
        local marks = view.squares[sq].marks
        for _, mark in ipairs(MARKS) do
            if marks[mark.name] then
                mark.paint(bb, layout:squareRect(sq, view.flipped), s, Theme.MARK)
            end
        end
    end
end

-- Where a text of a size goes in a corner of a square.
local CORNERS = {
    top_left = function(r, size, pad) return r.x + pad, r.y end,
    top_right = function(r, size, pad) return r.x + r.w - size.w - pad, r.y end,
    bottom_left = function(r, size, pad) return r.x + pad, r.y + r.h - size.h end,
    bottom_right = function(r, size, pad) return r.x + r.w - size.w - pad, r.y + r.h - size.h end,
}

-- Labels go in a corner of their square, or centred in the gutters when the layout has them.
local function paint_labels(bb, layout, view)
    local style = Theme.LABEL
    local gutters = layout:rects().files ~= nil
    local s = gutters and layout:rects().files.h or layout:squareSize()
    local size_px = math.floor(s * (gutters and style.gutter_share or style.share))
    local pad = math.max(1, math.floor(s / 20))
    for _, label in ipairs(layout:labels(view.flipped)) do
        local name = Rules.squareName(label.square)
        local is_file = label.kind == "file"
        local color = view.squares[label.square].light and style.on_light or style.on_dark
        local text = Theme.text(is_file and name:sub(1, 1) or name:sub(2, 2), size_px,
            gutters and style.on_gutter or color, style.bold)
        if gutters then
            local size = text:getSize()
            text:paintTo(bb, Rect.centred(label.rect, size.w, size.h))
        else
            local corner = CORNERS[is_file and style.file_corner or style.rank_corner]
            text:paintTo(bb, corner(label.rect, text:getSize(), pad))
        end
        text:free()
    end
end

local function paint_piece(bb, piece, r)
    Kit.bitmap(bb, Theme.piece(piece, r.w), r)
end

local function paint_pieces(bb, layout, view)
    for sq = 1, 64 do
        local piece = view.squares[sq].piece
        if piece then
            paint_piece(bb, piece, layout:squareRect(sq, view.flipped))
        end
    end
end

-- While a promotion waits for its piece: the board lightened, and the pieces to choose on white
-- squares with a frame.
local function paint_promotion(bb, layout, view)
    if not view.promotion then
        return
    end
    local style = Theme.PROMOTION
    local board = layout:rects().board
    bb:lightenRect(board.x, board.y, board.w, board.h, style.dim)
    local frame = share(layout:squareSize(), style.frame_width)
    for _, choice in ipairs(view.promotion.choices) do
        local r = layout:squareRect(choice.square, view.flipped)
        Kit.fill(bb, r, style.background)
        bb:paintInnerBorder(r.x, r.y, r.w, r.h, frame, style.frame)
        paint_piece(bb, choice.piece, r)
    end
end

-- The symbol shown instead of the turn when the game is over.
local ENDINGS = { checkmate = "#", stalemate = "½" }

-- In the corner where the coordinate strips meet: a ring when White moves, a disc when Black
-- does, or the symbol of how the game ended.
local function paint_status(bb, layout, view)
    local r = layout:rects().status
    if not r then
        return
    end
    local style = Theme.STATUS
    local ending = ENDINGS[view.status]
    if ending then
        Kit.text(bb, r, ending, math.floor(r.h * style.text_share), style.color, true)
    else
        local radius = share(r.h, style.radius)
        Kit.disc(bb, r, radius, style.color,
            view.turn == "w" and share(r.h, style.ring_width) or radius)
    end
end

function Board.paint(bb, layout, view)
    paint_squares(bb, layout, view)
    paint_marks(bb, layout, view)
    paint_labels(bb, layout, view)
    paint_pieces(bb, layout, view)
    paint_status(bb, layout, view)
    paint_promotion(bb, layout, view)
end

return Board
