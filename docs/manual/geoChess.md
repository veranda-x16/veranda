# geoChess

geoChess is a **chess game** against the computer. It was written for
GEOS 64 and 128 by **Scott Hutter** (2023,
[github.com/geos64128/geochess](https://github.com/geos64128/geochess)),
and ported to Veranda at 640 x 480. Its chess engine is derived from
**BMCP** by **Maksim Korzh**, which is based on ideas from **micro-Max**
by **H.G. Muller**.

## Start it

Double-click **geoChess** in `/VERANDA/APPS`.

## Play

- You play **White**; the computer plays Black.
- **Click a piece**, then **click the square** to move it to. Click the
  selected piece again to cancel.
- The status bar says "Your move.", "Thinking..." while the computer
  thinks, "Illegal move." for a move the rules do not allow, and the end
  of the game: "White is mated.", "Black is mated." or "Stalemate.".
- A bell sounds when the computer has moved and it is your turn.
- Castling, en passant and pawn promotion work.
- **The move log** at the right lists the game, a row per move.

## Menus

| Menu | Items |
|---|---|
| geoChess | About geoChess, the desk accessories, Quit |
| File | New game, Open game..., Save game... |
| Options | Colour board (a green board; on at first) |

## Saving games

**File > Save game...** saves the game in Veranda's Save box (long names
up to 59 characters; the type "Saved games"). **File > Open game...**
opens one. The format is the same as on GEOS 64. After opening a saved
game, the move log shows only the last moves (the file keeps the last
eleven).

## Limits

- A pawn is always promoted to a queen.
- Draws by repetition, by the fifty-move rule and by too little material
  are not detected.
- You cannot switch sides or take back a move.

## Credits and terms

geoChess is by Scott Hutter, with contributions from the authors in its
repository's history. His source says: *"You are free to modify this
code as desired, as long as original author credit is mentioned for both
the GEOS code and the included AI engines."* The original repository has
no licence file; that permission is its only statement. The engine's
header carries Maksim Korzh's notice (the WTFPL, version 2). The
Veranda port is kept with geoChess, outside Veranda's MIT tree. See
[Licences](Licences.md).
