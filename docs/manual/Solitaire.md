# Solitaire

Veranda Solitaire is a collection of **card games for one player**, on
green felt, in black and white. The rules come from PySolFC. Version
1.0. GPL-3.0-or-later.

## Start it

Double-click **Solitaire** in `/VERANDA/APPS`. You need a mouse and at
least 512 KB.

## The games

**Game > Choose game**:

| Game | In short |
|---|---|
| Klondike | the classic. Draw 1 (or Draw 3 in Options), unlimited redeals. |
| FreeCell | "super moves" move several cards at once. Deal numbers are Microsoft's. |
| Spider (1 suit), (2 suits), (4 suits) | with one, two or four suits; in Spider (1 suit) a full suit goes home by itself |
| Golf | one round; queens may go on kings |
| Pyramid | three rounds; remove pairs that add up to 13, kings alone |
| Yukon | PySolFC's Yukon |
| Russian Solitaire | Yukon, built by suit |

## Play

- **Drag** a card, or a run from a card down. The stack nearest the
  card's corner takes it. A move the rules do not allow puts the cards
  back.
- **Click the stock** to deal, or to turn the waste over.
- In Golf, click a column to play its card. In Pyramid, click a free
  king to remove it.
- **Double-click** a card to send it to a foundation.
- Face-down cards turn up by themselves.
- **Options > Auto-drop** sends cards home by themselves.

When you win, the cards bounce off the foundations. A click or a key
shows "You won!" with your time, moves, and games won.

## Menus and keys

| Menu | Items |
|---|---|
| Solitaire | About Veranda Solitaire, the desk accessories |
| Game | New deal, Restart deal, Deal number..., Choose game, Statistics..., Quit |
| Edit | Undo, Redo |
| Options | Auto-drop, Draw 1 / Draw 3 (Klondike only) |

| Key | Action |
|---|---|
| Alt+N | a new deal |
| Alt+R | restart the deal |
| Alt+D | play a deal by its number (1 to 2147483647) |
| Alt+Z | undo |
| Alt+Y | redo |

Undo and redo go back as far as the deal, as far as memory allows.

## Deal numbers and statistics

- Every deal has a number. The status bar shows the game, the deal, the
  moves, the time, and the cards not yet home. Numbers below 32000 give
  the same deals as PySolFC.
- **Game > Statistics...** shows, for each game: played, won, the
  winning streak, the best streak, the best time and the fewest moves.
  They are saved in `/VERANDA/.SYSTEM/Veranda Solitaire Stats`, with the
  last game and the options.
