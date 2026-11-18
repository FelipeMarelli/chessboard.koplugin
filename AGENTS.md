# chessboard.koplugin

KOReader plugin: a chess board floating over the page of the book, for reading chess books on an e-reader (developed on a Kindle Paperwhite). Lua 5.1 / LuaJIT.

This file is the only versioned project document: it sets how the plugin is built and how to work on it. If there is a local `docs/` folder (not versioned), it holds the user stories, their status and working notes: read in `docs/stories.md` the initial context and **only** the story you were asked for, and check in its status table that the stories yours depends on are done. If they are not, don't start: say so.

## Guiding principle: pure logic apart from rendering

This is the most important rule. Everything else is subordinate to it.

- **Every decision is made in pure code.** Which moves are legal, which square is selected after a tap, where the window lands when released, which zone of the window got a tap, what each editor tool does: all of that lives in Lua modules without any KOReader `require` (folders `chess/` and `model/`).
- **The interface only translates and draws.** The modules in `ui/` turn a KOReader gesture into a call to the model and paint what the model says. They hold no conditions about rules, states or geometry.
- **Pure logic is tested; rendering is looked at.** Every public function in `chess/` and `model/` has automated tests in `spec/`, which run without the emulator. Screenshots serve only to check that the drawing looks right.
- **Test of the rule.** If checking a behavior requires opening the emulator, and that behavior is not purely visual, the logic is in the wrong place and must be moved to `model/`.
- **Sign of a violation.** An `if` in `ui/` that is not about how to draw something.

## How to work

- **One story per session.** Don't get ahead on other stories or add features nobody asked for.
- **Pure logic and its tests first, drawing after.**
- **Clean code, no repetition.** If a piece of code shows up twice, pull it out into a small function whose name says what it does. This also applies to the tests and to `selftest.lua`. Before each commit, reread what you wrote looking for repetition.
- **Respect the contracts** below. Functions can be added; if you need to change a signature that another module already uses, stop and ask.
- **Don't invent KOReader API.** Before using a function, look it up in `vendor/koreader-src/` and read how it is used.
- **Really run the tests** and paste the real output in your report. Don't say something passes if you didn't run it.
- **Look at the screenshots** the interface test leaves before calling a story done.
- Small commits on `main` (no branches per story), in English, in the imperative, with the story identifier at the start: `H07: select piece and show legal targets`. Before each commit the tests in `spec/` pass.
- A story does not touch files outside its scope except to fix a bug that blocks it; in that case the commit says so. A fixed bug comes with a test that reproduces it.

## Commands

