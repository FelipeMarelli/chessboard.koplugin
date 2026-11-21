# Spike: split screen, board on one half and the book on the other

Date: 2026-11-21. Emulator only (KOReader v2026.07.1), not tried on the Kindle.

**Result:** it works for EPUB and PDF, in portrait and landscape, as long as the reader's own view
is shrunk to its half, the same way KOReader handles a window resize or rotation. Adding the board's
size to the EPUB page margin does not work.

## Setup

- Books: Nunn's *Chess Endings* (EPUB) and *The Petroff* (PDF), page 30.
- Sizes: 632×840 and 840×632 at 150 dpi.
- Portrait: the board fills the bottom half. Landscape: it fills the right half. Either way the
  reader keeps the top left corner of the screen, so its own coordinates do not change.
- The window takes the biggest square size that fits its half and is centred in it. The rest of the
  half is painted white before the window, so no page shows around it.
- A tap at 90 % of the width, halfway down the book half, turns the page.

The code is in `split-screen.patch` (only `selftest.lua`, nothing of it is meant to be kept). It adds
two self-test scenarios:

```sh
git apply spikes/split-screen.patch
task ui SCENARIO=split BOOK=petroff                                   # checks and screenshots
SPIKE_SCROLL=0 task ui SCENARIO=split BOOK=petroff                    # PDF in page mode
SPIKE_EPUB=dimen task ui SCENARIO=split BOOK=nunn                     # EPUB, the way that works
SDL_VIDEO_DRIVER=wayland task ui:v SCENARIO=splitlive BOOK=nunn       # enters the split and stays
git apply -R spikes/split-screen.patch
```

- `split` turns the page four times, checks three of the advances and restores the full screen.
  The page turns are only checked for PDF; for EPUB, look at the screenshots.
- Without `SPIKE_EPUB=dimen`, `split` uses the EPUB margin way, the one that fails.
- `splitlive` uses the working way for both formats and leaves the emulator open. Closing the
  board leaves its half blank, and there is no way back to the full screen without reopening the
  book.

## EPUB

### Extra page margin: does not work

The board's size was added to the margin on the board's edge, only where crengine gets it:
`document.setPageMargins` was wrapped on the document instance, then `SetPageMargins` was sent with
the book's own margins. This is what `ReaderTypeset:onSetPageMargins` does with the status bar
height.

crengine gets a bottom margin of 453 px in portrait (board 420, status bar 17, book margin 16), but
the text still runs down to y = 419. The last line is cut by the board and is not repeated on the
next page, so it is lost. Why crengine ignores part of a large margin was not found; its sources are
not in `vendor/`.

### Smaller crengine page: works

crengine's page is set to the reader half, with the same steps `ReaderRolling:onSetDimensions` takes
on a resize:

1. `document:enableInternalHistory(true)`.
2. `document:setViewDimen(half)`.
3. `view:onSetDimensions(half)` and `view.footer:onSetDimensions()`.
4. `rolling:onUpdatePos()`.
5. `document:enableInternalHistory(false)` and `rolling:onRedrawCurrentView()`.

The `SetDimensions` event cannot be used as it is, because `ReaderRolling` handles it by setting
crengine back to the full screen.

The text reflows cleanly into its half, and no line is lost between pages: one page ends in
"…and then only in" and the next starts with "very favourable situations.". Landscape gives a
narrow but readable column. Restoring the full screen reflows the book back.

## PDF

The view is shrunk with `SetDimensions(half)`, followed by `InitScrollPageStates`. KOReader sends
the same pair when the screen rotates (`ReaderView:onSetRotationMode`).

Without `InitScrollPageStates`, continuous (scroll) mode kept the page states made for the full
screen:
- In portrait each tap moved one whole screen (≈ 790 px) while only 420 px were shown, so half of
  every page was skipped.
- Going back to the full screen left half of it blank.

Landscape seemed fine only because the split there does not change the view's height.

Advance per tap with `InitScrollPageStates`. Each advance is no more than the visible half, so nothing
is skipped:

| Mode | Orientation | Advance per tap | Book half |
|---|---|---|---|
| Continuous | portrait | 388 px | 420 px |
| Continuous | landscape | 601 px | 632 px |
| Page | portrait | 269, 202, 420 px | 420 px |
| Page | landscape | 592 px | 632 px |

- In page mode, the short step (202 px) is the end of the page, which KOReader aligns to its bottom.
  The next tap goes on to the next page.
- The screenshots agree: after a tap, the line that was cut by the board shows first, and page 29
  is read in halves before page 30.
- After leaving the split, the view is the full screen again (840×632 or 632×840).

## Open issues

- **Status bar:** it is still drawn at the bottom of the whole screen. In portrait it is hidden
  under the board; in landscape it is cut at the middle. It has to move to the book half or be
  hidden while split.
- **PDF zoom in landscape:** with "fit page" zoom the page is small in a half that is 420 px wide;
  "fit width" reads well. Whether the split should change the zoom is undecided.
- **Not checked:**
  - Highlights, links and the dictionary inside a shrunk view.
  - Rotating the screen while split.
  - DjVu.
  - The Kindle itself: refresh, ghosting and speed.

## Pitfalls met

- `SetScrollMode` is saved in the book's settings in `emu-data/`, so a run in page mode leaves the
  next run in page mode too. The spike sets the mode both ways when `SPIKE_SCROLL` is given.
- Screenshots are named by scenario and orientation, not by book: running EPUB and PDF one after the
  other overwrites the first ones. Copy them out between runs.

## Toward a story

- A new window state, "split", next to normal, minimized and maximized. While split, the window
  fills a fixed half and does not move.
- `model/layout.lua` would give both halves (board and book) as plain rectangles, with tests;
  `main.lua` would only hand the book's rectangle to KOReader, using the EPUB steps above or
  `SetDimensions` plus `InitScrollPageStates` for PDF.
- To decide with the maintainer:
  - How the split is turned on: a button in the size row, or a menu entry.
  - Which half the board takes in each orientation.
  - Whether the split is saved per book with the rest of the window state.
  - What happens to the status bar.