With [Task](https://taskfile.dev) (`Taskfile.yml`; `task` lists them):

```sh
task test                  # logic tests; task test -- rules_spec.lua runs only that file
task test:perft            # full move counts (slow)
task emu BOOK=petroff      # emulator by hand, portrait; emu:h in landscape
task ui SCENARIO=h05       # interface test, portrait and landscape; ui:v and ui:h, just one
task ui:all                # every scenario in both orientations (slow)
task check                 # logic tests and every interface scenario
task shots                 # opens emu-data/chessboard/ with the report and the screenshots
```

`BOOK` is a path or part of the name of a book in `example-books/` (default `nunn`); `PAGE` is the page where the interface test starts (default 30). The `task` interface tests run without a window (`SDL_VIDEO_DRIVER=offscreen`); to see it, `SDL_VIDEO_DRIVER=wayland task ui SCENARIO=h05`. Without Task:

```sh
(cd vendor/koreader-emu/lib/koreader && ./luajit "$OLDPWD/spec/run.lua")
./run-emu.sh "$PWD/example-books/<book>"
CHESSBOARD_SELFTEST=1 CHESSBOARD_SCENARIO=h05 CHESSBOARD_PAGE=30 ./run-emu.sh "$PWD/example-books/<book>"
```

There is no `lua`, `luajit` or `busted` installed on the system: always use the emulator's `luajit`. The emulator window size is set with `EMULATE_READER_W`, `EMULATE_READER_H` and `EMULATE_READER_DPI` (default 632, 840 and 150). The board opens from the reader menu: Tools › More tools › "Chess board". Interface runs share `emu-data/`: run them one at a time.

The plugin is linked into the emulator with a symlink at `vendor/koreader-emu/lib/koreader/plugins/chessboard.koplugin`, so changes show up when the emulator restarts. `vendor/` holds KOReader v2026.07.1 for Linux x86_64 (`koreader-emu/`) and the KOReader sources (`koreader-src/`, `koreader-base-src/`), for reference only. None of it is versioned.

## Technical decisions

| No. | Decision | Reason |
|---|---|---|
| D1 | Pure Lua for KOReader's LuaJIT (Lua 5.1). No C modules or external dependencies. | It installs by copying a folder, on any device that runs KOReader. |
| D2 | Reference version: KOReader v2026.07.1, the one in the emulator. | It is what we test against. |
| D3 | The floating window is a view module (`ReaderView:registerViewModule`) with its own touch zone (`registerTouchZones`), not a widget shown with `UIManager:show`. `UIManager:show` is only for short modal dialogs. | A `UIManager` window blocks taps to the reader. Taps outside the window must reach the reader as always (pages, menus, links); gestures that start inside it never reach the reader. |
| D4 | All logic (chess, interaction, window geometry, editor, state) is pure Lua with tests. | It is tested without the emulator, and the rendering can change without touching behavior. |
| D4b | `chess/rules.lua` starts from `ink_knight/chess.lua` by Ink Knight (GPL-3.0, version 3 only), adapted to the contract below, with its rules and move-count tests adapted into `spec/`. | Rules already tested against reference counts. |
| D5 | The game model is a move tree, even though the interface shows a single line. | Variations later do not force a migration of saved data. |
| D6 | Positions are saved as FEN and moves in coordinate notation (`e2e4`, `e7e8q`). | Standard formats that engines and lichess understand. |
| D7 | Merida pieces from their SVGs, turned into bitmaps with `RenderImage:renderSVGImageFile` at square size. | Sharp at any window size. |
| D8 | Plain squares in two grays, no texture. | Clean, and it does not dither in 16 grays. |
| D9 | Pieces and board background are generated once per square size and kept in memory. | Scaling on every repaint is too slow for the Kindle. |
| D10 | Each book's state is saved in the document settings (`self.ui.doc_settings`), under a single key `chessboard`, with a schema version number. | It respects the user's metadata folder and travels with the book. |
| D11 | Code, comments and commit messages in English. Interface texts in English in the code, translatable, with a Spanish translation. | Convention of KOReader and its plugin catalog. |
| D12 | Automated tests for the logic; the interface is checked with synthetic taps and screenshots in the emulator. | |

## Licenses

The plugin is AGPL-3.0, the same as KOReader (`LICENSE`). Everything brought in (graphics, code) must be compatible with AGPL-3.0, and its origin and license are noted in the `README.md`. The published package includes a copy of `LICENSE`.

`chess/rules.lua` and the tests that come from Ink Knight (`spec/inkknight_rules_spec.lua`, `spec/perft_spec.lua`) stay under GPL-3.0, version 3 only; section 13 of both licenses allows combining them. Each one carries in its header its origin, the Beater Studios copyright notice and the date of our changes, and the GPL text goes in `chess/LICENSE-GPL-3.0`. Ink Knight's `NOTICE` (section 7(e)): do not use the names "Ink Knight" or "Beater Studios" in a way that looks like an official version. The positions in `spec/perft/` come from scalachess (MIT). Icons come only from Lucide (ISC).

Code can be brought from other plugins if its license is compatible and the maintainer approves it. Brought code carries in its header its origin, the commit, the original copyright and what was changed.

## Architecture

### Layers

Some modules are still planned: `ui/editor.lua` (today the editor is painted by `ui/window.lua`), `store.lua`, `model/library.lua` and `model/state.lua`.

```
DEPENDS ON KOREADER (no automated tests; checked with screenshots)

  main.lua            plugin: menu, life cycle, KOReader events
  ui/window.lua       paints the window; translates gestures into model calls
  ui/board.lua        paints board, pieces and marks
  ui/notation.lua     paints the strip of moves
  ui/editor.lua       paints the editor palette and tools
  ui/theme.lua        sizes, grays, piece and icon cache
  store.lua           reads and writes the document settings
  i18n.lua            translatable texts
  selftest.lua        interface test with synthetic taps

------------------------------------------------------------------------
PURE LUA (no KOReader; all with tests in spec/)

  model/session.lua   interaction with the board: selection, targets,
                      pending promotion, marks to show, active buttons
  model/notation.lua  the moves written as in a book
  model/editor.lua    editing session: tool, place, erase, turn,
                      castling inference, validation
  model/layout.lua    window geometry: place, size, limits, states,
                      portrait and landscape, button rows, touch zones
  model/library.lua   saved positions
  model/state.lua     full state of the book, to a plain table and back
  chess/game.lua      game: move tree and cursor
  chess/rules.lua     position, legal moves, FEN, notation
```

Dependency rules:

- Arrows only point down: `ui/` and `main.lua` use `model/`; `model/` uses `chess/`; `chess/` uses nothing.
- `chess/` and `model/` do not `require` any KOReader module, nor `ui/`, and do not touch files, the clock or the screen. They take numbers and tables and return numbers and tables; the date, the page and the screen size are passed as arguments. `spec/run.lua` checks this by loading them where KOReader `require`s fail.
- `model/layout.lua` works with rectangles as plain tables and gets the screen size and density as data. It does not know `Geom` or `Screen`.
- `model/session.lua` exposes what must be drawn as data; `ui/board.lua` walks that and paints.
- `store.lua` only carries the table that `model/state.lua` produces to the document settings and back. Validation and version migration are in `model/state.lua`.
- `main.lua` wires the pieces together and holds no chess, interaction or drawing logic.

### Contracts between modules

Common conventions:

- A square is a number from 1 to 64: a1 = 1, b1 = 2, …, h1 = 8, a2 = 9, …, h8 = 64 (e4 = 29). The name `"e4"` is a display matter (`rules.squareName`). A piece is a FEN letter: `"P"`, `"n"`. A color is `"w"` or `"b"`.
- A move is `{ from = 13, to = 29, promotion = nil | "q" | "r" | "b" | "n" }`. Moves returned by `chess/rules.lua` add `castle` (the rook's square) when castling.
- A rectangle is `{ x, y, w, h }` in whole pixels.
- Functions that can fail because of input data return `nil, "message"`. Those that change something return whether it changed.

**`chess/rules.lua`**

```lua
rules.START_FEN
rules.square(file, rank)      -- -> square | nil   (1 to 8)
rules.fileOf(sq)  rules.rankOf(sq)                -- -> 1..8
rules.squareName(sq)          -- -> "e4"
rules.squareFromName(name)    -- -> square | nil
rules.fromFen(fen, chess960)  -- -> position | nil, err
rules.toFen(position)         -- -> string
rules.pieceAt(position, sq)   -- -> letter | nil
rules.turn(position)          -- -> "w" | "b"
rules.kingSquare(position, color) -- -> square | nil
rules.legalMoves(position)    -- -> { move, ... }
rules.legalMovesFrom(position, sq) -- -> { move, ... }
rules.apply(position, move)   -- -> new position, legal move | nil, err   (does not modify the original)
rules.isCheck(position)       -- -> boolean
rules.status(position)        -- -> "ongoing" | "checkmate" | "stalemate"
rules.ending(position)        -- -> nil | "checkmate" | "stalemate" | "insufficient" | "fifty"
rules.san(position, move)     -- -> { piece = letter | nil, text = "bd7", promotion = letter | nil,
                              --      suffix = "+" | "#" | "" } | nil, err
rules.sanText(position, move) -- -> "Nbd7+" | nil, err
rules.moveToUci(move, position) -- -> "e2e4"
rules.parseUci(position, uci) -- -> move | nil   (does not check that it is legal)
rules.validate(position)      -- -> true | nil, reason   (reason in English, the i18n key)
rules.perft(position, depth)  -- -> number
```

A position is `{ board, turn, castling, chess960, passant, halfmove, fullmove }`, with `board` mapping square to letter, and is immutable. In `san`, the interface draws a figurine instead of each letter; the full notation is `piece .. text .. "=" .. promotion .. suffix`. The en passant square is recorded after a move only if some pawn can take, as in lichess.

**`chess/game.lua`**

```lua
game.new(start_fen)           -- -> game | nil, err   (no argument: starting position)
game:reset(start_fen)         -- -> true | nil, err   (if it fails, nothing changes)
game:position()
game:play(move)               -- -> true | nil, err   (replaces the continuation if it differs)
game:back()  game:forward()  game:toStart()  game:toEnd()   -- -> boolean
game:canBack()  game:canForward()
game:lastMove()               -- -> nil | { move, number = 12, color = "b", san = <rules.san> }
game:recentMoves(count)       -- the last ones up to the cursor, oldest first
game:nextMoves(count)         -- those of the line after the cursor
game:startFen()
game:serialize()              -- -> { start = fen, moves = { "e2e4", ... }, cursor = 2 }
game.deserialize(table)       -- -> game | nil, err
```

The starting position must pass `rules.validate`. The cursor is the number of moves made from the start. Variations can be added as new fields without changing these.

**`model/layout.lua`**

```lua
layout.new{ screen_w, screen_h, px_per_mm, sizes }
layout:setScreen(screen_w, screen_h)          -- rotation; keeps the window inside
layout:rects()      -- -> { window, board, buttons, strip, notation?, status? }
layout:squareRect(sq, flipped)
layout:hit(x, y, flipped)  -- -> nil (outside) | { zone = "board" | "button" | "notation" | "strip",
                           --                    square, button = id, opens = row name }
layout:moveTo(x, y)        layout:resize(steps)   layout:canResize(steps)
layout:minimize()  layout:maximize()  layout:restore()  layout:mode()
layout:setOpen(boolean)    layout:isOpen()
layout:buttons()           layout:button(id)  layout:buttonRect(id)
layout:showRow(name)       layout:shownRow()
layout:startDrag(x, y, flipped, locked)       layout:pressedButton()   layout:isHidden()
layout:squareSize()        layout.labelSquares(flipped)
layout:dirtyRect(previous_rects)
layout:serialize()         layout.deserialize(table, screen)
```

- `sizes` carries millimeters defined in `ui/theme.lua`: `row`, `button`, `border`, `margin`, `min_square`, `size_step` and `notation` (height of the move strip; 0 or nothing, no strip).
- The window shows one button row at a time, by name (`"main"`, `"size"`, the editor's). A button can open another row instead of acting (`opens`); `"back"` opens the main one; opening or closing the window goes back to the main one. To add a row, declare it in `model/layout.lua` with the button that opens it. A row can have top buttons, in the place of the move strip.
- Buttons are laid out like a CSS flex row: if they don't fit at their size, they all shrink equally.
- Main row, from the left: eye (while the finger is on it the window is hidden: `isHidden`), move (the only place from which a drag moves the window), flip, size, reset (trash can) and edit; on the right, backward, forward and close. Held down, the arrows go to the start and the end of the line.
- A button that would do nothing comes with `enabled = false`, and `hit` treats it like the row between buttons (`{ zone = "button" }` without `button`). `hit` counts the thin window border as part of the neighboring zone; with the window closed it returns `nil`.

**`model/session.lua`**

```lua
session.new(game)
session:tapSquare(sq)      -- -> { changed, played = move | nil, needs_promotion }
session:choosePromotion(letter)   session:cancelPromotion()   session:isPromoting()
session:navigate("back" | "forward" | "start" | "end")   -- -> whether the position changed
session:reset()
session:startEdit()  session:finishEdit()  session:isEditing()
session:clearBoard()  session:toggleColor()  session:choosePiece(letter)  session:chooseEraser()
session:flip()             session:flipped()
session:view()
   -- { squares = { [29] = { piece = "P", light = false, marks = { selected, target, capture, check } } },
   --   flipped, turn = "w", status = "ongoing", last_move = <game:lastMove()>,
   --   notation = { moves = { ... }, current = 3, numbered = true },
   --   promotion = nil | { square, color, choices = { { square = 61, piece = "Q" }, ... } },
   --   buttons = { backward = true, forward = false, ... } }
```

`navigate` clears the selection and any pending promotion. While a promotion is pending, the choices are queen, knight, rook and bishop, in the file of the promotion square toward the center; a tap elsewhere (or outside the board) cancels it, and meanwhile the window does not move. The editor edits the starting position: it starts from the visible position; its color button sets both the piece color and the side to move; `clearBoard` sets the starting position and, if already there, empties the board; `finishEdit` starts a new game only if the position changed and is valid, otherwise the game and its line stay. While editing, the notation carries no moves.

**`model/editor.lua`**

```lua
editor.new(position)
editor:setTool(letter | "erase")   editor:tool()   editor:tapSquare(sq)
editor:clear()  editor:setStart()  editor:isStart()  editor:isChanged()
editor:setTurn(color)      editor:turn()
editor:position()          -- the position being built, to draw it
editor:result()            -- -> position | nil, reason
```

`result` carries no en passant square, starts at move 1 and has every castling right whose king and rook are on their starting squares.

**`model/notation.lua`**

```lua
notation.parts(moves, numbered)   -- -> { { kind = "text", text = "30." } | { kind = "figurine", piece = "B" } | { kind = "gap" }, ... }
notation.fit(moves, numbered, width_of, room, current)   -- parts that fit; those of move current carry current = true
```

White's moves carry a number and a period; Black's only if first shown, with an ellipsis; without `numbered` (game from an edited position), no numbers. `width_of(part)` is supplied by `ui/`. The strip shows the whole line with the current move in bold; it ends with the end of the line while the current move fits.

**`model/library.lua`** and **`model/state.lua`** (planned)

```lua
library.new()   library:add(name, fen, page, timestamp)   library:rename(id, name)
library:remove(id)   library:list()   -- most recent first
state.new()   state.serialize(state)   state.deserialize(table)   -- -> state, warning | nil
```

### Folder layout

```
chessboard.koplugin/
  _meta.lua  main.lua  i18n.lua  selftest.lua
  chess/     rules.lua  game.lua  LICENSE-GPL-3.0
  model/     session.lua  editor.lua  notation.lua  layout.lua
  ui/        window.lua  board.lua  notation.lua  theme.lua
  assets/    pieces/merida/*.svg   icons/*.svg
  l10n/      es.lua
spec/        run.lua  helper.lua  *_spec.lua  perft/
```

`spec/` stays outside the plugin folder so it does not go into the installed package. Storefront (and AppStore) install only the folder holding the shallowest `_meta.lua` of the repository zip, so this layout is published without building a zip by hand. Do not create any other `_meta.lua` outside `chessboard.koplugin/`. To appear in Storefront the repository needs the `.koplugin` name or the `koreader-plugin` topic, a non-draft Release with a tag like `v1.0`, a `version` in `_meta.lua` and a `README.md`.

### State

One state object per open book; everything drawn comes from it.

| Part | Content | Saved |
|---|---|---|
| Game | Starting position (FEN), move tree, cursor | Yes |
| Board | Orientation | Yes |
| Window | Open or closed; normal, minimized or maximized; place and size for portrait and for landscape, as fractions of the screen | Yes |
| Saved positions | Name, FEN, page and date | Yes |
| Interaction | Selection, promotion picker, drag in progress, editing session | No |

Persistence: read on `onReaderReady`, written on `onSaveSettings` and on close, never on every move. If the data is not understood, the default state is used, a warning is logged, and what was saved is not erased until the next write. Preferences that do not belong to a book go in a file of their own in KOReader's settings folder, never in its global settings.

### Flow of a tap

1. The plugin's touch zone gets the gesture before the reader's.
2. If the window is closed or the gesture starts outside it, the handler returns `false` and the reader processes it.
3. If it starts inside, `ui/window.lua` asks `model/layout.lua` which zone it belongs to, and returns `true`.
4. `ui/` calls the model operation (for example `session:tapSquare(29)`). The model changes the state and returns what changed. `ui/` decides nothing.
5. A repaint of the affected region is requested with `UIManager:setDirty`; `model/layout.lua` computes the region.
6. KOReader calls `paintTo`, which draws the window from what the model exposes.

The only drag, moving the window, starts with `touch` and follows with `pan` and `pan_release`; while it lasts the whole gesture is captured. Size changes with buttons, not dragging.

### Drawing and refresh

- `paintTo` is a function of the state: it changes nothing and gives the same result if called twice.
- One repaint per user action. No timers to animate.
- Only the region that changed is marked dirty: the window, or the union of the old and new regions when the window moves, resizes or changes state. Switching button rows repaints only the row.
- Refresh `ui` (no flash) for normal use, and `flashui` on the window when it covers new text (opening and enlarging): on the Kindle's MTK screen, `ui` let the text show through the gray squares.
- During a drag the window jumps to the new place on release, like KOReader's `MovableContainer`; it is not drawn along the way (on the Kindle, an outline following the finger lagged about 30 s). Only the move button is marked, once, as soon as the finger lands: painted directly on screen with a `fast` refresh and `forceRePaint`, like `Button:_doFeedbackHighlight`. KOReader only sends the first `pan` after about 35 dp of movement.
- Sizes in millimeters in `ui/theme.lua`, converted with the screen density. No fixed pixels outside that file.
- Cache bitmaps are freed when the square size changes and when the book is closed.

### Board on electronic ink

- The Kindle shows 16 grays. Tones of squares, marks and buttons are named constants in `ui/theme.lua`, provisional until tested on the device.
- The marks differ by shape as well as tone: thick dark border on the selected piece, dot on an empty target, corners on a capture, a disc behind the king in check. The last move is not marked on the board; the move strip shows it in bold.
- Whose turn it is, mate ("#") and stalemate ("½") go in the corner where the coordinate strips meet.

### Translation and errors

- No visible text is written loose: all go through `i18n.lua`, which looks it up in `l10n/<language>.lua`, then KOReader's `gettext`, then leaves the English. Move notation uses figurines and is not translated.
- `chess/` does not throw on invalid input (a broken FEN, an illegal move): it returns `nil` and a message. Exceptions are for programming errors.
- A plugin failure must not prevent reading: event handlers log the error with `logger`, close the window and let the reader go on.
- Messages to the user are one line long and say what to do.

## Code style

- Lua 5.1 / LuaJIT. 4-space indentation, no tabs. Lines up to 100 columns.
- Everything `local`; no new globals. One module per file, which returns a table. `require`s at the top, in alphabetical order.
- `PascalCase` for classes and modules, `camelCase` for methods, `snake_case` for locals and fields, `UPPERCASE` for constants.
- Interface classes with KOReader's `:extend{}` / `:new{}`; `chess/` and `model/` use plain tables and functions.
- No magic numbers: sizes and grays in `ui/theme.lua`; chess values as named constants.
- Comments in English, only for the why or a non-obvious KOReader behavior. Each file starts with a line that says what it does.
- Short functions. A drawing function longer than a screen is split.
- `luacheck` with KOReader's configuration (`vendor/koreader-src/.luacheckrc`), if installed.

## Interface style

- Icons instead of text on buttons, from Lucide only: simple stroke, single tone.
- Surfaces of 7 mm or more for everything tapped, squares of 4 mm or more; when a row does not fit, its buttons shrink (minimum square 4.2 mm).
- Thin borders, no shadows, gradients or textures.
- A disabled button looks lighter (60 %) and does not respond.
- Dialogs only to ask for a name or to confirm something that deletes data.
- Texts in KOReader's interface font.

## Tests

- **Logic.** `spec/*_spec.lua`, run by our own minimal runner `spec/run.lua`. Every public function in `chess/` and `model/` has tests, and every acceptance criterion that describes a behavior has at least one.
- **Interface.** `selftest.lua` (`CHESSBOARD_SELFTEST=1`) has named scenarios (`CHESSBOARD_SCENARIO`), one or more per story. Each injects gestures, checks the resulting state and leaves `selftest.txt` and screenshots `<scenario>_<v|h>_NN_<step>.png` in `emu-data/chessboard/`. The test does not judge how things look: look at the screenshots.
- **Sizes.** 632×840 and 840×632 at 150 dpi, with the Nunn EPUB only. A PDF run is added only if the change touches document pagination.
- **Real Kindle.** What can only be checked on the device (grays, ghosting, speed) is reported as not verified, never as done.

## Don't touch

- The sample books in `example-books/` (`*.pdf`, `*.epub`, `*.djvu`). They are not versioned or modified.
- `vendor/`: reference only.
- `LICENSE`.
- The acceptance criteria of the stories. If one looks wrong or impossible, stop and ask.

## When to stop and ask the maintainer

- Something that affects what the user sees or the format of saved data and is not decided here or in the story.
- An acceptance criterion you can't meet or verify.
- Third-party graphics or code whose license is not clearly compatible with AGPL-3.0.
- A failing test you don't understand. Don't delete it, skip it or change the expected value to make it pass.

## When a story is done

1. Every test in `spec/` passes, not just the new ones.
2. The interface test passes in portrait (632×840) and landscape (`EMULATE_READER_W=840 EMULATE_READER_H=632`).
3. If there are local docs, mark the story in the status table of `docs/stories.md` and update `docs/development.md`.
4. If what the user sees changed, update the `README.md` and the `version` in `_meta.lua`.
5. Report: what you did, the test output, and what was left unverified.
